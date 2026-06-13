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

- [x] ~~Factory-click crash~~ — withdrawn: playtest 2 confirmed the
      factory is fine; the game-1 crash was a one-off hard crash on the
      remote client with no log captured. Next occurrence: grab
      `%APPDATA%/Godot/app_userdata/Clash/logs/godot.log` from that
      machine immediately.
- [x] Units spawned on the producer's top edge regardless of rally
      ("marines spawning in weird places"): the spawn-tile perimeter
      walk now prefers the free tile nearest the rally target (def
      rally_offset as fallback), ties keeping clockwise order.
- [x] A worker no longer blocks its own pending build placement: order
      validation and the placement preview ignore the ordering worker,
      and the construction flow walks it out to the nearest free ring
      tile before the building spawns.

## Wave 1 — balance + pacing (one PR, .tres/map edits; canon values
hand-edited, never regenerated)

Decided: apply all at once, then re-playtest.

- [x] Gathering rate doubled: minerals 1→2/worker/turn, gold 2→3,
      gas 1→2.
- [x] Speeds: worker 6→8, marine 10→12, tank 8→11, helicopter 14→16.
- [x] One worker per mineral crystal (cap 2→1, gold too) — same peak
      income per base with half the workers; more income requires
      expanding.
- [x] Siege research removed (the ability was never actually gated by
      it; the research was a dead purchase). Factory researches = [],
      def deleted, registry/tests updated.
- [x] Production already counts the order turn as the first build turn
      (verified by `train_idle_producer_immediate_install`); the
      complaint is a visibility problem — moved to the HUD wave
      (production progress display).
- [x] Arena width 80→64 (mains ~25% closer); on-axis blocks and the
      center golds recentered; regenerated + rebaked, symmetry tests
      green.

## Wave 2 — HUD/UX (extends node 05's scope)

- [x] In-world unit life bars; selection panel with full unit stats.
- [x] Top bar: income per turn AND committed spending (what next turn's
      balance will look like).
- [x] Production visibility: what a building is producing, queue state,
      progress; cancel production with refund.
- [x] Worker state surfaced: building / gathering gas; gas workers
      shown as x/max per geyser.
- [x] Damage preview: expected damage vs the hovered/targeted enemy.
- [x] Range display on demand (Alt) — works in multiplayer too (the
      selected unit's current range always shows in both modes; Alt
      adds the hover-projected range).
- [x] Path preview shows EVERY per-turn stop along the route, not just
      the first stop (lets players count turns to arrival).
- [x] Command clarity: distinguish move+attack vs move+idle, etc.
      (Move (M) / Attack-move (A) / Gather (G) labels, tooltips, and
      controller-level M/A/G hotkeys). Soft shader fog (unexplored /
      explored / visible bands) replaced the per-run polygon overlay
      in the same wave.

## Wave 3 — mechanics (resolver changes, each with tests)

- [x] Friendly pass-through while moving (1x1 units): movement PLANNING
      treats own units as passable so paths press through friendly
      clumps instead of detouring; exact-move targets on a stationary
      ally still complete adjacent; two units can never end a turn on
      the same tile; enemies and buildings always block. NOTE: true
      "walk through a parked ally" needs displacement/shove mechanics —
      tiles stay exclusive — recorded under Roadmap.
- [x] Rally/gather valid near ANY owned completed base (within 10
      tiles, rect-to-rect); far-away resources rejected for both plain
      GATHER and rally-gather until a base is built nearby.
- [x] Tank splash damage: data-driven on StatusEffect (sieged: radius
      1, 50% falloff, FRIENDLY FIRE on per user decision); resources
      immune; codec round-trips the new fields.
- [x] Spawn trained units on the producer side facing the rally point
      (landed early with the wave-0 spawn fix).

## Roadmap (not yet defined — own PR after discussion)

- Shoot-vs-move tradeoff (firing halves movement?) and/or a Hold Fire
  toggle. User undecided; do not implement until specced.
- Unit displacement/shove so stationary allies can truly be walked
  through (tile exclusivity makes pass-through planning-only today).
- Defense-vs-offense balance and entrance geometry: re-evaluate after
  Wave 1 changes the game's tempo.

## Done when

- [ ] All waves merged, then a second network playtest where: a game
      reaches meaningful conflict before turn ~12, no hangs, no crash,
      and the players can read economy/production/army state without
      asking the dev.
