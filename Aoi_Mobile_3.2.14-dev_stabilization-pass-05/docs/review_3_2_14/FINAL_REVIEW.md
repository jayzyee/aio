# Aoi Mobile 3.2.14-dev — final review for stabilization pass 05

**Review target:** Godot 4.8 beta 1, Linux x86_64  
**Viewport:** 720 × 1520  
**Capture folder:** `final_pass/`

## Screens reviewed

| Screen | Capture | Review note |
|---|---|---|
| Chat | `chat_720x1520.png` | Full-screen conversation, restrained first-run empty state, composer stays anchored above the lower inset. |
| Project home | `projects_720x1520.png` | Saved project is visible; absence of a playable build is explicit; Continue with Aoi remains the primary action. |
| Workbench | `workflow_720x1520.png` | Project-specific summary matches the game brief; saved workflow and pending review context remain visible. |
| Creation card | `creation_card_720x1520.png` | One coherent activity surface; status and 20% progress come from the saved five-task plan, not an invented animation percentage. |
| Model selector | `model_selector_720x1520.png` | Existing neutral sheet, search field and compact first-run state; draggable header and close control remain clear. |
| GitHub | `github_connection_720x1520.png` | Fine-grained token guidance and permissions are shortened, with token replacement verified before save. |
| Cloud Linux | `linux_connection_720x1520.png` | Explicitly identifies GitHub-hosted Linux, preserves the existing connection-sheet design, and exposes create/select/refresh/open/use in one scrollable sheet. |

## Changes arising from review

- Removed the remaining wording that could imply a personal Linux/desktop connection.
- Reworked GitHub permission guidance into a smaller set of actions without removing the permission names needed by the API.
- Reworked cloud setup copy to separate GitHub credentials from the independent bridge key and repository secret.
- Corrected the Workbench fixture's unrelated project summary.
- Tightened `ChatScreen` delta, notice and completion ownership to prevent a second screen from consuming another screen's response.
- Removed temporary debugging output from the shipped review scripts.

## Release boundary

The app opens under the Library-provided Godot build and the reviewed desktop captures are fresh. The live GitHub/Codespaces handshake and physical Android validation remain pending the user's own GitHub connection and target-device review. A playable-game acceptance pass remains a separate requirement for each generated game; no empty workspace, scaffold or screenshot is treated as a finished game.
