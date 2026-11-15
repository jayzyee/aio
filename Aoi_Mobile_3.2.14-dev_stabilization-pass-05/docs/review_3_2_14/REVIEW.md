# Aoi Mobile 3.2.14-dev — visual system reset

## Direction

The previous pass treated screens as separate component collections. This pass establishes one shared visual language for the whole app:

- Neutral ink palette. Decorative blue, violet and teal are removed from the app chrome, Aoi mark, progress visuals and Markdown links. Colour remains only where it carries status meaning.
- No decorative shadows. Shared content groups are flat; alignment, type, whitespace and thin separators establish hierarchy.
- Shared geometry. Buttons, text inputs, menus, activity surfaces and sheets use a consistent restrained radius and edge treatment.
- One navigation model. The global overflow menu is chat-only; secondary screens use their own relevant actions. Connections and Settings replace vague Explore/Customize labels.
- Direct copy. First-run setup, project empty states and section labels say what is available or what happens next.
- Monochrome vector identity. Aoi's orbital mark and state-driven motion remain, but no longer rely on accent gradients.

## Screen review

- **Chat:** header controls are unboxed; composer is a single quiet surface; first-run action is explicit; message actions remain inline; task activity is a low-emphasis in-chat disclosure.
- **Project Home:** result-first structure from 3.2.13 is retained; no fabricated preview; project options use one consistent overflow menu; duplicate global overflow is removed.
- **Connections:** the page explains that entries are services Aoi can use after connection and separates native capabilities from browser destinations.
- **Library:** removed the duplicate page title and summary card; notes read as a clean list with quiet inline actions.
- **Settings:** removed the duplicate Preferences title and accent picker; appearance is a neutral system with an optional reduced-motion setting.
- **Menus:** global and project overflow menus use the same panel, text, hover and spacing treatment.

## Fresh visual evidence

All captures are Xvfb desktop renders at 720 × 1520. They are not physical Android screenshots.

- `screenshots/chat_720x1520.png`
- `screenshots/chat_messages_720x1520.png`
- `screenshots/chat_activity_720x1520.png`
- `screenshots/header_menu_720x1520.png`
- `screenshots/drawer_720x1520.png`
- `screenshots/projects_720x1520.png`
- `screenshots/project_menu_720x1520.png`
- `screenshots/explore_720x1520.png`
- `screenshots/setup_720x1520.png`
- `screenshots/knowledge_720x1520.png`

## Remaining product gaps

1. Research is currently strongest inside project discovery/planning and depends on the optional Brave Search connection. A general-purpose, user-invoked research action in ordinary chat is not yet implemented.
2. The composer still needs a proper attachment/input system for files and images; do not add a decorative attachment button until the flow is real.
3. The Connections directory is still a long catalogue. The next information-architecture pass should bring relevant capabilities into the conversation context rather than making users browse a service directory first.
4. Physical Android testing is still required for safe areas, IME resizing, gestures, rotation and animation performance. The automated touch-scroll run did not finish cleanly in this environment, so gesture acceptance remains open.
5. The separate Dropbox 3.2.12 archive could not be materialised for a source diff. This checkpoint follows the recovered 3.2.13 working tree and does not claim that archive's unique changes were merged.

## Validation record

The Godot project imported and launched. Unit, project-job, provider-mock, bridge, editor-addon and UI suites were exercised. The final UI run completed after a transient earlier run; raw logs are included in `logs/`. Provider tests use a local mock server. No live API provider or physical Android device was used.
