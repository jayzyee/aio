# Aoi Mobile 3.2.6-dev-recovered — product review

**Engine target:** Godot 4.8 beta1 from the user's Library  
**Reference viewport:** 720 × 1520 portrait  
**Checkpoint type:** Recovered development source checkpoint; not a release-readiness claim.

## What is now implemented in the app source

- The chosen Spatial Prism concept is now drawn by `AoiSignalField.gd` at runtime. It combines the existing Signal Field dot matrix with a perspective-projected 3D wire prism, translucent face planes, orbital traces, vertex highlights and a progress frontier. The visual responds to project stage and uses a bounded redraw cadence rather than a pre-rendered animation asset.
- The dot field and prism edges were strengthened after inspecting the phone-size capture. The central prism remains contained inside its rounded visual surface.
- The existing Inter Variable font is now used through explicit regular, medium, semibold and display `FontVariation` roles, with `wght` and `opsz` axes. Rich chat text has dedicated regular/bold/italic/monospaced font roles.
- The Appearance card exposes a persistent **Reduce motion** setting. The constellation mark, Spatial Prism and progress rail settle into still compositions when enabled.
- Shared buttons now have restrained press/release/hover feedback. The first-use tween path was corrected after a runtime interaction review found an uninitialized metadata lookup.
- The generic robot-face asset was replaced by the abstract Aoi prism/orbit mark. Launcher, adaptive foreground and monochrome icons now use the same visual identity.
- The previous Signal Field creation card, plan-derived progress and real-result gating were retained; the new visual does not invent work progress or a game preview.

## Fresh visual evidence

- `chat_empty_720x1520.png` — freshly captured initial chat state at reference dimensions.
- `creation_spatial_prism_720x1520.png` — freshly captured creation-card state. This is a controlled UI fixture with a saved plan, not evidence that a generated game has been built.
- `preferences_appearance_720x1520.png` — freshly captured Preferences view showing the Appearance controls and reduced-motion switch.
- `../design/AOI_MOTION_TYPE_ICON_BOARD.png` — the three-way Aoi identity board. Spatial Prism is selected for hero/creation states; Signal Lattice remains the quiet ambient direction; Kinetic Wordmark is reserved for brand reveals.

All screenshots above were rendered by the Godot project at 720 × 1520 and visually inspected. They are desktop/Xvfb renders, not physical Android device captures.

## Source lineage — read before replacing an installation

This recovery checkpoint starts from the locally retained 3.2.3-dev project source. The 3.2.4 archive remains preserved in Dropbox, but its source diff could not be materialized into this session. The previous 3.2.5 ZIP was confirmed to contain unchanged 3.2.3 source plus design/review artifacts. The 3.2.5 motion/type/icon work has now been reimplemented in source here; the package does **not** claim to include the unavailable 3.2.4 source diff. Full details: `docs/RECOVERY_LEDGER_3.2.6.md`.

## Still open

- Install and test on the physical target Android phone: camera/status-bar safe areas, gesture navigation, keyboard resizing/panning, rotation, background/restore and lifecycle.
- Profile the animated vector field and icon transitions on the actual low/mid-range phone. Desktop software rendering is not a mobile performance measurement.
- Verify reduced-motion transitions on-device and check system accessibility behavior.
- Verify long-running work persistence across forced process termination and restart.
- Finish genuine playable-game output and landscape immersive hand-off. The project card must never expose a workspace or screenshot as a finished game.
- Recover and compare the 3.2.4 source archive when available locally; merge any distinct 3.2.4 changes without overwriting this recovered work.

## Quality boundary

The Godot 4.8 beta1 editor import and project test suites were run during this pass. Those checks support the implementation but are not product progress and do not establish physical Android stability. This remains a recovered development checkpoint, not a production release.
