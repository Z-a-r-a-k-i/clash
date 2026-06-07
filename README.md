# clash

Turn based PvP strategy game. Godot client (GDScript) at M0/M1; network play arrives at M2 with server stack and wire protocol picked at that point. Mobile and web.

> Pre alpha. Repo scaffold only; no playable build yet.

## Layout

- `client/` — Godot project (GDScript per ADR 0020).
- `server/` — Server stack (deferred until M2; technology picked then — see ADR 0006).
- `proto/` — Protobuf definitions, used only if proto is chosen as the wire format at M2.
- `docs/` — Architecture, protocol, decisions, contributing, design specs.
- `plan/` — Project plan tree (agent dispatchable).

## Getting started

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Network playtest

The first trusted same-version PvP slice runs a headless Godot WebSocket server from `client/`. See [docs/NETWORK-PLAYTEST.md](docs/NETWORK-PLAYTEST.md).

## License

Private. All rights reserved.
