---
status: sketch
---

# Configuration and tunables

Foundation for everything else in M0. All gameplay values — stats, footprints, costs, timers, tile size — live in Godot Resources, never in code. We will retune dozens of numbers per playtest session; the iteration loop must be "edit `.tres`, reload scenario" with no recompile.

The full data model is specified in `docs/superpowers/specs/2026-04-29-entity-data-model-design.md`. This node is the M0-implementation projection of that spec; refer to the spec for field-level detail.

## Layout

- **Per-entity definitions.** A single `EntityDef` Resource per concrete entity (`marine.tres`, `barracks.tres`, `mineral_patch.tres`, etc.), bundling optional capability sub-resources (`HealthDef`, `CombatDef`, `MovementDef`, `VisionDef`, `PopulationDef`, `ConstructionDef`, `ProductionDef`, `GatherDef`, `ResourceSourceDef`, `AbilitiesDef`). An entity has a capability only if the corresponding sub-resource is non-null.
- **Ability definitions.** One `AbilityDef.tres` per concrete ability (`stim.tres`, `siege_mode.tres`, `unsiege_mode.tres`). Each carries an `Effect` sub-resource (e.g. `StatBuffEffect`, `TransformEffect`).
- **Entity registry.** `EntityRegistry.tres` — a manually-maintained list of all `EntityDef` files. Loaded once at match start; the resolver looks up entity defs by string id through it.
- **Global tunables.** A single `Tunables.tres` for cross-cutting values not bound to an entity: tile pixel size, pop cap, default turn timer, default starting workers / minerals / gas, default mineral patch yield, default gas geyser yield, default vision radii, `LayersImplyingHidden`.
- **Scenario overrides.** `ScenarioDef.tres` files (see node 07) may swap the registry or override individual fields for a single match. Canonical `.tres` files stay untouched.

## Required content (M0)

- **Entities** (12 total):
  - Units (5): `marine`, `tank`, `siege_tank` (alt-form for tank's siege ability), `helicopter`, `worker`.
  - Buildings (5): `base`, `refinery`, `barracks`, `factory`, `starport`.
  - Neutrals (2): `mineral_patch`, `gas_geyser`.
- **Abilities** (3): `stim`, `siege_mode`, `unsiege_mode`.
- **Researches**: placeholder (no concrete researches at M0). Schema slot present.
- **Effects**: at least `StatBuffEffect` and `TransformEffect` to back the M0 abilities.

## Loading and lifetime

- Tunables and the entity registry are loaded once at match start. The resolver receives an immutable `RuleSet` snapshot for the duration of the match.
- Live edits to `.tres` during a running match have no effect until the next match / scenario reload.
- The dev play mode includes a "reload tunables and restart scenario" command (≤ one keypress).

## Out of scope at M0

- Live balance UI with sliders. The "edit + reload" loop is fast enough.
- Per-player asymmetric tunables. M0 is symmetric per ADR 0015.
- Localization of display names. Display names are dev-facing only at M0.

## Open questions

- Project layout for `client/data/`. Default per design spec: `client/data/entities/{units,buildings,neutrals}/`, `client/data/abilities/`, `client/data/scenarios/`. Confirm once the Godot project is bootstrapped.
- How research effects are expressed: small DSL string, or a few hardcoded `Effect` subclasses (`StatModifyEffect`, `UnlockUnitEffect`, `EnableAbilityEffect`)? Default: hardcoded effect kinds; expand if needed.

## Done when

- [ ] All capability sub-resource C# classes (`HealthDef`, `CombatDef`, `MovementDef`, `VisionDef`, `PopulationDef`, `ConstructionDef`, `ProductionDef`, `GatherDef`, `ResourceSourceDef`, `AbilitiesDef`) exist in `client/scripts/Data/`, each marked `[GlobalClass]`.
- [ ] `EntityDef.cs` wraps the capability sub-resources per the design spec.
- [ ] `AbilityDef.cs`, `AbilityCost.cs`, `Effect.cs` (abstract) and `StatBuffEffect.cs`, `TransformEffect.cs` exist.
- [ ] `EntityRegistry.cs` and `Tunables.cs` exist.
- [ ] One `.tres` exists per MVP entity (5 units, 5 buildings, 2 neutrals) with placeholder values.
- [ ] One `.tres` exists per MVP ability (stim, siege_mode, unsiege_mode).
- [ ] `EntityRegistry.tres` lists all 12 entity defs.
- [ ] `Tunables.tres` exists with placeholder global values.
- [ ] Resolver loads tunables and registry at match start; nothing in the resolver references hardcoded numbers.
- [ ] Scenario override mechanism works (test: scenario sets marine HP to 999, dev play confirms).
- [ ] Dev play mode "reload tunables" command works without restarting Godot.
- [ ] A short note in `docs/CONTRIBUTING.md` describes the "I changed a stat" workflow.
