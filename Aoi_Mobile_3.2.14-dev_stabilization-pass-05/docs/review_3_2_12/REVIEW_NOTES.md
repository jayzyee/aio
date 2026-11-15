# Aoi Mobile 3.2.12-dev — Review Notes

Date: 2026-11-14
Base: recovered `Aoi_Mobile_3.2.11-dev_Godot4.8beta1.zip`

## Implemented in this checkpoint

### Provider failure handling
- HTTP 404 is treated as a non-transient model/route failure.
- The client advances immediately to the next fallback already present in the provider's verified model catalogue.
- The failed model is not retried. The fallback attempt resets per-model compatibility/token retry flags.
- If no verified fallback is available, the user receives a clear instruction to refresh the model list or select another model.

### Creation task state
- A terminal LLM failure now writes `aoi_work_stage=error`, the actual provider error detail, a fresh timestamp and an activity event through the existing project persistence path.
- The creation card displays the error detail rather than continuing to show a generic active planning label.

### Android keyboard / viewport
- Detects when Android has already resized the app window for the IME and avoids subtracting the reported keyboard height a second time.
- Retains bottom-inset handling for overlay-mode keyboards.
- Removes the empty-state's fixed 360px minimum height so the scroll area can yield space to the composer on short viewports.

### Markdown tables
- Recognizes GitHub-style table header/separator rows outside fenced code blocks.
- Converts rows to vertically stacked labelled records rather than rendering raw pipe syntax or forcing a narrow horizontally clipped grid.
- Preserves escaped pipe characters inside cell content.

### Existing project discovery
- Adds a read-only `workspace.search_projects` tool for Aoi-managed projects on the device, searching title, goal, notes and task labels.
- Updates creation instructions: search saved Aoi projects and personal Knowledge Library before saying an existing project is unavailable or creating a replacement.
- Search output states its boundary explicitly; it does not claim to scan general phone storage, cloud drives or an unconnected PC. A configured paired workspace remains a separate, explicitly scoped search.

## Regression coverage added
- Mock provider can return HTTP 404 for the selected model while allowing the next catalogue model to succeed.
- E2E case asserts the failed model is requested once and the next verified fallback is used.

## Verification status
- Source edits and mock-provider regression case are present.
- Python mock-provider syntax and repository Python checks were run. Bridge and bootstrap checks passed; the editor-addon check could not run because it requires a Godot executable.
- Markdown and provider E2E GDScript regression cases were added but could not be executed without Godot.
- Godot runtime/E2E/UI tests are **not verified in this environment** because no Godot 4.8 executable is available in the current workspace.
- Physical Android IME behavior and fresh 720×1600 device screenshots remain **unverified** and must be checked on the target phone.

## Remaining agreed priorities
1. Full Android IME, focus, scroll-position, safe-area and rotation validation.
2. Verify project/library discovery against a real saved Flappy project and connected workspace.
3. Fresh physical-phone screenshots and comparison against the November 14 evidence.
4. Resolve source metadata lineage: previous archive `VERSION` says 3.2.11-dev while its `project.godot` and README said 3.2.9-dev. This checkpoint aligns the current project's version metadata to 3.2.12-dev; historical archive remains unchanged.
