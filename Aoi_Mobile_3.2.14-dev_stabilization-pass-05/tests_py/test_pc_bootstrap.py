#!/usr/bin/env python3
"""Tests the optional one-file PC companion bootstrap without installing startup hooks."""
import importlib.util
import json
import os
import tempfile
import threading
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "companion" / "aoi_pc_bootstrap.py"


def main():
    passed = 0
    total = 0

    def check(name, ok):
        nonlocal passed, total
        total += 1
        if ok:
            passed += 1
        else:
            print("PC_BOOTSTRAP_", name, " FAIL", sep="")

    with tempfile.TemporaryDirectory(prefix="aoi_pc_test_") as tmp:
        os.environ["AOI_PC_HOME"] = str(Path(tmp) / "companion")
        spec = importlib.util.spec_from_file_location("aoi_pc_bootstrap", SOURCE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.tailscale_ipv4 = lambda: ""
        installed = module.install(no_start=True)
        cfg = module.read_config()
        check("INSTALL_CREATES_CONFIG_AND_WORKSPACE", Path(installed["home"]).is_dir() and Path(installed["workspace"]).is_dir() and cfg.get("token"))
        check("INSTALL_DEFAULTS_TO_LOOPBACK_WITHOUT_TAILSCALE", installed["host"] == "127.0.0.1" and installed["network_mode"] == "loopback_only")
        check("INSTALL_NEVER_EXPOSES_REMOTE_EXECUTION", "remote_execution_enabled" not in cfg and "token" in cfg)

        server = ThreadingHTTPServer(("127.0.0.1", 0), module.Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = "http://127.0.0.1:%d" % server.server_address[1]
        try:
            with urllib.request.urlopen(base + "/health", timeout=3) as response:
                health = json.loads(response.read().decode())
            check("HEALTH_ENDPOINT_READS_ONLINE", health.get("status") == "online")
            try:
                urllib.request.urlopen(base + "/v1/status", timeout=3)
                unauthorized = False
            except urllib.error.HTTPError as error:
                unauthorized = error.code == 401
            check("STATUS_REJECTS_MISSING_TOKEN", unauthorized)
            request = urllib.request.Request(base + "/v1/status", headers={"Authorization": "Bearer " + cfg["token"]})
            with urllib.request.urlopen(request, timeout=3) as response:
                status = json.loads(response.read().decode())
            check("STATUS_ACCEPTS_VALID_TOKEN", status.get("name") and status.get("remote_execution_enabled") is False)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    os.environ.pop("AOI_PC_HOME", None)
    print("PC_BOOTSTRAP_SUMMARY %d/%d passed" % (passed, total))
    raise SystemExit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
