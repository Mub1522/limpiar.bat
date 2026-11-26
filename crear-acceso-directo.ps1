# Crea en el Escritorio un acceso directo a limpiar.bat con el icono limpiar.ico, y le pone ese
# mismo icono a la carpeta del script (desktop.ini). Un .bat no puede tener icono propio.
# Uso: doble clic en crear-acceso-directo.bat (lo llama con -ExecutionPolicy Bypass).
# Si mueves la carpeta, vuelve a ejecutarlo (el acceso directo guarda rutas completas;
# el icono de la carpeta usa una ruta relativa y sigue funcionando).

$carpeta = $PSScriptRoot
$bat = Join-Path $carpeta 'limpiar.bat'
$icono = Join-Path $carpeta 'limpiar.ico'
if (-not (Test-Path $bat)) {
    Write-Host "No se encontro limpiar.bat en $carpeta" -ForegroundColor Red
    exit 1
}

# --- Acceso directo en el Escritorio ---
$destino = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Limpieza Windows.lnk'
$shell = New-Object -ComObject WScript.Shell
$acceso = $shell.CreateShortcut($destino)
$acceso.TargetPath = $bat
$acceso.WorkingDirectory = $carpeta
if (Test-Path $icono) { $acceso.IconLocation = "$icono,0" }
$acceso.Description = 'Limpieza y mantenimiento de Windows'
$acceso.Save()
Write-Host "Acceso directo creado: $destino" -ForegroundColor Green

# --- Icono de la carpeta ---
# El Explorador lee desktop.ini solo si el archivo es oculto y de sistema y la carpeta tiene el
# atributo de solo lectura (en una carpeta no impide escribir: Windows lo usa como marca).
# Si ya habia un desktop.ini se conserva lo demas y solo se cambia la linea del icono.
if (Test-Path $icono) {
    $ini = Join-Path $carpeta 'desktop.ini'
    $lineaIcono = 'IconResource=limpiar.ico,0'
    $lineas = @()
    if (Test-Path $ini) {
        (Get-Item $ini -Force).Attributes = 'Normal'   # oculto y de sistema no se puede sobrescribir
        $lineas = @(Get-Content $ini | Where-Object { $_ -notmatch '^\s*IconResource\s*=' })
    }
    $iSeccion = [array]::FindIndex([string[]]$lineas, [Predicate[string]] { param($l) $l.Trim() -eq '[.ShellClassInfo]' })
    if ($iSeccion -lt 0) {
        $lineas = @('[.ShellClassInfo]', $lineaIcono) + $lineas
    } else {
        $lineas = @($lineas[0..$iSeccion]) + $lineaIcono + @($lineas | Select-Object -Skip ($iSeccion + 1))
    }
    Set-Content $ini $lineas -Encoding Unicode   # UTF-16: el formato que usa Windows en desktop.ini
    (Get-Item $ini -Force).Attributes = 'Hidden, System'
    $dir = Get-Item $carpeta
    $dir.Attributes = $dir.Attributes -bor [IO.FileAttributes]::ReadOnly
    Write-Host "Icono puesto en la carpeta: $carpeta" -ForegroundColor Green
    Write-Host '  (si el Explorador sigue mostrando la carpeta normal, presiona F5 o espera unos segundos)' -ForegroundColor DarkGray
}
