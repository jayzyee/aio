# Aoi cloud Linux workspace and GitHub setup

Aoi uses two separate connections:

- **GitHub** lets Aoi browse repositories and, when explicitly enabled, create a remote Linux workspace.
- **GitHub Codespaces** supplies the remote Linux machine where Aoi can inspect projects, run Godot, launch games and capture the running window.

Your phone remains the Aoi interface. The Codespace runs in GitHub's cloud; it is not your personal computer, a Termux session or a Linux machine you must maintain.

## 1. One-time repository preparation

A Codespace is created from a GitHub repository, so Aoi's cloud environment files must exist in the repository before the first creation.

1. Create or choose a **private GitHub repository** for the Aoi cloud workspace.
2. Upload the Aoi project source into its root, preserving `.devcontainer/` and `companion/` exactly. The repository must contain `.devcontainer/devcontainer.json`, `.devcontainer/Dockerfile`, and the `companion/` setup/bridge scripts.
3. Commit and push those files to the branch you intend to use.
4. In Aoi, open **Connections → GitHub** and connect a fine-grained personal access token.
5. Restrict the token to the repository that contains the Aoi cloud environment. Grant:
   - **Metadata: Read-only** for repository lookup.
   - **Codespaces: Read and write** to list and create Codespaces.
   - **Codespaces metadata: Read** so Aoi can inspect machine types and choose the smallest eligible Linux machine before provisioning.
   - **Contents: Read-only** only when private source browsing is needed. Use **Contents: Read and write** only when you intend to approve repository writes.
6. Open the repository's **Settings → Secrets and variables → Codespaces** and create a repository secret named `AOI_BRIDGE_TOKEN`. Aoi generates this 64-character hexadecimal key in its **Cloud Linux workspace** connection sheet. Add the exact value there before creating the Codespace. This secret is separate from the GitHub PAT.

Do not commit either secret, paste them into a project README, or include them in shell commands. Aoi stores the GitHub PAT and cloud bridge key in its protected local credential store.

## 2. Create the remote Linux machine from Aoi

1. Open **Connections → Cloud Linux workspace**.
2. Enter the repository as `owner/repository`; leave the branch blank to use the default branch, or enter a branch that contains the `.devcontainer` files.
3. Confirm that the GitHub PAT is verified and that the `AOI_BRIDGE_TOKEN` repository secret has been saved.
4. Select **Create GitHub Codespace**. Aoi first asks GitHub which Linux machine types are eligible for that repository and branch, then selects the smallest available machine by CPU count, memory and storage. It does not automatically retry the create request.
5. When GitHub returns the Codespace, Aoi saves its identity and forwarded bridge address. Allow the dev-container setup to finish. Use **Refresh existing workspaces** to reconcile the server-side state if the create response was interrupted.
6. Choose the workspace and select **Use selected workspace**. **Open selected Codespace** opens GitHub's Codespaces page so you can start a stopped machine or inspect its setup.
7. Select **Save and test connection** after the workspace has started and port 8765 has been forwarded. Aoi checks bridge authentication and whether the pinned Godot runtime is available.

Aoi uses the standard forwarded HTTPS address for port 8765. The included `postAttachCommand` attempts to make the port Public. If repository or organization policy blocks this, open the Codespace's **Ports** panel and set port `8765` to Public manually. The port is internet-reachable, but every bridge route requires the 256-bit `X-Aoi-Token` secret.

## 3. What the cloud workspace installs

The included dev container:

- Installs the official Godot 4.8 beta 1 Linux x86_64 binary and verifies its published SHA-256 before use.
- Installs the Python screenshot dependencies and creates a virtual X display for real application captures.
- Starts the authenticated bridge on port 8765 and restarts it when the Codespace starts.
- Uses a dedicated Aoi workspace directory under the Codespace user's home, separate from the repository checkout.
- Runs the credential-bearing bridge as the Codespaces `vscode` account, but executes project shell commands and Godot as a separate low-privilege `aoi-runner` account. The accounts share only the Aoi workspace group for project files.
- Passes project code a clean environment without `AOI_BRIDGE_TOKEN`, `GH_TOKEN` or `GITHUB_TOKEN`, and kills timed-out process groups rather than leaving child build processes behind.
- Supports workspace-scoped file listing, reading, searching and writing; bounded shell execution; Godot project creation, launch, stop, headless verification, logs and screenshot capture.

A workspace/project scaffold is not a finished game. Aoi must still implement the requested project, run it, inspect fresh captures, correct defects and verify playability before it can call the result complete.

## 4. Free usage and cost controls

GitHub Free personal accounts currently include **120 Codespaces core-hours and 15 GB-month of storage**. Compute is charged in core-hours: a 2-core machine uses two core-hours for each active hour, while a 4-core machine uses four. The monthly included compute is therefore not a fixed number of clock hours; actual time depends on the smallest machine GitHub offers for that repository and region. Storage is a separate quota.

Aoi requests a 30-minute idle timeout and chooses the smallest eligible Linux machine returned by GitHub. Stop the Codespace when you finish. Once included compute or storage is exhausted, GitHub may prevent creating or opening Codespaces until the quota renews unless a payment method and spending are configured. Check the GitHub billing page before enabling paid usage.

- **GitHub Codespaces:** preferred for an interactive Linux environment and real Godot desktop captures.
- **GitHub Actions:** useful for temporary build/test/package jobs, but the runner is discarded after each workflow and cannot replace the persistent interactive bridge.
- **Oracle Cloud:** deliberately optional and deferred. Aoi does not require an Oracle account to plan or build a project when GitHub Codespaces is configured.

## 5. Security boundary

The forwarded Public port is reachable from the internet by anyone who knows its URL. Every bridge route requires `X-Aoi-Token`; the bridge rejects short secrets, uses constant-time key comparison and temporarily locks out a source after repeated failed authentication. In cloud mode, the bridge process and project runner use separate Linux accounts. Project code cannot read the bridge's environment or GitHub CLI credentials through the normal process boundary, and commands are limited to the shared Aoi workspace for file writes. This is defense in depth, not a hardened hostile-code sandbox: project code still has network access and can read or modify its workspace. Keep the repository private, use a unique random cloud key, do not commit secrets, and stop the Codespace when finished. Do not put unrelated personal credentials or sensitive data in the workspace.

## 6. Troubleshooting

- **Codespaces machine lookup returns 403:** add `Codespaces metadata: Read` to the fine-grained PAT for that repository, then reconnect the token.
- **Codespace creation returns 403:** add `Codespaces: Read and write` and include the repository in the PAT's repository access.
- **Aoi says the previous create result is unknown:** refresh existing Codespaces before trying again. Aoi blocks a second create until the list refresh resolves the ambiguous request.
- **Codespace starts but Aoi cannot connect:** confirm port 8765 is Public and use the forwarded HTTPS address, not localhost.
- **401 Unauthorized:** the Aoi cloud key and the `AOI_BRIDGE_TOKEN` repository secret differ. Update both to the same 64-character value and restart the Codespace.
- **The isolated project runner is missing:** rebuild the Codespace container so the `aoi-runner` account and shared workspace group are created, then reconnect.
- **Godot is missing:** rebuild the Codespace so `codespaces_setup.sh` can install and verify the official binary.
- **Godot launches but no screenshot returns:** confirm setup installed Xvfb, `mss` and Pillow; inspect the Codespace terminal output.
- **GitHub token rejected:** reconnect with a valid fine-grained token and ensure its repository selection and permissions include the requested action.
- **Included quota exhausted:** stop/delete unused Codespaces and wait for the monthly allowance to renew, or review GitHub's budget/payment settings before allowing paid usage.

## Official references

- GitHub Codespaces REST API: https://docs.github.com/en/rest/codespaces/codespaces?apiVersion=2026-03-10
- GitHub Codespaces machine types API: https://docs.github.com/en/rest/codespaces/machines?apiVersion=2026-03-10
- GitHub Codespaces included usage: https://docs.github.com/en/billing/reference/product-usage-included
- GitHub Codespaces usage guidance: https://docs.github.com/en/codespaces/troubleshooting/troubleshooting-included-usage
- GitHub Codespaces forwarding ports: https://docs.github.com/en/codespaces/developing-in-a-codespace/forwarding-ports-in-your-codespace
- GitHub Codespaces dev containers: https://docs.github.com/en/codespaces/setting-up-your-project-for-codespaces/introduction-to-dev-containers
- GitHub Actions hosted runner limits: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- Fine-grained token permissions: https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens
- Godot 4.8 beta 1 Linux release assets and checksums: https://github.com/godotengine/godot-builds/releases/tag/4.8-beta1
