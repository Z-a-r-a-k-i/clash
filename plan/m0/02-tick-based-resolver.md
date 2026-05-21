---
status: done
depends_on:
  - ./01-tile-grid-and-occupancy.md
---

# Tick-based resolver

The deterministic engine that turns `(state, queue_a, queue_b)` into `events[]`. At M0 lives inside the Godot client as a pure GDScript function over plain-data structures (per ADR 0020). Lifted to a server at M2; server language and wire protocol are deferred until then.

## Algorithm

```text
resolve(state, queue_a, queue_b) -> events[]:
  N = max action-queue length across all units this turn
  events = []
  for tick in 1..N:
    # Phase 1: self abilities, then a simultaneous automatic attack batch
    collect_attack_intents_for_all_non_move_only_combat_units()
    apply_attack_damage_batch(state, events)
    # Phase 2: every unit's k-th action that is a move
    for unit in stable_id_order(all_units):
      action = unit.queue[tick] if exists else None
      if action is move-like:
        resolve_move(unit, action, state, events) # post-shot budget unless Move Only
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

Target focus: `attack { target_id_priority: [t1, t2, t3, ...] }`.

1. For each ID in priority list, in order: if entity is alive, in range, and targetable at attack-phase start, fire at it.
2. If list exhausted or the focus is out of range: fire at closest enemy in range (ties broken by ID).
3. Move Only units skip the attack batch. Halt-on-sight never suppresses shooting.

## Open questions

- How is "k-th action" defined when a unit's queue is exhausted before tick N? Skip (no action this tick) — confirmed.
- Persistent move from prior turns: does it count as the unit's tick-1 action this turn, or does it only advance when no fresh order is queued? Latter — fresh orders this turn override the persistent path.
- Movement budget per tick vs per turn? Per turn — speed stat = tiles per turn, distributed across moves. Units that shoot use their `MovementDef.post_shot_move_fraction`; Move Only uses full speed.

## Done when

- [x] Pure-function `Resolver.resolve(state, submit_a, submit_b, registry, tunables) -> ResolveResult` exists in `client/scripts/resolver/`.
- [x] Deterministic on identical input (golden test: same input → identical event list across N runs).
- [x] Handles resolver-level order types from node 03 (move, Move Only, target focus, halt-on-sight toggle, cancel, build, train, research, gather, surrender flag).
- [x] Unit tests cover target fallback, simultaneous attack batches, Move Only, halt-on-sight movement blocking, post-shot movement budget, persistent-move continuation, multi-tile collision during move, attacks-before-moves ordering within a tick, and movement-speed budget.
- [x] No RNG in the resolver call graph (verified by grep + review).

## Artifacts

- PR [#2](https://github.com/Z-a-r-a-k-i/clash/pull/2) — tick-based turn resolver.
