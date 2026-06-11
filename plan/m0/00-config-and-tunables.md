---
status: done
---

# Configuration and tunables — entity data model

Foundation for everything else in M0. All gameplay values — stats, footprints, costs, timers, tile size — live in Godot Resources, never in code. We retune dozens of numbers per playtest session; the iteration loop must be "edit `.tres`, reload scenario" with no recompile.

Defines the unified entity data model used by every subsequent node: a single `EntityDef` shape with optional capability sub-resources, dispatched per-capability by the resolver. Originally elaborated in a 2026-04-29 brainstorm session whose design rationale is inlined below.

## Goals

1. One unified entity data shape — no `UnitDef` / `BuildingDef` split.
2. Capability composition: an entity has a capability (Health, Combat, Movement, etc.) only if it actually has it.
3. Pure-function resolver over plain-data structures. Determinism is the load-bearing requirement.
4. Authoring story optimised for the Godot inspector: `.tres` Resource files, sub-resources, hot-editable.
5. Forward-compatible with any wire format the M2 network layer chooses. Schemas use common-denominator primitives.

## Non-goals

- Implementing the full ability dispatch pipeline at M0. Two flagship abilities (stim, siege) are enough to validate the schema.
- Energy / mana resource at M0. Add when an ability needs it.
- Live balance UI. The "edit `.tres`, reload scenario" loop is fast enough.
- Per-player asymmetric tunables. M0 is symmetric per ADR-0015.
- Decoupling the data layer from Godot Resources at M0. Revisit at M2 alongside the network-layer decision.

## Capability composition

Every entity in the game — a marine, a barracks, a worker, a mineral patch, a sieged tank — is an `EntityDef`. The def carries a small set of always-present fields plus optional capability sub-resources. A capability being non-null means the entity has that behaviour; null means it doesn't.

### Always-present fields

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | Stable identifier, e.g. `"marine"`. Used for runtime lookup. |
| `display_name` | `String` | Human-readable. Dev-facing only at M0. |
| `footprint` | `Vector2i` | Tile dimensions occupied by this entity. |
| `tags` | `Array[String]` | Damage-modifier inputs: `"light"`, `"heavy"`, `"biological"`, `"mechanical"`, etc. |
| `default_hidden` | `bool` | True for permanently-invisible entities. M0: false everywhere. |

### Capability sub-resources

| Capability | What it grants | Key fields (M0) |
|---|---|---|
| `HealthDef` | Entity is destructible at zero HP. | `max_hp` |
| `CombatDef` | Entity can fire weapons. | Canonical fields are defined in `client/scripts/data/combat_def.gd` (code is source of truth). |
| `MovementDef` | Entity can move. | `speed_tiles_per_turn`, `default_layer`, `pathable_terrain_tags`, `impassable_terrain_tags` |
| `VisionDef` | Entity reveals fog and (optionally) detects hidden enemies. | `sight_radius`, `detection_radius` |
| `PopulationDef` | Entity counts in pop math. | `pop_cost`, `pop_provides` |
| `ConstructionDef` | Entity can be built. | `build_time_turns`, `mineral_cost`, `gas_cost`, `built_by_tag`, `requires_target_tag` |
| `ProductionDef` | Entity has a build queue. | `produces`, `researches`, `queue_capacity`, `rally_offset` |
| `GatherDef` | Entity gathers resources. | `gather_per_turn`, `carry_amount`, `accepts_resource_types` |
| `ResourceSourceDef` | Entity yields resources when gathered from. | `resource_type`, `yield_per_worker_per_turn`, `capacity`, `requires_extractor` |
| `AbilitiesDef` | Entity has abilities. | `abilities: Array[AbilityDef]` |

The resolver dispatches per capability:

```gdscript
for entity in state.all_entities:
    if entity.def.combat != null:
        CombatSystem.resolve_tick(entity, ...)
    if entity.def.movement != null:
        MovementSystem.resolve_tick(entity, ...)
    if entity.def.production != null:
        ProductionSystem.resolve_tick(entity, ...)
```

Null check, dispatch if present. No virtual calls, no inheritance, fully deterministic.

### Worked examples

| Entity | Capabilities |
|---|---|
| Marine | Health + Combat + Movement + Vision + Population + Construction(`built_by="barracks"`) + Abilities([stim]) |
| Tank | Health + Combat + Movement + Vision + Population + Construction(`built_by="factory"`) + Abilities([siege_mode]) |
| Siege Tank (alt-form) | Health + Combat(longer range) + Vision + Population + Construction(none) + Abilities([unsiege_mode]) |
| Helicopter | Health + Combat + Movement(`default_layer="flying"`) + Vision + Population + Construction(`built_by="starport"`) |
| Worker | Health + Combat(weak) + Movement + Vision + Population + Construction(`built_by="base"`) + Gather |
| Base | Health + Vision + Construction(`built_by="worker"`) + Production(`produces=[worker]`, `pop_provides=10`) |
| Refinery | Health + Vision + Construction(`built_by="worker"`, `requires_target_tag="gas_geyser"`) |
| Barracks / Factory / Starport | Health + Vision + Construction(`built_by="worker"`) + Production(`produces=[unit list]`) |
| Mineral Patch | (footprint only) + ResourceSource(minerals, `requires_extractor=false`) |
| Gas Geyser | (footprint only) + ResourceSource(gas, `requires_extractor=true`) |

## Three orthogonal axes: layers, terrain, visibility

These are kept separate to allow flexible composition.

### Layer (where you exist physically)

A single string field; M0/M1 values: `"ground"`, `"flying"`, `"burrowed"`. Open-ended for future layers. The layer is part of *runtime state*, not pure def: `MovementDef` carries a `default_layer`; abilities can transition `Entity.current_layer`.

Targeting: `attacker.combat.target_layers` contains `target.current_layer` → CAN hit, else CANNOT. Tank with `target_layers = ["ground"]` can't hit flying. Marine with `["ground", "flying"]` hits both.

### Terrain compatibility (which tiles you can occupy)

Per-unit, **not** layer-derived. Each tile carries `terrain_tags`. `MovementDef` carries `pathable_terrain_tags` and `impassable_terrain_tags`. Resolver:

```text
unit can occupy tile  iff  (pathable_terrain_tags is empty OR tile.terrain_tags overlaps pathable_terrain_tags)
                           AND no overlap between tile.terrain_tags and impassable_terrain_tags
```

`impassable_terrain_tags` wins. Empty `pathable_terrain_tags` = "any non-impassable tile" (M0 default).

### Visibility and detection

Orthogonal to layer. A unit can be on any layer and either visible or hidden:

- `VisionDef.sight_radius`: what this entity reveals.
- `VisionDef.detection_radius`: 0 = not a detector; positive = reveals hidden enemies.
- `EntityDef.default_hidden`: true for permanently-invisible.
- `Tunables.layers_implying_hidden`: e.g. `["burrowed"]`.
- `Entity.is_hidden` (runtime): `default_hidden OR active hide ability OR current_layer in layers_implying_hidden`, AND no allied detector within `detection_radius`.

M0 ships zero hidden units; schema slots present for M1+.

## Abilities schema

```text
AbilitiesDef
└── abilities: Array[AbilityDef]

AbilityDef
├── id, display_name
├── target_type: "self" | "ally" | "enemy" | "tile" | "area"
├── target_range: int (tiles; 0 for self-target)
├── costs: Array[AbilityCost]
├── cooldown_turns: int
├── cast_time_turns: int (0 = instant)
└── effect: Effect (polymorphic)

AbilityCost { type: "hp" | "minerals" | "gas", amount: int }

Effect (base)
├── StatBuffEffect      stat overrides for N turns
└── TransformEffect     replace current_def_id with another EntityDef
```

Buff and debuff are the same effect type pointed at different targets via `AbilityDef.target_type`.

### Examples

```text
stim:        target=self,  cost=[hp 10],   cooldown=5, cast=0,  effect=StatBuffEffect{ duration=3, damage_mult=1.5, speed_mult=1.5 }
siege_mode:  target=self,  cost=[],        cooldown=0, cast=1,  effect=TransformEffect{ to_def="siege_tank" }
```

The sieged tank is a separate `EntityDef` (`siege_tank.tres`) with different stats and an `unsiege_mode` ability transforming back. Modes-as-defs matches how SC2 handles transformations internally.

## Runtime entity

```gdscript
class_name Entity
extends Resource

var id: int                                  # unique runtime id (not the def id string)
var def_id: String                           # canonical def lookup
var current_def_id: String                   # == def_id unless TransformEffect swapped it
var owner_player_id: int
var origin: Vector2i
var current_layer: String
var current_hp: int
var order_queue: Array[EntityOrder]
var persistent_order: EntityOrder
var ability_cooldowns: Dictionary
var active_buffs: Array[ActiveBuff]
var is_hidden: bool                          # recomputed each turn
var production_state: ProductionState        # null if no Production capability
var gather_state: GatherState                # null if no Gather capability
```

Per plan-07a, runtime types extend `Resource` with `@export` annotations so save/load round-trips them via `ResourceSaver` / `ResourceLoader` natively. (Originally `RefCounted`; switched to `Resource` for save-ergonomics.)

## File layout

```text
client/
├── data/                                Godot Resource files (.tres) — canonical data
│   ├── entities/
│   │   ├── units/                       marine.tres, tank.tres, siege_tank.tres, helicopter.tres, worker.tres
│   │   ├── buildings/                   base.tres, refinery.tres, barracks.tres, factory.tres, starport.tres
│   │   └── neutrals/                    mineral_patch.tres, mineral_patch_gold.tres, gas_geyser.tres
│   ├── abilities/                       stim.tres, siege_mode.tres, unsiege_mode.tres
│   ├── researches/                      stim_research.tres, siege_mode_research.tres
│   ├── scenarios/                       smoke_minimal.tres, combat_marines_vs_tanks.tres, economy_full_base.tres, mvp_map.tres
│   ├── entity_registry.tres
│   └── tunables.tres
│
├── scripts/
│   ├── data/                            Resource subclasses
│   │   ├── entity_def.gd
│   │   ├── health_def.gd, combat_def.gd, movement_def.gd, vision_def.gd, population_def.gd
│   │   ├── construction_def.gd, production_def.gd, gather_def.gd, resource_source_def.gd
│   │   ├── abilities_def.gd, ability_def.gd, ability_cost.gd, research_def.gd
│   │   ├── attack_modifier.gd
│   │   ├── entity_registry.gd, tunables.gd, scenario_def.gd, scenario_placement.gd, scenario_stat_override.gd
│   │   ├── entity_placement.gd, mvp_map_root.gd                    (plan-08 authoring)
│   │   └── effects/
│   │       ├── effect.gd, stat_buff_effect.gd, transform_effect.gd
│   │
│   ├── runtime/                         plain-data state classes (extends Resource)
│   │   ├── match_state.gd, entity.gd, player_state.gd, active_buff.gd
│   │   ├── order.gd, submit_turn.gd, order_builder.gd
│   │   ├── production_state.gd, gather_state.gd, tile_grid.gd
│   │   ├── scenario_loader.gd, match_saver.gd, saved_session.gd, loaded_scenario.gd
│   │
│   ├── resolver/                        pure-function turn resolution
│   │   ├── resolver.gd, resolve_result.gd, resolver_event.gd
│   │   ├── _state_helpers.gd
│   │   ├── combat_system.gd, movement_system.gd, production_system.gd
│   │   ├── gather_system.gd, construction_system.gd, end_of_turn_system.gd
│   │
│   ├── game/                            scene controllers (presentation layer; plan-07b)
│   │
│   └── _dev/                            development tools and tests
│       ├── generate_placeholder_data.gd, generate_mvp_map.gd, run_mvp_bake.gd
│       ├── map_baker.gd
│       ├── test_resolver.gd, test_tile_grid.gd
│       └── test_resolver_scene.tscn, test_tile_grid_scene.tscn
│
└── addons/
    └── clash_dev/                       EditorPlugin for "Bake MVP Map" Tools menu item
```

## M0 required content

- **Entities** (13 total):
  - Units (5): `marine`, `tank`, `siege_tank` (alt-form), `helicopter`, `worker`.
  - Buildings (5): `base`, `refinery`, `barracks`, `factory`, `starport`.
  - Neutrals (3): `mineral_patch`, `mineral_patch_gold`, `gas_geyser`.
- **Abilities** (3): `stim`, `siege_mode`, `unsiege_mode`.
- **Researches** (2): `stim_research`, `siege_mode_research`.
- **Effects**: `StatBuffEffect`, `TransformEffect`.

## Loading and lifetime

- Tunables and the entity registry are loaded once at match start. The resolver receives an immutable `RuleSet` snapshot for the duration of the match.
- Live edits to `.tres` during a running match have no effect until the next match / scenario reload.
- The dev play mode includes a "reload tunables and restart scenario" command (≤ one keypress, plan-07b).

## Network layer and serialization (deferred to M2)

This design locks in:
- Resolver is a pure function on plain-data structures. Portable to any wire protocol — proto, JSON, msgpack, Godot-native.
- `.tres` is the authoring source of truth.
- Field types stick to common-denominator primitives.
- Polymorphism (`Effect` subclasses) is GDScript inheritance at M0; if proto's `oneof` is needed at M2, a thin mapping layer is added then.

What stays out of any network format: `PackedScene` references, editor-only metadata. Each entity has a *data* half (network-shareable) and a *presentation* half (Godot-only).

Final wire-format call deferred to M2. Advisory recommendation is headless Godot/GDScript server (resolver code ships unchanged), but Go-server-with-protobuf or Nakama remain valid options.

## Done when

- [x] All capability sub-resource GDScript classes exist in `client/scripts/data/`.
- [x] `entity_def.gd` (`class_name EntityDef`) wraps the capability sub-resources.
- [x] `ability_def.gd`, `ability_cost.gd`, `effect.gd`, `stat_buff_effect.gd`, `transform_effect.gd` exist.
- [x] `entity_registry.gd` and `tunables.gd` exist.
- [x] One `.tres` exists per MVP entity (5 units, 5 buildings, 3 neutrals).
- [x] One `.tres` exists per MVP ability.
- [x] `EntityRegistry.tres` lists all entity defs.
- [x] `Tunables.tres` exists with placeholder global values.
- [x] Resolver loads tunables and registry at match start; nothing in the resolver references hardcoded numbers.
- [x] Scenario override mechanism works (`stat_overrides` clone-and-patch the registry).

## ADRs invoked

- **ADR-0010** (multi-tile occupancy)
- **ADR-0013** (deterministic resolution)
- **ADR-0015** (identical fixed roster at MVP)
- **ADR-0018** (data-driven tunables)
- **ADR-0019** (entity component composition model)
- **ADR-0020** (GDScript primary, C# dropped)

## Artifacts

- PR [#1](https://github.com/Z-a-r-a-k-i/clash/pull/1) — initial M0 data layer, runtime classes, tile grid (covers nodes 00 + 01).
- 07a converted runtime classes from `RefCounted` to `Resource` for save-ergonomics.
- 08 added `mineral_patch_gold` and the `EntityVisuals`-adjacent placeholders.
