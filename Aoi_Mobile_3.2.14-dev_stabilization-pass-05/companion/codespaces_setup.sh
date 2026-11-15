#!/usr/bin/env bash
set -euo pipefail

GODOT_VERSION="4.8-beta1"
# Godot reports prerelease versions with dots (4.8.beta1), while the
# downloadable archive and installation directory use hyphens.
GODOT_VERSION_PREFIX="${GODOT_VERSION/-/.}"
GODOT_URL="https://github.com/godotengine/godot-builds/releases/download/4.8-beta1/Godot_v4.8-beta1_linux.x86_64.zip"
GODOT_SHA256="199b2d6a0daa3a74a697356f31c33347f997f65258ba7dd07ca8c1110757927d"
INSTALL_DIR="$HOME/.local/opt/godot-$GODOT_VERSION"
BIN_DIR="$HOME/.local/bin"
VENV_DIR="$HOME/.local/share/aoi-bridge-venv"

mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$HOME/aoi_workspace"

# Project code must not execute as the account holding AOI_BRIDGE_TOKEN.
# The Codespace bridge stays under vscode; terminal commands and Godot run
# under the unprivileged aoi-runner account with access only to this workspace.
if ! id aoi-runner >/dev/null 2>&1 || ! getent group aoi-workspace >/dev/null 2>&1; then
  echo "The isolated Aoi project runner is missing. Rebuild the Codespace container." >&2
  exit 1
fi
sudo -n chgrp -R aoi-workspace "$HOME/aoi_workspace"
find "$HOME/aoi_workspace" -type d -exec chmod 2770 {} +
find "$HOME/aoi_workspace" -type f -exec chmod g+rw {} +
chmod 2770 "$HOME/aoi_workspace"
sudo -n -u aoi-runner -g aoi-workspace -- test -r "$HOME/aoi_workspace"
sudo -n -u aoi-runner -g aoi-workspace -- test -w "$HOME/aoi_workspace"
current_version=""
if [[ -x "$BIN_DIR/godot" ]]; then
  current_version="$("$BIN_DIR/godot" --version 2>/dev/null || true)"
fi
if [[ "$current_version" != "$GODOT_VERSION_PREFIX"* ]]; then
  rm -f "$BIN_DIR/godot"
  archive="$(mktemp --suffix=.zip)"
  trap 'rm -f "$archive"' EXIT
  curl --fail --location --retry 3 --retry-delay 2 "$GODOT_URL" -o "$archive"
  echo "$GODOT_SHA256  $archive" | sha256sum --check --status || {
    echo "Godot download did not match the official SHA-256 release digest." >&2
    exit 1
  }
  unzip -o -q "$archive" -d "$INSTALL_DIR"
  godot_binary="$(find "$INSTALL_DIR" -maxdepth 2 -type f -name 'Godot_v4.8-beta1_linux.x86_64' -print -quit)"
  if [[ -z "$godot_binary" ]]; then
    echo "The verified Godot archive did not contain the expected Linux executable." >&2
    exit 1
  fi
  chmod +x "$godot_binary"
  ln -sfn "$godot_binary" "$BIN_DIR/godot"
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  python3 -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/python" -m pip install --disable-pip-version-check --upgrade "mss>=9,<11" "Pillow>=10,<13"
installed_version="$("$BIN_DIR/godot" --version)"
if [[ "$installed_version" != "$GODOT_VERSION_PREFIX"* ]]; then
  echo "Expected Godot $GODOT_VERSION but found $installed_version." >&2
  exit 1
fi
printf '%s\n' "$installed_version"
printf '\nAoi cloud runtime installed. Workspace: %s\n' "$HOME/aoi_workspace"
