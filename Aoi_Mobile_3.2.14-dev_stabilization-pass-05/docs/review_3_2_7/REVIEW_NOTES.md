# Aoi 3.2.7-dev — Review notes

**Engine:** Godot 4.8 beta1 (the user's Library copy)  
**Capture target:** 720 × 1520 logical pixels  
**Scope:** vector identity, chat activity states, typography and keyboard-aware reading position  
**PC companion/live streaming:** explicitly deferred

## What changed in the product

### One Aoi identity across work states

`AoiPresence.gd` now draws a state-driven constellation/prism language. Its geometry, dot spacing, orbit direction, line connections and accent treatment vary between thinking, researching, planning, writing, creating, checking, finishing, retrying, waiting for approval, paused, error and complete. The visual remains an abstract mark; it does not use a face, emoji or generic robot mascot.

`ChatScreen.gd` resolves actual activity state/detail into the appropriate visual state and short activity wording. `BuildExperienceCard.gd` forwards the current project stage/detail to the same presence renderer. Paused, waiting, error and complete states settle instead of maintaining an active orbit. App focus loss suspends animation; the existing reduced-motion preference suppresses it as well. Redraw is capped at 30 FPS.

### Chat typography

`Md.gd` now differentiates H1/H2/H3, semibold/bold and italic emphasis, inline code, fenced code, links, list markers and quotes. Inter Variable continues to provide the interface hierarchy; code uses a system monospace face. The planning/Explore spark symbols were also redrawn as a coordinated orbit-and-diamond motif. Interactive button labels use Inter Medium, body text remains regular, and heading hierarchy uses semibold/display roles. No extra display font or large dependency was added.

### Keyboard-aware reading position

`Main.gd` now caches whether the reader was already following the latest chat content before the mobile keyboard opens. It scrolls to the bottom only on the keyboard's closed→open transition and only when the cached state says the reader was at the bottom. `ChatScreen.should_follow_bottom()` centralizes the same follow rule used by streamed replies. This avoids yanking a reader away from older messages when the IME reduces the viewport.

## Source files changed

- `scripts/ui/AoiPresence.gd` — state mapping, vector geometry, animation scheduling, focus/reduced-motion behavior.
- `scripts/ui/ChatScreen.gd` — activity-state mapping and `should_follow_bottom()`.
- `scripts/ui/BuildExperienceCard.gd` — forwards current task state/detail into AoiPresence.
- `scripts/core/Md.gd` — expressive Markdown typography and code/link/list/quote treatments.
- `scripts/ui/Ui.gd` — Inter Medium action labels and shared interactive button motion.
- `scripts/Main.gd` — keyboard transition and preserve-reading-position logic.
- `tests/unit_probe.gd` — state-resolution and typography expectations.
- `tests/e2e_scroll.gd` — near-bottom/older-reading assertions and a sufficiently long project-scroll fixture.
- `tests/review_capture.gd` — deterministic state/typography screenshot fixtures.
- `docs/review_3_2_7/` — fresh phone-sized captures and this review record.

## Screenshot evidence

All listed captures are Xvfb desktop renders at 720 × 1520. They are useful layout/visual evidence but do not substitute for a physical Android install.

- `activity_researching_720x1520.png` — research activity text and constellation state.
- `activity_writing_720x1520.png` — file/script work state and copy.
- `activity_checking_720x1520.png` — verification state and copy.
- `activity_paused_720x1520.png` — paused state; mark settles and wording changes to “Work paused”.
- `creation_state_720x1520.png` — existing project creation card / Spatial Prism state.
- `typography_720x1520.png` — headings, emphasis, inline code, links, quote and fenced code.
- `project_actions_720x1520.png` — project action buttons and task hierarchy with the branded planning icon.

## Verification and limitations

- Godot editor/import pass completed under Godot 4.8 beta1.
- Unit probe completed after state and Markdown changes.
- Phone swipe E2E completed, including the two new chat-follow assertions and project-page scrolling.
- The broader provider-backed `e2e_ui.tscn` run did **not** complete: provider setup checks failed and its log endpoint was malformed as `http://127.0.0.1:/__log`, indicating the mock provider port was not supplied in this environment. This pass does not re-certify provider connectivity, streamed responses or live tool execution.
- Keyboard logic was validated through its shared follow-position rule, but a real Android 8.1 IME open/close run remains outstanding. Physical safe-area, gesture navigation and lifecycle behavior also remain outstanding.
- No paired-PC streaming implementation was advanced in this milestone.
- Godot 4.8 beta1 is a beta engine; no stable-engine or production-release claim is made.

## Next product direction

Continue the same identity through richer context transitions and message surfaces without making the chat noisy. After that, prioritize one mobile foundation item based on a fresh full-app review. Keep immersive playable-game hand-off as a separate acceptance milestone; do not imply it is available until a real runnable game can be entered and returned from.
