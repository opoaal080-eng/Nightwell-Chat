"""Run Nightwell Chat on Windows or Linux without Docker (single worker)."""
from __future__ import annotations

import os
import secrets
import signal
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = ROOT / ".env"
DATA_DIR = ROOT / "data"
PID_FILE = DATA_DIR / "nightwell_chat.pid"


def load_environment() -> None:
    """Generate a secret once, load .env, and select a local SQLite database."""
    if not ENV_FILE.exists():
        try:
            with ENV_FILE.open("x", encoding="utf-8") as env:
                env.write("SECRET_KEY=" + secrets.token_hex(48) + "\n")
        except FileExistsError:
            pass
        print("[Nightwell Chat] Created .env with a random secret.", flush=True)

    for line in ENV_FILE.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value

    secret = os.environ.get("SECRET_KEY", "")
    if len(secret) < 32 or secret.startswith("REPLACE_WITH_"):
        raise ValueError("Invalid SECRET_KEY in .env. Set a random key (32+ chars).")

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("DB_PATH", str(DATA_DIR / "nightwell_chat.db"))


def stop_server() -> int:
    if not PID_FILE.exists():
        print("[Nightwell Chat] Server PID file not found. Is it running?")
        return 1

    try:
        pid = int(PID_FILE.read_text(encoding="ascii").strip())
        if pid <= 1:
            raise ValueError("bad PID")
    except ValueError:
        print("[Nightwell Chat] Invalid PID file. No process was stopped.")
        return 1

    if os.name == "nt":
        # Check the command line so a reused PID cannot kill another program.
        ps = (
            f'$p = Get-CimInstance Win32_Process -Filter "ProcessId = {pid}"; '
            'if ($null -eq $p) { exit 3 }; '
            "if ($p.CommandLine -notmatch 'local_server\\.py') { exit 4 }; "
            'exit 0'
        )
        checked = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps],
            capture_output=True, text=True, check=False,
        )
        if checked.returncode != 0:
            if checked.returncode == 3:
                PID_FILE.unlink(missing_ok=True)
                print("[Nightwell Chat] Already stopped; stale PID file removed.")
            else:
                print("[Nightwell Chat] Cannot verify server process; nothing stopped.")
            return 1
        result = subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], check=False)
        if result.returncode != 0:
            return 1
    else:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            print("[Nightwell Chat] Already stopped.")
        except PermissionError:
            print("[Nightwell Chat] Access denied; no process stopped.")
            return 1

    PID_FILE.unlink(missing_ok=True)
    print("[Nightwell Chat] Stop command sent.")
    return 0


def run_server() -> int:
    try:
        load_environment()
    except (OSError, ValueError) as exc:
        print(f"[Nightwell Chat] Startup error: {exc}", file=sys.stderr)
        return 1

    import uvicorn

    os.chdir(ROOT / "server")
    PID_FILE.write_text(str(os.getpid()), encoding="ascii")
    print("[Nightwell Chat] Health: http://127.0.0.1:8009/health", flush=True)
    print("[Nightwell Chat] Public access: HTTPS via Caddy -> 127.0.0.1:8009", flush=True)
    try:
        uvicorn.run("app:app", host="127.0.0.1", port=8009,
                    workers=1, access_log=False)
    finally:
        try:
            if PID_FILE.read_text(encoding="ascii") == str(os.getpid()):
                PID_FILE.unlink(missing_ok=True)
        except FileNotFoundError:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(stop_server() if sys.argv[1:] == ["stop"] else run_server())
