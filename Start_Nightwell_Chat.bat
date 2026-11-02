@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Nightwell Chat - Server
chcp 65001 >nul
pushd "%~dp0" 2>nul
if errorlevel 1 goto bad_path

if not exist "server\windows_bootstrap.py" goto missing_files
if not exist "server\app.py" goto missing_files

set "NW_PYTHON="
where py >nul 2>nul
if not errorlevel 1 (
    for %%V in (3.12 3.13 3.11 3.10) do (
        if not defined NW_PYTHON (
            py -%%V -c "import sys; print('NIGHTWELL_PY_OK' if (3,10) <= sys.version_info[:2] <= (3,13) else 'BAD_VERSION')" 2>nul | findstr /X /C:"NIGHTWELL_PY_OK" >nul
            if not errorlevel 1 set "NW_PYTHON=py -%%V"
        )
    )
)
if not defined NW_PYTHON (
    where python >nul 2>nul
    if not errorlevel 1 (
        python -c "import sys; print('NIGHTWELL_PY_OK' if (3,10) <= sys.version_info[:2] <= (3,13) else 'BAD_VERSION')" 2>nul | findstr /X /C:"NIGHTWELL_PY_OK" >nul
        if not errorlevel 1 set "NW_PYTHON=python"
    )
)
if not defined NW_PYTHON goto missing_python

echo.
echo ================================================
echo           NIGHTWELL CHAT SERVER
echo ================================================
echo Running from: %CD%
echo Using Python: %NW_PYTHON%
echo.
%NW_PYTHON% -u "server\windows_bootstrap.py"
set "NW_EXIT=%ERRORLEVEL%"
echo.
if "%NW_EXIT%"=="0" (
    echo [Nightwell] Server has stopped normally.
) else (
    echo [Nightwell] Startup failed. Error code: %NW_EXIT%
)
echo [Nightwell] Log: "%CD%\logs\startup.log"
echo Do not delete .env or the data folder when updating.
echo.
pause
popd
exit /b %NW_EXIT%

:missing_files
echo.
echo [ERROR] Server files not found next to this BAT.
echo Extract the ENTIRE ZIP archive before running the BAT.
echo Required: server\app.py and server\windows_bootstrap.py
echo Working directory: %CD%
echo.
pause
popd
exit /b 2

:missing_python
echo.
echo [ERROR] Compatible Python was not found.
echo Install Python 3.12 and restart this BAT.
echo PowerShell: winget install -e --id Python.Python.3.12
echo Then close and reopen the launcher.
echo.
pause
popd
exit /b 3

:bad_path
echo [ERROR] Cannot access the server folder.
pause
exit /b 4
