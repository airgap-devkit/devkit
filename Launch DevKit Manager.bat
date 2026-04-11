@echo off
title DevKit Manager — airgap-cpp-devkit
cd /d "%~dp0"

where bash >nul 2>nul
if %errorlevel% neq 0 (
    echo.
    echo  ERROR: 'bash' not found on PATH.
    echo.
    echo  To fix this, install Git for Windows:
    echo    https://git-scm.com/downloads
    echo  During install, choose "Git from the command line and also from 3rd-party software"
    echo  so that bash.exe is added to your PATH.
    echo.
    pause
    exit /b 1
)

echo.
echo  Starting DevKit Manager...
echo  Your browser will open at http://127.0.0.1:8080
echo  Press Ctrl+C in this window to stop the server.
echo.

bash launch.sh
