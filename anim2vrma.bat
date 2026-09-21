@echo off
setlocal

:: ==============================================================================
:: VRM Animation (.vrma) Drag-and-Drop Converter
:: ==============================================================================

if "%~1"=="" (
    echo [ERROR] No input file provided.
    echo Usage: Drag and drop a Unity .anim or .unitypackage file onto this batch script.
    pause
    exit /b
)

set INPUT_FILE="%~1"
set PS_SCRIPT="%~dp0Convert-AnimToVrma.ps1"

echo --------------------------------------------------
echo VRMA Headless Conversion Pipeline
echo --------------------------------------------------

powershell.exe -ExecutionPolicy Bypass -File %PS_SCRIPT% -InputPath %INPUT_FILE%

echo.
pause
