# Aoi Mobile — Android setup guide

This guide covers the phone app, its optional cloud runtime, and the separate toolchain used to export an APK. These are distinct environments.

## 1. Android app

- Install the Aoi APK exported for your device.
- Ordinary chat, model selection, projects, personal knowledge and local settings run in the Godot app. Python and Termux are not prerequisites.
- Connect a model provider in **Setup**. Aoi uses the API key you provide; provider model availability, pricing and regional limits are controlled by that provider.
- Setup also accepts a custom OpenAI-compatible API root and discovers its chat models from `/models`. The endpoint must use HTTPS, except localhost HTTP for development. Aoi sends the key and requested chat content to the endpoint you configure; only the encrypted key is stored locally.

## 2. Optional cloud Linux for Godot games

Aoi's full game-creation workflow can use a remote Linux runtime. The recommended first provider is GitHub Codespaces. Your phone remains the Aoi interface; you do not need to host Linux on the phone or keep your personal computer online.

Follow [`LINUX_GITHUB_SETUP.md`](LINUX_GITHUB_SETUP.md). In summary, place this Aoi project in a private GitHub repository, add the generated 64-character `AOI_BRIDGE_TOKEN` as a Codespaces repository secret, create or rebuild a Codespace, make forwarded port 8765 Public, then save the forwarded HTTPS URL and same key in Aoi under **Connections → Cloud Linux workspace**. The included dev-container installs the matching Godot runtime and starts the authenticated bridge.

GitHub Codespaces Free usage is capped by monthly compute and storage allowances; it is not an unlimited server. GitHub Actions provides ephemeral Linux jobs and is suitable for future build automation, but it is not a persistent interactive runtime. Oracle Cloud Always Free is another possible host, but requires separate setup and capacity is not guaranteed. Details and current official references are in the cloud setup guide.

**Security:** the forwarded Codespaces port is internet-reachable when Public. Every bridge request needs the generated token, but the bridge is not an OS sandbox; shell commands run with the remote workspace user's permissions. Use a private repository, keep the key out of source control and stop the Codespace when it is not needed.

## 3. Android Clock and Calendar tools

The Android APK includes a Godot Android plugin for user-approved system intents. In chat, Aoi can open Android Clock with a one-time alarm prefilled or Android Calendar with an event prefilled. You must confirm Save in the destination app. Aoi does not read existing calendar events, schedule background notifications, or know whether you saved the item. These actions do not request calendar access or exact-alarm permissions.

The plugin is built from `addons/aoi_android_actions/src/main/java/com/aoi/mobile/android/AoiAndroidActionsPlugin.java`. To regenerate its AAR, set `ANDROID_SDK_ROOT` and `GODOT_ANDROID_SOURCE_ZIP` to the Android SDK and matching Godot 4.8 template source zip, then run `bash addons/aoi_android_actions/build_plugin.sh`. The Android export preset uses Gradle because Godot v2 Android plugins require it.

## 4. Export the Android APK

The supplied source project targets Godot **4.8 beta 1**. Use the matching editor build and export templates for this development checkpoint. A probe against Godot 4.7.2 stable currently fails the Aoi Studio editor-addon compile and the automated touch-scroll checks, so do not switch engine versions until that compatibility work is complete.

1. Open `project.godot` in Godot 4.8 beta 1.
2. Install matching export templates from **Editor → Manage Export Templates**.
3. Use **Project → Install Android Build Template** or the Android export preset setup flow to configure the Java/Android SDK components. The project targets Android API 24 minimum (Android 7.0), which includes Android 8.0 and 8.1, and API 36 target.
4. If configuring manually, install OpenJDK 17 and the Android SDK command-line tools. Configure Java SDK and Android SDK paths in **Editor Settings → Export → Android**.
5. Open **Project → Export**, select the Android preset and export a debug APK.
6. Install the APK on the phone. For USB, enable Developer options and USB debugging, then use `adb install -r path/to/aoi-mobile.apk`. Otherwise copy it to the device and install it through a file manager.

Official guide: https://docs.godotengine.org/en/latest/tutorials/export/exporting_for_android.html

The current export preset includes arm64-v8a and armeabi-v7a support, network permissions and app icons. The APK still needs export with matching templates and acceptance on the physical target phone. Android will reject an in-place update signed with a different key.

## 5. Physical-device review

A desktop render at a phone-sized resolution is not a substitute for a real Android review. On the actual Android 8.1 device, check:

- Status bar, camera/notch area, rounded corners and navigation/gesture areas do not overlap content.
- The composer remains visible when the keyboard opens, and multiline input scrolls internally after reaching its intended height.
- Sheets and menus fit short viewports, scroll fully and can be dragged or dismissed reliably.
- Touch scrolling still works when a drag begins over a card, label, button or message.
- Back closes the topmost sheet/drawer before leaving the current screen.
- Backgrounding, process recreation and returning to a chat preserve drafts, project activity and tool results.
- A cloud Godot game can be launched, stopped, checked and captured while its process is genuinely running.

Physical Android acceptance remains separate from a successful desktop editor run. Confirm alarm and calendar actions hand off to installed apps, and verify the user can review and save each prefilled item.
