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

This area splits into a headless half (07a), a gameplay-first visual/control path (07b1 → 07b6), and a deferred debugger node (07b7):

- [`07a-scenario-loader-and-save-load.md`](./07a-scenario-loader-and-save-load.md) — `done`. Scenario data shape, loader, save/load round-trip.
- [`07b1-renderer-and-camera.md`](./07b1-renderer-and-camera.md) — `done`. Renderer + camera + attack visualization. *See the map.*
- [`07b2-input-and-turn-advance.md`](./07b2-input-and-turn-advance.md) — `done`. Mouse selection + order issuing + manual turn advance. *Play a turn.*
- [`07b3-perspective-and-fog.md`](./07b3-perspective-and-fog.md) — `done`. Per-player perspective + fog of war (ADR-0016). *Swap perspectives.*
- [`07b4-gameplay-command-surface.md`](./07b4-gameplay-command-surface.md) — `done`. Rough controls for all non-ability M0 orders. *Drive the economy and army.*
- [`07b5-use-abilities.md`](./07b5-use-abilities.md) — `ready`. Minimal self-target ability order path for stim and siege/unsiege. *Make unit kits real.*
- [`07b6-playtest-loop.md`](./07b6-playtest-loop.md) — `ready`. Repeatable M0 playtest checklist and smoke path. *Start learning what is fun.*
- [`07b7-tick-step-debugger.md`](./07b7-tick-step-debugger.md) — `stub`. Single-tick advance + state inspector. *Debug ticks if playtests demand it.*

## What it does (full area, all sub-PRs combined)

- **Perspective switch.** Toggle between Player A's and Player B's views (each rendered with its own fog of war). Either tabbed UI or split-screen, dev's choice.
- **No timer pressure.** The dev advances turns manually with a button. Player A's queue, Player B's queue, then "Resolve."
- **Scenario loader.** Read a config file and spawn arbitrary entities at chosen positions, set resource counts, force-complete buildings, set research state. Lets us test "marines vs tanks at 8 tile range" or "helicopter harassing exposed mineral line" without playing 5 minutes to set it up.
- **Save / load mid-match state.** Snapshot to a file; reload restores exactly, including in-flight production timers and persistent move orders. Critical for reproducing bugs.
- **Gameplay command surface.** Use rough dev controls for build, train, research, cancel, hold-fire, attack-move, and abilities so the full M0 roster can be exercised.
- **Playtest loop.** Run repeatable sessions on `mvp_map.tres` and capture first gameplay notes before investing in deeper debug tooling.

## What it explicitly is not

- Not a playable two-human mode. Hot-seat is incompatible with simultaneous turns by construction. Real human-vs-human play arrives with network play (M2).
- Not a vs-AI mode. AI opponent is M1.
- Not a polished player UI. It is allowed to be rough, but it must be complete enough to start finding obvious fun, pacing, and command-surface problems.

## Open questions (resolved during 07a)

- Save/load format: same shape as the scenario `ScenarioDef.tres`, or a separate runtime-snapshot format? **Resolved in 07a:** same shape — a "scenario" and a "save" are the same `ScenarioDef.tres` data, with the "save" version filling in mid-match production progress, persistent move orders, ability cooldowns, etc.
- Where the scenario picker lives in the dev UI: a file dialog, a fixed dropdown of registered scenarios, or both? **Default:** dropdown listing `client/data/scenarios/*.tres`, with a "load file…" escape hatch. Lands when 07b2 wires UI.

## Done when

- [x] Scenario loader reads a config file and instantiates the described state. *(07a)*
- [x] Save current state to file; loading the file reproduces it exactly (including production progress and persistent move orders). *(07a)*
- [x] At least three scenario files exist for regression testing key combat / economy situations. *(07a + 08)*
- [x] Dev can issue orders for either player in any order and advance the turn manually. *(07b2)*
- [x] Dev can switch between Player A and Player B perspectives at any time, with each view's fog of war computed correctly. *(07b3)*
- [x] Dev can drive all non-ability M0 orders from the UI: attack-move, hold-fire, build, train, research, and cancel. *(07b4)*
- [ ] Dev can use M0 self-target abilities, including stim and siege/unsiege. *(07b5)*
- [ ] A repeatable M0 playtest checklist exists and a smoke path proves `mvp_map.tres` can exercise economy, production, combat, fog, and match end. *(07b6)*
- [ ] Gameplay-first sub-PRs land. *(07a `done`; 07b1 `done`; 07b2 `done`; 07b3 `done`; 07b4 `done`; 07b5 `ready`; 07b6 `ready`; 07b7 deferred `stub`)*
