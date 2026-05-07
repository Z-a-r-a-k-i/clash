---
status: sketch
depends_on:
  - ../02-tick-based-resolver.md
  - ../03-action-queue-and-orders.md
  - ../06-combat-and-win.md
---

# Dev play mode + scenario tooling

A debug-and-validation tool, not a play mode. Simultaneous-turn resolution requires blind concurrent input from two players, which a single shared screen cannot deliver — so hot-seat is out. M0 ships dev-only tooling that lets one developer drive both players, with no timer, plus a scenario loader for testing specific situations without grinding through a full match.

## Sub-PRs

This area splits into a headless half (07a) and a visual half decomposed into four sub-PRs (07b1 → 07b4):

- [`07a-scenario-loader-and-save-load.md`](./07a-scenario-loader-and-save-load.md) — `done`. Scenario data shape, loader, save/load round-trip.
- [`07b1-renderer-and-camera.md`](./07b1-renderer-and-camera.md) — `done`. Renderer + camera + attack visualization. *See the map.*
- [`07b2-input-and-turn-advance.md`](./07b2-input-and-turn-advance.md) — `stub`. Mouse selection + order issuing + manual turn advance. *Play a turn.*
- [`07b3-perspective-and-fog.md`](./07b3-perspective-and-fog.md) — `stub`. Per-player perspective + fog of war (ADR-0016). *Swap perspectives.*
- [`07b4-tick-step-debugger.md`](./07b4-tick-step-debugger.md) — `stub`. Single-tick advance + state inspector. *Step ticks.*

## What it does (full area, all sub-PRs combined)

- **Perspective switch.** Toggle between Player A's and Player B's views (each rendered with its own fog of war). Either tabbed UI or split-screen, dev's choice.
- **No timer pressure.** The dev advances turns manually with a button. Player A's queue, Player B's queue, then "Resolve."
- **Scenario loader.** Read a config file and spawn arbitrary entities at chosen positions, set resource counts, force-complete buildings, set research state. Lets us test "marines vs tanks at 8 tile range" or "helicopter harassing exposed mineral line" without playing 5 minutes to set it up.
- **Save / load mid-match state.** Snapshot to a file; reload restores exactly, including in-flight production timers and persistent move orders. Critical for reproducing bugs.
- **Tick-step debugger.** Step the resolver one tick at a time, inspect entity state and event log between ticks.

## What it explicitly is not

- Not a playable two-human mode. Hot-seat is incompatible with simultaneous turns by construction. Real human-vs-human play arrives with network play (M2).
- Not a vs-AI mode. AI opponent is M1.
- Not a fun-validation tool. It validates that the systems are correct, not that the game is fun. Fun validation needs an opponent that doesn't share the dev's brain.

## Open questions (resolved during 07a)

- Save/load format: same shape as the scenario `ScenarioDef.tres`, or a separate runtime-snapshot format? **Resolved in 07a:** same shape — a "scenario" and a "save" are the same `ScenarioDef.tres` data, with the "save" version filling in mid-match production progress, persistent move orders, ability cooldowns, etc.
- Where the scenario picker lives in the dev UI: a file dialog, a fixed dropdown of registered scenarios, or both? **Default:** dropdown listing `client/data/scenarios/*.tres`, with a "load file…" escape hatch. Lands when 07b2 wires UI.

## Done when

- [x] Scenario loader reads a config file and instantiates the described state. *(07a)*
- [x] Save current state to file; loading the file reproduces it exactly (including production progress and persistent move orders). *(07a)*
- [x] At least three scenario files exist for regression testing key combat / economy situations. *(07a + 08)*
- [ ] Dev can switch between Player A and Player B perspectives at any time, with each view's fog of war computed correctly. *(07b3)*
- [ ] Dev can issue orders for either player in any order and advance the turn manually. *(07b2)*
- [ ] Tick-step mode advances the resolver one tick at a time and exposes intermediate state. *(07b4)*
- [ ] All five sub-PRs land. *(07a `done`; 07b1 `done`; 07b2/3/4 `stub`)*
