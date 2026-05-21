---
status: done
depends_on:
  - ./12-dev-play-command-ux.md
---

# M0 combat command simplification

The human-playable dev pass exposed that the command model is still too hard to
predict. The next PR should simplify combat orders before deeper playtest
iteration: units should defend themselves automatically, movement should be one
clear turn intent, and the UI should preview whether a selected unit will shoot,
move, shoot-and-move, Move Only, or halt.

## Scope

- Preserve automatic combat: every combat unit may fire once per turn at a
  valid enemy in weapon range, preferring its focused target and otherwise
  falling back to the closest enemy.
- Use halt-on-sight as the defensive stance. Halt-on-sight should stop movement when
  an enemy is visible, but should not stop automatic shooting.
- Add a Move Only command. Move Only is a one-turn movement-only intent:
  no shot, ignores halt-on-sight, and receives full movement budget.
- Keep Target as priority focus only. Target should not be a separate attack
  action, and an out-of-range focused target should fall back to closest enemy
  in range.
- Batch attack damage simultaneously within the attack phase so entity id order
  never decides whether a unit gets to fire.
- Reduce movement after firing with a per-unit tunable, defaulting to 50 percent
  of normal movement. Units that do not fire, or that Move Only, keep full movement.
- Collapse unit movement/combat input to one effective turn intent for M0:
  latest move-like intent wins, latest target focus wins, and no unit receives
  multiple move or attack slots in one resolve.
- Add clear dev-play intent previews for selected units and friendly-intent
  overlays: move, shoot + move, shoot + hold, Move Only, idle + shoot, and halted.
- Update the command card text and playtest docs so the player-facing model is
  "Move, Move Only, Target, Halt on Sight" rather than queued attack/move chains.

## Non-goals

- No control groups, multi-unit command formation behavior, hotkeys, or minimap.
- No final combat balance pass. The 50 percent post-shot movement value is a
  starting point for playtest, not a tuned value.
- No true no-shoot stance. If it becomes necessary, add it later as a deliberate
  stance after playtesting Move Only and halt-on-sight.
- No terrain/pathfinding redesign.

## Design notes

- Attack selection uses start-of-turn positions. Moving into range should not
  grant a same-turn shot.
- Movement happens after the simultaneous attack batch and uses the surviving
  unit's resulting movement budget.
- A unit killed during the attack batch still fires if it had a valid shot at
  the start of the attack phase, but dead units do not move afterward.
- Move Only trades damage for mobility. A Move Only unit can still be shot by
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
- A Move Only unit does not fire and spends its full movement budget.
- Halt-on-sight blocks movement when an enemy is visible but still allows a
  weapon-range shot.
- Latest move-like intent wins, latest target focus wins, and extra submitted
  unit move/attack slots do not create multiple resolve ticks.
- Dev-play previews distinguish move, shoot + move, shoot + hold, Move Only, and
  halted states.

## Done when

- [x] The old no-shoot stance is gone from runtime state, resolver behavior, command UI, tests,
  and docs.
- [x] Halt-on-sight and Move Only are available from dev play and covered by tests.
- [x] Attack damage is resolved as a simultaneous batch.
- [x] Post-shot movement reduction is tunable per unit and defaults to 50 percent.
- [x] Unit input/resolution is one effective turn intent for M0.
- [x] The player can see before resolve whether a selected unit will shoot, move,
  shoot-and-move, Move Only, or halt.
- [x] Resolver, dev input, dev play, and renderer tests cover the simplified
  command model.

## Artifacts

- PR [#24](https://github.com/Z-a-r-a-k-i/clash/pull/24) — combat command simplification for manual playtesting.
