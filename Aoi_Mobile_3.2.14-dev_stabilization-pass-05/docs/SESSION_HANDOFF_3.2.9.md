# CONTINUE HERE — Aoi Mobile 3.2.9-dev

**Read this file first after a ChatGPT app restart or conversation reset.**  
**Checkpoint:** `Aoi_Mobile_3.2.9-dev_Godot4.8beta1.zip`  
**Engine:** Godot 4.8 beta1 from the user's Library  
**Base:** full 3.2.8 source plus 3.2.9 composer ownership corrections.  
**Project root in this session:** `/mnt/data/aoi_3_2_8_source`

## Do not restart or roll back

Continue from the current 3.2.9 source package. It contains all 3.2.7 recovery/source work and the 3.2.8 approval/queued-message/roadmap work, plus the changes listed below. Do not replace it with a prior 3.2.7 or 3.2.8 snapshot. Older packages are rollback history only.

## Product rules that remain binding

1. Use the actual global preferences file `Global_Working_Preferences_Strict_Engineering_Standards.md` and `docs/AOI_PRODUCT_DIRECTION.md`.
2. User progress updates describe visible functionality and behavior, not test counts.
3. Preserve chat-first, consumer-friendly presentation. Do not put raw tools, terminal output, task graphs or developer jargon into the default user experience.
4. Ordinary chat stays quiet. Activity appears only for real work events and only in the conversation that owns them.
5. A workspace, scaffold, screenshot, or tool success is not a finished requested outcome.
6. Never fabricate percentages, previews, task progress or runtime connectivity.
7. Keep paired-PC live streaming deferred until explicitly reselected by the user.
8. Capture fresh screenshots around 720 × 1600, inspect them inline, correct visible defects, and distinguish desktop/Xvfb renders from physical Android evidence.
9. After every meaningful checkpoint, create a versioned full-source ZIP, clean-extract and verify it, upload the versioned ZIP to Dropbox `/Aoi`, preserve the existing Current under a dated `pre_<version>` name, then copy the new version to `/Aoi/Aoi_Mobile_Current_Godot4.8beta1.zip`. Never destroy the only good checkpoint.
10. Save an updated `SESSION_HANDOFF_<version>.md` in the package every time, because the user may leave ChatGPT and the app may reload.

## Current 3.2.9 implementation

### 3.2.8 work carried forward
- Pending approval is owned by its originating conversation and persisted with native tool-call identity, payload and queued tool context.
- Follow-up user messages can be queued in the owning conversation while an approval/tool cycle is pending.
- Switching away hides the approval card without silently approving or denying the action. Returning restores it.
- Background tool results return to their origin conversation.
- Project plan validation requires a meaningful 5–14 task roadmap with detailed task scope, implementation instructions, deliverables, observable acceptance, specific verification, roles/priority and valid dependencies.

### 3.2.9 changes
- `scripts/ui/ChatScreen.gd::_refresh_composer_icon()` derives Send/Stop from whether the active conversation owns the running ToolRunner. An unrelated conversation keeps Send.
- `_on_send_pressed()` cancels a project tool only when the active conversation owns it and the composer is empty. Typed text in the owning chat is queued; typed text in another chat is sent as an independent chat message.
- Composer state refreshes on text edits, session navigation and tool-state transitions.
- `_on_tool_state_changed()` does not display a background tool's activity strip in a chat that does not own the tool.
- On completion after a conversation switch, the actual result and queued messages are written back to the original session and that session is marked for resume.
- `project.godot` and `VERSION` metadata now identify 3.2.9-dev rather than stale 3.2.6 text.

## Evidence in the project

- `docs/review_3_2_9/approval_queue_720x1520.png` — pending permission with queued follow-up (presentation fixture).
- `docs/review_3_2_9/independent_chat_while_building_720x1520.png` — independent chat uses Send and remains visually quiet (presentation fixture).
- `docs/review_3_2_9/REVIEW_NOTES.md` — captures, what was actually tested, and limitations.
- `docs/e2e_ui_3_2_9.stdout` — focused phone UI flow; `UI_SUMMARY 106/106 passed`.
- `docs/unit_probe_3_2_9.stdout` — core logic probe.
- `docs/project_jobs_probe_3_2_9.stdout` — project job behavior probe.
- `docs/persistence_recovery_probe_3_2_9.stdout` — last-known-good recovery scenarios.
- `docs/e2e_scroll_xvfb_3_2_9.stdout` — GUI-backed touch drag scenarios; use the Xvfb run, not headless touch injection.
- `docs/chat_shell_behavior_probe_3_2_9.stdout` — chat header/composer behavior.

## Environment and rerun commands

Project root: `/mnt/data/aoi_3_2_8_source`  
Godot binary: `/mnt/data/godot_4_8_engine/Godot_v4.8-beta1_linux.x86_64`  
Mock provider used for UI flow: `tests_py/mock_openai_server.py` on `127.0.0.1:18100`.

Phone UI flow:

```bash
MOCK_PORT=18100 AOI_MOBILE_BASE_OPENROUTER=http://127.0.0.1:18100/v1 GODOT_SILENCE_ROOT_WARNING=1 /mnt/data/godot_4_8_engine/Godot_v4.8-beta1_linux.x86_64 --headless --path . res://tests/e2e_ui.tscn --log-file docs/e2e_ui_3_2_9.log
```

Touch/scroll (requires a GUI window):

```bash
GODOT_SILENCE_ROOT_WARNING=1 xvfb-run -a -s '-screen 0 720x1520x24' /mnt/data/godot_4_8_engine/Godot_v4.8-beta1_linux.x86_64 --path . res://tests/e2e_scroll.tscn --log-file docs/e2e_scroll_xvfb_3_2_9.log
```

## Next direction — Project Home and real Results

The screenshot audit already selected this as the next product milestone. Project detail is still a developer-oriented workbench: it foregrounds GitHub, Linux bridge setup, raw task rows and release criteria. Redesign it around:

- human-readable project name and the user's original goal;
- one primary `Continue with Aoi` action that keeps the same project and conversation;
- truthful status and a compact summary tied to persisted deliverables;
- real results/artifacts only when present, with no fake preview or Play action;
- recent outcomes in ordinary language;
- technical integrations, logs, raw task details and release controls behind a secondary Work Details surface.

Before implementing, inspect current `ProjectsScreen.gd`, `Store.gd`, project schema and all related screenshot fixtures. Preserve the underlying technical capabilities and data; change the default presentation, not the architecture by guessing.

After that redesign, re-open the new phone captures and choose the following direction from actual visual evidence. Do not return to another decorative animation pass by default.

## Known unresolved acceptance items

- Physical Android testing: IME, safe areas, gesture navigation, rotation and app background/foreground/process-kill lifecycle.
- Full durability of live provider streaming and tool execution across process death; existing persistence probes cover saved app data, not every active provider stream.
- Full playable game-generation result and real immersive landscape hand-off.
- Aggregate release certification and stable Godot release validation.

## Checkpoint/Dropbox procedure

Always write `VERSION`, `README.md`, `CHANGELOG.md`, a fresh `docs/review_<version>/REVIEW_NOTES.md`, `docs/SESSION_HANDOFF_<version>.md`, and a SHA-256 source manifest. Zip the complete project source, tests, assets and docs while excluding `.godot/`, Python bytecode and local caches. Clean-extract the ZIP, import it with Godot, rerun the focused path from the extracted copy, then upload versioned ZIP to `/Aoi`. Preserve `/Aoi/Aoi_Mobile_Current_Godot4.8beta1.zip` as `/Aoi/Aoi_Mobile_Current_pre_<version>_<YYYYMMDD>.zip` before replacing Current. Keep all previous versioned archives.
