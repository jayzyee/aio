# Aoi Mobile 3.2.1-dev — Working checkpoint

**Engine:** Godot 4.8 beta1 (Library-provided Linux editor/runtime)  
**Source of truth:** this project tree (`aoi_work`)  
**Status:** development checkpoint, not a release claim

## Product contract

Aoi is a general-purpose, conversation-first AI workspace. Users should describe an outcome in natural language and receive a finished result without having to understand tools, engines, terminals or developer workflows. Projects, runs, files, activity and previews are presented as contextual objects inside the conversation. Global preferences/references are reusable; project context remains isolated.

Visual target is the supplied ChatGPT mobile screenshots: full-screen conversation, system-safe top/bottom spacing, two floating control pills, a thick floating composer, black/white/neutral surfaces and one controlled accent. Type, icons, spacing and touch targets must scale against actual phone screenshots. Do not copy ChatGPT branding.

## Current working implementation

- Full-screen chat shell with floating menu and right-side action pill; composer is thick and inset.
- Animated Aoi presence for idle/working states.
- Activity item maps real tool/job state events to concise user-facing copy and can expand to show recent steps.
- Approval UI is compact and separates a human-readable decision from expandable technical details.
- New project creation can be initiated from normal Chat and binds the created project to the conversation.
- Project intent is represented independently from the detected runtime.
- Inline creation card has responsive captures at 720×1520 and 390×844.
- Global working standards and workspace vision are included as reusable global context; project notes/data remain project scoped.
- Explore now uses a compact directory and integration detail sheets; Projects uses a list/detail/edit pattern rather than permanent form panels.

## Latest runtime evidence

- `docs/review_3_2_8/chat_baseline_720x1520.png` — Godot 4.8 beta1 runtime capture at 720×1520.
- `docs/review_3_2_6/chat_project_card_kindfix.png` — chat-created project card at 720×1520.
- `docs/review_3_2_6/chat_project_card_390.png` — same card at 390×844.
- `docs/review_3_2_6/activity_timeline_720.png` — compact activity presentation.
- `docs/review_3_2_6/approval_compact_720.png` — compact approval decision surface.
- `docs/review_3_2_7/final_import.log` — Godot editor import; no GDScript parse errors.

## Known blockers / next direction

1. The chat-created project is local, but the end-to-end companion path is not finished: provision a remote project, sync safely, run the actual project, inspect logs, capture a preview and return it as a real artifact.
2. Inline project card currently has an Open project handoff; Run/Inspect/Immerse and actual thumbnail/game-window preview must be integrated with truthful runtime state.
3. Background job state must persist independently of the open chat screen and recover across app pause/restart.
4. Tool activity must be driven only by actual events, never simulated narration; approval requests must remain visible/reachable and never wait invisibly.
5. Complete five-turn temporal provider test, including retry/error recovery and clean final assistant response; then repeat with a real provider.
6. Validate with fresh 720×1520 and 390×844 captures, plus landscape runtime capture; compare manually with supplied screenshots.
7. Physical Android 8.1 test remains mandatory for keyboard resize, safe areas, app lifecycle, touch, scroll and memory pressure.

## Validation boundary

Godot 4.8 beta1 is installed from the user's Library and runs in this environment. The latest editor import was executed successfully and the 720×1520 review-capture scene rendered. This does not establish physical Android stability or a completed playable game workflow. No fake preview/runtime status should be shown.
