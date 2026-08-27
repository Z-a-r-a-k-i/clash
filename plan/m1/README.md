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

## Delivered order and remaining work

The original sketch proposed `00 → 03 → 04 → 05 → 01 → 02`. In practice the
shared controller and arena landed first, followed by AI and simulation, while
the standalone graphics/HUD sketches were overtaken by focused playtest-driven
HUD and movement-animation PRs. The table below is authoritative; remaining
presentation work should be promoted only from observed playtest problems.

| # | Concern | Node | Status |
|---|---|---|---|
| 1 | One play-mode controller (solo/multi DRY) | [00-play-mode-consolidation.md](00-play-mode-consolidation.md) | `done` |
| 2 | 1v1 arena, main and natural per player | [03-map-1v1-three-bases.md](03-map-1v1-three-bases.md) | `done` |
| 3 | 2D graphics pass | [04-graphics-pass-2d.md](04-graphics-pass-2d.md) | `stub` |
| 4 | HUD pass | [05-hud-pass.md](05-hud-pass.md) | `stub` |
| 5 | Scripted AI opponent | [01-ai-opponent.md](01-ai-opponent.md) | `done` |
| 6 | Headless simulation + balance metrics | [02-simulation-harness.md](02-simulation-harness.md) | `done` |

## Carried from M0 / ROADMAP

- Box/multi-selection and group orders already landed in M0 (#42); persistent
  numbered RTS control groups are still unimplemented and should be added only
  if playtests justify them.
- Counter matrix started in M0 (marine > heli > tank > marine via
  integer-percent `AttackModifier`s); the simulator's job is to validate and
  tune it with data.
- Turn-timer pressure and blind simultaneous submit remain open design work.
  The AI and trusted network slice make that testable now; promote the first
  repeated playtest finding to a focused node instead of choosing a value from
  theory.

## Done when

- [ ] A human can play a full match vs the AI on the 1v1 map and lose to it
      at least sometimes.
- [x] `make simulate` (or equivalent) runs N AI-vs-AI matches headless and
      emits a metrics CSV.
- [x] dev play and network play share one match-session controller.
- [ ] The game is watchable: units face their movement direction, statuses
      and attacks are visible, the HUD shows resources/supply/production at a
      glance.
