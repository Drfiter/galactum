@echo off
REM Galactum MVP - juego local (servidor SGM+SSS embebido, sin red).
setlocal
set "ROOT=%~dp0"
set "GODOT=%ROOT%Godot\Godot_v4.6.2-stable_win64.exe"
if not exist "%GODOT%" (
  where godot >nul 2>nul && (set "GODOT=godot") || (
    echo No se encontro Godot. Copia Godot_v4.6.2-stable_win64.exe dentro de la carpeta Godot.
    pause
    exit /b 1
  )
)
if not exist "%ROOT%.godot\imported" (
  echo Preparando recursos del proyecto ^(solo la primera vez, ~1 minuto^)...
  "%GODOT%" --headless --path "%ROOT%." --import >nul 2>nul
)
start "" "%GODOT%" --path "%ROOT%."
