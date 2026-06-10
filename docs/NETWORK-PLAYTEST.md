# Network Playtest

This is the first same-version PvP slice. It is for trusted development playtests, not production multiplayer.

## What it does

- Runs an authoritative headless Godot server from the existing `client/` project.
- Hosts invite-code matches for two peers.
- Assigns player slots `0` and `1`.
- Resolves a turn only after both slots submit.
- Broadcasts the full authoritative `MatchState` and resolver events to both clients.
- Saves a same-version `MatchReplay` journal under `user://tmp/network_replays` by default.

The v0 wire format is Godot Variant binary with an adapter boundary in `client/scripts/network/network_v0_codec.gd`. The codec normalizes messages into primitive Variant containers and rebuilds a small whitelist of Clash runtime objects. It is only compatible with the same client/server code version.

## Run A Local Server

PowerShell:

```powershell
$godot = "C:\Program Files\Godot_v4.6.1-stable_mono_win64\Godot_v4.6.1-stable_mono_win64_console.exe"
& $godot --headless --path client --script scripts/network/headless_server.gd -- --port=9087 --bind=127.0.0.1 --scenario=res://data/scenarios/mvp_map.tres
```

Then connect clients to:

```text
ws://127.0.0.1:9087
```

The project main scene opens `res://scenes/main_menu.tscn`. Choose `Multiplayer` to open the lobby scene. The lobby auto-connects to the last server URL you used, or `ws://127.0.0.1:9087` by default. You can still edit the URL and press `Connect` to use a tunnel or alternate local port. Create/join there, then play in the dedicated network match HUD. Dev replay and snapshot controls stay out of multiplayer.

## Tunnel Smoke

Bind the server locally, then expose the port through an HTTP tunnel that supports WebSockets.

Cloudflare Quick Tunnel (Cloudflare documents the quick tunnel command as `cloudflared tunnel --url http://localhost:<port>` at https://try.cloudflare.com/):

```powershell
cloudflared tunnel --url http://localhost:9087
```

Use the returned `https://...trycloudflare.com` hostname as a WebSocket URL by switching the scheme to `wss://`.

ngrok (ngrok documents WebSocket servers through HTTP endpoints and the `ngrok http <port>` tunnel shape at https://ngrok.com/docs/http and https://ngrok.com/docs/using-ngrok-with/websockets):

```powershell
ngrok http 9087
```

Use the returned HTTPS forwarding hostname as `wss://...`.

## Manual Smoke Checklist

1. Start the headless server.
2. Open two clients.
3. Choose `Multiplayer` in both clients.
4. Connect both clients to the same server URL.
5. On client A, create a match and copy the invite code.
6. Confirm client A stays in the lobby and the map does not open yet.
7. On client B, join with that code.
8. Confirm both clients enter the match after client B joins.
9. Queue orders in both clients and verify order previews render.
10. Toggle `Show All Orders` and verify queued orders from all local units can be shown/hidden.
11. Toggle `Hide UI` and verify units behind the HUD can be clicked, then toggle `Show UI`.
12. Toggle `Submit Turn` on, then off before the other player submits, and verify readiness can be cancelled.
13. Queue a long-distance move or multiple queued orders, submit, and confirm follow-up orders remain queued on the next turn.
14. Submit from one client and confirm it shows `Submitted. Waiting for opponent.`
15. Submit from the second client and confirm both clients advance to the next turn.
16. Confirm a trained unit starts/completes and a moved unit changes authoritative position in both clients.
17. Confirm both clients receive the same resolved state and events.
18. If a submit is rejected, confirm the status shows the server error and the `Submit Turn` button becomes available again.
19. Press Escape in a match and confirm the menu can resume, leave back to the multiplayer lobby, or return to the main menu.
20. Leave from one client during an active match and confirm the remaining player receives the win and a centered `Victory` overlay.
21. Repeat with one client connecting through the tunnel URL.

## Automated Parity Smoke

Run the focused live WebSocket smoke after multiplayer command changes:

```powershell
$godot = "C:\Program Files\Godot_v4.6.1-stable_mono_win64\Godot_v4.6.1-stable_mono_win64_console.exe"
& $godot --headless --path client --script scripts/_dev/run_test_network_live_headless.gd
```

This starts an in-process server on a non-default test port, connects two real network clients, creates and joins a match, submits both slots, and asserts live move/train results apply identically on both clients. It is also part of `make test`.

## Current Limits

- No accounts, matchmaking, reconnect, TLS hosting, persistence, shared turn timer, or anti-cheat hardening.
- Server sends full authoritative state to both clients.
- Clients and server must run the same code version.
