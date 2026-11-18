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
    $filas = @($filas + $nueva) | Select-Object -Last $script:maxHistorial
    $filas | Export-Csv $ruta -Delimiter ';' -NoTypeInformation -Encoding UTF8
    return $filas.Count
}

# "hace 25 min", "hace 5 horas", "hace 6 dias"
function Format-Hace($fecha) {
    $t = (Get-Date) - $fecha
    if ($t.TotalMinutes -lt 60) { return "hace $([math]::Max(1, [math]::Floor($t.TotalMinutes))) min" }
    if ($t.TotalHours -lt 48) { return "hace $([math]::Floor($t.TotalHours)) horas" }
    return "hace $([math]::Floor($t.TotalDays)) dias"
}
