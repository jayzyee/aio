#!/usr/bin/env python3
"""Load the Aoi Studio addon in a clean temporary Godot editor project."""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    godot = os.environ.get("GODOT", "godot")
    with tempfile.TemporaryDirectory(prefix="aoi-editor-addon-") as temp:
        project = Path(temp)
        for name in ("project.godot", "icon.svg", "assets", "scripts", "scenes", "addons"):
            source = root / name
            if not source.exists():
                continue
            destination = project / name
            if source.is_dir():
                shutil.copytree(source, destination, ignore=shutil.ignore_patterns("*.import", ".godot", "__pycache__"))
            else:
                shutil.copy2(source, destination)

        config = project / "project.godot"
        data = config.read_text(encoding="utf-8")
        data += '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/aoi_studio/plugin.cfg")\n'
        config.write_text(data, encoding="utf-8")

        env = os.environ.copy()
        env.setdefault("GODOT_SILENCE_ROOT_WARNING", "1")
        command = [godot, "--headless", "--editor", "--path", str(project), "--quit"]
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=90, env=env)
        except (OSError, subprocess.TimeoutExpired) as exc:
            print(f"STUDIO_EDITOR_ADDON_SUMMARY 0/1 failed: {exc}")
            return 1
        output = (result.stdout or "") + "\n" + (result.stderr or "")
        errors = [line for line in output.splitlines() if any(token in line for token in ("SCRIPT ERROR", "Parse Error", "Failed to load script", "Failed to load plugin"))]
        if result.returncode == 0 and not errors:
            print("STUDIO_EDITOR_ADDON_SUMMARY 1/1 passed")
            return 0
        print("STUDIO_EDITOR_ADDON_SUMMARY 0/1 failed")
        print("\n".join(errors[-20:]) or output[-5000:])
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
