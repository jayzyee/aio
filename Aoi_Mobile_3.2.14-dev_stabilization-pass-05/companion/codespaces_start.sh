#!/usr/bin/env bash
set -euo pipefail
umask 0002

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_PYTHON="$HOME/.local/share/aoi-bridge-venv/bin/python"
BRIDGE="$ROOT/companion/aoi_linux_bridge.py"
PID_FILE="$HOME/.aoi-bridge.pid"
LOG_FILE="$HOME/.aoi-bridge.log"
XVFB_PID_FILE="$HOME/.aoi-xvfb.pid"

process_is_live() {
  local state
  state="$(ps -p "$1" -o stat= 2>/dev/null | tr -d ' ' || true)"
  [[ -n "$state" && "$state" != Z* && "$state" != X* ]]
}

if [[ -z "${AOI_BRIDGE_TOKEN:-}" || ! "${AOI_BRIDGE_TOKEN}" =~ ^[a-fA-F0-9]{64}$ ]]; then
  echo "Aoi cloud bridge is not started. Add the 64-character hexadecimal AOI_BRIDGE_TOKEN repository secret." >&2
  exit 0
fi
if [[ ! -x "$VENV_PYTHON" || ! -x "$HOME/.local/bin/godot" ]]; then
  echo "Aoi cloud runtime is incomplete. Rebuild the Codespace so its setup can finish." >&2
  exit 1
fi
mkdir -p "$HOME/aoi_workspace"

# Reuse Xvfb only when the saved PID still belongs to Xvfb. Never trust a stale
# PID file after Codespaces has recycled a process ID.
if [[ -s "$XVFB_PID_FILE" ]]; then
  xvfb_pid="$(cat "$XVFB_PID_FILE" 2>/dev/null || true)"
  xvfb_cmd="$(ps -p "$xvfb_pid" -o comm= 2>/dev/null || true)"
else
  xvfb_pid=""
  xvfb_cmd=""
fi
if [[ "$xvfb_cmd" != "Xvfb" ]]; then
  rm -f "$XVFB_PID_FILE"
  # Clear only stale X11 socket/lock files after confirming the saved process
  # is not the active server. Do not let a slow Xvfb startup race Godot launch.
  rm -f /tmp/.X11-unix/X99 /tmp/.X99-lock
  Xvfb :99 -screen 0 1440x900x24 -nolisten tcp -noreset > "$HOME/.aoi-xvfb.log" 2>&1 &
  echo $! > "$XVFB_PID_FILE"
  xvfb_pid="$(cat "$XVFB_PID_FILE")"
  display_ready=0
  for _ in {1..40}; do
    if ! process_is_live "$xvfb_pid"; then break; fi
    if [[ -S /tmp/.X11-unix/X99 ]]; then display_ready=1; break; fi
    sleep 0.125
  done
  if [[ "$display_ready" -eq 0 ]]; then
    kill -TERM "$xvfb_pid" 2>/dev/null || true
    rm -f "$XVFB_PID_FILE"
    echo "Could not start the cloud display:" >&2
    cat "$HOME/.aoi-xvfb.log" >&2 || true
    exit 1
  fi
fi

# Stop only the bridge process recorded by this project. A stale PID must not
# kill an unrelated process in the Codespace.
if [[ -s "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  old_cmd="$(ps -p "$old_pid" -o args= 2>/dev/null || true)"
  if [[ "$old_pid" =~ ^[0-9]+$ && "$old_cmd" == *"$BRIDGE"* ]]; then
    kill -TERM "$old_pid" 2>/dev/null || true
    stopped=0
    for _ in {1..20}; do
      if ! process_is_live "$old_pid"; then stopped=1; break; fi
      sleep 0.25
    done
    if [[ "$stopped" -eq 0 ]]; then
      kill -KILL "$old_pid" 2>/dev/null || true
      for _ in {1..8}; do
        if ! process_is_live "$old_pid"; then stopped=1; break; fi
        sleep 0.25
      done
    fi
    if [[ "$stopped" -eq 0 ]]; then
      echo "The previous Aoi bridge process would not stop; refusing to start a duplicate." >&2
      exit 1
    fi
  fi
  rm -f "$PID_FILE"
fi

export DISPLAY=:99
export LIBGL_ALWAYS_SOFTWARE=1
nohup "$VENV_PYTHON" "$BRIDGE" \
  --host 0.0.0.0 \
  --port 8765 \
  --allow-public-interface \
  --workspace "$HOME/aoi_workspace" \
  --godot "$HOME/.local/bin/godot" \
  --runner-user aoi-runner \
  --runner-group aoi-workspace \
  > "$LOG_FILE" 2>&1 &
bridge_pid=$!
echo "$bridge_pid" > "$PID_FILE"

for _ in {1..30}; do
  if ! process_is_live "$bridge_pid"; then
    echo "Aoi bridge exited during startup:" >&2
    cat "$LOG_FILE" >&2 || true
    rm -f "$PID_FILE"
    exit 1
  fi
  if curl --silent --fail --max-time 2 -H "X-Aoi-Token: $AOI_BRIDGE_TOKEN" http://127.0.0.1:8765/health >/dev/null; then
    echo "Aoi cloud workspace is running. Open the Codespaces Ports panel and copy port 8765 into Aoi."
    exit 0
  fi
  sleep 0.5
done
kill -TERM "$bridge_pid" 2>/dev/null || true
wait "$bridge_pid" 2>/dev/null || true
rm -f "$PID_FILE"
echo "Aoi bridge failed its authenticated startup check:" >&2
cat "$LOG_FILE" >&2 || true
exit 1
