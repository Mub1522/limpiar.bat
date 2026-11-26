# Historial de ejecuciones: una linea por limpieza en historial.csv (junto a limpiar.bat).
# Sirve para comparar con la vez anterior en el resumen.
# Se carga con dot-sourcing desde limpiar.ps1.
#
# Los numeros se guardan con punto decimal (cultura invariante) y el separador es ';':
# en esta configuracion regional la coma es el separador decimal y romperia el CSV.

$script:culturaHistorial = [Globalization.CultureInfo]::InvariantCulture
$script:maxHistorial = 200   # se conservan las ultimas N ejecuciones

# Devuelve la ultima ejecucion registrada, o $null si no hay ninguna (o el archivo no se puede leer)
function Get-UltimaEjecucion($ruta) {
    if (-not (Test-Path $ruta)) { return $null }
    try {
        $filas = @(Import-Csv $ruta -Delimiter ';')
        if (-not $filas) { return $null }
        $u = $filas[-1]
        [pscustomobject]@{
            Fecha       = [datetime]::ParseExact($u.Fecha, 'yyyy-MM-dd HH:mm:ss', $script:culturaHistorial)
            LiberadoMB  = [double]::Parse($u.LiberadoMB, $script:culturaHistorial)
            LibreFinGB  = [double]::Parse($u.LibreFinGB, $script:culturaHistorial)
            Avisos      = [int]$u.Avisos
            Cantidad    = $filas.Count
        }
    } catch {
        return $null
    }
}

# Agrega la ejecucion actual al final y recorta a las ultimas $maxHistorial
function Add-Ejecucion($ruta, $liberadoMB, $libreFinBytes, $avisos) {
    $c = $script:culturaHistorial
    $nueva = [pscustomobject]@{
        Fecha      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $c)
        LiberadoMB = ([math]::Round($liberadoMB, 2)).ToString($c)
        LibreFinGB = ([math]::Round($libreFinBytes / 1GB, 2)).ToString($c)
        Avisos     = "$avisos"
    }
    $filas = @()
    if (Test-Path $ruta) { $filas = @(Import-Csv $ruta -Delimiter ';') }
    # @() por fuera: con una sola fila Select-Object devuelve el objeto suelto y en PS 5.1
    # un PSCustomObject suelto no tiene .Count (el log mostraba "( registrada(s)")
    $filas = @(@($filas + $nueva) | Select-Object -Last $script:maxHistorial)
    $filas | Export-Csv $ruta -Delimiter ';' -NoTypeInformation -Encoding UTF8
    return $filas.Count
}

# A que ritmo se esta llenando C:, con una recta de minimos cuadrados sobre el espacio libre despues de
# cada limpieza de los ultimos 120 dias (mas la de hoy). Como todos los puntos son despues de limpiar,
# lo que se mide es lo que se pierde aunque se limpie. Necesita 4 puntos y 14 dias de historial; si no, $null.
# No se compara solo con una ejecucion vieja: el 25/11/2026 la de base cayo en un dia con 172 GB libres
# y, por archivos que el usuario borro a mano despues, el resumen decia "ganas 24,6 GB al mes".
function Get-TendenciaEspacio($ruta, $libreFinBytes, $tamanoBytes) {
    if (-not (Test-Path $ruta) -or $tamanoBytes -le 0) { return $null }
    try {
        $c = $script:culturaHistorial
        $filas = @(Import-Csv $ruta -Delimiter ';' | ForEach-Object {
            [pscustomobject]@{
                Fecha      = [datetime]::ParseExact($_.Fecha, 'yyyy-MM-dd HH:mm:ss', $c)
                LibreFinGB = [double]::Parse($_.LibreFinGB, $c)
            }
        })
    } catch {
        return $null
    }
    $ahora = Get-Date
    $libreGB = $libreFinBytes / 1GB
    $puntos = @($filas | Where-Object { $_.Fecha -gt $ahora.AddDays(-120) }) +
        [pscustomobject]@{ Fecha = $ahora; LibreFinGB = $libreGB }
    $desde = ($puntos | Sort-Object Fecha | Select-Object -First 1).Fecha
    if ($puntos.Count -lt 4 -or ($ahora - $desde).TotalDays -lt 14) { return $null }
    # Pendiente en GB por dia (x = dias desde el primer punto)
    $xs = @($puntos | ForEach-Object { ($_.Fecha - $desde).TotalDays })
    $ys = @($puntos | ForEach-Object { $_.LibreFinGB })
    $mx = ($xs | Measure-Object -Average).Average
    $my = ($ys | Measure-Object -Average).Average
    $num = 0.0; $den = 0.0
    for ($i = 0; $i -lt $xs.Count; $i++) {
        $num += ($xs[$i] - $mx) * ($ys[$i] - $my)
        $den += ($xs[$i] - $mx) * ($xs[$i] - $mx)
    }
    if ($den -le 0) { return $null }
    $gbPorMes = -($num / $den) * 30   # positivo = se esta llenando
    $base = [pscustomobject]@{ Fecha = $desde }
    # Meses hasta quedar con menos del 15 % libre (el limite del aviso de "Espacio en C:")
    $margenGB = $libreGB - 0.15 * $tamanoBytes / 1GB
    [pscustomobject]@{
        GBPorMes = $gbPorMes
        Desde    = $base.Fecha
        Meses    = if ($gbPorMes -gt 0.1 -and $margenGB -gt 0) { $margenGB / $gbPorMes } else { $null }
    }
}

# "hace 25 min", "hace 5 horas", "hace 6 dias"
function Format-Hace($fecha) {
    $t = (Get-Date) - $fecha
    if ($t.TotalMinutes -lt 60) { return "hace $([math]::Max(1, [math]::Floor($t.TotalMinutes))) min" }
    if ($t.TotalHours -lt 2) { return 'hace 1 hora' }
    if ($t.TotalHours -lt 48) { return "hace $([math]::Floor($t.TotalHours)) horas" }
    return "hace $([math]::Floor($t.TotalDays)) dias"
}
