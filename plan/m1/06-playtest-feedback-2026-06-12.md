---
status: sketch
depends_on:
  - ./03-map-1v1-three-bases.md
---

# Playtest feedback — 2026-06-12 (first human-vs-human network game)

Triage of the first real playtest. Perf was the blocker and is fixed
(PR #54: turn resolve 14.5s → 1.3s worst case on a 144-entity load).
Remaining work in user-decided order: bugs → balance → HUD → mechanics.
Each wave is its own PR; re-playtest after the balance wave.

## Wave 0 — bugs (first, regardless of order)

- [ ] Crash when clicking a factory right after building it (repro +
      fix; suspect command-card option building against a
      mid-construction producer).
- [ ] Units sometimes spawn far from their producer ("marines spawning
      far away on top") — audit the spawn-tile search order.
- [ ] A worker blocks its own pending build placement (the build
      footprint should treat the assigned worker as passable instead of
      forcing the player to move it first).

## Wave 1 — balance + pacing (one PR, .tres/map edits; canon values
hand-edited, never regenerated)

Decided: apply all at once, then re-playtest.

- [ ] Gathering rate up (games must not sit at 22 uneventful turns).
- [ ] Movement range up across the board; tanks notably faster.
- [ ] One worker per mineral crystal (cap 2 → 1) to force expansions.
- [ ] Remove the siege research gate — tanks siege from the moment
      they're built.
- [ ] Production starts with one cycle already done (ordering a unit
      counts the order turn as the first build turn).
- [ ] Arena: bring the mains closer together (players too far apart);
      re-bake + symmetry tests.

## Wave 2 — HUD/UX (extends node 05's scope)

- [ ] In-world unit life bars; selection panel with full unit stats.
- [ ] Top bar: income per turn AND committed spending (what next turn's
      balance will look like).
- [ ] Production visibility: what a building is producing, queue state,
      progress; cancel production with refund.
- [ ] Worker state surfaced: building / gathering gas; gas workers
      shown as x/max per geyser.
- [ ] Damage preview: expected damage vs the hovered/targeted enemy.
- [ ] Range display on demand (Alt) — works in multiplayer too.
- [ ] Path preview shows EVERY per-turn stop along the route, not just
      the first stop (lets players count turns to arrival).
- [ ] Command clarity: distinguish move+attack vs move+idle, etc.

## Wave 3 — mechanics (resolver changes, each with tests)

- [ ] Friendly pass-through while moving: allies are transparent during
      movement; two units still cannot end a turn on the same tile;
      enemies always block.
- [ ] Rally/gather to resources near ANY owned base ("resource is not
      valid" rejection only when no base is nearby; far-away gathering
      stays invalid).
- [ ] Tank splash damage.
- [ ] Spawn trained units on the producer side facing the rally point.

## Roadmap (not yet defined — own PR after discussion)

- Shoot-vs-move tradeoff (firing halves movement?) and/or a Hold Fire
  toggle. User undecided; do not implement until specced.
- Defense-vs-offense balance and entrance geometry: re-evaluate after
  Wave 1 changes the game's tempo.

## Done when

- [ ] All waves merged, then a second network playtest where: a game
      reaches meaningful conflict before turn ~12, no hangs, no crash,
      and the players can read economy/production/army state without
      asking the dev.
