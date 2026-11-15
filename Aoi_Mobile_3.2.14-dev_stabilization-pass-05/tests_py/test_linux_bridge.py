#!/usr/bin/env python3
"""Loopback integration tests for the Aoi Termux/Linux companion bridge."""
from __future__ import annotations
import importlib.util
import json
import os
import tempfile
import time
from types import SimpleNamespace
import threading
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("aoi_linux_bridge", ROOT / "companion" / "aoi_linux_bridge.py")
assert SPEC and SPEC.loader
BRIDGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BRIDGE)


def request(base: str, route: str, token: str = "", payload: dict | None = None):
    data = None if payload is None else json.dumps(payload).encode()
    headers = {}
    if token:
        headers["X-Aoi-Token"] = token
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(base + route, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=4) as response:
            return response.status, json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode())


def run() -> int:
    results: list[tuple[str, bool]] = []
    def check(name: str, passed: bool):
        results.append((name, passed))
        print(f"LINUX_{name} {'PASS' if passed else 'FAIL'}")

    with tempfile.TemporaryDirectory(prefix="aoi-bridge-test-") as temp:
        workspace = Path(temp) / "workspace"
        workspace.mkdir()
        token = "aoi-test-token-" + "x" * 30
        server = BRIDGE.create_server(
            "127.0.0.1", 0, token, workspace, "__aoi_missing_godot__"
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_port}"
        try:
            status, payload = request(base, "/health")
            check("unauthorized_health_denied", status == 401)
            status, payload = request(base, "/health", token)
            check("authenticated_health_ok", status == 200 and payload.get("ok") is True)
            check("missing_godot_is_reported_as_unavailable", status == 200 and payload.get("capabilities", {}).get("godot") is False)
            status, payload = request(base, "/v1/write", token, {"path": "notes/readme.txt", "content": "Aoi workspace note"})
            check("workspace_write_ok", status == 200 and (workspace / "notes/readme.txt").read_text() == "Aoi workspace note")
            original_replace = BRIDGE.os.replace
            def fail_replace(source, destination):
                raise OSError("injected replacement failure")
            BRIDGE.os.replace = fail_replace
            replacement_failed = False
            try:
                BRIDGE.atomic_write_file(workspace / "notes" / "readme.txt", b"partial replacement")
            except OSError:
                replacement_failed = True
            finally:
                BRIDGE.os.replace = original_replace
            leftovers = [path for path in (workspace / "notes").iterdir() if ".aoi-tmp-" in path.name]
            check("failed_atomic_replacement_preserves_old_file",
                  replacement_failed and (workspace / "notes" / "readme.txt").read_text() == "Aoi workspace note" and not leftovers)
            status, payload = request(base, "/v1/read", token, {"path": "notes/readme.txt"})
            check("workspace_read_roundtrip", status == 200 and payload.get("content") == "Aoi workspace note")
            status, payload = request(base, "/v1/list", token, {"path": "notes"})
            check("workspace_list_ok", status == 200 and any(x.get("name") == "readme.txt" for x in payload.get("items", [])))
            status, payload = request(base, "/v1/read", token, {"path": "../outside.txt"})
            check("workspace_path_escape_denied", status == 400)
            status, payload = request(base, "/v1/exec", token, {"command": "python -c \"print('aoi-ok')\"", "cwd": ".", "timeout": 5})
            check("workspace_command_runs", status == 200 and payload.get("exit_code") == 0 and "aoi-ok" in payload.get("stdout", ""))
            status, payload = request(base, "/v1/exec", token, {"command": "sudo id", "cwd": ".", "timeout": 5})
            check("privilege_escalation_blocked", status == 403)

            # Exercise the cloud runner environment builder without requiring
            # sudo or mutating the host's account database.
            handler = BRIDGE.Bridge.__new__(BRIDGE.Bridge)
            handler.server = SimpleNamespace(
                runner_user="aoi-runner", runner_group="aoi-workspace", workspace=workspace
            )
            prefix, runner_env = handler._runner_prefix({
                "GODOT": "/home/vscode/.local/bin/godot",
                "AOI_BRIDGE_TOKEN": "must-not-pass",
                "GITHUB_TOKEN": "must-not-pass",
                "GH_TOKEN": "must-not-pass",
            })
            check("cloud_runner_uses_separate_account", prefix[:4] == ["sudo", "-n", "-u", "aoi-runner"])
            check("cloud_runner_environment_excludes_credentials",
                  all(key not in runner_env for key in ("AOI_BRIDGE_TOKEN", "GITHUB_TOKEN", "GH_TOKEN")))
            check("cloud_runner_keeps_explicit_godot_path",
                  runner_env.get("GODOT") == "/home/vscode/.local/bin/godot")

            local_handler = BRIDGE.Bridge.__new__(BRIDGE.Bridge)
            local_handler.server = SimpleNamespace(runner_user="", runner_group="", workspace=workspace)
            start = time.monotonic()
            bounded = local_handler._run_bounded(["bash", "-lc", "sleep 8 & wait"], workspace, 0.25, None)
            check("timed_out_command_group_is_terminated",
                  bounded.timed_out and bounded.returncode == 124 and time.monotonic() - start < 4.5)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
    failed = sum(not ok for _, ok in results)
    print(f"LINUX_BRIDGE_SUMMARY {len(results) - failed}/{len(results)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(run())
