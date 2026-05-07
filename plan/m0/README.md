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

| Concern | Node | Status |
|---|---|---|
| Tunables and entity definitions | [00-config-and-tunables.md](00-config-and-tunables.md) | `done` |
| Map representation, multi-tile entities | [01-tile-grid-and-occupancy.md](01-tile-grid-and-occupancy.md) | `done` |
| Turn resolver | [02-tick-based-resolver.md](02-tick-based-resolver.md) | `done` |
| Order types and persistence | [03-action-queue-and-orders.md](03-action-queue-and-orders.md) | `done` |
| Resources and workers | [04-economy.md](04-economy.md) | `done` |
| Production and build times | [05-production.md](05-production.md) | `done` |
| Combat resolution and win | [06-combat-and-win.md](06-combat-and-win.md) | `done` |
| Dev play mode + scenario tooling | [07-dev-play-mode/](07-dev-play-mode/) | compound — 07a `done`; 07b1 `ready`; 07b2/3/4 `stub` |
| MVP map layout | [08-mvp-map.md](08-mvp-map.md) | `done` |

## What's deferred to M1 or later

- AI opponent (M1) — first time a single human can play solo.
- Network play by invitation (M2) — first time two humans can actually play.
- Control groups (M1) — M0 selects unit-by-unit; group orders come once we know the action surface.
- Tuning pass on tile size, pop slots, timer length (M1 onward, with playtest data).
- Polished art (post-MVP). M0 uses placeholder sprites.

## Done when

- [ ] A developer can drive a complete match (both sides) through the dev play mode, ending in a raze or surrender.
- [x] Scenario loader covers at least three regression scenarios (combat, economy, edge case). *(plan-07a + plan-08)*
- [ ] All nine child nodes are `done`. *(seven done; 07-dev-play-mode/ in progress: 07a done, 07b1-07b4 remaining)*
- [ ] Mechanic-correctness notes captured in `../../docs/ROADMAP.md` or in follow-up plan nodes for M1.

## Plan-tree convention

This tree follows termwatch's plan-format (see termwatch/`docs/PLAN-FORMAT.md` v0.1). YAML frontmatter `status: stub | sketch | ready | doing | done`. Compound nodes are directories with `README.md`; leaves are plain `.md` files. The plan node body IS the spec — design rationale, build chunks, tests, ADR invocations all live in the node, not in a separate `docs/superpowers/specs/` directory. Done nodes stay in place as historical record with an `## Artifacts` section linking the merged PR.
