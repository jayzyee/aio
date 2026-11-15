# Aoi Mobile — Session Handoff / Continue Here

**Checkpoint:** Aoi Mobile 3.2.8-dev  
**Engine:** Godot 4.8 beta1  
**Created:** 2026-11-14  
**Purpose:** Restore the exact project context if the ChatGPT mobile app reloads or this working session is lost.

## First action after resuming

1. Locate and open `Aoi_Mobile_Current_Godot4.8beta1.zip` in Dropbox, or use the versioned `Aoi_Mobile_3.2.8-dev_Godot4.8beta1.zip`.
2. Extract to a new working directory; do not overwrite the only working copy.
3. Read this file, `docs/AOI_PRODUCT_DIRECTION.md`, `docs/RECOVERY_LEDGER_3.2.6.md`, `docs/review_3_2_7/REVIEW_NOTES.md`, and `docs/review_3_2_8/REVIEW_NOTES.md`.
4. Continue from the **Next implementation direction** below. Do not restart the project, discard previous visual work, revert to 3.2.7, or treat the 3.2.8 changes as merely design proposals.

## User's product direction

Aoi is an outcome-first AI partner in a polished, full-screen mobile chat. The user should not need to understand agents, tools, terminals, Godot, project manifests or build logs. Normal chat stays quiet; real long-running work gets a truthful, compact status card. A workspace is not a finished product. A game is only complete when the planned experience is actually implemented and verified as playable.

Visual reference: supplied ChatGPT Android screenshots at approximately 720 px width. Use two slightly inset floating header pills, a thick floating composer, clean typography, refined branded vector motion and restrained copy. No robot/smiley identity. Use Inter Variable, preserve the abstract constellation/prism identity, and respect reduced-motion. PC streaming is explicitly deferred.

## Source lineage and preservation

- 3.2.8 is based on the recovered 3.2.7-dev source tree.
- The earlier 3.2.4 archive and 3.2.6/3.2.7 versioned checkpoints remain preserved in Dropbox; see `docs/RECOVERY_LEDGER_3.2.6.md`.
- The 3.2.5 package/source mismatch and 3.2.4 source-diff limitation remain documented. Do not retroactively claim the missing 3.2.4 diff was merged.
- Every meaningful checkpoint must produce a full source ZIP, a review/handoff record, an extracted-package verification, a versioned Dropbox archive, and an updated Dropbox `Current` only after preserving the previous `Current` under a dated backup filename.
- Never overwrite the sole known-good archive or package screenshots without the actual Godot source.

## Implemented in 3.2.8

### Conversation / approvals
- A follow-up can be queued while a high-risk action awaits approval or while the original project tool step is still running.
- Queued text is saved to the originating session and shown as queued; it does not execute until the decision/tool step resolves.
- Pending approval state stores its originating conversation/project, tool payload, native tool call identity and native tool queue.
- Leaving a chat hides the card but retains its persisted approval. Returning restores it.
- Cross-chat ownership keeps tool results and activity attached to the session that started the work; unrelated chats remain usable.
- Tool advertisements are suppressed in unrelated chats while another session owns a pending approval/tool cycle.

### Planning / execution
- Roadmaps require 5–14 tasks.
- Each task requires a detailed implementation brief (48+ chars), unique descriptive title, at least one concrete deliverable, observable acceptance criterion, verification method, file/discovery scope, supported specialist role and priority.
- Dependency references must resolve to other tasks and be acyclic.
- Planner prompt uses the same schema and includes project inspection before file-scope decisions.
- Workbench task cards show the task details, deliverables, completion condition and verification information.

### Preserved work
- State-driven Aoi Presence / Spatial Prism / Signal Field.
- Inter Variable typography roles and code font treatment.
- Branded icons, reduced-motion preference, activity state language.
- Project-agnostic Jobs/Workbench and existing bridge/provider integrations.
- Creation-card truth gates; no fake progress or fake finished-game claim.

## Current review artifacts

All are 720 × 1520 desktop/Xvfb viewport captures, not physical-phone captures:

- `docs/review_3_2_8/chat_baseline_720x1520.png` — first-run/no-provider empty state only.
- `docs/review_3_2_8/approval_with_queued_message_720x1520.png` — pending action plus queued follow-up.
- `docs/review_3_2_8/detailed_workflow_720x1520.png` — expanded roadmap / workflow details.

Review notes: `docs/review_3_2_8/REVIEW_NOTES.md`.

## Verification status — do not overstate

- Latest isolated Godot 4.8 beta1 editor import: completed without parse errors.
- Focused logic tests: 82/82.
- Project-job contract: 21/21.
- Provider mock integration: 24/24.
- Latest isolated phone UI run: 106/106.
- A later aggregate run was terminated during the whole-phone UI stage (exit 143) and listed five failures in that invocation. The aggregate run is therefore **not clean**. Reproduce and diagnose the affected UI tests and runner timeout/configuration before considering a release.
- No physical Android install/interaction verification was available.

Raw logs for context are in `/mnt/data` in the current working environment and are summarized in `docs/review_3_2_8/REVIEW_NOTES.md`; logs are not feature progress.

## Newly identified product/design concerns

1. **Project Home remains developer-facing.** The previous project screen still exposes GitHub, Linux bridge, regression tests, task checklists and release criteria too prominently. Recompose it around the user's requested outcome, current status, real results, and one prominent “Continue with Aoi” action. Keep technical information under a secondary Work Details surface.
2. **The workflow screen is information-dense.** The current 720 × 1520 capture exposes project brief, workflow stages, four specialist-role cards, plan-generation controls, capture decision, task progress and detailed task contents simultaneously. This is useful evidence but too much for a consumer-facing default. Keep a clear primary summary and progressively disclose detail.
3. **Creation/approval content can dominate the chat.** In the approval capture the creation card, approval card and queued message are all present. Check vertical rhythm, compactness and whether the user can clearly distinguish the one required decision from queued follow-up.
4. **Chat typography still needs a dedicated comparison.** The user's supplied reference is cleaner and less visually bulky. Do not replace Inter wholesale; review body size, line height, paragraph spacing, inline code padding, list indentation and action-icon size against the real phone reference.
5. **No-provider empty state capture is not a conversation proof.** Its only purpose is to confirm the setup/onboarding empty state.
6. **Physical Android lifecycle remains open.** The app must preserve draft text, session, queued messages, approval and running-work identity through app backgrounding, process death and relaunch on the actual Android 8.1 device.
7. **Approval and tool lifecycle semantic coverage.** Review allow, deny, cancel, timeout, reconnect, process restart, provider failure, tool failure, queued message replay exactly-once, multiple consecutive native tool calls, and stale approvals. Confirm no duplicate tool execution or lost message on recovery.
8. **Roadmap completeness.** The validator enforces structure and dependency correctness, but semantic review must still ensure game plans include welcome/title screen, core loop, pause/settings, audio, saves, restart/game-over, accessibility, polish and final playable verification where appropriate.

## Next implementation direction

**Stabilize and make Project Home consumer-first.** Do not add decorative features until the approval/task lifecycle and default project experience are trustworthy. Recommended order:

1. Re-run and diagnose the inconsistent aggregate UI run. Confirm message queue replay, approval restore, cross-chat event ownership and tool-result return; repair any actual failures.
2. Add a focused lifecycle scenario that persists a pending approval + queued user message + native tool-call context, closes/reloads the app process, restores the owning chat, resolves the decision once, and verifies queued follow-up gets processed once.
3. Improve task workflow durability: checkpoint at plan accepted, task started, tool completed, task review, task approved/revised, and task failed/paused. Keep plan revision history and preserve task status only when acceptance criteria are unchanged.
4. Redesign Project Home/Results for ordinary users: project outcome, short status, real latest result, recent useful accomplishments, primary “Continue with Aoi”. Move GitHub/Linux bridge, task graph, raw release criteria and diagnostics under a secondary details/workbench path.
5. Review screenshots again and select the next direction based on the strongest remaining real defect.
6. Only then return to further vector animation and typographic refinement.

## Strict checkpoint routine

At every meaningful work boundary—and especially before any context switch or end of ChatGPT app session—update this handoff, update the review ledger, create a complete versioned ZIP, verify the extracted archive, upload it under `/Aoi/`, preserve the previous `Current` with a dated backup, then copy the new versioned archive to `/Aoi/Aoi_Mobile_Current_Godot4.8beta1.zip`. In the next chat, start by opening this handoff and the current package.
