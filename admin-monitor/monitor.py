"""Local-only hardware monitor for Nightwell Admin (Windows/Linux)."""
from __future__ import annotations

import hmac
import json
import os
import platform
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

import psutil

ROOT = Path(__file__).resolve().parent
LOCK = threading.RLock()
CACHE: dict = {}
STATS: dict = {}
TEMPERATURES: dict = {"checked": 0.0, "items": []}


def _setting(key: str, default: str = "") -> str:
    value = os.environ.get(key, "").strip()
    if value:
        return value
    config = ROOT / ".env"
    if config.is_file():
        for line in config.read_text(encoding="utf-8-sig").splitlines():
            name, sep, content = line.partition("=")
            if sep and name.strip() == key:
                return content.strip().strip('"').strip("'")
    return default


def rate(current: int, previous: int | None, seconds: float) -> float | None:
    if previous is None or seconds <= 0:
        return None
    return round(max(0, current - previous) / seconds, 1)


def cpu_name() -> str:
    if sys.platform == "win32":
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                                r"HARDWARE\DESCRIPTION\System\CentralProcessor\0") as key:
                return str(winreg.QueryValueEx(key, "ProcessorNameString")[0]).strip()
        except (OSError, ValueError):
            pass
    return platform.processor() or "CPU"


def _gpu() -> list[dict]:
    # NVIDIA provides optional GPU readings without an additional Python package.
    try:
        smi = shutil.which("nvidia-smi")
        if not smi and os.name == "nt":
            for base in (os.environ.get("ProgramFiles"), os.environ.get("ProgramW6432")):
                if base:
                    candidate = Path(base) / "NVIDIA Corporation" / "NVSMI" / "nvidia-smi.exe"
                    if candidate.is_file():
                        smi = str(candidate)
                        break
        command = [
            smi or "nvidia-smi",
            "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu",
            "--format=csv,noheader,nounits",
        ]
        result = subprocess.run(command, capture_output=True, text=True, timeout=1.8,
                                check=False, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        if result.returncode:
            return []
        def number(raw: str) -> float | None:
            raw = raw.strip()
            return float(raw) if re.fullmatch(r"-?\d+(?:\.\d+)?", raw) else None
        output = []
        for line in result.stdout.splitlines()[:8]:
            values = [item.strip() for item in line.split(",")]
            if len(values) != 5:
                continue
            name, usage, mem_used, mem_total, temperature = values
            output.append({
                "name": name[:100],
                "usage_percent": number(usage),
                "memory_used_bytes": (int(float(mem_used) * 1048576) if number(mem_used) is not None else None),
                "memory_total_bytes": (int(float(mem_total) * 1048576) if number(mem_total) is not None else None),
                "temperature_c": number(temperature),
            })
        return output
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return []


def _temperature_items() -> list[dict]:
    readings = []
    try:
        for sensor_group, entries in psutil.sensors_temperatures().items():
            for entry in entries:
                value = getattr(entry, "current", None)
                if value is not None and -15 < float(value) < 130:
                    readings.append({
                        "name": (entry.label or sensor_group)[:90],
                        "temperature_c": round(float(value), 1),
                    })
    except (AttributeError, OSError, NotImplementedError):
        pass
    if sys.platform == "win32":
        # Optional LibreHardwareMonitor/OpenHardwareMonitor WMI integration.
        # If neither application exports its sensors, leave them unavailable.
        for namespace in (r"root\LibreHardwareMonitor", r"root\OpenHardwareMonitor"):
            command = (
                "Get-CimInstance -Namespace '" + namespace +
                "' -ClassName Sensor -ErrorAction Stop | "
                "Where-Object { $_.SensorType -eq 'Temperature' } | "
                "Select-Object Name,Value | ConvertTo-Json -Compress"
            )
            try:
                result = subprocess.run(
                    ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", command],
                    capture_output=True, text=True, timeout=2.5,
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                )
                if result.returncode or not result.stdout.strip():
                    continue
                values = json.loads(result.stdout)
                for entry in (values if isinstance(values, list) else [values]):
                    temperature = float(entry["Value"])
                    if -15 < temperature < 130:
                        readings.append({
                            "name": str(entry.get("Name", "Датчик"))[:90],
                            "temperature_c": round(temperature, 1),
                        })
                if values:
                    break
            except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, TypeError):
                continue
    unique = []
    seen = set()
    for item in readings:
        label = item["name"]
        if label not in seen:
            seen.add(label)
            unique.append(item)
    return unique[:24]


def _temperatures(now: float) -> list[dict]:
    if now - TEMPERATURES["checked"] >= 20:
        TEMPERATURES["items"] = _temperature_items()
        TEMPERATURES["checked"] = now
    return TEMPERATURES["items"]


def _is_listening(port: int) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.15):
            return True
    except OSError:
        return False


def collect() -> dict:
    with LOCK:
        now = time.monotonic()
        if CACHE and now - STATS.get("checked", 0) < 1.5:
            return CACHE.copy()

        memory = psutil.virtual_memory()
        volumes = []
        for disk in psutil.disk_partitions(all=False):
            try:
                usage = psutil.disk_usage(disk.mountpoint)
            except (OSError, PermissionError):
                continue
            if usage.total:
                volumes.append({
                    "name": disk.device or disk.mountpoint,
                    "mount": disk.mountpoint,
                    "total_bytes": usage.total,
                    "used_bytes": usage.used,
                    "free_bytes": usage.free,
                    "percent": round(usage.percent, 1),
                })

        disk_io = psutil.disk_io_counters()
        net_io = psutil.net_io_counters()
        previous = STATS.get("io")
        elapsed = now - STATS.get("checked", now)
        disk_rates = None
        network = {
            "rx_bytes_per_sec": None,
            "tx_bytes_per_sec": None,
            "total_received_bytes": net_io.bytes_recv if net_io else 0,
            "total_sent_bytes": net_io.bytes_sent if net_io else 0,
        }
        if disk_io:
            disk_rates = {
                "read_bytes_per_sec": rate(disk_io.read_bytes, previous["disk_read"], elapsed) if previous else None,
                "write_bytes_per_sec": rate(disk_io.write_bytes, previous["disk_write"], elapsed) if previous else None,
            }
        if net_io and previous:
            network["rx_bytes_per_sec"] = rate(net_io.bytes_recv, previous["net_rx"], elapsed)
            network["tx_bytes_per_sec"] = rate(net_io.bytes_sent, previous["net_tx"], elapsed)

        STATS["io"] = {
            "disk_read": disk_io.read_bytes if disk_io else 0,
            "disk_write": disk_io.write_bytes if disk_io else 0,
            "net_rx": net_io.bytes_recv if net_io else 0,
            "net_tx": net_io.bytes_sent if net_io else 0,
        }
        STATS["checked"] = now

        result = {
            "timestamp": int(time.time()),
            "hostname": socket.gethostname()[:100],
            "os": platform.platform()[:140],
            "uptime_seconds": max(0, int(time.time() - psutil.boot_time())),
            "cpu": {
                "model": cpu_name(),
                "usage_percent": round(psutil.cpu_percent(interval=None), 1),
                "physical_cores": psutil.cpu_count(logical=False),
                "logical_cores": psutil.cpu_count(logical=True),
                "per_core_percent": [round(x, 1) for x in psutil.cpu_percent(interval=None, percpu=True)],
            },
            "memory": {
                "total_bytes": memory.total,
                "used_bytes": memory.used,
                "available_bytes": memory.available,
                "percent": round(memory.percent, 1),
            },
            "disks": volumes[:16],
            "disk_io": disk_rates,
            "network": network,
            "gpu": _gpu(),
            "temperatures": _temperatures(now),
            "services": {
                "music": _is_listening(8080),
                "chat": _is_listening(8009),
            },
        }
        CACHE.clear()
        CACHE.update(result)
        return result.copy()


class MonitorHandler(BaseHTTPRequestHandler):
    server_version = "NightwellMonitor"
    sys_version = ""

    def do_GET(self) -> None:
        path = urlsplit(self.path).path
        if path != "/v1/system/metrics":
            self._reply(404, {"error": "Not found"})
            return
        supplied = self.headers.get("Authorization", "")
        expected = "Bearer " + self.server.monitor_token
        if not hmac.compare_digest(supplied.encode("utf-8"), expected.encode("utf-8")):
            self._reply(401, {"error": "Unauthorized"})
            return
        try:
            self._reply(200, collect())
        except Exception:
            self._reply(503, {"error": "Metrics temporarily unavailable"})

    def _reply(self, code: int, obj: dict) -> None:
        data = json.dumps(obj, ensure_ascii=False, allow_nan=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args) -> None:
        # Never print admin endpoints, network clients or credentials into logs.
        pass


class MonitorHTTPServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, addr: tuple[str, int], token: str):
        super().__init__(addr, MonitorHandler)
        self.monitor_token = token


def main() -> None:
    token = _setting("NIGHTWELL_MONITOR_TOKEN")
    if len(token) < 32:
        raise SystemExit("NIGHTWELL_MONITOR_TOKEN missing or too short; see admin-monitor/.env")
    port = int(_setting("NIGHTWELL_MONITOR_PORT", "8091"))
    if not 1024 <= port <= 65535:
        raise SystemExit("Monitor port must be between 1024 and 65535")
    psutil.cpu_percent(interval=None)
    psutil.cpu_percent(interval=None, percpu=True)
    with MonitorHTTPServer(("127.0.0.1", port), token) as server:
        print(f"Nightwell Monitor is listening on localhost:{port}")
        print("Only /v1/system/metrics is available. HTTPS and auth are handled by Caddy + agent.")
        try:
            server.serve_forever(poll_interval=0.3)
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
