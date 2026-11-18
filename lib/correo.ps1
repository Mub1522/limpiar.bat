# Envio del resumen por correo con Resend (https://resend.com).
# La configuracion, incluida la API key, esta en correo.json junto a limpiar.bat.
# Se carga con dot-sourcing desde limpiar.ps1.

# Lee y valida correo.json. Devuelve $null si no existe (el envio queda desactivado).
function Get-ConfigCorreo($ruta) {
    if (-not (Test-Path $ruta)) { return $null }
    try { $config = Get-Content $ruta -Raw | ConvertFrom-Json }
    catch { throw "correo.json no es un JSON valido: $($_.Exception.Message)" }
    foreach ($campo in 'apiKey', 'de', 'para') {
        if (-not $config.$campo) { throw "falta el campo '$campo' en correo.json" }
    }
    return $config
}

# Envia el correo y devuelve el id que asigna Resend. Si falla lanza una excepcion
# con el mensaje de error de Resend (nunca incluye la API key).
function Send-ResumenCorreo($config, $asunto, $html) {
    # PowerShell 5.1 no activa TLS 1.2 por defecto y la API de Resend lo exige
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $cuerpo = @{
        from    = $config.de
        to      = @($config.para)
        subject = $asunto
        html    = $html
    } | ConvertTo-Json -Compress

    try {
        $respuesta = Invoke-RestMethod -Method Post -Uri 'https://api.resend.com/emails' `
            -Headers @{ Authorization = "Bearer $($config.apiKey)" } `
            -ContentType 'application/json; charset=utf-8' `
            -Body ([Text.Encoding]::UTF8.GetBytes($cuerpo)) -TimeoutSec 30 -ErrorAction Stop
    } catch {
        # Resend explica el error en el cuerpo de la respuesta (ej. API key invalida)
        $detalle = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        throw $detalle
    }
    if (-not $respuesta.id) { throw "Resend no devolvio un id de envio" }
    return $respuesta.id
}
