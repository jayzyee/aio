# Aoi Mobile 3.2.13-dev — Session Handoff

## Current direction

Continue the approved outcome-first Project Home / Results milestone. Keep the default project screen focused on the user's goal, a truthful real-output surface and **Continue with Aoi**. Keep progress internals, roadmaps, task controls and event history in **Work details**. Never show a fake preview, inferred completion or percentage unsupported by persisted state.

## Implemented in this checkpoint

- `scripts/ui/ProjectsScreen.gd`: latest output appears before the action row. A connected-runtime capture is shown only if its path exists and its `preview_kind` is the supported capture type; tapping **View game capture** opens a review sheet. A job report is shown only if `report.md` exists and opens through the report viewer.
- No-output state explains that the project goal/context are saved but no reviewable output is attached; it shows the next saved workflow task if one exists.
- Status, activity, progress bar/counter, roadmap, tasks and notes are displayed under Work details.
- Project status, activity and roadmap cards now use `Ui.card_body()` rather than adding an overlapping second child to the `PanelContainer`.
- `tests/e2e_ui.gd`: validates no-output home, hidden progress-management detail, actual saved image capture rendering, and opening the capture review sheet.
- `tests/e2e_scroll.gd`: tests scroll behavior on Work details; a short Project Home is deliberately allowed not to scroll.

## Evidence and test results

- UI: 113/113.
- Touch scroll: 8/8.
- Logic: 93/93.
- Project jobs: 21/21.
- Provider E2E with mock server: 25/25.
- Linux bridge: 9/9.
- Aoi Studio bridge: 10/10.
- PC companion bootstrap: 6/6.
- Studio editor addon: 1/1.
- Total: 286 individual assertions across separately run suites. `run_tests.sh` still stalls at its GUI stage when run as one combined command, although the UI and touch suites pass when run separately.

## Known limitations / next steps

1. Reconcile the separate Dropbox `Aoi_Mobile_3.2.12-dev_Godot4.8beta1.zip` before replacing the main `Current` archive. This worktree is based on the recovered 3.2.11-dev source plus the 3.2.12 recovery patch; it is not yet merged against that separate archive.
2. Test with an actual provider account and verify real generated project outputs, not only the preview fixture and mock-provider tests.
3. Install on the target Android phone; validate keyboard, safe areas, lifecycle, scrolling and landscape handoff physically.
4. Next product slice should strengthen artifact/result coverage beyond the currently supported report and paired-runtime capture, without inventing previews for other output types.

The screenshots are Xvfb desktop renders at 720 × 1280, not physical Android evidence. Do not describe this checkpoint as production-ready.
