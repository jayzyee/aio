# Aoi 3.1 development redesign review

**Review date:** 2026-11-12  
**Engine:** Godot 4.8 beta1 (`4.8.beta1.official.4d10419ca`)  
**Capture viewport:** 720 × 1520, Linux desktop render backend. These are actual Godot runtime captures at a phone-sized portrait resolution, not photographs from the user's Android handset.

## Product direction

Aoi is a general-purpose, project-agnostic AI workspace. It must support the user's game development, Godot work, AI/model experiments, general software/app development, research and unrelated projects. Godot-specific functions are optional capabilities inside Workbench; they must not define the entire product. Global preferences and reusable references are shared defaults, while project sources, goals and instructions remain scoped to their own projects.

## Visible changes in the current working tree

- The five primary destinations are Chat, Projects, Workbench, Library and Explore. Preferences, integrations setup and workflow controls are reached through context-appropriate secondary navigation.
- The disconnected Chat state has one clear provider setup action. The duplicate header connection button is hidden until a valid provider key and model are selected. Sending a draft without a provider routes to setup without discarding the draft.
- Projects presents workspace totals, open/completed task counts, search, progress and the next outstanding task before opening a project.
- Workbench is described as a general development workspace for supported projects. Godot-specific API and scene tools are shown as optional capabilities for Godot projects.
- Preferences imports the user's complete 7,663-character global engineering standard, presents it in a readable Markdown-rendered preview, and opens a dedicated editor for changes. The complete standard is included in new-chat context (subject to the explicit 16,000-character cap).
- A global **Goals & ambitions** reference category now holds the user's Aoi workspace vision. Global references can be categorized and filtered; project-specific material remains in the project source system.
- Library cards normalize Markdown headings, emphasis and checklist syntax into readable excerpts. The full underlying source text remains intact for editing.
- Store persistence uses temporary writes and last-known-good backups for project/session/knowledge JSON, settings and encrypted credentials. Recovery handles interrupted or corrupt primary files; intentional deletion also removes recovery sidecars.
- Explore lists integrations with clearer tool/connection prerequisites, but its density and visual hierarchy still need a larger redesign pass.

## Screenshots in this review

- `chat_provider_setup.png` — first-run disconnected Chat.
- `projects_overview.png` — project totals, search and workspace progress.
- `workbench_landing.png` — general development workspace landing.
- `explore_integrations.png` — integration catalogue and prerequisites.
- `global_preferences_reference_design.png` — complete global standard and references.
- `global_reference_categories.png` — filtered reference view and developer reference section.
- `knowledge_library.png` — clean Markdown-aware knowledge previews.
- `godot_api_explorer.png` and `godot_api_node_selected.png` — earlier live ClassDB inspection captures; refresh as part of the next Workbench redesign pass.

## Next product-level redesign targets

1. Replace the repeated rounded-card/pale-canvas pattern with a stronger visual system, clearer hierarchy and deliberate density rules across every destination.
2. Redesign Explore's integration catalogue: distinguish connected apps, native tools, browser services, manual runners and unavailable capabilities; make permission and billing requirements scannable without oversized cards.
3. Continue the Chat pass: keyboard/safe-area behavior, conversation streaming, tool activity, approval and retry states, cancellation, empty/error recovery and long-thread performance.
4. Rework the Projects workspace detail view into a deliberate dashboard with clearer relationships between goals, tasks, notes, sources, workflow and evidence.
5. Consolidate global reference ingestion, category management, source provenance and retrieval; verify no project-private information leaks into global context or other projects.
6. Improve Workbench's mobile source/API/run workflows and distinguish capabilities available locally from those requiring a paired PC runtime.

## Reliability and verification boundary

- Actual Godot 4.8 beta1 app renders and focused GDScript behavior probes were exercised. The runtime logs still emit `Unexpected NUL character` warnings during startup/import; the source has not yet been isolated, so this remains open.
- These captures use Linux/llvmpipe at a phone-sized viewport. They do not prove physical Android 8.1 keyboard, cutout, gesture inset, lifecycle, input or performance behavior.
- Live provider credentials and external service end-to-end runs were not available for this review. Do not claim the full chat/tool workflow is stable on-device.
- Full accessibility review, long-session memory/cleanup testing, Android export and physical device validation remain outstanding.
- This is an in-progress redesign checkpoint, not a finished or stable release.

## Source of truth

The root of this Aoi Godot project is the latest working tree. Do not replace it with the older 3.0.2-dev archive. The separate ACI language-learning experiment remains independent; Aoi supports it as one project among many and must not absorb its model logic.
