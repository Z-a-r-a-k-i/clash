# Protocol

> **Status: v0 playtest + tentative M2 direction.**
> The current playable network slice uses a same-version Godot Variant WebSocket codec in `client/scripts/network/`. The production M2 server technology and long-term wire format are still open; the protobuf notes below remain a candidate path, not the current implementation.

## v0 Godot WebSocket Slice

The v0 slice is intentionally narrow:

- Transport: plain WebSocket for local/tunneled playtests.
- Encoding: Godot Variant binary through `NetworkV0Codec`.
- Scope: same client/server code version only.
- State visibility: full authoritative state goes to both clients.
- Message boundary: game logic receives dictionaries at the adapter edge and typed runtime objects after decoding.

Implemented message kinds are: client hello, create match, join match, match joined, turn started, submit turn, turn resolved, match error, and disconnect notice. Type definitions stay in code.

See `docs/NETWORK-PLAYTEST.md` for local and tunnel smoke instructions.

## M2 Candidate Direction

Wire protocol between clash client and server. Authoritative type definitions live in `proto/clash/v1/`. This document describes how the wire is used at a high level; do not duplicate field lists here.

## Transport

WebSocket over TLS (in production). For local prototyping, plain WebSocket.

Two encoding modes:

- **JSON encoded protobuf** for control frames (lobby, matchmaking, auth). Easier to debug; size is not critical.
- **Binary encoded protobuf** for in match frames (turn state, action queue, resolved events). Smaller and faster.

The two modes share the same `.proto` definitions; only the wire encoding differs.

## Top level frame

```proto
message Envelope {
  string id = 1;          // request id (for request/response correlation)
  oneof payload {
    // ... full set defined in proto/clash/v1/
  }
}
```

## Message categories

| Category | Examples | Encoding |
|----------|----------|----------|
| **Lobby / matchmaking** | join queue, leave queue, match found, accept | JSON protobuf |
| **Turn lifecycle** | turn start, submit turn, resolved turn | Binary protobuf |
| **Out of band** | ping, error, reconnect | JSON protobuf |

## Versioning

Versioning is by folder: `proto/clash/v1/`. Breaking shape changes go to `proto/clash/v2/`. Both versions can run side by side during a migration window. (Note per ADR 0020: godobuf, the GDScript-side codegen, does not support proto `package` directives — use a name-prefix convention like `ClashV1TurnStart` to keep type identity unambiguous.)

Field number changes are free within a version (we have no on disk persistence yet). Once persistence is added, persisted enums and persisted messages are flagged in their `.proto` and renumbering requires confirmation.

## Reconnect

When a client disconnects mid match, it can reconnect with the same auth token and match id. The server holds match state in memory; on reconnect, it sends a `Resync { current_state, current_turn_phase }` so the client can resume. If the match is older than the reconnect window (e.g., 60s), the disconnected player forfeits.

(Skeleton; fleshes out as the protocol stabilises.)
