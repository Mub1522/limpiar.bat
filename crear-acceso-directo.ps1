# Crea en el Escritorio un acceso directo a limpiar.bat con el icono limpiar.ico.
# Uso: clic derecho > "Ejecutar con PowerShell", o:
#   powershell -ExecutionPolicy Bypass -File crear-acceso-directo.ps1
# Si mueves la carpeta del script, vuelve a ejecutarlo (el acceso directo guarda rutas completas).

$carpeta = $PSScriptRoot
$bat = Join-Path $carpeta 'limpiar.bat'
$icono = Join-Path $carpeta 'limpiar.ico'
if (-not (Test-Path $bat)) {
    Write-Host "No se encontro limpiar.bat en $carpeta" -ForegroundColor Red
    exit 1
}

$destino = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Limpieza Windows.lnk'
$shell = New-Object -ComObject WScript.Shell
$acceso = $shell.CreateShortcut($destino)
$acceso.TargetPath = $bat
$acceso.WorkingDirectory = $carpeta
if (Test-Path $icono) { $acceso.IconLocation = "$icono,0" }
$acceso.Description = 'Limpieza y mantenimiento de Windows'
$acceso.Save()
Write-Host "Acceso directo creado: $destino" -ForegroundColor Green
