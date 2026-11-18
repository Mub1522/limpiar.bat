@echo off
title Limpieza de Windows

rem Si no somos administrador, nos relanzamos pidiendo permisos (UAC)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Pidiendo permisos de administrador...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" || (
        echo Permisos denegados. No se ejecuto la limpieza.
        pause
    )
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0limpiar.ps1"
