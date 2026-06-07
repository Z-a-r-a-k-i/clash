# Network Playtest

This is the first same-version PvP slice. It is for trusted development playtests, not production multiplayer.

## What it does

- Runs an authoritative headless Godot server from the existing `client/` project.
- Hosts invite-code matches for two peers.
- Assigns player slots `0` and `1`.
- Resolves a turn only after both slots submit.
- Broadcasts the full authoritative `MatchState` and resolver events to both clients.
- Saves a same-version `MatchReplay` journal under `user://tmp/network_replays` by default.

The v0 wire format is Godot Variant binary with an adapter boundary in `client/scripts/network/network_v0_codec.gd`. It intentionally allows Godot objects and is only compatible with the same client/server code version.

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

Client UI entry is `res://scripts/network/network_play_mode.gd`. It builds a network HUD plus a shared `MatchPlaySurface`; dev replay and snapshot controls are intentionally absent.

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
3. Connect both clients to the same server URL.
4. On client A, create a match and copy the invite code.
5. On client B, join with that code.
6. Submit one turn for each player.
7. Confirm both clients receive the same resolved state and events.
8. Repeat with one client connecting through the tunnel URL.

## Current Limits

- No accounts, matchmaking, reconnect, TLS hosting, persistence, shared turn timer, or anti-cheat hardening.
- Server sends full authoritative state to both clients.
- Clients and server must run the same code version.
