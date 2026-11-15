#!/usr/bin/env python3
"""Aoi PC Companion bootstrap — standard-library-only installer and status service.

The default service binds ONLY to the computer's Tailscale IPv4 address. If Tailscale
is absent, it binds to loopback and is not remotely reachable. This avoids exposing an
unauthenticated shell or an HTTP bearer token to an ordinary Wi-Fi network.

Usage:
  python aoi_pc_bootstrap.py install
  python aoi_pc_bootstrap.py status
  python aoi_pc_bootstrap.py uninstall

This first bootstrap milestone provides authenticated health/status and startup
registration. It deliberately does not expose remote shell, filesystem writes or
Godot execution yet; those require the later approval-aware bridge integration.
"""
from __future__ import annotations

import argparse
import getpass
import hmac
import json
import os
import platform
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional

VERSION = "0.1.0"
HOSTNAME = socket.gethostname()


def companion_home() -> Path:
    override = os.environ.get("AOI_PC_HOME", "").strip()
    if override:
        return Path(override).expanduser().resolve()
    if os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
        return base / "AoiPC"
    if platform.system() == "Darwin":
        return Path.home() / "Library" / "Application Support" / "AoiPC"
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / "aoi-pc"


def config_path(home: Optional[Path] = None) -> Path:
    return (home or companion_home()) / "config.json"


def read_config(home: Optional[Path] = None) -> dict:
    path = config_path(home)
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def tailscale_ipv4() -> str:
    exe = shutil.which("tailscale")
    if not exe:
        return ""
    try:
        result = subprocess.run([exe, "ip", "-4"], capture_output=True, text=True, timeout=4, check=False)
        for line in result.stdout.splitlines():
            candidate = line.strip()
            try:
                import ipaddress
                address = ipaddress.ip_address(candidate)
                if address.version == 4 and not address.is_loopback:
                    return candidate
            except ValueError:
                continue
    except (OSError, subprocess.TimeoutExpired):
        pass
    return ""


def install_startup(home: Path) -> str:
    script = home / "aoi_pc_bootstrap.py"
    python = sys.executable
    system = platform.system()
    if system == "Windows":
        startup = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming")) / "Microsoft" / "Windows" / "Start Menu" / "Programs" / "Startup"
        startup.mkdir(parents=True, exist_ok=True)
        launcher = startup / "AoiPCCompanion.vbs"
        pyw = Path(python).with_name("pythonw.exe")
        runner = str(pyw if pyw.exists() else python).replace('"', '""')
        target = str(script).replace('"', '""')
        launcher.write_text(f'Set shell = CreateObject("WScript.Shell")\nshell.Run """{runner}"" """{target}"" serve", 0, False\n', encoding="utf-8")
        return str(launcher)
    if system == "Darwin":
        agents = Path.home() / "Library" / "LaunchAgents"
        agents.mkdir(parents=True, exist_ok=True)
        plist = agents / "com.aoi.pc-companion.plist"
        content = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.aoi.pc-companion</string>
<key>ProgramArguments</key><array><string>{python}</string><string>{script}</string><string>serve</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>StandardOutPath</key><string>{home / 'companion.log'}</string>
<key>StandardErrorPath</key><string>{home / 'companion.log'}</string>
</dict></plist>'''
        plist.write_text(content, encoding="utf-8")
        subprocess.run(["launchctl", "load", str(plist)], capture_output=True, timeout=5, check=False)
        return str(plist)
    units = Path.home() / ".config" / "systemd" / "user"
    units.mkdir(parents=True, exist_ok=True)
    unit = units / "aoi-pc-companion.service"
    unit.write_text(
        "[Unit]\nDescription=Aoi PC Companion\nAfter=network-online.target\nWants=network-online.target\n\n"
        "[Service]\nType=simple\nExecStart=%s %s serve\nRestart=always\nRestartSec=5\n\n"
        "[Install]\nWantedBy=default.target\n" % (python, script), encoding="utf-8"
    )
    systemctl = shutil.which("systemctl")
    if systemctl:
        subprocess.run([systemctl, "--user", "daemon-reload"], capture_output=True, timeout=5, check=False)
        subprocess.run([systemctl, "--user", "enable", "--now", "aoi-pc-companion.service"], capture_output=True, timeout=8, check=False)
    return str(unit)


def install(no_start: bool = False) -> dict:
    home = companion_home()
    home.mkdir(parents=True, exist_ok=True)
    try:
        home.chmod(0o700)
    except OSError:
        pass
    source = Path(__file__).resolve()
    target = home / "aoi_pc_bootstrap.py"
    if source != target:
        shutil.copy2(source, target)
    cfg = read_config(home)
    token = str(cfg.get("token", "")) or secrets.token_urlsafe(36)
    workspace = Path(cfg.get("workspace", str(home / "workspace"))).expanduser()
    workspace.mkdir(parents=True, exist_ok=True)
    address = tailscale_ipv4()
    cfg = {
        "version": VERSION,
        "token": token,
        "workspace": str(workspace.resolve()),
        "host": address or "127.0.0.1",
        "port": int(cfg.get("port", 43821)),
        "network_mode": "tailscale" if address else "loopback_only",
        "created_at": cfg.get("created_at", int(time.time())),
    }
    config_path(home).write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    try:
        config_path(home).chmod(0o600)
    except OSError:
        pass
    startup = "not registered"
    if not no_start:
        startup = install_startup(home)
        if platform.system() == "Windows":
            start_detached(target)
    return {"home": str(home), "workspace": str(workspace), "host": cfg["host"], "port": cfg["port"], "network_mode": cfg["network_mode"], "token": token, "startup": startup}


def start_detached(script: Path) -> None:
    flags = 0
    if os.name == "nt":
        flags = getattr(subprocess, "DETACHED_PROCESS", 0) | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    try:
        subprocess.Popen([sys.executable, str(script), "serve"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=(os.name != "nt"), creationflags=flags)
    except OSError:
        pass


class Handler(BaseHTTPRequestHandler):
    server_version = "AoiPC/" + VERSION

    def log_message(self, fmt: str, *args) -> None:
        home = companion_home()
        try:
            with (home / "companion.log").open("a", encoding="utf-8") as log:
                log.write("%s %s\n" % (self.log_date_time_string(), fmt % args))
        except OSError:
            pass

    def do_GET(self) -> None:
        cfg = read_config()
        if self.path == "/health":
            self._json(200, {"service": "Aoi PC Companion", "version": VERSION, "status": "online"})
            return
        if self.path != "/v1/status":
            self._json(404, {"error": "not_found"})
            return
        supplied = self.headers.get("Authorization", "").removeprefix("Bearer ").strip()
        if not hmac.compare_digest(supplied, str(cfg.get("token", ""))):
            self._json(401, {"error": "unauthorized"})
            return
        self._json(200, {
            "name": HOSTNAME,
            "os": platform.platform(),
            "version": VERSION,
            "uptime_seconds": int(time.monotonic() - STARTED),
            "workspace": cfg.get("workspace", ""),
            "network_mode": cfg.get("network_mode", "loopback_only"),
            "address": cfg.get("host", "127.0.0.1"),
            "port": cfg.get("port", 43821),
            "capabilities": ["health", "status"],
            "remote_execution_enabled": False,
        })

    def _json(self, status: int, value: dict) -> None:
        body = json.dumps(value).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


def serve() -> None:
    cfg = read_config()
    if not cfg:
        raise SystemExit("Aoi PC Companion is not installed. Run: python aoi_pc_bootstrap.py install")
    global STARTED
    STARTED = time.monotonic()
    while True:
        cfg = read_config()
        host = str(cfg.get("host", "127.0.0.1"))
        port = int(cfg.get("port", 43821))
        try:
            server = ThreadingHTTPServer((host, port), Handler)
        except OSError:
            # Tailscale may start after the desktop login service. Keep retrying,
            # and refresh the bound address if the tailnet IP changed after reboot.
            if str(cfg.get("network_mode", "")) != "tailscale":
                raise
            refreshed = tailscale_ipv4()
            if refreshed and refreshed != host:
                cfg["host"] = refreshed
                config_path().write_text(json.dumps(cfg, indent=2), encoding="utf-8")
            time.sleep(8)
            continue
        server.daemon_threads = True
        try:
            server.serve_forever(poll_interval=0.5)
        except KeyboardInterrupt:
            server.server_close()
            break
        finally:
            server.server_close()
        break


STARTED = time.monotonic()


def status() -> None:
    cfg = read_config()
    if not cfg:
        print("Aoi PC Companion: not installed")
        return
    print(json.dumps({key: value for key, value in cfg.items() if key != "token"}, indent=2))


def uninstall() -> None:
    home = companion_home()
    system = platform.system()
    if system == "Windows":
        startup = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming")) / "Microsoft" / "Windows" / "Start Menu" / "Programs" / "Startup" / "AoiPCCompanion.vbs"
        startup.unlink(missing_ok=True)
    elif system == "Darwin":
        plist = Path.home() / "Library" / "LaunchAgents" / "com.aoi.pc-companion.plist"
        subprocess.run(["launchctl", "unload", str(plist)], capture_output=True, timeout=5, check=False)
        plist.unlink(missing_ok=True)
    else:
        unit = Path.home() / ".config" / "systemd" / "user" / "aoi-pc-companion.service"
        subprocess.run(["systemctl", "--user", "disable", "--now", "aoi-pc-companion.service"], capture_output=True, timeout=8, check=False)
        unit.unlink(missing_ok=True)
    print("Startup registration removed. Companion data remains at:", home)
    print("Delete that folder manually if you also want to remove its token and workspace.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Install or manage the optional Aoi PC Companion.")
    parser.add_argument("command", choices=["install", "serve", "status", "uninstall"], nargs="?", default="install")
    parser.add_argument("--no-start", action="store_true", help="Install files without registering startup or launching the service")
    args = parser.parse_args()
    if args.command == "install":
        result = install(no_start=args.no_start)
        print("Aoi PC Companion installed.")
        print(json.dumps({key: value for key, value in result.items() if key != "token"}, indent=2))
        print("Pairing token (store privately; enter it in Aoi):", result["token"])
        if result["network_mode"] == "loopback_only":
            print("Remote pairing is disabled. Install and sign in to Tailscale on this PC and phone, then rerun install.")
        print("This milestone exposes status only; remote commands and file access are not enabled.")
    elif args.command == "serve":
        serve()
    elif args.command == "status":
        status()
    elif args.command == "uninstall":
        uninstall()


if __name__ == "__main__":
    main()
