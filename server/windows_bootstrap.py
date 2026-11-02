"""Safe Windows launcher for Nightwell Chat without Docker.

Preserves .env/data/, repairs only the dedicated .venv, prints every error,
and duplicates installation/server output to logs/startup.log.
"""
from __future__ import annotations

import hashlib
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVER = ROOT / "server"
REQUIREMENTS = SERVER / "requirements.txt"
VENV = ROOT / ".venv"
LOG = ROOT / "logs" / "startup.log"
IS_WIN = os.name == "nt"


def output(message: str) -> None:
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {message}"
    print(line, flush=True)
    with LOG.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def stream(cmd: list[str], label: str) -> int:
    output(label)
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8:replace"
    env["PYTHONUNBUFFERED"] = "1"
    try:
        with subprocess.Popen(
            cmd, cwd=ROOT, env=env, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, encoding="utf-8",
            errors="replace", bufsize=1,
        ) as process:
            try:
                assert process.stdout is not None
                for line in process.stdout:
                    print(line, end="", flush=True)
                    with LOG.open("a", encoding="utf-8") as f:
                        f.write(line)
                return process.wait()
            except KeyboardInterrupt:
                output("Stopping child process (Ctrl+C).")
                process.terminate()
                try:
                    process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                return 0
    except OSError as exc:
        output(f"Cannot execute: {cmd[0]}: {exc}")
        return 1


def env_python() -> Path:
    return VENV / ("Scripts/python.exe" if IS_WIN else "bin/python")


def version_ok(executable: str) -> bool:
    try:
        result = subprocess.run(
            [executable, "-c", "import sys; raise SystemExit(0 if sys.version_info.major == 3 and 10 <= sys.version_info.minor <= 13 else 1)"],
            cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=20, check=False,
        )
        return result.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def port_status() -> str:
    try:
        with socket.create_connection(("127.0.0.1", 8009), timeout=0.6):
            pass
    except OSError:
        return "free"
    try:
        with urllib.request.urlopen("http://127.0.0.1:8009/health", timeout=3) as reply:
            if b'"service":"nightwell-chat"' in reply.read().replace(b" ", b""):
                return "nightwell"
    except (OSError, urllib.error.URLError):
        pass
    return "occupied"


def ensure_virtualenv() -> Path:
    python = env_python()
    if python.is_file() and version_ok(str(python)):
        output("Existing virtual environment is usable.")
        return python
    if VENV.exists():
        backup = ROOT / (".venv.broken-" + time.strftime("%Y%m%d-%H%M%S"))
        output(f"Old Python environment is invalid, moving it to {backup.name}.")
        try:
            VENV.rename(backup)
        except OSError as exc:
            raise RuntimeError(f"Cannot repair .venv: {exc}. Close the old server and try again.") from exc
    result = stream([sys.executable, "-m", "venv", str(VENV)], "Creating isolated Python environment...")
    if result:
        raise RuntimeError(f"venv creation failed ({result}). Python must include venv and pip.")
    if not python.is_file():
        raise RuntimeError(f"Virtual Python executable not found: {python}")
    return python


def install_dependencies(python: Path) -> None:
    signature = hashlib.sha256(REQUIREMENTS.read_bytes()).hexdigest()
    marker = VENV / ".nightwell-dependencies"
    probe = subprocess.run(
        [str(python), "-c", "import fastapi, uvicorn, jwt, PIL, multipart, websockets, firebase_admin, pywebpush"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False, timeout=20,
    )
    if marker.is_file() and marker.read_text(encoding="ascii").strip() == signature and probe.returncode == 0:
        output("Dependencies are installed; skipping pip download.")
        return
    if stream([str(python), "-m", "pip", "--version"], "Checking pip..."):
        if stream([str(python), "-m", "ensurepip", "--upgrade"], "Restoring pip..."):
            raise RuntimeError("pip is unavailable. Install a complete Python 3.12 distribution.")
    result = stream(
        [str(python), "-m", "pip", "install", "--disable-pip-version-check", "-r", str(REQUIREMENTS)],
        "Installing required libraries (internet is required only for first installation)...",
    )
    if result:
        raise RuntimeError(f"pip install failed ({result}). Check network, proxy/VPN and errors above.")
    marker.write_text(signature, encoding="ascii")
    output("Dependencies installed successfully.")


def main() -> int:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    output("=== Nightwell Chat Windows launcher ===")
    output(f"Server folder: {ROOT}")
    output(f"Python: {sys.executable} ({sys.version.split()[0]})")
    if not version_ok(sys.executable):
        output("ERROR: use Python 3.10 - 3.13, preferably 3.12.")
        return 3
    for file in (SERVER / "app.py", SERVER / "local_server.py", REQUIREMENTS):
        if not file.is_file():
            output(f"ERROR: missing {file}. Extract the complete server archive.")
            return 2
    if not (ROOT / ".env").is_file():
        output("No .env found: a NEW secret will be created on first start.")
        output("If you are UPDATING an existing server, copy its old .env and data/ here before starting.")
    port = port_status()
    if port == "nightwell":
        output("Nightwell Chat is already listening on localhost:8009. No duplicate started.")
        return 0
    if port == "occupied":
        output("ERROR: port 8009 is already used by another application.")
        output("On Windows run: netstat -ano | findstr :8009")
        return 5
    try:
        python = ensure_virtualenv()
        install_dependencies(python)
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
        output(f"ERROR: {exc}")
        return 1
    output("Starting server on http://127.0.0.1:8009/health")
    result = stream([str(python), "-u", str(SERVER / "local_server.py")], "Launching Nightwell Chat API...")
    if result:
        output(f"ERROR: server exited with code {result}. Inspect the traceback above.")
        return result
    output("Server stopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
