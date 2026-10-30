@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo [Nightwell Chat] No local Python environment was found.
    pause
    exit /b 1
)
".venv\Scripts\python.exe" "server\local_server.py" stop
if errorlevel 1 (
    pause
    exit /b 1
)
pause
