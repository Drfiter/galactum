@echo off
REM Demo multijugador: levanta el SSS dedicado y abre dos clientes.
REM En cada cliente: "Servidor dedicado" > 127.0.0.1 : 9100 > usuario y contrasena
REM > "Crear cuenta" la primera vez y luego "Entrar" (usa usuarios distintos en
REM cada ventana; apareceran como vecinos en el mapa).
setlocal
set "ROOT=%~dp0"
set "GODOT=%ROOT%Godot\Godot_v4.6.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=godot"
if not exist "%ROOT%.godot\imported" (
  echo Preparando recursos del proyecto ^(solo la primera vez, ~1 minuto^)...
  "%GODOT%" --headless --path "%ROOT%." --import >nul 2>nul
)
start "Galactum SSS" "%GODOT%" --headless --path "%ROOT%." -- --server --port=9100
timeout /t 4 >nul
start "" "%GODOT%" --path "%ROOT%." --position 20,40 --resolution 1100x620
start "" "%GODOT%" --path "%ROOT%." --position 700,420 --resolution 1100x620
