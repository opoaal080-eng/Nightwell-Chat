@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

where py >nul 2>nul
if not errorlevel 1 (
    set "PY=py -3"
) else (
    where python >nul 2>nul
    if errorlevel 1 (
        echo [Nightwell Chat] Install Python 3.10+ first, including pip.
        pause
        exit /b 1
    )
    set "PY=python"
)

if not exist ".venv\Scripts\python.exe" (
    echo [Nightwell Chat] Creating a local Python environment...
    %PY% -m venv ".venv"
    if errorlevel 1 goto :error
)

echo [Nightwell Chat] Checking Python dependencies...
".venv\Scripts\python.exe" -m pip install --disable-pip-version-check -q -r "server\requirements.txt"
if errorlevel 1 goto :error

echo [Nightwell Chat] Starting on localhost:8009...
".venv\Scripts\python.exe" "server\local_server.py"
if errorlevel 1 goto :error
exit /b 0

:error
echo [Nightwell Chat] Failed to start. Read the error above.
pause
exit /b 1
