# Aoi — Product Direction & Anti-Drift Contract

**Applies to:** Aoi Mobile, Aoi Studio, background project work, and all user-facing creation flows.  
**Baseline:** 3.2.8-dev, Godot 4.8 beta1.  
**Status:** Product direction approved; several acceptance items remain unimplemented or unverified.

## 1. Product promise

Aoi is a capable AI partner presented through a familiar, clean mobile conversation. The user describes an outcome in ordinary language. Aoi understands the request, does the available work, reports meaningful progress, verifies what it can, and presents the actual result. The user should not need to understand agents, tool schemas, terminals, Godot, runtimes, task manifests, or build logs merely to use Aoi.

Aoi must never imply that a workspace, scaffold, empty folder, starter screen, generated thumbnail, or successful tool call is the finished product. Completion means the requested outcome has been implemented against its acceptance criteria and verified to the level the connected runtime allows. When that standard is not met, the UI must say what remains and why.

## 2. Mobile interface direction

Use the supplied ChatGPT phone screenshots as the mobile interaction and sizing reference—not as a visual skin to copy.

- Conversation owns the full available screen. Top and bottom controls may sit close to the physical screen edges, but content must respect status bars, cutouts, camera grips, gesture areas, and the on-screen keyboard.
- Keep two floating header control groups: a left navigation pill and a right action pill. Position them slightly inward and lower than a conventional edge-pinned toolbar, as in the supplied reference.
- Keep the composer floating above the bottom gesture area, inset from the sides, visibly thick and comfortable to touch. It must grow to a deliberate small multi-line cap, then scroll internally rather than pushing the conversation out of view.
- Use one consistent typographic scale, icon family, spacing system, corner language, elevation, focus treatment, and motion curve across chat, project cards, tool activity, sheets, and previews.
- Icons must be branded, precise vector assets. Do not substitute Unicode emoji or generic smiley faces for identity. The Aoi presence should be the approved abstract constellation / orbital mark; no eyes or smiling face.
- Every control must have clear active, disabled, focus, loading, and error feedback. Preserve readable contrast and accessible touch targets.

## 3. Conversation and work activity

Ordinary conversation stays quiet. Greetings, simple questions, and answers must not produce an agent-status panel, progress percentage, fake thinking card, or work feed.

When a real tool or long-running task starts, show a compact, human-readable activity treatment. It may explain the current stage—understanding, researching, planning, creating, checking, or finishing—but every status must be driven by a real event or persisted task state. Expanded details may show useful actions and results, translated into ordinary language. Internal raw logs, API payloads, debug traces, and developer-only controls stay out of the primary chat surface; expose diagnostics only when the user asks or enters an appropriate workbench view.

Errors and stalled work must be visible. Aoi should distinguish active work, waiting for approval, paused work, retrying, failed work, and completed work. “Still working” must not animate indefinitely when the underlying job has stopped. Provide a truthful retry/resume path where possible.

## 4. Creation experience and project card

The active visual direction is **Signal Field** (see `docs/design/AOI_CREATION_CARD_DIRECTION_BOARD.png`). The card uses a stronger blue-to-violet particle matrix and two restrained orbital traces on a light surface. The dot field is the focal element; it must remain visible at phone scale, not fade into a decorative texture. Keep one short stage headline, one concise status line, one real progress rail and a small percentage pill only when a saved plan provides a valid completed/total ratio. The project goal and detailed activity history belong in the project workspace, not in this card.


A substantial creation request may attach a project to the originating conversation. The project experience should then become the primary progress surface, not a disconnected developer dashboard.

The in-chat creation card should stay intentionally compact:

- Keep the stage headline, one concise status line, progress and freshness/recovery state inside one coherent container.
- Keep the full project goal, recent completed steps, task graph and detailed history in the project workspace rather than crowding the creation moment.
- Use the abstract Aoi mark / particle system as a restrained visual identity. Motion must have meaning: formation, orbit, focus, progress and completion—not constant decoration.
- Use a determinate percentage only when derived from the saved task plan or another explicit measurable completion contract. No invented percentages or arbitrary progress jumps.
- Use an indeterminate animated rail when Aoi is genuinely working but no meaningful plan percentage exists.
- A stale update should visibly become paused or need attention rather than appear alive indefinitely. Offer resume for a resumable checkpoint or continue the same project without creating a duplicate workspace.
- Persist work events, current stage, task statuses, checkpoint references, results and known blockers so the card restores correctly after app restart.
- Offer a result/preview action only when an actual preview artifact or runnable output exists. Workspace creation alone must not expose a “play” or “open finished game” action.

For general AI experiments, scripts, research and data tasks, Aoi should show progress and report/log artifacts without forcing a game preview card. Card type and controls must follow the task's real output type.

## 5. Games and immersive hand-off

A game request should result in a genuinely playable game, not merely a new workspace or static mockup. Aoi should work through the full planned outcome: design, implementation, asset integration, launch, playability checks, bug fixing, and acceptance review.

When a real game build is ready, show a useful cover/thumbnail or an actual captured game menu/opening. The user can tap an immerse/expand control. That transition should open the playable output in its natural orientation (commonly landscape), use the available display area, handle device rotation/safe areas, and provide a clear route back to chat. It must not be a static screenshot pretending to be a running game.

The full landscape immersive hand-off is an acceptance requirement, not a feature to mark complete until it has been tested on an actual Android device/build and a real playable project.

## 6. Agent and tool behavior

The user asks for outcomes, not tools. Aoi selects the workflow and hides implementation detail unless the user asks for it.

- Use task classification and project inspection to choose research, planning, specialist roles, implementation, runtime testing, visual inspection, repair, or a combination.
- Keep long tasks resumable: persist project/task identity, plan, current step, completed work, files changed, checkpoints, last activity, retries, and next action.
- Use real tool results. Wait for calls to return before reporting success; never invent file writes, test results, screenshots, training steps, or generated outputs.
- Use the right execution host. Local GDScript tasks may run on-device under Aoi's documented trusted-code boundary. Python, shell, native binaries, full Godot execution, and PC screen capture require an actually connected compatible runtime. Do not pretend the phone can execute them when it cannot.
- Use Godot's actual headless runtime for project parse/import/test where available; inspect logs, correct failures and rerun bounded checks. For visual work, capture a fresh screenshot, inspect it, record concrete defects, and iterate.
- Maintain least privilege, project scoping, approval gates for consequential actions, stop/cancel, failure handling, and audit history.
- Keep model providers replaceable. Research, coding, vision, and other specialist capabilities must be honest about the selected provider's actual abilities.

## 7. Visual language and motion

Aoi's personality is expressed through a deliberate graphic system rather than a cartoon face: a restrained constellation/orbit mark, subtle particle formation, a small set of typographic treatments, and purposeful state-driven transitions. Branded light and depth can be used in activity cards, but must not harm legibility, performance, or calm composition.

Possible creation phrases (for example, “shaping the idea”, “building the world”, “checking the details”, “adding the finishing touches”) are copy variations, not proof of progress. The state machine decides what may be said. Animation must reflect real state and stop/reduce when motion is disabled or the task is no longer active.

## 8. Acceptance and release discipline

For every meaningful pass:

1. Inspect the current project and existing decisions before editing.
2. Research the specific implementation when the approach is not established; compare the strongest strategies when requirements are materially ambiguous.
3. Implement the smallest robust vertical slice that advances the product promise.
4. Run static/import checks, focused feature tests, provider/bridge tests, and relevant UI/touch tests.
5. Capture real app screenshots at the supplied 720 × 1520 phone reference size (and additional target sizes when relevant).
6. Compare controls, typography, padding, hierarchy, composer placement, card proportions, and safe areas against the supplied references.
7. Record what is verified, what failed, what was not testable, and what remains unfinished.
8. Correct defects found in the pass before packaging when feasible.

A passing unit suite does not establish stability by itself. A desktop-rendered screenshot does not establish physical Android behavior. A Godot beta import does not establish stable-engine compatibility. Do not call a build release-ready while critical acceptance checks or known regressions remain.

## 9. Explicit non-goals for this UI

- No default developer console, terminal transcript, raw tool-call dump, project tree, or task graph on the chat landing surface.
- No forced workspace/project creation for simple questions or greetings.
- No game result card for unrelated tasks.
- No fake progress percentage, fake preview, fake “complete” state, or fake runtime connection.
- No smiling mascot or generic emoji replacing the brand identity.
- No claim that agent roles are independent models, that work continues after process death, or that a runtime is connected unless the architecture and tests demonstrate it.

## 10. Current checkpoint limits (3.2.8-dev)

The 3.2.8-dev checkpoint carries forward the full-screen conversation-first shell, floating control groups, thick composer, abstract Aoi constellation/prism presence, Inter Variable typography, reduced-motion preference, state-driven work representation, Signal Field creation card, project-agnostic task runner, persisted workflows, and optional Linux/PC companion integrations.

This pass adds persisted follow-up messages while an approval or project tool step is pending; approval cards that restore to their originating conversation; cross-chat ownership boundaries for pending actions and background results; and a strict 5–14 task roadmap contract with detailed implementation briefs, deliverables, file/discovery scope, acceptance criteria, verification methods and dependency-cycle detection.

The following remain separate acceptance items and must not be described as complete without new evidence: full Android process-kill/relaunch and lifecycle verification; real keyboard/IME, safe-area, gesture and rotation behavior on a physical device; aggregate provider-backed phone UI reliability across long sessions; semantic quality and completeness of generated project roadmaps; fully playable game generation and real launch verification; full game preview/immersive landscape hand-off; and actual Android release packaging/signing. The latest aggregate whole-phone UI runner was terminated with inconsistent failures despite a separate focused UI run completing, so release stability is not certified by this checkpoint.
