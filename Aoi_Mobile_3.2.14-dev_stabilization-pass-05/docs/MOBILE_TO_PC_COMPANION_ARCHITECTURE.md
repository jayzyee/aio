> **Historical architecture note (superseded for 3.2.14-dev):** This document describes the earlier paired-PC/Termux direction. The current recommended remote execution host is GitHub Codespaces cloud Linux. Use [`LINUX_GITHUB_SETUP.md`](LINUX_GITHUB_SETUP.md) for current setup and security instructions. A personal PC is not required.

# Aoi mobile now, PC environment later

## Product boundary

Aoi Mobile remains a native Godot/GDScript client. It owns the mobile chat experience, provider selection, local conversations, personal knowledge library, projects, workflow review, notifications, approval cards, and remote-session controls.

The future PC environment is a separate, optional execution host. It owns long-running jobs and capabilities that are poor fits for Android app sandboxing: a full Linux workspace, arbitrary approved command execution, larger Python environments, local model runtimes, indexing jobs, Git worktrees, desktop automation, and project build/test loops.

## Connection model

- The phone and PC communicate over a versioned JSON API, initially HTTP for request/response and WebSocket for status/events.
- The PC host advertises capabilities. The phone only shows controls supported by the connected host.
- Pairing must use a one-time code or QR handshake, then a revocable per-device token. Never expose the host API to the public internet by default.
- Local-network connections should require an explicit pairing action. Remote access should use a secure tunnel or VPN, not an unauthenticated port-forward.
- All write, execute, delete, external-message, and repository-mutation actions carry an action ID, a permission class, a human-readable preview, and an approval decision.
- The host records task ID, action ID, timestamp, working directory, command or patch summary, exit status, output digest, and cancellation state.
- The phone can pause/cancel a job, inspect logs, approve a requested action, and receive the final artifact/evidence.

## Keep the app useful without a PC

Without a connected PC, Aoi Mobile still supports cloud-model chat, local conversation storage, personal knowledge notes/search, project notes/tasks, project workflow planning/review, GitHub API operations, media generation when a provider is connected, and browser workspace launching.

Termux remains an optional mobile shell adapter. It is not the only environment and must not be treated as a secure sandbox. The PC host is the intended long-term execution environment for heavier or more complex development tasks.

## Suggested implementation order

1. Stabilise the mobile client screens and local data formats.
2. Define the mobile/host API schema and permission contract.
3. Implement pairing, host health/capability discovery, and event streaming.
4. Implement job lifecycle: queued, running, waiting_for_approval, paused, cancelled, failed, completed, needs_review.
5. Add file browsing, command previews, logs, artifact transfer and resumable sessions.
6. Add Python environments and project-specific toolchains on the PC host.
7. Add a local model adapter and indexed knowledge service as optional PC capabilities.

## Non-goals

- Do not embed a desktop operating system inside the mobile app.
- Do not automatically execute commands because an LLM requested them.
- Do not make PC connectivity a prerequisite for casual chat or the personal knowledge library.
- Do not store long-lived host credentials in project JSON or chat messages.
