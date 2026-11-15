#!/usr/bin/env bash
# Kept separate because running two GUI Godot processes sequentially inside one Xvfb
# session is unstable in some headless CI/container environments.
cd "$(dirname "$0")"
GODOT=${GODOT:-godot}
if ! command -v xvfb-run >/dev/null; then
  echo "xvfb-run is required for the touch-scroll test on Linux."
  exit 2
fi
GODOT_SILENCE_ROOT_WARNING=1 AOI_MOBILE_DEMO=1 timeout 120 xvfb-run -a -s "-screen 0 720x1280x24" "$GODOT" --audio-driver Dummy --rendering-driver opengl3 --resolution 720x1280 --path . res://tests/e2e_scroll.tscn
