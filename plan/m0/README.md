---
status: sketch
---

# M0 — Local prototype

Smallest playable thing that has the soul of the game on one machine. No networking, no accounts, no ladder, no card system. The goal is to find out — fast — whether the simultaneous-turn RTS feels fun.

## Scope

M0 is a **dev-only** prototype. Simultaneous turns require blind concurrent input, so hot-seat is incompatible by construction; an AI opponent is M1. Until then, one developer drives both players from a debug tool with no timer and a scenario loader.

Both sides start with an identical roster:

- 1 base, a few workers, mineral patches and a gas geyser per base position.
- Buildings unlocked by tech path: refinery (gas extraction), barracks, factory, starport.
- Units: marine (T1), tank (T2), helicopter (T3).
- Pop cap 50, variable slot cost per unit (tunable).

A match ends when one player has zero buildings, or surrenders. M0's purpose is validating that the **systems are correct** — fun validation needs a real opponent and arrives once M1 (AI) or M2 (network play) lands.

## What's in M0

| Concern | Node | Notes |
|---|---|---|
| Tunables and entity definitions | [00-config-and-tunables.md](00-config-and-tunables.md) | Foundation for fast iteration. All stats / footprints / costs live in `.tres`, never code. |
| Map representation, multi-tile entities | [01-tile-grid-and-occupancy.md](01-tile-grid-and-occupancy.md) | The grid data model. Pathfinding, range, vision, collision all depend on this. |
| Turn resolver | [02-tick-based-resolver.md](02-tick-based-resolver.md) | Action-slot lockstep, attacks-before-moves per tick. |
| Order types and persistence | [03-action-queue-and-orders.md](03-action-queue-and-orders.md) | Move, attack, attack-move, hold-fire, persistent moves, target chains. |
| Resources and workers | [04-economy.md](04-economy.md) | Minerals, gas (via refinery on geyser), workers, autonomous gathering. |
| Production and build times | [05-production.md](05-production.md) | Buildings, units, research — all on per-item turn-count timers. |
| Combat resolution and win | [06-combat-and-win.md](06-combat-and-win.md) | HP, damage, attack range, light/heavy/flying counters, raze detection. |
| Dev play mode + scenario tooling | [07-dev-play-mode.md](07-dev-play-mode.md) | One dev drives both sides; no timer; scenario loader; tick-step debugger. |
| MVP map layout | [08-mvp-map.md](08-mvp-map.md) | Symmetric SC2-shaped map: main + natural + 2 expansions per side. |

## What's deferred to M1 or later

- AI opponent (M1) — first time a single human can play solo.
- Network play by invitation (M2) — first time two humans can actually play.
- Control groups (M1) — M0 selects unit-by-unit; group orders come once we know the action surface.
- Tuning pass on tile size, pop slots, timer length (M1 onward, with playtest data).
- Polished art (post-MVP). M0 uses placeholder sprites.

## Done when

- [ ] A developer can drive a complete match (both sides) through the dev play mode, ending in a raze or surrender.
- [ ] Scenario loader covers at least three regression scenarios (combat, economy, edge case).
- [ ] All nine child nodes are `done`.
- [ ] Mechanic-correctness notes captured in `../../docs/ROADMAP.md` or in follow-up plan nodes for M1.
