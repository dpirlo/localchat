@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar-windows.ps1" %*
if errorlevel 1 (
  echo.
  echo La instalacion no pudo completarse.
  pause
  exit /b 1
)
exit /b 0
