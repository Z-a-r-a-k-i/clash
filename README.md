# clash

Clash is a pre-alpha simultaneous-turn strategy game built with Godot and
GDScript. It combines an RTS economy, base construction, fog-of-war scouting,
army composition, and combat with deterministic turns: both players queue
orders, submit them blind, and then watch the shared result resolve.

## Current status

The repository contains a playable development build rather than a scaffold.
The current slice includes:

- solo play against three data-driven AI strategies;
- a symmetric main-and-natural 1v1 arena with contested center resources;
- gathering, construction, production, combat, abilities, fog of war,
  victory, and surrender;
- snapshots, deterministic replays, and an AI-vs-AI balance simulator;
- a shared solo/network match surface, player-facing HUD, and animated
  resolved movement; and
- trusted same-version multiplayer through an invite-code WebSocket server
  running in headless Godot.

The multiplayer server is a development playtest path, not the final M2
production stack. Accounts, matchmaking, reconnect, persistent hosting, a
shared turn timer, and anti-cheat hardening are not implemented.

## Layout

- `client/` — Godot project (GDScript per ADR 0020).
- `server/` — Reserved for a production server stack if M2 chooses one; the
  current trusted playtest server lives in `client/` so it can reuse the
  resolver and game data directly.
- `proto/` — Protobuf definitions, used only if proto is chosen as the wire format at M2.
- `docs/` — Architecture, protocol, decisions, contributing, design specs.
- `plan/` — Project plan tree (agent dispatchable).

## Getting started

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

Open `client/` in Godot 4.6 or newer. The main menu exposes Solo, Multiplayer,
and Replay. Run the automated suite with:

```text
make test GODOT=/path/to/godot
```

Run balance simulations with `make simulate ARGS="..."`; examples live in the
root `Makefile` and [M1 simulation plan](plan/m1/02-simulation-harness.md).

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Network playtest

The first trusted same-version PvP slice runs a headless Godot WebSocket server from `client/`. See [docs/NETWORK-PLAYTEST.md](docs/NETWORK-PLAYTEST.md).

## Near-term focus

The next useful milestone is an external playtest cycle: validate the newly
landed resolved-movement animation, make combat outcomes easier to read, and
collect structured feedback on controls, pacing, balance, and the
simultaneous-turn loop. See [docs/ROADMAP.md](docs/ROADMAP.md) for the longer
horizon.

## License

Private. All rights reserved.
