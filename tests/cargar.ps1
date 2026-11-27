# Carga para las pruebas las funciones de limpiar.ps1 SIN ejecutar el script (se sacan del arbol
# de sintaxis) y los modulos de lib\. Se usa con dot-sourcing al inicio de cada *.Tests.ps1.
# Log no escribe nada: las pruebas no deben llenar la consola.

$script:raizProyecto = Split-Path $PSScriptRoot -Parent
$script:muestras = Join-Path $PSScriptRoot 'muestras'

function Log($msg, $color = 'Gray') { }

$astLimpiar = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $script:raizProyecto 'limpiar.ps1'), [ref]$null, [ref]$null)
# $false: solo las funciones del script, no las que pudiera haber dentro de otras funciones
foreach ($fn in $astLimpiar.FindAll({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    if ($fn.Name -eq 'Log') { continue }
    . ([scriptblock]::Create($fn.Extent.Text))
}

foreach ($modulo in 'resumen', 'salud', 'historial', 'correo') {
    . (Join-Path $script:raizProyecto "lib\$modulo.ps1")
}

# Lee una salida real guardada en tests\muestras (UTF-8)
function Get-Muestra($nombre) {
    @(Get-Content (Join-Path $script:muestras $nombre) -Encoding UTF8)
}
