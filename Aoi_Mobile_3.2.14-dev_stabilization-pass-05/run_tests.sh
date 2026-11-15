#!/usr/bin/env bash
# Imports project assets, then runs the main regression suite. Run run_touch_tests.sh separately for touch swipes. Needs: GODOT=<path to a Godot 4 binary>, python3, and xvfb-run for the UI test (Linux).
cd "$(dirname "$0")"
set -o pipefail
FAIL=0
echo "== import project assets"
if "$GODOT" --headless --path . --editor --import; then
  echo "PROJECT_IMPORT_SUMMARY passed"
else
  echo "PROJECT_IMPORT_FAIL"
  exit 1
fi
PYTHON=${PYTHON:-python3}
PORT=${MOCK_PORT:-$("$PYTHON" -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')}
"$PYTHON" tests_py/mock_openai_server.py $PORT & MOCK=$!
cleanup () {
  kill "$MOCK" 2>/dev/null || true
  wait "$MOCK" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
sleep 0.7
export MOCK_PORT=$PORT AOI_MOBILE_BASE_OPENROUTER="http://127.0.0.1:$PORT/v1" AOI_MOBILE_BASE_GOOGLE_AI="http://127.0.0.1:$PORT/g/v1" AOI_MOBILE_BASE_PUTER="http://127.0.0.1:$PORT/p/v1"
run () {  # name, then command
  local name="$1"; shift
  local log
  log=$(mktemp "${TMPDIR:-/tmp}/aoi-test.XXXXXX.log")
  echo "== $name"
  # Let Godot write to a regular file. Capturing a long-running GUI process
  # through command substitution + grep can stall Xvfb/Godot on some hosts.
  "$@" >"$log" 2>&1
  local command_status=$?
  local output
  output=$(grep -E "(UNIT|E2E|UI|SCROLL|LINUX_BRIDGE|STUDIO_BRIDGE|STUDIO_EDITOR_ADDON|PC_BOOTSTRAP|PROJECT_JOB)_[A-Z0-9_]*SUMMARY|(UNIT|E2E|UI|SCROLL|LINUX_BRIDGE|STUDIO_BRIDGE|STUDIO_EDITOR_ADDON|PC_BOOTSTRAP|PROJECT_JOB)_.* FAIL|SCRIPT ERROR|Parse Error|ERROR:" "$log" || true)
  echo "$output"
  if [ "$command_status" -ne 0 ]; then
    echo "TEST_COMMAND_EXIT $command_status ($name)"
    FAIL=1
  fi
  if ! echo "$output" | grep -qE "SUMMARY"; then
    echo "TEST_SUMMARY_MISSING ($name); full log: $log"
    FAIL=1
  else
    rm -f "$log"
  fi
  if echo "$output" | grep -qE "FAIL|ERROR"; then FAIL=1; fi
}
run "linux bridge (auth, workspace paths, file tools, command policy)" "$PYTHON" tests_py/test_linux_bridge.py
run "Aoi Studio bridge (project create/import, binary sources, run/test/stop/logs)" "$PYTHON" tests_py/test_aoi_studio_bridge.py
run "PC companion bootstrap (install, loopback, auth, status)" "$PYTHON" tests_py/test_pc_bootstrap.py
run "Godot editor addon (clean editor load)" "$PYTHON" tests_py/test_editor_plugin.py
run "logic (SSE, markdown, catalog, storage)" timeout 90 "$GODOT" --headless --path . res://tests/unit_probe.tscn
run "project-agnostic headless task contract (project-owned tasks, checkpoints, metrics, artifacts, cancellation)" timeout 90 "$GODOT" --headless --path . res://tests/project_jobs_probe.tscn
run "client vs mock provider (streaming, fallback, errors, cancel)" timeout 120 "$GODOT" --headless --path . res://tests/e2e_llm.tscn
if command -v xvfb-run >/dev/null; then
  run "whole phone UI vs mock provider" timeout 300 xvfb-run -a -s "-screen 0 720x1280x24" "$GODOT" --audio-driver Dummy --rendering-driver opengl3 --resolution 720x1280 --path . res://tests/e2e_ui.tscn
fi
[ $FAIL -eq 0 ] && echo "ALL MOBILE TESTS PASSED" || echo "SOME MOBILE TESTS FAILED"
exit $FAIL
