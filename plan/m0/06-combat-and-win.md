---
status: done
depends_on:
  - ./00-config-and-tunables.md
  - ./02-tick-based-resolver.md
  - ./05-production.md
---

# Combat resolution + win condition

How damage is dealt, how counters work, how a match ends.

## Unit stats at MVP

| Unit | HP | Damage | Range | Speed (tiles/turn) | Pop | Layer | Tags |
|---|---|---|---|---|---|---|---|
| Marine | low | low | medium | medium | 1 | ground | light, biological |
| Tank | high | high | long | low | 3 | ground | heavy, mechanical |
| Helicopter | medium | medium | medium | high | 4 | flying | light, mechanical |

Numeric values are tuned in playtest; the table is structural. All values data-driven via `EntityDef`s. Per the design spec, **Layer** maps to `MovementDef.DefaultLayer` (drives pathing and which attackers can target the unit); **Tags** are the entity's `Tags[]` and feed `AttackModifier` damage multipliers.

## Counter rules

Two independent mechanisms (per the design spec):

1. **Layer-based targeting.** An attacker's `CombatDef.TargetLayers` lists which layers it can fire on. A unit whose `TargetLayers = ["ground"]` can't hit a flying-layer target at all. A marine with `TargetLayers = ["ground", "flying"]` can hit both.
2. **Tag-based damage modifiers.** `CombatDef.AttackModifiers[]` is a list of `{ TargetTag, DamageMult }` entries applied when the target carries the matching tag. Examples: tank vs `heavy` 1.5x, helicopter vs `light` 1.5x.

At MVP keep modifiers small (one or two per unit). Expand into a proper counter matrix when M1 brings the full roster.

## Building HP

Buildings have HP and can be destroyed. At M0 the resolver removes occupancy immediately when a building is destroyed; delayed wreck/blocking visuals are presentation polish for later dev-play work.

## Win condition

- **Raze:** a player with zero buildings loses. Workers and units alone cannot win or contest the match.
- **Surrender:** a player can surrender at the start of any turn. Resolver emits a `MatchEnd { winner }` event.
- No timer-based decision at MVP. Stalemates are a non-goal for the prototype — if matches stall, that's playtest data, not a feature.

## Done when

- [x] Marine, tank, and helicopter can deal damage to valid ground / flying targets per the rules above.
- [x] Counter modifiers apply correctly (golden test on known data values).
- [x] Building destruction emits an event and removes occupancy.
- [x] Win check runs after every turn's end-of-turn pass and ends the match cleanly.
- [x] Surrender flag delivered in `SubmitTurn` ends the match immediately.

## Artifacts

- PR [#6](https://github.com/Z-a-r-a-k-i/clash/pull/6) — combat data, counter modifiers (light/heavy), research data.
