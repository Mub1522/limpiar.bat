# Índice de memoria global: limpiar.bat

Revisado: 2026-11-26 · 2 archivos · **versionado**: igual en todos los PCs, sin datos privados (el repo es público). Reglas en [REGLAS-MEMORIA.md](REGLAS-MEMORIA.md). Lo de cada PC va en `memory-local/`.

## Dónde va cada cosa en este repo

| Qué es | Dónde va | ¿Se sube? |
|---|---|---|
| Reglas, riesgos y trampas del script | `CLAUDE.md` (la sección 9 dice cómo escribirlo) | Sí, sin datos personales |
| Lo que ve el usuario del script, instalación, historial de cambios | `README.md` (la sección 10 de `CLAUDE.md` dice cómo escribirlo) | Sí |
| Reglas y decisiones del proyecto que valen en cualquier PC | `memory-global/` | Sí |
| Flujo de trabajo de este PC, cuentas, datos privados | `memory-local/` | No (`.git/info/exclude`) |
| Problemas de este PC por reintentar | `PENDIENTES.md` | No (`.gitignore`) |

## Usuario
_(ninguna: las preferencias generales están en `~/.claude/CLAUDE.md` §1)_

## Feedback
- [Documentación al día](DOCUMENTACION-AL-DIA.md) — en cada cambio: Requisitos e Instalación del README (CLAUDE.md §10) y memorias; sin que lo pida

## Proyecto
_(ninguna)_

## Referencia
- [Reglas de la memoria](REGLAS-MEMORIA.md) — global vs. local, formato, crecimiento, mantenimiento y cómo montarla en otro PC
