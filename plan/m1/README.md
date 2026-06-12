---
status: sketch
---

# M1 — Solo play and the iteration engine

First time a single human can play solo, and first time the game can play
itself. M1 has two spines that feed each other:

1. **AI opponent** — makes the game solo-playable (the campaign foundation).
2. **Simulation harness** — AI vs AI headless matches at scale, producing
   balance metrics. Every later tuning question ("is the marine too strong?",
   "how fast can you max with 2-base tank?") becomes a script run instead of
   a manual playtest.

Around the spines, M1 pays down the presentation debt that blocks fun
discovery: one shared play-mode controller instead of two divergent ones, a
real 1v1 map, a readable HUD, and a 2D graphics pass.

## Ordering and dependencies

Execution order (node numbers are ids, not sequence):
**00 → 03 → 04 → 05 → 01 → 02.**

Consolidation (00) goes first — graphics (04) and HUD (05) changes would
otherwise be made twice. The map (03) lands next so the presentation passes
have real terrain and layouts to render. AI (01) before simulator (02); the
simulator drives two AIs through the same submit interface, on a map and
presentation layer that are already settled.

| # | Concern | Node | Status |
|---|---|---|---|
| 1 | One play-mode controller (solo/multi DRY) | [00-play-mode-consolidation.md](00-play-mode-consolidation.md) | `sketch` |
| 2 | 1v1 map, three bases per player | [03-map-1v1-three-bases.md](03-map-1v1-three-bases.md) | `sketch` |
| 3 | 2D graphics pass | [04-graphics-pass-2d.md](04-graphics-pass-2d.md) | `stub` |
| 4 | HUD pass | [05-hud-pass.md](05-hud-pass.md) | `stub` |
| 5 | Scripted AI opponent | [01-ai-opponent.md](01-ai-opponent.md) | `sketch` |
| 6 | Headless simulation + balance metrics | [02-simulation-harness.md](02-simulation-harness.md) | `sketch` |

## Carried from M0 / ROADMAP

- Control groups and group orders already landed in M0 (#42); M1 extends them
  only if playtests demand it.
- Counter matrix started in M0 (marine > heli > tank > marine via
  integer-percent `AttackModifier`s); the simulator's job is to validate and
  tune it with data.
- Turn-timer pressure and blind simultaneous submit remain open design work —
  the AI doesn't need a timer, but solo fun validation does. Promote to a node
  when 01 is playable.

## Done when

- [ ] A human can play a full match vs the AI on the 1v1 map and lose to it
      at least sometimes.
- [ ] `make simulate` (or equivalent) runs N AI-vs-AI matches headless and
      emits a metrics CSV.
- [ ] dev play and network play share one match-session controller.
- [ ] The game is watchable: units face their movement direction, statuses
      and attacks are visible, the HUD shows resources/supply/production at a
      glance.
