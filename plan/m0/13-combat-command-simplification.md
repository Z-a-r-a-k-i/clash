---
status: ready
depends_on:
  - ./12-dev-play-command-ux.md
---

# M0 combat command simplification

The human-playable dev pass exposed that the command model is still too hard to
predict. The next PR should simplify combat orders before deeper playtest
iteration: units should defend themselves automatically, movement should be one
clear turn intent, and the UI should preview whether a selected unit will shoot,
move, shoot-and-move, retreat, or halt.

## Scope

- Preserve automatic combat: every combat unit may fire once per turn at a
  valid enemy in weapon range, preferring its focused target and otherwise
  falling back to the closest enemy.
- Replace hold-fire with halt-on-sight. Halt-on-sight should stop movement when
  an enemy is visible, but should not stop automatic shooting.
- Add a retreat / force-move command. Retreat is a one-turn move-only intent:
  no shot, ignores halt-on-sight, and receives full movement budget.
- Keep Target as priority focus only. Target should not be a separate attack
  action, and an out-of-range focused target should fall back to closest enemy
  in range.
- Batch attack damage simultaneously within the attack phase so entity id order
  never decides whether a unit gets to fire.
- Reduce movement after firing with a per-unit tunable, defaulting to 50 percent
  of normal movement. Units that do not fire, or that retreat, keep full movement.
- Collapse unit movement/combat input to one effective turn intent for M0:
  latest move-like intent wins, latest target focus wins, and no unit receives
  multiple move or attack slots in one resolve.
- Add clear dev-play intent previews for selected units and friendly-intent
  overlays: move, shoot + move, shoot + hold, retreat, idle + shoot, and halted.
- Update the command card text and playtest docs so the player-facing model is
  "Move, Retreat, Target, Halt on Sight" rather than queued attack/move chains.

## Non-goals

- No control groups, multi-unit command formation behavior, hotkeys, or minimap.
- No final combat balance pass. The 50 percent post-shot movement value is a
  starting point for playtest, not a tuned value.
- No true hold-fire stance. If a no-shoot mode becomes necessary, add it later
  as a deliberate stance after playtesting retreat and halt-on-sight.
- No terrain/pathfinding redesign.

## Design notes

- Attack selection uses start-of-turn positions. Moving into range should not
  grant a same-turn shot.
- Movement happens after the simultaneous attack batch and uses the surviving
  unit's resulting movement budget.
- A unit killed during the attack batch still fires if it had a valid shot at
  the start of the attack phase, but dead units do not move afterward.
- Retreat trades damage for mobility. A retreating unit can still be shot by
  enemies that had it in range at the start of the turn.
- Halt-on-sight should be evaluated from current visibility/sight data, not from
  weapon range alone. If that proves too defensive in playtest, change the rule
  in a follow-up balance PR.

## Suggested tests

- Two units that can kill each other in the same attack phase both deal damage
  and both die.
- Multiple attackers overkilling one target emit deterministic damage events
  before one deterministic destruction event.
- A focused target in range is preferred; a focused target out of range falls
  back to closest in-range enemy.
- A firing unit with a normal move spends the reduced post-shot movement budget.
- A retreating unit does not fire and spends its full movement budget.
- Halt-on-sight blocks movement when an enemy is visible but still allows a
  weapon-range shot.
- Latest move-like intent wins, latest target focus wins, and extra submitted
  unit move/attack slots do not create multiple resolve ticks.
- Dev-play previews distinguish move, shoot + move, shoot + hold, retreat, and
  halted states.

## Done when

- [ ] Hold-fire is gone from runtime state, resolver behavior, command UI, tests,
  and docs.
- [ ] Halt-on-sight and retreat are available from dev play and covered by tests.
- [ ] Attack damage is resolved as a simultaneous batch.
- [ ] Post-shot movement reduction is tunable per unit and defaults to 50 percent.
- [ ] Unit input/resolution is one effective turn intent for M0.
- [ ] The player can see before resolve whether a selected unit will shoot, move,
  shoot-and-move, retreat, or halt.
- [ ] Resolver, dev input, dev play, and renderer tests cover the simplified
  command model.
