@echo off
REM ============================================================================
REM Cloak for Windows — WSL Bridge
REM Launches Cloak inside Windows Subsystem for Linux
REM ============================================================================

title Cloak - Vany Offline Suite

REM Check if WSL is available
wsl --status >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo.
    echo   Cloak requires Windows Subsystem for Linux ^(WSL^).
    echo.
    echo   Install WSL:
    echo     wsl --install
    echo.
    echo   Then restart your computer and run this again.
    echo.
    pause
    exit /b 1
)

REM Get the directory of this batch file
set "CLOAK_WIN_DIR=%~dp0"

REM Convert Windows path to WSL path
for /f "tokens=*" %%i in ('wsl wslpath -u "%CLOAK_WIN_DIR%"') do set "CLOAK_WSL_DIR=%%i"

REM Launch cloak inside WSL
wsl bash "%CLOAK_WSL_DIR%cloak-wsl.sh" %*
