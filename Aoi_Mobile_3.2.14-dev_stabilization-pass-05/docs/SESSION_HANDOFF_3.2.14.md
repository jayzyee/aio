# Aoi Mobile 3.2.14-dev — session handoff

## Current source

- Godot: 4.8 beta1
- Version: 3.2.14-dev
- Base: recovered 3.2.13-dev working tree
- Current milestone: unified neutral visual system and menu/navigation consistency

## What changed

- `scripts/ui/Ui.gd`: neutral palette, no decorative shadows, flat content groups, standardized controls and shared PopupMenu styling; primary buttons load white vector icon variants.
- `scripts/Main.gd`: unboxed header controls, chat-only global overflow, Connections and Settings navigation labels.
- `scripts/ui/ChatScreen.gd`: direct first-run language, calmer composer and activity surface, consistent composer menu.
- `scripts/ui/ProjectsScreen.gd`: one project overflow menu, result-first copy and neutral output treatment.
- `scripts/ui/ToolsScreen.gd`: Connections wording and clearer native-vs-external group names.
- `scripts/ui/KnowledgeScreen.gd` and `SetupScreen.gd`: removed duplicate titles and unnecessary summary/panel treatments; neutral appearance.
- `scripts/core/Md.gd`: neutral link, heading, quote, code and list styling.
- `scripts/ui/AoiPresence.gd`, `AoiSignalField.gd`, `AoiProgressRail.gd`: monochrome vector motion.
- App and launcher icon assets rebuilt to match the orbital monochrome identity.

## Evidence

See `docs/review_3_2_14/REVIEW.md`, screenshots and raw logs.

## Next work — do not broaden before this

1. Build contextual research inside chat: a clear, low-emphasis research action, current-source retrieval, inline citations/source review, and honest connection/usage states. General chat research is not yet implemented; current Brave research is project-scoped.
2. Design and implement real file/image attachment flows before exposing composer affordances.
3. Rework Connections as a secondary utility, with relevant capabilities invoked from chat rather than relying on a long catalogue.
4. Review all remaining screens and menus against the same neutral system; inspect each new screenshot before accepting it.
5. Run physical Android acceptance for safe areas, keyboard, gestures, rotation and motion.

## Known limits

- No physical Android device was used for this checkpoint.
- Provider E2E uses a mock service.
- The separately stored Dropbox 3.2.12 archive remains unreconciled; do not claim its unique changes were merged.
- Do not replace a source archive with a different base without checking lineage.
