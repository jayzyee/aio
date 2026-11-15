# Aoi 3.2.11 — User Phone Evidence & Usability Audit

**Evidence date:** 2026-11-14  
**Source:** ten screenshots supplied by the user from the current 3.2.9-era phone build.  
**Capture dimensions:** 720 × 1600.  
**Purpose:** preserve observed issues for the next implementation pass. These are real-device screenshots, not Xvfb fixtures.

## Defects visible in the supplied phone captures

### P0 — Workflow appears stuck and does not communicate failure promptly
- The creation card repeatedly remains at **“Imagining your game” / “Shaping the first plan”** across multiple time-separated captures.
- The visible card offers no useful last-event timestamp, no clear heartbeat freshness, and no clear transition to blocked/retrying/failed when the request has stopped.
- One screenshot eventually shows an OpenRouter **HTTP 404**, while the creation card still looks like active work. The provider failure and task state are not reconciled in a way that restores user trust.
- The same unavailable model can be surfaced as a retry target even though a 404 is generally a non-transient model/route problem. It should be classified, checked against the model catalogue, and routed to a valid fallback or shown as a clear recoverable model-selection issue.

### P0 — Keyboard / viewport composition
- With the keyboard open, the chat's central empty-state composition remains positioned as if the full-height viewport were still available. It is visually stranded above the keyboard instead of adapting into the available space.
- The composer / focused input relationship needs inspection on the actual Android IME: it must remain visible, avoid being covered, and preserve the user's reading position.
- Chat layout must respond to the effective visible viewport, not only the full device height. Re-check focus, keyboard appearance/disappearance, multiline growth, scroll-to-bottom and safe-area/gesture insets.

### P1 — Markdown rendering and text hierarchy
- A model comparison table is displayed as raw Markdown pipe syntax rather than a readable table or deliberately formatted fallback.
- Long assistant explanations are rendered as dense full-width paragraphs. Break prose into meaningful sections and lists only where content supports it; retain correct Markdown structure.
- Validate headings, nested lists, block quotes, code, links, tables, long URLs, and mixed-language text. Do not silently render unsupported Markdown syntax as literal punctuation.

### P1 — Existing project discovery and truthful capability messaging
- Aoi tells the user that no existing Flappy project appears in the Knowledge Library and that it cannot browse the phone filesystem, then immediately offers a fresh workspace. It should search every supported project/library surface first, and distinguish “not indexed”, “not connected”, “not found”, and “not accessible”. Do not imply a complete device search if no such capability exists.
- The app's capability explanation should be aligned with current connected tools. It must not contradict the newly introduced Research phase or available project/library discovery paths.

### P1 — Conversation and task lifecycle
- Users send follow-up requests while a creation task is still running, but the activity card must not continue displaying a stale stage while a subsequent request or provider failure has changed the task state.
- Task/project creation, research, planning, implementation, provider retry/fallback, pause, approval, cancellation, and completion must have distinct persisted states.
- A rejected model call must terminate or transition the task's active heartbeat and display an action that actually changes the failure condition. Repeating the same unavailable model is not a recovery path.

### P2 — Visual consistency
- Creation card remains spacious and visually coherent, but its status must earn the space by changing with meaningful events.
- Chat prose and user bubbles need closer comparison with the supplied ChatGPT reference: line length, paragraph spacing, list indentation, heading rhythm, width, top inset beneath floating header pills, and composer padding.
- Long scroll positions must not allow a message to be hidden behind the floating header. Verify first/last message visibility and focus transitions.

## Current codebase context carried into this checkpoint

- `scripts/ui/ProjectsScreen.gd` includes a consumer-facing Project Home plus a secondary Work Details surface (`docs/review_3_2_10/`).
- `scripts/core/AgentFlow.gd` contains research records, source validation and plan gating.
- `scripts/ui/ChatScreen.gd` initiates mandatory research for new substantial projects and requires persisted evidence before roadmap acceptance.
- `scripts/core/LLM.gd` has streaming, non-stream fallback and transient retry behavior, but the HTTP 404 path currently terminates the call rather than resolving the model against a refreshed catalogue / alternative configured model. This is a candidate for focused repair.
- `scripts/core/Md.gd` has inline rendering for headings, emphasis, links, code, lists and blockquotes, but no Markdown table renderer; this explains the raw pipe output observed in the phone screenshot.
- Keyboard-aware follow behavior exists in `ChatScreen.gd`, but the real-device screenshots show the empty-state layout does not compact/anchor correctly when the keyboard occupies the lower portion of the screen. Physical IME behavior needs a dedicated correction and verification pass.

## Priority order for the next implementation pass

1. Fix live task-state reconciliation: provider 404, retries, progress heartbeat, stale-work detection and truthful paused/failed/recoverable states.
2. Fix Android keyboard/viewport behavior: effective viewport sizing, visible composer, empty-state vertical placement, message-area scroll and position preservation.
3. Fix Markdown table rendering and rich-text layout consistency.
4. Fix project/library discovery and capability messaging so existing projects are not prematurely abandoned.
5. Re-run the actual creation workflow with a deliberately unavailable model and a valid fallback, then confirm the progress card changes state and the chat remains usable.
6. Capture new physical-phone screenshots at 720 × 1600 and compare each issue against this audit.

## Scope guard

Do not add further decorative animations or broaden the feature set before P0 usability and task-state defects are addressed. Keep the research-first design workflow, Project Home, detailed planning, Aoi constellation identity, Inter typography, approval continuity and cross-chat ownership from previous checkpoints. Do not regress these foundations.

## Evidence inventory

- `06-42-17.png` (720×1520): Chat opens with keyboard; central empty-state content remains far below focus area.
- `06-44-17.png` (720×1520): Creation flow starts with activity card; monitor whether status changes and follows genuine events.
- `06-47-25.png` (720×1520): Assistant capability explanation and follow-up chat; inspect prose density and response context.
- `06-53-02.png` (720×1520): Long model comparison output; Markdown table syntax appears as raw pipe-delimited text.
- `06-55-34.png` (720×1520): Empty chat after switching/new session; inspect viewport and composer behavior.
- `06-55-52.png` (720×1520): New project request with active creation card; status text remains unchanged.
- `06-56-01.png` (720×1520): Creation card continues showing the same planning state; user is not getting useful heartbeat updates.
- `06-57-28.png` (720×1520): Assistant claims no existing Flappy project can be found; project/library discovery limitation is exposed to the user.
- `06-58-47.png` (720×1520): Repeated stuck creation state and long explanatory response; no meaningful task advancement visible.
- `07-00-42.png` (720×1520): OpenRouter HTTP 404 surfaced; same task card remains and recovery feels disconnected.

- Contact sheet: `PHONE_EVIDENCE_CONTACT_SHEET.png`
