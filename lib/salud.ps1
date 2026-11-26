# Datos de salud del equipo para el resumen final (todo de solo lectura: aqui no se cambia nada).
# Get-SaludEquipo junta todo y deja el detalle en el log (paso 17); lib\resumen.ps1 lo muestra.
# Se carga con dot-sourcing desde limpiar.ps1 (usa su funcion Log).

# Lee el estado de WinRE de la salida de "reagentc /info". Solo mira la linea del estado
# ("Windows RE status: Enabled" / "Estado de Windows RE: Enabled"), no el resto del texto.
# Devuelve $true, $false o $null si no se reconoce.
function Get-EstadoWinRE($texto) {
    foreach ($linea in "$texto" -split "`n") {
        if ($linea -match '(status|estado)[^:]*:\s*(\S+)') {
            if ($Matches[2] -match '^(Enabled|Habilitado)$') { return $true }
            if ($Matches[2] -match '^(Disabled|Deshabilitado)$') { return $false }
        }
    }
    return $null
}

# Eventos del registro System de los ultimos $dias dias. Devuelve $null si no se pudo leer el registro.
# Sin try/catch: un error atrapado igual queda escrito en el log.
function Get-EventosSistema($filtro, $dias) {
    $filtro = $filtro.Clone()
    $filtro.LogName = 'System'
    $filtro.StartTime = (Get-Date).AddDays(-$dias)
    $eventos = @(Get-WinEvent -FilterHashtable $filtro -ErrorAction SilentlyContinue -ErrorVariable errEventos)
    # "No hay eventos" tambien llega como error (en cualquier idioma); se reconoce por su Id
    if ($errEventos -and $errEventos[0].FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { return $null }
    # La coma evita que una lista vacia se convierta en $null al devolverla
    return , $eventos
}

# Pantallazos azules y apagados sin cerrar bien de los ultimos $dias dias:
#   1001 de WER-SystemErrorReporting = pantallazo azul (BugCheck)
#   41 de Kernel-Power = Windows se reinicio sin cerrar bien (tras un pantallazo, un corte de luz,
#   manteniendo el boton de encendido...). El 6008 no se cuenta: acompana al 41 y se contaria doble.
# Lo usa tambien el paso 7 para no borrar los volcados de memoria de un pantallazo reciente.
function Get-CuelguesRecientes($dias = 30) {
    $eventos = Get-EventosSistema @{ Id = 41, 1001 } $dias
    if ($null -eq $eventos) { return $null }
    $pantallazos = @($eventos | Where-Object { $_.Id -eq 1001 -and $_.ProviderName -eq 'Microsoft-Windows-WER-SystemErrorReporting' })
    $apagados = @($eventos | Where-Object { $_.Id -eq 41 -and $_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' })
    [pscustomobject]@{
        Pantallazos      = $pantallazos.Count
        # Un pantallazo azul tambien deja un 41: se restan para no contarlo dos veces
        OtrosApagados    = [math]::Max(0, $apagados.Count - $pantallazos.Count)
        Ultimo           = (@($pantallazos) + @($apagados) | Sort-Object TimeCreated | Select-Object -Last 1).TimeCreated
        UltimoPantallazo = ($pantallazos | Sort-Object TimeCreated | Select-Object -Last 1).TimeCreated
    }
}

# Errores de hardware que Windows registra (WHEA): memoria RAM, CPU, PCIe, discos.
#   Nivel 2 (error) = no se pudo corregir: grave.
#   Nivel 3 (advertencia) = el hardware lo corrigio: unos pocos son normales; muchos anuncian una falla.
function Get-ErroresHardware($dias = 30) {
    $eventos = Get-EventosSistema @{ ProviderName = 'Microsoft-Windows-WHEA-Logger' } $dias
    if ($null -eq $eventos) { return $null }
    [pscustomobject]@{
        Graves     = @($eventos | Where-Object { $_.Level -in 1, 2 }).Count
        Corregidos = @($eventos | Where-Object { $_.Level -eq 3 }).Count
        Ultimo     = ($eventos | Sort-Object TimeCreated | Select-Object -Last 1).TimeCreated
    }
}

# Estado del antivirus de Windows (Defender). $null si no se pudo leer (por ejemplo, desinstalado por otro antivirus).
function Get-EstadoDefender {
    $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue -ErrorVariable errMp
    if ($errMp -or -not $mp) { return $null }
    [pscustomobject]@{
        Modo        = "$($mp.AMRunningMode)"   # 'Normal'; 'Passive' u otro si hay otro antivirus a cargo
        TiempoReal  = [bool]$mp.RealTimeProtectionEnabled
        DiasFirmas  = [int]$mp.AntivirusSignatureAge   # 65535 si nunca se actualizaron
        FechaFirmas = $mp.AntivirusSignatureLastUpdated
    }
}

# Version de Windows legible: "Windows 11 26H2" y la compilacion completa
function Get-VersionWindows {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    if (-not $cv) { return $null }
    # Windows 11 sigue diciendo "Windows 10" en ProductName; se distingue por la compilacion
    $nombre = if ([int]$cv.CurrentBuild -ge 22000) { 'Windows 11' } else { 'Windows 10' }
    [pscustomobject]@{
        Nombre      = "$nombre $($cv.DisplayVersion)".Trim()
        Compilacion = "$($cv.CurrentBuild).$($cv.UBR)"
    }
}

# Windows Update con su API oficial (la misma que usa Configuracion): actualizaciones pendientes,
# fecha de la ultima instalada y las que fallaron hace poco y no se volvieron a instalar despues.
# Solo consulta: no descarga ni instala nada. La busqueda puede tardar un par de minutos.
function Get-EstadoWindowsUpdate {
    try {
        $buscador = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $cantidad = $buscador.GetTotalHistoryCount()
        $historial = if ($cantidad -gt 0) { @($buscador.QueryHistory(0, [math]::Min($cantidad, 200))) } else { @() }
        $encontradas = @($buscador.Search('IsInstalled=0 and IsHidden=0').Updates)
    } catch {
        return [pscustomobject]@{ Error = $_.Exception.Message }
    }
    # Operation 1 = instalacion. ResultCode 2 = correcta, 3 = correcta con errores, 4 = fallo.
    # Las fechas del historial vienen en hora UTC.
    $instalaciones = @($historial | Where-Object { $_.Operation -eq 1 } | ForEach-Object {
        [pscustomobject]@{ Titulo = $_.Title; Fecha = $_.Date.ToLocalTime(); Resultado = $_.ResultCode }
    })
    $correctas = @($instalaciones | Where-Object { $_.Resultado -in 2, 3 })
    # Las que fallaron en 30 dias y no se instalaron bien despues (Windows suele reintentar y lograrlo)
    $fallidas = @($instalaciones | Where-Object { $_.Resultado -eq 4 -and $_.Fecha -gt (Get-Date).AddDays(-30) } |
        Where-Object { $f = $_; -not ($correctas | Where-Object { $_.Titulo -eq $f.Titulo -and $_.Fecha -gt $f.Fecha }) } |
        Sort-Object Titulo -Unique)
    [pscustomobject]@{
        Error           = $null
        # BrowseOnly = opcional (vistas previas, algunos drivers): Windows no las instala solo
        Pendientes      = @($encontradas | Where-Object { -not $_.BrowseOnly } | ForEach-Object { $_.Title })
        Opcionales      = @($encontradas | Where-Object { $_.BrowseOnly } | ForEach-Object { $_.Title })
        UltimaInstalada = ($correctas | Sort-Object Fecha | Select-Object -Last 1).Fecha
        Fallidas        = @($fallidas | ForEach-Object { $_.Titulo })
    }
}

# Firewall, control de cuentas (UAC), Arranque seguro y cifrado del disco C: (BitLocker)
function Get-EstadoSeguridad($esAdmin) {
    $nombresRed = @{ Domain = 'dominio'; Private = 'privada'; Public = 'publica' }
    $perfiles = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
    $uac = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue).EnableLUA
    $arranque = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue).UEFISecureBootEnabled
    # BitLocker solo se puede leer como administrador (y en Windows Home no existe el comando)
    $cifrado = $null
    if ($esAdmin -and (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
        $v = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
        if ($v) { $cifrado = "$($v.ProtectionStatus)" -eq 'On' }
    }
    [pscustomobject]@{
        FirewallLeido    = $perfiles.Count -gt 0
        FirewallApagado  = @($perfiles | Where-Object { "$($_.Enabled)" -eq 'False' } | ForEach-Object { $nombresRed["$($_.Name)"] })
        UacActivo        = $uac -ne 0       # sin el valor, Windows lo tiene activo
        ArranqueSeguro   = if ($null -eq $arranque) { $null } else { $arranque -eq 1 }   # $null: equipo sin UEFI
        DiscoCifrado     = $cifrado
    }
}

# Respaldo de los archivos personales: si Documentos y Escritorio estan dentro de OneDrive (y OneDrive
# abierto para que sincronice) o si el Historial de archivos esta configurado. Ademas, el punto de
# restauracion mas reciente (solo administrador).
function Get-EstadoRespaldo($esAdmin) {
    $raicesOneDrive = @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial) | Where-Object { $_ } | Select-Object -Unique
    $carpetas = @{ Documentos = [Environment]::GetFolderPath('MyDocuments'); Escritorio = [Environment]::GetFolderPath('Desktop') }
    $enOneDrive = @($carpetas.Keys | Where-Object {
        $ruta = $carpetas[$_]; [bool]($raicesOneDrive | Where-Object { $ruta.StartsWith("$_\", 'OrdinalIgnoreCase') })
    })
    $punto = $null
    if ($esAdmin) {
        $p = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber | Select-Object -Last 1
        if ($p) { $punto = $p.ConvertToDateTime($p.CreationTime) }
    }
    [pscustomobject]@{
        EnOneDrive         = $enOneDrive | Sort-Object
        OneDriveAbierto    = [bool](Get-Process OneDrive -ErrorAction SilentlyContinue)
        HistorialArchivos  = Test-Path "$env:LOCALAPPDATA\Microsoft\Windows\FileHistory\Configuration\Config1.xml"
        UltimoPunto        = $punto
    }
}

# Datos de salud del equipo. Lo que requiere administrador queda en $null si no lo es.
# Deja el detalle en el log (lo que no cabe en el resumen: titulos de actualizaciones, etc.)
function Get-SaludEquipo($discoC, $esAdmin) {
    # Bateria (solo portatiles): capacidad actual frente a la de fabrica, segun el informe de Windows
    $bateria = $null
    if (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) {
        $xml = Join-Path $env:TEMP 'bateria_limpieza.xml'
        powercfg /batteryreport /xml /output $xml | Out-Null
        try {
            $b = ([xml](Get-Content $xml -Raw)).BatteryReport.Batteries.Battery | Select-Object -First 1
            if ([double]$b.DesignCapacity -gt 0) {
                $bateria = [pscustomobject]@{
                    Salud  = [math]::Round(100 * [double]$b.FullChargeCapacity / [double]$b.DesignCapacity)
                    Ciclos = $b.CycleCount
                }
            }
        } catch { }
        Remove-Item $xml -ErrorAction SilentlyContinue
    }

    $winre = $null
    $sistemaArchivos = $null
    if ($esAdmin) {
        $winre = Get-EstadoWinRE ((& reagentc.exe /info 2>$null) -join "`n")
        # Revision en linea del sistema de archivos (como chkdsk /scan): no pide reiniciar ni desconecta C:,
        # pero NTFS corrige en el momento lo que puede (eventos 130 de Ntfs); lo que necesita C: libre
        # queda anotado para chkdsk /spotfix
        Log "  revisando el sistema de archivos de C: (en linea, sin reiniciar; puede tardar unos minutos)..."
        $r = Repair-Volume -DriveLetter C -Scan -ErrorAction SilentlyContinue -ErrorVariable errVolumen
        $sistemaArchivos = if ($errVolumen) { $null } else { "$r" }
        Log "  sistema de archivos: $(if ($sistemaArchivos) { $sistemaArchivos } else { 'no se pudo revisar' })" DarkGray
        # Si quedo algo pendiente, el detalle (que carpeta, que tipo de error) esta en el informe que
        # deja la revision en el registro Application (Chkdsk, evento 26226): al log las lineas de problemas
        if ($sistemaArchivos -and $sistemaArchivos -ne 'NoErrorsFound') {
            $informe = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Chkdsk'; Id = 26226; StartTime = (Get-Date).AddMinutes(-15) } -MaxEvents 1 -ErrorAction SilentlyContinue
            if ($informe) {
                @($informe.Message -split "`r?`n" | Where-Object { $_ -match '\$I30|\$FILE_NAME|\$MFT|\$Bitmap|cl.ster' } |
                    ForEach-Object { $_.Trim() } | Select-Object -Unique -First 5) | ForEach-Object { Log "    $_" DarkGray }
            }
        }
    }

    $version = Get-VersionWindows
    if ($version) { Log "  $($version.Nombre), compilacion $($version.Compilacion)" DarkGray }
    Log "  consultando Windows Update (solo consulta, no instala nada)..."
    $wu = Get-EstadoWindowsUpdate
    if ($wu.Error) {
        Log "  no se pudo consultar Windows Update: $($wu.Error)" DarkYellow
    } else {
        Log "  Windows Update: $($wu.Pendientes.Count) pendiente(s), $($wu.Opcionales.Count) opcional(es)" DarkGray
        foreach ($t in $wu.Pendientes) { Log "    pendiente: $t" DarkGray }
        foreach ($t in $wu.Opcionales) { Log "    opcional: $t" DarkGray }
        foreach ($t in $wu.Fallidas) { Log "    fallo y no se volvio a instalar: $t" DarkYellow }
        if ($wu.UltimaInstalada) { Log ("  ultima actualizacion instalada: {0:dd/MM/yyyy HH:mm}" -f $wu.UltimaInstalada) DarkGray }
    }

    $hardware = Get-ErroresHardware 30
    if ($hardware -and ($hardware.Graves + $hardware.Corregidos) -gt 0) {
        Log "  errores de hardware (WHEA) en 30 dias: $($hardware.Graves) grave(s), $($hardware.Corregidos) corregido(s)" DarkYellow
    }

    [pscustomobject]@{
        Bateria           = $bateria
        Fiabilidad        = if ($esAdmin) { $discoC | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue } else { $null }
        SistemaArchivos   = $sistemaArchivos
        WinRE             = $winre
        Version           = $version
        WindowsUpdate     = $wu
        Cuelgues          = Get-CuelguesRecientes 30
        Hardware          = $hardware
        Defender          = Get-EstadoDefender
        Seguridad         = Get-EstadoSeguridad $esAdmin
        Respaldo          = Get-EstadoRespaldo $esAdmin
        # Con el Inicio rapido activo, Apagar no reinicia Windows de verdad: esta fecha solo cambia al Reiniciar
        UltimoArranque    = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime
        ReinicioPendiente = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
                            (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    }
}
