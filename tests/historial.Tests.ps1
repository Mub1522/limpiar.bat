# Pruebas de lib\historial.ps1 (historial.csv, tendencia del espacio y "hace X"). Usan un CSV en TestDrive.

. (Join-Path $PSScriptRoot 'cargar.ps1')

# Escribe un historial de prueba: una fila por punto, con la fecha a $dias dias atras
function New-HistorialPrueba($ruta, $puntos) {
    $c = [Globalization.CultureInfo]::InvariantCulture
    $puntos | ForEach-Object {
        [pscustomobject]@{
            Fecha      = (Get-Date).AddDays(-$_.Dias).ToString('yyyy-MM-dd HH:mm:ss', $c)
            LiberadoMB = '100.5'
            LibreFinGB = ([double]$_.LibreGB).ToString($c)
            Avisos     = '0'
        }
    } | Export-Csv $ruta -Delimiter ';' -NoTypeInformation -Encoding UTF8
}

Describe 'Add-Ejecucion y Get-UltimaEjecucion' {
    It 'guarda y vuelve a leer la ejecucion con decimales' {
        $ruta = "TestDrive:\hist1.csv"
        Add-Ejecucion $ruta 1536.25 (150.5 * 1GB) 2 | Should Be 1
        $u = Get-UltimaEjecucion $ruta
        $u.LiberadoMB | Should Be 1536.25
        $u.LibreFinGB | Should Be 150.5
        $u.Avisos | Should Be 2
        $u.Cantidad | Should Be 1
    }

    It 'guarda los numeros con punto decimal aunque la cultura use coma' {
        $ruta = "TestDrive:\hist2.csv"
        $anterior = [Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [Threading.Thread]::CurrentThread.CurrentCulture = 'es-CO'
            Add-Ejecucion $ruta 10.5 (20.25 * 1GB) 0 | Out-Null
        } finally {
            [Threading.Thread]::CurrentThread.CurrentCulture = $anterior
        }
        (Get-Content $ruta)[1] | Should Match '"10\.5";"20\.25"'
    }

    It 'conserva solo las ultimas 200 ejecuciones' {
        $ruta = "TestDrive:\hist3.csv"
        New-HistorialPrueba $ruta (1..200 | ForEach-Object { @{ Dias = 300 - $_; LibreGB = 100 } })
        Add-Ejecucion $ruta 1 (100 * 1GB) 0 | Should Be 200
    }

    It 'devuelve $null si no hay historial o esta danado (no corta la ejecucion)' {
        Get-UltimaEjecucion "TestDrive:\no-existe.csv" | Should BeNullOrEmpty
        Set-Content "TestDrive:\danado.csv" '"Fecha";"LiberadoMB";"LibreFinGB";"Avisos"', '"ayer";"x";"y";"z"'
        Get-UltimaEjecucion "TestDrive:\danado.csv" | Should BeNullOrEmpty
    }
}

Describe 'Get-TendenciaEspacio' {
    $tamano = 500GB

    It 'calcula cuantos GB por mes se pierden (recta sobre todos los puntos)' {
        # 1 GB menos por dia = 30 GB al mes
        $ruta = "TestDrive:\tend1.csv"
        New-HistorialPrueba $ruta (@(30, 20, 10, 5) | ForEach-Object { @{ Dias = $_; LibreGB = 200 + $_ } })
        $t = Get-TendenciaEspacio $ruta (200GB) $tamano
        [math]::Round($t.GBPorMes, 1) | Should Be 30
        # Margen hasta el 15 % libre: 200 - 75 = 125 GB, a 30 GB por mes
        [math]::Round($t.Meses, 1) | Should Be 4.2
    }

    It 'si el espacio libre sube, la cifra es negativa y no estima meses' {
        $ruta = "TestDrive:\tend2.csv"
        New-HistorialPrueba $ruta (@(30, 20, 10, 5) | ForEach-Object { @{ Dias = $_; LibreGB = 200 - $_ } })
        $t = Get-TendenciaEspacio $ruta (200GB) $tamano
        $t.GBPorMes | Should BeLessThan 0
        $t.Meses | Should BeNullOrEmpty
    }

    It 'necesita 4 puntos y 14 dias de historial' {
        $ruta = "TestDrive:\tend4.csv"
        New-HistorialPrueba $ruta (@(30, 20) | ForEach-Object { @{ Dias = $_; LibreGB = 200 } })
        Get-TendenciaEspacio $ruta (200GB) $tamano | Should BeNullOrEmpty
        New-HistorialPrueba $ruta (@(10, 8, 5, 2) | ForEach-Object { @{ Dias = $_; LibreGB = 200 } })
        Get-TendenciaEspacio $ruta (200GB) $tamano | Should BeNullOrEmpty
    }

    It 'ignora lo de hace mas de 120 dias' {
        $ruta = "TestDrive:\tend5.csv"
        New-HistorialPrueba $ruta (@(200, 150, 130, 10) | ForEach-Object { @{ Dias = $_; LibreGB = 200 } })
        Get-TendenciaEspacio $ruta (200GB) $tamano | Should BeNullOrEmpty
    }
}

Describe 'Format-Hace' {
    It 'usa minutos, horas o dias segun el tiempo' {
        Format-Hace (Get-Date).AddSeconds(-10) | Should Be 'hace 1 min'
        Format-Hace (Get-Date).AddMinutes(-25) | Should Be 'hace 25 min'
        Format-Hace (Get-Date).AddMinutes(-90) | Should Be 'hace 1 hora'
        Format-Hace (Get-Date).AddHours(-20) | Should Be 'hace 20 horas'
        Format-Hace (Get-Date).AddDays(-6) | Should Be 'hace 6 dias'
    }
}
