#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ANDROID_SDK_ROOT:-}" || -z "${GODOT_ANDROID_SOURCE_ZIP:-}" ]]; then
	echo "Set ANDROID_SDK_ROOT and GODOT_ANDROID_SOURCE_ZIP to the matching Godot Android template." >&2
	exit 2
fi

android_jar="$ANDROID_SDK_ROOT/platforms/android-36/android.jar"
if [[ ! -f "$android_jar" || ! -f "$GODOT_ANDROID_SOURCE_ZIP" ]]; then
	echo "The Android 36 SDK platform or Godot Android source template is missing." >&2
	exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

unzip -p "$GODOT_ANDROID_SOURCE_ZIP" libs/release/godot-lib.template_release.aar > "$temp_dir/godot.aar"
unzip -p "$temp_dir/godot.aar" classes.jar > "$temp_dir/godot-classes.jar"
mkdir -p "$temp_dir/classes" "$temp_dir/aar"
javac -source 8 -target 8 -Xlint:-options \
	-classpath "$android_jar:$temp_dir/godot-classes.jar" \
	-d "$temp_dir/classes" \
	"$script_dir/src/main/java/com/aoi/mobile/android/AoiAndroidActionsPlugin.java"
jar --create --file "$temp_dir/aar/classes.jar" -C "$temp_dir/classes" .
cp "$script_dir/AndroidManifest.xml" "$temp_dir/aar/AndroidManifest.xml"
(
	cd "$temp_dir/aar"
	zip -q -r "$script_dir/aoi_android_actions.aar" AndroidManifest.xml classes.jar
)
