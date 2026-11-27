# Limpieza de Windows - se ejecuta desde limpiar.bat
$ErrorActionPreference = 'Continue'
# Sin permisos de administrador no se hace nada: la mayoria de los pasos los necesitan y una limpieza
# a medias deja el resumen y el historial incompletos. Se sale antes de Start-Transcript para no
# reemplazar el log de la ejecucion anterior. limpiar.bat ya pide el permiso (UAC).
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $esAdmin) {
    Write-Host 'Sin permisos de administrador: no se ejecuto la limpieza.' -ForegroundColor Red
    Write-Host 'Abrela con limpiar.bat (o el acceso directo del Escritorio) y acepta el permiso de Windows.' -ForegroundColor Gray
    Read-Host 'Presiona Enter para cerrar' | Out-Null
    exit 1
}

# Un solo log: cada ejecucion reemplaza al anterior
$logFile = Join-Path $PSScriptRoot 'limpieza.log'
Start-Transcript -Path $logFile | Out-Null

# Modulos: resumen final (consola + HTML), datos de salud, envio por correo e historial de ejecuciones
. (Join-Path $PSScriptRoot 'lib\resumen.ps1')
. (Join-Path $PSScriptRoot 'lib\salud.ps1')
. (Join-Path $PSScriptRoot 'lib\correo.ps1')
. (Join-Path $PSScriptRoot 'lib\historial.ps1')
$archivoHistorial = Join-Path $PSScriptRoot 'historial.csv'

function Log($msg, $color = 'Gray') {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg) -ForegroundColor $color
}

# Edicion rapida (QuickEdit) de la consola: un clic en la ventana la pone en "Seleccionar" y el
# siguiente Write-Host se queda esperando hasta Enter o Esc, asi que la limpieza se detiene sin avisar
# (el 26/11/2026 quedo 10 minutos parada en el paso 17). Se apaga mientras corre y se devuelve al final.
# 0x40 = ENABLE_QUICK_EDIT_MODE; 0x80 = ENABLE_EXTENDED_FLAGS (sin ella Windows ignora el cambio).
function Get-ModoSinEdicionRapida([uint32]$modo) {
    return [uint32](($modo -bor 0x80) -band (-bnot 0x40))
}

# Devuelve el modo que tenia la consola (para Restore-ModoConsola) o $null si no se pudo cambiar
function Disable-EdicionRapida {
    try {
        if (-not ('Limpieza.Consola' -as [type])) {
            Add-Type -Namespace Limpieza -Name Consola -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        }
        $entrada = [Limpieza.Consola]::GetStdHandle(-10)
        $modo = [uint32]0
        if (-not [Limpieza.Consola]::GetConsoleMode($entrada, [ref]$modo)) { return $null }
        if (-not [Limpieza.Consola]::SetConsoleMode($entrada, (Get-ModoSinEdicionRapida $modo))) { return $null }
        return $modo
    } catch { return $null }
}

function Restore-ModoConsola($modo) {
    if ($null -eq $modo) { return }
    try { [void][Limpieza.Consola]::SetConsoleMode([Limpieza.Consola]::GetStdHandle(-10), [uint32]$modo) } catch { }
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

# Cierra un programa: primero amablemente (como cerrar sus ventanas) y lo que quede abierto, a la fuerza
function Stop-Programa($proceso, $nombre) {
    Log "  cerrando $nombre..."
    Get-Process $proceso -ErrorAction SilentlyContinue | ForEach-Object { $_.CloseMainWindow() | Out-Null }
    Start-Sleep -Seconds 3
    # Lo que siga abierto (procesos en segundo plano, icono junto al reloj) se cierra a la fuerza
    Get-Process $proceso -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# Carpetas de cache de tipo Chrome (Cache, Code Cache, GPUCache) dentro de los datos de una app
# hecha con Electron o WebView2. Solo esas: nunca sesiones, mensajes ni configuracion.
function Get-CarpetasCache($raiz) {
    $encontradas = @()
    $candidatas = Get-ChildItem $raiz -Directory -Recurse -Depth 4 -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -cin 'Cache', 'Code Cache', 'GPUCache' } | Sort-Object { $_.FullName.Length }
    foreach ($d in $candidatas) {
        # Si ya esta dentro de otra carpeta de cache encontrada, esa la incluye
        if ($encontradas | Where-Object { $d.FullName.StartsWith("$_\") }) { continue }
        $encontradas += $d.FullName
    }
    $encontradas
}

# Limpia una cache con el comando oficial de su herramienta (pnpm, go) y devuelve los MB liberados,
# medidos por lo que achico su carpeta
function Invoke-LimpiezaComando($texto, $carpeta, $exe, $argumentos) {
    Log "  ${texto}: $(Split-Path $exe -Leaf) $($argumentos -join ' ')"
    $antes = Get-FolderSize $carpeta
    & $exe @argumentos 2>&1 | ForEach-Object { "$_" -replace '\x1b\[[0-9;]*m', '' } | Where-Object { $_.Trim() } |
        ForEach-Object { Log "  $($_.Trim())" DarkGray }
    if ($LASTEXITCODE -ne 0) { Log "  $exe termino con codigo $LASTEXITCODE" DarkYellow }
    $liberado = [math]::Round([math]::Max([double]0, $antes - (Get-FolderSize $carpeta)) / 1MB, 2)
    Log "  $liberado MB liberados" Green
    return $liberado
}

# Restos de la ultima actualizacion grande de Windows (cambio de version): la instalacion anterior
# (Windows.old) y los archivos temporales del instalador ($WINDOWS.~BT, $WINDOWS.~WS)
function Get-RestosActualizacion {
    foreach ($n in 'Windows.old', '$WINDOWS.~BT', '$WINDOWS.~WS') {
        $ruta = Join-Path $env:SystemDrive $n
        $item = Get-Item -LiteralPath $ruta -Force -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        [pscustomobject]@{
            Nombre   = $n
            Bytes    = [double](Get-FolderSize $ruta)
            # Algo modificado en los ultimos dias: puede ser una actualizacion en curso, o la reciente
            # que todavia se podria deshacer (Windows permite volver atras durante 10 dias)
            Reciente = Test-Reciente $item (Get-Date).AddDays(-$diasRestosActualizacion)
        }
    }
}

# Ejecuta el Liberador de espacio de Windows solo con las categorias indicadas (nombres de las claves de
# VolumeCaches) y devuelve los MB liberados. Es la forma que indica Microsoft para lo que tiene permisos
# especiales o lo que Windows registra (instalacion anterior, paquetes de drivers). Se arma un perfil
# de una sola vez (/sagerun:42) y se quita al terminar, para no dejar configuracion cambiada.
$script:raizLiberador = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
$script:marcaLiberador = 'StateFlags0042'

# Quita el perfil temporal del Liberador (/sagerun:42). Devuelve las categorias que lo tenian:
# al inicio del script sirve para limpiar lo que dejo una ejecucion cortada a mitad del paso 9.
function Remove-PerfilLiberador {
    Get-ChildItem $script:raizLiberador -ErrorAction SilentlyContinue |
        Where-Object { $null -ne (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).($script:marcaLiberador) } |
        ForEach-Object {
            Remove-ItemProperty $_.PSPath -Name $script:marcaLiberador -ErrorAction SilentlyContinue
            $_.PSChildName
        }
}

function Invoke-LiberadorEspacio($categorias, $minutosMaximo = 20) {
    $libreAntes = (Get-PSDrive C).Free
    Remove-PerfilLiberador | Out-Null
    foreach ($c in $categorias | Where-Object { Test-Path "$script:raizLiberador\$_" }) {
        Set-ItemProperty "$script:raizLiberador\$c" -Name $script:marcaLiberador -Value 2 -Type DWord
    }
    # Con tiempo maximo: el 24/11/2026 el Liberador (drivers ya reemplazados) paso mas de una hora sin
    # terminar y la ejecucion quedo trabada ahi. Se espera solo al proceso del Liberador (Start-Process
    # -Wait tambien espera a cualquier proceso que este deje abierto, y eso puede no terminar nunca).
    $proceso = Start-Process cleanmgr.exe -ArgumentList '/sagerun:42' -PassThru
    if (-not $proceso.WaitForExit($minutosMaximo * 60 * 1000)) {
        Log "  el Liberador de espacio no termino en $minutosMaximo minutos: se cierra y la limpieza sigue" DarkYellow
        Stop-Process -Id $proceso.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-PerfilLiberador | Out-Null
    # Se mide por el espacio libre del disco (el Liberador no informa cuanto borra)
    $liberado = [math]::Round([math]::Max([double]0, (Get-PSDrive C).Free - $libreAntes) / 1MB, 2)
    Log "  $liberado MB liberados (medido por el espacio libre del disco)" Green
    return $liberado
}

# Ejecuta un programa como root dentro de una distribucion WSL y devuelve su salida (lineas de texto).
# El codigo de salida queda en $LASTEXITCODE. LC_ALL=C deja la salida de apt en ingles (se lee igual
# sea cual sea el idioma de la distro); DEBIAN_FRONTEND y NEEDRESTART_MODE=l evitan que apt se quede
# esperando una respuesta.
function Invoke-Wsl($distro, $argumentos) {
    $encAnterior = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    try {
        & wsl.exe -d $distro -u root --exec env LC_ALL=C DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l @argumentos 2>&1 |
            ForEach-Object { "$_" }
    } finally {
        [Console]::OutputEncoding = $encAnterior
    }
}

# Distribuciones WSL que usan apt (Ubuntu, Debian...). Las de Docker Desktop no se tocan nunca.
function Get-DistrosApt {
    foreach ($d in Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss -ErrorAction SilentlyContinue) {
        $nombre = (Get-ItemProperty $d.PSPath).DistributionName
        if (-not $nombre -or $nombre -like 'docker-desktop*') { continue }
        Invoke-Wsl $nombre @('test', '-x', '/usr/bin/apt-get') | Out-Null
        if ($LASTEXITCODE -eq 0) { $nombre }
    }
}

# Tamano en bytes de la cache de paquetes descargados de apt dentro de una distro (0 si no se puede leer)
# Sin "| Select-Object -First": corta la tuberia y mata wsl.exe antes de que restaure el modo de la
# consola, y desde ahi cada salto de linea deja de volver al inicio (texto en escalera, 26/11/2026)
function Get-CacheApt($distro) {
    $salida = @(Invoke-Wsl $distro @('du', '-sb', '/var/cache/apt/archives'))[0]
    if ("$salida" -match '^(\d+)') { return [double]$Matches[1] }
    return 0
}

# Actualiza los paquetes instalados de una distro WSL con apt y borra los paquetes descargados.
# Solo "apt-get upgrade": no instala ni quita paquetes (eso lo hace full-upgrade, que no se usa), y
# --force-confold conserva siempre los archivos de configuracion que se hayan modificado.
function Update-PaquetesWsl($distro) {
    $r = [pscustomobject]@{ Nombre = $distro; Ok = $false; Error = ''; Paquetes = @(); Retenidos = 0; CacheBytes = 0 }
    $esperarBloqueo = @('-o', 'DPkg::Lock::Timeout=120')   # si otro apt esta trabajando, esperar hasta 2 min

    Log "  ${distro}: buscando actualizaciones (apt-get update)..."
    # --allow-releaseinfo-change-label: si un repositorio solo cambia su nombre descriptivo (paso el
    # 25/11/2026 con el PPA de PHP, que paso a "PPA for PHP (deprecated)"), apt se detiene hasta que
    # alguien lo acepte. Ese nombre no cambia lo que se instala, asi que se acepta. Los cambios de
    # origen, version o codename si siguen deteniendo el paso.
    $salida = Invoke-Wsl $distro (@('apt-get', 'update', '-q', '--allow-releaseinfo-change-label') + $esperarBloqueo)
    $codigo = $LASTEXITCODE
    $salida | Where-Object { $_ -match '^(E|W|N): ' } | ForEach-Object { Log "    $_" DarkYellow }
    if ($codigo -ne 0) {
        # Sin update no se actualiza nada, pero la cache de apt se borra igual (al final, sin riesgo)
        $ultimoError = $salida | Where-Object { $_ -match '^E: ' } | Select-Object -Last 1
        $r.Error = "apt-get update fallo (codigo $codigo)$(if ($ultimoError) { ": $ultimoError" })"
        Log "    $($r.Error)" Red
    } else {
        Update-PaquetesAptInstalados $distro $r $esperarBloqueo
    }

    # Paquetes .deb descargados: ya no hacen falta. Lo liberado queda dentro del disco virtual de la
    # distro y vuelve a Windows al compactar (paso 13)
    $cacheAntes = Get-CacheApt $distro
    Invoke-Wsl $distro @('apt-get', 'clean') | Out-Null
    $r.CacheBytes = [math]::Max([double]0, $cacheAntes - (Get-CacheApt $distro))
    Log ("    cache de apt: {0:N2} MB borrados (apt-get clean)" -f ($r.CacheBytes / 1MB)) DarkGray
    return $r
}

# Lee la salida de "apt-get -s upgrade" (simulacion): lineas "Inst paquete [version actual] (version nueva ...)"
# y el total "... and N not upgraded.". Devuelve Paquetes (Nombre, Instalada, Disponible) y Retenidos.
# Separada de la llamada a WSL para poder probarla con salidas reales guardadas (tests\).
function ConvertFrom-SimulacionApt($lineas) {
    $paquetes = @(foreach ($l in $lineas) {
        if ($l -match '^Inst (\S+) \[([^\]]+)\] \((\S+)') {
            [pscustomobject]@{ Nombre = $Matches[1]; Instalada = $Matches[2]; Disponible = $Matches[3] }
        }
    })
    $retenidos = 0
    $lineaTotal = $lineas | Where-Object { $_ -match 'and (\d+) not upgraded' } | Select-Object -Last 1
    if ($lineaTotal -match 'and (\d+) not upgraded') { $retenidos = [int]$Matches[1] }
    return [pscustomobject]@{ Paquetes = $paquetes; Retenidos = $retenidos }
}

# Parte de Update-PaquetesWsl que corre solo si apt-get update funciono: lista lo que hay para
# actualizar, lo actualiza y anota el resultado en $r
function Update-PaquetesAptInstalados($distro, $r, $esperarBloqueo) {
    # Simulacion (no cambia nada) para saber que se va a actualizar
    $simulacion = ConvertFrom-SimulacionApt (Invoke-Wsl $distro @('apt-get', '-s', 'upgrade'))
    $paquetes = $simulacion.Paquetes
    $r.Retenidos = $simulacion.Retenidos

    if (-not $paquetes) {
        Log "    todo al dia" Green
        $r.Ok = $true
    } else {
        Log "    $($paquetes.Count) paquete(s) para actualizar:"
        foreach ($p in $paquetes) { Log "      $($p.Nombre): $($p.Instalada) -> $($p.Disponible)" DarkGray }
        Log "    actualizando (apt-get upgrade), puede tardar unos minutos..."
        $salida = Invoke-Wsl $distro (@('apt-get', 'upgrade', '-y', '-q', '-o', 'Dpkg::Options::=--force-confold') + $esperarBloqueo)
        $codigo = $LASTEXITCODE
        # De la salida de apt solo se guardan errores, avisos y el total (el resto es ruido)
        $salida | Where-Object { $_ -match '^(E|W): |^dpkg: |^\d+ upgraded, ' } | ForEach-Object { Log "    $_" DarkGray }
        if ($codigo -eq 0) {
            Log "    $($paquetes.Count) paquete(s) actualizado(s)" Green
            $r.Ok = $true
            $r.Paquetes = $paquetes
        } else {
            $ultimoError = $salida | Where-Object { $_ -match '^E: ' } | Select-Object -Last 1
            $r.Error = "apt-get upgrade fallo (codigo $codigo)$(if ($ultimoError) { ": $ultimoError" })"
            Log "    $($r.Error)" Red
        }
    }
    if ($r.Retenidos -gt 0) {
        # En Ubuntu suelen ser actualizaciones escalonadas (Ubuntu las libera de a poco) y llegan en otra
        # ejecucion; si no, son paquetes que necesitan instalar o quitar otros y no se tocan
        Log "    $($r.Retenidos) paquete(s) retenido(s) por apt: no se actualizan en esta ejecucion" DarkGray
    }
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
    $tabla = ConvertFrom-TablaWinget $salida $LASTEXITCODE
    $script:estadoWinget = $tabla.Estado
    $tabla.Apps
}

# Lee la salida de "winget upgrade" (lineas de texto) y su codigo de salida. Devuelve Estado
# ('ok', 'al dia' o 'error (codigo N)') y Apps (Nombre, Id, Instalada, Disponible).
# Separada de la llamada a winget para poder probarla con salidas reales guardadas (tests\).
function ConvertFrom-TablaWinget($salida, $codigo) {
    # Quitar la animacion de carga que winget escribe con `r antes de la tabla
    $lineas = @($salida | ForEach-Object { ("$_" -split "`r")[-1] })
    $iSep = 0..($lineas.Count - 1) | Where-Object { $lineas[$_] -match '^-{10,}$' } | Select-Object -First 1
    $col = if ($null -ne $iSep -and $iSep -ge 1) {
        @([regex]::Matches($lineas[$iSep - 1], '\S+') | ForEach-Object { $_.Index })   # Nombre, Id, Version, Disponible, Origen
    }
    if (-not $col -or $col.Count -lt 5) {
        # Sin tabla: 0 o "No installed package found" (-1978335212) = no hay actualizaciones; otro codigo = fallo
        $estado = if ($codigo -eq 0 -or $codigo -eq -1978335212) { 'al dia' } else { "error (codigo $codigo)" }
        return [pscustomobject]@{ Estado = $estado; Apps = @() }
    }
    $apps = @(foreach ($l in $lineas[($iSep + 1)..($lineas.Count - 1)]) {
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
    })
    return [pscustomobject]@{ Estado = 'ok'; Apps = $apps }
}

$total = 0
$compactados = @()
$trimError = $null   # motivo si el TRIM del paso 14 falla (va al resumen)
$dockerLiberado = 0          # bytes liberados dentro del disco virtual de Docker (paso 11)
$imagenesDockerBorradas = @()
$actualizacionesWsl = @()    # resultado de apt por distribucion WSL (paso 12)
$libreInicio = (Get-PSDrive C).Free
$maxPuntos = 2         # puntos de restauracion a conservar (se borran los mas viejos)
$horasTemporales = 24  # en los pasos 1 y 2 solo se borran temporales sin modificar en este tiempo
$diasVolcados = 7      # paso 7: si hubo un pantallazo azul en estos dias, se conservan los volcados de memoria
$diasRestosActualizacion = 10  # paso 9: restos de una actualizacion grande solo se ofrecen borrar pasado este tiempo

$navegadores = @(
    @{ Nombre = 'Chrome';  Proceso = 'chrome';  Datos = "$env:LOCALAPPDATA\Google\Chrome\User Data" },
    @{ Nombre = 'Edge';    Proceso = 'msedge';  Datos = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" },
    @{ Nombre = 'Brave';   Proceso = 'brave';   Datos = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" },
    @{ Nombre = 'Firefox'; Proceso = 'firefox'; Datos = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles" }
) | Where-Object { Test-Path $_.Datos }

# Apps de chat hechas con Electron/WebView2: guardan cache igual que Chrome (se limpia en el paso 4)
$appsChat = @(
    @{ Nombre = 'Teams';           Proceso = 'ms-teams'; Datos = "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams" },
    @{ Nombre = 'Teams (clasico)'; Proceso = 'Teams';    Datos = "$env:APPDATA\Microsoft\Teams" },
    @{ Nombre = 'Discord';         Proceso = 'Discord';  Datos = "$env:APPDATA\discord" },
    @{ Nombre = 'Slack';           Proceso = 'slack';    Datos = "$env:APPDATA\Slack" }
) | Where-Object { Test-Path $_.Datos }

# ======================================================================
# Inicio: encabezado y preguntas (todas al principio, para que despues corra sola)
# ======================================================================
Write-CajaConsola 'LIMPIEZA DE WINDOWS'
Write-Host "  $env:COMPUTERNAME - $(Get-Date -Format 'dd/MM/yyyy HH:mm') - como administrador" -ForegroundColor DarkGray

# Datos que necesitan las preguntas
$discosVirtuales = @(Get-DiscosVirtuales)
$dockerInstalado = [bool](Get-Command docker -ErrorAction SilentlyContinue)
$dockerActivo = Test-DockerActivo
$imagenesDockerSinUso = if ($dockerActivo) { @(Get-ImagenesDockerSinUso) } else { @() }
$listaImagenes = ($imagenesDockerSinUso.Nombre -join ', ')
# Distribuciones WSL con apt (consultarlas arranca cada distro unos segundos)
$distrosApt = @(Get-DistrosApt)
# Cache de NuGet (.NET): paquetes descargados (respeta NUGET_PACKAGES si se cambio la carpeta) y cache HTTP
$carpetaPaquetesNuget = if ($env:NUGET_PACKAGES) { $env:NUGET_PACKAGES } else { "$HOME\.nuget\packages" }
$carpetasNuget = @($carpetaPaquetesNuget, "$env:LOCALAPPDATA\NuGet\v3-cache", "$env:LOCALAPPDATA\NuGet\plugins-cache") |
    Where-Object { Test-Path $_ }
$bytesNuget = ($carpetasNuget | ForEach-Object { Get-FolderSize $_ } | Measure-Object -Sum).Sum
# Logs de las apps de PM2 (Node.js): respeta PM2_HOME si se cambio la carpeta
$carpetaPm2 = if ($env:PM2_HOME) { $env:PM2_HOME } else { "$HOME\.pm2" }
$carpetaLogsPm2 = Join-Path $carpetaPm2 'logs'
$bytesLogsPm2 = if (Test-Path $carpetaLogsPm2) { [double](Get-FolderSize $carpetaLogsPm2) } else { 0 }
# Cache de las apps de chat: si una esta abierta, solo se pregunta si vale la pena cerrarla
foreach ($app in $appsChat) {
    $app.Carpetas = @(Get-CarpetasCache $app.Datos)
    $app.Bytes = [double](($app.Carpetas | ForEach-Object { Get-FolderSize $_ } | Measure-Object -Sum).Sum)
}
$restosActualizacion = @(Get-RestosActualizacion)

# Solo se pregunta lo que aplica en este equipo y en este momento
$preguntas = New-Object System.Collections.ArrayList
foreach ($nav in $navegadores) {
    if (Get-Process $nav.Proceso -ErrorAction SilentlyContinue) {
        [void]$preguntas.Add(@{ Clave = "nav:$($nav.Nombre)"; Titulo = "Cerrar $($nav.Nombre) para limpiar su cache"
            Detalle = @("$($nav.Nombre) esta abierto: se cerraran todas sus ventanas.", 'Si dices que no, se salta su cache.') })
    }
}
foreach ($app in $appsChat) {
    if ($app.Bytes -gt 50MB -and (Get-Process $app.Proceso -ErrorAction SilentlyContinue)) {
        [void]$preguntas.Add(@{ Clave = "app:$($app.Nombre)"; Titulo = "Cerrar $($app.Nombre) para limpiar su cache"
            Detalle = @("$($app.Nombre) esta abierto y su cache ocupa $(Format-Tamano $app.Bytes). Se cerrara y no se vuelve a abrir solo.",
                'Si estas en una llamada, responde N.') })
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
[void]$preguntas.Add(@{ Clave = 'dism'; Titulo = 'Limpieza profunda de Windows (DISM)'
    Detalle = @('Borra versiones viejas de componentes de Windows Update. Tarda 5-15 minutos.',
        'Despues no se podra desinstalar las actualizaciones ya instaladas.') })
# Restos de una actualizacion grande: solo si ninguno es reciente (actualizacion en curso o que aun se puede deshacer)
$bytesRestos = ($restosActualizacion | Measure-Object Bytes -Sum).Sum
if ($bytesRestos -gt 100MB -and -not ($restosActualizacion | Where-Object Reciente)) {
    $detalle = @('Archivos de la version anterior de Windows y de su instalador:')
    $detalle += $restosActualizacion | ForEach-Object { "  - C:\$($_.Nombre) ($(Format-Tamano $_.Bytes))" }
    $detalle += 'Despues ya no se podra volver a la version anterior de Windows. Los borra el Liberador de espacio de Windows.'
    [void]$preguntas.Add(@{ Clave = 'restos'; Titulo = 'Borrar los restos de la ultima actualizacion grande de Windows'; Detalle = $detalle })
}
[void]$preguntas.Add(@{ Clave = 'reparacion'; Titulo = 'Revisar y reparar archivos de Windows (SFC + DISM)'
    Detalle = @('Crea un punto de restauracion antes. Tarda 10-60 minutos.') })
if ($imagenesDockerSinUso) {
    # Se muestra exactamente que se borraria; despues se borran solo esas (por nombre)
    $bytesImagenes = ($imagenesDockerSinUso | Sort-Object Id -Unique | Measure-Object Bytes -Sum).Sum
    $detalle = @('Imagenes que no usa ningun contenedor:')
    $detalle += $imagenesDockerSinUso | ForEach-Object { "  - $($_.Nombre) ($(Format-Tamano $_.Bytes))" }
    $detalle += 'Total: hasta {0:N2} GB. Si se vuelven a necesitar hay que descargarlas o reconstruirlas.' -f ($bytesImagenes / 1GB)
    [void]$preguntas.Add(@{ Clave = 'imagenes'; Titulo = 'Borrar imagenes de Docker sin usar'; Detalle = $detalle })
}
if ($distrosApt) {
    [void]$preguntas.Add(@{ Clave = 'wsl'; Titulo = 'Actualizar los paquetes de Linux en WSL (apt)'
        Detalle = @("Distribuciones: $($distrosApt -join ', '). Necesita internet.",
            'Solo actualiza lo que ya esta instalado: no instala ni quita paquetes y conserva tu configuracion.') })
}
if ($discosVirtuales) {
    [void]$preguntas.Add(@{ Clave = 'compactar'; Titulo = 'Compactar los discos virtuales de Docker y WSL'
        Detalle = @('Se apagan Docker y WSL mientras tanto (los contenedores en marcha se detienen).') })
}
[void]$preguntas.Add(@{ Clave = 'actualizar'; Titulo = 'Actualizar las aplicaciones desactualizadas (winget)'
    Detalle = @('Algunas apps pueden cerrarse mientras se actualizan.') })

# Interpreta una respuesta: 'S', 'N', 'T' (si a esta y a todas las que faltan) o $null (no valida).
# Enter sin escribir nada no es valido: hay que elegir (lo pidio el usuario el 2026-11-26).
# $null (Read-Host sin entrada, por ejemplo con la entrada cerrada) = N, para no preguntar para siempre.
function ConvertFrom-RespuestaSiNo($texto) {
    if ($null -eq $texto) { return 'N' }
    $resp = "$texto".Trim()
    if ($resp -match '^(s|si)$') { return 'S' }
    if ($resp -match '^(n|no)$') { return 'N' }
    if ($resp -match '^(t|todas?|todo)$') { return 'T' }
    return $null
}

# Tarjeta de una pregunta S/N/T. Otra respuesta (o Enter sin nada) se vuelve a preguntar.
# Con -SiATodas la tarjeta se muestra igual (para que quede a la vista y en el log), pero sin preguntar.
# La respuesta se repite en su propia linea porque lo que se escribe en Read-Host no queda en el log.
function Read-SiNo($pregunta, $numero, $cantidad, [switch]$SiATodas) {
    Write-Host ''
    Write-Host ('  [{0}/{1}] {2}' -f $numero, $cantidad, $pregunta.Titulo) -ForegroundColor White
    foreach ($linea in $pregunta.Detalle) { Write-Host "        $linea" -ForegroundColor DarkGray }
    if ($SiATodas) { Write-Host '        -> SI (todas)' -ForegroundColor Green; return 'S' }
    $opciones = if ($cantidad -gt 1) { '        S/N, T = si a todas' } else { '        S/N' }
    while ($true) {
        $resp = ConvertFrom-RespuestaSiNo (Read-Host $opciones)
        if ($resp -eq 'S') { Write-Host '        -> SI' -ForegroundColor Green; return 'S' }
        if ($resp -eq 'T') { Write-Host '        -> SI (y a todas las que faltan)' -ForegroundColor Green; return 'T' }
        if ($resp -eq 'N') { Write-Host '        -> NO' -ForegroundColor DarkGray; return 'N' }
        Write-Host '        Respuesta no valida: escribe S, N o T' -ForegroundColor Yellow
    }
}

$respuestas = @{}
if ($preguntas.Count -gt 0) {
    Write-SeccionConsola 'ANTES DE EMPEZAR'
    Write-Host "  $($preguntas.Count) pregunta(s). Despues la limpieza sigue sola, sin pedir nada mas." -ForegroundColor Gray
    $siATodas = $false
    for ($i = 0; $i -lt $preguntas.Count; $i++) {
        $resp = Read-SiNo $preguntas[$i] ($i + 1) $preguntas.Count -SiATodas:$siATodas
        if ($resp -eq 'T') { $siATodas = $true }
        $respuestas[$preguntas[$i].Clave] = ($resp -ne 'N')
    }
}
$cerrarNav = @{}
foreach ($nav in $navegadores) {
    if ($respuestas.ContainsKey("nav:$($nav.Nombre)")) { $cerrarNav[$nav.Nombre] = $respuestas["nav:$($nav.Nombre)"] }
}
$cerrarApp = @{}
foreach ($app in $appsChat) { $cerrarApp[$app.Nombre] = [bool]$respuestas["app:$($app.Nombre)"] }
$borrarRestos         = [bool]$respuestas['restos']
$hacerDism            = [bool]$respuestas['dism']
$hacerReparacion      = [bool]$respuestas['reparacion']
$borrarImagenesDocker = [bool]$respuestas['imagenes']
$actualizarWsl        = [bool]$respuestas['wsl']
$hacerCompactar       = [bool]$respuestas['compactar']
$hacerActualizar      = [bool]$respuestas['actualizar']
$borrarNuget          = [bool]$respuestas['nuget']
$borrarLogsPm2        = [bool]$respuestas['pm2']

Write-SeccionConsola 'LIMPIEZA EN CURSO'
Log "Todo listo: puedes dejar la ventana y volver cuando aparezca el resumen." Cyan
# Desde aqui nadie escribe en la ventana: un clic ya no puede detener la limpieza (ver Disable-EdicionRapida)
$modoConsola = Disable-EdicionRapida
if ($null -ne $modoConsola) {
    Log "Seleccion con el mouse desactivada hasta el final (un clic en la ventana ya no detiene la limpieza)" DarkGray
} else {
    Log "No se pudo desactivar la seleccion con el mouse: no hagas clic en la ventana; si su titulo dice 'Seleccionar', presiona Esc" DarkYellow
}
# Si una ejecucion anterior se corto en medio del Liberador de espacio (paso 9), su perfil temporal quedo puesto
$marcasViejas = @(Remove-PerfilLiberador)
if ($marcasViejas) {
    Log "Se quito el perfil temporal del Liberador de espacio que dejo una ejecucion anterior cortada ($($marcasViejas -join ', '))" DarkYellow
}

# --- Paso 1: archivos temporales del usuario ---
Log "Paso 1: temporales del usuario ($env:TEMP), los de mas de $horasTemporales h" Yellow
$total += Clear-Folder $env:TEMP -HorasMinimas $horasTemporales

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
    # Sin -WarningAction, PowerShell escribe "ADVERTENCIA: Esperando a que se inicie el servicio..."
    # cada pocos segundos mientras arranca (BITS suele tardar): asusta y no dice si al final arranco.
    # En su lugar se registra el estado final.
    Start-Service $s -ErrorAction SilentlyContinue -ErrorVariable errServicio -WarningAction SilentlyContinue
    $estado = (Get-Service $s -ErrorAction SilentlyContinue).Status
    if ("$estado" -eq 'Running') { Log "  servicio $s en marcha de nuevo" }
    else {
        # No es grave: Windows lo vuelve a iniciar solo cuando lo necesita
        Log "  servicio $s quedo en estado '$estado' (Windows lo inicia solo cuando lo necesita)" DarkYellow
    }
}

# --- Paso 4: cache de navegadores y VS Code ---
# Solo cache (no toca historial, cookies, contrasenas ni sesiones)
Log "Paso 4: cache de navegadores, VS Code y apps de chat" Yellow
foreach ($nav in $navegadores) {
    # Con el navegador abierto la cache esta bloqueada: solo se cierra si se autorizo al inicio
    if (Get-Process $nav.Proceso -ErrorAction SilentlyContinue) {
        if (-not $cerrarNav[$nav.Nombre]) {
            # Sin permiso, o se abrio despues de las preguntas
            Log "  $($nav.Nombre) esta abierto y no se autorizo cerrarlo: omitido" DarkYellow
            continue
        }
        Stop-Programa $nav.Proceso $nav.Nombre
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

# Apps de chat (Teams, Discord, Slack): solo su cache de tipo Chrome. Si estan abiertas se saltan,
# salvo que se haya autorizado cerrarlas (solo se pregunta cuando la cache pasa de 50 MB)
foreach ($app in $appsChat | Where-Object { $_.Carpetas }) {
    if (Get-Process $app.Proceso -ErrorAction SilentlyContinue) {
        if (-not $cerrarApp[$app.Nombre]) {
            Log "  $($app.Nombre) esta abierto: su cache ($(Format-Tamano $app.Bytes)) se salta" DarkYellow
            continue
        }
        Stop-Programa $app.Proceso $app.Nombre
    }
    foreach ($c in $app.Carpetas | Where-Object { Test-Path $_ }) {
        Log "  $($app.Nombre): $c"
        $total += Clear-Folder $c
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
Log "Paso 6: cache de paquetes de desarrollo (pip, npm, Yarn, pnpm, Go, NuGet) y logs de PM2" Yellow
# Yarn 1: los proyectos tienen su propia copia en node_modules. La cache de Yarn 2+ (Berry) no se toca:
# con Plug'n'Play los proyectos leen los paquetes directamente de ahi y dejarian de funcionar hasta reinstalar.
$total += Clear-Folders @(
    "$env:LOCALAPPDATA\pip\Cache",
    "$env:LOCALAPPDATA\npm-cache",
    "$env:LOCALAPPDATA\Yarn\Cache"
)
# pnpm: los node_modules de los proyectos son enlaces a su almacen, asi que no se borra la carpeta;
# 'pnpm store prune' quita solo los paquetes que ya no usa ningun proyecto
# Se usa pnpm.cmd y no pnpm.ps1: el .ps1 de npm/nvm muestra los avisos de pnpm como errores rojos
# de PowerShell (NativeCommandError) y repite cada linea en el log
$exePnpm = Get-Command pnpm.cmd, pnpm.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($exePnpm) {
    $almacenPnpm = "$(& $exePnpm.Source store path 2>$null)".Trim()
    if ($almacenPnpm -and (Test-Path $almacenPnpm)) {
        $total += Invoke-LimpiezaComando 'pnpm, paquetes sin usar' $almacenPnpm $exePnpm.Source @('store', 'prune')
    }
}
# Go: cache de compilacion (se regenera al compilar). Los modulos descargados no se tocan.
if (Get-Command go -ErrorAction SilentlyContinue) {
    $cacheGo = "$(& go env GOCACHE 2>$null)".Trim()
    if ($cacheGo -and (Test-Path $cacheGo)) {
        $total += Invoke-LimpiezaComando 'Go, cache de compilacion' $cacheGo 'go' @('clean', '-cache')
    }
}
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

# --- Paso 7: logs, volcados de memoria e informes de error de Windows ---
Log "Paso 7: logs de Windows (CBS y DISM), volcados de memoria e informes de error" Yellow
$total += Clear-Folders @(
    "$env:SystemRoot\Logs\CBS",
    "$env:SystemRoot\Logs\DISM"
)
# Los volcados de memoria solo sirven para averiguar la causa de un pantallazo azul:
# si hubo uno hace poco (o no se pudo saber) se conservan
$cuelgues = Get-CuelguesRecientes $diasVolcados
if (-not $cuelgues) {
    Log "  volcados de memoria conservados: no se pudo leer el registro de eventos para saber si hubo un pantallazo azul" DarkYellow
} elseif ($cuelgues.UltimoPantallazo) {
    Log ("  volcados de memoria conservados: hubo un pantallazo azul el {0:dd/MM HH:mm} (sirven para averiguar la causa)" -f $cuelgues.UltimoPantallazo) DarkYellow
} else {
    Log "  volcados de memoria (sin pantallazos azules en los ultimos $diasVolcados dias)"
    $volcado = "$env:SystemRoot\MEMORY.DMP"
    if (Test-Path $volcado) {
        $bytes = (Get-Item $volcado -Force).Length
        Remove-Item $volcado -Force -ErrorAction SilentlyContinue -ErrorVariable err
        if ($err) { Log "  MEMORY.DMP en uso, omitido" DarkYellow }
        else {
            Log "  $volcado borrado ($(Format-Tamano $bytes))" Green
            $total += [math]::Round($bytes / 1MB, 2)
        }
    }
    $total += Clear-Folders @(
        "$env:SystemRoot\Minidump",
        "$env:SystemRoot\LiveKernelReports"
    )
}
# Informes de error de Windows ya enviados o en cola (los mismos que borra el Liberador de espacio)
$total += Clear-Folders @(
    "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
    "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"
)

# --- Paso 8: cache de Delivery Optimization (comando oficial de Windows) ---
Log "Paso 8: cache de Delivery Optimization" Yellow
# Se mide por el espacio libre del disco, no por el tamano de los archivos:
# esta cache usa archivos "reservados" que aparentan pesar el tamano completo
# de la actualizacion aunque en disco ocupen mucho menos
$libreAntes = (Get-PSDrive C).Free
try {
    # En otro proceso: la funcion escribe "Deleting..." con Write-Host, y en PS 5.1 el transcript lo
    # registra sin hora aunque se redirija (6>$null no sirve). Asi su salida llega como texto.
    $salidaDO = @(& powershell.exe -NoProfile -Command 'Delete-DeliveryOptimizationCache -Force -ErrorAction Stop' 2>&1)
    # Si falla, solo la primera linea del error (lo demas es la ubicacion y la categoria del error)
    if ($LASTEXITCODE -ne 0) { throw ("$(@($salidaDO | Where-Object { $_ -is [Management.Automation.ErrorRecord] })[0])".Trim()) }
    $liberado = [math]::Round([math]::Max([double]0, (Get-PSDrive C).Free - $libreAntes) / 1MB, 2)
    Log "  $liberado MB liberados (medido por el espacio libre del disco)" Green
    $total += $liberado
} catch {
    Log "  no se pudo vaciar: $($_.Exception.Message)" DarkYellow
}

# --- Paso 9 (opcional): limpieza de componentes de Windows con DISM ---
Log "Paso 9 (opcional): limpieza profunda de Windows (restos de actualizaciones grandes y DISM)" Yellow
# Liberador de espacio de Windows: restos de la actualizacion grande, si se autorizo.
# Sin "Device Driver Packages": en tres ejecuciones (24 y 25/11/2026) libero 0 MB y tardo mas de
# 1 hora (trabado), 9 minutos y 20 (cortado por el tiempo maximo)
$categoriasLiberador = @()
$queLiberador = @()
if ($borrarRestos) {
    $categoriasLiberador += 'Previous Installations', 'Temporary Setup Files', 'Windows Upgrade Log Files', 'Setup Log Files'
    $queLiberador += 'restos de la actualizacion grande'
}
if ($categoriasLiberador) {
    Log "  Liberador de espacio de Windows ($($queLiberador -join ' y ')), puede tardar unos minutos..."
    $total += Invoke-LiberadorEspacio $categoriasLiberador
    if ($borrarRestos) {
        foreach ($r in @(Get-RestosActualizacion)) {
            Log "  quedo C:\$($r.Nombre) ($(Format-Tamano $r.Bytes)): el Liberador no lo borro" DarkYellow
        }
    }
}
if (-not $borrarRestos -and $restosActualizacion) {
    if ($restosActualizacion | Where-Object Reciente) {
        Log "  restos de actualizaciones conservados: tienen menos de $diasRestosActualizacion dias (actualizacion en curso, o aun se puede volver atras)" DarkGray
    } else {
        Log "  restos de actualizaciones conservados ($(Format-Tamano $bytesRestos))" DarkGray
    }
}
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
        # 0x800f0806: hay actualizaciones esperando un reinicio
        if ($codigo -eq -2146498554) {
            Log "  Windows tiene operaciones pendientes: reinicia el equipo y vuelve a ejecutar la limpieza" Yellow
        }
    }
} else {
    Log "  limpieza con DISM omitida" DarkYellow
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
    $textoFechaUltimo = if ($fechaUltimo) { $fechaUltimo.ToString('dd/MM/yyyy HH:mm') }   # "$fecha" sale como mes/dia
    if ($errRP) {
        Log "  no se pudo crear: $($errRP[0].Exception.Message)" DarkYellow
        Log "  (suele ser porque la Proteccion del sistema esta desactivada en C:)" DarkYellow
    } elseif ($ultimo -and $ultimo.SequenceNumber -ne $ultimoAntes.SequenceNumber) {
        Log "  punto de restauracion creado" Green
    } elseif ($fechaUltimo -and $fechaUltimo -gt (Get-Date).AddHours(-24)) {
        # Windows solo permite uno cada 24 horas; se usa el mas reciente
        Log "  ya hay uno de las ultimas 24 h, se usa ese: $textoFechaUltimo" Green
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
# y solo vuelve a Windows cuando ese disco se compacta (paso 13)
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
        Log "  (para que ese espacio vuelva a Windows hay que compactar los discos virtuales: paso 13)" DarkGray
    }
}

# --- Paso 12 (opcional): actualizar los paquetes de Linux en WSL ---
# Va antes de compactar: WSL tiene que estar encendido, y lo que libera apt-get clean
# vuelve a Windows al compactar (paso 13)
Log "Paso 12 (opcional): paquetes de Linux en WSL (apt)" Yellow
if (-not $distrosApt) {
    Log "  no hay distribuciones WSL con apt: se omite" DarkGray
} elseif ($actualizarWsl) {
    foreach ($distro in $distrosApt) { $actualizacionesWsl += Update-PaquetesWsl $distro }
} else {
    Log "  actualizacion de WSL omitida" DarkYellow
}

# --- Paso 13 (opcional): compactar los discos virtuales de Docker y WSL ---
Log "Paso 13 (opcional): compactar discos virtuales de Docker/WSL" Yellow
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

# --- Paso 14: TRIM del SSD (despues de compactar, para que el SSD sepa lo que se libero) ---
Log "Paso 14: optimizacion (TRIM) del SSD" Yellow
$discoC = Get-PhysicalDisk | Where-Object DeviceId -eq (Get-Partition -DriveLetter C).DiskNumber
if ($discoC.MediaType -eq 'SSD') {
    # Sin las lineas de progreso ("NN% completado") ni las vacias. El informe final llega en un
    # solo mensaje con saltos de linea y tabuladores: se parte para que cada linea lleve su hora.
    $inicioTrim = Get-Date
    Optimize-Volume -DriveLetter C -ReTrim -Verbose -ErrorAction SilentlyContinue -ErrorVariable errTrim 4>&1 |
        ForEach-Object { "$_" -split "`r?`n" } |
        ForEach-Object { ($_ -replace "`t", '  ').TrimEnd() } |
        Where-Object { $_.Trim() -and $_ -notmatch '\d+% completado' } |
        ForEach-Object { Log "  $_" DarkGray }
    if ($errTrim) {
        # El error solo dice "Failed"; el motivo esta en el evento 264 del optimizador (Application).
        # Caso real del 25/11/2026: "El bit de integridad esta establecido en este volumen" (0x89000015),
        # porque C: tenia una reparacion pendiente que chkdsk no podia hacer
        $evTrim = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Microsoft-Windows-Defrag'; Id = 264; StartTime = $inicioTrim.AddSeconds(-5) } -MaxEvents 1 -ErrorAction SilentlyContinue
        $trimError = if ($evTrim) { ($evTrim.Message -split ' debido a: ', 2)[-1].Trim() } else { "$($errTrim[0].Exception.Message)".Trim() }
        Log "  el TRIM no se pudo hacer: $trimError" DarkYellow
    } else {
        Log "  TRIM terminado" Green
    }
} else {
    Log "  C: no es SSD, se omite" DarkYellow
}

# --- Paso 15: conservar solo los puntos de restauracion mas recientes ---
Log "Paso 15: puntos de restauracion (se conservan los $maxPuntos mas recientes)" Yellow
$puntos = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber)
Log "  hay $($puntos.Count) punto(s) de restauracion"
if ($puntos.Count -gt $maxPuntos) {
    # API oficial de Windows: borra un punto concreto por su numero, sin tocar otras instantaneas
    Add-Type -Namespace Win32 -Name SrClient -MemberDefinition `
        '[DllImport("srclient.dll")] public static extern int SRRemoveRestorePoint(int index);'
    foreach ($p in $puntos[0..($puntos.Count - $maxPuntos - 1)]) {
        # ToString explicito: "$fecha" usa el formato de EE. UU. (mes/dia) aunque Windows este en espanol
        $fecha = $p.ConvertToDateTime($p.CreationTime).ToString('dd/MM/yyyy HH:mm')
        $codigo = [Win32.SrClient]::SRRemoveRestorePoint([int]$p.SequenceNumber)
        if ($codigo -eq 0) { Log "  borrado el mas viejo: $fecha - $($p.Description)" DarkGray }
        else { Log "  no se pudo borrar $fecha - $($p.Description) (codigo $codigo)" DarkYellow }
    }
}
foreach ($p in Get-ComputerRestorePoint -ErrorAction SilentlyContinue) {
    Log "  conservado: $($p.ConvertToDateTime($p.CreationTime).ToString('dd/MM/yyyy HH:mm')) - $($p.Description)" Green
}

# --- Paso 16: aplicaciones desactualizadas (winget) ---
Log "Paso 16: aplicaciones desactualizadas (winget)" Yellow
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
# Apps cuyo instalador se cancela si estan abiertas, y que el script nunca cierra (puede haber archivos sin
# guardar). Id de winget -> proceso. Caso real del 26/11/2026: VS Code abierto, el instalador vio "Visual
# Studio Code esta ejecutandose", cancelo solo y winget devolvio -1978335226 con la ruta de su log como motivo.
$appsSiAbiertas = @{
    'Microsoft.VisualStudioCode' = 'Code'
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
        if ($appsSiAbiertas.ContainsKey($app.Id) -and (Get-Process $appsSiAbiertas[$app.Id] -ErrorAction SilentlyContinue)) {
            $motivo = 'estaba abierta (no se cierra): se actualiza sola o en la proxima limpieza con la app cerrada'
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
    @(Get-AppsDesactualizadas | Where-Object { $_.Id -notin $appsFallidas.Id -and $_.Id -notin $appsOmitidas.Id -and -not $appsAutoactualizables.ContainsKey($_.Id) })
} else { $appsDisponibles }
# winget a veces dice que instalo bien pero despues la sigue listando con la misma version disponible
# (le pasaba a Google Play Games: no lee bien su version). No contarla como actualizada ni como pendiente.
if ($seActualizo) {
    $sinEfecto = @($appsActualizadas | Where-Object { $_.Id -in $appsPendientes.Id })
    if ($sinEfecto) {
        $motivo = 'winget dijo que se instalo, pero la sigue listando como desactualizada'
        foreach ($app in $sinEfecto) { Log "  $($app.Nombre): $motivo" DarkYellow }
        $appsActualizadas = @($appsActualizadas | Where-Object { $_.Id -notin $sinEfecto.Id })
        $appsPendientes = @($appsPendientes | Where-Object { $_.Id -notin $sinEfecto.Id })
        $appsFallidas += $sinEfecto | Add-Member -NotePropertyName Motivo -NotePropertyValue $motivo -PassThru -Force
    }
}

# --- Paso 17: revision de salud del equipo (solo lectura: no cambia nada) ---
# Windows Update, sistema de archivos, errores de hardware, seguridad y respaldo. El resultado va al
# resumen; el detalle (titulos de actualizaciones, etc.) queda aqui en el log.
Log "Paso 17: revision de salud del equipo (solo lectura)" Yellow
$discoSistema = Get-PhysicalDisk | Where-Object DeviceId -eq (Get-Partition -DriveLetter C).DiskNumber
$salud = Get-SaludEquipo $discoSistema $true

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
    EsAdmin          = $true
    DiscoC           = $discoSistema
    Salud            = $salud
    Total            = $total
    LibreInicio      = $libreInicio
    LibreFin         = $unidadC.Free
    TamanoC          = $unidadC.Used + $unidadC.Free
    Anterior         = Get-UltimaEjecucion $archivoHistorial
    Tendencia        = Get-TendenciaEspacio $archivoHistorial $unidadC.Free ($unidadC.Used + $unidadC.Free)
    Compactados      = $compactados
    TrimError        = $trimError
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
    DistrosApt       = $distrosApt
    ActualizarWsl    = $actualizarWsl
    ActualizacionesWsl = $actualizacionesWsl
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
# Ya no se escribe nada mas: se devuelve la seleccion con el mouse para poder copiar el resumen
Restore-ModoConsola $modoConsola

Write-Host ""
# Descartar teclas presionadas durante la ejecucion, para que no cierren la ventana solas
$Host.UI.RawUI.FlushInputBuffer()
Write-Host "Presiona Enter para cerrar..." -ForegroundColor Yellow
# Solo Enter cierra: Alt+Tab, la tecla Windows, Ctrl, teclas multimedia, etc. no
do { $tecla = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } until ($tecla.VirtualKeyCode -eq 13)
