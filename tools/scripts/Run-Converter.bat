@echo off
:: Set working directory to the folder containing this batch file
cd /d "%~dp0"

echo ======================================================
echo Launching BeamNG JBeam Tire Converter...
echo ======================================================
echo.

:: Launch PowerShell, bypass the execution policy restriction, and run your script
powershell -NoProfile -ExecutionPolicy Bypass -File "Convert-Tires.ps1"

echo.
echo ======================================================
echo Process complete. Press any key to close this window.
echo ======================================================
pause >nul