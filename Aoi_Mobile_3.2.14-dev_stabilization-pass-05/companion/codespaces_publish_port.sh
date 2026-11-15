#!/usr/bin/env bash
set -euo pipefail

# GitHub resets a public forwarded port to private when a Codespace restarts.
# Re-apply this only after the user has attached to their own Codespace.
if [[ -n "${CODESPACE_NAME:-}" ]] && command -v gh >/dev/null 2>&1; then
  gh codespace ports visibility 8765:public -c "$CODESPACE_NAME" >/dev/null 2>&1 || {
    echo "Aoi bridge is running, but GitHub did not allow automatic public port access. Set port 8765 to Public in the Ports panel."
  }
fi
