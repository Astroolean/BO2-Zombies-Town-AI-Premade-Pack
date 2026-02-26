@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title BO2 Custom Tracker Reset (Counter + Summary)

REM Prefer the fullscreen script if you dropped it in the same folder
set "PS1=%~dp0custom_reset_gui.ps1"
if exist "%~dp0custom_reset_gui_fullscreen_ascii.ps1" set "PS1=%~dp0custom_reset_gui_fullscreen_ascii.ps1"
if exist "%~dp0custom_reset_gui_fullscreen_utf8.ps1"  set "PS1=%~dp0custom_reset_gui_fullscreen_utf8.ps1"

REM Launch maximized and wait for it to finish
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "PS_ERR=%ERRORLEVEL%"
if not "%PS_ERR%"=="0" (
  echo.
  echo ========================================
  echo ERROR: Reset script failed (exit code %PS_ERR%).
  echo ========================================
)


echo.
echo ========================================
echo FINISHED
echo ========================================
echo Press any key to close...
pause >nul
endlocal
