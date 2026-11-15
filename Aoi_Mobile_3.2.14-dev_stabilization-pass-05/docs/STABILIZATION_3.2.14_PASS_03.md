# Aoi Mobile 3.2.14-dev — Stabilization Pass 03

**Date:** 2026-11-14  
**Worktree:** `Aoi_Mobile_3.2.14-dev_Godot4.8beta1`  
**Priority:** game-creation reliability and whole-app state stability. Oracle is a later optional provider, not a prerequisite.

## Changes in this pass

### Creation card and project continuity

- A chat with persisted project work no longer falls back to the generic first-run empty state. When the owning conversation has lost its explicit card message, the real saved project card is restored.
- Historical event rows alone no longer resurrect a ghost creation card. Restoration now depends on real project work state or an associated saved run.
- A stale on-device run is transitioned to `interrupted`, its last checkpoint is retained, and the existing resume path can recover it. A dead run cannot keep the card looking active indefinitely.
- The card uses the run heartbeat, rather than the less-frequent persistence timestamp, to judge freshness.
- Paused, stalled and failed copy uses the saved reason where one exists instead of hiding it behind generic status text.

### Task runner and persistence

- Progress callbacks update the in-memory job state only. They no longer bypass the runner's persistence/UI cadence by writing `job.json` and refreshing the interface on each callback.
- Checkpoint persistence is bounded to a one-second cadence; progress/UI notifications are bounded to 200 ms. Pause, cancellation, failure and completion still force a durable checkpoint.
- Job JSON and run artifacts are written through a temporary file and backup/replace sequence. A valid `.bak` is recovered if the app closes during replacement; artifact availability also recognizes a retained backup.
- Task progress detail is preserved when a step reports progress through the context callback but omits a detail string in its return value.

### Chat request ownership and model recovery

- Non-streaming fallback responses are bound to the exact chat generation that created them. A late response from a cancelled turn cannot be attached to a newer turn, even when both use the same provider.
- When a selected model returns HTTP 404 and cached alternatives are exhausted, Aoi refreshes the provider's model catalogue once and tries a newly listed eligible model. It stops with a clear recovery message when no alternative exists; it does not loop on the unavailable model.
- A missing live search key does not block project planning or implementation. Limited-research mode is explicit and does not invent current browsing or citations.

### Sheets and selectors

- Existing sheets use the expanded drag target, corrected content-height calculation and larger snap range already introduced in the preceding patch.
- Backdrop dismissal now checks whether the pointer/touch is actually outside the sheet. Bubbled touches from unused space inside the panel no longer dismiss it.
- No unrelated controls, developer-only panels or new colour treatment were added.

## Remote Linux direction

- **GitHub Codespaces** is the first remote Linux target. It is GitHub-hosted Linux, not the user's own PC or phone. The included dev container and bridge scripts prepare the project-matched Godot environment and authenticated bridge.
- **GitHub Actions** is a useful supplementary provider for temporary, on-demand Linux build/package jobs. Its standard Linux runners are free for public repositories; private-repository usage is governed by the account's included compute allowance. A runner ends with its workflow and is not a persistent interactive bridge.
- **Oracle Cloud** remains a later optional long-lived host. No part of the game-creation workflow should wait for an Oracle account.

## Work still requiring a real device/runtime

This pass is a source stabilization checkpoint, not a release-stability claim. The available work environment did not have a Godot 4.8-beta1 executable; the official release download could not be fetched from this environment. Therefore no post-change Godot render or physical Android screenshot is represented as completed.

The next highest-priority work is the full game-creation vertical slice: brief → plan → actual code/assets → remote or local Godot build → launch → playability checks → defect repair → real preview/result hand-off. Then repeat the same broad stability pass across chat, provider changes, keyboard/IME, project discovery, tools, Studio and app lifecycle on the actual Android device.
