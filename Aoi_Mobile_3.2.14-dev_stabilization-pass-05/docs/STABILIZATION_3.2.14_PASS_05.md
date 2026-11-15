# Aoi Mobile 3.2.14-dev — stabilization pass 05

**Date:** 14 November 2026  
**Base:** Pass 04, Godot 4.8 beta 1  
**Focus:** GitHub cloud Linux setup, chat ownership, broad phone UI review, and project-state truthfulness.

## User-facing changes

- Clarified that the Linux build machine is hosted by GitHub Codespaces. It is not a personal PC, phone, or Termux connection.
- Shortened the GitHub token and cloud workspace instructions while preserving the exact repository permissions, secret name, and free-usage cautions needed for setup.
- Kept the GitHub and Codespaces workflow inside Aoi's existing Connections sheet. No new developer dashboard, unrelated accent colours, or extra top-level controls were added.
- Kept the model selector compact and draggable; long connection sheets remain scrollable and can be moved using the existing sheet header.
- Prevented streamed text and status notices from being delivered to another ChatScreen just because it displays the same conversation ID. Only the screen that owns the active request receives its deltas, notices, and final response.
- Released request ownership on completion, so an old request identifier cannot claim a later response.
- Kept late completed responses attached to their original saved conversation when the user navigates away. Structured tool/planner output is resumed in that original conversation rather than executed against the newly visible chat.
- Removed a temporary diagnostic print from the UI review fixture.
- Corrected the Workbench review fixture so its project summary matches its arcade-game project brief.

## GitHub Codespaces implementation

- GitHub PAT verification remains tied to the account endpoint; a bad replacement token does not overwrite a previously verified credential.
- Aoi lists the account's existing Codespaces, creates a workspace from the selected repository and branch, refreshes uncertain create outcomes, selects an existing workspace, and opens the selected workspace in GitHub.
- Before creation, Aoi requests repository-eligible Linux machine types and selects the smallest available machine by CPU count, then memory and storage.
- The create/start operations are mutations and are never blindly retried. A lost create response blocks a second create until a complete refresh resolves whether GitHub already provisioned the workspace.
- The saved GitHub token is snapshotted across machine lookup and provisioning. A token/account change aborts the operation before it can silently continue under a different account.
- The cloud bridge requires the separate 64-character `AOI_BRIDGE_TOKEN` secret. Project code runs under the dedicated `aoi-runner` identity with a clean environment; it does not inherit the bridge or GitHub credentials.
- The Codespace dev container installs the project-matched Godot 4.8 beta 1 Linux binary from the official release and checks its SHA-256 before use.
- A successful GitHub API response is not treated as a connected Linux machine. Aoi still requires the forwarded bridge health check, the expected isolated execution identity, and a detected Godot runtime before remote project tools become available.
- Oracle remains optional and deferred. GitHub Codespaces is the first remote Linux route; GitHub Actions is an ephemeral job runner rather than a persistent interactive bridge.

## Runtime and visual review

The Library copy of `Godot_v4.8-beta1_linux.x86_64.zip` was used for the review. The app imported and opened under that exact pinned engine. Fresh 720 × 1520 captures are stored in `docs/review_3_2_14/final_pass/`:

- `chat_720x1520.png` — first-run chat and anchored composer.
- `projects_720x1520.png` — project home with no fabricated playable result.
- `workflow_720x1520.png` — project-scoped Workbench and game-aligned workflow brief.
- `creation_card_720x1520.png` — compact plan-derived creation card and signal-field treatment.
- `model_selector_720x1520.png` — compact, draggable model sheet.
- `github_connection_720x1520.png` — GitHub account/token setup and scoped permissions.
- `linux_connection_720x1520.png` — GitHub-hosted Linux workspace setup and existing Codespace selection.

The bridge and Studio bridge flows, the PC companion bootstrap, Godot editor add-on load, task persistence, provider response handling, phone UI, and touch scrolling were exercised in this environment. The fresh captures were visually inspected after the copy/layout changes.

## Not claimed as complete

- A real Codespace was not provisioned in this session because no user GitHub token/repository was connected. The account-specific API flow is implemented, but the user's first live provisioning and bridge handshake remain to be performed after connection.
- Physical Android hardware acceptance has not been performed. Desktop Godot captures do not establish actual Android IME, rotation, background/foreground, memory-pressure, or device-specific touch behavior.
- Aoi's game creation is not declared fully stable merely because a task card renders or a project opens. A real request still needs a full build, launch, playability pass, repair loop, fresh runtime capture, and final review on the connected Codespace.

These limits are deliberate release gates, not reasons to show a false success state.
