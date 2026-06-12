---
status: sketch
depends_on:
  - ./00-play-mode-consolidation.md
---

# AI opponent

A scripted bot that produces a `SubmitTurn` from a `MatchState` each turn,
through the same interface as a human player. Two consumers from day one: the
solo play mode (human vs AI) and the simulation harness (AI vs AI, node 02).

## Architecture

- Pure function shape, mirroring the resolver:
  `AiPlayer.plan_turn(state, player_id, registry, tunables, ai_config) -> SubmitTurn`.
  No node dependencies, runs headless, deterministic for a given (state,
  config) — seeded PRNG only if/when randomness is wanted, seed in the config.
- **Fog-honest by default:** the AI sees through the same
  `VisionSystem` mask as a player would (no cheating); a `cheats_vision` flag
  in the config allows omniscient baselines for the simulator.
- Layered decision-making, simplest thing that plays a full game:
  1. **Macro layer** — follow a *build order list* (data-driven: e.g.
     `["worker", "worker", "barracks", "marine", ...]`), then a steady-state
     rule set: keep minerals low, keep workers saturated (gather caps are in
     the data), expand when bases mine out, keep producing army.
  2. **Army layer** — utility rules: rally fresh units to a staging point;
     attack when army value ≥ threshold or when scouted enemy army is weaker;
     retreat damaged-and-losing groups; a-move via existing ATTACK_MOVE +
     halt-at-firing-range mechanics.
  3. **Micro layer (minimal at M1)** — focus-fire via target priority chains
     (lowest-HP visible enemy), siege/unsiege tanks by enemy proximity.
- **Difficulty = config, not code**: build order choice, attack thresholds,
  income handicaps, decision cadence (acting every Nth turn).

## Strategy configs

`AiConfig` resource: build order, aggression thresholds, unit mix weights,
expansion timing, vision cheat flag, seed. Ship 3 starter strategies —
`rush_marines`, `two_base_tanks`, `heli_harass` — these double as the
simulator's strategy matrix (node 02).

## Wiring

- Solo: LocalAdapter (node 00) asks the AI for player B's submission when the
  human submits — blind simultaneity holds because the AI never sees the
  human's pending orders, only the resolved state.
- Difficulty surfacing in dev play UI is a stretch goal; a config dropdown is
  enough.

## Done when

- [ ] AI plays a complete match (gathers, builds, expands, trains, attacks,
      can win by raze) from any loaded scenario on the 1v1 map.
- [ ] Headless test: AI vs do-nothing opponent wins within a turn bound;
      AI vs AI completes without errors or stalls (no-progress watchdog).
- [ ] All three starter strategies are expressed purely as `AiConfig` data.
- [ ] Determinism: same (state, config, seed) → identical SubmitTurn (golden
      test), so simulator runs are reproducible.
