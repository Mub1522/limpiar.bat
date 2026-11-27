# Pruebas de Receive-TrabajoConLimite: las consultas en segundo plano de winget (paso 16) y de Windows
# Update (paso 17). Usan trabajos de prueba que no llaman a ningun programa.

. (Join-Path $PSScriptRoot 'cargar.ps1')

Describe 'Receive-TrabajoConLimite' {
    It 'devuelve lo que devolvio el trabajo y lo quita' {
        $t = Start-Job { [pscustomobject]@{ Codigo = 0; Salida = @('a', 'b') } }
        $r = Receive-TrabajoConLimite $t 60
        $r.Ok | Should Be $true
        @($r.Resultado)[0].Codigo | Should Be 0
        @(@($r.Resultado)[0].Salida).Count | Should Be 2
        Get-Job -Id $t.Id -ErrorAction SilentlyContinue | Should BeNullOrEmpty
    }

    It 'si no termina a tiempo lo detiene, lo quita y no espera mas' {
        $t = Start-Job { Start-Sleep 60 }
        $inicio = Get-Date
        $r = Receive-TrabajoConLimite $t 1
        ((Get-Date) - $inicio).TotalSeconds | Should BeLessThan 30
        $r.Ok | Should Be $false
        $r.Error | Should Match 'no termino'
        Get-Job -Id $t.Id -ErrorAction SilentlyContinue | Should BeNullOrEmpty
    }

    It 'si el trabajo fallo devuelve el motivo' {
        $t = Start-Job { throw 'fallo de prueba' }
        $r = Receive-TrabajoConLimite $t 60
        $r.Ok | Should Be $false
        $r.Error | Should Match 'fallo de prueba'
    }

    It 'sin trabajo (no se pudo iniciar) no falla' {
        $r = Receive-TrabajoConLimite $null 1
        $r.Ok | Should Be $false
        $r.Error | Should Be 'no se pudo iniciar'
    }
}
