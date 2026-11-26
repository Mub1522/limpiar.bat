---
name: reglas-memoria
description: Cómo se organiza, escribe y mantiene la memoria de Claude Code (memory-global y memory-local); leer antes de crear, mover o cambiar una memoria
metadata:
  type: reference
  actualizado: 2026-11-26
---

# Reglas de la memoria

Lo pidió el usuario el 2026-11-26: memoria **dentro del proyecto**, ordenada y con reglas para que siga útil a largo plazo. Las reglas y lo que vale en cualquier PC se versionan (`memory-global/`), para que todos sus equipos tengan lo mismo; lo de cada PC queda fuera de git (`memory-local/`).

**Estas reglas son solo de este proyecto.** `~/.claude/CLAUDE.md` no tiene reglas de memoria: solo las preferencias generales del usuario, y no se le agrega nada sin consultarlo antes (lo decidió el usuario el 2026-11-26). Para cambiar una regla, se cambia aquí y se sube con el flujo normal del repo.

## 1. Dónde va cada cosa

| Qué es | Dónde va | ¿Se sube? |
|---|---|---|
| Preferencia del usuario para todos los proyectos (idioma, estilo) | `~/.claude/CLAUDE.md`, sección 1, **solo si el usuario lo aprueba antes** | No (cada PC) |
| Regla técnica del código que cualquiera que lo modifique necesita | `CLAUDE.md` del repo | Sí |
| Regla, decisión o preferencia del proyecto que vale en **cualquier PC** y no tiene datos privados | `memory-global/` | **Sí** |
| Lo que depende de **este PC** (cuentas de git, remotos, rutas, programas instalados) o tiene datos privados (correos, nombres reales, cuentas) | `memory-local/` | No (`.git/info/exclude`) |
| Historia de cambios | Commits o el historial del README, **nunca** en memoria | — |
| Lo que solo sirve en la conversación actual | En ningún lado | — |
| `~/.claude/projects/<proyecto>/memory/` | Solo un `MEMORY.md` de una línea que remite a las carpetas del repo. Nunca contenido | — |

- **Ante la duda entre global y local, va a local.** Pasar algo a global después es fácil; sacar un dato privado de GitHub no (queda en el historial).
- Si el repo es **público**, `memory-global/` se ve en GitHub: releer cada archivo antes de subirlo.
- Ante la duda entre `CLAUDE.md` y memoria: si es una regla del código que necesita cualquier persona que lo modifique, va a `CLAUDE.md`; si es del usuario o de su forma de trabajar, va a memoria.

## 2. Estructura en el proyecto

```
<repo>/
├── CLAUDE.md                 versionado: carga memory-global con @imports
├── CLAUDE.local.md           privado: carga memory-local con @imports
├── memory-global/            versionado: igual en todos los PCs
│   ├── MEMORY.md             índice por tipo
│   ├── REGLAS-MEMORIA.md     este archivo
│   └── NOMBRE-DEL-DATO.md    un dato por archivo
└── memory-local/             privado: solo este PC
    ├── MEMORY.md             índice por tipo
    └── NOMBRE-DEL-DATO.md
```

`memory-local/` y `CLAUDE.local.md` van en `.git/info/exclude`, **no** en `.gitignore`: así no se toca el `.gitignore` del repo y en otro PC cada uno arma los suyos.

## 3. Formato de un archivo

- Nombre en **MAYÚSCULAS** con guiones (`FLUJO-GIT-FORK.md`); `name:` y los enlaces `[[...]]` en kebab-case minúscula.
- Plantilla:

```markdown
---
name: nombre-del-dato
description: Una línea que diga cuándo sirve (se usa para decidir si es relevante)
metadata:
  type: user | feedback | project | reference
  actualizado: AAAA-MM-DD
---

El dato, en pocas líneas.

**Por qué:** la razón o el caso real que lo originó (con fecha).
**Cómo aplicarlo:** qué hacer distinto por saber esto.
```

- `Por qué` y `Cómo aplicarlo` son obligatorios en `feedback` y `project`.
- Los enlaces `[[...]]` pueden cruzar carpetas: una memoria global puede enlazar a una local, aunque en otro PC esa local no exista.

## 4. Reglas de escritura

- **Un dato por archivo.** Si un archivo cubre dos temas o pasa de ~40 líneas (este archivo de reglas es la excepción), dividirlo.
- **Fechas absolutas** (`2026-11-26`), nunca "ayer" o "la semana pasada".
- **Lo que no se deduce del código o de git:** el porqué, las decisiones, los casos reales. No copiar código ni comandos que ya estén en el repo.
- **Nunca secretos** (API keys, contraseñas, tokens), en ninguna de las dos carpetas. Correos y nombres reales solo si hacen falta, y solo en `memory-local/`.
- Pronombres neutros para el usuario y para cualquier persona ("el usuario", "lo pidió"), salvo que se sepa cuáles usa.
- Enlazar memorias relacionadas con `[[nombre]]`.

## 5. Reglas de crecimiento

| Situación | Qué hacer |
|---|---|
| Dato nuevo | Buscar primero en los dos índices: si ya hay un archivo del tema, **actualizarlo** (y su `actualizado`) |
| Archivo nuevo en `memory-global/` | Agregar su línea al índice de esa carpeta y su `@memory-global/...` en `CLAUDE.md` del repo, **en el mismo turno** |
| Archivo nuevo en `memory-local/` | Agregar su línea al índice de esa carpeta y su `@memory-local/...` en `CLAUDE.local.md`, **en el mismo turno** |
| Una memoria local resulta válida en cualquier PC (y no tiene datos privados) | Moverla a `memory-global/` (índices e imports de los dos lados) |
| Una memoria global resulta depender de este PC o tener un dato privado | Moverla a `memory-local/` **y** avisar al usuario: ya está en el historial de git |
| Una memoria resulta falsa o vieja | Corregirla o borrarla en el mismo turno (y quitarla del índice y de su archivo de carga) |
| Una memoria del proyecto parece valer para todos los proyectos | Proponérselo al usuario. Solo si acepta, pasarla a la sección 1 de `~/.claude/CLAUDE.md` y borrarla del proyecto |
| Una memoria se volvió regla del código | Pasarla al `CLAUDE.md` del repo y borrarla de la memoria |
| Más de ~15 memorias o ~300 líneas en total | Cargar con `@` solo los índices y las que se usan en cada sesión; las demás se leen del índice cuando su descripción aplique |

- Índice: una línea por memoria (`- [Título](ARCHIVO.md) — gancho`, ~150 caracteres), sin contenido.
- Antes de recomendar algo que una memoria nombra (archivo, función, opción), comprobar que sigue existiendo.

## 6. Mantenimiento

- **Siempre al día, sin que lo pidan.** Al terminar cada cambio, revisar los dos índices: si una memoria nombra algo que cambió (archivo, comando, rama, flujo, cuenta), corregirla en el mismo turno. Lo mismo con la documentación que el proyecto marque como obligatoria (README, `CLAUDE.md`). Porque una memoria o un README viejo llevan a errores sin que se note (lo pidió el usuario el 2026-11-26).
- Un cambio en `memory-global/` se sube igual que el código (rama, commit, PR): hasta que se mergea, el otro PC no lo ve.
- Al recorrer un índice, si un `actualizado` tiene más de 3 meses y el dato importa, comprobarlo con el usuario o el repo.
- La línea `Revisado:` de cada índice se actualiza cuando se revisan todas sus memorias.

## 7. Montar la memoria en otro PC

El repo ya trae `memory-global/` y `CLAUDE.md` ya la carga (sección 11). En cada PC nuevo solo falta lo local:

1. `git clone` o `git pull`.
2. Crear `memory-local/MEMORY.md` (índice con las secciones Usuario, Feedback, Proyecto y Referencia). Empieza vacía: lo de cada PC se escribe en cada PC.
3. Crear `CLAUDE.local.md` con `@memory-local/MEMORY.md` y una línea por memoria local.
4. Agregar `memory-local/` y `CLAUDE.local.md` a `.git/info/exclude` y comprobar con `git check-ignore -v memory-local/MEMORY.md CLAUDE.local.md`.
5. Dejar en `~/.claude/projects/<proyecto>/memory/MEMORY.md` la línea que remite a las carpetas del repo. Si ese directorio ya tenía memorias, migrarlas con estas reglas y dejar solo la línea.

`~/.claude/CLAUDE.md` de ese PC no necesita nada de la memoria. Si le falta la sección 1 (preferencias del usuario), preguntarle al usuario antes de copiarla.