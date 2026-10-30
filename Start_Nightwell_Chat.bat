@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

rem Only accept a Python interpreter that actually ran code and printed
rem a known marker. Some Python Install Manager versions return success even
rem when a requested runtime does not exist.
set "PY="
where py >nul 2>nul
if not errorlevel 1 (
    for %%V in (3.12 3.13 3.11 3.10) do (
        if not defined PY (
            py -%%V -c "import sys; print('NIGHTWELL_PY_READY' if (3,10) <= sys.version_info[:2] <= (3,13) else 'UNSUPPORTED')" 2>nul | findstr /X /C:"NIGHTWELL_PY_READY" >nul
            if not errorlevel 1 set "PY=py -%%V"
        )
    )
)
if not defined PY (
    where python >nul 2>nul
    if not errorlevel 1 (
        python -c "import sys; print('NIGHTWELL_PY_READY' if (3,10) <= sys.version_info[:2] <= (3,13) else 'UNSUPPORTED')" 2>nul | findstr /X /C:"NIGHTWELL_PY_READY" >nul
        if not errorlevel 1 set "PY=python"
    )
)
if not defined PY goto :missing_python

echo [Nightwell Chat] Python runtime found:
%PY% --version

rem Recreate only the local virtual environment if it uses an unsuitable
rem Python version or its original Python installation is now missing.
rem Keep .env, data, and database files untouched.
if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" -c "import sys; print('NIGHTWELL_PY_READY' if (3,10) <= sys.version_info[:2] <= (3,13) else 'UNSUPPORTED')" 2>nul | findstr /X /C:"NIGHTWELL_PY_READY" >nul
    if errorlevel 1 (
        echo [Nightwell Chat] Repairing old .venv (chat data stays intact)...
        rmdir /s /q ".venv"
    )
)
if not exist ".venv\Scripts\python.exe" (
    echo [Nightwell Chat] Creating a local Python environment...
    %PY% -m venv ".venv"
    if errorlevel 1 goto :error
)
if not exist ".venv\Scripts\python.exe" goto :error

".venv\Scripts\python.exe" -c "import sys; print('NIGHTWELL_PY_READY' if (3,10) <= sys.version_info[:2] <= (3,13) else 'UNSUPPORTED')" 2>nul | findstr /X /C:"NIGHTWELL_PY_READY" >nul
if errorlevel 1 goto :error

echo [Nightwell Chat] Installing dependencies...
".venv\Scripts\python.exe" -m pip install --disable-pip-version-check -r "server\requirements.txt"
if errorlevel 1 goto :error

echo [Nightwell Chat] Starting on localhost:8009...
".venv\Scripts\python.exe" "server\local_server.py"
if errorlevel 1 goto :error
exit /b 0

:missing_python
echo.
echo [Nightwell Chat] Python 3.10 - 3.13 was not found.
echo [Nightwell Chat] Python 3.15 cannot be used with this server setup.
echo [Nightwell Chat] To install Python 3.12, open PowerShell and run:
echo     py install 3.12
echo [Nightwell Chat] If that is unavailable, run:
echo     winget install -e --id Python.Python.3.12
echo [Nightwell Chat] Then restart this BAT file. Existing chat data is safe.
pause
exit /b 1

:error
echo [Nightwell Chat] Failed to start. Read the error above.
pause
exit /b 1
