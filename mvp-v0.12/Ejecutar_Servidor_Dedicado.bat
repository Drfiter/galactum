@echo off
REM Galactum - Servidor de Sistema Solar (SSS) dedicado por WebSocket.
REM Uso: Ejecutar_Servidor_Dedicado.bat [puerto]   (por defecto 9100)
REM Agrega --fresh al final del comando de abajo para generar un sistema nuevo.
REM Cuentas: el SSS exige iniciar sesion (JWT). Define GALACTUM_JWT_SECRET (32+
REM caracteres) antes de ejecutar para que los tokens sobrevivan a un reinicio;
REM nunca lo guardes en el repositorio. Con --no-auth vuelve el modo demo por nombre.
setlocal
set "ROOT=%~dp0"
set "PORT=%~1"
if "%PORT%"=="" set "PORT=9100"
set "GODOT=%ROOT%Godot\Godot_v4.6.2-stable_win64_console.exe"
if not exist "%GODOT%" set "GODOT=%ROOT%Godot\Godot_v4.6.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=godot"
if not exist "%ROOT%.godot\imported" (
  echo Preparando recursos del proyecto ^(solo la primera vez, ~1 minuto^)...
  "%GODOT%" --headless --path "%ROOT%." --import >nul 2>nul
)
echo Iniciando SSS en el puerto %PORT% ... (no cierres esta ventana)
"%GODOT%" --headless --path "%ROOT%." -- --server --port=%PORT%
pause
