---
status: done
depends_on:
  - ./07b1-renderer-and-camera.md
---

# Input + manual turn advance

Second of four sub-PRs splitting the visual half of plan node 07. After this
lands, a developer can load a scenario, select entities, queue the core M0
orders for either player, and manually resolve turns through the existing
deterministic resolver.

## Scope

This is a dev-only control surface, not a player-facing mode. It exists to make
the M0 systems operable before fog, AI, networking, or a polished command UI.

Implemented order surface:

- `MOVE` to a tile.
- `ATTACK` against a live enemy entity.
- `GATHER` against a resource source or refinery.
- `SubmitTurn.surrender` for the active player.
- Manual `Resolve` that calls `Resolver.resolve(...)`, renders the returned
  state/events, and clears both pending submissions.

Deferred to later plan nodes or follow-up work:

- Build placement, train, research, cancel, hold-fire, and attack-move controls. That belongs to 07b4.
- Ability controls and resolver effects. That belongs to 07b5.
- Per-player fog and perspective correctness. That belongs to 07b3.
- Tick stepping and intermediate-state inspection. That is deferred to 07b7 unless playtests make it urgent.
- Control groups and production-focused UX.

## Architecture

`DevTurnInput` owns the dev input model: active player, selected entity, pending
`SubmitTurn`s, validation, and order construction. It does not mutate
`MatchState` and does not call the resolver.

`DevPlayMode` owns scenario loading, the current `LoadedScenario`, the
`MatchRenderer` instance, the small dev HUD, mouse routing, and the manual
resolve button. It keeps UI/controller concerns out of the renderer.

`MatchRenderer` remains a pure visual sync layer. 07b2 only adds read-only
helpers for tile hit-testing and a `Highlights` overlay for selection/hover
rectangles.

## Done when

- [x] Dev scene loads `mvp_map.tres` by default.
- [x] Developer can switch the active player between P0 and P1.
- [x] Developer can select only live entities owned by the active player.
- [x] Right-click/context actions queue `MOVE`, `ATTACK`, or `GATHER`.
- [x] Resolve advances the turn by calling `Resolver.resolve(...)` and feeding
  the result into `MatchRenderer.render_step(...)`.
- [x] Pending submissions clear after resolve.
- [x] `make test` runs resolver, renderer, dev input, and dev play mode tests.
- [x] `gdlint` and `gdformat --check` pass for touched GDScript files.

## Artifacts

- PR [#14](https://github.com/Z-a-r-a-k-i/clash/pull/14)
