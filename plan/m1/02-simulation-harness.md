---
status: sketch
depends_on:
  - ./01-ai-opponent.md
---

# Simulation harness — AI matches, strategies, balance metrics

Headless runner that plays AI-vs-AI matches at scale and emits metrics. This
turns balance questions into script runs and becomes the regression gate for
every future mechanics/tuning change.

## Runner

- CLI entry like the existing headless test runners:
  `godot --headless --path client --script scripts/_dev/run_simulation.gd -- <args>`
  plus a `make simulate` target. Args: scenario/map, strategy A, strategy B,
  match count, max turns, seed base, output CSV path.
- Loop per match: `plan_turn` (both AIs) → `Resolver.resolve` → repeat until
  `match_over` or turn cap (cap = draw, recorded as such).
- Matches are independent → trivially batchable; start sequential, keep the
  loop pure so parallel workers are a later drop-in.
- Reuses the replay journal (`match_replay.gd` / dev replay tools, plan-39):
  optionally dump the replay of any match (e.g. the first loss per pairing)
  for visual inspection in dev play.

## Metrics

Per turn (sampled into time series) and per match (aggregates), written as
CSV next to the existing `export_balance_csv.gd` conventions:

- economy: minerals/gas banked + income rate, worker count, base count;
- army: supply used, army value (mineral+gas cost of live combat units),
  per-unit-type counts;
- tempo landmarks: turn of first barracks/factory/starport, first attack,
  first base kill, **time-to-max-army** (user metric: turns until pop cap
  with a given strategy), time-to-mined-out per base;
- combat: damage dealt/taken per unit type, units lost, trades (army value
  delta per engagement window);
- outcome: winner, end turn, end reason (raze / surrender / turn cap).

## Analysis layer

- Strategy matrix mode: run all configured strategy pairings N× and emit a
  win-rate grid — the canonical balance report. The marine/tank/heli counter
  triangle (docs/ROADMAP.md) is validated here: each counter pairing should
  sit inside an agreed win-rate band (e.g. 60–80%), mirror matchups near 50%.
- Per-resolve wall-clock is recorded too — the simulator doubles as a long-run
  perf soak for the resolver (catches state-size-dependent slowdowns the
  single-turn stress test misses).

## Done when

- [ ] `make simulate` plays N matches headless and writes the metrics CSV.
- [ ] Strategy-matrix report (win rates per pairing) generated from one run.
- [ ] Time-to-max-army and income curves derivable from the CSV for any
      strategy (one example documented).
- [ ] A seeded run is fully reproducible (same CSV byte-for-byte).
- [ ] One counter-triangle assertion wired as an optional regression check.
