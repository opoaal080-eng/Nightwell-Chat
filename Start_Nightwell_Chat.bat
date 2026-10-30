@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

rem Use a Python release with prebuilt packages. Python 3.15 was selected
rem previously by "py -3", causing PyYAML/C++ wheel installation failures.
set "PY="
where py >nul 2>nul
if not errorlevel 1 (
    for %%V in (3.12 3.13 3.11 3.10) do (
        if not defined PY (
            py -%%V -c "import sys; sys.exit(0 if (3, 10) <= sys.version_info[:2] <= (3, 13) else 1)" >nul 2>nul
            if not errorlevel 1 set "PY=py -%%V"
        )
    )
)
if not defined PY (
    where python >nul 2>nul
    if not errorlevel 1 (
        python -c "import sys; sys.exit(0 if (3, 10) <= sys.version_info[:2] <= (3, 13) else 1)" >nul 2>nul
        if not errorlevel 1 set "PY=python"
    )
)
if not defined PY goto :missing_python

echo [Nightwell Chat] Using:
%PY% --version

rem Repair an existing .venv made with Python 3.14/3.15 (or broken Python).
rem Never touch .env, data, or the SQLite database.
if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" -c "import sys; sys.exit(0 if (3, 10) <= sys.version_info[:2] <= (3, 13) else 1)" >nul 2>nul
    if errorlevel 1 (
        echo [Nightwell Chat] Recreating incompatible .venv. Your data will be kept.
        rmdir /s /q ".venv"
        if exist ".venv\Scripts\python.exe" goto :error
    )
)
if not exist ".venv\Scripts\python.exe" (
    echo [Nightwell Chat] Creating a local Python environment...
    %PY% -m venv ".venv"
    if errorlevel 1 goto :error
)
echo [Nightwell Chat] Checking Python dependencies...
".venv\Scripts\python.exe" -m pip install --disable-pip-version-check -r "server\requirements.txt"
if errorlevel 1 goto :error

echo [Nightwell Chat] Starting on localhost:8009...
".venv\Scripts\python.exe" "server\local_server.py"
if errorlevel 1 goto :error
exit /b 0

:missing_python
echo.
echo [Nightwell Chat] Python 3.10 - 3.13 is required. Python 3.15 is not supported by this launcher.
echo [Nightwell Chat] Recommended: install Python 3.12 from https://www.python.org/downloads/
echo [Nightwell Chat] You can also run: winget install -e --id Python.Python.3.12
echo [Nightwell Chat] Restart this launcher after installation. Keep .env and data.
pause
exit /b 1

:error
echo [Nightwell Chat] Failed to start. Read the error above.
pause
exit /b 1
