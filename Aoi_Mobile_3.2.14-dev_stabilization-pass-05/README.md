# Aoi Mobile 3.2.14-dev — unified visual system

Aoi Mobile 3.2.14-dev is a visual-system reset across the existing Godot app. It replaces decorative accent colours, floating card stacks and inconsistent rounded surfaces with a single neutral ink language. Content groups are flatter; hierarchy comes from typography, alignment and spacing. Buttons, inputs, bottom sheets and overflow menus share one geometry. The chat remains the centre of the app, with Projects, Library, Connections and Workbench reached through one consistent navigation drawer.

Aoi's orbital identity and in-chat activity retain state-driven vector motion, now in monochrome. Primary-action icons have matching white vector variants. First-run and project-empty copy has been rewritten to state what the user can do next. The Project Home result-first layout from 3.2.13 remains, but its visual treatment has been simplified as part of this reset.

**Current checkpoint:** 3.2.14-dev · Godot 4.8 beta1 · stabilization pass 05, GitHub Codespaces remote Linux workflow, chat request ownership, truthful game-result state and the existing monochrome visual system. The app remains pinned to this engine: a Godot 4.7.2 stable probe currently fails the editor-addon compile and touch-scroll regression. Fresh 720 × 1520 review captures are under `docs/review_3_2_14/final_pass/`.

**Stabilization handoff:** [`docs/STABILIZATION_3.2.14_PASS_05.md`](docs/STABILIZATION_3.2.14_PASS_05.md) records the latest user-facing and cloud-runtime changes. [`docs/review_3_2_14/FINAL_REVIEW.md`](docs/review_3_2_14/FINAL_REVIEW.md) identifies the fresh captures and the remaining live-account/device acceptance boundary.

**Verification limits:** the project was opened and captured using Godot 4.8 beta 1. Its full local regression, UI and touch-scroll suites pass after the test runner imports project assets. The reviewed screens are desktop renders at 720 × 1520, not physical Android captures. A real GitHub token/repository was not connected, so a live Codespace create/bridge handshake has not yet been performed. Physical device keyboard/IME, safe areas, gestures, rotation and performance remain unverified. Do not describe this checkpoint as an Android release.

**Source lineage:** based on the recovered 3.2.13-dev checkpoint (3.2.11 source plus the 3.2.12 recovery patch and Project Home changes). The separately stored Dropbox 3.2.12 archive could not be materialised for a binary/source diff; it is preserved until that comparison is possible.


## Project overview

Aoi Mobile is a phone-first AI workspace built with **Godot 4.8 beta1**. It combines model-backed chat, persistent project knowledge, a traceable specialist workflow, GitHub tools and an optional **remote cloud Linux workspace**. Your phone remains the interface; GitHub Codespaces is the recommended first remote host, so your personal computer does not need to stay online. Aoi Studio is project-agnostic: it imports ordinary folders and projects, detects project formats and entry points, indexes live Godot APIs, validates GDScript, generates native scenes, and previews supported scenes locally. Projects may declare their own optional headless tasks in `.aoi/tasks.json`; Aoi core contains no domain-specific training or application modules. The cloud runtime can launch Godot, return logs and capture the actual remote display. Aoi must verify a real live result before claiming a game is complete.

## Product direction and verification

The current user-facing design is governed by [`docs/AOI_PRODUCT_DIRECTION.md`](docs/AOI_PRODUCT_DIRECTION.md). The creation experience follows [`docs/AOI_CREATION_CARD_SPEC.md`](docs/AOI_CREATION_CARD_SPEC.md). The current visual review, fresh screenshot evidence and remaining acceptance boundary are recorded in [`docs/review_3_2_14/FINAL_REVIEW.md`](docs/review_3_2_14/FINAL_REVIEW.md). For a context reset, read [`docs/SESSION_HANDOFF_3.2.14.md`](docs/SESSION_HANDOFF_3.2.14.md). Historical checkpoint notes remain under `docs/review_3_2_9/` through `docs/review_3_2_12/`. The 3.2.8 handoff remains as historical checkpoint documentation. Source lineage is documented in [`docs/RECOVERY_LEDGER_3.2.6.md`](docs/RECOVERY_LEDGER_3.2.6.md).

## Product structure

### Chat and knowledge

- Streaming chat through Google AI Studio, OpenRouter and Groq using the user's own API key, plus native Puter chat using a full-access token and paid Puter plan.
- Casual Chat, Build and Money modes, with project context attached when selected.
- Model discovery and selection grouped by provider, with stop, regenerate, copy, select-text and save-to-project actions.
- Persistent local conversation history.
- A separate personal Knowledge Library with searchable notes, tags, pinning, editing and deletion. Assistant answers can be saved directly into it. Relevant personal notes can be retrieved into later chats, and explicit AI save operations require approval.
- Project-scoped knowledge notes, decisions and reusable playbooks. The assistant can search relevant project knowledge during a project conversation and save confirmed material only through an approval card.
- Wikipedia search/read as a background knowledge source. For current facts, use the research/web path rather than treating Wikipedia extracts as live news.

### Team workflow — plan, research, implement, verify, approve

The workflow combines researched patterns from **Teamily AI** (agent teams in conversation, connected context and shared memory) with **Teamly** (searchable knowledge, structured articles and reusable SOPs): specialist responsibilities, shared project knowledge, dependency-aware task boards, visible activity, reusable procedures, tool permissions and human approval. It is Aoi's own implementation and visual language, not a rebrand, integration or claim of affiliation.

A project can be converted into a dependency-aware plan. Each task has an owner role, detail, priority, prerequisites and an acceptance criterion. The workflow screen exposes:

1. **Planner** — turns the brief into explicit tasks and dependencies.
2. **Researcher** — gathers evidence and inspects public references, project knowledge and accessible repositories. Read-only.
3. **Engineer** — implements the assigned task using only connected tools. Every command execution and external mutation requires a separate approval.
4. **Reviewer** — checks evidence and acceptance criteria. It can inspect and run approved verification commands, but cannot write implementation files or GitHub changes.
5. **Human approval** — completed agent output enters `Review`; it is not marked complete until the project owner approves it. The owner can request changes with feedback, which returns the task to the queue.

Project knowledge, decisions, approvals, tool outcomes and task transitions are recorded in a local activity history. Knowledge notes and playbooks persist per project. Task attempts, dependencies, review feedback and acceptance criteria are persisted so a task can be retried without losing its context.

**Important architecture limit:** Planner, Researcher, Engineer and Reviewer are role-specialised workflow turns using the currently selected model/provider. They are not four independently hosted models, and the current graph is a guided project workflow rather than a fully autonomous distributed agent scheduler. The role prompts and tool allow-lists constrain what each turn may request; the app and its approval manager remain responsible for actually executing tools.

### Plugins and developer tools

The Connections directory distinguishes native AI-callable integrations from browser destinations. Opening a website does not mean Aoi can invoke its APIs.

**Native AI-callable tools:**

- **Android Clock and Calendar:** on Android builds, Aoi can prepare a one-time alarm or calendar event in the device app. Each action requires approval and the user confirms the save in Clock or Calendar. Aoi does not read the user's calendar and does not claim the event was saved. No exact-alarm or calendar-access permission is requested.
- **GitHub:** repository search, repository metadata, file/tree inspection, branch creation, file writes, issue creation and pull-request creation. Reads are available without a token for public repositories (within public API limits). Writes require a fine-grained token and individual user approval. Aoi requires a topic branch for file writes and blocks direct writes to `main`/`master`.
- **Cloud Linux workspace:** a token-protected bridge running in a remote Linux environment. The included GitHub Codespaces setup installs the matching Godot runtime, keeps file operations inside its workspace and returns real runtime logs and captures. Your personal computer is not the host. Shell commands still run with the remote workspace user's permissions; this is not an OS sandbox.
- **Piston Runner:** remote Python, JavaScript and Bash execution through a Piston server that the user owns or is authorised to use. This is distinct from the remote cloud Linux bridge. A remote server must be configured before it is callable.
- **Hugging Face Inference:** text-to-image generation and queued text-to-video generation through supported inference routes. Returned media is checked, saved in local app storage and linked to the chat. Provider/model availability and billing are controlled by Hugging Face and its selected inference provider.
- **Wikipedia:** public article search and extract retrieval.
- **Project tools:** search and save project knowledge, capture decisions and save reusable playbooks.

**Browser workspaces and creative destinations:** Puter, PixVerse, Kling, Hailuo, Hugging Face Spaces, Ideogram, Leonardo, Replit, StackBlitz, GitHub Codespaces, Google Colab, Kaggle Notebooks, JupyterLite, Canva and others. These are launch destinations, not native Aoi tool-call integrations unless a card explicitly states otherwise. Puter remains available as a browser workspace using its JavaScript/user-pays flow. Separately, Aoi supports native Puter text chat through its OpenAI-compatible API; that route requires a full-access Puter API token and a paid plan. Model discovery does not validate the token or make a paid request; the first actual chat checks access and may use account credit. Image, speech and video features remain browser workflows.

## Aoi Studio — Godot project workspace

Aoi Studio is deliberately project-agnostic: it can inspect and work on unrelated projects (Godot games, Python applications/AI experiments, Node projects, Rust/native projects, notebooks and generic source folders) without embedding any one project’s domain logic into Aoi. It detects project markers and entry points, reads the project’s own instructions, and proposes work based on the imported sources. ACI and other user projects remain separate folders and are never compiled into Aoi as product features. Aoi Studio lets the user create a project folder or import an accessible project folder, add source files, and describe the build in a bottom composer. A compact activity panel tracks planning, building, running and review. The Sources tab keeps the chat composer available while showing the project tree. The Toolbox can run/stop the project, run project verification, collect Godot logs and capture cloud runtime screenshots. For full setup, pairing security and the EditorPlugin dock, see [`docs/AOI_STUDIO_GUIDE.md`](docs/AOI_STUDIO_GUIDE.md).

The phone is the conversation, control and review surface; a connected cloud Linux workspace owns full desktop Godot runtime work. The immersive landscape game hand-off remains a future acceptance item until a real Android/playable-game flow is verified. The optional `addons/aoi_studio` Godot EditorPlugin adds a local editor dock. The Python bridge is an optional remote-workspace service, not a requirement for ordinary mobile chat or local project browsing.

## Connect GitHub

Open **Plugins → GitHub → Connect GitHub**. Create a fine-grained personal access token scoped to only the repositories Aoi needs. Suggested minimum permissions:

- **Metadata: Read-only** for repository metadata.
- **Contents: Read-only** for browsing and reading source.
- To allow branch/file writes, add **Contents: Read and write**.
- To create issues, add **Issues: Read and write**.
- To open pull requests, add **Pull requests: Read and write**.

Aoi verifies and stores the token in the encrypted local key file. Reads are immediate. Repository mutations appear in a confirmation card with the target repository/path/branch and a summary before they are sent. Aoi will not write a file directly to `main` or `master`; create a named topic branch first. Read the existing file and use its current blob SHA before updating it. Use the smallest repository scope and permission set that works.

## Connect a cloud Linux environment

Aoi's full Godot game workflow uses a **remote Linux workspace**. GitHub Codespaces is the recommended first provider; it is not your Android phone or your personal computer. The project includes a `.devcontainer` that installs the matching Godot 4.8 beta1 runtime, creates an isolated workspace, starts the authenticated bridge and exposes its HTTPS port.

1. Put this Aoi project in a **private GitHub repository**. Keep `.devcontainer/` and `companion/` in the repository.
2. In Aoi open **Connections → Cloud Linux workspace** and generate a 64-character key.
3. In GitHub repository settings, add that exact value as the Codespaces secret `AOI_BRIDGE_TOKEN`.
4. Create or rebuild a Codespace and let its setup finish.
5. In the Codespaces Ports panel, set port `8765` to Public if the included attach command could not do it automatically. Copy its HTTPS forwarded URL.
6. Paste the URL and same key into Aoi, save, and test the connection.

See [`docs/LINUX_GITHUB_SETUP.md`](docs/LINUX_GITHUB_SETUP.md) for the full setup, free usage limits, GitHub token guidance and security boundaries. Codespaces Free usage is limited, and this is not an unlimited always-on server. GitHub Actions can run temporary Linux jobs but does not keep an interactive Godot desktop alive.

The bridge supports `linux.exec`, `linux.list_files`, `linux.read_file`, `linux.search_files` and `linux.write_file`, plus Godot project create/run/stop/status/test/log/capture actions. File access is confined to its configured workspace. Shell commands run with the Codespaces user's permissions, so this is not an operating-system sandbox; keep the repository private and never commit the key.

## Connect Piston (remote execution)

Open **Plugins → Piston Runner → Connect a code runner** and enter a Piston API base URL owned by you or an authorised provider. Use HTTPS for remote endpoints. Test with a harmless snippet first. Code is sent to that remote server and must not contain passwords, tokens, personal information or other secrets. The previously public hosted Piston endpoint is not generally a dependable free service for new users; supply a working endpoint of your own.

## AI providers and keys

Open **Setup** and connect Google AI Studio, OpenRouter, Groq or Puter. Google AI Studio is a simple starting point. Model access, pricing, free tiers, regional availability and rate limits are determined by each provider and change over time. Native Puter chat requires a full-access API token from Puter Dashboard → Account → API Token and a paid Puter plan; the token is broad account access, not an app-scoped key. Aoi only loads Puter's public model catalogue during setup. It checks the token and plan on the first actual chat request, which may use account credit. Puter.js remains available in the browser for the separate user-pays flow. Aoi stores credentials in an encrypted local config file; this helps against casual file inspection but is not a security boundary on a rooted or compromised phone. Prompts and conversation data are sent to the provider you select.

## Run the project

1. Install a compatible Godot 4 editor. This revision was imported and tested with the user's **Godot 4.8 beta1** Linux binary.
2. Extract the project folder and import `project.godot`.
3. Press Play. Rendering is configured for mobile compatibility and a 720 × 1280 portrait design canvas.
4. For Android export, configure Android SDK/JDK and install matching Godot export templates. The Android preset contains arm64-v8a and armeabi-v7a support, network permissions and Aoi launcher/adaptive icons. The CI workflow builds a debug APK; it is not a Play Store production-signing pipeline.

No release APK is included. A physical Android 8.1 device test is still needed for keyboard resize, safe areas, lifecycle, memory pressure, external-app handoff and real provider connections.

## Run tests

On Linux, install Python 3 and `xvfb`, then run:

```bash
GODOT=/path/to/Godot_v4.8-beta1_linux.x86_64 ./run_tests.sh
```

The runner imports project assets, starts a mock model server and checks the local Linux bridge, GDScript logic, provider streaming/fallback/cancellation, the whole UI and touch scrolling. Live GitHub, Hugging Face, and remote cloud integration still require the relevant credentials and a running workspace.

## Important project files

| Path | Responsibility |
|---|---|
| `scripts/core/LLM.gd` | Streaming provider client, model discovery, cancellation and fallback |
| `scripts/core/Store.gd` | Conversations, projects, personal knowledge, settings and encrypted credentials |
| `scripts/core/AgentFlow.gd` | Task graph, project knowledge, playbooks, decisions, reviews and activity log |
| `scripts/core/ToolRunner.gd` | GitHub, Linux bridge, Piston, Wikipedia and Hugging Face tool execution |
| `scripts/ui/ChatScreen.gd` | Chat UI, role-scoped tool descriptions, knowledge save actions and approval cards |
| `scripts/ui/KnowledgeScreen.gd` | Searchable personal knowledge library with tags, pins and editing |
| `scripts/ui/WorkflowScreen.gd` | Specialist workflow, tasks, knowledge and review controls |
| `scripts/ui/ToolsScreen.gd` | Searchable integration catalogue and manual runners |
| `scripts/Main.gd` | App shell, navigation, setup sheets and approval routing |
| `companion/aoi_linux_bridge.py` | Token-protected cloud Linux bridge |
| `tests/`, `tests_py/` | Godot logic/UI and Python bridge regression tests |

## Release status

Aoi Mobile 3.2.14-dev is a **development checkpoint, not a Play Store release**. The project imports and launches in Godot 4.8 beta1. The current checkpoint includes the unified neutral visual system, consistent controls and menus, and the result-first Project Home carried forward from 3.2.13. The project opens under the pinned engine and fresh desktop captures are recorded in `docs/review_3_2_14/final_pass/`. A live Codespaces account/repository, physical Android device, Android export templates/SDK and actual provider credentials were not connected during this pass; those are distinct acceptance steps. Native integrations require the user's own tokens, accounts or companion service. Specialist roles currently share the selected model/provider; they are role-scoped workflow turns, not independently hosted models.

## Current runtime review captures

Historical captures remain in their original review folders. The latest 3.2.14 screenshots are fresh Godot/Xvfb desktop renders at a 720 × 1520 phone-sized viewport, not physical Android screenshots. The capture fixtures do not represent an active provider conversation or a live GitHub Codespace. The current cloud runtime implementation is described in `docs/LINUX_GITHUB_SETUP.md`; do not follow the older local-PC/Termux pairing notes as the current recommendation.

## Android and cloud Linux setup

See [`docs/ANDROID_MOBILE_SETUP.md`](docs/ANDROID_MOBILE_SETUP.md) for the Android 8.1 phone setup and export checklist. See [`docs/LINUX_GITHUB_SETUP.md`](docs/LINUX_GITHUB_SETUP.md) for the current Codespaces cloud Linux setup, free usage limits, security model and GitHub repository connection. [`docs/AOI_STUDIO_GUIDE.md`](docs/AOI_STUDIO_GUIDE.md) describes the current mobile project workflow and runtime requirements. Older PC/Termux documents are retained as historical implementation notes, not as the recommended cloud setup.


## Personal Knowledge Library

Aoi keeps personal notes separately from projects. Notes can be tagged, pinned, searched across title/content/tags, saved directly from an assistant answer, and retrieved as relevant context in later chats. The assistant can call `knowledge.search` as a read tool; `knowledge.save` requires per-action approval. Cloud Linux is optional; the mobile client remains useful without it.


## Aoi Studio implementation files

| Path | Responsibility |
|---|---|
| `scripts/ui/StudioScreen.gd` | Mobile Studio screen, source tree, project selection, activity panel, API Explorer, scene builder and local preview |
| `scripts/core/GodotSandbox.gd` | Live ClassDB index, class inspection, compiler validation, bounded file writes and restricted scene generation |
| `addons/aoi_studio/` | Standalone Godot EditorPlugin dock for local editor actions |
| `companion/aoi_linux_bridge.py` | Token-protected cloud Linux HTTP bridge and Godot process lifecycle |
| `tests_py/test_aoi_studio_bridge.py` | Project create/import/scan/upload/run/test/stop/logs bridge tests |
| `tests_py/test_editor_plugin.py` | Clean temporary Godot editor load test for the addon |
| `tests_py/test_pc_bootstrap.py` | Bootstrap install, loopback fallback and authenticated status tests |
| `docs/AOI_STUDIO_GUIDE.md` | Full setup, permissions, security and workflow guide |

## Aoi Studio review captures

Historical Aoi Studio captures are retained in `docs/review_2_9/`. Current cross-app captures are in `docs/review_3_2_14/screenshots/`. All are desktop-engine captures at phone-sized viewports, not photos of an Android device.


## Embedded Godot sandbox (2.9.0)

The on-device sandbox indexes live Godot classes from `ClassDB`, lazily inspects methods/properties/signals, validates `.gd` source through Godot's GDScript compiler path, writes bounded project-relative files and creates native `.tscn` scenes from a restricted node/property allow-list. The Studio Sources toolbox exposes API Explorer, starter 2D scene generation, local preview and script validation. It does not run arbitrary imported GDScript and is not a full Godot Editor. See `docs/EMBEDDED_GODOT_SANDBOX.md`.

## Optional PC companion bootstrap (0.1.0)

`companion/aoi_pc_bootstrap.py` is a standard-library one-file bootstrap. It creates a private config/workspace, registers startup for supported OS families, and exposes token-authenticated health/status. It binds to a Tailscale address when available and otherwise stays loopback-only. Remote file/command/Godot control is not enabled in this bootstrap milestone. See `docs/PC_COMPANION_BOOTSTRAP.md`.
