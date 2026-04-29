---
status: sketch
depends_on:
  - ./02-tick-based-resolver.md
  - ./03-action-queue-and-orders.md
  - ./06-combat-and-win.md
---

# Dev play mode + scenario tooling

A debug-and-validation tool, not a play mode. Simultaneous-turn resolution requires blind concurrent input from two players, which a single shared screen cannot deliver — so hot-seat is out. M0 ships dev-only tooling that lets one developer drive both players, with no timer, plus a scenario loader for testing specific situations without grinding through a full match.

## What it does

- **Perspective switch.** Toggle between Player A's and Player B's views (each rendered with its own fog of war). Either tabbed UI or split-screen, dev's choice.
- **No timer pressure.** The dev advances turns manually with a button. Player A's queue, Player B's queue, then "Resolve."
- **Scenario loader.** Read a config file and spawn arbitrary entities at chosen positions, set resource counts, force-complete buildings, set research state. Lets us test "marines vs tanks at 8 tile range" or "helicopter harassing exposed mineral line" without playing 5 minutes to set it up.
- **Save / load mid-match state.** Snapshot to a file; reload restores exactly, including in-flight production timers and persistent move orders. Critical for reproducing bugs.
- **Tick-step debugger.** Step the resolver one tick at a time, inspect entity state and event log between ticks.

## What it explicitly is not

- Not a playable two-human mode. Hot-seat is incompatible with simultaneous turns by construction. Real human-vs-human play arrives with network play (M2).
- Not a vs-AI mode. AI opponent is M1.
- Not a fun-validation tool. It validates that the systems are correct, not that the game is fun. Fun validation needs an opponent that doesn't share the dev's brain.

## Open questions

- Save/load format: same shape as the scenario `ScenarioDef.tres`, or a separate runtime-snapshot format? Default: same shape — a "scenario" and a "save" are the same `ScenarioDef.tres` data, with the "save" version filling in mid-match production progress, persistent move orders, ability cooldowns, etc.
- Where the scenario picker lives in the dev UI: a file dialog, a fixed dropdown of registered scenarios, or both? Default: dropdown listing `client/data/scenarios/*.tres`, with a "load file…" escape hatch.

## Done when

- [ ] Dev can switch between Player A and Player B perspectives at any time, with each view's fog of war computed correctly.
- [ ] Dev can issue orders for either player in any order and advance the turn manually.
- [ ] Scenario loader reads a config file and instantiates the described state.
- [ ] Save current state to file; loading the file reproduces it exactly (including production progress and persistent move orders).
- [ ] Tick-step mode advances the resolver one tick at a time and exposes intermediate state.
- [ ] At least three scenario files exist for regression testing key combat / economy situations.
