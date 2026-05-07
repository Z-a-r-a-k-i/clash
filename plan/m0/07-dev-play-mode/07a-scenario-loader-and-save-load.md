---
status: done
---

# Scenario loader + save/load

Headless half of plan node 07: a `ScenarioDef.tres` data shape, a `ScenarioLoader` that turns a scenario into a `MatchState` ready for the resolver, and a `MatchSaver` that round-trips state to/from disk for bug-repro snapshots. No visual layer (that ships in 07b1+).

Driven by ADR 0013 (deterministic resolution): save/load round-trips must reproduce the exact same state, including in-flight production timers, persistent move orders, ability cooldowns, gather state, and active buffs.

## Done when

- [x] `ScenarioDef`, `ScenarioPlacement`, `ScenarioStatOverride` resources defined with all fields needed for M0 scenarios.
- [x] `ScenarioLoader.load(scenario, registry, tunables) → LoadedScenario` is a pure function. Applies `registry_override` if set, clones-then-patches via `stat_overrides`, populates players + entities + tile grid.
- [x] `MatchSaver.save(state, path)` and `MatchSaver.load_from(path) → MatchState` round-trip preserves every persistent field.
- [x] `SavedSession` resource bundles `state + registry` so a scenario with `stat_overrides` reloads against the same patched registry.
- [x] All persistent runtime types extend `Resource` with `@export` annotations (MatchState, Entity, EntityOrder, ProductionState, GatherState, ActiveBuff, TileGrid, PlayerState, SubmitTurn).
- [x] At least three sample scenarios in `client/data/scenarios/` (smoke_minimal, combat_marines_vs_tanks, economy_full_base).
- [x] Five new tests cover loader + roundtrip paths.
- [x] All existing resolver tests still pass.

## Artifacts

- PR [#7](https://github.com/Z-a-r-a-k-i/clash/pull/7) — merged 2026-05-04
- Commit `b298a79`
