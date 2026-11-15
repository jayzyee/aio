## 3.2.14-dev — Codespaces execution isolation and process recovery

- Separated cloud bridge and project execution identities; project code receives no bridge/GitHub credentials.
- Added bounded process-group termination for timed-out command and test jobs.

# Changelog

## 3.2.14-dev — Stabilization Pass 05 (2026-11-14)

- Bind streamed chat deltas, notices and completion events to the active request owner; prevent a second ChatScreen from consuming another screen's shared LLM signal.
- Preserve late results in the originating saved conversation and release request ownership when the response completes.
- Clarify and shorten GitHub Codespaces setup copy while keeping exact token scopes, the separate bridge secret, and free-usage cautions.
- Preserve Aoi's existing monochrome Connections sheet rather than introducing new controls or a developer dashboard.
- Capture and review fresh 720 × 1520 chat, project home, Workbench, creation card, model selector, GitHub and cloud Linux screens under the Library-provided Godot 4.8 beta 1 build.
- Keep live Codespaces provisioning and physical Android acceptance explicitly open until a real GitHub account and target device are connected.

## 3.2.14-dev — Stabilization Pass 04 (2026-11-14)

- Add GitHub Codespaces list, create, select and open flows to the existing cloud connection sheet.
- Inspect repository-eligible Linux machine types before creation and select the smallest available option by CPU, memory and storage.
- Require the fine-grained token's Codespaces metadata read permission for machine discovery, plus Codespaces read/write for provisioning.
- Preserve the GitHub credential snapshot across machine lookup and provisioning; stop if the active account changes mid-request.
- Treat a lost Codespaces creation response as an ambiguous paid-resource operation and block another create until a list refresh confirms the server state.
- Restrict automatic HTTP retries to safe GET/HEAD requests; do not repeat remote mutations after a timeout.
- Avoid identical safe-area relayouts every frame and refit the multiline composer when its viewport width changes.
- Update cloud setup documentation with the actual in-app Codespaces workflow, free-tier quotas, cost behavior and recovery steps.
- Defer Oracle Cloud; GitHub Codespaces remains the first remote Linux path and is sufficient for the intended workflow when configured.


## 3.2.14-dev — Stabilization Pass 03 (2026-11-14)

- Reconcile restored project cards with actual saved work and prevent historical events from reviving ghost activity.
- Detect dead on-device task runs and preserve resumable checkpoints.
- Throttle task checkpoint and UI persistence; make job/artifact replacement recoverable.
- Bind non-streaming model responses to their originating chat generation and refresh model catalogues after HTTP 404.
- Prevent bubbled inside-sheet touches from dismissing the sheet.
- Keep GitHub Codespaces as the first remote Linux route; defer Oracle as an optional later host.

## 3.2.14-dev — cloud runtime and conversation stabilization pass

**Date:** 14 November 2026

- Reworked mobile sheets with a correctly sized scroll viewport, generous drag target, draggable header and expanded snap state.
- Added a GitHub Codespaces cloud Linux environment with a pinned, checksum-verified Godot 4.8-beta1 runtime, virtual display and authenticated bridge.
- Corrected GitHub token verification so Aoi stores a replacement only after the account endpoint confirms it; retained public repository reads without a token.
- Removed the unconditional Brave Search gate when no live-search credential is configured. Build chats now continue in an explicit limited-research mode without fabricated current sources.
- Stabilized build-card ownership, truthful game readiness, cross-chat tool-result persistence and interrupted-turn resumption.
- Fixed a game-card lifecycle defect: stopping a game after a successful live capture no longer makes a completed card regress to building; any later source write invalidates the old runtime proof and requires a fresh run/capture.
- Hardened cloud bridge startup/restart, project-title/path validation, Godot stop handling and live-capture requirements.
- Made remote Godot project creation idempotent and atomic, so retries reconnect to a valid existing project rather than failing on their own folder or leaving partial projects behind.
- Corrected the pinned Godot prerelease version comparison and project-relative cloud terminal scope.
- Preserved late chat replies in their owning conversation and resumed structured work there instead of losing it or applying it to the currently open chat.
- Updated current setup guidance to identify Codespaces as the recommended cloud host and GitHub Actions as an ephemeral job runner, not a persistent bridge.
- Preserved the existing monochrome visual language; no developer-only buttons or unrelated accent colours were added.

### Visual system reset
- Unified the app around a neutral monochrome visual language; removed decorative blue/violet/teal treatments from Aoi identity and progress visuals.
- Flattened shared content groups and removed decorative shadows, repeated card borders and over-rounded controls.
- Standardized button, input, sheet and popup-menu geometry.
- Removed duplicate overflow navigation on secondary screens and clarified Connections/Settings destinations.
- Rewrote first-run and project-empty copy in direct, ordinary language.
- Added white vector icon assets for primary dark actions and refined the orbital identity animation.

## 3.2.13-dev — 2026-11-14

- Reworked Project Home around the latest real output rather than roadmap status. A saved runtime capture or run report is displayed only when the persisted artifact exists; no preview or completion is fabricated.
- Added a deliberate no-output state that distinguishes the saved project goal/context from a reviewable deliverable and surfaces the next saved task when available.
- Kept **Continue with Aoi** as the primary action and moved work status, progress counters, recent activity, roadmap, task checklist and notes into **Work details**.
- Added a full review sheet for saved connected-runtime game captures.
- Corrected Project Home card composition to use the shared padded card body, fixing headings and content that previously sat flush against card edges.
- Added UI regressions for no-output honesty, progress-management separation, real saved-capture display and capture-sheet opening.
- Updated touch-scroll coverage to exercise the intentionally scrollable Work details view; a compact no-output Project Home is not expected to scroll when its content does not overflow.
- Visual review captures: `docs/review_3_2_13/screenshots/project_home_results_home_720x1280.png` and `project_home_results_details_720x1280.png`.
- Validation: bridge 9/9, Studio bridge 10/10, PC bootstrap 6/6, editor addon 1/1, logic 93/93, project jobs 21/21, provider E2E 25/25, phone UI 113/113, touch scrolling 8/8. Suites were run individually; the combined `run_tests.sh` wrapper still stalls at its GUI phase in this environment.
- Still unverified: physical Android acceptance, real provider session, and reconciliation against the separate Dropbox 3.2.12-dev archive.

## 3.2.12-dev — 2026-11-14

- Treat provider/model HTTP 404 as a non-transient model-route failure. Skip the unavailable model immediately and try the next model already verified in the provider catalogue; do not burn retries on the same dead route.
- When no verified fallback exists, return an actionable error directing the user to refresh the model list or choose another model.
- Persist failed creation requests as terminal `error` project work state immediately, instead of emitting an unhandled stage signal and leaving the card on `planning`.
- Show the actual actionable failure on the creation card.
- Detect Android IME window-resize mode and avoid applying the keyboard height as a second bottom inset. Overlay-mode IMEs continue to reserve the keyboard height.
- Remove the fixed 360 logical-pixel minimum from the empty-chat center so short keyboard-visible viewports can allocate space to the anchored composer.
- Add an end-to-end mock-provider regression case for HTTP 404 followed by a verified fallback.
- Render GitHub-style Markdown tables as phone-friendly vertically stacked labelled records, including escaped pipe characters.
- Add `workspace.search_projects` for searching Aoi-managed local project records. Creation guidance now requires searching existing Aoi projects and the personal Knowledge Library before claiming a project is missing or creating a replacement; the tool explicitly states its search boundaries.

## Historical changes

See the previous entries in the archived 3.2.11-dev source lineage and the review notes under `docs/`.
