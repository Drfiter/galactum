@echo off
REM Abre el proyecto en el editor de Godot (para exportar a Android: Proyecto > Exportar).
setlocal
set "ROOT=%~dp0"
set "GODOT=%ROOT%Godot\Godot_v4.6.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=godot"
start "" "%GODOT%" -e --path "%ROOT%."
