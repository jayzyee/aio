# Aoi Studio — project-agnostic mobile development workspace

Aoi Studio is a project workspace inside Aoi Mobile. It is designed to work with **the project selected by the user**, not a particular game, AI, language or framework. a Godot game, a Python research project, a Node application or another supported project remains an ordinary separate project folder. Aoi does not bundle project-specific business logic or training modules.

The phone is the primary interface and remains useful without a remote runtime. For full Godot game creation, Aoi can connect to a remote cloud Linux environment. GitHub Codespaces is the recommended first provider; your personal computer does not need to stay online. See [`LINUX_GITHUB_SETUP.md`](LINUX_GITHUB_SETUP.md) for the current setup.

## Project workflow

1. **Create or import.** Create a local workspace on the phone or import an accessible folder. Import copies the selected project into Aoi's app-private workspace; it does not silently edit the original folder. The importer preserves project files including `.aoi/tasks.json`, while excluding generated/build/cache directories and enforcing file-count, depth and size limits.
2. **Add sources.** Add scripts, scenes, assets, data, documents or other project files. The Sources view keeps the build composer visible below the project tree. The tree exposes the project's `.aoi` task metadata but hides sensitive hidden files such as `.env`.
3. **Describe the work.** Use the project-bound Chats composer to ask Aoi to inspect, build, debug, refactor, train, test or document the selected project. Aoi must first inspect actual files and entry points instead of assuming the project's purpose.
4. **Follow progress.** The compact activity sheet reports Plan → Build → Run → Review. It is an agent activity indicator; it does not imply that a game is running. File writes, task execution and other mutations require explicit approval.
5. **Inspect changes.** Review the project tree, read supported text files, inspect run logs and compare generated artifacts. Project-specific knowledge remains attached to that project; personal Knowledge Library notes remain separate.
6. **Run visual projects.** Use the local generated-scene preview for the supported scene subset. Full arbitrary Godot projects require a compatible Godot runtime provider; the app must state when that runtime is unavailable rather than faking a launch.
7. **Run headless projects.** Use Run & results to discover tasks declared by the selected project. A task can produce progress, checkpoints, metrics, logs and artifacts without opening a game preview. This is intended for tests, data processing, simulations, training loops and reports.
8. **Review and continue.** Ask Aoi to inspect the actual outputs, diagnose problems, update the project, rerun the task and compare results. Completed runs remain associated with their project.

## Project-owned headless task contract

Projects may declare their own optional tasks in `.aoi/tasks.json`. This manifest belongs to the imported project, not to Aoi's built-in code. Aoi discovers it generically.

Supported runtime identifiers:

- `gdscript_steps`: cooperative, bounded on-device GDScript task. Available without a PC.
- `python_companion`: Python task that requires a configured and connected cloud Linux/Python runtime.
- `shell_companion`: shell task that requires a configured and connected cloud Linux runtime.
- `godot_project`: full Godot project execution that requires a compatible Godot runtime provider.

A minimal manifest looks like:

```json
{
  "schema_version": 1,
  "tasks": [
    {
      "id": "analyze-data",
      "name": "Analyze data",
      "description": "Process the project's dataset and write a report.",
      "runtime": "gdscript_steps",
      "script": "tasks/analyze.gd",
      "parameters": [],
      "limits": {"max_runtime_seconds": 600}
    }
  ]
}
```

A `gdscript_steps` task is a project-owned `RefCounted` script implementing:

```gdscript
extends RefCounted

func start(context: Dictionary, parameters: Dictionary, checkpoint: Dictionary) -> Dictionary:
    return {"ok": true, "state": checkpoint, "detail": "Initialized"}

func step(context: Dictionary, state: Dictionary, budget_units: int) -> Dictionary:
    # Do a bounded amount of work and return a serializable checkpoint.
    return {
        "ok": true,
        "state": state,
        "progress": 0.0,
        "detail": "Working",
        "done": false,
        "metrics": {},
        "artifacts": {}
    }
```

The task context provides the project root, project/job IDs, validated parameters, logging, progress reporting, project-file reading, artifact writing, cancellation checks and bounded file listing. `step()` must return quickly and save resumable state in its `state` dictionary. Aoi stores outputs under the run's artifact directory and writes a report, result, metrics, checkpoint and log when available.

**Security boundary:** on-device `gdscript_steps` executes trusted project code inside Aoi's process with the app's permissions. This is not an operating-system-isolated sandbox. Aoi requires approval before running or resuming it, applies step/runtime/checkpoint/artifact limits, and must not automatically run arbitrary imported GDScript. Review task source before approval. Python, shell and full-project tasks are marked unavailable until the matching companion/runtime is actually connected.

## Optional cloud Linux runtime

Aoi's current remote execution provider is a token-protected Linux bridge that can run inside GitHub Codespaces. The included `.devcontainer` installs the project-matched Godot runtime and the bridge dependencies, then starts the service on port 8765. Aoi can create a project inside the cloud workspace, inspect and edit files, launch/stop Godot, check its process state, read logs and capture the live display.

Aoi can now list, create, select and open GitHub Codespaces from the existing cloud-connection sheet. The user still prepares the private GitHub repository, grants the fine-grained token permissions, adds the generated `AOI_BRIDGE_TOKEN` repository secret and reviews forwarded-port visibility once. Before provisioning, Aoi checks repository-eligible machine sizes and selects the smallest available Linux option. GitHub Actions remains a temporary job runner, not an interactive always-on bridge; see [`LINUX_GITHUB_SETUP.md`](LINUX_GITHUB_SETUP.md) for the full setup.

Security: the Codespaces forwarded port is internet-reachable when set to Public. Every bridge route requires the 256-bit token, but the bridge is not an OS sandbox. Shell commands run with the Codespaces user's permissions. Use a private repository, unique key, minimum GitHub permissions and stop the Codespace when it is not needed.

A local Linux host or Termux bridge may be used as an advanced option, but neither is required by the current product workflow. The earlier paired-PC design documents are historical references only.

## Godot EditorPlugin

The source project includes `addons/aoi_studio/`, a desktop Godot EditorPlugin. It can add a dock inside a Godot editor on a PC, but it does not run inside the exported Android app. It is an optional PC-side integration, not a prerequisite for Aoi Studio on the phone.

## Current limits

- Aoi does not embed the complete Godot Editor in Android.
- The local preview supports the generated scene subset; arbitrary imported projects may require an external Godot runtime.
- On-device task scripts are trusted code inside the application process, not OS-isolated execution.
- Python/shell/full Godot tasks require the cloud Linux runtime (or another explicitly configured compatible provider) to be connected.
- The Codespaces path requires one-time repository/secret/port setup and is subject to included compute and storage quotas.
- Simulated phone-size tests do not replace physical testing on each Android device, keyboard, cutout and gesture-navigation configuration.
