# Resumen final de la limpieza.
# Cada funcion Write-* produce las dos versiones a la vez, asi nunca se desincronizan:
#   - consola (texto de ancho fijo con colores; queda tambien en el log)
#   - HTML para el correo (tarjetas y filas que se adaptan al ancho del celular)
# Se carga con dot-sourcing desde limpiar.ps1.

$script:anchoResumen = 68
$script:resumenHtml = New-Object Text.StringBuilder
$script:tarjetaAbierta = $false
$script:avisosResumen = 0

# Colores de consola -> colores de texto del correo (fondo blanco)
$script:coloresHtml = @{
    Cyan  = '#0e7490'; DarkCyan = '#0e7490'
    Green = '#15803d'; Yellow   = '#a16207'; Red = '#b91c1c'
    White = '#0f172a'; Gray     = '#0f172a'; DarkGray = '#64748b'
}
$script:fuenteHtml = "-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"

# --- Piezas basicas ---

# Solo consola (y log). Siempre una linea completa de un solo color: el log de PowerShell 5.1
# corta la linea cada vez que se usa -NoNewline, asi que no se mezclan colores en una misma linea.
function Out-Resumen([string]$texto = '', $color = 'Gray') {
    Write-Host $texto -ForegroundColor $color
}

# Solo correo
function Add-Html([string]$html) { [void]$script:resumenHtml.Append($html) }
function Format-HtmlTexto([string]$texto) { [Net.WebUtility]::HtmlEncode($texto) }
function Get-ColorHtml($color) {
    $c = $script:coloresHtml[$color]
    if ($c) { $c } else { $script:coloresHtml['Gray'] }
}

function Close-Tarjeta {
    if ($script:tarjetaAbierta) {
        Add-Html '</td></tr></table></td></tr>'
        $script:tarjetaAbierta = $false
    }
}

# Recorta un texto a un ancho fijo para que las tablas de consola queden alineadas
# (siempre deja al menos un espacio de separacion con la columna siguiente)
function Format-Ancho($texto, $ancho) {
    $t = "$texto"
    if ($t.Length -gt $ancho - 1) { $t = $t.Substring(0, $ancho - 4) + '...' }
    return $t.PadRight($ancho)
}

# --- Bloques del resumen (consola + correo) ---

# Marco doble con un titulo centrado (solo consola; tambien lo usa el inicio de limpiar.ps1)
function Write-CajaConsola($titulo) {
    $interior = $script:anchoResumen - 2
    $izq = [math]::Floor(($interior - $titulo.Length) / 2)
    $h = [string][char]0x2550
    Out-Resumen ''
    Out-Resumen ('  ' + [char]0x2554 + ($h * $interior) + [char]0x2557) Cyan
    Out-Resumen ('  ' + [char]0x2551 + (' ' * $izq) + $titulo + (' ' * ($interior - $izq - $titulo.Length)) + [char]0x2551) Cyan
    Out-Resumen ('  ' + [char]0x255A + ($h * $interior) + [char]0x255D) Cyan
}

# Titulo de seccion con linea debajo (solo consola)
function Write-SeccionConsola($titulo) {
    Out-Resumen ''
    Out-Resumen "  $titulo" Cyan
    Out-Resumen ('  ' + ([string][char]0x2500 * ($script:anchoResumen - 2))) DarkCyan
}

function Write-Cabecera($titulo, $subtitulo) {
    Write-CajaConsola $titulo
    Out-Resumen "  $subtitulo" DarkGray

    Add-Html ('<tr><td style="background:#0e7490;border-radius:12px;padding:20px 20px 18px;color:#ffffff">' +
        '<div style="font-size:20px;font-weight:700;line-height:1.3">' + (Format-HtmlTexto $titulo) + '</div>' +
        '<div style="font-size:13px;color:#cffafe;margin-top:4px">' + (Format-HtmlTexto $subtitulo) + '</div>' +
        '</td></tr>')
}

function Write-Seccion($titulo) {
    Write-SeccionConsola $titulo

    Close-Tarjeta
    Add-Html ('<tr><td style="padding-top:12px">' +
        '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" ' +
        'style="background:#ffffff;border:1px solid #e2e8f0;border-radius:12px"><tr><td style="padding:14px 16px 10px">' +
        '<div style="font-size:12px;font-weight:700;letter-spacing:1px;color:#0e7490;padding-bottom:4px">' +
        (Format-HtmlTexto $titulo) + '</div>')
    $script:tarjetaAbierta = $true
}

# Dato "etiqueta ..... valor"; en el correo, etiqueta a la izquierda y valor a la derecha
function Write-Dato($etiqueta, $valor, $color = 'White') {
    Out-Resumen ('    ' + "$etiqueta ".PadRight(30, '.') + ' ' + $valor) $color

    Add-Html ('<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid #f1f5f9"><tr>' +
        '<td style="padding:8px 8px 8px 0;font-size:14px;color:#475569">' + (Format-HtmlTexto $etiqueta) + '</td>' +
        '<td align="right" style="padding:8px 0;font-size:14px;font-weight:600;color:' + (Get-ColorHtml $color) + '">' +
        (Format-HtmlTexto $valor).Replace(' -&gt; ', ' &rarr; ') + '</td></tr></table>')
}

# Linea con estado: OK (verde), AVISO (amarillo) o NA (gris, dato no disponible)
function Write-Estado($nivel, $etiqueta, $valor) {
    $marca, $color, $textoPastilla, $fondo, $tinta = switch ($nivel) {
        'OK'    { ' OK ', 'Green',    'OK',    '#dcfce7', '#15803d' }
        'AVISO' { ' !! ', 'Yellow',   'AVISO', '#fef9c3', '#a16207' }
        default { ' -- ', 'DarkGray', 'N/D',   '#f1f5f9', '#64748b' }
    }
    if ($nivel -eq 'AVISO') { $script:avisosResumen++ }
    Out-Resumen ('    [' + $marca + '] ' + "$etiqueta ".PadRight(24, '.') + ' ' + $valor) $color

    # En el correo: pastilla de color + etiqueta, y el detalle debajo (se lee bien en pantallas angostas)
    Add-Html ('<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid #f1f5f9"><tr>' +
        '<td width="64" valign="top" style="padding:9px 0">' +
        '<span style="display:inline-block;min-width:44px;text-align:center;padding:2px 8px;border-radius:999px;' +
        'font-size:11px;font-weight:700;background:' + $fondo + ';color:' + $tinta + '">' + $textoPastilla + '</span></td>' +
        '<td style="padding:8px 0">' +
        '<div style="font-size:14px;font-weight:600;color:#0f172a">' + (Format-HtmlTexto $etiqueta) + '</div>' +
        '<div style="font-size:13px;color:#475569;margin-top:2px">' + (Format-HtmlTexto $valor) + '</div>' +
        '</td></tr></table>')
}

# Nota pequena al pie de una seccion
function Write-Nota($texto, $color = 'DarkGray') {
    Out-Resumen "    $texto" $color
    Add-Html ('<div style="font-size:13px;color:' + (Get-ColorHtml $color) + ';padding:8px 0 4px">' + (Format-HtmlTexto $texto) + '</div>')
}

# Lista de nombres: dos columnas en consola, etiquetas que se acomodan solas en el correo
function Write-Lista($nombres) {
    $nombres = @($nombres)
    for ($i = 0; $i -lt $nombres.Count; $i += 2) {
        $fila = '    - ' + (Format-Ancho $nombres[$i] 28)
        if ($i + 1 -lt $nombres.Count) { $fila += '  - ' + $nombres[$i + 1] }
        Out-Resumen $fila.TrimEnd() White
    }
    Add-Html '<div style="padding:6px 0 2px">'
    foreach ($n in $nombres) {
        Add-Html ('<span style="display:inline-block;margin:0 6px 6px 0;padding:4px 10px;border-radius:999px;' +
            'background:#f1f5f9;color:#0f172a;font-size:13px">' + (Format-HtmlTexto $n) + '</span>')
    }
    Add-Html '</div>'
}

function Write-TablaApps($titulo, $apps, $color, [switch]$ConMotivo) {
    if (-not $apps) { return }
    $apps = @($apps)
    Out-Resumen ''
    Out-Resumen "    $titulo ($($apps.Count))" $color
    Add-Html ('<div style="font-size:14px;font-weight:700;color:' + (Get-ColorHtml $color) + ';padding:12px 0 2px">' +
        (Format-HtmlTexto "$titulo ($($apps.Count))") + '</div>')

    foreach ($a in $apps) {
        # Consola: si el nombre no cabe se muestra el Id, porque al recortar dos apps pueden
        # quedar iguales (ej. "Microsoft Visual C++ 2013 Redi..." x64 y x86); el Id es unico
        $nombre = if ($a.Nombre.Length -gt 33 -and $a.Id -and $a.Id.Length -le 33) { $a.Id } else { $a.Nombre }
        Out-Resumen ('      ' + (Format-Ancho $nombre 34) + (Format-Ancho $a.Instalada 15) + '-> ' + $a.Disponible) $color
        if ($ConMotivo -and $a.Motivo) { Out-Resumen "        motivo: $($a.Motivo)" DarkGray }

        # Correo: nombre completo (el texto se ajusta solo) y las versiones debajo
        # El motivo va en rojo solo si es un error; si no (ej. "se actualiza sola"), en gris
        $motivo = ''
        if ($ConMotivo -and $a.Motivo) {
            $colorMotivo = if ($color -eq 'Red') { '#b91c1c' } else { '#64748b' }
            $motivo = '<div style="font-size:12px;color:' + $colorMotivo + ';margin-top:2px">' + (Format-HtmlTexto $a.Motivo) + '</div>'
        }
        Add-Html ('<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid #f1f5f9"><tr>' +
            '<td style="padding:7px 0">' +
            '<div style="font-size:14px;color:#0f172a">' + (Format-HtmlTexto $a.Nombre) + '</div>' +
            '<div style="font-size:12px;color:#64748b;margin-top:1px">' + (Format-HtmlTexto $a.Instalada) + ' &rarr; ' +
            (Format-HtmlTexto $a.Disponible) + '</div>' + $motivo +
            '</td></tr></table>')
    }
}

# --- Datos ---

# Lee el estado de WinRE de la salida de "reagentc /info". Solo mira la linea del estado
# ("Windows RE status: Enabled" / "Estado de Windows RE: Enabled"), no el resto del texto.
# Devuelve $true, $false o $null si no se reconoce.
function Get-EstadoWinRE($texto) {
    foreach ($linea in "$texto" -split "`n") {
        if ($linea -match '(status|estado)[^:]*:\s*(\S+)') {
            if ($Matches[2] -match '^(Enabled|Habilitado)$') { return $true }
            if ($Matches[2] -match '^(Disabled|Deshabilitado)$') { return $false }
        }
    }
    return $null
}

# Datos de salud del equipo. Lo que requiere administrador queda en $null si no lo es.
function Get-SaludEquipo($discoC, $esAdmin) {
    # Bateria (solo portatiles): capacidad actual frente a la de fabrica, segun el informe de Windows
    $bateria = $null
    if (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) {
        $xml = Join-Path $env:TEMP 'bateria_limpieza.xml'
        powercfg /batteryreport /xml /output $xml | Out-Null
        try {
            $b = ([xml](Get-Content $xml -Raw)).BatteryReport.Batteries.Battery | Select-Object -First 1
            if ([double]$b.DesignCapacity -gt 0) {
                $bateria = [pscustomobject]@{
                    Salud  = [math]::Round(100 * [double]$b.FullChargeCapacity / [double]$b.DesignCapacity)
                    Ciclos = $b.CycleCount
                }
            }
        } catch { }
        Remove-Item $xml -ErrorAction SilentlyContinue
    }

    $winre = $null
    if ($esAdmin) {
        $winre = Get-EstadoWinRE ((& reagentc.exe /info 2>$null) -join "`n")
    }

    [pscustomobject]@{
        Bateria           = $bateria
        Fiabilidad        = if ($esAdmin) { $discoC | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue } else { $null }
        WinRE             = $winre
        ReinicioPendiente = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
                            (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    }
}

# --- Resumen completo ---

# Muestra el resumen. $d es un hashtable con los datos que junta limpiar.ps1.
function Show-Resumen($d) {
    $salud = Get-SaludEquipo $d.DiscoC $d.EsAdmin

    Write-Cabecera 'RESUMEN DE LA LIMPIEZA' ("$env:COMPUTERNAME - " + (Get-Date -Format 'dd/MM/yyyy HH:mm'))

    # --- Espacio ---
    Write-Seccion 'ESPACIO'
    $delta = ($d.LibreFin - $d.LibreInicio) / 1GB
    $signo = if ($delta -ge 0) { '+' } else { '' }
    # En GB desde 1000 MB: con separador de miles "15.823,82 MB" se lee como 15 MB
    $liberadoTexto = if ($d.Total -ge 1000) { '{0:N2} GB' -f ($d.Total / 1024) } else { '{0:N0} MB' -f $d.Total }
    Write-Dato 'Liberado por la limpieza' $liberadoTexto Green
    Write-Dato 'Espacio libre en C:' ('{0:N1} -> {1:N1} GB ({2}{3:N1} GB)' -f ($d.LibreInicio / 1GB), ($d.LibreFin / 1GB), $signo, $delta)

    # Comparacion con la limpieza anterior (historial.csv)
    if ($d.Anterior) {
        $a = $d.Anterior
        $liberadoAntes = if ($a.LiberadoMB -ge 1024) { '{0:N2} GB' -f ($a.LiberadoMB / 1024) } else { '{0:N0} MB' -f $a.LiberadoMB }
        Write-Dato 'Limpieza anterior' ('{0} ({1:dd/MM HH:mm}), libero {2}' -f (Format-Hace $a.Fecha), $a.Fecha, $liberadoAntes) White
        # Cuanto se lleno el disco entre esa limpieza y esta (antes de limpiar hoy)
        $lleno = $a.LibreFinGB - ($d.LibreInicio / 1GB)
        $textoLleno = if ($lleno -ge 0.05) { 'se ocuparon {0:N1} GB' -f $lleno } elseif ($lleno -le -0.05) { 'se liberaron {0:N1} GB' -f (-$lleno) } else { 'casi sin cambios' }
        Write-Dato 'Desde entonces' $textoLleno White
    } else {
        Write-Dato 'Limpieza anterior' 'esta es la primera registrada' DarkGray
    }
    # Docker: lo que libera queda dentro de su disco virtual; vuelve a Windows al compactar
    if ($d.DockerInstalado -and $d.EsAdmin) {
        if ($d.DockerActivo) {
            Write-Dato 'Limpieza de Docker' ('{0:N2} MB' -f ($d.DockerLiberado / 1MB)) Green
            if ($d.DockerImagenes) { Write-Nota ('Imagenes de Docker borradas: ' + (@($d.DockerImagenes).Nombre -join ', ')) }
        } else {
            Write-Dato 'Limpieza de Docker' 'no estaba en marcha' DarkGray
        }
    }
    foreach ($c in $d.Compactados) {
        if ($c.Ok) { Write-Dato "Disco virtual $($c.Nombre)" ('{0:N2} GB -> {1:N2} GB' -f ($c.Antes / 1GB), ($c.Despues / 1GB)) Green }
        else { Write-Dato "Disco virtual $($c.Nombre)" 'no se pudo compactar (ver log)' Red }
    }

    # --- Salud del equipo ---
    Write-Seccion 'SALUD DEL EQUIPO'
    $textoDisco = "$($d.DiscoC.HealthStatus)"
    $nivelDisco = if ($d.DiscoC.HealthStatus -eq 'Healthy') { 'OK' } else { 'AVISO' }
    $f = $salud.Fiabilidad
    if ($f -and $null -ne $f.Wear) {
        $textoDisco += " | vida usada $($f.Wear)%"
        if ($f.Wear -ge 80) { $nivelDisco = 'AVISO' }
    }
    if ($f -and $f.Temperature) {
        $textoDisco += " | $($f.Temperature) $([char]0xB0)C"
        # Un SSD NVMe trabaja normalmente a 60-75 C con carga (y se mide justo despues del TRIM);
        # empieza a protegerse cerca de 80 C. Con un umbral mas bajo habria avisos falsos.
        if ($f.Temperature -ge 80) { $nivelDisco = 'AVISO' }
    }
    Write-Estado $nivelDisco "Disco ($($d.DiscoC.MediaType))" $textoDisco

    # Poco espacio: con menos del 15 % libre Windows y las actualizaciones empiezan a tener problemas
    if ($d.TamanoC -gt 0) {
        $porcentaje = 100 * $d.LibreFin / $d.TamanoC
        $nivelEspacio = if ($porcentaje -lt 15) { 'AVISO' } else { 'OK' }
        $textoEspacio = '{0:N1} GB libres de {1:N0} GB ({2:N0} %)' -f ($d.LibreFin / 1GB), ($d.TamanoC / 1GB), $porcentaje
        if ($nivelEspacio -eq 'AVISO') { $textoEspacio += ': queda poco espacio' }
        Write-Estado $nivelEspacio 'Espacio en C:' $textoEspacio
    }

    if ($salud.Bateria) {
        $nivel = if ($salud.Bateria.Salud -ge 80) { 'OK' } else { 'AVISO' }
        Write-Estado $nivel 'Bateria' "$($salud.Bateria.Salud)% de la capacidad original ($($salud.Bateria.Ciclos) ciclos)"
    }

    if (-not $d.EsAdmin) { Write-Estado 'NA' 'Recuperacion (WinRE)' 'solo se revisa como administrador' }
    elseif ($salud.WinRE -eq $true) { Write-Estado 'OK' 'Recuperacion (WinRE)' 'activa' }
    elseif ($salud.WinRE -eq $false) { Write-Estado 'AVISO' 'Recuperacion (WinRE)' 'desactivada: si Windows no arranca no habra reparacion' }
    else { Write-Estado 'NA' 'Recuperacion (WinRE)' 'no se pudo leer el estado' }

    if ($salud.ReinicioPendiente) { Write-Estado 'AVISO' 'Reinicio pendiente' 'si: reinicia para terminar actualizaciones' }
    else { Write-Estado 'OK' 'Reinicio pendiente' 'no' }

    # --- Programas de inicio ---
    $inicio = @($d.Inicio)
    Write-Seccion "PROGRAMAS QUE ARRANCAN CON WINDOWS ($($inicio.Count))"
    Write-Lista ($inicio | ForEach-Object { $_.Name })
    Write-Nota 'Para desactivar: Administrador de tareas (Ctrl+Shift+Esc) > Aplicaciones de arranque'

    # --- Aplicaciones ---
    Write-Seccion 'APLICACIONES'
    if ($d.EstadoWinget -notin 'ok', 'al dia') {
        # No decir "todo al dia" si en realidad no se pudo consultar
        Write-Nota "No se pudo consultar winget: $($d.EstadoWinget). No se sabe si hay actualizaciones" Red
    } elseif ($d.SeActualizo) {
        Write-TablaApps 'Actualizadas' $d.AppsActualizadas Green
        Write-TablaApps 'No se pudieron actualizar' $d.AppsFallidas Red -ConMotivo
        Write-TablaApps 'Siguen pendientes' $d.AppsPendientes Yellow
        Write-TablaApps 'Se actualizan solas' $d.AppsOmitidas DarkGray -ConMotivo
        if (-not $d.AppsPendientes -and -not $d.AppsFallidas) { Write-Nota 'Todo lo demas esta al dia' Green }
    } elseif ($d.AppsDisponibles) {
        Write-TablaApps 'Con actualizacion disponible' $d.AppsDisponibles Yellow
        Write-Nota "Para actualizarlas, responde S a 'Actualizar las aplicaciones' la proxima vez"
    } else {
        Write-Nota 'Todas las aplicaciones estan al dia' Green
    }

    Close-Tarjeta
    Out-Resumen ''
    Out-Resumen ('  ' + ([string][char]0x2550 * $script:anchoResumen)) Cyan
}

# Documento HTML del correo. Ancho maximo 600 px (el estandar de los correos) y 100 % en el celular.
function Get-ResumenHtml($pie) {
    '<!doctype html><html><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width, initial-scale=1"></head>' +
    '<body style="margin:0;padding:0;background:#f1f5f9">' +
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f1f5f9"><tr>' +
    '<td align="center" style="padding:16px 10px">' +
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" ' +
    'style="max-width:600px;font-family:' + $script:fuenteHtml + ';color:#0f172a">' +
    $script:resumenHtml.ToString() +
    '<tr><td style="padding:14px 4px 0;font-size:12px;color:#64748b;text-align:center">' + (Format-HtmlTexto $pie) + '</td></tr>' +
    '</table></td></tr></table></body></html>'
}
