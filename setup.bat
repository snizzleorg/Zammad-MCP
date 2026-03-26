@echo off
setlocal ENABLEEXTENSIONS

echo === Zammad-MCP setup ===
echo.

REM --- Check winget ---
where winget >nul 2>nul
if errorlevel 1 (
    echo ERROR: winget was not found.
    echo Please install App Installer / Windows Package Manager first.
    pause
    exit /b 1
)

REM --- Install Git if missing ---
where git >nul 2>nul
if errorlevel 1 (
    echo Git not found. Installing Git...
    winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements
    if errorlevel 1 (
        echo ERROR: Failed to install Git.
        pause
        exit /b 1
    )
) else (
    echo Git is already installed.
)

REM --- Install uv if missing ---
where uv >nul 2>nul
if errorlevel 1 (
    echo uv not found. Installing uv...
    winget install -e --id astral-sh.uv --accept-package-agreements --accept-source-agreements
    if errorlevel 1 (
        echo ERROR: Failed to install uv.
        pause
        exit /b 1
    )
) else (
    echo uv is already installed.
)

REM --- Add common install paths for this session ---
set "PATH=C:\Program Files\Git\cmd;%USERPROFILE%\.local\bin;%PATH%"

REM --- Re-check tools ---
where git >nul 2>nul
if errorlevel 1 (
    echo ERROR: Git still not found after installation.
    echo Please close this window, open a new terminal, and run the script again.
    pause
    exit /b 1
)

where uv >nul 2>nul
if errorlevel 1 (
    echo ERROR: uv still not found after installation.
    echo Please close this window, open a new terminal, and run the script again.
    pause
    exit /b 1
)

REM --- Clone repo if not present ---
if exist "Zammad-MCP\.git" (
    echo Repository already exists: Zammad-MCP
) else (
    echo Cloning Zammad-MCP...
    git clone https://github.com/snizzleorg/Zammad-MCP.git
    if errorlevel 1 (
        echo ERROR: Failed to clone Zammad-MCP.
        pause
        exit /b 1
    )
)

REM --- Enter repo ---
cd /d Zammad-MCP
if errorlevel 1 (
    echo ERROR: Could not enter Zammad-MCP directory.
    pause
    exit /b 1
)

REM --- Sync dependencies with temporary SSL bypass ---
echo.
echo Running uv sync --extra pii ...
set GIT_SSL_NO_VERIFY=true
uv sync --extra pii
if errorlevel 1 (
    echo.
    echo ERROR: uv sync failed.
    pause
    exit /b 1
)

echo.
echo Setup completed successfully.
pause
endlocal