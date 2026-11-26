# Pruebas de las funciones que leen la salida de otros programas (winget, apt, Docker, reagentc).
# Son las mas fragiles: si el programa cambia su formato, tiene que fallar aqui y no en el resumen.
# Las muestras de tests\muestras imitan salidas reales, sin datos de ningun equipo.

. (Join-Path $PSScriptRoot 'cargar.ps1')

Describe 'ConvertFrom-TablaWinget (paso 16)' {
    It 'lee la tabla en ingles, con nombres que empiezan con numero y versiones con espacio' {
        $r = ConvertFrom-TablaWinget (Get-Muestra 'winget-upgrade-en.txt') 0
        $r.Estado | Should Be 'ok'
        $r.Apps.Count | Should Be 4
        $r.Apps[0].Nombre | Should Be 'Git'
        $r.Apps[0].Id | Should Be 'Git.Git'
        $r.Apps[0].Instalada | Should Be '2.45.1'
        $r.Apps[0].Disponible | Should Be '2.47.0'
        $r.Apps[1].Nombre | Should Be '7-Zip 23.01 (x64)'
        $r.Apps[2].Id | Should Be 'Ejemplo.TwoFactor'
        $r.Apps[3].Instalada | Should Be '< 8.0.40'
    }

    It 'lee la tabla en espanol, con un nombre recortado por winget' {
        $r = ConvertFrom-TablaWinget (Get-Muestra 'winget-upgrade-es.txt') 0
        $r.Estado | Should Be 'ok'
        $r.Apps.Count | Should Be 2
        $r.Apps[0].Id | Should Be 'Microsoft.VCRedist.2015+.x64'
        $r.Apps[0].Disponible | Should Be '14.42.34433.0'
        $r.Apps[1].Id | Should Be 'OpenJS.NodeJS.LTS'
    }

    It 'ignora la animacion de carga que winget escribe con retorno de carro' {
        $lineas = Get-Muestra 'winget-upgrade-en.txt'
        $lineas[0] = "   - `r   \ `r" + $lineas[0]
        $r = ConvertFrom-TablaWinget $lineas 0
        $r.Apps.Count | Should Be 4
        $r.Apps[0].Nombre | Should Be 'Git'
    }

    It 'dice "al dia" solo si winget termino bien y no hay tabla' {
        (ConvertFrom-TablaWinget @('No installed package found matching input criteria.') -1978335212).Estado | Should Be 'al dia'
        (ConvertFrom-TablaWinget @() 0).Estado | Should Be 'al dia'
    }

    It 'no dice "al dia" si winget fallo (sin internet, fuente rota...)' {
        $r = ConvertFrom-TablaWinget @('Failed when searching source: winget') -1978335217
        $r.Estado | Should Be 'error (codigo -1978335217)'
        $r.Apps.Count | Should Be 0
    }
}

Describe 'ConvertFrom-SimulacionApt (paso 12)' {
    It 'lee los paquetes a actualizar y los retenidos' {
        $r = ConvertFrom-SimulacionApt (Get-Muestra 'apt-simulacion.txt')
        $r.Paquetes.Count | Should Be 3
        $r.Paquetes[0].Nombre | Should Be 'libcurl4t64'
        $r.Paquetes[0].Instalada | Should Be '8.5.0-2ubuntu10.4'
        $r.Paquetes[0].Disponible | Should Be '8.5.0-2ubuntu10.5'
        $r.Paquetes[2].Disponible | Should Be '2024b-0ubuntu0.24.04'
        $r.Retenidos | Should Be 1
    }

    It 'sin nada que actualizar devuelve una lista vacia y 0 retenidos' {
        $r = ConvertFrom-SimulacionApt @('Reading package lists...', '0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.')
        $r.Paquetes.Count | Should Be 0
        $r.Retenidos | Should Be 0
    }

    It 'no cuenta como actualizacion un paquete nuevo (sin version instalada)' {
        $r = ConvertFrom-SimulacionApt @('Inst paquete-nuevo (1.0-1 Ubuntu:24.04/noble [amd64])')
        $r.Paquetes.Count | Should Be 0
    }
}

Describe 'ConvertFrom-TamanoDocker (paso 11)' {
    It 'usa unidades decimales, como Docker' {
        ConvertFrom-TamanoDocker '22.04MB' | Should Be 22040000
        ConvertFrom-TamanoDocker '1.368GB' | Should Be 1368000000
        ConvertFrom-TamanoDocker '512kB' | Should Be 512000
        ConvertFrom-TamanoDocker '0B' | Should Be 0
    }

    It 'lee el tamano dentro de un texto mas largo' {
        ConvertFrom-TamanoDocker 'Total reclaimed space: 1.5GB' | Should Be 1500000000
    }

    It 'devuelve 0 si no reconoce el texto' {
        ConvertFrom-TamanoDocker '' | Should Be 0
        ConvertFrom-TamanoDocker $null | Should Be 0
        ConvertFrom-TamanoDocker 'sin tamano' | Should Be 0
    }
}

Describe 'Get-EstadoWinRE (paso 17)' {
    $ingles = "Windows Recovery Environment (Windows RE) and system reset configuration`nInformation:`n`n" +
        "    Windows RE status:         {0}`n    Windows RE location:       \\?\GLOBALROOT\device\harddisk0\partition4\Recovery\WindowsRE"

    It 'reconoce habilitado y deshabilitado en ingles' {
        Get-EstadoWinRE ($ingles -f 'Enabled') | Should Be $true
        Get-EstadoWinRE ($ingles -f 'Disabled') | Should Be $false
    }

    It 'reconoce la salida en espanol' {
        Get-EstadoWinRE "    Estado de Windows RE:      Habilitado" | Should Be $true
        Get-EstadoWinRE "    Estado de Windows RE:      Deshabilitado" | Should Be $false
    }

    It 'devuelve $null si no encuentra la linea del estado' {
        Get-EstadoWinRE 'REAGENTC.EXE: acceso denegado' | Should BeNullOrEmpty
        Get-EstadoWinRE '' | Should BeNullOrEmpty
    }
}

Describe 'Get-Columna' {
    It 'devuelve texto vacio si la linea es mas corta que la columna' {
        Get-Columna 'Git' 10 20 | Should Be ''
    }

    It 'recorta hasta el final si la columna termina despues de la linea' {
        Get-Columna 'Git   2.45.1' 6 40 | Should Be '2.45.1'
    }
}
