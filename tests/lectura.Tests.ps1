# Pruebas de las funciones que leen la salida de otros programas (winget, apt, Docker, reagentc).
# Son las mas fragiles: si el programa cambia su formato, tiene que fallar aqui y no en el resumen.
# Las muestras de tests\muestras imitan salidas reales, sin datos de ningun equipo.

. (Join-Path $PSScriptRoot 'cargar.ps1')

Describe 'ConvertFrom-ResultadoWinget (paso 16)' {
    It 'cambia la ruta del log del instalador por un motivo en palabras (sin el nombre de usuario)' {
        $r = ConvertFrom-ResultadoWinget -1978335226 'El registro del instalador esta disponible en: C:\Users\alguien\AppData\Local\x.log'
        $r.Tipo | Should Be 'Fallo'
        $r.Motivo | Should Match 'estaba abierta'
        $r.Motivo | Should Not Match '\\'
    }
    It 'una version que no aplica (de pago) no es un fallo' {
        (ConvertFrom-ResultadoWinget -1978335189 'Una version mas reciente...').Tipo | Should Be 'NoAplica'
    }
    It 'reconoce la desinstalacion cancelada (1602)' {
        (ConvertFrom-ResultadoWinget -1978335184 'Error de desinstalacion con el codigo de salida: 1602').Motivo | Should Match 'cancelado'
    }
    It 'con un codigo desconocido deja el texto de winget, salvo que sea una ruta' {
        (ConvertFrom-ResultadoWinget -1 'Hash mismatch').Motivo | Should Be 'Hash mismatch (codigo -1)'
        (ConvertFrom-ResultadoWinget -1 'ver D:\logs\a.log').Motivo | Should Not Match '\\'
    }
}

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

Describe 'ConvertFrom-RespuestaSiNo (preguntas del inicio)' {
    It 'S / si en mayusculas o minusculas, con espacios' {
        ConvertFrom-RespuestaSiNo 's' | Should Be 'S'
        ConvertFrom-RespuestaSiNo ' SI ' | Should Be 'S'
    }
    It 'N / no = N; sin entrada ($null, entrada cerrada) = N para no quedar preguntando' {
        ConvertFrom-RespuestaSiNo 'n' | Should Be 'N'
        ConvertFrom-RespuestaSiNo 'NO' | Should Be 'N'
        ConvertFrom-RespuestaSiNo $null | Should Be 'N'
    }
    It 'Enter sin escribir nada no es valido: se vuelve a preguntar' {
        ConvertFrom-RespuestaSiNo '' | Should BeNullOrEmpty
        ConvertFrom-RespuestaSiNo '   ' | Should BeNullOrEmpty
    }
    It 'T / todas / todo = si a todas' {
        ConvertFrom-RespuestaSiNo 't' | Should Be 'T'
        ConvertFrom-RespuestaSiNo 'Todas' | Should Be 'T'
        ConvertFrom-RespuestaSiNo 'todo' | Should Be 'T'
    }
    It 'otra respuesta no es valida' {
        ConvertFrom-RespuestaSiNo 'sii' | Should BeNullOrEmpty
        ConvertFrom-RespuestaSiNo 'x' | Should BeNullOrEmpty
        ConvertFrom-RespuestaSiNo 'si a todas' | Should BeNullOrEmpty
    }
}

Describe 'ConvertFrom-FichaPapelera (paso 1)' {
    It 'lee la ficha de Windows 10+ (version 2)' {
        $fecha = Get-Date '2026-10-01 14:30:00'
        $ruta = 'C:\Usuario\Descargas\instalador.exe'
        $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
        $w.Write([int64]2); $w.Write([int64]123456); $w.Write([int64]$fecha.ToFileTime())
        $w.Write([int32]($ruta.Length + 1)); $w.Write([Text.Encoding]::Unicode.GetBytes($ruta + [char]0)); $w.Flush()
        $r = ConvertFrom-FichaPapelera $ms.ToArray()
        $r.Bytes | Should Be 123456
        $r.Fecha | Should Be $fecha
        $r.Ruta | Should Be $ruta
    }

    It 'lee la ficha de Windows 8.1 o anterior (version 1, ruta de largo fijo)' {
        $fecha = Get-Date '2020-01-02 03:04:05'
        $bytes = New-Object byte[] 544
        [BitConverter]::GetBytes([int64]1).CopyTo($bytes, 0)
        [BitConverter]::GetBytes([int64]42).CopyTo($bytes, 8)
        [BitConverter]::GetBytes([int64]$fecha.ToFileTime()).CopyTo($bytes, 16)
        [Text.Encoding]::Unicode.GetBytes('D:\viejo.txt').CopyTo($bytes, 24)
        $r = ConvertFrom-FichaPapelera $bytes
        $r.Ruta | Should Be 'D:\viejo.txt'
        $r.Fecha | Should Be $fecha
    }

    It 'devuelve $null si no la reconoce (muy corta, otra version o fecha invalida)' {
        ConvertFrom-FichaPapelera ([byte[]](1, 2, 3)) | Should BeNullOrEmpty
        ConvertFrom-FichaPapelera $null | Should BeNullOrEmpty
        $otra = New-Object byte[] 64
        [BitConverter]::GetBytes([int64]7).CopyTo($otra, 0)
        [BitConverter]::GetBytes([int64]1000).CopyTo($otra, 16)
        ConvertFrom-FichaPapelera $otra | Should BeNullOrEmpty
        $sinFecha = New-Object byte[] 64
        [BitConverter]::GetBytes([int64]2).CopyTo($sinFecha, 0)
        ConvertFrom-FichaPapelera $sinFecha | Should BeNullOrEmpty
    }
}

Describe 'ConvertFrom-EventoXml (paso 17, arranque)' {
    It 'lee los datos del evento por nombre' {
        $d = ConvertFrom-EventoXml ((Get-Muestra 'evento-arranque-101.xml') -join "`n")
        $d.FriendlyName | Should Be 'Programa de ejemplo'
        $d.DegradationTime | Should Be '2076'
        $d.Path | Should Be 'C:\Programas\Ejemplo\ejemplo.exe'
    }
}

# Evento de arranque ya leido (como lo devuelve Get-EventosArranque)
function New-EventoArranque($id, $diasAtras, $datos) {
    [pscustomobject]@{ Id = $id; Fecha = (Get-Date).AddDays(-$diasAtras); Datos = $datos }
}

Describe 'Get-Mediana' {
    It 'impar: el del medio; par: el promedio de los dos del medio; vacio: $null' {
        Get-Mediana @(3, 1, 2) | Should Be 2
        Get-Mediana @(4, 1, 3, 2) | Should Be 2.5
        Get-Mediana @() | Should BeNullOrEmpty
    }
}

Describe 'Get-ResumenArranque (paso 17)' {
    It 'avisa si la mediana de 30 dias empeoro 50 % y al menos 15 s' {
        $ev = @(1, 3, 5, 7 | ForEach-Object { New-EventoArranque 100 $_ @{ BootTime = '90000' } }) +
              @(40, 50, 60, 70 | ForEach-Object { New-EventoArranque 100 $_ @{ BootTime = '60000' } })
        $r = Get-ResumenArranque $ev
        $r.Mediana | Should Be 90
        $r.MedianaAntes | Should Be 60
        $r.Cantidad | Should Be 4
        $r.Ultimo | Should Be 90
        $r.MasLento | Should Be $true
    }

    It 'no avisa por una diferencia chica ni por un arranque suelto lento (usa la mediana)' {
        $ev = @(1, 3, 5 | ForEach-Object { New-EventoArranque 100 $_ @{ BootTime = '70000' } }) +
              @(New-EventoArranque 100 2 @{ BootTime = '400000' }) +
              @(40, 50, 60 | ForEach-Object { New-EventoArranque 100 $_ @{ BootTime = '60000' } })
        $r = Get-ResumenArranque $ev
        $r.Mediana | Should Be 70
        $r.MasLento | Should Be $false
    }

    It 'no avisa si empeoro 15 s o mas pero menos del 50 %' {
        $ev = @(1, 3, 5 | ForEach-Object { New-EventoArranque 100 $_ @{ BootTime = '100000' } }) +
              @(40, 50, 60 | ForEach-Object { New-EventoArranque 100 $_ @{ BootTime = '80000' } })
        (Get-ResumenArranque $ev).MasLento | Should Be $false
    }

    It 'con menos de 3 arranques en 30 dias no compara (solo el ultimo)' {
        $ev = @(
            New-EventoArranque 100 1 @{ BootTime = '50000' }
            New-EventoArranque 100 4 @{ BootTime = '80000' }
        )
        $r = Get-ResumenArranque $ev
        $r.Mediana | Should BeNullOrEmpty
        $r.Ultimo | Should Be 50
        $r.MasLento | Should Be $false
    }

    It 'sin arranques devuelve $null' {
        Get-ResumenArranque @(New-EventoArranque 101 1 @{ DegradationTime = '1000' }) | Should BeNullOrEmpty
    }
}

Describe 'Select-RetrasosArranque (paso 17)' {
    $ev = @(
        New-EventoArranque 101 2 @{ Name = 'app.exe'; FriendlyName = 'App lenta'; DegradationTime = '3000'; Path = 'C:\Programas\App\app.exe' }
        New-EventoArranque 101 9 @{ Name = 'app.exe'; FriendlyName = 'App lenta'; DegradationTime = '4000'; Path = 'C:\Programas\App\app.exe' }
        New-EventoArranque 101 3 @{ Name = 'otra.exe'; FriendlyName = 'Otra'; DegradationTime = '9000'; Path = 'D:\Otra\otra.exe' }
        New-EventoArranque 101 3 @{ Name = 'dwm.exe'; FriendlyName = 'dwm'; DegradationTime = '9999'; Path = "$env:SystemRoot\System32\dwm.exe" }
        New-EventoArranque 101 3 @{ Name = 'MsMpEng.exe'; DegradationTime = '9999'; Path = "$env:ProgramData\Microsoft\Windows Defender\Platform\MsMpEng.exe" }
        New-EventoArranque 102 3 @{ Name = 'msdriver'; DegradationTime = '9999'; CompanyName = 'Microsoft Corporation'; Path = "$env:SystemRoot\System32\drivers\x.sys" }
        New-EventoArranque 102 3 @{ Name = 'antitrampas'; FriendlyName = 'Driver de un juego'; DegradationTime = '1500'; CompanyName = 'Juegos SA'; Path = "$env:SystemRoot\System32\drivers\a.sys" }
        New-EventoArranque 101 45 @{ Name = 'vieja.exe'; DegradationTime = '99999'; Path = 'C:\Programas\vieja.exe' }
    )
    $r = Select-RetrasosArranque $ev 30

    It 'suma por programa y ordena del que mas retraso al que menos' {
        $r[0].Nombre | Should Be 'Otra'
        $r[1].Nombre | Should Be 'App lenta'
        $r[1].Segundos | Should Be 7
        $r[1].Veces | Should Be 2
    }

    It 'no cuenta lo de Windows ni de Defender, ni los drivers de Microsoft, ni lo de hace mas de 30 dias' {
        $r.Count | Should Be 3
        @($r | Where-Object { $_.Nombre -in 'dwm', 'MsMpEng.exe', 'msdriver', 'vieja.exe' }).Count | Should Be 0
    }

    It 'si cuenta los drivers que no son de Microsoft aunque esten en la carpeta de Windows' {
        $r[2].Nombre | Should Be 'Driver de un juego'
        $r[2].Tipo | Should Be 'driver'
    }
}

Describe 'ConvertFrom-PlanEnergia (paso 17)' {
    It 'lee el plan en espanol o ingles, incluido uno personalizado' {
        $r = ConvertFrom-PlanEnergia 'GUID de plan de energia: 381b4222-f694-41f0-9685-ff5bb260df2e  (Equilibrado)'
        $r.Nombre | Should Be 'Equilibrado'
        $r.AhorroEnergia | Should Be $false
        (ConvertFrom-PlanEnergia 'Power Scheme GUID: 0059706b-d9ad-4677-b01d-fc4e227b75c2  (My Custom Plan 1)').Nombre | Should Be 'My Custom Plan 1'
    }
    It 'reconoce Ahorro de energia por su GUID (no por el nombre, que cambia con el idioma)' {
        (ConvertFrom-PlanEnergia 'Power Scheme GUID: a1841308-3541-4fab-bc81-f71556f20b4a  (Power saver)').AhorroEnergia | Should Be $true
    }
    It 'devuelve $null si no la reconoce' {
        ConvertFrom-PlanEnergia 'error' | Should BeNullOrEmpty
    }
}

Describe 'Select-AppsQueFallan (paso 17)' {
    It 'solo las que fallaron 3 veces o mas, de la que mas a la que menos' {
        $fallos = @('a.exe', 'a.exe', 'a.exe', 'b.exe', 'c.exe', 'c.exe', 'c.exe', 'c.exe') | ForEach-Object { [pscustomobject]@{ App = $_ } }
        $r = Select-AppsQueFallan $fallos
        $r.Count | Should Be 2
        $r[0].App | Should Be 'c.exe'
        $r[0].Veces | Should Be 4
    }
    It 'sin fallos devuelve una lista vacia, no $null' {
        $r = Select-AppsQueFallan @()
        ($null -eq $r) | Should Be $false
        @($r).Count | Should Be 0
    }
}

Describe 'Select-UltimaPruebaMemoria (paso 17)' {
    It 'toma la ultima prueba y dice si encontro errores' {
        $ev = @(
            [pscustomobject]@{ Id = 1102; Fecha = (Get-Date).AddDays(-200) }
            [pscustomobject]@{ Id = 1201; Fecha = (Get-Date).AddDays(-10) }
            [pscustomobject]@{ Id = 2001; Fecha = (Get-Date).AddDays(-1) }
        )
        (Select-UltimaPruebaMemoria $ev).ConErrores | Should Be $false
        (Select-UltimaPruebaMemoria @($ev[0])).ConErrores | Should Be $true
    }
    It 'si nunca se hizo, $null' {
        Select-UltimaPruebaMemoria @() | Should BeNullOrEmpty
    }
}

Describe 'ConvertFrom-ObsoletoVsCode (paso 4)' {
    It 'lee las carpetas marcadas y descarta las que podrian salir de la carpeta de extensiones' {
        $r = ConvertFrom-ObsoletoVsCode '{"pub.ext-1.0.0":true,"pub.otra-2.1.3-win32-x64":true,"..\\..\\Windows":true,"..":true,".oculta":true,"a/b":true,"pub.falsa-1.0":false}'
        $r.Count | Should Be 2
        $r[0] | Should Be 'pub.ext-1.0.0'
        $r[1] | Should Be 'pub.otra-2.1.3-win32-x64'
    }
}

Describe 'ConvertFrom-BrowsersJson (paso 6)' {
    It 'devuelve las carpetas que usa una instalacion de Playwright' {
        $r = ConvertFrom-BrowsersJson '{"browsers":[{"name":"chromium","revision":"1248"},{"name":"chromium-headless-shell","revision":"1248"},{"name":"webkit","revision":"2370","revisionOverrides":{"mac14":"2251","win64":"2100"}}]}'
        $r -contains 'chromium-1248' | Should Be $true
        $r -contains 'chromium_headless_shell-1248' | Should Be $true
        $r -contains 'webkit-2100' | Should Be $true
    }
    It 'devuelve $null si no lo reconoce (y entonces no se borra nada)' {
        ConvertFrom-BrowsersJson 'no es json' | Should BeNullOrEmpty
        ConvertFrom-BrowsersJson '{"otra":1}' | Should BeNullOrEmpty
        ConvertFrom-BrowsersJson $null | Should BeNullOrEmpty
    }
}

Describe 'Select-DispositivosConProblema (paso 17)' {
    $lista = @(
        [pscustomobject]@{ Name = 'Teclado'; ConfigManagerErrorCode = 0; PNPClass = 'Keyboard'; PNPDeviceID = 'HID\A' }
        [pscustomobject]@{ Name = 'Adaptador apagado'; ConfigManagerErrorCode = 22; PNPClass = 'Net'; PNPDeviceID = 'PCI\B' }
        [pscustomobject]@{ Name = 'Mando desconectado'; ConfigManagerErrorCode = 45; PNPClass = 'HIDClass'; PNPDeviceID = 'USB\C' }
        [pscustomobject]@{ Name = 'Camara'; ConfigManagerErrorCode = 43; PNPClass = 'Camera'; PNPDeviceID = 'USB\D' }
        [pscustomobject]@{ Name = $null; ConfigManagerErrorCode = 28; PNPClass = $null; PNPDeviceID = 'ACPI\E' }
    )
    $r = Select-DispositivosConProblema $lista

    It 'ignora los que funcionan, los deshabilitados a proposito (22) y los desconectados (45)' {
        $r.Count | Should Be 2
        $r[0].Nombre | Should Be 'Camara'
        $r[0].Codigo | Should Be 43
    }

    It 'sin nombre usa el Id del dispositivo' {
        $r[1].Nombre | Should Be 'ACPI\E'
    }

    It 'si todo funciona devuelve una lista vacia, no $null (que el resumen leeria como "no se pudo leer")' {
        $vacia = Select-DispositivosConProblema @($lista[0])
        ($null -eq $vacia) | Should Be $false
        @($vacia).Count | Should Be 0
        Mock Get-CimInstance { $lista[0] }
        $leida = Get-DispositivosConProblema
        ($null -eq $leida) | Should Be $false
        @($leida).Count | Should Be 0
    }

    It 'explica los codigos conocidos y muestra el numero de los demas' {
        Get-TextoProblemaDispositivo 28 | Should Be 'sin driver'
        Get-TextoProblemaDispositivo 999 | Should Be 'codigo 999'
    }
}
