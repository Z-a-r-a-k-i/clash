---
status: sketch
depends_on:
  - ./01-tile-grid-and-occupancy.md
---

# Tick-based resolver

The deterministic engine that turns `(state, queue_a, queue_b)` into `events[]`. At M0 lives inside the Godot client (pure C# function over POCO state). Lifted to a server at M2; server language and wire protocol are deferred until then.

## Algorithm

```text
resolve(state, queue_a, queue_b) -> events[]:
  N = max action-queue length across all units this turn
  events = []
  for tick in 1..N:
    # Phase 1: every unit's k-th action that is an attack
    for unit in stable_id_order(all_units):
      action = unit.queue[tick] if exists else None
      if action is attack-like:
        resolve_attack(unit, action, state, events)
    # Phase 2: every unit's k-th action that is a move
    for unit in stable_id_order(all_units):
      action = unit.queue[tick] if exists else None
      if action is move-like:
        resolve_move(unit, action, state, events)
    # Phase 3: persistent move advance for units with no fresh order this tick
    advance_persistent_moves(state, events, tick)
  apply_end_of_turn_effects(state, events)
  check_win_condition(state, events)
  return events
```

## Determinism rules

- No RNG. If introduced later, only via a seeded PRNG with the seed in the turn frame.
- Iteration order is **always** stable (sorted by entity ID).
- Speed stat affects movement distance per turn only. Never affects attack order.
- All stat lookups go through a config table — no per-instance variation.

## Target chain resolution

Per attack action: `attack { target_id_priority: [t1, t2, t3, ...] }`.

1. For each ID in priority list, in order: if entity is alive at this tick, fire at it.
2. If list exhausted and unit is **not** on hold-fire: fire at closest enemy in range (ties broken by ID).
3. If unit is on hold-fire and list exhausted: do not fire this tick.

## Open questions

- How is "k-th action" defined when a unit's queue is exhausted before tick N? Skip (no action this tick) — confirmed.
- Persistent move from prior turns: does it count as the unit's tick-1 action this turn, or does it only advance when no fresh order is queued? Latter — fresh orders this turn override the persistent path.
- Movement budget per tick vs per turn? Per turn — speed stat = tiles per turn, distributed across moves. Confirm during playtest.

## Done when

- [ ] Pure-function `Resolve(state, queueA, queueB) -> events` exists in `client/scripts/Resolver/`.
- [ ] Deterministic on identical input (golden test: same input → identical event list across N runs).
- [ ] Handles all order types from node 03 (move, attack, attack-move, hold-fire toggle, group orders).
- [ ] Unit tests for: target-chain fallback, hold-fire blocking auto-acquire, persistent-move continuation, multi-tile collision during move, attacks-before-moves ordering within a tick.
- [ ] No RNG in the call graph (verified by grep + review).
