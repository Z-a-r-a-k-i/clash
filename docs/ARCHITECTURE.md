# Architecture

## Overview

Clash is a turn-based PvP strategy game. Two players queue actions during a shared turn timer; when both submit (or the timer expires), the resolver applies all queued actions deterministically and produces the resolved frame.

The architecture changes by milestone:

```text
M0 (current): no network, dev-only
+---------------------------+
|  Godot client (C#)        |
|  - Renders board          |
|  - Resolver runs locally  |
|  - Dev tooling drives     |
|    both players           |
+---------------------------+

M1: AI opponent added (still all client-side)

M2: network play, server-authoritative (server tech / protocol picked then)
+---------------+    wire protocol (TBD)    +---------------+
|  Godot client | <-----------------------> |  Server (TBD) |
|  (C#)         |  action queue / events    |               |
+---------------+                           +---------------+
```

Server technology and wire protocol are deferred to M2 per ADR 0006. Candidate paths (Go + protobuf, headless Godot/C#, Nakama, etc.) are evaluated in `docs/superpowers/specs/2026-04-29-entity-data-model-design.md`.

## Components

### Client (`client/`)

Godot 4.6+ project. C# is the primary language; GDScript is used only where it's meaningfully simpler. Responsibilities:

- Render the board, units, and resolved events.
- Let the player queue actions during the shared turn timer (move, attack, hold-fire toggle, target priority chain, build, train, research, surrender).
- At M0/M1: run the resolver locally.
- At M2 onward: submit the queued actions to the server, await the resolved frame, animate it. Authoritative game state moves to the server; client state becomes a faithful rendering of what the server sent plus the in-flight queue.

The resolver itself is a pure C# function over POCO data structures (see the design spec). It runs unchanged whether invoked locally (M0/M1) or on a server (M2+).

### Server (`server/`)

Empty at M0. Populated at M2 once the server stack is chosen. Likely responsibilities:

- **Matchmaker**: lobby, queue, pairing.
- **Resolver**: deterministic application of action queues against the current state (the same code as the client's M0 resolver, modulo any porting if the server is non-C#).
- **Connection hub**: lifecycle, encryption, message routing.

Stateless across matches except for in-memory match state. No DB at M0/M1 (defer until persistence is needed for ranking, accounts, replay storage).

### Protocol (`proto/`)

Empty at M0. If protobuf is chosen at M2 as the wire format, definitions go in `proto/clash/v1/`, generated code is committed to `client/generated/` (C#) and `server/internal/proto/` (the server's language), and `make generate` plus the pre-commit gate verify no drift. ADR 0007 covers this.

If a non-proto wire format is chosen at M2 (e.g. Godot-native serialization, JSON, msgpack), `proto/` may stay empty and ADR 0007 becomes moot.

## Spatial model

The map is a square-tile grid with small tiles. Units and buildings occupy a footprint of one or more tiles, defined per entity type. State for a placed entity is `{ origin: (x, y), footprint: (w, h) }`, not a single tile coordinate.

Pathfinding, range checks, vision (fog of war), and collision all assume multi-tile occupancy. Tile size and per-entity footprints are tuning knobs the prototype keeps configurable so playtesting can dial in the RTS-vs-grid feel.

## Turn Resolution

A turn proceeds as follows:

1. **Server: turn start.** Both clients receive `TurnStart { turn_index, timer_ms, current_state }`.
2. **Clients: queue.** Each player issues orders during the timer. An order can be: a per-unit action (move, attack, attack-move), a unit-mode toggle (hold-fire), a build/research/production command, or a group order applied to multiple units. Move orders persist across turns; the player only re-issues to override.
3. **Clients: submit.** Each client sends `SubmitTurn { actions[] }` when the player finishes, or an empty submission if the timer expires.
4. **Server: resolve.** Once both submissions are in, the resolver runs in **action-slot lockstep**:
   - Compute N = max action-queue length across all units this turn.
   - For each tick `k` from 1 to N:
     - Resolve every unit's `k`-th queued action. Within a tick, **all attacks fire before any moves execute**.
     - Target chains apply per attack: if the chosen target died earlier in the turn, fall back to the next chained target; if the chain is empty and the unit is not on hold-fire, fall back to the closest enemy in range.
     - Persistent move orders (from prior turns) advance one step per movement-budget per tick; attack-move halts to engage if an enemy enters range.
   - After the last tick, apply end-of-turn effects (production progress, research progress, building completion, status effects).
5. **Server: broadcast.** `ResolvedTurn { events[] }` goes to both clients.
6. **Clients: animate.** Each client plays the events in order. Once animation finishes, request the next turn.

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
