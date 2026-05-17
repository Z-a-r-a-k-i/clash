---
status: doing
depends_on:
  - ./07b4-gameplay-command-surface.md
---

# Self-target ability orders

Follow-up gameplay PR after the command surface. M0 data already defines
abilities (`stim`, `siege_mode`, `unsiege_mode`) and runtime state for
cooldowns and buffs, but the resolver has no ability order path yet.

## Scope

- Add `EntityOrder.Type.USE_ABILITY`.
- Reuse `EntityOrder.def_id` as the ability id.
- Support self-target abilities only for M0.
- Resolve ability orders as action-slot orders:
  - at tick `k`, apply `USE_ABILITY` before attacks and moves
  - an ability consumes that queued action slot
  - the same queued slot does not also attack or move
  - `cast_time_turns > 0` starts a cast that completes at end-of-turn and
    blocks later same-turn actions
- Implement M0 effect support:
  - `StatBuffEffect` applies active buffs, HP costs, cooldowns, and research gates
  - `TransformEffect` changes `current_def_id` for siege/unsiege
- Add `ResolverEvent.Type.ABILITY_USED`; transform abilities also emit
  `ENTITY_TRANSFORMED`.
- Expose available self-target abilities in dev play mode for the selected entity.

## Non-goals

- No targeted ally/enemy/tile/area abilities.
- No energy or mana resource.
- No ability animation polish.
- No broader effect DSL beyond the existing `StatBuffEffect` and
  `TransformEffect` resources.

## Done when

- [x] Resolver can execute self-target `USE_ABILITY` orders deterministically.
- [x] Stim spends HP, applies damage/speed buffs, gates on research, and starts cooldown.
- [x] Siege and unsiege transform `current_def_id` using existing data.
- [x] Dev play mode can queue available self-target abilities for the selected entity.
- [x] Headless resolver and dev-play-mode tests cover valid use, invalid gates,
  cooldowns, and transforms.
- [x] `make test`, `gdlint`, and `gdformat --check` pass.
