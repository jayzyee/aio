# Aoi Mobile 3.2.12-dev — Session Handoff

Start here when continuing the project. The source base is the recovered 3.2.11-dev archive. The current checkpoint is 3.2.12-dev.

## User-approved work contract

Fix evidence-backed defects in priority order. Do not broaden scope into decorative animation or feature expansion while P0 usability/state defects remain. Inspect before editing, make deliberate checkpoints, verify real behavior, capture and visually review phone screenshots, report user-visible changes rather than tool/test-count narration, and distinguish implemented/tested/unverified. Preserve the consumer Project Home, conversation-first interface, research-first planning, Aoi constellation identity, Inter typography, approval continuity and cross-chat task ownership.

## This checkpoint

- `scripts/core/LLM.gd`: HTTP 404 skips the unavailable model and advances to a catalogue-verified fallback.
- `scripts/ui/ChatScreen.gd`: terminal LLM failure persists the project error state; empty chat has no fixed 360px minimum height.
- `scripts/ui/BuildExperienceCard.gd`: error stage shows the actual actionable failure.
- `scripts/Main.gd`: avoids double-counting Android IME height when the OS already resized the app window.
- `scripts/core/Md.gd`: renders Markdown tables as vertically stacked labelled records and preserves escaped pipes.
- `scripts/core/ToolRunner.gd` + `scripts/ui/ChatScreen.gd`: add bounded Aoi-managed project search and instruct the assistant to search saved projects and personal Knowledge Library before proposing a replacement.
- `tests_py/mock_openai_server.py` and `tests/e2e_llm.gd`: regression case for 404-to-fallback.

## Next work

1. Run Godot headless logic and provider E2E tests, then the full UI test.
2. Verify Aoi-managed project search against a real saved Flappy project and test the separate paired-workspace search behavior.
3. Install/run on the physical Android phone; validate keyboard open/close, empty state, multiline composer, scroll-follow behavior, safe areas and rotation.
4. Capture fresh 720×1600 screenshots and inspect them against the recovered phone evidence.
5. Continue remaining P1/P2 defects only after the P0 workflow is verified.

## Verification caveat

No Godot executable is bundled in this working environment. Do not claim runtime or physical-device verification until those checks have actually been run.
