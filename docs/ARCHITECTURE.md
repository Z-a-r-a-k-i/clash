# Architecture

## Overview

Clash is a turn-based PvP strategy game. Two players queue actions and submit
them blind; the resolver then applies both queues deterministically and produces
the resolved frame. A shared turn timer is part of the production design but is
not implemented in the current solo or trusted-network slice.

The architecture changes by milestone. A same-version Godot WebSocket slice now exists for dev playtests before the production M2 server decision:

```text
M0/M1 baseline: local/dev play
+---------------------------+
|  Godot client (GDScript)  |
|  - Renders board          |
|  - Resolver runs locally  |
|  - Dev tooling drives     |
|    both players           |
+---------------------------+

First network slice: trusted Godot WebSocket playtest
+---------------------------+      Variant v0      +---------------------------+
|  Godot client             | <------------------> |  Headless Godot server    |
|  - Renders authoritative  |                       |  - Invite-code sessions   |
|    MatchState             |                       |  - Resolver authoritative |
|  - Submits own slot only  |                       |  - Replay journal capture |
+---------------------------+                       +---------------------------+

M2: production network play, server-authoritative (server tech / protocol picked then)
+---------------+    wire protocol (TBD)    +---------------+
|  Godot client | <-----------------------> |  Server (TBD) |
|  (GDScript)   |  action queue / events    |               |
+---------------+                           +---------------+
```

Server technology and wire protocol are deferred to M2 per ADR 0006. Candidate paths (Go + protobuf, headless Godot/GDScript, Nakama, etc.) are evaluated in `plan/m0/00-config-and-tunables.md`.

## Components

### Client (`client/`)

Godot 4.6+ project. GDScript only (per ADR 0020). Responsibilities:

- Render the board, units, and resolved events.
- Let the player queue actions before submitting (move, attack-ground, target
  enemy, gather, build, train, abilities, cancel, surrender, and box/group
  orders). The generic resolver supports data-driven research, but the current
  roster exposes no research options.
- At M0/M1: run the resolver locally.
- In the trusted network slice: submit the queued actions to the headless Godot
  server, await the authoritative resolved frame, and animate resolved movement.
  Production M2 keeps this authority boundary even if the stack or wire format
  changes.

The resolver itself is a pure GDScript function over plain-data structures (see
the design spec). It runs in-client for local/solo play and in the headless
Godot server for the trusted network slice. If production M2 stays on
Godot/GDScript, the resolver remains shared unchanged; otherwise a port is
needed (the design's plain-data shape keeps that port mechanical).

### Network playtest (`client/scripts/network/`)

The first PvP implementation is a headless Godot server that runs from the existing `client/` project. This keeps scenario loading, Resources, registries, resolver code, and replay/session types identical across client and server while the game is still pre-production.

It uses a v0 Godot Variant WebSocket codec behind an adapter boundary. This is not a compatibility promise; it is a same-code-version playtest path that can later be replaced by Go + protobuf, headless Godot, Nakama, or another M2 server choice.

### Server (`server/`)

Still reserved for the production M2 server stack once that technology is chosen. Likely responsibilities:

- **Matchmaker**: lobby, queue, pairing.
- **Resolver**: deterministic application of action queues against the current state (the same code as the client's M0 resolver if the server is headless Godot/GDScript, or a port if the server stack differs).
- **Connection hub**: lifecycle, encryption, message routing.

Stateless across matches except for in-memory match state. No DB until persistence is needed for ranking, accounts, replay storage, or reconnect windows.

### Protocol (`proto/`)

Empty at M0. If protobuf is chosen at M2 as the wire format, definitions go in `proto/clash/v1/`, generated code is committed to `client/generated/` (GDScript via [godobuf](https://github.com/oniksan/godobuf)) and `server/...` (whatever the server side needs), and `make generate` plus the pre-commit gate verify no drift. ADR 0007 covers this.

If a non-proto wire format is chosen at M2 (e.g. Godot-native serialization, JSON, msgpack), `proto/` may stay empty and ADR 0007 becomes moot. Per ADR 0020, godobuf does not support proto `package` directives — name-prefix convention (`ClashV1TurnStart`, etc.) replaces it.

## Spatial model

The map is a square-tile grid with small tiles. Units and buildings occupy a footprint of one or more tiles, defined per entity type. State for a placed entity is `{ origin: (x, y), footprint: (w, h) }`, not a single tile coordinate.

Pathfinding, range checks, vision (fog of war), and collision all assume multi-tile occupancy. Tile size and per-entity footprints are tuning knobs the prototype keeps configurable so playtesting can dial in the RTS-vs-grid feel.

## Turn Resolution

The target production flow is below. The current trusted slice follows the same
submit/resolve/broadcast boundary but starts without a timer and waits for both
explicit submissions.

A turn proceeds as follows:

1. **Server: turn start.** Both clients receive `TurnStart { turn_index, timer_ms, current_state }`.
2. **Clients: queue.** Each player issues orders during the timer. An order can be: a movement intent, an attack-ground intent, a targeted enemy focus, a gather/build/research/production command, an ability, cancel, or a group order applied to multiple units. Long-range movement is a client/input assist: unfinished destinations are re-submitted as visible move orders on later turns, and the player only re-issues to override.
3. **Clients: submit.** Each client sends `SubmitTurn { actions[] }` when the player finishes, or an empty submission if the timer expires.
4. **Server: resolve.** Once both submissions are in, the resolver applies immediate mode/order updates, then resolves the turn in deterministic phases:
   - Self-target abilities resolve first for units that submitted them.
   - Every combat unit may fire at most once from its current position, preferring its focused target and otherwise falling back to the closest enemy in range.
   - Player-issued Move does not stop early for enemies. Attack-ground movement stops before moving when a visible enemy is already in weapon range.
   - Movement resolves after attacks. Submitted move orders spend the unit's per-turn movement budget independently from combat.
   - The resolver does not advance hidden standing movement; clients submit any assisted follow-up move as normal turn input.
   - End-of-turn effects then run: gather income ticks, production progress, research progress, building completion, cooldowns, status effects, and win checks.
5. **Server: broadcast.** `ResolvedTurn { events[] }` goes to both clients.
6. **Clients: present.** Each client animates resolved movement batches in event
   order, then shows the final authoritative state. Combat/status presentation
   is still incomplete; once movement animation finishes, the next turn can
   begin.

The win check runs after end-of-turn effects: a player with no buildings loses; a surrender flag in the next `SubmitTurn` ends the match immediately.

## Determinism

The resolver must be deterministic. Same `(state, queue_a, queue_b)` triple must always produce the same `events[]`. Implications:

- No RNG by default. If randomness is later introduced for specific mechanics, it flows through a seeded PRNG whose seed lives in the turn frame.
- Iteration order over collections must be stable (sorted by entity ID, not map iteration order).
- The speed stat affects movement distance only — it does **not** affect attack order. Within a tick, attacks resolve in stable entity-ID order.

Determinism is the foundation for replays, network reconciliation, and (later) tournament integrity. The user-facing benefit matters more, though: players can mentally model a turn's outcome without comparing stat sheets.

## Authoritative state

The server holds the canonical match state. Clients render a copy. Any disagreement is resolved by trusting the server. This eliminates client side cheats and the need for rollback netcode.

The simultaneous turn model makes this cheap: clients don't predict, they wait for the server to send the resolved frame. Latency is bounded by the longer of the two players' submit times plus one round trip.

## Decisions log

See [docs/DECISIONS.md](DECISIONS.md).
