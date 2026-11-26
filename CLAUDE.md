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
| 9 | Limpieza profunda: Liberador de espacio (restos de actualización grande, drivers reemplazados) y DISM | sí | DISM; restos de actualización |
| 10 | Reparación: punto de restauración + DISM RestoreHealth + SFC | sí | sí |
| 11 | Docker: `prune` sin riesgo; imágenes sin usar solo si se autoriza | sí | imágenes |
| 12 | Compactar discos virtuales de WSL y Docker (`fstrim` + `diskpart`) | sí | sí |
| 13 | TRIM del SSD | sí | — |
| 14 | Puntos de restauración: conserva los `$maxPuntos` más recientes | sí | — |
| 15 | Apps desactualizadas (winget): siempre lista; actualiza con admin + S | parcial | actualizar |
| 16 | Revisión de salud, solo lectura (Windows Update, sistema de archivos, hardware, seguridad, respaldo...) | parcial | — |

### 2.2 Lo que NO hace (riesgos que no toma)

Estas cosas se rechazaron a propósito. **No se agregan aunque parezcan útiles**, salvo que el usuario lo pida explícitamente después de conocer el riesgo:

- **Limpiar el registro.** No da una mejora medible, y un error puede dejar programas o Windows sin arrancar.
- **Desfragmentar.** En un SSD gasta vida útil; para eso está el TRIM (paso 13).
- **Desactivar servicios.** Lo que se gana es mínimo y las fallas aparecen en silencio, a veces semanas después.
- **"Liberar RAM".** Windows usa la RAM libre como caché; vaciarla hace que todo cargue más lento.
- **Desactivar programas de inicio.** Solo se informan; decide el usuario.
- **Borrar instantáneas que no son puntos de restauración.**
- **Borrar `C:\Windows\Installer` o `$PatchCache$`.** Sin esos archivos no se pueden reparar ni desinstalar programas.
- **Borrar la caché de miniaturas.** Exige cerrar el Explorador de Windows y libera muy poco.
- **`docker volume prune` o `docker image prune -a`.** Los volúmenes guardan las bases de datos de los proyectos.
- **Instalar actualizaciones de Windows, drivers o BIOS.** Solo se informan (paso 16).
- **Cerrar VS Code.** Puede haber archivos sin guardar.
- **Tocar historial, cookies, contraseñas o sesiones** de navegadores y apps.
- **Borrar la carpeta del almacén de pnpm o la caché de Yarn 2+.** Los proyectos dependen de ellas.

---

## 3. Reglas de trabajo con el usuario

- **Nunca ejecutar `limpiar.ps1` ni `limpiar.bat`.** Borran archivos, detienen servicios, actualizan apps y piden UAC. El usuario lo ejecuta y después pide "validar/revisar el log" (`limpieza.log`, que se sobrescribe en cada ejecución).
- **El `README.md` siempre al día y fiel al script.** Nunca debe describir algo que el script ya no hace, ni omitir algo que sí hace. En cada cambio a `limpiar.ps1`, `limpiar.bat`, `lib\*.ps1` o al formato de `correo.json`, en el mismo turno y sin que lo pidan:
  - actualizar las secciones afectadas: archivos, preguntas, pasos y su numeración, pasos de administrador, resumen final, correo, configuración, recomendaciones y "Lo que no hace";
  - agregar una entrada con fecha en "Historial de cambios" (la más reciente arriba);
  - releer el README contra el script para confirmar que nada más quedó desactualizado.
- **Este `CLAUDE.md` también se mantiene al día** en el mismo turno (ver sección 9).
- **Todo lo útil tiene que quedar en `limpieza.log`** (ver 6.2).
- **No enviar correos** (por ejemplo, para probar Resend) sin preguntar antes.
- **Revisiones elevadas de solo lectura** (puntos de restauración, instantáneas, etc.): escribir un `.ps1` pequeño en el scratchpad y ejecutarlo con `Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -File ...`, guardando el resultado en un archivo de `%TEMP%`. El usuario tiene que aceptar el UAC, así que hay que avisarle antes.
- **Repositorio público.** `correo.json`, `limpieza.log`, `historial.csv` y `*.lnk` están en `.gitignore`. Nunca subir datos personales: correos, nombre del equipo, rutas del usuario, nombres de proyectos. `correo.json` guarda la **API key de Resend**: nunca copiarla al README, al log, al chat ni a otro archivo. Mantener `correo.ejemplo.json` igual al formato real.
- No hacer commit salvo que el usuario lo pida.

---

## 4. Arquitectura

### 4.1 Archivos

| Archivo | Rol |
|---|---|
| `limpiar.bat` | Comprueba si tiene permisos de administrador con `net session`; si no, se relanza con `Start-Process -Verb RunAs`. Después ejecuta `limpiar.ps1` con `-ExecutionPolicy Bypass`. |
| `limpiar.ps1` | Flujo principal: funciones de apoyo, configuración, preguntas, los 16 pasos numerados, resumen, historial y correo. |
| `lib\resumen.ps1` | Presentación del resumen: consola + HTML del correo. |
| `lib\salud.ps1` | Datos de salud del equipo (solo lectura). |
| `lib\historial.ps1` | `historial.csv`: última ejecución, tendencia del espacio, `Format-Hace`. |
| `lib\correo.ps1` | Lectura de `correo.json` y envío con Resend. |
| `crear-acceso-directo.ps1` | Crea el acceso directo del Escritorio con `limpiar.ico`. |
| `limpiar.ico` | Icono (negro con rojo neón; PNG de 16 a 256 px dentro del `.ico`). |
| `correo.ejemplo.json` | Plantilla pública de `correo.json`. |

### 4.2 Flujo de `limpiar.ps1`

1. `Start-Transcript`: el transcript **es** `limpieza.log`, y la salida de `Write-Host` también queda registrada.
2. Carga los módulos de `lib\` con dot-sourcing.
3. Define las funciones de apoyo y la configuración.
4. **Inicio:** recuadro (`Write-CajaConsola`), reúne los datos que necesitan las preguntas y arma `$preguntas`, solo con las que aplican ahora. Cada pregunta tiene `Clave`, `Titulo` y `Detalle`.
5. **Preguntas:** se muestran como tarjetas numeradas (`[2/6]`) con `Read-SiNo`: S/si/N/no, Enter = No, y vuelve a preguntar si la respuesta no es válida. Como `Read-Host` no queda en el transcript, `Read-SiNo` repite `-> SI` / `-> NO` en su propia línea. Las respuestas van a `$respuestas[Clave]` y se pasan a `$cerrarNav`, `$cerrarApp`, `$borrarRestos`, `$hacerDism`, `$hacerReparacion`, `$borrarImagenesDocker`, `$hacerCompactar`, `$hacerActualizar`, `$borrarNuget` y `$borrarLogsPm2`.
6. **Pasos 1 a 16**, sin intervención. Los que necesitan administrador van agrupados en `if ($esAdmin) { ... } else { Log "Pasos X a Y omitidos..." }`: hoy son el 2-3 y el 7-14. Al agregar pasos hay que actualizar ese mensaje. Los pasos 15 y 16 corren fuera del grupo y saltan solos sus partes de administrador.
7. `Show-Resumen` (con un hashtable que incluye `Salud`, del paso 16, y `Tendencia`), después `Add-Ejecucion` al historial (después del resumen, para incluir la cantidad de avisos) y después el correo.
8. `Stop-Transcript`. Se descarta lo que se tecleó durante la ejecución y **solo Enter cierra la ventana**, para que el resumen quede a la vista.

### 4.3 Módulos de `lib\`

- **`resumen.ps1`**: cada función de bloque (`Write-Cabecera`, `Write-Seccion`, `Write-Dato`, `Write-Estado`, `Write-Lista`, `Write-Nota`, `Write-TablaApps`) produce **las dos versiones a la vez**:
  - texto de ancho fijo con colores para la consola y el log (`Out-Resumen`);
  - HTML adaptable para el correo (`Add-Html` en `$resumenHtml`): una tarjeta por sección, filas de tabla y etiquetas de estado; máximo 600 px y 100 % en el celular.

  Nunca escribir contenido del resumen en una sola de las dos versiones. En el correo, solo estilos en línea y tablas (los clientes de correo ignoran `<style>` y flexbox); el texto pasa por `Format-HtmlTexto`. La paleta (negro con rojo neón) está arriba del archivo: `$neon`, `$brilloNeon`, `$fondoHtml`, `$lineaHtml` y `$coloresHtml`. El HTML se declara `color-scheme: dark` para que el modo oscuro del celular no invierta los colores. `Write-Estado` tiene cuatro niveles: `OK`, `AVISO`, `INFO` (solo informa) y `NA` (dato no disponible). Solo `AVISO` se cuenta en `$avisosResumen`, que va en el asunto del correo; lo que el usuario puede tener resuelto de otra forma va como `INFO`. Secciones: Espacio, Salud del equipo (hardware), Windows y seguridad, Programas de inicio, Aplicaciones.
- **`salud.ps1`**: `Get-SaludEquipo`, que se llama en el paso 16 y deja el detalle en el log con `Log`, junta:
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
| `Get-AppsDesactualizadas` | Lee la tabla de `winget upgrade` por la posición de los títulos (funciona en cualquier idioma). |

### 4.5 Configuración (al inicio de `limpiar.ps1`)

| Variable | Valor | Uso |
|---|---|---|
| `$maxPuntos` | 2 | Puntos de restauración que conserva el paso 14 (borra los más viejos con `srclient.dll!SRRemoveRestorePoint`). |
| `$horasTemporales` | 24 | Antigüedad mínima para borrar en los pasos 1 y 2. |
| `$diasVolcados` | 7 | Si hubo un pantallazo azul en estos días, el paso 7 conserva los volcados. |
| `$diasRestosActualizacion` | 10 | Los restos de una actualización grande solo se ofrecen borrar pasado este tiempo. |

También van ahí las listas `$navegadores`, `$appsChat` y `$appsAutoactualizables` (paso 15).

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

### 6.2 Log (`limpieza.log`)

- Todo lo que importa tiene que quedar dentro del transcript: qué se hizo o se saltó y por qué, las respuestas, los errores, el resultado de cada paso, el resumen y si se envió el correo. Lo que no llega solo al transcript se registra a mano: las respuestas de `Read-Host` (`Log`) y la salida de herramientas nativas (con `Log` o `Invoke-Herramienta`).
- Fuera del log: el progreso repetido y los volcados completos de excepciones.
- **Nunca `Write-Host -NoNewline`** en lo que deba leerse bien en el log: el transcript de PS 5.1 corta la línea en cada llamada. Por eso cada línea del resumen es un solo `Write-Host` de un solo color.
- Errores de borrado y de lectura: `-ErrorAction SilentlyContinue -ErrorVariable err`, **no** try/catch, porque los errores atrapados igual quedan escritos en el transcript. Las excepciones a esta regla (COM de Windows Update, Delivery Optimization, correo, batería) usan try/catch porque no hay otra forma.
- Para `Get-WinEvent`, "no hay eventos" llega como error `NoMatchingEventsFound*`: no es un fallo (`Get-EventosSistema`).

### 6.3 Medición del espacio

- Tamaños con `Format-Tamano` (GB desde 1000 MB): con el separador de miles de es-CO, "1.010 MB" se lee como 1 MB.
- **Por el espacio libre del disco**, cuando el tamaño de los archivos no refleja lo real: Delivery Optimization (paso 8; el tamaño aparente es mucho mayor que lo que ocupa), Liberador de espacio y DISM (paso 9).
- **Por lo que achicó el archivo** en la compactación (paso 12): `wsl --shutdown` hace que Windows borre `swap.vhdx` de `%TEMP%` segundos después, y el espacio libre lo contaba de más (~1,2 GB el 2026-11-17).
- **Docker** (paso 11): lo que libera queda dentro de `docker_data.vhdx` y solo vuelve a Windows al compactar. Se muestra aparte y **no** se suma a `$total` (la compactación ya lo cuenta). Por eso el paso 11 va justo antes del 12.

### 6.4 Por paso

- **1-2:** `Clear-Folder -HorasMinimas $horasTemporales`. Los programas en marcha dejan archivos de trabajo sin bloquear en `%TEMP%`; este script borró una vez el scratchpad de Claude Code a mitad de una sesión. Las cachés no necesitan esta protección.
- **4:** los navegadores solo se limpian cerrados o con permiso para cerrarlos. Se tocan solo `Cache`, `Code Cache` y `GPUCache` (Chromium) y `cache2` (Firefox). La caché de VS Code se salta si `Code` está abierto, y nunca se ofrece cerrarlo. Las apps de chat solo se limpian con `Get-CarpetasCache`; si están abiertas se saltan, salvo que se haya autorizado cerrarlas (solo se pregunta si su caché pasa de 50 MB).
- **6:** NuGet respeta `$env:NUGET_PACKAGES` y solo pregunta si pasa de 50 MB. Lo mismo con PM2 (`$env:PM2_HOME`): si el daemon está en marcha (`pm2.pid` apunta a un proceso `node` vivo), se usa `pm2 flush`, porque borrar los archivos que PM2 tiene abiertos no libera nada; si está detenido, `Clear-Folder`. pnpm solo con `pnpm store prune` (los `node_modules` son enlaces a su almacén). Yarn: solo la caché de Yarn 1 (con Plug'n'Play, los proyectos de Yarn 2+ leen su caché). Go: solo `go clean -cache`, no los módulos.
- **7:** los volcados (`MEMORY.DMP`, `Minidump`, `LiveKernelReports`) se conservan si `Get-CuelguesRecientes` ve un pantallazo azul en `$diasVolcados` días, o si no se pudo leer el registro.
- **3:** `Start-Service` va con `-WarningAction SilentlyContinue`. Si no, PowerShell escribe "ADVERTENCIA: Esperando a que se inicie el servicio..." mientras BITS arranca (es normal, pero el usuario lo vio y se preocupó el 24/11/2026). Después se registra el estado final de cada servicio.
- **6 (pnpm):** se ejecuta `pnpm.cmd`, no `pnpm.ps1`: con el `.ps1` de nvm, los avisos que pnpm escribe en stderr aparecían en el log como `NativeCommandError` en rojo, y cada línea salía repetida.
- **9:** los restos de actualización y los drivers reemplazados se borran **solo** con `Invoke-LiberadorEspacio`, nunca a mano. Caso real del 24/11/2026: con solo "Device Driver Packages", el Liberador pasó más de una hora sin terminar, la ejecución quedó trabada y el usuario apagó el equipo, así que la marca `StateFlags0042` quedó puesta. Por eso:
  - se espera con `WaitForExit` y un tiempo máximo de 20 min, no con `Start-Process -Wait`, que también espera a los procesos que el Liberador deje abiertos;
  - al inicio del script se llama a `Remove-PerfilLiberador`. Los restos solo se preguntan si ninguno es más nuevo que `$diasRestosActualizacion` y suman más de 100 MB. Los drivers se incluyen cuando se responde S a DISM. Error `0x800f0806` de DISM = hay operaciones pendientes: reiniciar y volver a ejecutar.
- **11:** sin preguntar, solo los cuatro `prune` sin riesgo (contenedores, imágenes huérfanas, caché de compilación, redes). Las imágenes sin usar solo se borran con S y solo las que se listaron, por nombre (`docker rmi <tag>`). **Nunca `docker volume prune`.**
- **12:** primero `fstrim`: `fstrim -a` en las distribuciones normales y `fstrim /mnt/docker-desktop-disk` en `docker-desktop` (solo con Docker Desktop abierto). Sin ese paso, 1,3 GB de imágenes borradas nunca volvieron a Windows. Docker Desktop se vuelve a abrir con `explorer.exe`, para que no herede el permiso de administrador. Si `diskpart compact` falla, se ejecuta `detach vdisk` para no dejar el disco conectado.
- **15:** `$estadoWinget` (`ok`, `al dia`, `no instalado`, `error (codigo N)`). "Al día" solo cuando winget sale con 0 o -1978335212; nunca a partir de una lista vacía. `$appsAutoactualizables` (App Installer, Edge, Spotify) sale como "Se actualizan solas". `$seActualizo` decide qué presentación usa el resumen, no si algo se actualizó. Si winget dice que instaló una app pero la sigue listando, cuenta como fallida.
- **16:** la búsqueda de Windows Update tarda; las fechas de su historial vienen en UTC (`ToLocalTime()`). WinRE se lee solo de la línea de estado de `reagentc /info` (`Get-EstadoWinRE`). Respaldo: si Documentos y Escritorio no están en OneDrive ni en el Historial de archivos, sale como `INFO`, no como `AVISO` (lo decidió el usuario el 25/11/2026: en su PC es así a propósito). `Repair-Volume -Scan` no es solo lectura: NTFS corrige en línea lo que puede (eventos 130 de `Ntfs` en System) y deja para `chkdsk /spotfix` lo que necesita C: libre. Niveles: corregido en línea → `OK`; necesita SpotFix → `INFO`; cualquier otro error → `AVISO` (`chkdsk C: /f`). Lo que necesita SpotFix es menor por definición (entradas de índice, vínculos) y el estado del disco se vigila aparte con sus contadores. Caso real del 25/11/2026: quedó pendiente una entrada `$I30` de `\Windows\Prefetch`, pero en esa versión de prueba de Windows (26300) no abrían `chkdsk.exe`, `chkntfs.exe` ni `autofmt.exe` ("Acceso denegado" aun como admin), y `Repair-Volume -SpotFix` / `-OfflineScanAndFix` devolvían `Failed`. Como `AVISO` se habría repetido en cada ejecución sin poder resolverse. El detalle sale del informe de la revisión (Application, proveedor `Chkdsk`, evento 26226) y va al log; para más contexto, ver los eventos 98 y 130 de `Ntfs`.

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
1. Revisión de sintaxis de `limpiar.ps1` y de cada `lib\*.ps1` (8.2).
2. Revisión de solo ASCII (debe dar 0).
3. Probar las funciones nuevas en solo lectura (8.2), sin ejecutar el script.
4. Si cambió el resumen o el correo: vista previa en el navegador, también en tamaño celular.
5. README actualizado (sección 3) y este archivo (sección 9).
6. Contarle al usuario qué no se pudo probar sin una ejecución real (normalmente, lo que necesita permisos de administrador).

### 8.2 Comandos

Sintaxis, sin ejecutar nada (en `limpiar.ps1` y en cada `lib\*.ps1`):
```powershell
$e = $null; [System.Management.Automation.Language.Parser]::ParseFile("$PWD\limpiar.ps1", [ref]$null, [ref]$e) | Out-Null; if ($e) { $e } else { "Sintaxis OK" }
```

Solo ASCII (debe imprimir 0):
```powershell
@(Select-String -Path limpiar.ps1, lib\*.ps1 -Pattern '[^\x00-\x7F]').Count
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
