# Limpieza de Windows

Script para limpiar y mantener Windows. Se ejecuta con doble clic, muestra un log de lo que va haciendo y al terminar muestra un resumen, lo envia por correo y espera a que presiones Enter.

## Archivos

| Archivo | Para que sirve |
|---|---|
| `limpiar.bat` | El que se ejecuta con **doble clic**. Pide permisos de administrador (UAC) y lanza el script. |
| `crear-acceso-directo.ps1` | Crea en el Escritorio el acceso directo `Limpieza Windows` a `limpiar.bat` con el icono de la escoba (negro con rojo neon). Si mueves la carpeta, vuelve a ejecutarlo (el acceso directo guarda rutas completas). |
| `limpiar.ico` | Icono del acceso directo (un `.bat` no puede tener icono propio). |
| `limpiar.ps1` | Los pasos de la limpieza (PowerShell). |
| `lib\resumen.ps1` | El resumen final: lo muestra en pantalla y arma la version HTML para el correo. |
| `lib\salud.ps1` | Los datos de salud del equipo para el resumen (Windows Update, disco, errores de hardware, seguridad, respaldo...). Solo lee, no cambia nada. |
| `lib\correo.ps1` | El envio del resumen por correo con Resend. |
| `lib\historial.ps1` | Guarda cada ejecucion en `historial.csv` y la lee para comparar con la anterior. |
| `historial.csv` | Una linea por ejecucion: fecha, MB liberados, espacio libre al terminar y avisos (se conservan las ultimas 200). Se crea solo. |
| `correo.json` | Configuracion del correo, **incluida la API key de Resend**. No lo compartas. Es opcional: se crea copiando `correo.ejemplo.json`. |
| `correo.ejemplo.json` | Plantilla de `correo.json` sin datos reales. |
| `limpieza.log` | Log de la **ultima** ejecucion. Se reemplaza cada vez. Guarda todo lo util: tus respuestas, que hizo u omitio cada paso, errores y el resumen final. |

`correo.json`, `limpieza.log`, `historial.csv` y el acceso directo (`.lnk`) son de cada equipo y estan en `.gitignore`: nunca se suben al repositorio.

## Requisitos

- Windows 10 u 11, instalado en C:.
- Windows PowerShell 5.1 (viene con Windows) y permisos de administrador (se piden con la ventana de UAC).
- Lo demas es opcional: si un programa no esta (Chrome, Brave, Firefox, Teams, Discord, Slack, Docker, WSL, pip, npm, Yarn, pnpm, Go, NuGet, PM2, drivers NVIDIA/AMD), su parte simplemente no encuentra nada y se sigue. Si `winget` no esta instalado, el paso 15 lo avisa en rojo.
- Pensado para Windows en espanol o ingles. En otros idiomas funciona igual, pero el estado de WinRE puede aparecer como "N/D".

## Como usarlo

1. Doble clic en `limpiar.bat`. Opcional: ejecuta una vez `crear-acceso-directo.ps1` (clic derecho > *Ejecutar con PowerShell*) para tener en el Escritorio un acceso directo con icono.
2. Acepta la ventana de permisos de administrador.
3. Responde las preguntas del inicio.
4. Espera a que aparezca el resumen y presiona **Enter** para cerrar. Ninguna otra tecla cierra la ventana, y las teclas presionadas durante la ejecucion se descartan.

## Preguntas (todas al inicio)

Al abrirse, el script muestra un encabezado (equipo, fecha y si corre como administrador) y luego las preguntas, cada una en su tarjeta numerada (`[1/6]`, `[2/6]`...) con una explicacion corta debajo. Solo aparecen las que aplican en ese momento. Despues de responderlas el script corre solo, sin pedir nada mas.

Se responde con `S`/`si` o `N`/`no` (mayusculas o minusculas). **Enter sin escribir nada = No.** Cualquier otra respuesta se vuelve a preguntar. Debajo de cada pregunta queda la respuesta (`-> SI` / `-> NO`), tambien en el log.

- **Cerrar el navegador** (solo si hay uno abierto) para limpiar su cache. Se cierra recien al llegar al paso 4.
- **Cerrar Teams, Discord o Slack** (solo si esta abierto y su cache pasa de 50 MB) para limpiar su cache. Se cierra al llegar al paso 4 y no se vuelve a abrir solo; si estas en una llamada, responde N.
- **Borrar la cache de NuGet (.NET)** (solo si ocupa mas de 50 MB). Muestra cuanto ocupa; la proxima compilacion de un proyecto .NET volvera a descargar sus paquetes.
- **Vaciar los logs de PM2 (Node.js)** (solo si ocupan mas de 50 MB). Muestra cuanto ocupan; se pierde el historial de salida y errores de las apps, que siguen corriendo.
- **Limpieza profunda (DISM).** Tarda 5-15 min. Borra versiones viejas de componentes de Windows Update: despues no se pueden desinstalar las actualizaciones ya instaladas.
- **Borrar los restos de la ultima actualizacion grande de Windows** (`Windows.old`, `$WINDOWS.~BT`, `$WINDOWS.~WS`; solo si existen, ocupan mas de 100 MB y ninguno se modifico en los ultimos 10 dias). Muestra cada carpeta con su tamano. Despues ya no se puede volver a la version anterior de Windows.
- **Revisar y reparar Windows (SFC + DISM).** Tarda 10-60 min (en las ejecuciones reales, entre 27 y 52 min) y crea un punto de restauracion antes.
- **Borrar imagenes de Docker sin usar** (solo si Docker esta abierto y hay alguna). Muestra la lista exacta con el tamano de cada una; se borran solo esas.
- **Compactar los discos virtuales de Docker/WSL** (solo si existen). Apaga Docker y WSL mientras tanto (los contenedores en marcha se detienen).
- **Actualizar las aplicaciones desactualizadas (winget).** Algunas apps pueden cerrarse mientras se actualizan.

## Pasos

### Limpieza

1. **Temporales del usuario** (`%TEMP%`): solo lo que no se modifico en las ultimas 24 h
2. **Temporales de Windows** (`C:\Windows\Temp`): igual, solo lo de mas de 24 h

   En las carpetas temporales hay archivos de programas que estan trabajando en ese momento (instaladores, Docker, etc.) y que no siempre estan bloqueados; borrarlos puede romper esos programas. Por eso se conserva lo reciente, igual que hace la Liberacion de espacio de Windows. Una carpeta se conserva si cualquier archivo dentro de ella es reciente.
3. **Cache de Windows Update**: detiene sus servicios, borra y los vuelve a iniciar. El log dice si cada servicio quedo en marcha (si alguno no, Windows lo inicia solo cuando lo necesita)
4. **Cache de navegadores** (Chrome, Edge, Brave, Firefox), **de VS Code y de apps de chat** (Teams, Teams clasico, Discord, Slack): solo cache (carpetas `Cache`, `Code Cache` y `GPUCache`). No toca historial, cookies, contrasenas, sesiones ni mensajes. VS Code no se cierra nunca (podria haber archivos sin guardar): si esta abierto, su cache se salta. Las apps de chat abiertas tambien se saltan, salvo que respondieras S a cerrarlas
5. **Cache de shaders de la GPU** (NVIDIA, DirectX, AMD)
6. **Cache de paquetes de desarrollo y logs de PM2**: siempre pip, npm, Yarn 1, pnpm (`pnpm store prune`: solo los paquetes que ya no usa ningun proyecto) y la cache de compilacion de Go (`go clean -cache`). La cache de Yarn 2+ no se toca (con Plug'n'Play los proyectos leen los paquetes de ahi), ni los modulos de Go. Ademas, NuGet (.NET) y los logs de PM2 (`%USERPROFILE%\.pm2\logs`, o `PM2_HOME` si esta definida) si respondiste S. Si PM2 esta en marcha sus logs se vacian con `pm2 flush` (borrarlos no liberaria nada mientras PM2 los tiene abiertos); si esta detenido se borran directamente
7. **Logs, volcados de memoria e informes de error de Windows**: logs CBS y DISM, informes de error ya enviados o en cola (`ProgramData\Microsoft\Windows\WER`) y los volcados de memoria de los pantallazos azules (`MEMORY.DMP`, `Minidump`, `LiveKernelReports`). Los volcados solo sirven para averiguar la causa de un pantallazo azul: si hubo uno en los ultimos 7 dias (o no se pudo leer el registro de eventos) se conservan
8. **Cache de Delivery Optimization**
9. **Limpieza profunda**, cada parte si respondiste S. Si el Liberador de espacio no termina en 20 minutos, se cierra y la limpieza sigue con lo demas; si una ejecucion se corta a mitad, la siguiente quita el perfil temporal que haya quedado:
   - **Restos de la ultima actualizacion grande** (`Windows.old`, `$WINDOWS.~BT`, `$WINDOWS.~WS`): los borra el Liberador de espacio de Windows (`cleanmgr /sagerun`, con un perfil de una sola vez que se quita al terminar), que es la forma que indica Microsoft. Lo liberado se mide por el espacio libre del disco. Si tienen menos de 10 dias se conservan sin preguntar (puede ser una actualizacion en curso, o una que todavia se puede deshacer)
   - **DISM**: borra versiones viejas de componentes de Windows Update. Si Windows tiene actualizaciones esperando un reinicio, DISM falla (error `0x800f0806`) y el log indica que hay que reiniciar y volver a ejecutar

### Mantenimiento

10. **Reparacion del sistema** (si respondiste S): punto de restauracion, DISM RestoreHealth y SFC
11. **Limpieza de Docker** (solo si Docker Desktop esta abierto):
    - Siempre, sin riesgo: contenedores detenidos, imagenes huerfanas, cache de compilacion y redes sin usar (`docker container/image/builder/network prune`).
    - Si respondiste S: las imagenes sin usar que se listaron en la pregunta (solo esas, por nombre).
    - **Nunca toca los volumenes**: ahi estan las bases de datos de los proyectos.
    - Lo liberado queda libre *dentro* del disco virtual de Docker; vuelve a Windows al compactar (paso 12). Por eso va justo antes.
12. **Compactar discos virtuales de Docker y WSL** (si respondiste S): libera los bloques sin uso (`fstrim`) dentro de Ubuntu y dentro de los datos de Docker, apaga Docker y WSL, compacta cada `.vhdx` y vuelve a abrir Docker Desktop si estaba abierto. No borra nada de adentro, solo achica el archivo. Lo liberado se mide por cuanto achico cada `.vhdx` (no por el espacio libre de C:, que se mezclaria con el archivo de intercambio de WSL que Windows borra al apagarlo). Para recuperar lo que borro Docker, Docker Desktop tiene que estar abierto al empezar (sus datos solo se pueden liberar con Docker en marcha)
13. **TRIM del SSD** (despues de compactar). Si falla, el log dice por que y el resumen lo avisa (por ejemplo, Windows no lo hace mientras C: tenga una reparacion pendiente)
14. **Puntos de restauracion**: si hay mas de 2, borra los mas viejos
15. **Aplicaciones desactualizadas (winget)**: siempre las lista; si respondiste S las actualiza una por una. Se saltan las que se actualizan solas: *App Installer* (actualizarlo cierra el propio winget; lo actualiza la Microsoft Store), *Microsoft Edge* (winget no puede actualizarlo; lo hace Edge Update) y *Spotify* (su instalador no funciona como administrador; se actualiza sola). Salen en el resumen como "Se actualizan solas". Si winget dice que instalo una app pero despues la sigue listando como desactualizada, sale en "No se pudieron actualizar" con ese motivo (no como actualizada ni como pendiente)

### Revision

16. **Revision de salud del equipo** (solo lectura, no cambia nada; tarda alrededor de un minuto): consulta Windows Update (las actualizaciones pendientes y opcionales, la ultima instalada y las que fallaron; no instala nada), revisa el sistema de archivos de C: sin reiniciar (`Repair-Volume -Scan`, solo como administrador; Windows corrige en el momento los errores menores que puede, como hace por su cuenta) y junta el resto de los datos de salud del resumen. El detalle (titulos de las actualizaciones, etc.) queda en el log

### Resumen final

Se muestra en pantalla antes de cerrar, queda en el log y se envia por correo. El encabezado indica el equipo, la version de Windows y la fecha. Esta separado en secciones; en las de salud cada linea lleva `[ OK ]`, `[ !! ]` (aviso), `[ i  ]` (solo informa; no cuenta como aviso) o `[ -- ]` (dato no disponible):

- **Espacio**: total liberado (en GB desde 1000 MB), espacio libre en C: antes y despues, la limpieza anterior (hace cuanto fue y cuanto libero) y cuanto se lleno el disco desde entonces, la **tendencia** (cuantos GB por mes se pierden aunque se limpie, calculada con las limpiezas de los ultimos 120 dias, cuando hay al menos 4 y 14 dias de historial, y en cuantos meses C: bajaria del 15 % libre; si el espacio libre sube, dice "no se esta llenando"), lo liberado dentro de Docker (y que imagenes se borraron) y tamano de los discos virtuales compactados.
- **Salud del equipo** (hardware):
  - Disco: estado, vida usada, temperatura y horas de uso del SSD. Aviso si la vida usada llega al 80 %, la temperatura a 80 C (un SSD NVMe trabaja normalmente a 60-75 C con carga, y se mide justo despues del TRIM) o si hay errores de lectura que el disco no pudo corregir (la senal mas clara de que esta fallando)
  - Sistema de archivos: resultado de la revision del paso 16. Si Windows ya corrigio los errores en linea, sale OK. Si queda un error menor (por ejemplo, una entrada de indice de una carpeta), sale como informacion, con el detalle en el log y el comando para corregirlo (`chkdsk C: /spotfix` como administrador y reiniciar). Si necesita una revision completa, sale como aviso (`chkdsk C: /f`)
  - TRIM del SSD: solo aparece si el TRIM del paso 13 fallo, como aviso y con el motivo
  - Espacio en C: GB libres y porcentaje (aviso por debajo del 15 %, cuando Windows y sus actualizaciones empiezan a tener problemas)
  - Bateria (solo portatiles): capacidad actual frente a la original y ciclos (aviso por debajo del 80 %)
  - Hardware (30 dias): errores de memoria RAM, CPU o disco que registra Windows (WHEA). Aviso si hay alguno grave o 10 o mas corregidos (unos pocos corregidos son normales)
  - Cuelgues (30 dias): pantallazos azules y apagados inesperados (cortes de luz, boton de encendido), segun el registro de eventos de Windows (eventos 1001 y 41); aviso si hubo alguno
- **Windows y seguridad**:
  - Windows Update: cuantas actualizaciones faltan y hace cuanto se instalo la ultima. Aviso si alguna fallo y no se volvio a instalar, o si pasaron mas de 45 dias sin instalar nada (Windows instala cada mes). Las opcionales (drivers, vistas previas) se mencionan aparte
  - Antivirus (Defender): aviso si la proteccion en tiempo real esta desactivada o sus firmas tienen mas de 7 dias. Si otro antivirus esta a cargo, aparece como no disponible
  - Seguridad: aviso si estan apagados el firewall (en alguna red), el control de cuentas (UAC) o el Arranque seguro. Tambien dice si C: esta cifrado con BitLocker (solo informa)
  - Respaldo de archivos: si Documentos y Escritorio estan en OneDrive (y OneDrive abierto) o si el Historial de archivos esta configurado. Si no, solo se informa (`[ i  ]`): no cuenta como aviso, porque puedes respaldar de otra forma
  - Punto de restauracion (solo administrador): el mas reciente; aviso si no hay ninguno
  - Ultimo reinicio: aviso si pasaron mas de 14 dias. Con el Inicio rapido de Windows, Apagar no cuenta: solo Reiniciar
  - Recuperacion (WinRE): si el entorno de reparacion de Windows esta activo
  - Reinicio pendiente: si Windows espera un reinicio para terminar actualizaciones
- **Programas que arrancan con Windows**: los habilitados, en dos columnas (solo informa, no desactiva nada).
- **Aplicaciones**: cuales se actualizaron, cuales no se pudieron actualizar (con el motivo), cuales siguen pendientes y cuales se saltaron porque se actualizan solas. Si no se pidio actualizar, la lista de las que tienen actualizacion disponible. Si winget no se pudo consultar (sin internet, no instalado), lo dice en rojo en vez de decir que todo esta al dia.

## Correo con el resumen

Al terminar, el resumen se envia usando [Resend](https://resend.com). Tiene el mismo contenido que la pantalla, pero con diseno de correo en negro con rojo neon: una tarjeta por seccion, etiquetas de color (OK / AVISO / N/D) y nombres completos de las apps. Se adapta al ancho del celular (maximo 600 px en el computador). El asunto incluye el equipo, la fecha, lo liberado y la cantidad de avisos, por ejemplo: `Limpieza MI-PC - 08/10/2026 22:56 - 1.2 GB liberados - 1 aviso(s)`.

Es opcional. Para activarlo, crea una cuenta en Resend, copia `correo.ejemplo.json` como `correo.json` (en la misma carpeta que `limpiar.bat`) y pon tu API key y tu correo:

```json
{
  "activo": true,
  "apiKey": "re_...",
  "de": "Limpieza Windows <onboarding@resend.dev>",
  "para": "tu-correo@ejemplo.com"
}
```

- `"activo": false` desactiva el envio sin borrar la configuracion. Si `correo.json` no existe, tampoco se envia.
- Con el remitente `onboarding@resend.dev` Resend solo permite enviar al correo de la cuenta de Resend.
- Si el envio falla (sin internet, API key invalida...), la limpieza no se ve afectada: el log y la pantalla muestran el motivo.
- **`correo.json` contiene la API key**: no lo compartas ni lo subas a ningun sitio. Si se filtra, revocala en el panel de Resend y genera otra.

## Sin permisos de administrador

Solo se hacen los pasos **1, 4, 5, 6, 15 y 16** (en el 15 solo se listan las apps, no se actualizan). Docker tampoco se limpia. El log indica que pasos se omitieron, y en el resumen WinRE, el desgaste del SSD, el sistema de archivos, el cifrado del disco y el punto de restauracion aparecen como no disponibles.

## Configuracion

Al inicio de `limpiar.ps1`:

```powershell
$maxPuntos = 2         # puntos de restauracion a conservar (se borran los mas viejos)
$horasTemporales = 24  # en los pasos 1 y 2 solo se borran temporales sin modificar en este tiempo
$diasVolcados = 7      # paso 7: si hubo un pantallazo azul en estos dias, se conservan los volcados de memoria
$diasRestosActualizacion = 10  # paso 9: restos de una actualizacion grande solo se ofrecen borrar pasado este tiempo
```

Y el correo, en `correo.json` (ver arriba).

## Recomendaciones de uso

- **Limpieza normal** (N a DISM y reparacion): cada 2-4 semanas.
- **Reparacion** (S): solo si notas errores o cuelgues, o cada pocos meses.
- **Compactar Docker/WSL** (S): cuando no tengas contenedores haciendo algo importante; tiene sentido despues de borrar imagenes o archivos grandes dentro de Linux.
- El paso 14 cuenta **todos** los puntos de restauracion, incluidos los creados a mano o por Windows Update.
- Para que se puedan crear puntos de restauracion, la Proteccion del sistema debe estar activada en C: (`sysdm.cpl` > Proteccion del sistema).

## Lo que no hace, a proposito

- **Limpiar el registro**: no acelera nada medible y un error puede dejar programas o Windows sin arrancar. Microsoft no da soporte a sistemas danados por limpiadores de registro.
- **Desfragmentar**: en un SSD no sirve y gasta su vida util; Windows ya hace TRIM (paso 13) y desfragmenta solo los discos mecanicos cuando hace falta.
- **Desactivar servicios**: lo que se gana es minimo y puede romper cosas de forma silenciosa (actualizaciones, impresion, Bluetooth, seguridad), a veces semanas despues.
- **"Liberar RAM"**: Windows usa la RAM libre como cache a proposito; vaciarla hace que todo cargue mas lento despues.
- **Borrar `C:\Windows\Installer`**, la cache de miniaturas o instantaneas que no son puntos de restauracion: o es peligroso o libera muy poco.
- **Desactivar programas de inicio**: solo se informan en el resumen; tu decides cuales quitar.

## Historial de cambios

- **2026-11-25** - Tras revisar la segunda ejecucion del dia: la limpieza profunda ya no le pide al Liberador de espacio los drivers ya reemplazados (en tres ejecuciones libero 0 MB y tardo mas de una hora, 9 minutos y 20 minutos). Paso 13: si el TRIM falla, el log muestra el motivo (antes salia el error de PowerShell repetido y despues "TRIM terminado") y el resumen agrega la linea "TRIM del SSD" como aviso. Paso 8: la cache de Delivery Optimization se vacia en un proceso aparte, para que el log no muestre "Deleting..." sin hora (redirigir la salida no alcanzaba).
- **2026-11-25** - Correcciones tras la primera ejecucion completa con los pasos nuevos: la tendencia del espacio se calcula con todas las limpiezas de los ultimos 120 dias (recta de minimos cuadrados) en vez de compararse con una sola, y si el espacio libre sube dice "no se esta llenando" (antes decia "ganas 24,6 GB al mes" por archivos borrados a mano). "Sistema de archivos" explica el resultado en espanol: si los errores ya se corrigieron en linea, sale OK; un error menor que solo necesita `chkdsk C: /spotfix` pasa a ser informativo (`[ i  ]`) y el log muestra que carpeta afecta; lo que necesita una revision completa sigue como aviso (`chkdsk C: /f`). El log muestra las fechas de los puntos de restauracion como dia/mes y parte el informe del TRIM en lineas. "hace 1 horas" pasa a "hace 1 hora".
- **2026-11-25** - Correcciones tras la primera ejecucion con los pasos nuevos (24/11): el Liberador de espacio (drivers ya reemplazados, paso 9) paso mas de una hora sin terminar y la ejecucion quedo trabada hasta que se apago el equipo. Ahora tiene un tiempo maximo de 20 minutos y se espera solo a su proceso; si una ejecucion se corta, la siguiente quita el perfil temporal que haya quedado. Paso 3: ya no aparece "ADVERTENCIA: Esperando a que se inicie el servicio BITS" (era normal: BITS tarda unos segundos en arrancar); en su lugar el log dice si cada servicio quedo en marcha. Paso 6: pnpm se ejecuta por `pnpm.cmd`, sin el error rojo ni las lineas repetidas en el log. "Respaldo de archivos" pasa a ser solo informativo (`[ i  ]`, nuevo nivel que no cuenta como aviso).
- **2026-11-24** - Salud y mantenimiento: nuevo paso 16 (revision de solo lectura) con Windows Update (pendientes, ultima instalada y fallidas), revision del sistema de archivos sin reiniciar, errores de hardware (WHEA), chequeo de seguridad (firewall, UAC, Arranque seguro, BitLocker), respaldo de archivos (OneDrive o Historial de archivos) y punto de restauracion mas reciente. El disco suma horas de uso y errores de lectura sin corregir. El resumen separa "Salud del equipo" (hardware) de "Windows y seguridad", muestra la version de Windows en el encabezado y la tendencia del espacio (GB por mes y cuando C: bajaria del 15 %). La limpieza profunda tambien quita los paquetes de drivers ya reemplazados (Liberador de espacio). Los datos de salud pasan a `lib\salud.ps1`. WSL no se agrega aparte: winget ya lo actualiza en el paso 15 (`Microsoft.WSL`).
- **2026-11-24** - Nuevas limpiezas y revisiones de salud, tras investigar que mas se puede hacer de forma segura: paso 4, cache de Teams, Discord y Slack (con pregunta para cerrarlos si estan abiertos y su cache pasa de 50 MB); paso 6, Yarn 1, `pnpm store prune` y `go clean -cache`; paso 7, volcados de memoria (se conservan si hubo un pantallazo azul en los ultimos 7 dias) e informes de error de Windows; paso 9, restos de la ultima actualizacion grande (`Windows.old`, `$WINDOWS.~BT`, `$WINDOWS.~WS`) con pregunta y con el Liberador de espacio de Windows. En Salud del equipo: cuelgues de los ultimos 30 dias, estado del antivirus y dias desde el ultimo reinicio. Nueva seccion "Lo que no hace, a proposito".
- **2026-11-24** - Nuevo estilo negro con rojo neon: el correo del resumen pasa a fondo negro con titulos y bordes en rojo neon (el brillo solo se ve en clientes que lo soportan, como Apple Mail; en Gmail queda el rojo plano) y se marca como oscuro para que el modo oscuro del celular no invierta los colores. Las etiquetas OK / AVISO siguen en verde / amarillo. Nuevo `limpiar.ico` con el mismo estilo; si el acceso directo sigue mostrando el icono anterior, vuelve a ejecutar `crear-acceso-directo.ps1`.

- **2026-11-24** - Correcciones tras revisar una ejecucion en otro equipo: el log del historial no mostraba la cantidad de ejecuciones en la primera (`( registrada(s)`); "Liberado por la limpieza" se muestra en GB desde 1000 MB (`15.823,82 MB` se leia como 15 MB); una app que winget dice instalar pero sigue listando ya no aparece a la vez en "Actualizadas" y "Siguen pendientes"; el paso 9 explica el error `0x800f0806` (reiniciar y volver a ejecutar); la pregunta de reparacion estima 10-60 minutos (una ejecucion tardo 52).
- **2026-11-20** - Paso 6: logs de PM2 (Node.js) con pregunta al inicio, solo si ocupan mas de 50 MB. Con PM2 en marcha se vacian con `pm2 flush`; con PM2 detenido se borran.
- **2026-11-17** - Paso 12: lo liberado al compactar se mide por cuanto achico cada `.vhdx`. Antes se media por el espacio libre de C:, y el archivo de intercambio de WSL que Windows borra al apagarlo se contaba como compactacion (en la ejecucion del 17/11 sumo ~1.2 GB de mas). Paso 15: Spotify se salta como app que se actualiza sola (winget siempre fallaba con "The installer cannot be run from an administrator context").
- **2026-11-17** - Icono: nuevo `limpiar.ico` y `crear-acceso-directo.ps1`, que crea en el Escritorio un acceso directo a `limpiar.bat` con ese icono.
- **2026-11-17** - Preparado para repositorio publico: `.gitignore` (correo.json, log, historial y accesos directos no se suben), plantilla `correo.ejemplo.json`, licencia MIT y seccion de requisitos.
- **2026-10-09** - Historial de ejecuciones (`historial.csv`) y comparacion con la limpieza anterior en el resumen. Aviso en Salud del equipo si C: baja del 15 % libre. Cache de NuGet (.NET) con pregunta en el paso 6. Cache de VS Code en el paso 4 (se salta si VS Code esta abierto). Los tamanos de 1000 MB o mas se muestran en GB.
- **2026-10-09** - La pregunta de reparacion del sistema ahora estima 10-40 minutos (antes 10-20; en las ejecuciones reales tardo 27 y 41 minutos).
- **2026-10-09** - Paso 12: ahora tambien se ejecuta `fstrim` dentro de los datos de Docker antes de compactar. Antes se saltaba, y lo que borraba Docker (1.3 GB de imagenes en la primera prueba) no volvia a Windows: el disco de Docker usaba 4.6 GB por dentro pero el archivo seguia pesando 8 GB.
- **2026-10-09** - Nuevo paso 11: limpieza de Docker (contenedores detenidos, imagenes huerfanas, cache de compilacion y redes sin usar siempre; imagenes sin usar con pregunta que muestra la lista exacta; los volumenes nunca se tocan). Va antes de compactar para que lo liberado vuelva a Windows. Los pasos siguientes pasan a ser 12 (compactar), 13 (TRIM), 14 (puntos de restauracion) y 15 (winget). Inicio redisenado: encabezado y preguntas en tarjetas numeradas con explicacion y la respuesta debajo.
- **2026-10-09** - Revision de errores posibles:
  - Pasos 1 y 2: ya no se borran temporales modificados en las ultimas 24 h. Antes se podian borrar archivos de programas trabajando en ese momento.
  - Paso 14 y resumen: si winget falla o no esta instalado se avisa, en vez de decir "todas las aplicaciones estan al dia". Ya no se recomienda responder S si ya se respondio S y solo quedaban apps que se actualizan solas. Una app que se instala pero pide reiniciar ya no cuenta como error. La lectura de la tabla de winget ya no se corta con filas incompletas ni con apps cuyo nombre empieza con un numero.
  - Paso 10: el mensaje "ya hay un punto de las ultimas 24 h" solo aparece si es cierto.
  - Casos raros que podian cortar el script: una distribucion de WSL registrada sin carpeta, o la ventana cerrada mientras hacia una pregunta.
- **2026-10-09** - Corregido el resumen en el log: cada linea quedaba partida en pedazos (en la ventana se veia bien). Ahora cada linea del resumen va de un solo color. El aviso de temperatura del SSD pasa de 70 C a 80 C (con 70 C saltaria en un uso normal). Quitada una linea vacia que dejaba `wsl --shutdown`.
- **2026-10-09** - Correo redisenado para el celular: antes era texto de ancho fijo que se veia diminuto o cortado; ahora usa tarjetas y filas que se adaptan a la pantalla. Microsoft Edge se salta en el paso 14 (winget siempre fallaba con el; se actualiza solo) y el resumen muestra aparte las apps que se actualizan solas.
- **2026-10-08** - Nuevos pasos 11 (compactar discos virtuales de Docker/WSL) y 14 (aplicaciones desactualizadas con winget); el TRIM pasa a ser el 12 y los puntos de restauracion el 13. Resumen final redisenado por secciones, con salud del equipo (SSD, bateria, WinRE, reinicio pendiente) y resultado de las actualizaciones. Envio del resumen por correo con Resend. El resumen y el correo pasan a `lib\` para que `limpiar.ps1` no crezca.
- **2026-10-08** - Paso 8: lo liberado se mide por el espacio libre del disco. Antes sumaba el tamano aparente de los archivos y mostraba ~4.4 GB que en realidad no se liberaban.
- **2026-10-08** - Las preguntas aceptan S/si/N/no, Enter = No y repiten si la respuesta no es valida. La ventana solo se cierra con Enter (antes cualquier tecla, incluso Alt+Tab o teclas presionadas durante la ejecucion, la cerraba). Menos ruido del TRIM en el log.
- **2026-10-08** - Resumen final en pantalla (espacio, disco y programas de inicio) para verlo sin abrir el log. Agregado el paso de puntos de restauracion (maximo 2).
- **2026-10-08** - Pasos de reparacion (SFC + DISM) y TRIM, y reporte de programas de inicio. Corregido un error al calcular mas de 2 GB y reducido el progreso de DISM/SFC en el log (cada 10 %).
- **2026-10-07** - Pasos 5-9 (shaders, pip/npm, logs de Windows, Delivery Optimization, DISM opcional). Todas las preguntas pasan al inicio.
- **2026-10-07** - Pasos 1-4 (temporales, Windows Update, navegadores). El `.bat` pide permisos de administrador. Un solo archivo de log.
