# Pruebas de las funciones que miden y borran carpetas. Trabajan solo dentro de TestDrive
# (una carpeta temporal que Pester crea y borra): nunca tocan carpetas reales del equipo.

. (Join-Path $PSScriptRoot 'cargar.ps1')

# Crea un archivo de $bytes bytes con la fecha de modificacion indicada
function New-ArchivoPrueba($ruta, $bytes, $horasAtras = 0) {
    New-Item -ItemType Directory -Force (Split-Path $ruta -Parent) | Out-Null
    [IO.File]::WriteAllBytes($ruta, (New-Object byte[] $bytes))
    (Get-Item $ruta).LastWriteTime = (Get-Date).AddHours(-$horasAtras)
}

Describe 'Get-FolderSize' {
    It 'suma los archivos de todas las subcarpetas' {
        New-ArchivoPrueba "$TestDrive\tam\a.bin" 1000
        New-ArchivoPrueba "$TestDrive\tam\sub\b.bin" 2000
        New-ArchivoPrueba "$TestDrive\tam\sub\otra\c.bin" 3000
        Get-FolderSize "$TestDrive\tam" | Should Be 6000
    }

    It 'devuelve vacio si la carpeta no existe' {
        Get-FolderSize "$TestDrive\no-existe" | Should BeNullOrEmpty
    }
}

Describe 'Clear-Folder' {
    It 'borra el contenido pero no la carpeta, y devuelve los MB liberados' {
        New-ArchivoPrueba "$TestDrive\limpiar\a.bin" 1MB
        New-ArchivoPrueba "$TestDrive\limpiar\sub\b.bin" 1MB
        $liberado = Clear-Folder "$TestDrive\limpiar"
        $liberado | Should Be 2
        Test-Path "$TestDrive\limpiar" | Should Be $true
        @(Get-ChildItem "$TestDrive\limpiar" -Force).Count | Should Be 0
    }

    It 'con -HorasMinimas conserva lo reciente (pasos 1 y 2)' {
        New-ArchivoPrueba "$TestDrive\temp\viejo.tmp" 1000 -horasAtras 48
        New-ArchivoPrueba "$TestDrive\temp\nuevo.tmp" 1000 -horasAtras 1
        Clear-Folder "$TestDrive\temp" -HorasMinimas 24 | Out-Null
        Test-Path "$TestDrive\temp\viejo.tmp" | Should Be $false
        Test-Path "$TestDrive\temp\nuevo.tmp" | Should Be $true
    }

    It 'conserva una carpeta vieja si algo dentro se modifico hace poco' {
        # Caso real: el scratchpad de Claude Code se borro a mitad de una sesion (CLAUDE.md 6.4)
        New-ArchivoPrueba "$TestDrive\temp2\programa\viejo.dat" 1000 -horasAtras 72
        New-ArchivoPrueba "$TestDrive\temp2\programa\en-uso\nuevo.dat" 1000 -horasAtras 1
        (Get-Item "$TestDrive\temp2\programa").LastWriteTime = (Get-Date).AddHours(-72)
        New-ArchivoPrueba "$TestDrive\temp2\abandonada\viejo.dat" 1000 -horasAtras 72
        (Get-Item "$TestDrive\temp2\abandonada").LastWriteTime = (Get-Date).AddHours(-72)
        Clear-Folder "$TestDrive\temp2" -HorasMinimas 24 | Out-Null
        Test-Path "$TestDrive\temp2\programa\en-uso\nuevo.dat" | Should Be $true
        Test-Path "$TestDrive\temp2\programa\viejo.dat" | Should Be $true
        Test-Path "$TestDrive\temp2\abandonada" | Should Be $false
    }

    It 'no falla si la carpeta no existe' {
        Clear-Folder "$TestDrive\no-existe" | Should Be 0
    }
}

Describe 'Clear-Folders' {
    It 'salta las carpetas que no existen y suma lo de las demas' {
        New-ArchivoPrueba "$TestDrive\varias\uno\a.bin" 1MB
        New-ArchivoPrueba "$TestDrive\varias\dos\b.bin" 1MB
        $liberado = Clear-Folders @("$TestDrive\varias\uno", "$TestDrive\varias\no-existe", "$TestDrive\varias\dos")
        $liberado | Should Be 2
    }
}

Describe 'Get-CarpetasCache (paso 4, apps de chat)' {
    $raiz = "$TestDrive\app"
    foreach ($c in 'Cache\Cache_Data', 'Code Cache\js', 'GPUCache', 'Partitions\p1\Cache', 'Local Storage\leveldb', 'Session Storage', 'cache') {
        New-Item -ItemType Directory -Force (Join-Path $raiz $c) | Out-Null
    }
    $encontradas = @(Get-CarpetasCache $raiz | ForEach-Object { Split-Path $_ -Leaf })

    It 'encuentra Cache, Code Cache y GPUCache, tambien dentro de subcarpetas' {
        $encontradas -contains 'Code Cache' | Should Be $true
        $encontradas -contains 'GPUCache' | Should Be $true
        @($encontradas | Where-Object { $_ -ceq 'Cache' }).Count | Should Be 2
    }

    It 'nunca devuelve sesiones ni datos guardados' {
        $encontradas -contains 'Local Storage' | Should Be $false
        $encontradas -contains 'Session Storage' | Should Be $false
        $encontradas -contains 'leveldb' | Should Be $false
    }

    It 'distingue mayusculas ("cache" no es una cache de Chromium)' {
        @($encontradas | Where-Object { $_ -ceq 'cache' }).Count | Should Be 0
    }

    It 'no repite carpetas que ya estan dentro de otra encontrada' {
        $encontradas -contains 'Cache_Data' | Should Be $false
        $encontradas.Count | Should Be 4
    }
}

Describe 'Format-Tamano' {
    It 'muestra MB hasta 999 MB y GB desde 1000 MB' {
        Format-Tamano 500MB | Should Be '500 MB'
        Format-Tamano 999MB | Should Be '999 MB'
        Format-Tamano 1000MB | Should Match '^0[.,]98 GB$'
        Format-Tamano 3.1GB | Should Match '^3[.,]10 GB$'
    }
}
