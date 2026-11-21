# Limpieza de Windows

Script para limpiar y mantener Windows. Se ejecuta con doble clic, muestra un log de lo que va haciendo y al terminar muestra un resumen, lo envia por correo y espera a que presiones Enter.

## Archivos

| Archivo | Para que sirve |
|---|---|
| `limpiar.bat` | El que se ejecuta con **doble clic**. Pide permisos de administrador (UAC) y lanza el script. |
| `crear-acceso-directo.ps1` | Crea en el Escritorio el acceso directo `Limpieza Windows` a `limpiar.bat` con el icono de la escoba. Si mueves la carpeta, vuelve a ejecutarlo (el acceso directo guarda rutas completas). |
| `limpiar.ico` | Icono del acceso directo (un `.bat` no puede tener icono propio). |
| `limpiar.ps1` | Los pasos de la limpieza (PowerShell). |
| `lib\resumen.ps1` | El resumen final: lo muestra en pantalla y arma la version HTML para el correo. |
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
- Lo demas es opcional: si un programa no esta (Chrome, Brave, Firefox, Docker, WSL, pip, npm, NuGet, PM2, drivers NVIDIA/AMD), su parte simplemente no encuentra nada y se sigue. Si `winget` no esta instalado, el paso 15 lo avisa en rojo.
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
- **Borrar la cache de NuGet (.NET)** (solo si ocupa mas de 50 MB). Muestra cuanto ocupa; la proxima compilacion de un proyecto .NET volvera a descargar sus paquetes.
- **Vaciar los logs de PM2 (Node.js)** (solo si ocupan mas de 50 MB). Muestra cuanto ocupan; se pierde el historial de salida y errores de las apps, que siguen corriendo.
- **Limpieza profunda (DISM).** Tarda 5-15 min.
- **Revisar y reparar Windows (SFC + DISM).** Tarda 10-40 min (en este equipo, entre 27 y 41 min) y crea un punto de restauracion antes.
- **Borrar imagenes de Docker sin usar** (solo si Docker esta abierto y hay alguna). Muestra la lista exacta con el tamano de cada una; se borran solo esas.
- **Compactar los discos virtuales de Docker/WSL** (solo si existen). Apaga Docker y WSL mientras tanto (los contenedores en marcha se detienen).
- **Actualizar las aplicaciones desactualizadas (winget).** Algunas apps pueden cerrarse mientras se actualizan.

## Pasos

### Limpieza

1. **Temporales del usuario** (`%TEMP%`): solo lo que no se modifico en las ultimas 24 h
2. **Temporales de Windows** (`C:\Windows\Temp`): igual, solo lo de mas de 24 h

   En las carpetas temporales hay archivos de programas que estan trabajando en ese momento (instaladores, Docker, etc.) y que no siempre estan bloqueados; borrarlos puede romper esos programas. Por eso se conserva lo reciente, igual que hace la Liberacion de espacio de Windows. Una carpeta se conserva si cualquier archivo dentro de ella es reciente.
3. **Cache de Windows Update**: detiene sus servicios, borra y los vuelve a iniciar
4. **Cache de navegadores** (Chrome, Edge, Brave, Firefox) **y de VS Code**: solo cache. No toca historial, cookies ni contrasenas. VS Code no se cierra nunca (podria haber archivos sin guardar): si esta abierto, su cache se salta
5. **Cache de shaders de la GPU** (NVIDIA, DirectX, AMD)
6. **Cache de paquetes de desarrollo y logs de PM2**: pip y npm siempre; NuGet (.NET) y los logs de PM2 (`%USERPROFILE%\.pm2\logs`, o `PM2_HOME` si esta definida) si respondiste S. Si PM2 esta en marcha sus logs se vacian con `pm2 flush` (borrarlos no liberaria nada mientras PM2 los tiene abiertos); si esta detenido se borran directamente
7. **Logs de Windows** (CBS y DISM)
8. **Cache de Delivery Optimization**
9. **Limpieza profunda DISM** (si respondiste S)

### Mantenimiento

10. **Reparacion del sistema** (si respondiste S): punto de restauracion, DISM RestoreHealth y SFC
11. **Limpieza de Docker** (solo si Docker Desktop esta abierto):
    - Siempre, sin riesgo: contenedores detenidos, imagenes huerfanas, cache de compilacion y redes sin usar (`docker container/image/builder/network prune`).
    - Si respondiste S: las imagenes sin usar que se listaron en la pregunta (solo esas, por nombre).
    - **Nunca toca los volumenes**: ahi estan las bases de datos de los proyectos.
    - Lo liberado queda libre *dentro* del disco virtual de Docker; vuelve a Windows al compactar (paso 12). Por eso va justo antes.
12. **Compactar discos virtuales de Docker y WSL** (si respondiste S): libera los bloques sin uso (`fstrim`) dentro de Ubuntu y dentro de los datos de Docker, apaga Docker y WSL, compacta cada `.vhdx` y vuelve a abrir Docker Desktop si estaba abierto. No borra nada de adentro, solo achica el archivo. Lo liberado se mide por cuanto achico cada `.vhdx` (no por el espacio libre de C:, que se mezclaria con el archivo de intercambio de WSL que Windows borra al apagarlo). Para recuperar lo que borro Docker, Docker Desktop tiene que estar abierto al empezar (sus datos solo se pueden liberar con Docker en marcha)
13. **TRIM del SSD** (despues de compactar)
14. **Puntos de restauracion**: si hay mas de 2, borra los mas viejos
15. **Aplicaciones desactualizadas (winget)**: siempre las lista; si respondiste S las actualiza una por una. Se saltan las que se actualizan solas: *App Installer* (actualizarlo cierra el propio winget; lo actualiza la Microsoft Store), *Microsoft Edge* (winget no puede actualizarlo; lo hace Edge Update) y *Spotify* (su instalador no funciona como administrador; se actualiza sola). Salen en el resumen como "Se actualizan solas"

### Resumen final

Se muestra en pantalla antes de cerrar, queda en el log y se envia por correo, separado en secciones:

- **Espacio**: total liberado, espacio libre en C: antes y despues, la limpieza anterior (hace cuanto fue y cuanto libero) y cuanto se lleno el disco desde entonces, lo liberado dentro de Docker (y que imagenes se borraron) y tamano de los discos virtuales compactados.
- **Salud del equipo**, cada linea con `[ OK ]`, `[ !! ]` (aviso) o `[ -- ]` (dato no disponible):
  - Disco: estado, vida usada y temperatura del SSD (aviso si la vida usada llega al 80 % o la temperatura a 80 C; un SSD NVMe trabaja normalmente a 60-75 C con carga, y se mide justo despues del TRIM)
  - Espacio en C: GB libres y porcentaje (aviso por debajo del 15 %, cuando Windows y sus actualizaciones empiezan a tener problemas)
  - Bateria (solo portatiles): capacidad actual frente a la original y ciclos (aviso por debajo del 80 %)
  - Recuperacion (WinRE): si el entorno de reparacion de Windows esta activo
  - Reinicio pendiente: si Windows espera un reinicio para terminar actualizaciones
- **Programas que arrancan con Windows**: los habilitados, en dos columnas (solo informa, no desactiva nada).
- **Aplicaciones**: cuales se actualizaron, cuales no se pudieron actualizar (con el motivo), cuales siguen pendientes y cuales se saltaron porque se actualizan solas. Si no se pidio actualizar, la lista de las que tienen actualizacion disponible. Si winget no se pudo consultar (sin internet, no instalado), lo dice en rojo en vez de decir que todo esta al dia.

## Correo con el resumen

Al terminar, el resumen se envia usando [Resend](https://resend.com). Tiene el mismo contenido que la pantalla, pero con diseno de correo: una tarjeta por seccion, etiquetas de color (OK / AVISO / N/D) y nombres completos de las apps. Se adapta al ancho del celular (maximo 600 px en el computador). El asunto incluye el equipo, la fecha, lo liberado y la cantidad de avisos, por ejemplo: `Limpieza MI-PC - 08/10/2026 22:56 - 1.2 GB liberados - 1 aviso(s)`.

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

Solo se hacen los pasos **1, 4, 5, 6 y 15** (en el 15 solo se listan las apps, no se actualizan). Docker tampoco se limpia. El log indica que pasos se omitieron, y en el resumen WinRE y el desgaste del SSD aparecen como no disponibles.

## Configuracion

Al inicio de `limpiar.ps1`:

```powershell
$maxPuntos = 2         # puntos de restauracion a conservar (se borran los mas viejos)
$horasTemporales = 24  # en los pasos 1 y 2 solo se borran temporales sin modificar en este tiempo
```

Y el correo, en `correo.json` (ver arriba).

## Recomendaciones de uso

- **Limpieza normal** (N a DISM y reparacion): cada 2-4 semanas.
- **Reparacion** (S): solo si notas errores o cuelgues, o cada pocos meses.
- **Compactar Docker/WSL** (S): cuando no tengas contenedores haciendo algo importante; tiene sentido despues de borrar imagenes o archivos grandes dentro de Linux.
- El paso 14 cuenta **todos** los puntos de restauracion, incluidos los creados a mano o por Windows Update.
- Para que se puedan crear puntos de restauracion, la Proteccion del sistema debe estar activada en C: (`sysdm.cpl` > Proteccion del sistema).

## Historial de cambios

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
