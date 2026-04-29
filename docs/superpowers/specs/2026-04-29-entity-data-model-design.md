# Entity Data Model and Code Organization — Design

**Date:** 2026-04-29
**Status:** Draft, pending user review
**Scope:** clash M0 (with hooks toward M2 networking)

## Context

clash needs a data model for units, buildings, neutral entities (mineral patches, gas geysers), abilities, and research items. The model must:

- Support fast iteration: dozens of stat retunes per playtest session.
- Stay deterministic-friendly: the resolver must be a pure function, no runtime polymorphism that would muddy reproducibility.
- Compose flexibly: future entities (lift-off buildings, transforming units, neutral creatures, asymmetric race units) must fit without schema rewrites.
- Bridge cleanly to whatever wire format is chosen at M2: schemas use common-denominator primitives so they serialize to any candidate (proto, JSON, msgpack, Godot-native, etc.).

This doc captures the resolved design from the 2026-04-29 brainstorm session. Per ADR 0020 the implementation language is GDScript.

## Goals

1. One unified entity data shape — no `UnitDef` / `BuildingDef` split.
2. Capability composition: an entity has a capability (Health, Combat, Movement, etc.) only if it actually has it.
3. Pure-function resolver over plain-data structures. Determinism is the load-bearing requirement.
4. Authoring story optimised for the Godot inspector: `.tres` Resource files, sub-resources, hot-editable.
5. Forward-compatible with any wire format the M2 network layer chooses. Schemas use common-denominator primitives; no exotic types or hard-to-serialize polymorphism.

## Non-goals

- Implementing the full ability dispatch pipeline at M0. Two flagship abilities (stim, siege) are enough to validate the schema.
- Energy / mana resource at M0. Add when an ability needs it.
- Live balance UI. The "edit `.tres`, reload scenario" loop is fast enough.
- Per-player asymmetric tunables (different stats for A vs B). M0 is symmetric per ADR 0015.
- Decoupling the data layer from Godot Resources at M0. Revisit at M2 alongside the network-layer decision.

## The entity model: capability composition

Every entity in the game — a marine, a barracks, a worker, a mineral patch, a sieged tank — is an `EntityDef`. The def carries a small set of always-present fields plus optional capability sub-resources. A capability being non-null means the entity has that behaviour; null means it doesn't.

### Always-present fields

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | Stable identifier, e.g. `"marine"`, `"barracks"`. Used for runtime lookup. |
| `display_name` | `String` | Human-readable. Dev-facing only at M0. |
| `footprint` | `Vector2i` | Tile dimensions occupied by this entity. |
| `tags` | `Array[String]` | For damage-modifier rules: `"light"`, `"heavy"`, `"biological"`, `"mechanical"`, etc. |
| `default_hidden` | `bool` | True for permanently-invisible entities (e.g. cloak-from-spawn). M0: false everywhere. |

### Capability sub-resources

| Capability | What it grants | Key fields (M0) |
|---|---|---|
| `HealthDef` | Entity is destructible at zero HP. | `max_hp` |
| `CombatDef` | Entity can fire weapons. | `damage`, `attack_range`, `target_layers: Array[String]`, `attack_modifiers: Array[AttackModifier]`, `attacks_per_turn` |
| `MovementDef` | Entity can move. | `speed_tiles_per_turn`, `default_layer`, `pathable_terrain_tags: Array[String]`, `impassable_terrain_tags: Array[String]` |
| `VisionDef` | Entity reveals fog and (optionally) detects hidden enemies. | `sight_radius`, `detection_radius` |
| `PopulationDef` | Entity counts in pop math. | `pop_cost`, `pop_provides` |
| `ConstructionDef` | Entity can be built. | `build_time_turns`, `mineral_cost`, `gas_cost`, `built_by_tag`, `requires_target_tag` |
| `ProductionDef` | Entity has a build queue. | `produces: Array[EntityDef]`, `researches: Array[ResearchDef]`, `queue_capacity`, `rally_offset` |
| `GatherDef` | Entity gathers resources. | `gather_per_turn`, `carry_amount`, `accepts_resource_types: Array[String]` |
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
    # ...
```

Null check, dispatch if present. No virtual calls, no inheritance, fully deterministic.

### Worked examples

| Entity | Capabilities |
|---|---|
| Marine | Health + Combat + Movement + Vision + Population + Construction(built_by="barracks") + Abilities([stim]) |
| Tank | Health + Combat + Movement + Vision + Population + Construction(built_by="factory") + Abilities([siege_mode]) |
| Siege Tank (alt-form) | Health + Combat(longer range, more damage) + Vision + Population + Construction(none — not built directly) + Abilities([unsiege_mode]) |
| Helicopter | Health + Combat + Movement(default_layer="flying") + Vision + Population + Construction(built_by="starport") |
| Worker | Health + Combat(weak) + Movement + Vision + Population + Construction(built_by="base") + Gather |
| Base | Health + Vision + Construction(built_by="worker") + Production(produces=[worker], pop_provides=10) |
| Refinery | Health + Vision + Construction(built_by="worker", requires_target_tag="gas_geyser") |
| Barracks / Factory / Starport | Health + Vision + Construction(built_by="worker") + Production(produces=[unit list]) |
| Mineral Patch | (footprint only) + ResourceSource(minerals, requires_extractor=false) |
| Gas Geyser | (footprint only) + ResourceSource(gas, requires_extractor=true) |

## Three orthogonal axes: layers, terrain, visibility

These are kept separate to allow flexible composition.

### Layer (where you exist physically)

A single string field; M0/M1 likely set: `"ground"`, `"flying"`, `"burrowed"`. Open-ended so future layers (`"swimming"`, etc.) can be added without code changes. The layer is part of *runtime state*, not pure def: an entity's `MovementDef` carries a `default_layer`, and abilities can transition `Entity.current_layer` (e.g. burrow toggles ground ↔ burrowed).

Targeting check at the resolver:

```
attacker.combat.target_layers contains target.current_layer  →  CAN hit
                                                       else  CANNOT hit
```

A tank with `target_layers = ["ground"]` can't hit a flying target. A marine with `target_layers = ["ground", "flying"]` can hit both. Anti-air-only weapons are just `target_layers = ["flying"]`.

### Terrain compatibility (which tiles you can occupy)

Per-unit, **not** layer-derived. Each tile carries `terrain_tags: Array[String]` (e.g. `["water", "ramp", "blocks_burrowed"]`). Each `MovementDef` carries `pathable_terrain_tags` (terrain tags this unit can occupy) and optional `impassable_terrain_tags` (explicit blockers).

Resolver rule, evaluated per-unit per-tile:

```
unit can occupy tile  iff  (pathable_terrain_tags is empty OR tile.terrain_tags overlaps pathable_terrain_tags)
                           AND no overlap between tile.terrain_tags and impassable_terrain_tags
```

`impassable_terrain_tags` wins. Empty `pathable_terrain_tags` means "can occupy any non-impassable tile" (the M0 default — open ground only).

This means flying-with-burrow-ability is fine: the unit's own pathing tags decide what it can occupy in either layer. M0 ships with open ground only and minimal terrain tags; the schema slots are present.

### Visibility and detection

Orthogonal to layer. A unit can be on any layer and either visible or hidden. Schema:

- `VisionDef.sight_radius`: what this entity reveals.
- `VisionDef.detection_radius`: 0 = not a detector; positive = reveals hidden enemies in radius.
- `EntityDef.default_hidden`: true for permanently-invisible entities.
- `Tunables.layers_implying_hidden`: e.g. `["burrowed"]`.
- `Entity.is_hidden` (runtime, recomputed each turn): `default_hidden OR active hide ability OR current_layer in layers_implying_hidden`, AND no allied detector within `detection_radius` of the entity.

Targeting check: target visible to attacker's owner AND attacker can hit target's `current_layer`. Both must be true. M0 ships zero hidden units; schema slots are present for M1+.

## Abilities

```
AbilitiesDef
└── abilities: Array[AbilityDef]

AbilityDef
├── id: String
├── display_name: String
├── target_type: String         "self" | "ally" | "enemy" | "tile" | "area"
├── target_range: int           tiles; 0 for self-target
├── costs: Array[AbilityCost]
├── cooldown_turns: int
├── cast_time_turns: int        0 = instant
└── effect: Effect              polymorphic — what actually happens

AbilityCost
├── type: String                "hp" | "minerals" | "gas"  (M0; "energy" added later)
└── amount: int

Effect (base class via class_name; subclasses extend it)
├── StatBuffEffect              stat overrides for N turns; can target self (buff) or enemy (debuff)
├── TransformEffect             replace entity's current_def_id with another EntityDef
└── (later: DamageEffect, HealEffect, SummonEffect, ChannelEffect, AoEEffect)
```

Buff and debuff are the same effect type pointed at different targets (`AbilityDef.target_type`).

### Worked example: stim (marine)

```
AbilityDef stim
  target_type = "self"
  target_range = 0
  costs = [{ type: "hp", amount: 10 }]
  cooldown_turns = 5
  cast_time_turns = 0
  effect = StatBuffEffect { duration_turns: 3, damage_mult: 1.5, speed_mult: 1.5 }
```

### Worked example: siege mode (tank)

```
AbilityDef siege_mode
  target_type = "self"
  target_range = 0
  costs = []
  cooldown_turns = 0
  cast_time_turns = 1
  effect = TransformEffect { to_def: "siege_tank" }
```

The sieged tank is a separate `EntityDef` (`siege_tank.tres`) with different stats and an `unsiege_mode` ability that transforms back. Modes-as-defs matches how SC2 handles transformations internally.

## Runtime entity (plain GDScript class, no `Node` inheritance)

```gdscript
class_name Entity
extends RefCounted

var id: int                                  # unique runtime id (not the def id string)
var def_id: String                           # canonical def lookup
var current_def_id: String                   # == def_id unless a TransformEffect swapped it
var owner_player_id: int
var origin: Vector2i
var current_layer: String                    # may differ from def.movement.default_layer
var current_hp: int
var order_queue: Array[Order]                # orders queued for this turn's submission
var persistent_order: Order                  # move/attack-move that persists across turns
var ability_cooldowns: Dictionary            # { ability_id: turns_remaining }
var active_buffs: Array[ActiveBuff]
var is_hidden: bool                          # recomputed each turn
var production_state: ProductionState        # null if def has no Production capability
var gather_state: GatherState                # null if def has no Gather capability
```

The runtime entity extends `RefCounted` (not `Node`) so it isn't tied to the scene tree. This keeps the resolver testable without booting a scene and serializable for save/load and replays.

## File layout

```
client/
├── data/                                Godot Resource files (.tres) — canonical data
│   ├── entities/
│   │   ├── units/                       marine.tres, tank.tres, siege_tank.tres, helicopter.tres, worker.tres
│   │   ├── buildings/                   base.tres, refinery.tres, barracks.tres, factory.tres, starport.tres
│   │   └── neutrals/                    mineral_patch.tres, gas_geyser.tres
│   ├── abilities/                       stim.tres, siege_mode.tres, unsiege_mode.tres
│   ├── researches/                      ResearchDef files (placeholder at M0)
│   ├── scenarios/                       default_match.tres + regression scenarios
│   ├── entity_registry.tres             canonical registry (manual list)
│   └── tunables.tres                    global tunables
│
├── scripts/                             GDScript code
│   ├── data/                            Resource subclasses, one file per class
│   │   ├── entity_def.gd
│   │   ├── health_def.gd, combat_def.gd, movement_def.gd, vision_def.gd, population_def.gd
│   │   ├── construction_def.gd, production_def.gd, gather_def.gd, resource_source_def.gd
│   │   ├── abilities_def.gd, ability_def.gd, ability_cost.gd, research_def.gd
│   │   ├── attack_modifier.gd
│   │   ├── entity_registry.gd, tunables.gd, scenario_def.gd
│   │   └── effects/
│   │       ├── effect.gd                base class
│   │       ├── stat_buff_effect.gd
│   │       └── transform_effect.gd
│   │
│   ├── runtime/                         plain-data state classes
│   │   ├── match_state.gd               top-level mutable state for a match
│   │   ├── entity.gd, player_state.gd, active_buff.gd, order.gd
│   │   ├── production_state.gd, gather_state.gd
│   │
│   ├── resolver/                        pure-function turn resolution
│   │   ├── resolver.gd                  entry point: Resolver.resolve(state, queue_a, queue_b, registry, tunables)
│   │   ├── combat_system.gd, movement_system.gd, production_system.gd
│   │   ├── gather_system.gd, ability_system.gd, vision_system.gd, pathfinding.gd
│   │
│   └── game/                            Godot scene controllers (presentation layer)
│       ├── match_controller.gd          main scene; bridges resolver and rendering
│       ├── entity_renderer.gd
│       └── dev_play_mode.gd             dev tooling per plan/m0/07-dev-play-mode.md
│
└── tests/                               GDScript test scenes / GUT-style tests
    └── resolver_test.gd
```

Subfolders inside `entities/` are designer ergonomics — the registry and resolver treat all `EntityDef`s uniformly regardless of which subfolder.

## Key class skeletons

```gdscript
# entity_def.gd
class_name EntityDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var tags: Array[String] = []
@export var default_hidden: bool = false

# Optional capability sub-resources — null if not applicable
@export var health: HealthDef
@export var combat: CombatDef
@export var movement: MovementDef
@export var vision: VisionDef
@export var population: PopulationDef
@export var construction: ConstructionDef
@export var production: ProductionDef
@export var gather: GatherDef
@export var resource_source: ResourceSourceDef
@export var abilities: AbilitiesDef
```

```gdscript
# health_def.gd
class_name HealthDef
extends Resource

@export var max_hp: int = 1
```

```gdscript
# combat_def.gd
class_name CombatDef
extends Resource

@export var damage: int = 0
@export var attack_range: int = 0
@export var target_layers: Array[String] = []
@export var attack_modifiers: Array[AttackModifier] = []
@export var attacks_per_turn: int = 1
```

```gdscript
# attack_modifier.gd
class_name AttackModifier
extends Resource

@export var target_tag: String = ""    # matches against target.tags
@export var damage_mult: float = 1.0   # e.g. 1.5 for "+50% vs heavy"
```

```gdscript
# effects/effect.gd
class_name Effect
extends Resource
# Base class. Subclasses below.
```

```gdscript
# effects/stat_buff_effect.gd
class_name StatBuffEffect
extends Effect

@export var duration_turns: int = 0
@export var damage_mult: float = 1.0
@export var speed_mult: float = 1.0
```

```gdscript
# effects/transform_effect.gd
class_name TransformEffect
extends Effect

@export var to_def: EntityDef
```

In the Godot inspector, `@export var effect: Effect` on `AbilityDef` shows a dropdown of all `Effect` subclasses thanks to `class_name` registration. Designer picks one; properties of that subclass become editable below.

## Registration and lookup

```gdscript
# entity_registry.gd
class_name EntityRegistry
extends Resource

@export var entities: Array[EntityDef] = []

var _by_id: Dictionary = {}

func get_by_id(id: String) -> EntityDef:
    if _by_id.is_empty() and not entities.is_empty():
        for e in entities:
            _by_id[e.id] = e
    return _by_id.get(id)
```

`entity_registry.tres` is hand-maintained: when a designer adds a new entity, they add it to the registry array. Loaded once at match start; resolver references it through `MatchState.registry`.

Auto-discovery (scan all `.tres` files and infer the registry) is rejected — explicit registry is boring and bulletproof, makes scenarios trivial to swap, and avoids load-order surprises.

## Resolver entry point

```gdscript
# resolver.gd
class_name Resolver

static func resolve(
    state: MatchState,
    queue_a: TurnSubmission,
    queue_b: TurnSubmission,
    registry: EntityRegistry,
    tunables: Tunables
) -> ResolveResult:
    # pure: produce a new MatchState + event list, never mutate inputs
    pass
```

Static, pure. The test harness creates a `MatchState`, calls `resolve`, asserts on outputs. Replays = recorded `(state, queue_a, queue_b)` triples; deterministic playback.

## Scenarios

```gdscript
# scenario_def.gd
class_name ScenarioDef
extends Resource

@export var map_scene: PackedScene
@export var starting_resources_per_player: Dictionary
@export var placements: Array[ScenarioPlacement] = []
@export var registry_override: EntityRegistry              # optional; default = standard
@export var stat_overrides: Array[ScenarioStatOverride] = []  # optional per-instance overrides
```

Dev play mode loads a scenario via `ScenarioLoader.apply(scenario, registry, tunables) -> MatchState`. Per ADR 0018, scenarios can swap the entire registry or override specific stat fields without mutating the canonical `.tres` files.

## Network layer and serialization (decision deferred to M2)

The original scaffolding sketched a Go server + WebSocket + protobuf path (per ADR 0006 and 0007), but that's a tentative direction, not a commitment. The actual networking technology should be picked at M2 when network play by invitation actually has to ship.

### Candidate paths

| Path | What it is | Tradeoffs |
|---|---|---|
| Go server + WebSocket + protobuf | Custom protocol; server logic in Go consuming proto-defined schemas | Most control; standard production pattern; biggest setup; resolver port required (Go ≠ GDScript) |
| Headless Godot/GDScript server + WebSocket (any encoding) | Same engine on both sides; resolver code reused 1:1 | Simpler ops, one codebase; less standard; deployment is a Godot headless binary; scaling unproven |
| Nakama (or similar BaaS) | Backend-as-a-service: matchmaking, accounts, custom server logic in Lua/JS | Fast to ship; covers M3+ features; vendor lock-in; rules in their scripting language |
| Godot built-in MultiplayerAPI (P2P or relay) | Engine's built-in RPC over ENet / WebRTC / WebSocket | Zero setup; can't be server-authoritative without a "host" peer — breaks anti-cheat / determinism guarantees |

### What clash's network needs at M2

- Turn-based, ~one `SubmitTurn` per few seconds. High latency tolerance.
- Server-authoritative resolver, so peer-to-peer is out.
- Low concurrent match counts at M2 (invite-only). Scaling is theoretical.

The simplest path that meets these requirements wins. ADR 0006 (deferred server) and ADR 0007 (committed proto code) both stay valid *if* we choose protobuf, and become moot otherwise. No need to lock in either way before M2.

### What this design locks in regardless of network path

- Resolver is a pure function on plain-data structures. Portable to any wire protocol — proto, JSON, msgpack, Godot-native binary, custom binary.
- `.tres` is the authoring source of truth for static game data. Whatever serialization the network uses, it consumes from these.
- Field types stick to common-denominator primitives (`int`, `float`, `String`, `bool`, arrays). Maps cleanly to proto, JSON, msgpack, or anything else.
- `EntityDef`-level polymorphism (`Effect` subclasses) is GDScript inheritance at M0 for editor ergonomics. If the wire format chosen at M2 requires a discriminated-union encoding (e.g. proto `oneof`), a thin mapping layer is added then.

### What stays out of any network format

- `PackedScene` references for visual presentation. Engine-side only.
- Editor-only metadata (icons, designer notes). Engine-side only.

A single entity has a *data* half (`marine.tres`, network-shareable) and a *presentation* half (`marine_visual.tscn`, Godot-only). The resolver consumes only the data half.

### Recommendation, advisory only

Headless Godot/GDScript server is the cheapest M2 path: the resolver code we're building right now ships unchanged to the server, no port. Wire format can be JSON for debuggability or whatever's idiomatic. Revisit if scaling demands it; the pure-function resolver is portable.

If proto is chosen, GDScript-side codegen is [godobuf](https://github.com/oniksan/godobuf). Note godobuf does not support proto `package` directives — use a name-prefix convention (e.g. `ClashV1TurnStart`) instead.

Final call deferred to M2.

## Plan tree alignment

The M0 plan tree was updated to reflect this design as part of the same brainstorming session:

- Plan node 00 rewritten around `EntityDef` + capability sub-resources, expanded entity list, and the scenario / registry split.
- Plan node 06 table now has a separate `Layer` column; tags reduced to damage-modifier inputs (light/heavy/biological/mechanical).
- Plan node 02 reworded for the deferred server-and-protocol decision.
- Plan node 07 scenario format aligned with `ScenarioDef.tres`.
- AGENTS.md, ARCHITECTURE.md, PROTOCOL.md, DECISIONS.md (ADR 0006, 0007, 0018, 0019, 0020) updated for the same reasons.

Plan nodes 01, 03, 04, 05, 08 carried no stale model language and required no edits.

## M0 implementation checklist

In order:

1. Bootstrap Godot project at `client/` (manual: editor → New Project → GDScript, no C# solution).
2. Create `client/scripts/data/` with all `*Def` Resource subclasses (`class_name X extends Resource`).
3. Create `client/scripts/runtime/` plain-data state classes (`extends RefCounted`).
4. Author `client/data/entities/*` `.tres` files for the M0 entity set.
5. Author `client/data/abilities/stim.tres` and `siege_mode.tres` (+ `unsiege_mode.tres`).
6. Author `client/data/entity_registry.tres` and `client/data/tunables.tres`.
7. Implement `Resolver` with a minimal tick loop and one capability system at a time.
8. Author scenario files for combat / economy regression tests.
9. Implement dev play mode UI per `plan/m0/07-dev-play-mode.md`.

## Open questions

These don't block the data model itself but are flagged for resolution during implementation:

- Worker carry capacity / round-trip time tuning. Defer to playtest.
- Mineral patch depletion behaviour: idle worker, or auto-reassign to nearest patch? Default idle at MVP.
- Gas geyser depletion model: finite or infinite at M0? Default infinite at MVP.
- Research effect schema: small DSL, or hardcoded `Effect` subclasses (`StatModifyEffect`, `UnlockUnitEffect`, `EnableAbilityEffect`)? Default to hardcoded effect kinds at M0; expand if needed.
- Refinery destruction handling: workers idle, geyser stays. Confirmed.
- Terrain tag table: empty at M0 (open ground only). Populated as terrain features are added.

## References

ADRs this design implements or depends on:

- ADR 0007 — Generated proto code is committed (conditional on proto being chosen at M2).
- ADR 0010 — Multi-tile entity occupancy.
- ADR 0011 — Pop cap 50, variable slot cost.
- ADR 0013 — Deterministic resolution, no RNG by default.
- ADR 0015 — Identical fixed roster at MVP.
- ADR 0016 — Fog of war from day one.
- ADR 0017 — Win condition: raze all enemy buildings, or surrender.
- ADR 0018 — Tunables are data-driven Godot Resources.
- ADR 0019 — Entity component composition model.
- ADR 0020 — GDScript primary, C# dropped.

Plan nodes affected by this design:

- `plan/m0/00-config-and-tunables.md` — single `EntityDef` model with capability sub-resources.
- `plan/m0/03-action-queue-and-orders.md` — order types and runtime queue interaction with this entity model.
- `plan/m0/06-combat-and-win.md` — combat resolution against `CombatDef` and `AttackModifier`.
- `plan/m0/07-dev-play-mode.md` — scenario / registry override mechanism.
- `plan/m0/04-economy.md` — `GatherDef` / `ResourceSourceDef` interaction.
- `plan/m0/05-production.md` — `ProductionDef` queue and `ConstructionDef` placement rules.
