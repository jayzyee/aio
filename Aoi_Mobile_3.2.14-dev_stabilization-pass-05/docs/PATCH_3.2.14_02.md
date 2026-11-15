# Aoi Mobile 3.2.14-dev — connectivity and workflow stabilisation pass 02

## What changed

### Model selector and shared sheets

- Raised the resting sheet height to 88% of the viewport and made the expanded snap point 94%.
- Made the entire grip area a 48 px touch target and allowed dragging from the header's empty area, not only the tiny visual grip.
- Corrected the scroll-height budget to reserve the full 168 px used by the sheet's top margin, grip row, header, spacing and bottom margin. Long forms now scroll inside the available viewport rather than calculating against missing chrome.
- Kept the close control independent from header dragging and respected reduced-motion settings.

### GitHub

- Connected the visible GitHub action to a real account-verification request (`GET /user`). The UI no longer points to a missing `connect_github` method.
- A replacement token is stored only after GitHub returns a valid account identity; a failed replacement does not destroy the previous saved token.
- Public repository discovery/read requests can run without a PAT. Private reads and repository mutations use a verified token; branch, file, issue and pull-request mutations remain separately approval-gated.
- Authentication status is now tied to a SHA-256 fingerprint of the exact verified token. A stale username or an old token cannot make a different token appear authenticated.
- Superseded verification requests cannot update connection state after a newer request has started.

### Linux / Termux pairing

- Removed the fake PC address from the actual field value. The example address is now placeholder text only and cannot accidentally be saved as a real host.
- Added strict URL, IPv4 octet and port validation and clearer messages for unreachable hosts, token mismatch, outdated companion endpoints and companion-side errors.
- Reset previous health status whenever pairing details are edited, and show a recent verification as time-limited rather than implying a device remains connected indefinitely.
- A late `/health` response is ignored when the saved address or token has changed since the request started.
- Successful health checks can report whether the paired machine exposes a Godot runtime; file and terminal access remain available when Godot is not installed.

### Building without a paid search key

- New game/app project workspaces no longer hard-stop when Brave Search is not connected.
- Aoi proceeds in a clearly marked limited-research mode using the supplied brief, saved project evidence and stable background knowledge. It must not claim live-source research or invent citations.
- When Brave Search is connected, the source-backed research gate remains in place.

## Runtime evidence and limits

The existing 720 × 1520 Chat and Connections captures in `docs/review_3_2_14/screenshots/` were inspected as the pre-change baseline. This workspace does not contain a Godot executable, and the official Godot 4.8-beta1 Linux binary could not be downloaded from this network. Therefore this pass does **not** claim a fresh post-change Godot screenshot, successful Godot import, physical-device gesture validation, or release readiness. The patch is source-level work awaiting a matching Godot 4.8-beta1 runtime for actual screen capture and interaction review.
