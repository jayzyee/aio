# Aoi PC Companion bootstrap — 0.1.0

The PC companion is optional. Aoi Mobile and the embedded Godot sandbox continue to work when the PC is offline or unavailable.

## One-file setup

Transfer `companion/aoi_pc_bootstrap.py` to the PC. It uses only the Python standard library.

```bash
python aoi_pc_bootstrap.py install
python aoi_pc_bootstrap.py status
python aoi_pc_bootstrap.py uninstall
```

`install` creates an AoiPC data directory, a workspace folder, a random bearer token and a startup entry. It supports Windows Startup, macOS LaunchAgents and Linux systemd user services in code. The current automated test exercises the install-without-startup path and authenticated HTTP status service on Linux; OS-specific startup registration has not yet been physically verified on Windows/macOS/Linux desktops.

## Network and security model

- If Tailscale is installed and has an IPv4 address, the service binds only to that Tailscale interface. This supports same-network and different-network access through the private tailnet, subject to Tailscale account/device policy. If the tailnet interface starts late or its IP changes after reboot, the service retries and refreshes the binding.
- If Tailscale is absent, it binds to `127.0.0.1` only. It is not reachable from the phone over ordinary Wi-Fi. Install/sign in to Tailscale on both devices and rerun `install` to enable tailnet binding.
- Do not port-forward the service or expose it to public Wi-Fi. Do not use an unauthenticated LAN listener.
- `/health` is a minimal unauthenticated liveness endpoint. `/v1/status` requires `Authorization: Bearer <token>` and uses constant-time token comparison.
- The token is stored in the companion config file; on POSIX systems the file is chmod 0600 and its parent directory chmod 0700. Protect the PC account and config file.
- If the PC powers off, the service disappears. Startup registration is intended to restart it on the next boot. Aoi Mobile must show offline/last-seen state and must not block local work.

## Deliberate current limitation

This 0.1.0 bootstrap exposes only health and status. It does **not** expose shell, file writes, Godot run/stop, screenshots or arbitrary command execution yet. Those capabilities will be added only after device pairing, per-device key rotation, permission scopes, command approval, bounded execution, audit logs and a stop mechanism are implemented and tested. The current mobile Plugins card is an honest setup-plan/status entry, not a live PC connection.
