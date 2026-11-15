# Aoi Mobile 3.2.8-dev — Product and Engineering Review

**Review date:** 2026-11-14  
**Capture size:** 720 × 1520  
**Engine:** Godot 4.8 beta1  
**Status:** Development checkpoint; not production/release approved.

## User-visible changes

- The composer no longer becomes unusable just because a project action needs approval. A follow-up message can be sent and is shown as queued until the pending action is decided.
- Leaving the originating conversation no longer silently denies or discards its pending action. The approval card can be restored when returning to that conversation.
- Another conversation can remain usable while the original project action is pending or running. Tool output and activity stay attached to the originating chat.
- Roadmaps must contain 5–14 structured milestones with detailed implementation briefs, deliverables, acceptance criteria, verification, file/discovery scope, valid roles/priorities and a valid acyclic dependency graph.
- Workflow task cards show the actual detail, deliverables, acceptance and verification information used to direct the implementation.

## Screenshot review

### `approval_with_queued_message_720x1520.png`

The composition demonstrates the desired continuity behavior: original user request, paused build card, one explicit approval card, then a follow-up message visibly marked as queued. The main risk is vertical density: the creation card plus the approval card plus the queued bubble consume substantial height. Retain the clear distinction between “one required decision” and “your message is saved”; consider reducing secondary explanatory copy after a full chat review.

### `detailed_workflow_720x1520.png`

The task schema is now visible and detailed enough to direct a specialist. However, the full screen is dense: project brief, stage sequence, four role cards, two plan actions and execution cards compete for the same viewport. Keep the underlying detail, but make the default user-facing overview progressively disclosed: outcome + short progress summary + next action, with task detail and specialist information one level deeper.

### `chat_baseline_720x1520.png`

This is a no-provider first-run empty-state fixture only. It is not evidence of provider connection or ordinary conversation behavior.

## Code areas changed

- `scripts/ui/ChatScreen.gd`: deferred follow-up queue; pending approval persistence/restoration; conversation ownership on session switching; cross-chat tool ownership guards; activity/result ownership.
- `scripts/core/AgentFlow.gd`: structured roadmap schema validation, task count bounds, field checks, dependency reference resolution and cycle detection.
- `scripts/Main.gd`: planner prompt aligned with validator schema and project discovery requirements.
- `scripts/ui/WorkflowScreen.gd`: detailed task instructions and deliverables made visible in the workflow surface.
- `tests/e2e_ui.gd`, `tests/unit_probe.gd`, `tests/review_capture.gd`: regression and capture coverage for the changed workflows.

## Verification evidence

- Godot editor import: latest isolated import log completed; Godot 4.8 beta1.
- Focused logic suite: 82/82.
- Project-job contract: 21/21.
- Provider mock integration: 24/24.
- Latest isolated full mobile UI flow: 106/106.
- Later aggregate run: terminated (exit 143) during whole-phone UI stage and printed five UI failures in that invocation. Treat aggregate verification as unresolved. Do not report this package as “all suites passed”.
- Physical Android device testing: not performed.

## Known limitations / defects to carry forward

- Confirm exact-once behavior when queued messages are flushed after both approval and denial, and when the pending tool returns an error.
- Explicit process-kill/relaunch scenario for pending approval, queued message, native call context and background work remains to be verified on Android.
- Project Home remains a developer-oriented workbench rather than the consumer-facing outcome/results surface specified by the product direction.
- Workflow view is too dense for a default novice-facing screen; technical detail should be progressively disclosed.
- Roadmap field validation does not by itself guarantee that a game roadmap includes every requested user-facing screen/system. Semantic completeness review is still required.
- Physical Android IME, safe-area, gesture navigation, keyboard resizing and rotation remain unverified.
- Full playable-game generation, actual game runtime launch, and landscape immersive hand-off remain unfinished. Paired-PC live streaming remains deferred.

## Release decision

**Development checkpoint only.** Do not ship as a stable release until the aggregate UI runner inconsistency is resolved, the approval/queue/restart lifecycle is validated, and physical-device acceptance is performed.
