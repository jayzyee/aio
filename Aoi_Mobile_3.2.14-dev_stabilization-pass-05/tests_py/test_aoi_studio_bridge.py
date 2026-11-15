#!/usr/bin/env python3
"""Aoi Studio PC bridge integration tests: project scaffolding, binary sources, run/test/stop/logs."""
from __future__ import annotations
import base64
import importlib.util
import json
import os
import tempfile
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("aoi_studio_bridge", ROOT / "companion" / "aoi_linux_bridge.py")
assert SPEC and SPEC.loader
BRIDGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BRIDGE)


def request(base: str, route: str, token: str, payload: dict | None = None, method: str | None = None):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(base + route, data=data, method=method, headers={"X-Aoi-Token": token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=8) as response:
            return response.status, json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode())


def run() -> int:
    checks: list[tuple[str, bool]] = []
    def check(name: str, passed: bool):
        checks.append((name, passed))
        print(f"STUDIO_{name} {'PASS' if passed else 'FAIL'}")

    with tempfile.TemporaryDirectory(prefix="aoi-studio-bridge-") as temp:
        root = Path(temp) / "workspace"
        root.mkdir()
        fake_godot = Path(temp) / "godot-fake"
        fake_godot.write_text("#!/bin/sh\ncase \"$*\" in *--headless*) echo fake-godot-import-ok; exit 0;; esac\nsleep 25\n", encoding="utf-8")
        fake_godot.chmod(0o755)
        token = "aoi-studio-test-token-" + "q" * 24
        server = BRIDGE.ThreadingHTTPServer(("127.0.0.1", 0), BRIDGE.Bridge)
        server.token = token
        server.workspace = root
        server.godot_executable = str(fake_godot)
        server.godot_processes = {}
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_port}"
        try:
            status, payload = request(base, "/v1/godot/create", token, {"name": "Studio Sample", "path": "projects/studio_sample", "goal": "A small platformer"})
            project = root / "projects" / "studio_sample"
            check("create_godot_project", status == 200 and (project / "project.godot").is_file() and "platformer" in (project / "README.md").read_text())
            status, payload = request(base, "/v1/godot/projects", token, {})
            check("discover_project_manifest", status == 200 and any(x["path"] == "projects/studio_sample" for x in payload.get("projects", [])))
            status, payload = request(base, "/v1/godot/scan", token, {"path": "projects/studio_sample"})
            check("scan_project_tree", status == 200 and any(x["path"] == "project.godot" for x in payload.get("items", [])))
            binary = bytes([0, 1, 2, 255, 128, 65])
            status, payload = request(base, "/v1/upload", token, {"path": "projects/studio_sample/sources/asset.bin", "data": base64.b64encode(binary).decode()})
            check("binary_source_upload", status == 200 and (project / "sources" / "asset.bin").read_bytes() == binary)
            status, payload = request(base, "/v1/upload", token, {"path": "../escape.bin", "data": base64.b64encode(binary).decode()})
            check("binary_upload_path_escape_denied", status == 400)
            (project / "run_tests.sh").write_text("#!/bin/sh\necho STUDIO_FAKE_TEST_SUITE_PASS\nexit 0\n", encoding="utf-8")
            status, payload = request(base, "/v1/godot/test", token, {"path": "projects/studio_sample"})
            check("project_test_script_is_preferred", status == 200 and payload.get("test_kind") == "project test suite" and payload.get("exit_code") == 0)
            status, payload = request(base, "/v1/godot/run", token, {"path": "projects/studio_sample"})
            check("launch_godot_project", status == 200 and payload.get("running") is True)
            status, payload = request(base, "/v1/godot/status", token, {"path": "projects/studio_sample"})
            check("running_state_is_reported", status == 200 and payload.get("running") is True)
            status, payload = request(base, "/v1/godot/stop", token, {"path": "projects/studio_sample"})
            check("godot_process_can_be_stopped", status == 200 and payload.get("running") is False)
            status, payload = request(base, "/v1/godot/logs", token, {"path": "projects/studio_sample"})
            check("godot_log_endpoint_is_available", status == 200 and payload.get("ok") is True)
        finally:
            for proc in server.godot_processes.values():
                if proc.poll() is None:
                    proc.terminate()
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
    failures = sum(not ok for _, ok in checks)
    print(f"STUDIO_BRIDGE_SUMMARY {len(checks)-failures}/{len(checks)} passed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(run())
