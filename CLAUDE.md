# CLAUDE.md

Guía para Claude Code al trabajar en este repositorio. Es la referencia interna del proyecto: qué es, hasta dónde llega, cómo está armado, qué riesgos no toma y cómo hacerlo crecer sin romperlo. La documentación para el usuario es `README.md`; este archivo es para quien modifica el código.

---

## 1. Qué es el proyecto

Script de limpieza y mantenimiento de Windows para el PC del propio usuario. Se ejecuta con doble clic en `limpiar.bat` (o en el acceso directo del Escritorio). Hace todas las preguntas al inicio, después corre solo y, al terminar:

- muestra un resumen en pantalla (espacio liberado, salud del equipo, Windows y seguridad, programas de inicio, aplicaciones);
- lo deja en `limpieza.log`;
- lo guarda en `historial.csv`;
- lo envía por correo (Resend), con estilo negro y rojo neón.

El usuario habla en español. **Todo lo que ve el usuario va en español**: consola, log, correo, README y este archivo.

**Objetivo:** liberar espacio y mantener el equipo al día **sin riesgo**. Ante la duda, el script conserva, pregunta o solo informa.

---

## 2. Alcance

### 2.1 Lo que hace

| Paso | Qué hace | Admin | Pregunta |
|---|---|---|---|
| 1 | Temporales del usuario (`%TEMP%`), solo los de más de 24 h | no | — |
| 2 | Temporales de Windows, solo los de más de 24 h | sí | — |
| 3 | Caché de Windows Update (detiene y reinicia `wuauserv`/`bits`) | sí | — |
| 4 | Caché de navegadores, VS Code y apps de chat (Teams, Discord, Slack) | no | cerrar navegador o app abierta |
| 5 | Caché de shaders de la GPU | no | — |
| 6 | Caché de pip, npm, Yarn 1, pnpm (`store prune`) y Go; NuGet y logs de PM2 | no | NuGet y PM2 (si pasan de 50 MB) |
| 7 | Logs CBS/DISM, informes de error (WER) y volcados de memoria | sí | — |
| 8 | Caché de Delivery Optimization | sí | — |
| 9 | Limpieza profunda: Liberador de espacio (restos de actualización grande) y DISM | sí | DISM; restos de actualización |
| 10 | Reparación: punto de restauración + DISM RestoreHealth + SFC | sí | sí |
| 11 | Docker: `prune` sin riesgo; imágenes sin usar solo si se autoriza | sí | imágenes |
| 12 | Paquetes de Linux en WSL: `apt-get update` + `upgrade` (sin instalar ni quitar) y `apt-get clean` | sí | sí (solo si hay distros con apt) |
| 13 | Compactar discos virtuales de WSL y Docker (`fstrim` + `diskpart`) | sí | sí |
| 14 | TRIM del SSD | sí | — |
| 15 | Puntos de restauración: conserva los `$maxPuntos` más recientes | sí | — |
| 16 | Apps desactualizadas (winget): siempre lista; actualiza con admin + S | parcial | actualizar |
| 17 | Revisión de salud, solo lectura (Windows Update, sistema de archivos, hardware, seguridad, respaldo...) | parcial | — |

### 2.2 Lo que NO hace (riesgos que no toma)

Estas cosas se rechazaron a propósito. **No se agregan aunque parezcan útiles**, salvo que el usuario lo pida explícitamente después de conocer el riesgo:

- **Limpiar el registro.** No da una mejora medible, y un error puede dejar programas o Windows sin arrancar.
- **Desfragmentar.** En un SSD gasta vida útil; para eso está el TRIM (paso 14).
- **Desactivar servicios.** Lo que se gana es mínimo y las fallas aparecen en silencio, a veces semanas después.
- **"Liberar RAM".** Windows usa la RAM libre como caché; vaciarla hace que todo cargue más lento.
- **Desactivar programas de inicio.** Solo se informan; decide el usuario.
- **Borrar instantáneas que no son puntos de restauración.**
- **Borrar `C:\Windows\Installer` o `$PatchCache$`.** Sin esos archivos no se pueden reparar ni desinstalar programas.
- **Borrar la caché de miniaturas.** Exige cerrar el Explorador de Windows y libera muy poco.
- **`docker volume prune` o `docker image prune -a`.** Los volúmenes guardan las bases de datos de los proyectos.
- **Instalar actualizaciones de Windows, drivers o BIOS.** Solo se informan (paso 17).
- **`apt full-upgrade`/`dist-upgrade` o `apt autoremove` en WSL.** Instalan o quitan paquetes de los que pueden depender los entornos de desarrollo; el paso 12 solo usa `apt-get upgrade`.
- **Cerrar VS Code.** Puede haber archivos sin guardar.
- **Tocar historial, cookies, contraseñas o sesiones** de navegadores y apps.
- **Borrar la carpeta del almacén de pnpm o la caché de Yarn 2+.** Los proyectos dependen de ellas.

---

## 3. Reglas de trabajo con el usuario

- **Nunca ejecutar `limpiar.ps1` ni `limpiar.bat`.** Borran archivos, detienen servicios, actualizan apps y piden UAC. El usuario lo ejecuta y después pide "validar/revisar el log" (`limpieza.log`, que se sobrescribe en cada ejecución).
- **El `README.md` siempre al día y fiel al script.** Nunca debe describir algo que el script ya no hace, ni omitir algo que sí hace. En cada cambio a `limpiar.ps1`, `limpiar.bat`, `lib\*.ps1` o al formato de `correo.json`, en el mismo turno y sin que lo pidan:
  - actualizar las secciones afectadas: archivos, preguntas, pasos y su numeración, pasos de administrador, resumen final, correo, configuración, recomendaciones y "Lo que no hace";
  - agregar una entrada con fecha en "Historial de cambios" (la más reciente arriba);
  - releer el README contra el script para confirmar que nada más quedó desactualizado;
  - seguir las reglas de estructura del README (sección 10), sobre todo "Requisitos" e "Instalación en otro equipo" (10.2).
- **Este `CLAUDE.md` también se mantiene al día** en el mismo turno (ver sección 9).
- **Todo lo útil tiene que quedar en `limpieza.log`** (ver 6.2).
- **No enviar correos** (por ejemplo, para probar Resend) sin preguntar antes.
- **Revisiones elevadas de solo lectura** (puntos de restauración, instantáneas, etc.): escribir un `.ps1` pequeño en el scratchpad y ejecutarlo con `Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -File ...`, guardando el resultado en un archivo de `%TEMP%`. El usuario tiene que aceptar el UAC, así que hay que avisarle antes.
- **Repositorio público.** `correo.json`, `limpieza.log`, `historial.csv` y `*.lnk` están en `.gitignore`. Nunca subir datos personales: correos, nombre del equipo, rutas del usuario, nombres de proyectos. `correo.json` guarda la **API key de Resend**: nunca copiarla al README, al log, al chat ni a otro archivo. Mantener `correo.ejemplo.json` igual al formato real. `memory-global/` también se sube: nada privado ahí (va a `memory-local/`, ver 11).
- No hacer commit salvo que el usuario lo pida.

---

## 4. Arquitectura

### 4.1 Archivos

| Archivo | Rol |
|---|---|
| `limpiar.bat` | Comprueba si tiene permisos de administrador con `net session`; si no, se relanza con `Start-Process -Verb RunAs`. Después ejecuta `limpiar.ps1` con `-ExecutionPolicy Bypass`. |
| `limpiar.ps1` | Flujo principal: funciones de apoyo, configuración, preguntas, los 17 pasos numerados, resumen, historial y correo. |
| `lib\resumen.ps1` | Presentación del resumen: consola + HTML del correo. |
| `lib\salud.ps1` | Datos de salud del equipo (solo lectura). |
| `lib\historial.ps1` | `historial.csv`: última ejecución, tendencia del espacio, `Format-Hace`. |
| `lib\correo.ps1` | Lectura de `correo.json` y envío con Resend. |
| `crear-acceso-directo.ps1` | Crea el acceso directo del Escritorio con `limpiar.ico`. |
| `limpiar.ico` | Icono (negro con rojo neón; PNG de 16 a 256 px dentro del `.ico`). |
| `correo.ejemplo.json` | Plantilla pública de `correo.json`. |
| `verificar.ps1` | Revisión sin ejecutar la limpieza: sintaxis, solo ASCII, pruebas y PSScriptAnalyzer (si está instalado). Sale con 1 si algo falla. |
| `tests\cargar.ps1` | Carga las funciones de `limpiar.ps1` desde el AST (sin ejecutar el script) y los módulos de `lib\`; `Log` no escribe nada. |
| `tests\*.Tests.ps1` | Pruebas de Pester (ver 8.4). |
| `tests\muestras\` | Salidas de ejemplo de winget y apt (UTF-8, sin datos de ningún equipo). |
| `memory-global\` | Memoria de Claude Code que vale en cualquier PC (ver 11). No la usa el script. |
| `.githooks\pre-commit` | Corre `verificar.ps1` antes de cada commit. Se activa por equipo con `git config core.hooksPath .githooks`; va en LF (`.gitattributes`) porque lo ejecuta `sh`. |

### 4.2 Flujo de `limpiar.ps1`

1. `Start-Transcript`: el transcript **es** `limpieza.log`, y la salida de `Write-Host` también queda registrada.
2. Carga los módulos de `lib\` con dot-sourcing.
3. Define las funciones de apoyo y la configuración.
4. **Inicio:** recuadro (`Write-CajaConsola`), reúne los datos que necesitan las preguntas y arma `$preguntas`, solo con las que aplican ahora. Cada pregunta tiene `Clave`, `Titulo` y `Detalle`.
5. **Preguntas:** se muestran como tarjetas numeradas (`[2/6]`) con `Read-SiNo`: S/si/N/no, Enter = No, y vuelve a preguntar si la respuesta no es válida. Como `Read-Host` no queda en el transcript, `Read-SiNo` repite `-> SI` / `-> NO` en su propia línea. Las respuestas van a `$respuestas[Clave]` y se pasan a `$cerrarNav`, `$cerrarApp`, `$borrarRestos`, `$hacerDism`, `$hacerReparacion`, `$borrarImagenesDocker`, `$actualizarWsl`, `$hacerCompactar`, `$hacerActualizar`, `$borrarNuget` y `$borrarLogsPm2`.
6. **Pasos 1 a 17**, sin intervención. Los que necesitan administrador van agrupados en `if ($esAdmin) { ... } else { Log "Pasos X a Y omitidos..." }`: hoy son el 2-3 y el 7-15. Al agregar pasos hay que actualizar ese mensaje. Los pasos 16 y 17 corren fuera del grupo y saltan solos sus partes de administrador.
7. `Show-Resumen` (con un hashtable que incluye `Salud`, del paso 17, y `Tendencia`), después `Add-Ejecucion` al historial (después del resumen, para incluir la cantidad de avisos) y después el correo.
8. `Stop-Transcript`. Se descarta lo que se tecleó durante la ejecución y **solo Enter cierra la ventana**, para que el resumen quede a la vista.

### 4.3 Módulos de `lib\`

- **`resumen.ps1`**: cada función de bloque (`Write-Cabecera`, `Write-Seccion`, `Write-Dato`, `Write-Estado`, `Write-Lista`, `Write-Nota`, `Write-TablaApps`) produce **las dos versiones a la vez**:
  - texto de ancho fijo con colores para la consola y el log (`Out-Resumen`);
  - HTML adaptable para el correo (`Add-Html` en `$resumenHtml`): una tarjeta por sección, filas de tabla y etiquetas de estado; máximo 600 px y 100 % en el celular.

  Nunca escribir contenido del resumen en una sola de las dos versiones. En el correo, solo estilos en línea y tablas (los clientes de correo ignoran `<style>` y flexbox); el texto pasa por `Format-HtmlTexto`. La paleta (negro con rojo neón) está arriba del archivo: `$neon`, `$brilloNeon`, `$fondoHtml`, `$lineaHtml` y `$coloresHtml`. El HTML se declara `color-scheme: dark` para que el modo oscuro del celular no invierta los colores. `Write-Estado` tiene cuatro niveles: `OK`, `AVISO`, `INFO` (solo informa) y `NA` (dato no disponible). Solo `AVISO` se cuenta en `$avisosResumen`, que va en el asunto del correo; lo que el usuario puede tener resuelto de otra forma va como `INFO`. Secciones: Espacio, Salud del equipo (hardware), Windows y seguridad, Programas de inicio, Aplicaciones y Paquetes de Linux (WSL; solo si hay distros con apt).
- **`salud.ps1`**: `Get-SaludEquipo`, que se llama en el paso 17 y deja el detalle en el log con `Log`, junta:
  - batería, contadores del SSD, `Repair-Volume -Scan` (admin) y WinRE;
  - versión de Windows;
  - Windows Update, con el COM `Microsoft.Update.Session`: pendientes, opcionales, última instalada y las que fallaron sin volver a instalarse. La búsqueda tarda unos 30-60 s;
  - errores de hardware (WHEA);
  - pantallazos azules y apagados inesperados (`Get-CuelguesRecientes`, que también usa el paso 7);
  - Defender; firewall, UAC, Arranque seguro y BitLocker;
  - respaldo (OneDrive o Historial de archivos) y el punto de restauración más reciente.

  Las lecturas del registro de eventos pasan por `Get-EventosSistema`.
- **`historial.ps1`**: `Get-UltimaEjecucion` y `Add-Ejecucion` (últimas 200 ejecuciones); `Get-TendenciaEspacio` (GB por mes que se pierden: recta de mínimos cuadrados sobre el espacio libre después de cada limpieza de los últimos 120 días, más la de hoy; necesita 4 puntos y 14 días). No comparar con una sola ejecución vieja: el 25/11/2026 eso dio "ganas 24,6 GB al mes" por archivos borrados a mano. Si el espacio sube, el resumen dice "no se está llenando", sin cifra; `Format-Hace`. El CSV usa `;` y números en cultura invariante, porque en es-CO la coma es el separador decimal. Si el CSV falta o está dañado, devuelve `$null` sin cortar la ejecución.
- **`correo.ps1`**: `Get-ConfigCorreo` lee y valida `correo.json` (`activo`, `apiKey`, `de`, `para`) y devuelve `$null` si no existe. `Send-ResumenCorreo` usa la API REST de Resend, fuerza TLS 1.2 para PS 5.1 y lanza el mensaje de error de Resend. Los fallos del correo se atrapan y se registran: nunca cortan la ejecución.

### 4.4 Funciones de apoyo en `limpiar.ps1`

| Función | Para qué |
|---|---|
| `Log` | `Write-Host` con hora. |
| `Format-Tamano` | Tamaño legible, en GB desde 1000 MB. |
| `Get-FolderSize`, `Test-Reciente` | Tamaño de una carpeta; si algo dentro se modificó después de una fecha. |
| `Clear-Folder` / `Clear-Folders` | Borra el **contenido** de una carpeta (o de una lista, saltando las que no existen) y devuelve los MB liberados. `-HorasMinimas` conserva lo reciente. |
| `Invoke-Herramienta` | Ejecuta dism/sfc: junta las barras de progreso (`\r`) y registra el progreso cada 10 %. `-Unicode` para la salida UTF-16 de sfc. |
| `Invoke-LimpiezaComando` | Ejecuta el comando oficial de limpieza de una herramienta (pnpm, go) y mide lo que achicó su carpeta. |
| `Invoke-LiberadorEspacio` | `cleanmgr /sagerun:42` solo con las categorías indicadas (marca temporal `StateFlags0042`, que se quita al terminar), con un tiempo máximo de 20 min; mide por el espacio libre del disco. |
| `Remove-PerfilLiberador` | Quita la marca `StateFlags0042`. También se llama al inicio (con permisos de administrador) para limpiar lo que haya dejado una ejecución cortada. |
| `Stop-Programa` | Cierra un programa: primero sus ventanas, después a la fuerza lo que quede. |
| `Get-CarpetasCache` | Carpetas exactamente `Cache`, `Code Cache` o `GPUCache` dentro de una app Electron/WebView2. |
| `Get-RestosActualizacion` | `Windows.old`, `$WINDOWS.~BT` y `$WINDOWS.~WS`, con tamaño y si son recientes. |
| `Test-InicioHabilitado` | Lee `Explorer\StartupApproved` (primer byte impar = deshabilitado en el Administrador de tareas). |
| `Get-DiscosVirtuales` | Los `.vhdx` de WSL (`HKCU\...\Lxss`) y `docker_data.vhdx`. |
| `Test-DockerActivo`, `Get-ImagenesDockerSinUso`, `ConvertFrom-TamanoDocker` | Paso 11. |
| `Invoke-Wsl`, `Get-DistrosApt`, `Get-CacheApt`, `Update-PaquetesWsl`, `Update-PaquetesAptInstalados`, `ConvertFrom-SimulacionApt` | Paso 12. `Invoke-Wsl` ejecuta como root con `LC_ALL=C`, `DEBIAN_FRONTEND=noninteractive` y `NEEDRESTART_MODE=l`, y captura la salida en UTF-8. |
| `Get-AppsDesactualizadas`, `ConvertFrom-TablaWinget` | Llama a `winget upgrade`; la segunda lee la tabla por la posición de los títulos (funciona en cualquier idioma). |

Regla: la lectura de la salida de un programa externo va en una función `ConvertFrom-*` aparte, que recibe las líneas (y el código de salida) y no llama a nada. Así se prueba con muestras (8.4) sin ejecutar el programa.

### 4.5 Configuración (al inicio de `limpiar.ps1`)

| Variable | Valor | Uso |
|---|---|---|
| `$maxPuntos` | 2 | Puntos de restauración que conserva el paso 15 (borra los más viejos con `srclient.dll!SRRemoveRestorePoint`). |
| `$horasTemporales` | 24 | Antigüedad mínima para borrar en los pasos 1 y 2. |
| `$diasVolcados` | 7 | Si hubo un pantallazo azul en estos días, el paso 7 conserva los volcados. |
| `$diasRestosActualizacion` | 10 | Los restos de una actualización grande solo se ofrecen borrar pasado este tiempo. |

También van ahí las listas `$navegadores`, `$appsChat` y `$appsAutoactualizables` (paso 16).

---

## 5. Principios de diseño (cómo se decide qué tocar)

1. **Solo se borra lo que se regenera solo** (cachés, temporales, logs, informes ya enviados). Lo demás se pregunta o solo se informa.
2. **Preguntar mostrando exactamente qué se borra**, y después borrar solo eso. Por ejemplo, las imágenes de Docker se borran por nombre, nunca con `prune -a`.
3. **Preferir el mecanismo oficial** al borrado a mano: `Delete-DeliveryOptimizationCache`, DISM, `cleanmgr /sagerun`, `pnpm store prune`, `go clean`, `pm2 flush`, `docker ... prune`.
4. **Conservar lo reciente o lo que está en uso:** temporales de menos de 24 h, apps abiertas, volcados de un pantallazo reciente, restos de actualización de menos de 10 días.
5. **Nunca afirmar algo que no se comprobó.** Si una consulta falla, se muestra "N/D" o una nota en rojo, nunca "todo bien". Ejemplos: `$estadoWinget`, la lectura de eventos que devuelve `$null`.
6. **Medir de verdad lo liberado** (ver 6.3) y no sumar dos veces el mismo espacio.
7. **Un fallo parcial no corta la ejecución:** cada paso registra su error y se sigue con el siguiente.
8. **No dejar configuración cambiada:** perfiles temporales que se quitan al terminar (y al inicio de la siguiente ejecución, por si una se cortó), servicios que se vuelven a iniciar, Docker que se vuelve a abrir sin heredar el permiso de administrador.
9. **Nada externo puede trabar la ejecución para siempre:** si se espera a un programa (Liberador de espacio, etc.), con un tiempo máximo.

---

## 6. Detalles técnicos y trampas conocidas

### 6.1 Windows PowerShell 5.1

- Los `.ps1` deben ser **solo ASCII** (sin tildes ni ñ): el UTF-8 sin BOM se lee como ANSI y se desfigura. Lo que no es ASCII en pantalla (líneas de recuadro, `°`) se genera con `[char]0x....`. Los `.md` sí pueden llevar tildes.
- `[math]::Max([double]0, ...)`: `Max(0, x)` usa la versión de Int32 y falla con valores de más de 2 GB.
- La salida de winget es UTF-8: poner `[Console]::OutputEncoding` en UTF8 mientras se captura. La de sfc es UTF-16 (`Invoke-Herramienta -Unicode`).
- Un `PSCustomObject` suelto no tiene `.Count` en PS 5.1: envolver en `@(...)`.
- **Nunca `| Select-Object -First` sobre la salida de `wsl.exe`** (ni de otro programa nativo que cambie el modo de la consola): corta la tubería y mata el proceso antes de que restaure la consola. El 26/11/2026, en `Get-CacheApt`, dejó los saltos de línea sin volver al inicio y todo lo que siguió en pantalla salió en escalera (el log quedó bien, con `TerminatingError(): "The pipeline has been stopped."`). Usar `@(...)[0]`.

### 6.2 Log (`limpieza.log`)

- Todo lo que importa tiene que quedar dentro del transcript: qué se hizo o se saltó y por qué, las respuestas, los errores, el resultado de cada paso, el resumen y si se envió el correo. Lo que no llega solo al transcript se registra a mano: las respuestas de `Read-Host` (`Log`) y la salida de herramientas nativas (con `Log` o `Invoke-Herramienta`).
- Fuera del log: el progreso repetido y los volcados completos de excepciones.
- **Nunca `Write-Host -NoNewline`** en lo que deba leerse bien en el log: el transcript de PS 5.1 corta la línea en cada llamada. Por eso cada línea del resumen es un solo `Write-Host` de un solo color.
- Errores de borrado y de lectura: `-ErrorAction SilentlyContinue -ErrorVariable err`, **no** try/catch, porque los errores atrapados igual quedan escritos en el transcript. Las excepciones a esta regla (COM de Windows Update, Delivery Optimization, correo, batería) usan try/catch porque no hay otra forma.
- Para `Get-WinEvent`, "no hay eventos" llega como error `NoMatchingEventsFound*`: no es un fallo (`Get-EventosSistema`).

### 6.3 Medición del espacio

- Tamaños con `Format-Tamano` (GB desde 1000 MB): con el separador de miles de es-CO, "1.010 MB" se lee como 1 MB.
- **Por el espacio libre del disco**, cuando el tamaño de los archivos no refleja lo real: Delivery Optimization (paso 8; el tamaño aparente es mucho mayor que lo que ocupa), Liberador de espacio y DISM (paso 9).
- **Por lo que achicó el archivo** en la compactación (paso 13): `wsl --shutdown` hace que Windows borre `swap.vhdx` de `%TEMP%` segundos después, y el espacio libre lo contaba de más (~1,2 GB el 2026-11-17).
- **Docker** (paso 11): lo que libera queda dentro de `docker_data.vhdx` y solo vuelve a Windows al compactar. Se muestra aparte y **no** se suma a `$total` (la compactación ya lo cuenta). Lo mismo con `apt-get clean` en WSL (paso 12). Por eso los pasos 11 y 12 van antes del 13.

### 6.4 Por paso

- **1-2:** `Clear-Folder -HorasMinimas $horasTemporales`. Los programas en marcha dejan archivos de trabajo sin bloquear en `%TEMP%`; este script borró una vez el scratchpad de Claude Code a mitad de una sesión. Las cachés no necesitan esta protección.
- **4:** los navegadores solo se limpian cerrados o con permiso para cerrarlos. Se tocan solo `Cache`, `Code Cache` y `GPUCache` (Chromium) y `cache2` (Firefox). La caché de VS Code se salta si `Code` está abierto, y nunca se ofrece cerrarlo. Las apps de chat solo se limpian con `Get-CarpetasCache`; si están abiertas se saltan, salvo que se haya autorizado cerrarlas (solo se pregunta si su caché pasa de 50 MB).
- **6:** NuGet respeta `$env:NUGET_PACKAGES` y solo pregunta si pasa de 50 MB. Lo mismo con PM2 (`$env:PM2_HOME`): si el daemon está en marcha (`pm2.pid` apunta a un proceso `node` vivo), se usa `pm2 flush`, porque borrar los archivos que PM2 tiene abiertos no libera nada; si está detenido, `Clear-Folder`. pnpm solo con `pnpm store prune` (los `node_modules` son enlaces a su almacén). Yarn: solo la caché de Yarn 1 (con Plug'n'Play, los proyectos de Yarn 2+ leen su caché). Go: solo `go clean -cache`, no los módulos.
- **7:** los volcados (`MEMORY.DMP`, `Minidump`, `LiveKernelReports`) se conservan si `Get-CuelguesRecientes` ve un pantallazo azul en `$diasVolcados` días, o si no se pudo leer el registro.
- **3:** `Start-Service` va con `-WarningAction SilentlyContinue`. Si no, PowerShell escribe "ADVERTENCIA: Esperando a que se inicie el servicio..." mientras BITS arranca (es normal, pero el usuario lo vio y se preocupó el 24/11/2026). Después se registra el estado final de cada servicio.
- **6 (pnpm):** se ejecuta `pnpm.cmd`, no `pnpm.ps1`: con el `.ps1` de nvm, los avisos que pnpm escribe en stderr aparecían en el log como `NativeCommandError` en rojo, y cada línea salía repetida.
- **9:** los restos de actualización se borran **solo** con `Invoke-LiberadorEspacio`, nunca a mano. **No volver a agregar "Device Driver Packages":** en tres ejecuciones liberó 0 MB. El 24/11/2026 pasó más de una hora sin terminar, la ejecución quedó trabada y el usuario apagó el equipo, así que la marca `StateFlags0042` quedó puesta. El 25/11/2026 tardó 9 minutos y después 20 (cortado). Por ese caso:
  - se espera con `WaitForExit` y un tiempo máximo de 20 min, no con `Start-Process -Wait`, que también espera a los procesos que el Liberador deje abiertos;
  - al inicio del script se llama a `Remove-PerfilLiberador`. Los restos solo se preguntan si ninguno es más nuevo que `$diasRestosActualizacion` y suman más de 100 MB. Error `0x800f0806` de DISM = hay operaciones pendientes: reiniciar y volver a ejecutar.
- **11:** sin preguntar, solo los cuatro `prune` sin riesgo (contenedores, imágenes huérfanas, caché de compilación, redes). Las imágenes sin usar solo se borran con S y solo las que se listaron, por nombre (`docker rmi <tag>`). **Nunca `docker volume prune`.**
- **12:** solo distros con `/usr/bin/apt-get`; las `docker-desktop*` nunca. `apt-get update --allow-releaseinfo-change-label` (solo la etiqueta: el 25/11/2026 el PPA `ondrej/php` pasó a "PPA for PHP (deprecated)" y apt se detenía). No ampliarlo a `--allow-releaseinfo-change`: un cambio de origen, versión o codename merece que lo mire una persona. La lista de paquetes sale de `apt-get -s upgrade` (`Inst pkg [vieja] (nueva`), y los retenidos de "N not upgraded" (en Ubuntu suelen ser actualizaciones escalonadas, no un problema). `apt-get upgrade -y -o Dpkg::Options::=--force-confold` y `DPkg::Lock::Timeout=120`. De la salida de apt solo van al log `E:`/`W:`/`dpkg:` y el total. `apt-get clean` corre aunque el update falle; si falla, el error real de apt (`E:`) va al resumen.
- **13:** primero `fstrim`: `fstrim -a` en las distribuciones normales y `fstrim /mnt/docker-desktop-disk` en `docker-desktop` (solo con Docker Desktop abierto). Sin ese paso, 1,3 GB de imágenes borradas nunca volvieron a Windows. Docker Desktop se vuelve a abrir con `explorer.exe`, para que no herede el permiso de administrador. Si `diskpart compact` falla, se ejecuta `detach vdisk` para no dejar el disco conectado.
- **8:** `Delete-DeliveryOptimizationCache` escribe "Deleting..." con `Write-Host`. En PS 5.1 el transcript registra `Write-Host` aunque se redirija (`6>$null` y `*>$null` no sirven, probado el 25/11/2026), así que se ejecuta en otro `powershell.exe` y se usa su código de salida.
- **14:** `Optimize-Volume -ReTrim` solo dice `Failed`; el motivo se lee del evento 264 de `Microsoft-Windows-Defrag` (Application) y va a `$trimError`, que el resumen muestra como `AVISO`. Nunca registrar "TRIM terminado" si falló. Caso real del 25/11/2026: `0x89000015`, el volumen tiene el bit de "revisar" puesto por una reparación pendiente (ver 17), y Windows no hace TRIM hasta que se repare.
- **16:** `$estadoWinget` (`ok`, `al dia`, `no instalado`, `error (codigo N)`). "Al día" solo cuando winget sale con 0 o -1978335212; nunca a partir de una lista vacía. `$appsAutoactualizables` (App Installer, Edge, Spotify) sale como "Se actualizan solas". `$seActualizo` decide qué presentación usa el resumen, no si algo se actualizó. Si winget dice que instaló una app pero la sigue listando, cuenta como fallida.
- **17:** la búsqueda de Windows Update tarda; las fechas de su historial vienen en UTC (`ToLocalTime()`). WinRE se lee solo de la línea de estado de `reagentc /info` (`Get-EstadoWinRE`). Respaldo: si Documentos y Escritorio no están en OneDrive ni en el Historial de archivos, sale como `INFO`, no como `AVISO` (lo decidió el usuario el 25/11/2026: en su PC es así a propósito). `Repair-Volume -Scan` no es solo lectura: NTFS corrige en línea lo que puede (eventos 130 de `Ntfs` en System) y deja para `chkdsk /spotfix` lo que necesita C: libre. Niveles: corregido en línea → `OK`; necesita SpotFix → `INFO`; cualquier otro error → `AVISO` (`chkdsk C: /f`). Lo que necesita SpotFix es menor por definición (entradas de índice, vínculos) y el estado del disco se vigila aparte con sus contadores. Caso real del 25/11/2026: quedó pendiente una entrada `$I30` de `\Windows\Prefetch`, pero en esa versión de prueba de Windows (26300) no abrían `chkdsk.exe`, `chkntfs.exe` ni `autofmt.exe` ("Acceso denegado" aun como admin), y `Repair-Volume -SpotFix` / `-OfflineScanAndFix` devolvían `Failed`. Como `AVISO` se habría repetido en cada ejecución sin poder resolverse. El detalle sale del informe de la revisión (Application, proveedor `Chkdsk`, evento 26226) y va al log; para más contexto, ver los eventos 98 y 130 de `Ntfs`.

---

## 7. Cómo hacer crecer el proyecto

Antes de agregar algo, comprobar que respeta la sección 2.2 y los principios de la sección 5. Si una idea toca algo de 2.2, **explicarle el riesgo al usuario** en vez de implementarla.

### 7.1 Agregar una limpieza a un paso existente
1. Ubicarla en el paso que corresponde por tema (cachés de apps → 4, desarrollo → 6, Windows → 7/8, Liberador → 9).
2. Usar `Clear-Folders`, `Invoke-LimpiezaComando` o `Invoke-LiberadorEspacio`; no reinventar la medición.
3. Si borra algo que no se regenera solo, o cierra un programa: pregunta con umbral de tamaño.

### 7.2 Agregar un paso nuevo
1. Preferir ampliar un paso existente: renumerar obliga a tocar el README, los mensajes y esta guía.
2. Si es necesario, numerarlo, agregarle `Log "Paso N: ..." Yellow` y ubicarlo dentro o fuera de `if ($esAdmin)`. Actualizar el mensaje "Pasos X a Y omitidos" y la sección "Sin permisos de administrador" del README.

### 7.3 Agregar una pregunta
1. Reunir los datos antes de las preguntas y agregar la entrada a `$preguntas`, solo si aplica (umbral de tamaño, programa abierto, etc.).
2. Pasar `$respuestas['clave']` a una variable `$hacerX` o `$borrarX` y listarla en 4.2.
3. El `Detalle` dice cuánto ocupa, cuánto tarda y qué se pierde.

### 7.4 Agregar una línea de salud o un dato del resumen
1. Juntar el dato en `lib\salud.ps1` (solo lectura, `$null` si no se pudo leer) o pasarlo en el hashtable de `Show-Resumen`.
2. Mostrarlo en `lib\resumen.ps1` con `Write-Estado` (`OK` / `AVISO` / `INFO` / `NA`) o `Write-Dato`. Nunca escribir solo en consola o solo en HTML.
3. Elegir el umbral del aviso para que no salte en uso normal: un aviso falso desgasta la confianza en el resumen y aumenta el contador del asunto del correo.
4. El detalle extenso va al log, no al resumen.

### 7.5 Agregar configuración
Una variable al inicio de `limpiar.ps1`, con un comentario en la misma línea, más la tabla 4.5 y la sección "Configuración" del README.

---

## 8. Mantenimiento y verificación

### 8.1 Antes de dar un cambio por terminado
1. `verificar.ps1` sin fallos: sintaxis, solo ASCII y pruebas (8.2). El hook de pre-commit lo corre solo; no saltarlo con `--no-verify`.
2. Si el cambio agrega o modifica lógica que se puede probar sin efectos (lectura de una salida, cálculo, borrado dentro de una carpeta), agregar o ajustar su prueba (8.4).
3. Probar en solo lectura (8.2), sin ejecutar el script, las funciones nuevas que no tienen prueba.
4. Si cambió el resumen o el correo: vista previa en el navegador, también en tamaño celular.
5. README actualizado (sección 3) y este archivo (sección 9).
6. Contarle al usuario qué no se pudo probar sin una ejecución real (normalmente, lo que necesita permisos de administrador).

### 8.2 Comandos

Sintaxis, solo ASCII y pruebas, sin ejecutar la limpieza (tarda unos segundos):
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File verificar.ps1
```

Probar una función de `limpiar.ps1` por separado (extraerla del AST y cargarla):
```powershell
$ast = [System.Management.Automation.Language.Parser]::ParseFile("$PWD\limpiar.ps1", [ref]$null, [ref]$null)
$fn = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Test-InicioHabilitado' }, $true)[0]
. ([scriptblock]::Create($fn.Extent.Text))
```

Vista previa del resumen y del correo sin limpiar nada, en un proceso nuevo de `powershell -File`:
1. Definir un `Log` simple y cargar `lib\resumen.ps1`, `lib\salud.ps1` y `lib\historial.ps1`.
2. Llamar a `Get-SaludEquipo $disco $false`, que solo lee (Windows Update tarda ~1 min).
3. Llamar a `Show-Resumen` con un hashtable de prueba (las mismas claves que pasa `limpiar.ps1`, incluidas `Salud` y `Tendencia`).
4. Escribir `Get-ResumenHtml $pie` en un `.html` **dentro de la carpeta del proyecto**: los archivos de otras carpetas no se pueden capturar en el navegador.
5. Revisarlo en tamaño escritorio y `mobile`, y **borrar el archivo** al terminar.

Leer el log sin el detalle archivo por archivo:
```powershell
Get-Content limpieza.log | Where-Object { $_ -notmatch '^\[\d\d:\d\d:\d\d\]   (borrado|en uso, omitido): ' }
```

### 8.3 Al revisar un log
- Recorrer cada paso: qué hizo, qué saltó y por qué, y los errores (`DarkYellow` / `Red`).
- Comparar lo liberado con el delta de espacio libre del resumen.
- Ver si algún aviso del resumen es un falso positivo; si lo es, ajustar el umbral y registrar el caso real en 6.4.
- Lo que se aprenda de una ejecución real (números, errores nuevos) va a la sección 6 con la fecha.

### 8.4 Pruebas (`tests\`)
- **Pester 3.4**, el que viene con Windows: sintaxis `Should Be`, no `Should -Be` (esa es de Pester 4+). `verificar.ps1` usa la versión 3 o 4 más nueva que haya, así que instalar Pester 5 no las rompe.
- Cada `*.Tests.ps1` empieza con `. (Join-Path $PSScriptRoot 'cargar.ps1')`. Las pruebas también son `.ps1`: **solo ASCII**.
- **Nunca tocar carpetas reales:** lo que borra trabaja en `$TestDrive` (carpeta temporal de Pester). Para .NET (`[IO.File]`) usar `"$TestDrive\..."`, no `TestDrive:\`, que .NET no entiende.
- No probar lo que necesita administrador, red o programas externos (winget, wsl, docker, el registro): se prueba su función `ConvertFrom-*` con una muestra (4.4).
- Muestras en `tests\muestras`, en UTF-8 y con apps o paquetes genéricos: **nunca** copiar una salida de este PC con nombres de proyectos, rutas o el nombre del equipo (repo público).
- `reglas.Tests.ps1` revisa el código **sin comentarios** contra la lista de 2.2 y las trampas de 6.1/6.2 (`volume prune`, `full-upgrade`, `-NoNewline`...). Si el usuario autoriza algo de 2.2, se quita su patrón ahí en el mismo cambio. Si se agrega algo a 2.2, se agrega su patrón.
- Una prueba que se escribe y pasa a la primera no prueba nada hasta que se la ve fallar: romper la función a propósito, ver que la prueba falla y deshacer el cambio. Así se hizo el 2026-11-26 con `Clear-Folder` y la regla de `volume prune`.

---

## 9. Reglas para escribir este archivo

- **Todo en español.** Los nombres de código (funciones, variables, rutas, comandos) van tal cual, entre comillas invertidas.
- **Mantenerlo al día en el mismo turno** que el cambio de código, igual que el README: pasos (2.1), lo que no hace (2.2), archivos y funciones (4), configuración (4.5), trampas (6).
- **Cada cosa en su sección**, sin repetirla en otra; si hace falta, remitir ("ver 6.3").
- **Solo lo que no se deduce leyendo el código:** el porqué, los riesgos, los casos reales que llevaron a una decisión (con fecha y cifras) y las reglas de trabajo. No copiar el código.
- **Reglas con su razón:** "nunca X, porque Y". Una regla sin razón termina rompiéndose.
- **Breve y escaneable:** tablas para inventarios, listas para reglas, un tema por viñeta.
- **No incluir datos personales ni secretos** (repositorio público): ni la API key, ni correos, ni el nombre del equipo, ni rutas del usuario.
- **Si algo deja de ser cierto, se borra o se corrige**; no se acumulan notas viejas. La historia de los cambios va en el README ("Historial de cambios"), no aquí.
- **Si se agrega una sección, conservar la numeración** y actualizar las referencias cruzadas ("ver 6.3").

---

## 10. Reglas para escribir el `README.md`

El README es para **quien usa el script en su propio equipo**, sin saber nada del código ni de este PC. El objetivo es que funcione en otros equipos, no solo en este (lo pidió el usuario el 2026-11-26).

### 10.1 Estructura

Orden fijo de las secciones (`##`). Si se agrega una, va en el lugar que le corresponde por tema, no al final:

| # | Sección | Contenido |
|---|---|---|
| 1 | Archivos | Tabla de todos los archivos del repo y de los que se generan |
| 2 | Requisitos | Qué necesita el equipo |
| 3 | Instalación en otro equipo | Qué ocupa, pasos y qué se copia entre equipos |
| 4 | Cómo usarlo | Ejecución diaria |
| 5-6 | Preguntas, Pasos (con "Resumen final" como `###`) | Qué hace el script (igual a 2.1 y al código) |
| 7-11 | Correo, Sin permisos de administrador, Configuración, Recomendaciones, Lo que no hace | Referencia |
| 12 | Si modificas el script | Solo para desarrollo: clonar, hook, comandos de las pruebas |
| 13 | Historial de cambios | `- **AAAA-MM-DD** - texto`, el más reciente arriba |

- Hoy va **sin tildes** (todo ASCII): mantener ese estilo en lo que se agregue.
- Tablas para inventarios (archivos, campos, comandos), pasos numerados para lo que se hace en orden, bloques de código para los comandos que se copian.
- Sin datos de este PC (repositorio público): ni rutas del usuario, ni el nombre del equipo, ni correos reales. Ejemplos genéricos (`C:\Herramientas\...`, `tu-correo@ejemplo.com`).

### 10.2 "Requisitos" e "Instalación en otro equipo" siempre al día

Es lo primero que lee alguien que lo instala en otro equipo, y un dato viejo ahí hace que falle sin que se entienda por qué. Revisar estas dos secciones en **cada** cambio, aunque parezca que no las toca:

| Si el cambio... | Actualizar |
|---|---|
| Necesita un programa, versión, permiso o configuración de Windows nueva | Requisitos |
| Agrega un archivo que el usuario tiene que crear, copiar o llenar (como `correo.json`) | Pasos (con el comando para crearlo y una tabla de sus campos), "Qué se copia" y `.gitignore` |
| Cambia el formato de `correo.json` | La tabla de campos, `correo.ejemplo.json` y la sección Correo |
| Genera un archivo nuevo, o cambia lo que ocupa uno que ya existe | "Qué ocupa en el equipo" (con el tamaño aproximado) |
| Deja algo en el equipo (registro, tarea, servicio, perfil temporal) | "Qué ocupa" y la frase "No crea servicios ni tareas..." si deja de ser cierta |
| Agrega una herramienta de desarrollo (pruebas, analizador) | "Si modificas el script" |

Las tablas de estas secciones se comprueban contra el repo de verdad (`git ls-files`, el tamaño de los archivos, los comandos ejecutados), no de memoria.

---

## 11. Memoria de Claude Code

La memoria del proyecto está en dos carpetas. Las reglas (qué va en cada una, formato, crecimiento) están en `memory-global/REGLAS-MEMORIA.md`.

| Carpeta | Qué guarda | ¿Se sube? | La carga |
|---|---|---|---|
| `memory-global/` | Reglas y decisiones que valen en cualquier PC, **sin datos privados** (este repo es público) | Sí | Este archivo (abajo) |
| `memory-local/` | Lo de cada PC: cuentas de git, remotos, datos privados | No (`.git/info/exclude`) | `CLAUDE.local.md` |

Un `@memory-global/...` por memoria global. Si una no está aquí, no se carga en las sesiones siguientes.

@memory-global/MEMORY.md
@memory-global/REGLAS-MEMORIA.md
@memory-global/DOCUMENTACION-AL-DIA.md
