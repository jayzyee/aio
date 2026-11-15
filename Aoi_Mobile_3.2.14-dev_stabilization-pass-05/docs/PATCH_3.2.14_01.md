# Aoi Mobile 3.2.14-dev — interaction patch 01

## Scope

Correct the shared mobile bottom sheet used by model selection, connection setup, chat/session selection, project pickers and result details.

## Changes

- Added a 48 px touch target around the sheet grip so the drag gesture is usable on a phone rather than requiring a swipe on a 3 px visual line.
- Added touch and mouse dragging. Pulling upward expands the sheet to 94% of the available viewport; pulling down returns to its resting size or dismisses it after a deliberate downward gesture.
- Increased the default resting height from 78% to 88% of the viewport.
- Replaced the fixed scroll-height deduction with a bounded 168 px chrome-aware calculation. The content viewport now uses the available space more efficiently while retaining an internal vertical scroll region.
- Recalculates the sheet's content viewport when the viewport changes, including orientation and window-size changes.
- Preserved reduced-motion behavior: snap animation is skipped when the user has enabled reduced motion.

## Runtime status

The source patch is implemented. A Godot 4.8 beta 1 runtime could not be obtained in this workspace, so no fresh Godot-rendered post-change screenshot or on-device gesture acceptance is claimed. Existing project captures are baseline evidence only.
