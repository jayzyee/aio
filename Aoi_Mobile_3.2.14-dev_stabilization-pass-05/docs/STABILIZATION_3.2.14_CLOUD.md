# Aoi Mobile 3.2.14-dev — stabilization handoff

**Work focus:** preserve the 3.2.14 monochrome interface while correcting broken user journeys across chat, project creation and remote Godot execution.

## User-facing changes

### Sheets and selectors

- Increased usable sheet height and corrected the scroll viewport calculation so long model and connection forms stay inside the visible sheet.
- Made the existing grip and header area draggable, with an expanded snap state and a predictable downward close gesture.
- Kept the current neutral palette, icon language and action hierarchy. No developer-only controls or unrelated coloured panels were introduced.

### Chat and project continuity

- Bound each model stream to the conversation and project that started it. Late callbacks cannot update another open chat.
- Persist successful replies to their original conversation when the user switches chats mid-response.
- Resume structured responses in their originating conversation rather than applying them to whichever conversation is currently open.
- Preserve tool results and generated media in the originating conversation; attach projects created after a chat switch to that chat so the project card is not lost.
- Restore pending work on return to the owning chat and clear stale project activity when a session is left.

### Creation experience

- The card follows the newest project run instead of letting an older failed run overwrite a newer result.
- Project activity is project-scoped, not inferred from an unrelated chat or global busy flag.
- A terminal failed run is shown as needing attention instead of appearing to build forever; saved work remains available and a continuation path is shown.
- A game is not marked ready from a folder, scaffold, tool call or screenshot alone. The plan, live runtime and actual capture must all exist.
- Runtime verification is now recorded against the successful paired-runtime capture rather than the process remaining alive forever. Stopping a game after capture does not regress its card; a subsequent source write invalidates that proof and requires a new run/capture.
- A live capture remains reviewable while the project is being checked, without pretending that the game is complete.

### GitHub and research

- GitHub token replacement is verified against the account endpoint before it is saved. An invalid replacement does not overwrite a previously valid credential.
- Public repository browsing remains available without a personal access token; private repository access and remote writes require the appropriate verified credential and permissions.
- Aoi can list existing GitHub Codespaces, create a Codespace from a selected repository/branch, restore an interrupted create through a list refresh, select an existing workspace and open it in GitHub.
- Before provisioning, Aoi reads repository-eligible machine options and selects the smallest available Linux option by CPU count, then memory and storage. This requires **Codespaces metadata: Read** plus **Codespaces: Read and write** on the selected repository.
- A lost Codespaces create response is treated as uncertain, not as a normal failure. Aoi blocks another create until a successful list refresh resolves the possibility that GitHub already provisioned the machine.
- A missing Brave Search key no longer blocks a game or project build. Aoi explicitly enters limited-research mode, uses the brief and saved project context, and does not claim current web research or fabricate citations.

### Cloud Linux runtime

- GitHub Codespaces is the recommended remote Linux host. The user's phone remains the Aoi interface; a personal PC or Termux session is not required.
- The included dev container installs the project-matched Godot 4.8 beta 1 Linux binary, verifies its official SHA-256, creates a virtual display and starts the authenticated bridge.
- Cloud project creation is idempotent: reconnecting to an existing Aoi project returns its existing folder; creating it is staged and committed atomically to avoid leaving partial folders after a failed request.
- Godot launch now checks that the process survives its startup handshake before returning a running state. Stop and capture paths clear dead process records and captures require a live process.
- Cloud connection keys must be 64 hexadecimal characters. The public forwarded endpoint is authenticated. The bridge runs as `vscode` while project code and Godot run as a separate low-privilege `aoi-runner` account without the bridge/GitHub credential environment. This is defense in depth, not a complete OS/container sandbox.
- Project-scoped terminal actions accept the Codespaces-relative project path, while paths outside the project still require additional approval.

## Remote Linux provider choice

- **GitHub Codespaces:** preferred for an interactive Linux workspace and Godot desktop. It has a monthly compute/storage allowance and is not an always-on server.
- **GitHub Actions:** suitable for temporary build/test/package jobs. A hosted runner is discarded after its job and cannot act as the persistent interactive bridge.
- **Oracle Cloud Always Free:** a possible longer-lived VM alternative, but it needs separate setup and capacity can be unavailable in the selected region.

See [`LINUX_GITHUB_SETUP.md`](LINUX_GITHUB_SETUP.md) for the first-time setup and current provider limits.

## Stabilization pass 04

- Query GitHub's repository machine-types endpoint before provisioning and choose the smallest eligible Linux machine instead of assuming a fixed two-core default.
- Require the additional `Codespaces metadata: Read` permission and give an actionable explanation when GitHub rejects the machine lookup.
- Bind machine lookup and Codespaces provisioning to the same verified PAT snapshot so a credential change cannot switch the account midway through a create request.
- Persist ambiguous Codespaces create outcomes and require a successful list refresh before another create, preventing blind duplicate billable resources.
- Limit automatic HTTP retries to read-only GET/HEAD requests. Mutations such as creating a Codespace, writing files, creating branches or launching a process are not automatically repeated after a timeout.
- Separate the credential-bearing bridge from the project execution identity in Codespaces; project shells and Godot inherit neither the Aoi bridge key nor GitHub CLI credential variables.
- Run shell commands and headless project checks in bounded process groups, terminating their child processes on timeout rather than leaving orphaned build processes.
- Preserve the existing Aoi UI system; the Codespaces workflow reuses the existing cloud-connection sheet rather than introducing a separate developer dashboard.
- Apply the mobile safe-area/keyboard margins only when the effective insets change instead of forcing an identical container relayout every frame.
- Refit the existing multiline composer after width/viewport changes, not only after text edits.
- Refresh the Linux setup guide to describe the in-app create/select workflow, token permissions, smallest-machine selection, quota behavior and recovery steps.

## Current acceptance boundary

The exact Godot 4.8 beta 1 Linux binary from the user's Library has now been used to import and open the project. Fresh 720 × 1520 captures were produced and inspected for chat, project home, Workbench, creation card, model selector, GitHub connection and cloud Linux connection. The current review and images are in `docs/review_3_2_14/FINAL_REVIEW.md` and `docs/review_3_2_14/final_pass/`.

The app-side GitHub/Codespaces API flow and cloud bridge are implemented, but no user GitHub PAT/repository was connected during this session. Therefore no real Codespace was provisioned, no user's quota was consumed, and the live account-specific bridge handshake remains unverified. Physical Android acceptance also remains outstanding; a desktop capture cannot prove device IME, rotation, lifecycle, memory-pressure or hardware touch behavior.

A game request is not considered complete until it has been implemented in the connected runtime, launched, played through the requested experience, inspected with fresh captures, repaired where needed, and handed back as a real runnable result. The creation card, workspace scaffold, a successful tool call or a static image alone do not meet that acceptance gate.

For the exact changes in the current source pass, see `STABILIZATION_3.2.14_PASS_05.md`.
