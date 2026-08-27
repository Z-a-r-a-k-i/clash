---
status: done
---

# M0 — Local prototype

Completed local prototype that established the game's deterministic rules and
playable development surface before solo and network paths existed.

## Scope

M0 was a **dev-only playable** prototype. Simultaneous turns require blind concurrent input, so hot-seat was incompatible by construction; one developer drove both players from a rough debug tool with no timer and a scenario loader. Later M1 and network work now provide the normal playable paths, but this tree remains the historical record of the underlying systems.

Both sides start with an identical roster:

- 1 base, a few workers, mineral patches and a gas geyser per base position.
- Buildings unlocked by tech path: refinery (gas extraction), barracks, factory, starport.
- Units: marine (T1), tank (T2), helicopter (T3).
- Pop cap 50, variable slot cost per unit (tunable).

A match ends when one player has zero buildings, or surrenders. M0's purpose is validating that the **systems are operable together** and starting qualitative gameplay discovery. True solo fun validation needs AI (M1) and true PvP validation needs network play (M2), but M0 should still be playable enough to reveal obvious problems.

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
| Dev play mode + scenario tooling | [07-dev-play-mode/](07-dev-play-mode/) | compound - 07a `done`; 07b1 `done`; 07b2 `done`; 07b3 `done`; 07b4 `done`; 07b5 `done`; 07b6 `done`; 07b7 `stub` |
| MVP map layout | [08-mvp-map.md](08-mvp-map.md) | `done` |
| Manual playtest readiness | [09-manual-playtest-readiness.md](09-manual-playtest-readiness.md) | `done` |
| Dev play human playability | [10-dev-play-human-playable.md](10-dev-play-human-playable.md) | `done` |
| Simple facing playtest map | [11-simple-facing-playtest-map.md](11-simple-facing-playtest-map.md) | `done` |
| Dev play command UX | [12-dev-play-command-ux.md](12-dev-play-command-ux.md) | `done` |
| Combat command simplification | [13-combat-command-simplification.md](13-combat-command-simplification.md) | `done` |
| Mechanics and status effects | [14-mechanics-and-status-effects.md](14-mechanics-and-status-effects.md) | `done` |

## What M0 deferred

- AI opponent and simulation — subsequently implemented in M1.
- Network play by invitation — a trusted development slice is now implemented;
  production infrastructure remains M2.
- Box/multi-selection and group orders — subsequently implemented. Persistent
  numbered RTS control groups remain future work.
- Tuning and presentation passes — active, driven by external playtests.
- Polished art and production exports — later milestones.

## Closure evidence

The gameplay-first M0 nodes landed, the repeatable smoke path covers economy,
production, combat, fog, and match end, and the full headless suite protects the
resolver and dev-play surface. The initial manual pass exposed presentation and
command-clarity blockers; those findings became later M0/M1 work rather than an
open M0 handoff. The optional tick-step debugger remains a deferred stub.

## Done when

- [x] The dev-play surface and smoke path exercise a complete match ending in
      raze or surrender; later solo and network paths reuse the same controller.
- [x] Scenario loader covers at least three regression scenarios (combat, economy, edge case). *(plan-07a + plan-08)*
- [x] All M0 implementation and readiness nodes through 09 are `done` except
  07b7, which remains an intentional `07-dev-play-mode` debugger stub pending
  playtest findings.
- [x] Mechanic-correctness and playtest notes are captured in the roadmap and
      follow-up M1 nodes.

## Plan-tree convention

This tree follows termwatch's plan-format (see termwatch/`docs/PLAN-FORMAT.md` v0.1). YAML frontmatter `status: stub | sketch | ready | doing | done`. Compound nodes are directories with `README.md`; leaves are plain `.md` files. The plan node body IS the spec — design rationale, build chunks, tests, ADR invocations all live in the node, not in a separate `docs/superpowers/specs/` directory. Done nodes stay in place as historical record with an `## Artifacts` section linking the merged PR.
