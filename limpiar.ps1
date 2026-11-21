# Limpieza de Windows - se ejecuta desde limpiar.bat
$ErrorActionPreference = 'Continue'
# Un solo log: cada ejecucion reemplaza al anterior
$logFile = Join-Path $PSScriptRoot 'limpieza.log'
Start-Transcript -Path $logFile | Out-Null

# Modulos: resumen final (consola + HTML), envio por correo e historial de ejecuciones
. (Join-Path $PSScriptRoot 'lib\resumen.ps1')
. (Join-Path $PSScriptRoot 'lib\correo.ps1')
. (Join-Path $PSScriptRoot 'lib\historial.ps1')
$archivoHistorial = Join-Path $PSScriptRoot 'historial.csv'

function Log($msg, $color = 'Gray') {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg) -ForegroundColor $color
}

# Tamano legible: en GB desde 1000 MB, porque "1.010 MB" se confunde con 1 MB por el separador de miles
function Format-Tamano($bytes) {
    if ($bytes -ge 1000MB) { return '{0:N2} GB' -f ($bytes / 1GB) }
    return '{0:N0} MB' -f ($bytes / 1MB)
}

function Get-FolderSize($path) {
    (Get-ChildItem $path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
}

# Indica si un archivo o carpeta se uso despues de $limite (en una carpeta mira todo su contenido;
# se detiene en el primer archivo reciente que encuentra)
function Test-Reciente($item, $limite) {
    if ($item.LastWriteTime -gt $limite) { return $true }
    if (-not $item.PSIsContainer) { return $false }
    $reciente = Get-ChildItem $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $limite } | Select-Object -First 1
    return [bool]$reciente
}

# Borra el contenido de una carpeta (no la carpeta) y devuelve los MB liberados.
# Con -HorasMinimas solo borra lo que no se modifico en ese tiempo: en las carpetas temporales
# hay archivos de programas que estan trabajando ahora mismo (instaladores, Docker, etc.) y que
# no siempre estan bloqueados; borrarlos puede romper esos programas.
function Clear-Folder($path, $HorasMinimas = 0) {
    $antes = Get-FolderSize $path
    $borrados = 0; $omitidos = 0; $recientes = 0
    $limite = (Get-Date).AddHours(-$HorasMinimas)
    foreach ($item in Get-ChildItem $path -Force -ErrorAction SilentlyContinue) {
        if ($HorasMinimas -gt 0 -and (Test-Reciente $item $limite)) {
            $recientes++
            continue
        }
        # SilentlyContinue + ErrorVariable para que el error no ensucie el log
        Remove-Item $item.FullName -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable err
        if ($err) {
            Log "  en uso, omitido: $($item.Name)" DarkYellow
            $omitidos++
        } else {
            Log "  borrado: $($item.Name)" DarkGray
            $borrados++
        }
    }
    # Max(0): si un programa escribe en la carpeta mientras tanto, no mostrar negativos
    $liberado = [math]::Round([math]::Max([double]0, $antes - (Get-FolderSize $path)) / 1MB, 2)
    $textoRecientes = if ($HorasMinimas -gt 0) { ", $recientes conservados por ser de las ultimas $HorasMinimas h" } else { '' }
    Log "  $borrados borrados, $omitidos omitidos$textoRecientes, $liberado MB liberados" Green
    return $liberado
}

# Ejecuta una herramienta de consola (dism, sfc) mostrando su salida en el log.
# Devuelve el codigo de salida.
function Invoke-Herramienta($exe, $argumentos, [switch]$Unicode) {
    # sfc escribe en UTF-16: sin esto su salida sale con caracteres raros
    $encAnterior = [Console]::OutputEncoding
    if ($Unicode) { [Console]::OutputEncoding = [Text.Encoding]::Unicode }
    $ultimaDecena = -1
    try {
        & $exe @argumentos | ForEach-Object {
            # Las barras de progreso reescriben la linea con `r: quedarse con el ultimo estado
            $linea = $_ -split "`r" | Where-Object { $_.Trim() } | Select-Object -Last 1
            if (-not $linea) { return }
            # Progreso: registrar solo cada 10% para no llenar el log de cientos de lineas
            if ($linea -match '(\d+)[\.,]?\d*\s*%') {
                $decena = [math]::Floor([int]$Matches[1] / 10)
                if ($decena -le $ultimaDecena) { return }
                $ultimaDecena = $decena
            }
            Log "  $($linea.Trim())" DarkGray
        }
    } finally {
        [Console]::OutputEncoding = $encAnterior
    }
    return $LASTEXITCODE
}

# Indica si un programa de inicio esta habilitado (el Administrador de tareas
# guarda los deshabilitados en StartupApproved con el primer byte impar)
function Test-InicioHabilitado($cmd) {
    $sub = switch -Wildcard ($cmd.Location) {
        '*Startup'      { 'StartupFolder' }
        '*Wow6432Node*' { 'Run32' }
        default         { 'Run' }
    }
    $hive = if ($cmd.Location -like 'HKLM*' -or $cmd.Location -eq 'Common Startup') { 'HKLM:' } else { 'HKCU:' }
    $nombre = if ($sub -eq 'StartupFolder') { $cmd.Command } else { $cmd.Name }
    $clave = "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$sub"
    $valor = (Get-ItemProperty $clave -Name $nombre -ErrorAction SilentlyContinue).$nombre
    return -not ($valor -and ($valor[0] % 2 -eq 1))
}

# Discos virtuales (.vhdx) de las distribuciones WSL registradas y los datos de Docker.
# Estos archivos crecen pero nunca se achican solos.
function Get-DiscosVirtuales {
    $lxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    foreach ($d in Get-ChildItem $lxss -ErrorAction SilentlyContinue) {
        $p = Get-ItemProperty $d.PSPath
        if (-not $p.BasePath) { continue }   # distribucion registrada a medias
        $vhd = Join-Path ($p.BasePath -replace '^\\\\\?\\', '') $(if ($p.VhdFileName) { $p.VhdFileName } else { 'ext4.vhdx' })
        if (Test-Path $vhd) { [pscustomobject]@{ Nombre = $p.DistributionName; Ruta = $vhd } }
    }
    $docker = "$env:LOCALAPPDATA\Docker\wsl\disk\docker_data.vhdx"
    if (Test-Path $docker) { [pscustomobject]@{ Nombre = 'Docker (datos)'; Ruta = $docker } }
}

# Indica si Docker esta instalado y su motor en marcha (si Docker Desktop esta cerrado no se puede limpiar)
function Test-DockerActivo {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return $false }
    & docker info --format '{{.ServerVersion}}' 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Imagenes de Docker con nombre que no usa ningun contenedor (ni siquiera uno detenido).
# Las huerfanas (<none>) no se incluyen: esas las borra 'docker image prune' sin preguntar.
function Get-ImagenesDockerSinUso {
    $contenedores = @(& docker ps -a -q --no-trunc 2>$null)
    $usadas = if ($contenedores) { @(& docker inspect --format '{{.Image}}' @contenedores 2>$null) } else { @() }
    foreach ($linea in & docker images --no-trunc --format '{{.ID}}|{{.Repository}}:{{.Tag}}' 2>$null) {
        $id, $nombre = "$linea" -split '\|', 2
        if (-not $nombre -or $nombre -like '*<none>*' -or $id -in $usadas) { continue }
        [pscustomobject]@{
            Id     = $id
            Nombre = $nombre
            Bytes  = [double](& docker image inspect --format '{{.Size}}' $id 2>$null)
        }
    }
}

# Convierte un tamano como lo escribe Docker ("22.04MB", "1.368GB", "0B") a bytes.
# Docker usa unidades decimales (1 kB = 1000 B).
function ConvertFrom-TamanoDocker($texto) {
    if ("$texto" -notmatch '([\d\.]+)\s*(B|kB|KB|MB|GB|TB)\b') { return 0 }
    $factor = switch ($Matches[2]) { 'B' { 1 } { $_ -in 'kB', 'KB' } { 1e3 } 'MB' { 1e6 } 'GB' { 1e9 } 'TB' { 1e12 } }
    return [double]$Matches[1] * $factor
}

# Recorta una columna de una linea de tabla sin fallar si la linea es mas corta
function Get-Columna($linea, $desde, $hasta) {
    if ($desde -ge $linea.Length) { return '' }
    $largo = [math]::Min($hasta, $linea.Length) - $desde
    return $linea.Substring($desde, $largo).Trim()
}

# Aplicaciones con actualizacion disponible segun winget, leidas de su tabla de texto.
# Las columnas se ubican por la posicion de los titulos (el idioma de winget no importa).
# Deja en $script:estadoWinget si la consulta funciono, para no decir "todo al dia" cuando
# en realidad winget fallo (sin internet, no instalado...):
#   'ok' (hay tabla), 'al dia' (winget confirma que no hay nada), 'no instalado' o 'error (codigo N)'
function Get-AppsDesactualizadas {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { $script:estadoWinget = 'no instalado'; return }
    $encAnterior = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    try { $salida = winget upgrade --accept-source-agreements --disable-interactivity 2>$null }
    finally { [Console]::OutputEncoding = $encAnterior }
    $codigo = $LASTEXITCODE
    # Quitar la animacion de carga que winget escribe con `r antes de la tabla
    $lineas = @($salida | ForEach-Object { ("$_" -split "`r")[-1] })
    $iSep = 0..($lineas.Count - 1) | Where-Object { $lineas[$_] -match '^-{10,}$' } | Select-Object -First 1
    $col = if ($null -ne $iSep -and $iSep -ge 1) {
        @([regex]::Matches($lineas[$iSep - 1], '\S+') | ForEach-Object { $_.Index })   # Nombre, Id, Version, Disponible, Origen
    }
    if (-not $col -or $col.Count -lt 5) {
        # Sin tabla: 0 o "No installed package found" (-1978335212) = no hay actualizaciones; otro codigo = fallo
        $script:estadoWinget = if ($codigo -eq 0 -or $codigo -eq -1978335212) { 'al dia' } else { "error (codigo $codigo)" }
        return
    }
    $script:estadoWinget = 'ok'
    foreach ($l in $lineas[($iSep + 1)..($lineas.Count - 1)]) {
        # La tabla termina en la primera linea vacia o en el total ("17 upgrades available.",
        # 3 palabras; una fila de app tiene al menos 5 columnas aunque el nombre empiece con numero)
        if (-not $l.Trim() -or ($l -match '^\d+ ' -and @($l.Trim() -split '\s+').Count -le 4)) { break }
        $app = [pscustomobject]@{
            Nombre     = Get-Columna $l 0 $col[1]
            Id         = Get-Columna $l $col[1] $col[2]
            Instalada  = Get-Columna $l $col[2] $col[3]
            Disponible = Get-Columna $l $col[3] $col[4]
        }
        if ($app.Id) { $app }
    }
}

$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$total = 0
$compactados = @()
$dockerLiberado = 0          # bytes liberados dentro del disco virtual de Docker (paso 11)
$imagenesDockerBorradas = @()
$libreInicio = (Get-PSDrive C).Free
$maxPuntos = 2         # puntos de restauracion a conservar (se borran los mas viejos)
$horasTemporales = 24  # en los pasos 1 y 2 solo se borran temporales sin modificar en este tiempo

$navegadores = @(
    @{ Nombre = 'Chrome';  Proceso = 'chrome';  Datos = "$env:LOCALAPPDATA\Google\Chrome\User Data" },
    @{ Nombre = 'Edge';    Proceso = 'msedge';  Datos = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" },
    @{ Nombre = 'Brave';   Proceso = 'brave';   Datos = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" },
    @{ Nombre = 'Firefox'; Proceso = 'firefox'; Datos = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles" }
) | Where-Object { Test-Path $_.Datos }

# ======================================================================
# Inicio: encabezado y preguntas (todas al principio, para que despues corra sola)
# ======================================================================
Write-CajaConsola 'LIMPIEZA DE WINDOWS'
$modo = if ($esAdmin) { 'como administrador' } else { 'SIN permisos de administrador: se hara solo una parte' }
Write-Host "  $env:COMPUTERNAME - $(Get-Date -Format 'dd/MM/yyyy HH:mm') - $modo" -ForegroundColor DarkGray

# Datos que necesitan las preguntas
$discosVirtuales = @(Get-DiscosVirtuales)
$dockerInstalado = [bool](Get-Command docker -ErrorAction SilentlyContinue)
$dockerActivo = $esAdmin -and (Test-DockerActivo)
$imagenesDockerSinUso = if ($dockerActivo) { @(Get-ImagenesDockerSinUso) } else { @() }
$listaImagenes = ($imagenesDockerSinUso.Nombre -join ', ')
# Cache de NuGet (.NET): paquetes descargados (respeta NUGET_PACKAGES si se cambio la carpeta) y cache HTTP
$carpetaPaquetesNuget = if ($env:NUGET_PACKAGES) { $env:NUGET_PACKAGES } else { "$HOME\.nuget\packages" }
$carpetasNuget = @($carpetaPaquetesNuget, "$env:LOCALAPPDATA\NuGet\v3-cache", "$env:LOCALAPPDATA\NuGet\plugins-cache") |
    Where-Object { Test-Path $_ }
$bytesNuget = ($carpetasNuget | ForEach-Object { Get-FolderSize $_ } | Measure-Object -Sum).Sum
# Logs de las apps de PM2 (Node.js): respeta PM2_HOME si se cambio la carpeta
$carpetaPm2 = if ($env:PM2_HOME) { $env:PM2_HOME } else { "$HOME\.pm2" }
$carpetaLogsPm2 = Join-Path $carpetaPm2 'logs'
$bytesLogsPm2 = if (Test-Path $carpetaLogsPm2) { [double](Get-FolderSize $carpetaLogsPm2) } else { 0 }

# Solo se pregunta lo que aplica en este equipo y en este momento
$preguntas = New-Object System.Collections.ArrayList
foreach ($nav in $navegadores) {
    if (Get-Process $nav.Proceso -ErrorAction SilentlyContinue) {
        [void]$preguntas.Add(@{ Clave = "nav:$($nav.Nombre)"; Titulo = "Cerrar $($nav.Nombre) para limpiar su cache"
            Detalle = @("$($nav.Nombre) esta abierto: se cerraran todas sus ventanas.", 'Si dices que no, se salta su cache.') })
    }
}
if ($bytesNuget -gt 50MB) {
    # Con poco tamano no vale la pena preguntar
    [void]$preguntas.Add(@{ Clave = 'nuget'; Titulo = 'Borrar la cache de paquetes NuGet (.NET)'
        Detalle = @("Ocupa $(Format-Tamano $bytesNuget). La proxima compilacion de un proyecto .NET tendra que volver a descargar sus paquetes.") })
}
if ($bytesLogsPm2 -gt 50MB) {
    [void]$preguntas.Add(@{ Clave = 'pm2'; Titulo = 'Vaciar los logs de PM2 (Node.js)'
        Detalle = @("Ocupan $(Format-Tamano $bytesLogsPm2). Se pierde el historial de salida y errores de las apps; las apps siguen corriendo.") })
}
if ($esAdmin) {
    [void]$preguntas.Add(@{ Clave = 'dism'; Titulo = 'Limpieza profunda de Windows (DISM)'
        Detalle = @('Borra versiones viejas de actualizaciones ya instaladas. Tarda 5-15 minutos.') })
    [void]$preguntas.Add(@{ Clave = 'reparacion'; Titulo = 'Revisar y reparar archivos de Windows (SFC + DISM)'
        Detalle = @('Crea un punto de restauracion antes. Tarda 10-40 minutos.') })
    if ($imagenesDockerSinUso) {
        # Se muestra exactamente que se borraria; despues se borran solo esas (por nombre)
        $bytesImagenes = ($imagenesDockerSinUso | Sort-Object Id -Unique | Measure-Object Bytes -Sum).Sum
        $detalle = @('Imagenes que no usa ningun contenedor:')
        $detalle += $imagenesDockerSinUso | ForEach-Object { "  - $($_.Nombre) ($(Format-Tamano $_.Bytes))" }
        $detalle += 'Total: hasta {0:N2} GB. Si se vuelven a necesitar hay que descargarlas o reconstruirlas.' -f ($bytesImagenes / 1GB)
        [void]$preguntas.Add(@{ Clave = 'imagenes'; Titulo = 'Borrar imagenes de Docker sin usar'; Detalle = $detalle })
    }
    if ($discosVirtuales) {
        [void]$preguntas.Add(@{ Clave = 'compactar'; Titulo = 'Compactar los discos virtuales de Docker y WSL'
            Detalle = @('Se apagan Docker y WSL mientras tanto (los contenedores en marcha se detienen).') })
    }
    [void]$preguntas.Add(@{ Clave = 'actualizar'; Titulo = 'Actualizar las aplicaciones desactualizadas (winget)'
        Detalle = @('Algunas apps pueden cerrarse mientras se actualizan.') })
}

# Tarjeta de una pregunta S/N. Enter sin escribir nada = No; otra respuesta se vuelve a preguntar.
# La respuesta se repite en su propia linea porque lo que se escribe en Read-Host no queda en el log.
function Read-SiNo($pregunta, $numero, $cantidad) {
    Write-Host ''
    Write-Host ('  [{0}/{1}] {2}' -f $numero, $cantidad, $pregunta.Titulo) -ForegroundColor White
    foreach ($linea in $pregunta.Detalle) { Write-Host "        $linea" -ForegroundColor DarkGray }
    while ($true) {
        # "$(...)": si Read-Host no devuelve nada (entrada cerrada) se toma como vacio = No, sin error
        $resp = "$(Read-Host '        S/N (Enter = N)')".Trim()
        if ($resp -match '^(s|si)$') { Write-Host '        -> SI' -ForegroundColor Green; return $true }
        if ($resp -match '^(n|no)?$') { Write-Host '        -> NO' -ForegroundColor DarkGray; return $false }
        Write-Host '        Respuesta no valida: escribe S o N' -ForegroundColor Yellow
    }
}

$respuestas = @{}
if ($preguntas.Count -gt 0) {
    Write-SeccionConsola 'ANTES DE EMPEZAR'
    Write-Host "  $($preguntas.Count) pregunta(s). Despues la limpieza sigue sola, sin pedir nada mas." -ForegroundColor Gray
    for ($i = 0; $i -lt $preguntas.Count; $i++) {
        $respuestas[$preguntas[$i].Clave] = Read-SiNo $preguntas[$i] ($i + 1) $preguntas.Count
    }
}
$cerrarNav = @{}
foreach ($nav in $navegadores) {
    if ($respuestas.ContainsKey("nav:$($nav.Nombre)")) { $cerrarNav[$nav.Nombre] = $respuestas["nav:$($nav.Nombre)"] }
}
$hacerDism            = [bool]$respuestas['dism']
$hacerReparacion      = [bool]$respuestas['reparacion']
$borrarImagenesDocker = [bool]$respuestas['imagenes']
$hacerCompactar       = [bool]$respuestas['compactar']
$hacerActualizar      = [bool]$respuestas['actualizar']
$borrarNuget          = [bool]$respuestas['nuget']
$borrarLogsPm2        = [bool]$respuestas['pm2']

Write-SeccionConsola 'LIMPIEZA EN CURSO'
Log "Todo listo: puedes dejar la ventana y volver cuando aparezca el resumen." Cyan

# --- Paso 1: archivos temporales del usuario ---
Log "Paso 1: temporales del usuario ($env:TEMP), los de mas de $horasTemporales h" Yellow
$total += Clear-Folder $env:TEMP -HorasMinimas $horasTemporales

if ($esAdmin) {
    # --- Paso 2: temporales de Windows ---
    $winTemp = Join-Path $env:SystemRoot 'Temp'
    Log "Paso 2: temporales de Windows ($winTemp), los de mas de $horasTemporales h" Yellow
    $total += Clear-Folder $winTemp -HorasMinimas $horasTemporales

    # --- Paso 3: cache de descargas de Windows Update ---
    # Hay que detener los servicios para que suelten los archivos
    $wuCache = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
    Log "Paso 3: cache de Windows Update ($wuCache)" Yellow
    $servicios = 'wuauserv', 'bits'
    foreach ($s in $servicios) {
        Log "  deteniendo servicio $s..."
        Stop-Service $s -Force -ErrorAction SilentlyContinue
    }
    $total += Clear-Folder $wuCache
    foreach ($s in $servicios) {
        Log "  reiniciando servicio $s..."
        Start-Service $s -ErrorAction SilentlyContinue
    }
} else {
    Log "Pasos 2 y 3 omitidos: no se ejecuto como administrador" Red
}

# --- Paso 4: cache de navegadores y VS Code ---
# Solo cache (no toca historial, cookies, contrasenas ni sesiones)
Log "Paso 4: cache de navegadores y VS Code" Yellow
foreach ($nav in $navegadores) {
    # Con el navegador abierto la cache esta bloqueada: solo se cierra si se autorizo al inicio
    if (Get-Process $nav.Proceso -ErrorAction SilentlyContinue) {
        if (-not $cerrarNav[$nav.Nombre]) {
            # Sin permiso, o se abrio despues de las preguntas
            Log "  $($nav.Nombre) esta abierto y no se autorizo cerrarlo: omitido" DarkYellow
            continue
        }
        Log "  cerrando $($nav.Nombre)..."
        Get-Process $nav.Proceso -ErrorAction SilentlyContinue | ForEach-Object { $_.CloseMainWindow() | Out-Null }
        Start-Sleep -Seconds 3
        # Lo que siga abierto (procesos en segundo plano) se cierra a la fuerza
        Get-Process $nav.Proceso -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    if ($nav.Proceso -eq 'firefox') {
        $carpetas = Get-ChildItem $nav.Datos -Directory | ForEach-Object { Join-Path $_.FullName 'cache2' }
    } else {
        # Navegadores basados en Chromium: un perfil por carpeta (Default, Profile 1, ...)
        $perfiles = Get-ChildItem $nav.Datos -Directory | Where-Object { $_.Name -match '^(Default|Profile \d+)$' }
        $carpetas = foreach ($p in $perfiles) {
            foreach ($c in 'Cache', 'Code Cache', 'GPUCache') { Join-Path $p.FullName $c }
        }
    }
    foreach ($c in $carpetas | Where-Object { Test-Path $_ }) {
        Log "  $($nav.Nombre): $c"
        $total += Clear-Folder $c
    }
}

# VS Code usa el mismo motor que Chrome y guarda caches parecidas. No se ofrece cerrarlo
# (podria haber archivos sin guardar): si esta abierto, simplemente se salta.
$carpetaVSCode = "$env:APPDATA\Code"
if (Test-Path $carpetaVSCode) {
    if (Get-Process 'Code' -ErrorAction SilentlyContinue) {
        Log "  VS Code esta abierto: su cache se salta (cierralo antes de la limpieza para incluirla)" DarkYellow
    } else {
        foreach ($c in 'Cache', 'CachedData', 'Code Cache', 'GPUCache', 'CachedExtensionVSIXs') {
            $ruta = Join-Path $carpetaVSCode $c
            if (Test-Path $ruta) {
                Log "  VS Code: $ruta"
                $total += Clear-Folder $ruta
            }
        }
    }
}

# Limpia una lista de carpetas, saltando las que no existen
function Clear-Folders($carpetas) {
    $liberado = 0
    foreach ($c in $carpetas | Where-Object { Test-Path $_ }) {
        Log "  $c"
        $liberado += Clear-Folder $c
    }
    return $liberado
}

# --- Paso 5: cache de shaders de la GPU (se regenera sola) ---
Log "Paso 5: cache de shaders de la GPU" Yellow
$total += Clear-Folders @(
    "$env:LOCALAPPDATA\NVIDIA\DXCache",
    "$env:LOCALAPPDATA\NVIDIA\GLCache",
    "$env:LOCALAPPDATA\D3DSCache",
    "$env:LOCALAPPDATA\AMD\DxCache"
)

# --- Paso 6: cache de paquetes de desarrollo (pip, npm y, si se autorizo, NuGet y logs de PM2) ---
Log "Paso 6: cache de paquetes de desarrollo (pip, npm, NuGet) y logs de PM2" Yellow
$total += Clear-Folders @(
    "$env:LOCALAPPDATA\pip\Cache",
    "$env:LOCALAPPDATA\npm-cache"
)
if ($borrarNuget) {
    $total += Clear-Folders $carpetasNuget
} elseif ($carpetasNuget) {
    Log "  NuGet conservado ($(Format-Tamano $bytesNuget))" DarkGray
}
if ($borrarLogsPm2) {
    # Con PM2 en marcha sus logs estan abiertos: borrarlos no libera nada hasta reiniciarlo,
    # por eso se vacian con 'pm2 flush'. Con PM2 detenido se borran directamente.
    $pidPm2 = "$(Get-Content (Join-Path $carpetaPm2 'pm2.pid') -ErrorAction SilentlyContinue)".Trim()
    # El PID guardado puede haber quedado de otra sesion y ser ahora de otro programa: debe ser node
    $pm2Activo = $pidPm2 -match '^\d+$' -and
        [bool](Get-Process -Id $pidPm2 -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -eq 'node' })
    if (-not $pm2Activo) {
        Log "  Logs de PM2 (PM2 detenido: se borran)" Gray
        $total += Clear-Folder $carpetaLogsPm2
    } elseif (-not (Get-Command pm2 -ErrorAction SilentlyContinue)) {
        Log "  Logs de PM2 conservados: PM2 esta en marcha pero no se encontro el comando pm2" DarkYellow
    } else {
        Log "  Logs de PM2 (PM2 en marcha: pm2 flush)" Gray
        $antes = Get-FolderSize $carpetaLogsPm2
        # Sin los colores ANSI que pm2 pone en su salida
        & pm2 flush 2>&1 | ForEach-Object { "$_" -replace '\x1b\[[0-9;]*m', '' } | Where-Object { $_.Trim() } |
            ForEach-Object { Log "  $($_.Trim())" DarkGray }
        if ($LASTEXITCODE -ne 0) { Log "  pm2 flush termino con codigo $LASTEXITCODE" DarkYellow }
        $liberado = [math]::Round([math]::Max([double]0, $antes - (Get-FolderSize $carpetaLogsPm2)) / 1MB, 2)
        Log "  $liberado MB liberados" Green
        $total += $liberado
    }
} elseif ($bytesLogsPm2 -gt 0) {
    Log "  Logs de PM2 conservados ($(Format-Tamano $bytesLogsPm2))" DarkGray
}

if ($esAdmin) {
    # --- Paso 7: logs de instalacion de Windows ---
    Log "Paso 7: logs de Windows (CBS y DISM)" Yellow
    $total += Clear-Folders @(
        "$env:SystemRoot\Logs\CBS",
        "$env:SystemRoot\Logs\DISM"
    )

    # --- Paso 8: cache de Delivery Optimization (comando oficial de Windows) ---
    Log "Paso 8: cache de Delivery Optimization" Yellow
    # Se mide por el espacio libre del disco, no por el tamano de los archivos:
    # esta cache usa archivos "reservados" que aparentan pesar el tamano completo
    # de la actualizacion aunque en disco ocupen mucho menos
    $libreAntes = (Get-PSDrive C).Free
    try {
        Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
        $liberado = [math]::Round([math]::Max([double]0, (Get-PSDrive C).Free - $libreAntes) / 1MB, 2)
        Log "  $liberado MB liberados (medido por el espacio libre del disco)" Green
        $total += $liberado
    } catch {
        Log "  no se pudo vaciar: $($_.Exception.Message)" DarkYellow
    }

    # --- Paso 9 (opcional): limpieza de componentes de Windows con DISM ---
    Log "Paso 9 (opcional): limpieza profunda de componentes de Windows (DISM)" Yellow
    if ($hacerDism) {
        $libreAntes = (Get-PSDrive C).Free
        Log "  ejecutando DISM, no cierres esta ventana..."
        $codigo = Invoke-Herramienta dism.exe @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
        if ($codigo -eq 0) {
            # DISM no informa cuanto borra: se mide por el espacio libre del disco
            $liberado = [math]::Round([math]::Max([double]0, (Get-PSDrive C).Free - $libreAntes) / 1MB, 2)
            Log "  DISM terminado: $liberado MB liberados" Green
            $total += $liberado
        } else {
            Log "  DISM termino con error (codigo $codigo)" Red
        }
    } else {
        Log "  limpieza profunda omitida" DarkYellow
    }

    # --- Paso 10 (opcional): revisar y reparar archivos de Windows ---
    Log "Paso 10 (opcional): reparacion del sistema" Yellow
    if ($hacerReparacion) {
        # Punto de restauracion por si algo sale mal
        Log "  creando punto de restauracion..."
        $ultimoAntes = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber | Select-Object -Last 1
        Checkpoint-Computer -Description 'Limpieza Windows' -RestorePointType MODIFY_SETTINGS `
            -ErrorAction SilentlyContinue -ErrorVariable errRP -WarningAction SilentlyContinue
        $ultimo = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber | Select-Object -Last 1
        $fechaUltimo = if ($ultimo) { $ultimo.ConvertToDateTime($ultimo.CreationTime) }
        if ($errRP) {
            Log "  no se pudo crear: $($errRP[0].Exception.Message)" DarkYellow
            Log "  (suele ser porque la Proteccion del sistema esta desactivada en C:)" DarkYellow
        } elseif ($ultimo -and $ultimo.SequenceNumber -ne $ultimoAntes.SequenceNumber) {
            Log "  punto de restauracion creado" Green
        } elseif ($fechaUltimo -and $fechaUltimo -gt (Get-Date).AddHours(-24)) {
            # Windows solo permite uno cada 24 horas; se usa el mas reciente
            Log "  ya hay uno de las ultimas 24 h, se usa ese: $fechaUltimo" Green
        } else {
            Log "  Windows no creo el punto de restauracion (sin mensaje de error); la reparacion sigue sin el" DarkYellow
        }

        Log "  DISM: reparando la imagen de Windows (puede quedarse un rato en el mismo %)..."
        $codigo = Invoke-Herramienta dism.exe @('/Online', '/Cleanup-Image', '/RestoreHealth')
        if ($codigo -eq 0) { Log "  DISM RestoreHealth terminado" Green }
        else { Log "  DISM RestoreHealth termino con error (codigo $codigo)" Red }

        Log "  SFC: revisando archivos del sistema..."
        Invoke-Herramienta sfc.exe @('/scannow') -Unicode | Out-Null
        Log "  SFC terminado (el resultado esta en las lineas de arriba)" Green
    } else {
        Log "  reparacion omitida" DarkYellow
    }

    # --- Paso 11: limpieza de Docker ---
    # Va antes de compactar: lo que borra Docker queda libre dentro de su disco virtual,
    # y solo vuelve a Windows cuando ese disco se compacta (paso 12)
    Log "Paso 11: limpieza de Docker" Yellow
    if (-not $dockerInstalado) {
        Log "  Docker no esta instalado: se omite" DarkGray
    } elseif (-not $dockerActivo) {
        Log "  Docker no esta en marcha (Docker Desktop cerrado): se omite" DarkYellow
    } else {
        # Sin riesgo: nada de esto lo usa ningun contenedor ni contiene datos (los volumenes no se tocan nunca)
        $limpiezasDocker = @(
            @{ Texto = 'contenedores detenidos'; Argumentos = @('container', 'prune', '-f') },
            @{ Texto = 'imagenes huerfanas';     Argumentos = @('image', 'prune', '-f') },
            @{ Texto = 'cache de compilacion';   Argumentos = @('builder', 'prune', '-f') },
            @{ Texto = 'redes sin usar';         Argumentos = @('network', 'prune', '-f') }
        )
        foreach ($l in $limpiezasDocker) {
            $salida = & docker @($l.Argumentos) 2>&1
            if ($LASTEXITCODE -ne 0) {
                Log "  $($l.Texto): error (codigo $LASTEXITCODE): $(($salida | Select-Object -Last 1))" Red
                continue
            }
            # Docker informa lo recuperado en una linea "Total reclaimed space: X" o "Total: X"
            $lineaTotal = $salida | Where-Object { "$_" -match '^Total' } | Select-Object -Last 1
            if ($lineaTotal) {
                $bytes = ConvertFrom-TamanoDocker $lineaTotal
                $dockerLiberado += $bytes
                Log ("  {0}: {1:N2} MB" -f $l.Texto, ($bytes / 1MB))
            } else {
                Log "  $($l.Texto): nada que borrar"
            }
        }

        # Imagenes sin usar: solo si se autorizo, y solo las que se listaron en la pregunta
        if ($borrarImagenesDocker) {
            foreach ($img in $imagenesDockerSinUso) {
                $salida = & docker rmi $img.Nombre 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Log ("  imagen borrada: {0} ({1:N2} MB)" -f $img.Nombre, ($img.Bytes / 1MB))
                    $imagenesDockerBorradas += $img
                } else {
                    # Por ejemplo, si se empezo a usar despues de la pregunta
                    Log "  no se pudo borrar la imagen $($img.Nombre): $(($salida | Select-Object -Last 1))" DarkYellow
                }
            }
            # Las capas compartidas entre imagenes se cuentan una vez por Id; es un maximo aproximado
            $dockerLiberado += ($imagenesDockerBorradas | Sort-Object Id -Unique | Measure-Object Bytes -Sum).Sum
        } elseif ($imagenesDockerSinUso) {
            Log "  imagenes sin usar conservadas: $listaImagenes" DarkGray
        }

        Log ("  Docker: {0:N2} MB liberados dentro de su disco virtual" -f ($dockerLiberado / 1MB)) Green
        if (-not $hacerCompactar -and $dockerLiberado -gt 0) {
            Log "  (para que ese espacio vuelva a Windows hay que compactar los discos virtuales: paso 12)" DarkGray
        }
    }

    # --- Paso 12 (opcional): compactar los discos virtuales de Docker y WSL ---
    Log "Paso 12 (opcional): compactar discos virtuales de Docker/WSL" Yellow
    if ($hacerCompactar) {
        $dockerExe = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
        $dockerAbierto = [bool](Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue)

        # fstrim marca como libres los bloques borrados dentro de Linux; sin esto la compactacion no
        # recupera lo borrado (pasaba con Docker: se borraban 1.3 GB de imagenes y el disco no bajaba)
        foreach ($d in Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss -ErrorAction SilentlyContinue) {
            $distro = (Get-ItemProperty $d.PSPath).DistributionName
            if ($distro -like 'docker-desktop*') {
                # Los datos de Docker (docker_data.vhdx) estan montados en esta ruta de su maquina virtual,
                # y solo mientras Docker Desktop esta en marcha
                if (-not $dockerAbierto) {
                    Log "  Docker Desktop esta cerrado: no se puede liberar dentro de sus datos (se compacta igual, pero recupera menos)" DarkYellow
                    continue
                }
                Log "  liberando bloques sin uso dentro de los datos de Docker (fstrim)..."
                & wsl.exe -d $distro -u root -- fstrim /mnt/docker-desktop-disk 2>&1 | Out-Null
            } else {
                Log "  liberando bloques sin uso dentro de $distro (fstrim)..."
                & wsl.exe -d $distro -u root -- fstrim -a 2>&1 | Out-Null
            }
            if ($LASTEXITCODE -ne 0) {
                Log "  fstrim fallo en $distro (codigo $LASTEXITCODE): se compacta igual, pero puede recuperar menos" DarkYellow
            }
        }
        if ($dockerAbierto) {
            Log "  cerrando Docker Desktop..."
            Get-Process 'Docker Desktop', 'com.docker.backend', 'com.docker.build' -ErrorAction SilentlyContinue |
                Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Log "  apagando WSL..."
        & wsl.exe --shutdown 2>&1 | Out-Null
        Start-Sleep -Seconds 5

        foreach ($v in $discosVirtuales) {
            $antes = (Get-Item $v.Ruta).Length
            Log ("  compactando {0} ({1:N2} GB), puede tardar unos minutos..." -f $v.Nombre, ($antes / 1GB))
            $guion = Join-Path $env:TEMP 'compactar_vhdx.txt'
            Set-Content $guion -Encoding ASCII -Value @(
                "select vdisk file=`"$($v.Ruta)`"", 'attach vdisk readonly', 'compact vdisk', 'detach vdisk')
            $salida = & diskpart.exe /s $guion 2>&1
            $codigo = $LASTEXITCODE
            if ($codigo -ne 0) {
                # Si fallo a mitad, asegurarse de que el disco no quede conectado
                Set-Content $guion -Encoding ASCII -Value @("select vdisk file=`"$($v.Ruta)`"", 'detach vdisk')
                & diskpart.exe /s $guion 2>&1 | Out-Null
            }
            Remove-Item $guion -ErrorAction SilentlyContinue
            $despues = (Get-Item $v.Ruta).Length
            # Se mide por lo que achico el .vhdx (no es disperso, asi que es lo que se libero en C:).
            # El espacio libre de C: no sirve aqui: al apagar WSL, Windows borra su swap.vhdx de %TEMP%
            # unos segundos despues y eso se contaba como compactacion (~1.2 GB de mas el 17/11/2026).
            $liberado = [math]::Round([math]::Max([double]0, $antes - $despues) / 1MB, 2)
            $compactados += [pscustomobject]@{ Nombre = $v.Nombre; Antes = $antes; Despues = $despues; Ok = ($codigo -eq 0) }
            if ($codigo -eq 0) {
                Log ("  {0}: {1:N2} GB -> {2:N2} GB, {3} MB liberados" -f $v.Nombre, ($antes / 1GB), ($despues / 1GB), $liberado) Green
                $total += $liberado
            } else {
                $error1 = $salida | Where-Object { "$_".Trim() } | Select-Object -Last 2
                Log "  no se pudo compactar $($v.Nombre) (codigo $codigo): $($error1 -join ' ')" Red
            }
        }

        if ($dockerAbierto) {
            if (Test-Path $dockerExe) {
                # Abrirlo a traves del Explorador para que no quede ejecutandose como administrador
                Log "  volviendo a abrir Docker Desktop..."
                Start-Process explorer.exe -ArgumentList "`"$dockerExe`""
            } else {
                Log "  Docker Desktop estaba abierto pero no esta en $dockerExe : abrelo a mano" DarkYellow
            }
        }
    } else {
        Log "  compactacion omitida" DarkYellow
    }

    # --- Paso 13: TRIM del SSD (despues de compactar, para que el SSD sepa lo que se libero) ---
    Log "Paso 13: optimizacion (TRIM) del SSD" Yellow
    $discoC = Get-PhysicalDisk | Where-Object DeviceId -eq (Get-Partition -DriveLetter C).DiskNumber
    if ($discoC.MediaType -eq 'SSD') {
        # Sin las lineas intermedias "NN% completado..." (solo ruido en el log)
        Optimize-Volume -DriveLetter C -ReTrim -Verbose 4>&1 |
            Where-Object { "$_" -notmatch '\d+% completado\.\.\.' } |
            ForEach-Object { Log "  $_" DarkGray }
        Log "  TRIM terminado" Green
    } else {
        Log "  C: no es SSD, se omite" DarkYellow
    }

    # --- Paso 14: conservar solo los puntos de restauracion mas recientes ---
    Log "Paso 14: puntos de restauracion (se conservan los $maxPuntos mas recientes)" Yellow
    $puntos = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber)
    Log "  hay $($puntos.Count) punto(s) de restauracion"
    if ($puntos.Count -gt $maxPuntos) {
        # API oficial de Windows: borra un punto concreto por su numero, sin tocar otras instantaneas
        Add-Type -Namespace Win32 -Name SrClient -MemberDefinition `
            '[DllImport("srclient.dll")] public static extern int SRRemoveRestorePoint(int index);'
        foreach ($p in $puntos[0..($puntos.Count - $maxPuntos - 1)]) {
            $fecha = $p.ConvertToDateTime($p.CreationTime)
            $codigo = [Win32.SrClient]::SRRemoveRestorePoint([int]$p.SequenceNumber)
            if ($codigo -eq 0) { Log "  borrado el mas viejo: $fecha - $($p.Description)" DarkGray }
            else { Log "  no se pudo borrar $fecha - $($p.Description) (codigo $codigo)" DarkYellow }
        }
    }
    foreach ($p in Get-ComputerRestorePoint -ErrorAction SilentlyContinue) {
        Log "  conservado: $($p.ConvertToDateTime($p.CreationTime)) - $($p.Description)" Green
    }
} else {
    Log "Pasos 7 a 14 omitidos: no se ejecuto como administrador" Red
}

# --- Paso 15: aplicaciones desactualizadas (winget) ---
Log "Paso 15: aplicaciones desactualizadas (winget)" Yellow
$appsActualizadas = @()
$appsFallidas = @()
$appsOmitidas = @()
# Apps que se actualizan solas y que winget no debe tocar:
# - App Installer: actualizarlo cierra el propio winget a mitad de camino
# - Edge: winget falla siempre ("install technology is different"); Edge Update lo mantiene al dia
# - Spotify: su instalador se niega a correr como administrador (codigo -1978335146); se actualiza sola
$appsAutoactualizables = @{
    'Microsoft.AppInstaller' = 'se actualiza sola desde la Microsoft Store'
    'Microsoft.Edge'         = 'se actualiza sola con Edge Update'
    'Spotify.Spotify'        = 'se actualiza sola (su instalador no funciona como administrador)'
}
$appsDisponibles = @(Get-AppsDesactualizadas)
$estadoWingetInicial = $estadoWinget
if ($estadoWinget -in 'ok', 'al dia') {
    Log "  $($appsDisponibles.Count) aplicacion(es) con actualizacion disponible"
} else {
    Log "  no se pudo consultar winget: $estadoWinget" Red
}
# Se intento actualizar solo si se pidio y habia algo que actualizar (no todas pueden ser autoactualizables)
$seActualizo = $hacerActualizar -and $appsDisponibles.Count -gt 0
if ($seActualizo) {
    foreach ($app in $appsDisponibles) {
        if ($appsAutoactualizables.ContainsKey($app.Id)) {
            $motivo = $appsAutoactualizables[$app.Id]
            Log "  omitido $($app.Nombre): $motivo" DarkGray
            $appsOmitidas += $app | Add-Member -NotePropertyName Motivo -NotePropertyValue $motivo -PassThru -Force
            continue
        }
        Log "  actualizando $($app.Nombre) ($($app.Instalada) -> $($app.Disponible))..."
        $encAnterior = [Console]::OutputEncoding
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        try {
            $salida = & winget.exe upgrade --id $app.Id --exact --silent --accept-package-agreements `
                --accept-source-agreements --disable-interactivity 2>&1
        } finally {
            [Console]::OutputEncoding = $encAnterior
        }
        $codigo = $LASTEXITCODE
        # Del texto de winget solo interesa la ultima linea (el resultado); se descartan animaciones
        $resultado = $salida | ForEach-Object { ("$_" -split "`r")[-1].Trim() } |
            Where-Object { $_ -and $_ -notmatch '^[\s\-\\|/]+$' } | Select-Object -Last 1
        # Algunos instaladores terminan pidiendo reiniciar y winget lo informa con un codigo distinto de 0
        # aunque la app quedo instalada: no contarlo como error
        $instalada = ($codigo -eq 0) -or [bool]($salida -match 'Successfully installed')
        if ($instalada) {
            Log "    OK: $resultado" Green
            $appsActualizadas += $app
        } else {
            Log "    ERROR (codigo $codigo): $resultado" Red
            $appsFallidas += $app | Add-Member -NotePropertyName Motivo -NotePropertyValue $resultado -PassThru -Force
        }
    }
} elseif (-not $hacerActualizar) {
    Log "  actualizacion omitida (solo se listan en el resumen)" DarkYellow
}
# Lo que sigue pendiente despues de actualizar (sin repetir las que fallaron ni las que se actualizan solas)
$appsPendientes = if ($seActualizo) {
    @(Get-AppsDesactualizadas | Where-Object { $_.Id -notin $appsFallidas.Id -and -not $appsAutoactualizables.ContainsKey($_.Id) })
} else { $appsDisponibles }

Log "=== Limpieza completada ===" Cyan

# ======================================================================
# Resumen final (lib\resumen.ps1): va al final de todo para que quede a la vista antes de cerrar
# ======================================================================
# Programas que arrancan con Windows (solo informa, no desactiva nada)
# Solo el usuario actual y los de todo el equipo: como administrador tambien
# aparecen las cuentas internas de Windows (S-1-5-18/19/20), que no interesan
$miSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$inicio = @(Get-CimInstance Win32_StartupCommand |
    Where-Object { $_.Location -notlike 'HKU\*' -or $_.Location -like "HKU\$miSid\*" } |
    Where-Object { Test-InicioHabilitado $_ })

$unidadC = Get-PSDrive C
Show-Resumen @{
    EsAdmin          = $esAdmin
    DiscoC           = Get-PhysicalDisk | Where-Object DeviceId -eq (Get-Partition -DriveLetter C).DiskNumber
    Total            = $total
    LibreInicio      = $libreInicio
    LibreFin         = $unidadC.Free
    TamanoC          = $unidadC.Used + $unidadC.Free
    Anterior         = Get-UltimaEjecucion $archivoHistorial
    Compactados      = $compactados
    DockerInstalado  = $dockerInstalado
    DockerActivo     = $dockerActivo
    DockerLiberado   = $dockerLiberado
    DockerImagenes   = $imagenesDockerBorradas
    Inicio           = $inicio
    EstadoWinget     = $estadoWingetInicial
    SeActualizo      = $seActualizo
    AppsDisponibles  = $appsDisponibles
    AppsActualizadas = $appsActualizadas
    AppsFallidas     = $appsFallidas
    AppsPendientes   = $appsPendientes
    AppsOmitidas     = $appsOmitidas
}

# --- Historial (lib\historial.ps1): se guarda despues del resumen para incluir los avisos ---
try {
    $cantidad = Add-Ejecucion $archivoHistorial $total $unidadC.Free $avisosResumen
    Log "Historial: ejecucion guardada ($cantidad registrada(s) en historial.csv)" DarkGray
} catch {
    Log "Historial: no se pudo guardar: $($_.Exception.Message)" DarkYellow
}

# --- Envio del resumen por correo (lib\correo.ps1, configurado en correo.json) ---
try {
    $configCorreo = Get-ConfigCorreo (Join-Path $PSScriptRoot 'correo.json')
    if (-not $configCorreo) {
        Log "Correo: no configurado (no existe correo.json)" DarkGray
    } elseif ($configCorreo.activo -eq $false) {
        Log "Correo: desactivado en correo.json" DarkGray
    } else {
        $liberadoTexto = if ($total -ge 1024) { '{0:N1} GB' -f ($total / 1024) } else { '{0:N0} MB' -f $total }
        $asunto = "Limpieza $env:COMPUTERNAME - $(Get-Date -Format 'dd/MM/yyyy HH:mm') - $liberadoTexto liberados"
        if ($avisosResumen -gt 0) { $asunto += " - $avisosResumen aviso(s)" }
        $pie = "Enviado por limpiar.ps1 desde $env:COMPUTERNAME. Log completo en $logFile"
        $idCorreo = Send-ResumenCorreo $configCorreo $asunto (Get-ResumenHtml $pie)
        Log "Correo: resumen enviado a $($configCorreo.para) (id $idCorreo)" Green
    }
} catch {
    Log "Correo: no se pudo enviar el resumen: $($_.Exception.Message)" Red
}
Log "Log completo: $logFile" DarkGray
Stop-Transcript | Out-Null

Write-Host ""
# Descartar teclas presionadas durante la ejecucion, para que no cierren la ventana solas
$Host.UI.RawUI.FlushInputBuffer()
Write-Host "Presiona Enter para cerrar..." -ForegroundColor Yellow
# Solo Enter cierra: Alt+Tab, la tecla Windows, Ctrl, teclas multimedia, etc. no
do { $tecla = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } until ($tecla.VirtualKeyCode -eq 13)
