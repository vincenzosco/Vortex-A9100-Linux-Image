@echo off
REM ===========================================================
REM build.bat - Vortex86 A9100 Image Builder for Windows
REM
REM This script builds a complete bootable Linux image for
REM the DM&P Vortex86 A9100 (i486-compatible) SoC on Windows
REM using WSL2 (Windows Subsystem for Linux).
REM
REM Requirements:
REM   - Windows 10 version 2004+ or Windows 11
REM   - WSL2 with Ubuntu (or any Debian-based distro)
REM   - ~5GB free disk space
REM   - Internet connection for Buildroot downloads
REM
REM Usage:
REM   build.bat              # Full build inside WSL2
REM   build.bat clean        # Clean build artifacts
REM   build.bat distclean    # Remove everything
REM   build.bat help         # Show this help
REM
REM First time setup:
REM   1. Install WSL2: https://aka.ms/wsl2-kernel
REM   2. Install Ubuntu: wsl --install -d Ubuntu
REM   3. Install build dependencies inside WSL:
REM      sudo apt-get update && sudo apt-get install -y build-essential ^
REM        bison flex bc wget tar gzip bzip2 xz-utils patch sed gawk ^
REM        findutils file cpio unzip rsync python3 uuid-dev libblkid-dev
REM ===========================================================
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM --- Colors (via ANSI escape codes, works in Windows Terminal) ---
set "RED=[31m"
set "GREEN=[32m"
set "YELLOW=[33m"
set "BLUE=[34m"
set "NC=[0m"

REM --- Helper functions via findstr abuse ---
goto :main

:info
    echo [%GREEN%[INFO][%NC%  %*
    exit /b 0

:warn
    echo [%YELLOW%[WARN][%NC%  %*
    exit /b 0

:error
    echo [%RED%[ERROR][%NC% %*
    exit /b 0

:step
    echo [%BLUE%[STEP][%NC%  %*
    exit /b 0

:show_help
    echo.
    echo Vortex86 A9100 Linux Image Builder for Windows
    echo.
    echo Builds a complete Linux image for the DM&P Vortex86 A9100
    echo using WSL2 (Windows Subsystem for Linux).
    echo.
    echo Usage: build.bat [command]
    echo.
    echo Commands:
    echo   (none)       Full build (download, configure, compile, package)
    echo   clean        Remove all build artifacts
    echo   distclean    Remove everything including downloaded sources
    echo   help         Show this help
    echo.
    echo First-time WSL2 setup:
    echo   1. Install WSL2: https://aka.ms/wsl2-kernel
    echo   2. wsl --install -d Ubuntu
    echo   3. Inside WSL, install dependencies:
    echo      sudo apt-get update ^&^& sudo apt-get install -y ^
    echo        build-essential bison flex bc wget tar gzip bzip2 ^
    echo        xz-utils patch sed gawk findutils file cpio unzip ^
    echo        rsync python3 uuid-dev libblkid-dev
    echo.
    echo Output:
    echo   buildroot/output/images/vortex86_a9100.img  - Bootable image
    echo.
    exit /b 0

:check_wsl
    where wsl >nul 2>nul
    if %ERRORLEVEL% neq 0 (
        call :error "WSL is not installed!"
        echo   Install WSL2 first: https://aka.ms/wsl2-kernel
        echo   Or run: wsl --install
        exit /b 1
    )
    exit /b 0

:check_wsl_distro
    wsl -l -v 2>nul | findstr /i "Ubuntu" >nul
    if %ERRORLEVEL% neq 0 (
        call :warn "No Ubuntu WSL distro found. Install one with:"
        echo   wsl --install -d Ubuntu
        echo   Then re-run this script.
        exit /b 1
    )
    exit /b 0

REM ===========================================================
REM Main
REM ===========================================================
:main
    set "CMD=%1"

    if /i "%CMD%"=="help" (
        call :show_help
        exit /b 0
    )
    if /i "%CMD%"=="/?" (
        call :show_help
        exit /b 0
    )
    if /i "%CMD%"=="-h" (
        call :show_help
        exit /b 0
    )
    if /i "%CMD%"=="--help" (
        call :show_help
        exit /b 0
    )

    call :step "Checking WSL2 environment..."

    call :check_wsl
    if %ERRORLEVEL% neq 0 exit /b 1

    call :check_wsl_distro
    if %ERRORLEVEL% neq 0 exit /b 1

    REM Verify that build.sh exists (it should, since we're in the repo dir)
    if not exist "%SCRIPT_DIR%\build.sh" (
        call :error "build.sh not found!"
        echo   Make sure you're in the Vortex-A9100-Linux-Image directory.
        exit /b 1
    )

    REM Ensure build.sh is executable inside WSL
    wsl --cd "%SCRIPT_DIR%" -e bash -lc "chmod +x '%SCRIPT_DIR%/build.sh' 2>/dev/null"

    REM Check for build dependencies inside WSL
    call :step "Checking WSL build dependencies..."
    wsl --cd "%SCRIPT_DIR%" -e bash -lc "
        MISSING=\"\"
        for cmd in gcc g++ make bison flex bc wget tar gzip bzip2 xz patch sed gawk find file cpio unzip rsync python3; do
            which \$cmd >/dev/null 2>&1 || MISSING=\"\$MISSING \$cmd\"
        done
        if [ -n \"\$MISSING\" ]; then
            echo \"Missing dependencies:\$MISSING\"
            echo \"Install them with:\"
            echo \"  sudo apt-get update && sudo apt-get install -y build-essential bison flex bc wget tar gzip bzip2 xz-utils patch sed gawk findutils file cpio unzip rsync python3 uuid-dev libblkid-dev\"
            exit 1
        fi
        echo \"All dependencies satisfied!\"
    "

    if %ERRORLEVEL% neq 0 exit /b 1

    REM Run the build
    call :step "Starting Buildroot build inside WSL2..."
    echo.
    echo   Note: This runs entirely inside WSL2. The buildroot/
    echo   directory is shared between Windows and WSL via /mnt/...
    echo.

    wsl --cd "%SCRIPT_DIR%" -e bash -lc "cd '%SCRIPT_DIR%' && ./build.sh %*"

    set "BUILD_EXIT=%ERRORLEVEL%"

    echo.
    if !BUILD_EXIT! equ 0 (
        call :info "Build completed successfully!"
        call :info "Output image: %SCRIPT_DIR%\buildroot\output\images\vortex86_a9100.img"
        echo.
        echo   To write to a USB/CF drive:
        echo     Option 1 (Windows): Run install.ps1 in PowerShell as Admin
        echo     Option 2 (WSL):      sudo dd if=buildroot/output/images/vortex86_a9100.img of=/dev/sdX bs=4M status=progress
    ) else (
        call :error "Build failed! Check buildroot/output/build.log for details."
    )

    exit /b !BUILD_EXIT!
