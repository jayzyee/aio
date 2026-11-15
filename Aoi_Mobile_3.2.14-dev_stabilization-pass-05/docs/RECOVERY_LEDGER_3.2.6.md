# Aoi source recovery ledger — 3.2.6-dev-recovered

## Why this recovery exists
The user explicitly required source-complete checkpoint packaging after each meaningful milestone. A prior 3.2.5 archive did not meet that requirement: its project source was byte-for-byte the same as the locally retained 3.2.3-dev source, with only design and review artifacts added. The visual work was therefore not present in the actual running app despite the screenshots being present in the ZIP.

## Preserved checkpoints
- `/Aoi/Aoi_Mobile_3.2.4-dev_Godot4.8beta1.zip` remains preserved in Dropbox. It was confirmed present and downloadable by Dropbox metadata, but the archive bytes could not be materialized into this container during this recovery pass.
- `/Aoi/Aoi_Mobile_3.2.2-dev_Godot4.8beta1.zip` remains a prior checkpoint.
- The 3.2.3-dev and 3.2.5 visual checkpoint ZIPs were retained locally and not overwritten.
- No previous checkpoint was deleted or modified during recovery.

## Exact source lineage
This 3.2.6-dev-recovered working tree starts from the locally retained 3.2.3-dev source. It does not claim the unavailable 3.2.4 source diff was merged. Instead, it reconstructs the recovered 3.2.5 intent directly in the source tree. The source-lineage caveat is intentional and must remain in future package notes until the 3.2.4 archive can be compared and merged.

## Recovered and integrated product work
- Chosen visual direction: Spatial Prism over Signal Field; Twenty2 Kinetic Wordmark retained for deliberate brand reveals rather than ordinary activity states.
- `scripts/ui/AoiSignalField.gd`: a custom, state-aware spatial prism renderer with perspective-projected vertices, translucent faces, orbital traces, the Signal Field lattice and progress frontier. Motion is throttled and can be reduced.
- `scripts/ui/AoiPresence.gd`: abstract non-face Aoi constellation mark; updates at a bounded cadence and respects reduced motion.
- `scripts/ui/BuildExperienceCard.gd`: stage forwarding and reduced-motion configuration for the creation visual and progress rail. Existing plan-derived progress and real-result gates remain the source of truth.
- `scripts/ui/Ui.gd`: Inter Variable roles (regular, medium, semibold, display) using weight and optical-size axes; monospaced code face; reduced-motion preference reader; restrained button press/hover feedback.
- `scripts/ui/ChatScreen.gd`: display typography for the empty-state heading and structured RichTextLabel typography roles.
- `scripts/ui/SetupScreen.gd`: persistent Appearance setting for reduced motion.
- `assets/icons/agent.svg`, `assets/app/aoi_mark.svg`, adaptive foreground/monochrome SVG and raster launcher icons: abstract Aoi prism/orbit identity, no robot face.

## Review evidence
- `docs/design/AOI_MOTION_TYPE_ICON_BOARD.png` — the approved three-way identity board.
- `docs/review_3_2_6/creation_spatial_prism_720x1520.png` — freshly captured Godot runtime UI fixture at 720 × 1520. It depicts the card and visual system, not a generated playable game.
- `docs/review_3_2_6/chat_empty_720x1520.png` — freshly captured initial chat state at 720 × 1520.
- `docs/review_3_2_6/preferences_appearance_720x1520.png` — freshly captured Appearance/Reduced Motion preference state at 720 × 1520.

## Outstanding product acceptance items
- Physically install on the target Android phone and verify status-bar/cutout insets, gesture navigation, keyboard IME resize/pan, rotation and app lifecycle.
- Validate vector motion on a real low/mid-range phone, including reduced-motion transitions and thermal/frame pacing.
- Complete durable long-running work through process death/restart.
- Complete genuine game generation, playability checks and landscape immersive hand-off; the card must not pretend a workspace or screenshot is a game.
- Recover and diff 3.2.4 source when the archive can be made available locally, then merge only non-conflicting changes. Preserve this recovery line as a separate checkpoint until that comparison is done.

## Checkpoint replacement protocol (mandatory)
1. Keep the current known-good ZIP and every versioned checkpoint unchanged.
2. Make changes in a separate working directory.
3. Run engine import, focused feature tests, relevant full suites, and fresh 720 × 1520 screenshots. Review the screenshots and repair defects before release.
4. Build a fresh ZIP from the actual source tree, excluding only generated caches such as `.godot/`; include sources, assets, tests, manifests, design boards and current review notes.
5. Extract the ZIP into a clean directory, verify its file manifest/hash, then run the Godot import against the extracted package.
6. Upload a versioned checkpoint to Dropbox `/Aoi/` first. Do not replace `Current` until that versioned upload is confirmed.
7. Preserve the prior `Current` as a versioned backup, then update `/Aoi/Aoi_Mobile_Current_Godot4.8beta1.zip` from the verified new package. Never delete prior checkpoints.
8. Report user-visible feature progress and the package location. Test counts and internal checks remain internal QA evidence, not development progress.
