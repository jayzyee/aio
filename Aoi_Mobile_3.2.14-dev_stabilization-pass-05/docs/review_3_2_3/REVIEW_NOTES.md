# Aoi Mobile 3.2.3-dev — Product Review

**Engine:** Godot 4.8 beta1 (Library build)  
**Phone reference:** 720 × 1520 portrait  
**Checkpoint:** Development package; not a release-readiness claim.

## Product changes in this pass

- Replaced the report-like creation panel with the selected **Signal Field** direction: abstract constellation identity, one stage headline, one short status line, a visible blue-to-violet dot matrix, two restrained orbital traces, one progress rail and a compact percentage pill.
- Removed the project title, full brief, multi-line activity history and repeated explanations from the creation moment. The full brief and detailed task history remain accessible in the project workspace.
- Moved short creation acknowledgements into the card visually when a compact “I’m building it” message is immediately followed by the project card. Detailed assistant explanations remain ordinary chat messages.
- Added state-driven headline/status transitions and a restrained left-to-right signal movement.
- Percentages are derived from completed/total tasks in the saved project plan. When the plan cannot provide a defensible ratio, the card uses an indeterminate rail and shows no percentage.
- Added stale-work detection based on persisted activity. Aoi now distinguishes active model/tool work from stalled work, offers to resume an existing resumable checkpoint through its approval path, or continues the same project conversation without creating another workspace.
- Older projects without the dedicated Aoi heartbeat field can use their existing update timestamp as the freshness fallback.
- Kept the ready state gated by a completed plan and an existing preview tagged as a paired-runtime capture. A generic image, thumbnail or empty workspace cannot be marked as a finished game.

## Visual review files

- `creation_card_progress_720x1520.png` — controlled visual fixture with a three-step plan at one completed step. It demonstrates 33% derived progress; it is not a real game build.
- `creation_card_stale_720x1520.png` — controlled stale-state fixture demonstrating recovery copy and the `Continue work` action. It is not a real stalled user project.
- `../design/AOI_CREATION_CARD_DIRECTION_BOARD.png` — the three-way comparison board (Signal Field, Orbital Mark, Twenty2 Form).

Both captures were rendered at exactly 720 × 1520 to match the supplied ChatGPT phone reference and visually inspected after generation. The short build acknowledgement is not duplicated above the card in these current captures.

## Explicit limits / next acceptance work

- The bottom result/immersive composition on the design board is aspirational; the full landscape/immersive game hand-off is not yet implemented. A screenshot capture is not an interactive game. Aoi must only show a play/immerse affordance once a real runnable game session/output is available.
- A project generated on this phone cannot be assumed to run as a separate native game process. The next implementation should connect the paired runtime or an explicitly supported local runtime, validate its launch/readiness lifecycle, and then add an immersive player surface with orientation restore/back navigation.
- Physical Android verification of status/navigation bar insets, keyboard behavior, rotation, app background/restore, touch targets and lifecycle is still required.
- Provider-specific native tool calling and multi-hour job continuity remain broader acceptance areas; this checkpoint does not claim they are solved.

## Quality boundary

Automated checks and engine imports are recorded in the build logs; they are engineering verification, not product progress. The user-facing progress summary should describe shipped behavior and visible changes, not counts of passing tests.
