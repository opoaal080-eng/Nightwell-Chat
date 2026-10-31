@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"

set "PY=py -3.12"
%PY% --version >nul 2>nul
if errorlevel 1 set "PY=python"
%PY% -c "import sys; sys.exit(0 if (3,10) <= sys.version_info[:2] <= (3,13) else 1)" >nul 2>nul
if errorlevel 1 goto :python_error

if not exist ".venv\Scripts\python.exe" (
    %PY% -m venv ".venv"
    if errorlevel 1 goto :error
)
if not exist ".env" (
    ".venv\Scripts\python.exe" -c "import pathlib,secrets; pathlib.Path('.env').write_text('NIGHTWELL_MONITOR_TOKEN='+secrets.token_urlsafe(42)+'\nNIGHTWELL_MONITOR_PORT=8091\n',encoding='utf-8')"
    if errorlevel 1 goto :error
    echo [Nightwell Monitor] Created a private key in admin-monitor\.env
    echo Copy NIGHTWELL_MONITOR_TOKEN into the iPhone Admin settings.
)
".venv\Scripts\python.exe" -c "import psutil" >nul 2>nul
if errorlevel 1 (
    ".venv\Scripts\python.exe" -m pip install --disable-pip-version-check -r "requirements.txt"
    if errorlevel 1 goto :error
)
echo [Nightwell Monitor] Starting...
".venv\Scripts\python.exe" monitor.py
if errorlevel 1 goto :error
exit /b 0

:python_error
echo [Nightwell Monitor] Install Python 3.12 and try again.
pause
exit /b 1

:error
echo [Nightwell Monitor] Failed. See the error above.
pause
exit /b 1
