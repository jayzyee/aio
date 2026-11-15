# Aoi Mobile 3.2.13-dev — Project Home / Results review

**Date:** 2026-11-14  
**Engine:** Godot 4.8 beta1 (`4.8.beta1.official.4d10419ca`) from the user's Library  
**Capture:** 720 × 1280 Xvfb desktop render; not physical Android

## Change selected

The agreed next direction was Project Home → real results. The default page should answer three questions quickly: what is this project, what can I inspect now, and how do I continue? Internal progress management remains available, but no longer leads the consumer-facing view.

## What changed

- A `LATEST OUTPUT` surface leads the page.
- A paired-runtime capture is rendered only when the project has a saved existing file and `preview_kind == paired_runtime_capture`; it can be opened in a dedicated review sheet.
- A job report is shown only when the latest job actually contains `report.md`; the user can open it.
- When no supported deliverable exists, the page explicitly says so and identifies the next saved workflow task where available. It does not substitute the roadmap graphic or a generated placeholder for a real output.
- **Continue with Aoi** remains the primary action.
- Work status, progress counter, recent activity, roadmap, tasks and notes remain accessible under **Work details**.
- The project status, activity and roadmap surfaces now use the card helper's padded inner body consistently.

## Visual inspection

### Project Home

![Project Home](screenshots/project_home_results_home_720x1280.png)

The result area is calm and legible, with a truthful no-preview state and a concrete next step. The large lower whitespace is intentional for a project with no actual deliverable; the page does not fill it with mock output or a task dashboard. The primary continuation action is visibly dominant.

### Work details

![Work details](screenshots/project_home_results_details_720x1280.png)

The work ledger remains available and is now clearly secondary. Card padding, roadmap and task hierarchy are easier to scan. Long work details still scroll as expected.

## Verification

| Suite | Result |
|---|---:|
| Linux bridge | 9/9 |
| Aoi Studio bridge | 10/10 |
| PC companion bootstrap | 6/6 |
| Studio editor addon | 1/1 |
| Logic | 93/93 |
| Project jobs | 21/21 |
| Provider E2E (mock server) | 25/25 |
| Phone UI | 113/113 |
| Touch scrolling | 8/8 |
| **Total individual assertions** | **286/286** |

Each suite passed when run individually. The combined `run_tests.sh` wrapper consistently stalls at the GUI phase after the headless suites; the same UI test passes independently (113/113), as does the touch test (8/8). Logs are included with the checkpoint. The environment prints a VSync warning under Xvfb and runs without physical audio hardware; it uses the dummy audio driver.

## Remaining risks

- No physical Android phone was connected. Keyboard/IME, cutout/safe-area, lifecycle, rotation, actual touch feel and device performance remain unverified.
- Provider E2E used a local mock server; no real API credentials or live provider session were exercised.
- The capture review test uses a generated test image to verify the UI path. It is not evidence that Aoi generated or verified a real game in this run.
- The separate Dropbox `Aoi_Mobile_3.2.12-dev_Godot4.8beta1.zip` was not materialised for diff/merge. This worktree is the recovered 3.2.11-dev base plus the prior 3.2.12 recovery patch and this Project Home slice. Do not replace the separate archive or `Current` with this checkpoint until reconciled.

## Next direction

Extend the results surface to handle real output types beyond `report.md` and paired-runtime captures, each with explicit validation and an appropriate viewer. Do not add artificial progress or decorative project-management content to Project Home.
