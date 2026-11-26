# Revisa el proyecto sin ejecutar la limpieza (CLAUDE.md 8.1): sintaxis, solo ASCII, pruebas y,
# si esta instalado, PSScriptAnalyzer. Termina con codigo 1 si algo falla (lo usa el hook de git).
#   powershell -NoProfile -ExecutionPolicy Bypass -File verificar.ps1
$ErrorActionPreference = 'Stop'
$raiz = $PSScriptRoot
$fallos = 0

function Write-Resultado($ok, $texto) {
    if ($ok) { Write-Host "  [OK]    $texto" -ForegroundColor Green }
    else { Write-Host "  [FALLA] $texto" -ForegroundColor Red; $script:fallos++ }
}

$scripts = @(Get-ChildItem $raiz -Filter *.ps1) + @(Get-ChildItem (Join-Path $raiz 'lib'), (Join-Path $raiz 'tests') -Filter *.ps1)
Write-Host ''
Write-Host "Verificando $($scripts.Count) archivos .ps1" -ForegroundColor Cyan

# 1. Sintaxis (solo se analiza, no se ejecuta nada)
$conError = foreach ($s in $scripts) {
    $errores = $null
    [Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$null, [ref]$errores) | Out-Null
    foreach ($e in $errores) { "    $($s.Name):$($e.Extent.StartLineNumber): $($e.Message)" }
}
Write-Resultado (-not $conError) 'sintaxis'
$conError | ForEach-Object { Write-Host $_ -ForegroundColor Red }

# 2. Solo ASCII: PowerShell 5.1 lee el UTF-8 sin BOM como ANSI y desfigura tildes y simbolos (CLAUDE.md 6.1)
$noAscii = @(Select-String -Path $scripts.FullName -Pattern '[^\x00-\x7F]')
Write-Resultado ($noAscii.Count -eq 0) 'solo ASCII'
$noAscii | ForEach-Object { Write-Host "    $($_.Filename):$($_.LineNumber): $($_.Line.Trim())" -ForegroundColor Red }

# 3. Pruebas (Pester 3.4 viene con Windows; la sintaxis "Should Be" sirve hasta Pester 4)
$pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -le 4 } | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) {
    Write-Resultado $false 'pruebas: no se encontro Pester 3 o 4'
} else {
    Import-Module $pester -Force
    $r = Invoke-Pester -Script (Join-Path $raiz 'tests') -PassThru -Quiet
    Write-Resultado ($r.FailedCount -eq 0) "pruebas: $($r.PassedCount) correctas, $($r.FailedCount) fallidas (Pester $($pester.Version))"
    foreach ($t in $r.TestResult | Where-Object { -not $_.Passed }) {
        Write-Host "    $($t.Describe) > $($t.Name)" -ForegroundColor Red
        Write-Host "      $($t.FailureMessage)" -ForegroundColor DarkGray
    }
}

# 4. PSScriptAnalyzer: opcional (se instala aparte desde PowerShell Gallery). Solo errores y advertencias.
if (Get-Module -ListAvailable PSScriptAnalyzer) {
    $avisos = @(Invoke-ScriptAnalyzer -Path $raiz -Recurse -Severity Error, Warning)
    Write-Resultado ($avisos.Count -eq 0) "PSScriptAnalyzer: $($avisos.Count) aviso(s)"
    $avisos | ForEach-Object { Write-Host "    $($_.ScriptName):$($_.Line): [$($_.RuleName)] $($_.Message)" -ForegroundColor Yellow }
} else {
    Write-Host '  [--]    PSScriptAnalyzer no esta instalado (opcional)' -ForegroundColor DarkGray
}

Write-Host ''
if ($fallos) { Write-Host "$fallos revision(es) fallaron" -ForegroundColor Red; exit 1 }
Write-Host 'Todo bien' -ForegroundColor Green
exit 0
