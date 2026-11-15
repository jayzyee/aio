# CONTINUE HERE — Aoi Mobile 3.2.11-dev

## Source of truth
- This directory is the working source: `aoi_3_2_11_work/`.
- Version: `Aoi Mobile 3.2.11-dev`, Godot 4.8 beta1.
- The 3.2.9 source lineage is retained, including approval queueing and cross-chat tool ownership.
- 3.2.10 Project Home/Work Details implementation remains in `scripts/ui/ProjectsScreen.gd` and the two review images in `docs/review_3_2_10/`.
- Research-first workflow exists in `scripts/ui/ChatScreen.gd` and `scripts/core/AgentFlow.gd`.
- The user-supplied 10 current-phone screenshots are preserved in `docs/user_report_2026-11-14/`; see `REVIEW_NOTES.md`.

## User's current instruction
The user wants the app audited beyond the previously enumerated items. Their device screenshots show additional issues, especially keyboard/viewport behavior, text rendering and density, and stale creation activity. They want checkpoints packaged and preserved before continuing because leaving ChatGPT may reset this session. Do not assume this handoff's context will remain live.

## Confirmed next priorities
1. **Task heartbeat and provider failure reconciliation.** The creation card stays at “Imagining your game” / “Shaping the first plan” over multiple captures and does not clearly reflect the OpenRouter HTTP 404. Inspect `LLM.gd`, `ChatScreen.gd`, task state persistence and card state wiring. 404 is not a transient timeout; check catalogue/selected-model identity and configured fallbacks before asking the user to select another model. Ensure every terminal failure moves the activity card out of active/animated state.
2. **Android keyboard and viewport.** Real screenshots show keyboard open while the chat empty state remains centered in the original full-height region. Inspect `Main.gd` layout, viewport/window resize mode, chat VBox/ScrollContainer/composer sizing, IME resize/pan behavior, safe area, focus, and bottom-follow rules. Keep composer visible and preserve scroll unless the user was already following the bottom.
3. **Markdown tables and typography.** `scripts/core/Md.gd` does not support tables, matching the raw `| Model | Why it fits |` screenshot. Add a bounded table renderer or intentionally transform tables to readable labelled rows. Review line length, paragraph rhythm, header overlap, code blocks, lists and inline links.
4. **Project/library discovery.** User requested to continue from existing Flappy project; Aoi prematurely says no existing project is in Knowledge Library and offers a new workspace. Inspect all supported local/library/project search capabilities, and communicate exact scope/limitations.
5. **Research-first workflow.** Preserve the existing research step as mandatory before substantial new projects; never make it a fake blocker if web search is not connected. If required research tools are unavailable, explain this accurately and do not create a false research completion.
6. Run a full app review to find other issues, then choose one more product direction only after P0 phone usability is repaired.

## Critical code locations
- `scripts/ui/ChatScreen.gd`: keyboard-aware scroll, composer, activity strip, research/tool flow, project start and activity reconciliation.
- `scripts/core/LLM.gd`: HTTP status, error classification, retries and model fallback.
- `scripts/core/Md.gd`: Markdown → BBCode; currently lacks table support.
- `scripts/core/AgentFlow.gd`: research and roadmap validation.
- `scripts/ui/BuildExperienceCard.gd`, `AoiPresence.gd`, `AoiProgressRail.gd`: activity card, vector status and progress.
- `scripts/Main.gd`: screen layout, viewport and system UI insets.
- `scripts/ui/ProjectsScreen.gd`: consumer Project Home and advanced Work Details.

## What was intentionally not done yet
- The issues above were documented, not falsely claimed fixed.
- The new real-phone screenshots are evidence, not test fixtures.
- Physical Android IME behavior has not been verified by an automated desktop-render test.
- A passing headless suite must not be used as proof of Android usability.

## Packaging rule
At every meaningful milestone: update `VERSION`, `CHANGELOG.md`, this handoff, include fresh screenshots and review notes, create a versioned ZIP, clean-extract and verify it, upload the versioned ZIP to `/Aoi`, preserve the old Dropbox Current under a dated backup name, then copy the new version to `/Aoi/Aoi_Mobile_Current_Godot4.8beta1.zip`. Never remove historical archives or replace Current before the versioned upload is confirmed.

## User-facing progress style
Report user-visible features and behavior, not test counts. Be direct about what is implemented, what remains, and what evidence supports claims.
