@echo off
title Crear acceso directo - Limpieza de Windows

rem Doble clic aqui. Llama a crear-acceso-directo.ps1 con -ExecutionPolicy Bypass (solo para
rem esta vez): un .ps1 abierto con doble clic se abre en el Bloc de notas, y con
rem "Ejecutar con PowerShell" puede fallar por la politica de ejecucion de scripts.
rem No necesita permisos de administrador.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0crear-acceso-directo.ps1"
echo.
pause
