# Aoi Creation Card — 3.2.3 Direction & Behavior Contract

## Selected direction: A / Signal Field

The supplied ChatGPT reference has a deliberately quiet hierarchy: a short creation status, one large dotted visual, and a small progress pill. Aoi keeps that low-noise structure but places the text and progress inside one contained card.

The comparison board records three directions:

- **A / Signal Field (selected):** the closest match to the reference. A broad dot field gains a left-to-right signal as real project work advances.
- **B / Orbital Mark:** adds more depth and dimensionality. Its orbital traces are used only as restrained accents, not as a separate illustration.
- **C / Twenty2 Form:** a distinctive brand signature for future identity work. It is not the active progress visual because it competes with the user's project content.

## Card hierarchy

1. A small abstract Aoi mark and a single stage headline.
2. The animated Signal Field. No mascot face, emoji, game-specific illustration or unrelated decoration.
3. One short, user-facing status line.
4. One slim progress rail. A percentage pill is shown only when the saved project plan has a meaningful completed/total ratio. Unknown progress uses an indeterminate signal and no number.
5. A real runtime capture replaces the signal field only after the preview is verified. A result action appears only when the saved plan is complete and the capture is tagged as a paired-runtime capture.

The card deliberately omits the project title, full project brief, multi-line activity feed, tool names, task graph and duplicate explanatory copy. Those details remain available in the project workspace; they do not belong in the creation moment.

## State language

| Internal state | Headline | Supporting line |
|---|---|---|
| planning | Imagining your game | Shaping the first plan |
| building | Building your game | Short phrase derived from the current real activity |
| reviewing | Polishing the details | Checking the experience before sharing it |
| waiting | One detail needs you | The rest of the work is safely paused |
| retrying | Picking up where we left off | Recovering the last saved step |
| stalled | Work may have paused | No new progress has arrived. Your saved work is still here. |
| ready | Your game is ready | Your result is ready to explore |

## Progress integrity

- The percentage is calculated from the saved project plan (`completed / total`).
- No percentage is shown when the plan is absent or incomplete as a data source.
- A preview image by itself cannot mark a project ready.
- A ready state requires both all planned tasks complete and an existing preview tagged `paired_runtime_capture`.
- A running/queued JobRunner task prevents stale detection.
- Paused, interrupted or failed resumable jobs expose a checkpoint-resume action. Resuming still goes through the existing explicit approval flow.
- Other stale work exposes `Continue work`, which sends a continuation request in the same project conversation. It explicitly tells Aoi not to create a new workspace.
- While the model or a connected tool is actively busy, the card does not claim that work has stalled. Streaming activity persists a heartbeat so a later app restart can distinguish current work from an abandoned task.

## Result and immersion boundary

The current app can display a verified paired-runtime capture and open its project workspace. A still capture is not an interactive game. The full-screen landscape hand-off must wait for a real playable runtime bridge; the UI must never present a screenshot as gameplay. This remains an explicit next acceptance item.

## Review criteria

- Compare the card's text density and proportions against `AOI_CREATION_CARD_DIRECTION_BOARD.png` and the supplied 720px-wide ChatGPT screenshot.
- Confirm the empty/chat landing remains quiet; the card appears only for project creation/build sessions.
- Inspect both progress and ready render states.
- Confirm a real task update changes the rail and status; an unknown plan shows no percentage.
- Confirm stale recovery resumes the existing project/job and does not create another project.
