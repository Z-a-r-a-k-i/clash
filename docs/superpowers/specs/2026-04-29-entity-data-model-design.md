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

This doc captures the resolved design from the 2026-04-29 brainstorm session.

## Goals

1. One unified entity data shape — no `UnitDef` / `BuildingDef` split.
2. Capability composition: an entity has a capability (Health, Combat, Movement, etc.) only if it actually has it.
3. Pure-function resolver over POCO runtime data. Determinism is the load-bearing requirement.
4. Authoring story optimised for the Godot inspector: `.tres` Resource files, type-safe sub-resources, hot-editable.
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
| `Id` | string | Stable identifier, e.g. `"marine"`, `"barracks"`. Used for runtime lookup. |
| `DisplayName` | string | Human-readable. Dev-facing only at M0. |
| `Footprint` | Vector2I | Tile dimensions occupied by this entity. |
| `Tags` | string[] | For damage-modifier rules: `"light"`, `"heavy"`, `"biological"`, `"mechanical"`, etc. |
| `DefaultHidden` | bool | True for permanently-invisible entities (e.g. cloak-from-spawn). M0: false everywhere. |

### Capability sub-resources

| Capability | What it grants | Key fields (M0) |
|---|---|---|
| `HealthDef` | Entity is destructible at zero HP. | `MaxHp` |
| `CombatDef` | Entity can fire weapons. | `Damage`, `AttackRange`, `TargetLayers[]`, `AttackModifiers[]`, `AttacksPerTurn` |
| `MovementDef` | Entity can move. | `SpeedTilesPerTurn`, `DefaultLayer`, `PathableTerrainTags[]`, `ImpassableTerrainTags[]` |
| `VisionDef` | Entity reveals fog and (optionally) detects hidden enemies. | `SightRadius`, `DetectionRadius` |
| `PopulationDef` | Entity counts in pop math. | `PopCost`, `PopProvides` |
| `ConstructionDef` | Entity can be built. | `BuildTimeTurns`, `MineralCost`, `GasCost`, `BuiltByTag`, `RequiresTargetTag` |
| `ProductionDef` | Entity has a build queue. | `Produces[]`, `Researches[]`, `QueueCapacity`, `RallyOffset` |
| `GatherDef` | Entity gathers resources. | `GatherPerTurn`, `CarryAmount`, `AcceptsResourceTypes[]` |
| `ResourceSourceDef` | Entity yields resources when gathered from. | `ResourceType`, `YieldPerWorkerPerTurn`, `Capacity`, `RequiresExtractor` |
| `AbilitiesDef` | Entity has abilities. | `Abilities[]` (list of `AbilityDef`) |

The resolver dispatches per capability:

```csharp
foreach (var entity in state.AllEntities) {
    if (entity.Def.Combat != null)     CombatSystem.ResolveTick(entity, ...);
    if (entity.Def.Movement != null)   MovementSystem.ResolveTick(entity, ...);
    if (entity.Def.Production != null) ProductionSystem.ResolveTick(entity, ...);
    // ...
}
```

Null check, dispatch if present. No virtual calls, no inheritance, fully deterministic.

### Worked examples

| Entity | Capabilities |
|---|---|
| Marine | Health + Combat + Movement + Vision + Population + Construction(BuiltByTag="barracks") + Abilities([stim]) |
| Tank | Health + Combat + Movement + Vision + Population + Construction(BuiltByTag="factory") + Abilities([siege_mode]) |
| Siege Tank (alt-form) | Health + Combat(longer range, more damage) + Vision + Population + Construction(none — not built directly) + Abilities([unsiege_mode]) |
| Helicopter | Health + Combat + Movement(DefaultLayer="flying") + Vision + Population + Construction(BuiltByTag="starport") |
| Worker | Health + Combat(weak) + Movement + Vision + Population + Construction(BuiltByTag="base") + Gather |
| Base | Health + Vision + Construction(BuiltByTag="worker") + Production(Produces=[worker], PopProvides=10) |
| Refinery | Health + Vision + Construction(BuiltByTag="worker", RequiresTargetTag="gas_geyser") |
| Barracks / Factory / Starport | Health + Vision + Construction(BuiltByTag="worker") + Production(Produces=[unit list]) |
| Mineral Patch | (footprint only) + ResourceSource(minerals, RequiresExtractor=false) |
| Gas Geyser | (footprint only) + ResourceSource(gas, RequiresExtractor=true) |

## Three orthogonal axes: layers, terrain, visibility

These are kept separate to allow flexible composition.

### Layer (where you exist physically)

A single string field; M0/M1 likely set: `"ground"`, `"flying"`, `"burrowed"`. Open-ended so future layers (`"swimming"`, etc.) can be added without code changes. The layer is part of *runtime state*, not pure def: an entity's `MovementDef` carries a `DefaultLayer`, and abilities can transition `Entity.CurrentLayer` (e.g. burrow toggles ground ↔ burrowed).

Targeting check at the resolver:

```
attacker.Combat.TargetLayers contains target.CurrentLayer  →  CAN hit
                                                       else  CANNOT hit
```

A tank with `TargetLayers = ["ground"]` can't hit a flying target. A marine with `TargetLayers = ["ground", "flying"]` can hit both. Anti-air-only weapons are just `TargetLayers = ["flying"]`.

### Terrain compatibility (which tiles you can occupy)

Per-unit, **not** layer-derived. Each tile carries `terrain_tags: string[]` (e.g. `["water", "ramp", "blocks_burrowed"]`). Each `MovementDef` carries `PathableTerrainTags[]` (terrain tags this unit can occupy) and optional `ImpassableTerrainTags[]` (explicit blockers).

Resolver rule, evaluated per-unit per-tile:

```
unit can occupy tile  iff  (PathableTerrainTags is empty OR tile.terrain_tags overlaps PathableTerrainTags)
                           AND no overlap between tile.terrain_tags and ImpassableTerrainTags
```

ImpassableTerrainTags wins. Empty PathableTerrainTags means "can occupy any non-impassable tile" (the M0 default — open ground only).

This means flying-with-burrow-ability is fine: the unit's own pathing tags decide what it can occupy in either layer. M0 ships with open ground only and minimal terrain tags; the schema slots are present.

### Visibility and detection

Orthogonal to layer. A unit can be on any layer and either visible or hidden. Schema:

- `VisionDef.SightRadius`: what this entity reveals.
- `VisionDef.DetectionRadius`: 0 = not a detector; positive = reveals hidden enemies in radius.
- `EntityDef.DefaultHidden`: true for permanently-invisible entities.
- `Tunables.LayersImplyingHidden`: e.g. `["burrowed"]`.
- `Entity.IsHidden` (runtime, recomputed each turn): `DefaultHidden OR active hide ability OR CurrentLayer ∈ LayersImplyingHidden`, AND no allied detector within `DetectionRadius` of the entity.

Targeting check: target visible to attacker's owner AND attacker can hit target's `CurrentLayer`. Both must be true. M0 ships zero hidden units; schema slots are present for M1+.

## Abilities

```
AbilitiesDef
└── Abilities: AbilityDef[]

AbilityDef
├── Id: string
├── DisplayName: string
├── TargetType: string         "self" | "ally" | "enemy" | "tile" | "area"
├── TargetRange: int           tiles; 0 for self-target
├── Costs: AbilityCost[]
├── CooldownTurns: int
├── CastTimeTurns: int         0 = instant
└── Effect: Effect             polymorphic — what actually happens

AbilityCost
├── Type: string               "hp" | "minerals" | "gas"  (M0; "energy" added later)
└── Amount: int

Effect (abstract base; subclasses)
├── StatBuffEffect             stat overrides for N turns; can target self (buff) or enemy (debuff)
├── TransformEffect            replace entity's CurrentDefId with another EntityDef
└── (later: DamageEffect, HealEffect, SummonEffect, ChannelEffect, AoEEffect)
```

Buff and debuff are the same effect type pointed at different targets (`AbilityDef.TargetType`).

### Worked example: stim (marine)

```
AbilityDef stim
  TargetType = "self"
  TargetRange = 0
  Costs = [{ Type: "hp", Amount: 10 }]
  CooldownTurns = 5
  CastTimeTurns = 0
  Effect = StatBuffEffect { DurationTurns: 3, DamageMult: 1.5, SpeedMult: 1.5 }
```

### Worked example: siege mode (tank)

```
AbilityDef siege_mode
  TargetType = "self"
  TargetRange = 0
  Costs = []
  CooldownTurns = 0
  CastTimeTurns = 1
  Effect = TransformEffect { ToDef: "siege_tank" }
```

The sieged tank is a separate `EntityDef` (`siege_tank.tres`) with different stats and an `unsiege_mode` ability that transforms back. Modes-as-defs matches how SC2 handles transformations internally.

## Runtime entity (POCO, no Godot inheritance)

```csharp
public sealed class Entity
{
    public int Id;                                  // unique runtime id (not the DefId)
    public string DefId;                            // canonical def lookup
    public string CurrentDefId;                     // == DefId unless a TransformEffect swapped it
    public int OwnerPlayerId;
    public Vector2I Origin;
    public string CurrentLayer;                     // may differ from def.Movement.DefaultLayer
    public int CurrentHp;
    public List<Order> OrderQueue;                  // orders queued for this turn's submission
    public Order PersistentOrder;                   // move/attack-move that persists across turns
    public Dictionary<string, int> AbilityCooldowns;
    public List<ActiveBuff> ActiveBuffs;
    public bool IsHidden;                           // recomputed each turn
    public ProductionState Production;              // null if def has no Production capability
    public GatherState Gather;                      // null if def has no Gather capability
}
```

The runtime entity is plain C#: no Godot `Node`, no `Resource`, nothing inherited. This keeps the resolver testable without booting Godot and serializable for save/load and replays.

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
│   ├── EntityRegistry.tres              canonical registry (manual list)
│   └── Tunables.tres                    global tunables
│
├── scripts/                             C# code
│   ├── Data/                            Resource subclasses, one file per class
│   │   ├── EntityDef.cs
│   │   ├── HealthDef.cs, CombatDef.cs, MovementDef.cs, VisionDef.cs, PopulationDef.cs
│   │   ├── ConstructionDef.cs, ProductionDef.cs, GatherDef.cs, ResourceSourceDef.cs
│   │   ├── AbilitiesDef.cs, AbilityDef.cs, AbilityCost.cs, ResearchDef.cs
│   │   ├── EntityRegistry.cs, Tunables.cs, ScenarioDef.cs
│   │   └── Effects/
│   │       ├── Effect.cs                abstract base
│   │       ├── StatBuffEffect.cs
│   │       └── TransformEffect.cs
│   │
│   ├── Runtime/                         POCO state
│   │   ├── MatchState.cs                top-level mutable state for a match
│   │   ├── Entity.cs, PlayerState.cs, ActiveBuff.cs, Order.cs
│   │   ├── ProductionState.cs, GatherState.cs
│   │
│   ├── Resolver/                        pure-function turn resolution
│   │   ├── Resolver.cs                  entry point: Resolve(state, queueA, queueB, registry, tunables)
│   │   ├── CombatSystem.cs, MovementSystem.cs, ProductionSystem.cs
│   │   ├── GatherSystem.cs, AbilitySystem.cs, VisionSystem.cs, Pathfinding.cs
│   │
│   └── Game/                            Godot scene controllers (presentation layer)
│       ├── MatchController.cs           main scene; bridges resolver and rendering
│       ├── EntityRenderer.cs
│       └── DevPlayMode.cs               dev tooling per plan/m0/07-dev-play-mode.md
│
└── tests/                               C# unit tests, no Godot scenes required
    └── Resolver.Tests.cs
```

Subfolders inside `entities/` are designer ergonomics — the registry and resolver treat all `EntityDef`s uniformly regardless of which subfolder.

## Key C# class skeletons

```csharp
[GlobalClass]
public partial class EntityDef : Resource
{
    [Export] public string Id { get; set; } = "";
    [Export] public string DisplayName { get; set; } = "";
    [Export] public Vector2I Footprint { get; set; } = new(1, 1);
    [Export] public string[] Tags { get; set; } = Array.Empty<string>();
    [Export] public bool DefaultHidden { get; set; } = false;

    [Export] public HealthDef Health { get; set; }
    [Export] public CombatDef Combat { get; set; }
    [Export] public MovementDef Movement { get; set; }
    [Export] public VisionDef Vision { get; set; }
    [Export] public PopulationDef Population { get; set; }
    [Export] public ConstructionDef Construction { get; set; }
    [Export] public ProductionDef Production { get; set; }
    [Export] public GatherDef Gather { get; set; }
    [Export] public ResourceSourceDef ResourceSource { get; set; }
    [Export] public AbilitiesDef Abilities { get; set; }
}

[GlobalClass]
public partial class CombatDef : Resource
{
    [Export] public int Damage { get; set; }
    [Export] public int AttackRange { get; set; }
    [Export] public string[] TargetLayers { get; set; } = Array.Empty<string>();
    [Export] public AttackModifier[] AttackModifiers { get; set; } = Array.Empty<AttackModifier>();
    [Export] public int AttacksPerTurn { get; set; } = 1;
}

[GlobalClass]
public partial class AttackModifier : Resource
{
    [Export] public string TargetTag { get; set; } = "";   // matches against target.Tags
    [Export] public float DamageMult { get; set; } = 1.0f; // e.g. 1.5 for "+50% vs heavy"
}

[GlobalClass]
public abstract partial class Effect : Resource { }

[GlobalClass]
public partial class StatBuffEffect : Effect
{
    [Export] public int DurationTurns { get; set; }
    [Export] public float DamageMult { get; set; } = 1.0f;
    [Export] public float SpeedMult { get; set; } = 1.0f;
}

[GlobalClass]
public partial class TransformEffect : Effect
{
    [Export] public EntityDef ToDef { get; set; }
}
```

`[GlobalClass]` makes each class registerable in Godot's editor. An `[Export] Effect Effect { get; set; }` field on `AbilityDef` shows a dropdown of all Effect subclasses; designer picks one and edits its specific fields below.

## Registration and lookup

```csharp
[GlobalClass]
public partial class EntityRegistry : Resource
{
    [Export] public EntityDef[] Entities { get; set; } = Array.Empty<EntityDef>();

    private Dictionary<string, EntityDef> _byId;

    public EntityDef GetById(string id)
    {
        _byId ??= Entities.ToDictionary(e => e.Id);
        return _byId.TryGetValue(id, out var def) ? def : null;
    }
}
```

`EntityRegistry.tres` is hand-maintained: when a designer adds a new entity, they add it to the registry array. Loaded once at match start; resolver references it through `MatchState.Registry`.

Auto-discovery (scan all `.tres` files and infer the registry) is rejected — explicit registry is boring and bulletproof, makes scenarios trivial to swap, and avoids load-order surprises.

## Resolver entry point

```csharp
public static class Resolver
{
    public static (MatchState, ResolvedEvents) Resolve(
        MatchState state,
        TurnSubmission queueA,
        TurnSubmission queueB,
        EntityRegistry registry,
        Tunables tunables)
    {
        // pure: produce a new MatchState + event list, never mutate inputs
    }
}
```

Static, pure. The test harness creates a `MatchState`, calls `Resolve`, asserts on outputs. Replays = recorded `(state, queueA, queueB)` triples; deterministic playback.

## Scenarios

```csharp
[GlobalClass]
public partial class ScenarioDef : Resource
{
    [Export] public PackedScene MapScene { get; set; }
    [Export] public Godot.Collections.Dictionary StartingResourcesPerPlayer { get; set; }
    [Export] public ScenarioPlacement[] Placements { get; set; }
    [Export] public EntityRegistry RegistryOverride { get; set; }   // optional; default = standard
    [Export] public ScenarioStatOverride[] StatOverrides { get; set; } // optional per-instance overrides
}
```

Dev play mode loads a scenario via `ScenarioLoader.Apply(scenario, registry, tunables) -> MatchState`. Per ADR 0018, scenarios can swap the entire registry or override specific stat fields without mutating the canonical `.tres` files.

## Network layer and serialization (decision deferred to M2)

The original scaffolding sketched a Go server + WebSocket + protobuf path (per ADR 0006 and 0007), but that's a tentative direction, not a commitment. The actual networking technology should be picked at M2 when network play by invitation actually has to ship.

### Candidate paths

| Path | What it is | Tradeoffs |
|---|---|---|
| Go server + WebSocket + protobuf | Custom protocol; server logic in Go consuming proto-defined schemas | Most control; standard production pattern; biggest setup; two languages to maintain |
| Headless Godot/C# server + WebSocket (any encoding) | Same engine on both sides; resolver code reused 1:1 | Simpler ops, one codebase; less standard; deployment is a Godot headless binary; scaling unproven |
| Nakama (or similar BaaS) | Backend-as-a-service: matchmaking, accounts, custom server logic in Lua/JS | Fast to ship; covers M3+ features; vendor lock-in; rules in their scripting language |
| Godot built-in MultiplayerAPI (P2P or relay) | Engine's built-in RPC over ENet / WebRTC / WebSocket | Zero setup; can't be server-authoritative without a "host" peer — breaks anti-cheat / determinism guarantees |

### What clash's network needs at M2

- Turn-based, ~one `SubmitTurn` per few seconds. High latency tolerance.
- Server-authoritative resolver, so peer-to-peer is out.
- Low concurrent match counts at M2 (invite-only). Scaling is theoretical.

The simplest path that meets these requirements wins. ADR 0006 (deferred Go server) and ADR 0007 (committed proto code) both stay valid *if* we choose protobuf, and become moot otherwise. No need to lock in either way before M2.

### What this design locks in regardless of network path

- Resolver is a pure function on POCO data. Portable to any wire protocol — proto, JSON, msgpack, Godot-native binary, custom binary.
- `.tres` is the authoring source of truth for static game data. Whatever serialization the network uses, it consumes from these.
- Field types stick to common-denominator primitives (`int`, `float`, `string`, `bool`, arrays). Maps cleanly to proto, JSON, msgpack, or anything else.
- `EntityDef`-level polymorphism (`Effect` subclasses) is C# inheritance at M0 for editor ergonomics. If the wire format chosen at M2 requires a discriminated-union encoding (e.g. proto `oneof`), a thin mapping layer is added then.

### What stays out of any network format

- `PackedScene` references for visual presentation. Engine-side only.
- Editor-only metadata (icons, designer notes). Engine-side only.

A single entity has a *data* half (`marine.tres`, network-shareable) and a *presentation* half (`marine_visual.tscn`, Godot-only). The resolver consumes only the data half.

### Recommendation, advisory only

Headless Godot/C# server is the cheapest M2 path: the resolver code we're building right now ships unchanged to the server, no Go port, no proto schema duplication. Wire format can be JSON for debuggability or whatever's idiomatic for Godot. Revisit if scaling demands it; the pure-function resolver is portable.

Final call deferred to M2.

## Plan tree alignment

The M0 plan tree was updated to reflect this design as part of the same brainstorming session:

- Plan node 00 rewritten around `EntityDef` + capability sub-resources, expanded entity list, and the scenario / registry split.
- Plan node 06 table now has a separate `Layer` column; tags reduced to damage-modifier inputs (light/heavy/biological/mechanical).
- Plan node 02 reworded for the deferred server-and-protocol decision.
- Plan node 07 scenario format aligned with `ScenarioDef.tres`.
- AGENTS.md, ARCHITECTURE.md, PROTOCOL.md, DECISIONS.md (ADR 0006, 0007, 0018, 0019) updated for the same reasons.

Plan nodes 01, 03, 04, 05, 08 carried no stale model language and required no edits.

## M0 implementation checklist

In order:

1. Bootstrap Godot project at `client/` (manual: editor → New Project → C#).
2. Create `client/scripts/Data/` with all `*Def` Resource subclasses.
3. Create `client/scripts/Runtime/` POCO classes.
4. Author `client/data/entities/*` `.tres` files for the M0 entity set.
5. Author `client/data/abilities/stim.tres` and `siege_mode.tres` (+ `unsiege_mode.tres`).
6. Author `client/data/EntityRegistry.tres` and `client/data/Tunables.tres`.
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

- ADR 0007 — Generated proto code is committed.
- ADR 0010 — Multi-tile entity occupancy.
- ADR 0011 — Pop cap 50, variable slot cost.
- ADR 0013 — Deterministic resolution, no RNG by default.
- ADR 0015 — Identical fixed roster at MVP.
- ADR 0016 — Fog of war from day one.
- ADR 0017 — Win condition: raze all enemy buildings, or surrender.
- ADR 0018 — Tunables are data-driven Godot Resources.

Plan nodes affected by this design:

- `plan/m0/00-config-and-tunables.md` — needs rewrite to reflect single `EntityDef` model with capability sub-resources.
- `plan/m0/03-action-queue-and-orders.md` — order types and runtime queue interaction with this entity model.
- `plan/m0/06-combat-and-win.md` — combat resolution against `CombatDef` and `AttackModifier`.
- `plan/m0/07-dev-play-mode.md` — scenario / registry override mechanism.
- `plan/m0/04-economy.md` — `GatherDef` / `ResourceSourceDef` interaction.
- `plan/m0/05-production.md` — `ProductionDef` queue and `ConstructionDef` placement rules.
