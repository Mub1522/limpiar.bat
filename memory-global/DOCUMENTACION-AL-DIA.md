---
name: documentacion-al-dia
description: Al cerrar cualquier cambio en limpiar.bat, revisar "Requisitos" e "Instalacion en otro equipo" del README y las memorias
metadata:
  type: feedback
  actualizado: 2026-11-26
---

El script tiene que poder usarse en otros equipos, no solo en este. Por eso "Requisitos" e "Instalación en otro equipo" del README tienen que estar siempre al día, igual que las memorias, y respetar sus reglas de estructura.

Dónde están las reglas (no repetirlas aquí):
- README: `CLAUDE.md` del repo, sección 10 (estructura en 10.1 y tabla de "si el cambio... actualizar" en 10.2).
- Memorias: [[reglas-memoria]] (sección 6, "Siempre al día").

**Por qué:** lo pidió el usuario el 2026-11-26, después de que se agregó la guía de instalación: alguien tiene que poder instalarlo en otro PC solo con el README.
**Cómo aplicarlo:** al terminar cada cambio, aunque parezca que no toca esas secciones, recorrer la tabla 10.2 del `CLAUDE.md` y los índices de `memory-global/` y `memory-local/`, y corregir en el mismo turno lo que haya quedado viejo, sin esperar a que lo pida.
