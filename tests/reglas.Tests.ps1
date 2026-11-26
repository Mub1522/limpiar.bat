# Guardas de "Lo que NO hace" (CLAUDE.md 2.2 y 6): falla si el codigo vuelve a usar un comando que
# se rechazo a proposito. Se revisa el codigo sin comentarios (los comentarios si pueden nombrarlos
# para explicar por que no se usan). Si una regla cambia porque el usuario lo pidio, se cambia aqui.

. (Join-Path $PSScriptRoot 'cargar.ps1')

# Codigo de un .ps1 sin comentarios, sin comillas y sin comas: @('volume', 'prune') queda "volume prune"
function Get-CodigoSinComentarios($ruta) {
    $tokens = $null
    [Management.Automation.Language.Parser]::ParseFile($ruta, [ref]$tokens, [ref]$null) | Out-Null
    $texto = [IO.File]::ReadAllText($ruta)
    $partes = New-Object Text.StringBuilder
    $desde = 0
    foreach ($t in $tokens | Where-Object { $_.Kind -eq 'Comment' }) {
        [void]$partes.Append($texto.Substring($desde, $t.Extent.StartOffset - $desde))
        $desde = $t.Extent.EndOffset
    }
    [void]$partes.Append($texto.Substring($desde))
    return ($partes.ToString() -replace '[''"]', '' -replace '\s*,\s*', ' ')
}

$archivos = @(Join-Path $script:raizProyecto 'limpiar.ps1') + @(Get-ChildItem (Join-Path $script:raizProyecto 'lib') -Filter *.ps1 | ForEach-Object FullName)
$codigo = ($archivos | ForEach-Object { Get-CodigoSinComentarios $_ }) -join "`n"

Describe 'Lo que el script no hace (CLAUDE.md 2.2)' {
    $prohibidos = @(
        @{ Patron = 'volume\s+prune';              Motivo = 'los volumenes de Docker guardan las bases de datos de los proyectos' },
        @{ Patron = 'system\s+prune';              Motivo = 'docker system prune puede borrar volumenes e imagenes en uso' },
        @{ Patron = 'prune\s+(-\w*a\b|--all)';     Motivo = 'las imagenes sin usar se borran solo por nombre y con permiso' },
        @{ Patron = 'full-upgrade|dist-upgrade';   Motivo = 'instalan o quitan paquetes de WSL' },
        @{ Patron = 'autoremove';                  Motivo = 'quita paquetes de WSL de los que pueden depender los proyectos' },
        @{ Patron = 'releaseinfo-change(?!-label)'; Motivo = 'solo se acepta el cambio de etiqueta del repositorio' },
        @{ Patron = 'Device Driver Packages';      Motivo = 'libero 0 MB y trabo el Liberador mas de una hora (24/11/2026)' },
        @{ Patron = 'Windows\\Installer|PatchCache'; Motivo = 'sin esos archivos no se pueden reparar ni desinstalar programas' },
        @{ Patron = 'thumbcache';                  Motivo = 'exige cerrar el Explorador y libera muy poco' },
        @{ Patron = '\bdefrag\b|Optimize-Volume(?![^\r\n]*-ReTrim)'; Motivo = 'en un SSD desfragmentar gasta vida util: solo TRIM' },
        @{ Patron = 'Set-Service|Disable-ScheduledTask'; Motivo = 'no se desactivan servicios ni tareas' },
        @{ Patron = 'Stop-Programa\s+Code\b';      Motivo = 'VS Code puede tener archivos sin guardar' },
        @{ Patron = 'Write-Host[^\r\n]*-NoNewline'; Motivo = 'el transcript de PS 5.1 corta la linea (CLAUDE.md 6.2)' },
        @{ Patron = 'wsl\.exe[^\r\n]*\|\s*Select-Object\s+-First'; Motivo = 'mata wsl.exe y deja la consola en escalera (CLAUDE.md 6.1)' },
        @{ Patron = 'Remove-Item[^\r\n]*(Windows\.old|WINDOWS\.~)'; Motivo = 'los restos de actualizacion solo los borra el Liberador de espacio' }
    )
    foreach ($p in $prohibidos) {
        It "no usa /$($p.Patron)/: $($p.Motivo)" {
            $encontrado = [regex]::Matches($codigo, $p.Patron) | ForEach-Object { $_.Value }
            $encontrado | Should BeNullOrEmpty
        }
    }
}

Describe 'La guarda detecta lo que tiene que detectar' {
    It 'encuentra un comando prohibido en el codigo aunque este armado como lista' {
        $ruta = "TestDrive:\prueba.ps1"
        Set-Content $ruta "# docker volume prune en un comentario no cuenta`n& docker @('volume', 'prune', '-f')"
        $c = Get-CodigoSinComentarios (Resolve-Path $ruta).ProviderPath
        $c | Should Match 'volume\s+prune'
        ($c -split "`n")[0] | Should Not Match 'prune'
    }
}

Describe 'Sin permisos de administrador no se hace nada' {
    $principal = [IO.File]::ReadAllText((Join-Path $script:raizProyecto 'limpiar.ps1'))
    $inicioLog = [regex]::Match($principal, '(?m)^Start-Transcript').Index

    It 'sale antes de empezar el log (asi no reemplaza el de la ejecucion anterior)' {
        $guarda = [regex]::Match($principal, 'if \(-not \$esAdmin\) \{[^}]*\bexit 1\b')
        $guarda.Success | Should Be $true
        ($guarda.Index -lt $inicioLog) | Should Be $true
    }
    It 'no vuelve a tener pasos que solo corren con administrador (ya no hay modo a medias)' {
        $principal | Should Not Match 'if \(\$esAdmin\)'
    }
}
