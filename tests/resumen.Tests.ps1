# Pruebas de lib\resumen.ps1: que cada bloque escriba en consola y en el correo, y que solo
# AVISO cuente para el asunto del correo.

. (Join-Path $PSScriptRoot 'cargar.ps1')

Describe 'Write-Estado' {
    Mock Out-Resumen { }

    It 'solo AVISO suma al contador del asunto del correo' {
        $script:avisosResumen = 0
        Write-Estado 'OK' 'Disco' 'bien'
        Write-Estado 'INFO' 'Respaldo' 'sin OneDrive'
        Write-Estado 'NA' 'Bateria' 'N/D'
        $script:avisosResumen | Should Be 0
        Write-Estado 'AVISO' 'Espacio' 'queda poco'
        $script:avisosResumen | Should Be 1
    }

    It 'escribe la misma linea en la consola y en el correo' {
        $script:resumenHtml = New-Object Text.StringBuilder
        Write-Estado 'AVISO' 'Windows Update' '2 fallaron'
        Assert-MockCalled Out-Resumen -Scope It -Times 1 -ParameterFilter { $texto -match 'Windows Update' -and $texto -match '2 fallaron' }
        $html = $script:resumenHtml.ToString()
        $html | Should Match 'Windows Update'
        $html | Should Match '2 fallaron'
        $html | Should Match '>AVISO<'
    }

    It 'escapa el texto en el HTML del correo' {
        $script:resumenHtml = New-Object Text.StringBuilder
        Write-Estado 'INFO' 'App <script>' 'a & b'
        $html = $script:resumenHtml.ToString()
        $html | Should Not Match '<script>'
        $html | Should Match '&lt;script&gt;'
        $html | Should Match 'a &amp; b'
    }
}

Describe 'Write-Dato' {
    Mock Out-Resumen { }

    It 'escribe en la consola y en el correo' {
        $script:resumenHtml = New-Object Text.StringBuilder
        Write-Dato 'Liberado' '3.10 GB' Green
        Assert-MockCalled Out-Resumen -Scope It -Times 1 -ParameterFilter { $texto -match 'Liberado \.+ 3\.10 GB' }
        $script:resumenHtml.ToString() | Should Match '3\.10 GB'
    }
}

Describe 'Format-Ancho' {
    It 'rellena hasta el ancho' {
        (Format-Ancho 'Git' 10).Length | Should Be 10
    }

    It 'recorta con "..." y deja un espacio antes de la columna siguiente' {
        $t = Format-Ancho 'Microsoft Visual C++ 2015-2022' 12
        $t.Length | Should Be 12
        $t | Should Be 'Microsof... '
    }
}
