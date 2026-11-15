# Aoi 3.2 — product direction and implementation contract

> **Historical architecture baseline:** its paired-PC / Termux Linux-device proposal has been superseded in 3.2.14-dev by the remote GitHub Codespaces cloud workspace. Use [`LINUX_GITHUB_SETUP.md`](LINUX_GITHUB_SETUP.md) for the current connection model.

**Status:** active redesign specification, not a release claim  
**Baseline:** Aoi 3.1.0-dev ProjectAgnostic (Godot 4.8 beta1)

## Product definition

Aoi is a general-purpose AI chat with a capable project workspace behind it. It is not a project-management dashboard that happens to contain a chat screen. The default interaction is ordinary conversation. The user can discuss an idea, ask a question, request an implementation, inspect the result, and continue the same conversation without manually orchestrating a workflow.

Project context is optional and contextual. Aoi must not force every chat into a project or force every project into Godot. Global preferences, references and ambitions are reusable workspace context; project-specific code, sources, instructions, run history and artifacts remain isolated to that project.

## Visual direction

- Reference quality: restrained, readable ChatGPT-style mobile conversation, not a copy of its branding.
- Default palette: black, white and neutral greys. One configurable accent is reserved for selection/focus and a small number of semantic states. Do not use multiple decorative accent colours.
- Typography: consistent text scale, line height, readable paragraph measure and predictable heading hierarchy. Avoid oversized body text, dense debug text, and arbitrary size jumps between components.
- Layout: stable spacing tokens, consistent touch targets, safe-area and keyboard-aware composer, content-first scrolling, and minimal persistent chrome.
- Navigation: Chat is the primary home. Keep only essential destinations persistent. Projects and Library are secondary destinations; Workbench and integrations are contextual tools, not competing primary tabs. Chat history search matches conversation titles and visible user/assistant messages while excluding internal tool records. Users can rename conversations, pin important chats, and copy a readable transcript containing only visible chat messages; pinned chats are marked in the navigation drawer and stay above recent chats without changing their activity timestamp.
- Surfaces: use cards only when they represent a real object or action. Avoid wrapping every section in a card. Keep messages and tool activity visually quiet.
- Empty chats offer a few mode-specific starter prompts that fill the composer without sending or spending provider credits; provider setup remains explicit and unsent drafts survive the redirect.
- Ordinary chat requests show a restrained animated Aoi presence while waiting for the first response content. The status changes to preparing an action only when streamed content identifies a tool call, then yields to the actual answer. It must not imply access to hidden chain-of-thought or invent work.
- Builder conversations inspect the active project's actual files and available runtimes, choose the supported toolchain rather than assuming a phone-only Godot workflow, and prioritize complete, runnable, verified outcomes over toy stubs. Report partial work and blockers plainly.
- The first-run empty state pairs the Aoi constellation mark with a clear Aoi wordmark; keep identity recognizable without repeating decorative branding throughout the conversation.
- Voice interaction is turn-based and user initiated: keyboard dictation supplies input, and an explicit per-message action uses the device's speech synthesis. Aoi does not keep the microphone open or upload raw audio.
- Connections prioritize tools that work inside Aoi. Browser destinations stay searchable but are collapsed by default so they do not overwhelm the native setup options.

## Conversation-first project experience

When a user says “make a small game”, Aoi should remain in the conversation and work in the background. The chat should show one compact, evolving work item rather than dumping a checklist or a wall of tool logs:

1. Preparing — understand the request and inspect available project/runtime context.
2. Planning — form a short internal implementation plan; expose it only when it helps the user.
3. Building — show the current meaningful action, not raw tool payloads.
4. Checking — run relevant project checks and inspect actual logs/output.
5. Ready — render an inline project artifact card with preview, concise result, and actions such as **Open project**, **Run**, **Inspect**, and **Continue in chat**.

The card is an entry point to a dedicated project/runtime view. Run should open an immersive game-oriented runtime surface with orientation/full-screen support and a small, dismissible helper overlay. Returning to chat must preserve conversation and project state.

## Autonomous work and approval boundaries

A user request to implement something is authorization to work inside the active project workspace. Do not ask for approval for every ordinary file write. Aoi should keep working when the user leaves and return a coherent completed result.

Default policy: **Workspace autonomy**.

Allowed without per-action prompts inside the active, explicitly selected project:
- Read/list/search project files.
- Create and update project-scoped source/config/docs/assets.
- Maintain a durable task plan, checkpoints and run artifacts.
- Run the selected project's configured, bounded verification/build/test actions when the connected runtime is paired to that exact project.
- Capture screenshots and read logs from that project's runtime.
- Retry transient failures up to three attempts with bounded backoff; preserve state between attempts and turns.

Require a visible review before:
- Accessing or modifying files outside the selected project root.
- Arbitrary shell commands, package installation, executable downloads, privilege escalation, or changes to system configuration.
- GitHub writes, branch/PR/issue creation, publishing/deployment, or other remote side effects.
- Credential access, secret export, network destinations outside configured allowlists, or sharing private data.
- Deleting data, overwriting unrelated files, changing permissions, or disabling safeguards.
- Executing project-declared scripts that run as trusted code inside Aoi without OS-level isolation.

Aoi must explain the exact boundary it hit, keep the job resumable, and never display an approval request without a visible, reachable approval surface. The app must not leave the model waiting on an invisible approval state.

## Job lifecycle and resilience

Long-running work is a persisted job, not a fragile chain of one chat turn. Each job stores:
- Job ID, originating conversation, project ID and scope.
- User goal, acceptance criteria and concise plan.
- Current stage and meaningful user-facing status.
- Checkpoint, files changed, tool events, test output and screenshots.
- Retry count, last error, next retry decision and cancellation state.

Transient provider/network/tool errors: retry at most three times with bounded exponential backoff. Never retry permission denials, unsafe actions, invalid input or deterministic build errors without changing the approach. On the third failed attempt, stop retrying, summarize the concrete blocker and preserve a resumable checkpoint. Never tell the user “passed” without real output.

A job may continue when the user leaves chat. Returning to the conversation must restore its current state. The app must not require the user to keep the chat screen open or approve routine workspace edits.

Workflow tasks are bound to their exact persisted conversation. Only a complete response from that task's own conversation may move it into human review; partial, stopped or failed responses return the task to a retryable state with the issue and prior conversation preserved. Task cards show a concise preview of the returned result, keep acceptance criteria visible, and provide a direct route to the full conversation and evidence. A requested revision clears the prior preview. If no provider is connected, starting a task must leave it runnable rather than creating a misleading active state.

## Tool activity presentation

- One compact activity row attached to the relevant assistant turn.
- Show meaningful labels such as “Reading project files”, “Updating Player.gd”, “Running Godot import”, “Capturing preview”, and “Retrying connection”.
- Expand on tap to show tool name, scope, duration, concise inputs/outputs and errors. Do not expose raw JSON as the default view.
- Every visible status must correspond to an actual emitted tool/job event. No invented activity narration.
- Keep completed history collapsed by default. Surface only the latest meaningful action while work is active.
- Approval cards are exceptional and pinned/visible, with a concise human-readable summary and file diff/command preview.

## Runtime and Linux device architecture

Aoi Mobile is the control surface. A paired Linux companion is the execution device. Pairing must be explicit and visible (device name, OS, connection state, last heartbeat, project roots and supported capabilities). The companion runs on the user's own Linux PC or Termux environment; it is not an implicit cloud computer and cannot be assumed online.

The bridge must use authenticated requests, loopback/LAN binding by default, bounded payloads/timeouts, workspace-root path validation, and capability negotiation. Shell access is a higher-risk capability than file operations. The existing bridge is not a hardened OS sandbox: shell commands run with the account's permissions. Never describe it as isolated.

## GitHub integration

Short-term compatibility: fine-grained personal access token (PAT), limited to explicitly selected repositories and only the permissions required. Repository inspection starts with Metadata read + Contents read. File commits require Contents write. Issue and pull-request operations add their own permissions only when used.

Long-term product path: a GitHub App using OAuth Device Flow, with short-lived user tokens and repository selection. This avoids asking the user to paste a long-lived credential into the app. The current PAT-based connector must not be described as Device Flow.

GitHub changes remain review-gated and branch-scoped until a robust diff/review workflow exists. Aoi should create a topic branch, show the diff, then commit/push only after the user explicitly enables the remote-write capability.

## Required end-to-end acceptance scenario

Use a deterministic local OpenAI-compatible test provider (the existing mock server is the starting point) and then repeat against a real provider:

1. Run at least five sequential assistant response turns with mixed normal text, tool activity, tool results, one recoverable error, one retry and a final clean response.
2. Confirm tool status rows match actual requests and never show fabricated tools.
3. Confirm a project-scoped write proceeds without a per-file approval in Workspace autonomy.
4. Confirm arbitrary shell, GitHub mutation and out-of-project write remain review-gated.
5. Ask for a small playable game. Aoi should inspect the project, implement it, run the selected runtime, capture a screenshot, inspect the result and iterate on visible defects.
6. The final game result must appear inline in chat as a project artifact card. Open it, run it in the immersive runtime view, return to chat, ask for a change, and verify the same project/job context continues.
7. Force a provider interruption and an execution error. Verify up to three transient retries, durable checkpoints, no invisible approval state, no duplicate writes, and a clear final blocker only after retry exhaustion.

## Release gates

- Real Godot runtime captures at phone-sized portrait and landscape viewports.
- Physical Android 8.1 test for keyboard resize, safe areas, lifecycle resume, scrolling, touch targets and memory pressure.
- Provider integration test against at least one real OpenAI-compatible endpoint.
- Five-turn tool workflow and playable-game end-to-end scenario above.
- App startup, import, logs, export and install verified on the actual target device.
- Dropbox and Library each contain one clearly named current build, with prior build revisions replaced rather than accumulated as separate files.
