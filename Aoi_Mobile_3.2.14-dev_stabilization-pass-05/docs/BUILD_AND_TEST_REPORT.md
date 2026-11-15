# Aoi Mobile — build and verification report

## Current working snapshot: 3.1.0-dev (2026-11-12)

This checkpoint continues from the newest 3.1 redesign working tree. It does not replace it with the older Library 3.0.2-dev archive.

### Visible and behavioral changes in this snapshot

- Global Preferences now contain the user's full saved engineering standard, carried into the actual chat system context. The main page displays a readable preview; a separate editor handles changes and length validation.
- Added the Aoi-wide Goals & ambitions category and the user's general Aoi workspace vision as a reusable global reference. Global reference categories can be filtered in Preferences. Library cards now show clean Markdown-aware excerpts without changing the stored source text.
- Repositioned the user-facing Studio destination as **Workbench**, making its general project/task role clearer while retaining optional Godot-specific tools.
- Removed the redundant model connection shortcut from the disconnected Chat header. The main setup call-to-action remains in the empty state; a selected provider shortcut appears only when both a model and its key are present.
- Sending without a configured provider now routes to setup without clearing the user's draft.
- Store writes now preserve a last-known-good copy for JSON records, settings and encrypted credentials; recovery restores the previous complete state after an interrupted or corrupt write. Delete operations remove backup/temp sidecars to prevent deleted records returning.

### Actual runtime verification

Godot engine: `4.8.beta1.official.4d10419ca` running in a Linux desktop render environment with the Compatibility renderer (llvmpipe). The app was rendered at 720 × 1520 and Chat, Projects, Workbench, Explore, Library and Preferences were inspected from current screenshots. Focused GDScript behavior probes exercised preference migration and editing, chat provider setup/draft preservation, and recovery/deletion behavior through the real Store implementation.

- `tests/preferences_behavior_probe.tscn`: actual global preference preview/editor/save, reference category filtering, global vision persistence and chat context coverage.
- `tests/persistence_recovery_probe.tscn`: interrupted save recovery, retained last-known-good snapshots, corrupt settings and encrypted credential recovery, and no resurrection after deletion.
- `tests/chat_shell_behavior_probe.tscn`: disconnected header state, retained new-chat action, draft preservation during provider setup, active model shortcut visibility and stale-key removal.
- `tests/preferences_behavior_probe.tscn`: additionally verifies that Library preview formatting removes raw Markdown syntax from the Aoi workspace-vision excerpt.

Screenshots captured for this milestone are in `docs/review_3_1/`. They are desktop Godot renders at a phone-sized viewport, not screenshots from the user's physical phone.

### Not verified / still open

- Physical Android 8.1 handset behavior, APK export, keyboard geometry, camera cutout and gesture insets on the handset.
- Full real-provider streaming/tool-call E2E against live external providers and credentials in this environment.
- Full integrated Projects, Explore and Workbench usability redesign; this checkpoint improves shared product direction but does not claim those screens are finished. Explore remains dense and card-heavy, and the app-wide visual system needs a stronger second redesign pass.
- Startup/import emits an unresolved Godot `Unexpected NUL character` parsing warning. It remains visible in runtime logs and needs a separate source-level diagnosis.
- Full accessibility audit, longer soak/memory lifecycle, and Android performance profiling.

The above items are unverified or still open, not assumed passed. Do not treat this source snapshot as a finished or stable mobile release.

---

## Historical verification record — 2.9.0 baseline

## Release summary

Aoi Mobile 2.9.0 builds on the 2.8.0 Aoi Studio checkpoint. The new work adds an embedded Godot API explorer, GDScript compiler validation, a constrained native scene builder, local scene preview, an optional PC companion plugin entry and a one-file Python PC bootstrap foundation.

## Substantial changes in this development pass

1. **Live Godot API Explorer:** enumerates the active engine's ClassDB (1,088 classes in the reviewed Godot 4.8 beta1 runtime), searches class names and lazily loads selected class methods, argument types, properties and signals. Details are cached only after a class is opened.
2. **Compiler-backed GDScript validation:** uses Godot's own `GDScript.reload()` path and a 256 KB size cap. The new-script save flow validates before writing.
3. **Native scene builder and preview:** creates a portable `.tscn` starter platformer scaffold with a real `CharacterBody2D`, capsule collision, `Camera2D`, `StaticBody2D` ground and rectangle collision, then previews the saved scene locally without a PC. This is not yet a playable game; movement logic and on-screen controls are not attached.
4. **Optional PC Companion entry:** adds an Explore/Plugins card and a responsive setup/status panel that clearly labels the companion as optional and not yet paired. The card does not pretend that the PC is connected.
5. **One-file PC bootstrap:** adds `companion/aoi_pc_bootstrap.py`, standard-library-only, with install/status/uninstall commands, local workspace creation, a random bearer token, OS-specific startup registration code and a token-authenticated status endpoint. It binds to a Tailscale interface when detected and otherwise binds only to loopback. It exposes no remote shell or file/command execution in this milestone.
6. **Responsive Explore categories:** replaces the clipped horizontal category rail with a wrapping flow layout after screenshot review exposed the cutoff on a 720 px phone viewport.
7. **Credential-store reliability:** avoids serializing an empty encrypted ConfigFile when the final API key is removed, eliminating an engine error seen during first-run UI tests.
8. **Regression coverage and documentation:** adds focused API, compiler, scene, PC bootstrap and UI tests plus sandbox/PC setup guides.

## Visual review

Fresh Godot-rendered 720 × 1520 captures are in `docs/review_2_9/`:

- `explore_720x1520.png` — category chips wrap cleanly; no horizontal cutoff.
- `studio_720x1520.png` — Sources workspace and bottom composer.
- `studio_api_720x1520.png` — live API Explorer with a full-width mobile layout and readable class list/detail panel.
- `pc_companion_720x1520.png` — optional PC setup plan and security limitations.

The first API Explorer and PC setup modal captures had dark, clipped content. Both were rebuilt with a white panel, full-rect layout, and scrollable mobile content; the final captures above are the corrected versions. These are desktop-engine renders at a phone-sized viewport, not physical Android screenshots.

## Automated verification

Engine: `4.8.beta1.official.4d10419ca` (Godot 4.8 beta1).

| Suite | Result | Coverage |
|---|---:|---|
| Linux bridge | 8/8 | Token auth, workspace confinement, file operations and command policy |
| Aoi Studio bridge | 10/10 | Project create/import/scan, binary uploads, run/test/stop/logs |
| PC bootstrap | 6/6 | Temp install, loopback-only fallback, health endpoint, missing-token rejection and valid-token status |
| Godot EditorPlugin load | 1/1 | Clean temporary editor project loads the addon |
| Godot logic | 71/71 | Existing logic plus ClassDB, class inspection, compiler validation, safe paths, file writes, native scene packing and collision shapes |
| Provider end-to-end | 17/17 | Streaming, model selection, fallback, errors and cancellation |
| Whole app UI | 61/61 | Existing screens plus PC companion card/modal, wrapping category chips, scene builder/preview and API Explorer selection |
| **Main suite total** | **174/174** | All suites in `run_tests.sh` passed |
| Touch scrolling (separate GUI process) | 6/6 | Swipe propagation across chat, setup and project surfaces; run with `run_touch_tests.sh` |
| **Combined verified total** | **180/180** | Main suite and separate touch suite passed |

Run locally with:

```bash
GODOT=/path/to/Godot_v4.8-beta1_linux.x86_64 ./run_tests.sh
GODOT=/path/to/Godot_v4.8-beta1_linux.x86_64 ./run_touch_tests.sh
```

The main suite's final output was `ALL MOBILE TESTS PASSED`. The touch suite is launched separately because two GUI Godot processes sequentially inside a single Xvfb session were unstable in this headless container. Godot uses the dummy audio driver in this headless environment because no audio device is present; that does not affect the UI or logic tests.

## Important limitations

- This is a Godot source project, not an exported APK. Android SDK/JDK/export templates were not configured for this pass.
- No physical Android 8.1/Oppo device validation has been performed. Camera cutout, bottom gesture area, keyboard resize, lifecycle and touch feel still require device testing.
- The embedded sandbox is not the Godot Editor. It does not execute arbitrary imported GDScript in the Aoi process. It uses a restricted node/property allow-list for generated scenes.
- The starter 2D scene is a scene and physics scaffold, not a completed playable platformer.
- The PC bootstrap is an initial service foundation. It exposes only `/health` and authenticated `/v1/status`. It does not yet integrate its token/status into the Aoi mobile connection manager, and does not expose file transfer, shell, Godot run/stop, screenshot or log endpoints.
- Tailscale must already be installed and signed in on both devices for secure cross-network reachability. Without Tailscale the service binds to loopback only. No public port forwarding is supported.
- OS-specific startup registration is implemented for Windows Startup, macOS LaunchAgents and Linux systemd user services, but this environment has not physically verified each target OS. The automated bootstrap test uses `--no-start` and tests the HTTP/auth layer on Linux.
- The existing 2.8 paired-PC bridge still uses its prior shared-token HTTP model. Do not expose it outside a trusted LAN; migrate it to the private authenticated transport before remote-network use.

## Next acceptance milestone

1. Build a proper on-device project importer/exporter with ZIP traversal, size and compression-ratio preflight.
2. Expand the scene blueprint schema and create a playable touch-controlled 2D sandbox loop with collision/physics.
3. Add compile diagnostics and dependency checks for multi-file projects.
4. Integrate the PC bootstrap with Aoi's connection manager using device pairing, token rotation, Tailscale address discovery, online/offline/last-seen status and reconnect handling.
5. Add bounded approved PC tools only after pairing, audit logging, timeout, cancellation and security tests pass.
6. Export a debug APK and test on the actual Android phone.
