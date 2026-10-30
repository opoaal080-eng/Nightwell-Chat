@echo off
chcp 65001 >nul
cd /d "%~dp0"
where docker >nul 2>nul
if errorlevel 1 (
  echo Docker Desktop not found. Install and start Docker Desktop.
  pause
  exit /b 1
)
if not exist .env (
  echo Configure .env first: copy .env.example to .env and replace SECRET_KEY.
  echo Example secret: python -c "import secrets; print(secrets.token_urlsafe(48))"
  pause
  exit /b 1
)
docker compose up -d --build
if errorlevel 1 (
  echo Server failed to start. Run docker compose logs --tail=100 chat
) else (
  echo Nightwell Chat server is running on http://127.0.0.1:8009
)
pause
