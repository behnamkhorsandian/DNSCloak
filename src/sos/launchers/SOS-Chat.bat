@echo off
REM SOS Emergency Chat - Windows Launcher
REM Double-click this file to start SOS

cd /d "%~dp0"

if exist "sos-windows-amd64.exe" (
    sos-windows-amd64.exe
) else (
    echo Error: SOS binary not found!
    echo Make sure sos-windows-amd64.exe is in the same folder.
    pause
    exit /b 1
)

if errorlevel 1 (
    echo.
    pause
)
