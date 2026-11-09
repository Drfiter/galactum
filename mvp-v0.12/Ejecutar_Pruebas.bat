@echo off
REM Suite de pruebas canonicas, pruebas del feedback del 26/10 y harness de balance (10.000 combates).
setlocal
set "ROOT=%~dp0"
set "GODOT=%ROOT%Godot\Godot_v4.6.2-stable_win64_console.exe"
if not exist "%GODOT%" set "GODOT=%ROOT%Godot\Godot_v4.6.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=godot"
if not exist "%ROOT%.godot\imported" (
  echo Preparando recursos del proyecto ^(solo la primera vez, ~1 minuto^)...
  "%GODOT%" --headless --path "%ROOT%." --import >nul 2>nul
)
"%GODOT%" --headless --path "%ROOT%." res://tests/run_tests.tscn
"%GODOT%" --headless --path "%ROOT%." res://tests/feedback_checks.tscn
"%GODOT%" --headless --path "%ROOT%." res://tools/balance_harness.tscn -- --n=10000
pause
