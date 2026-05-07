# Protocol

> **Status: tentative — pending M2 network-layer choice.**
> This doc describes a Go-server + WebSocket + protobuf path. At M0 the resolver lives in the Godot client and there is no network layer at all. The server technology and wire format are picked at M2 (candidate paths in `plan/m0/00-config-and-tunables.md`). If proto is chosen, the shape below is the starting point. If not, this doc gets rewritten or replaced.

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
