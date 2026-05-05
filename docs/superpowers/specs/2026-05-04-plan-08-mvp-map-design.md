# Plan-08 — MVP Map (Authoring + Baking) — Design

**Date:** 2026-05-04
**Status:** Draft, pending user review
**Scope:** clash M0 plan node 08 (`plan/m0/08-mvp-map.md`)

## Context

Plan-07a shipped the headless half of dev-play-mode: scenarios load, save/load round-trips, three smoke scenarios are green. The resolver can now be exercised on any `ScenarioDef`. What's missing is a *map* — a single hand-authored battlefield large enough to drive plan-09's manual end-to-end playtest. Plan-08 ships that map plus the authoring pipeline that produces it.

## Goals

1. Author the map in the **Godot 2D scene editor** (drag, snap, multi-select, visual layout) rather than hand-editing `.tres` text.
2. Author **half the map only**; the other half is a guaranteed mirror — fairness enforced by the build step, not eyeballed.
3. Produce a single `mvp_map.tres` that `ScenarioLoader.load()` consumes without changes — keeping the resolver completely unaware of authoring details.
4. Catch authoring mistakes (out-of-bounds, unknown def_id, right-half placements, axis violations) at bake time with clear errors pointing to the offending node.
5. Add one new entity def — `mineral_patch_gold.tres` — to support the map's contested neutral middle base.

## Non-goals

- **No renderer.** No sprites, 3D meshes, cameras. Visual representation is plan-07b's territory.
- **No UI.** Manual turn advance, perspective toggle, debugger — all plan-07b.
- **No additional maps.** One map for M0; map selection / multiple maps post-M0.
- **No terrain types beyond ground.** Choke points emerge from where players build defensive structures, not from authored cliffs/ramps.
- **No fog-of-war asymmetric vision rules.** Existing vision system handles fog uniformly per ADR-0014.
- **No `USE_ABILITY` order type.** Still unwired.

## The map: 7-base symmetric layout

Two players, vertical mirror across the **left↔right axis** (axis line between `x=24` and `x=25` for a 50-wide map). Each player gets:

- **Main** — Base + main mineral cluster (8 patches) + main geyser. Center-left (or center-right for P2), against the map edge.
- **Natural** — Mineral cluster (6 patches) + geyser. Forward of main, toward the map center.
- **Expansion** — Mineral cluster (6 patches) + geyser. Top-left corner (top-right for P2).

Plus one **golden cluster** in the contested middle — `mineral_patch_gold` patches (4 left of axis, 4 mirrored to right) and 2 geysers (one left of axis, mirrored to right). Total: 62 entities in the baked output, 31 authored on the left half.

```text
                              x=24│x=25
   ┌──────────────────────────────┼──────────────────────────────┐
   │ EXP                                                  EXP    │
   │                                                              │
   │ ▓▓ P1 main                                  P2 main ▓▓       │
   │ workers minerals                            minerals workers │
   │ geyser                                              geyser   │
   │            NATURAL              GOLDEN          NATURAL      │
   │            minerals             ●●●●            minerals     │
   │            geyser               ▓▓▓             geyser       │
   │                                 ▓▓▓                          │
   │                                                              │
   └──────────────────────────────┼──────────────────────────────┘
```

## Authoring pipeline

### Source: `mvp_map.tscn`

Authored in Godot's 2D scene editor. Structure:

```text
MvpMap (Node2D, @tool, script: mvp_map_root.gd)
└── Placements (Node2D)
    ├── P1Main (EntityPlacement, def_id=base, owner=0, tile_position=(2,22))
    ├── P1MainMinerals_1..8 (EntityPlacement, def_id=mineral_patch, owner=-1, ...)
    ├── P1MainGeyser (EntityPlacement, def_id=gas_geyser, owner=-1, ...)
    ├── P1Worker_1, P1Worker_2 (EntityPlacement, def_id=worker, owner=0)
    ├── P1Natural_*  ...
    ├── P1Expansion_*  ...
    └── Golden_*  (EntityPlacement, owner=-1, mirrored across axis)
```

Only the **left half + axis-paired neutrals** are authored. The right half is generated.

### `EntityPlacement` node (`client/scripts/data/entity_placement.gd`)

```gdscript
@tool
class_name EntityPlacement
extends Node2D

@export var def_id: String = ""
@export var owner_player_id: int = -1     # -1 = neutral
@export var tile_position: Vector2i = Vector2i.ZERO
@export var initial_hp_override: int = -1 # -1 = use def default
@export var on_axis: bool = false         # only for axis-straddling even-footprint neutrals
```

Editor-time `_draw()` renders a colored rectangle for the entity's footprint and a label with `def_id`. `_ready()` (under `Engine.is_editor_hint()`) snaps `position` to the tile grid via `tile_position * Tunables.tile_pixel_size`.

### Map root script (`client/scripts/data/mvp_map_root.gd`)

`@tool` script attached to the scene root. Three editor-time jobs:

1. Draw the mirror axis line at `x = map_width * tile_pixel_size / 2`.
2. Draw faded ghost previews of every left-half placement reflected to the right half — so the author can see the full battlefield while only editing one side.
3. Validate via `_get_configuration_warnings()`: every placement must be on the left half OR on-axis; `def_id` must resolve in the registry; no two placements may overlap.

### Baker (`client/scripts/_dev/map_baker.gd`)

```gdscript
@tool
class_name MapBaker
extends RefCounted

# Bakes an authored map scene into a ScenarioDef resource.
static func bake(
    map_scene_path: String,
    output_tres_path: String,
    map_width: int,
    map_height: int,
    starting_resources: Dictionary,
    registry: EntityRegistry
) -> Error

static func bake_to_resource(...) -> ScenarioDef  # for tests, no disk write
```

**Algorithm:**

1. Instantiate `map_scene_path`, walk `$Placements` children.
2. For each placement, classify into one of three zones:
   - **Left half** (`tile_position.x + footprint.x ≤ map_width / 2`): emit source + mirror.
   - **On-axis** (`on_axis=true` AND `footprint.x` even AND properly centered): emit once.
   - **Invalid** (anything else): return `ERR_INVALID_DATA` with the node path.
3. Mirror math: `mirror_x = map_width - 1 - source.tile_position.x - footprint.x + 1`. `mirror_owner = (1 - owner)` for owner ∈ {0, 1}, else -1.
4. Sort by `(owner, def_id, x, y)` for stable diffs.
5. Wrap in `ScenarioDef` and `ResourceSaver.save()`.

### Bake triggers

- **(a) Editor button:** `EditorPlugin` in `client/addons/clash_dev/` adds a "Bake MVP Map" item to the Project → Tools menu. Calls `MapBaker.bake(...)` with hardcoded paths for `mvp_map`. Toast on success/failure.
- **(b) File watcher / `_save` hook (rejected):** auto-fire bake when the `.tscn` saves. Rejected because failures are silent in editor consoles — the author wouldn't notice a bake failure until tests fail later.
- **(c) CI parity test:** `_test_mvp_map_bake_parity` re-bakes in-memory and asserts equality with the checked-in `.tres`. Catches "edited the scene, forgot to bake" before merge.

(a) and (c) combine: explicit bake trigger for normal flow + safety net in CI.

## Mirror logic edge cases

The axis is a **line between tiles 24 and 25**, not a tile itself.

| Footprint | On-axis? | Behavior |
|---|---|---|
| 1×1 patch | No | Mirrored normally. Author one, baker emits two. |
| 2×1 / 1×2 (even × odd) | No (mirror produces non-overlapping pair) | Mirrored normally. |
| 2×2 / 4×4 (even width, centered) | Yes if `on_axis=true` and `tile_position.x = map_width/2 - footprint.x/2` | Emitted once, owner must be -1. |
| 3×3 (odd width) | **No.** Cannot be on-axis. | Use paired pattern: author one near axis, baker mirrors. The "golden base" therefore has 2 geysers. |

**Owner rule:** an `on_axis=true` placement must have `owner_player_id = -1`. A player-owned axis-straddling entity would be nonsensical (which player owns it?).

## New entity def: `mineral_patch_gold.tres`

Near-clone of `mineral_patch.tres`. Only `resource_source.capacity` differs:

```text
[sub_resource type="Resource" id="Resource_gold"]
script = ExtResource("resource_source_def.gd")
capacity = 2400          # was 1500 — +60% (matches SC2 gold:standard ratio)

[resource]
id = "mineral_patch_gold"
display_name = "Golden Mineral Patch"
footprint = Vector2i(1, 3)
tags = Array[String](["neutral", "resource_source", "minerals", "golden"])
resource_source = SubResource("Resource_gold")
```

Registered in `entity_registry.tres` alongside `mineral_patch`.

## Updated existing footprint: `mineral_patch`

`Vector2i(2, 1)` → `Vector2i(1, 3)`. Reason: workers must stand on adjacent tiles to gather, and a taller patch gives more adjacency points without forcing wide horizontal sprawl. This change requires re-positioning patches in `economy_full_base.tres`; folded into the same chunk to keep tests green.

## Tunables additions

`tunables.gd` is currently empty (no `@export` fields). Adds:

```gdscript
@export var map_width: int = 50
@export var map_height: int = 50
@export var tile_pixel_size: int = 32       # used by EntityPlacement._snap_to_tile()
@export var starting_minerals: int = 50
@export var starting_gas: int = 0
@export var starting_pop_cap: int = 10
```

Per-scenario starting resources still come from `ScenarioDef.starting_resources_per_player`; Tunables provides the defaults.

Mineral / gas yields stay on each entity def, not in Tunables, per ADR-0019.

## Tests (5 new)

| Name | Asserts |
|---|---|
| `_test_mvp_map_loads` | Loading `mvp_map.tres` produces 50×50 grid, 2 players, expected entity counts by def_id. |
| `_test_mvp_map_is_mirror` | Every player-0 entity has a player-1 counterpart at the mirrored tile coords. Every neutral has a mirror neutral or sits on-axis. |
| `_test_mvp_map_bake_parity` | Re-baking the source `.tscn` matches the checked-in `.tres`. Catches stale-bake commits. |
| `_test_golden_minerals_higher_yield` | After N turns of mining, a worker on `mineral_patch_gold` produces strictly more minerals than one on `mineral_patch`. No specific ratio asserted (lets us retune). |
| `_test_map_baker_validation` | The baker rejects: right-half placements, unknown `def_id`, axis-crossing without `on_axis=true`, on-axis placements with player owner. |

Helpers (`_entity_counts_by_def_id`, `_find_entity_at`, `_scenario_defs_equal`, `_make_test_map_scene`, `_add_placement`) live in `test_resolver.gd` alongside existing plan-07a helpers.

## Files

**Create:**
- `client/scripts/data/entity_placement.gd`
- `client/scripts/data/mvp_map_root.gd`
- `client/scripts/_dev/map_baker.gd`
- `client/addons/clash_dev/plugin.gd`
- `client/addons/clash_dev/plugin.cfg`
- `client/data/entities/neutrals/mineral_patch_gold.tres`
- `client/data/scenarios/mvp_map.tscn`
- `client/data/scenarios/mvp_map.tres`

**Modify:**
- `client/data/entities/neutrals/mineral_patch.tres` (footprint)
- `client/data/entity_registry.tres` (register gold patch)
- `client/data/scenarios/economy_full_base.tres` (re-position for new footprint)
- `client/scripts/data/tunables.gd` (add fields)
- `client/data/tunables.tres` (set values)
- `client/scripts/_dev/test_resolver.gd` (5 tests + helpers)

## Build order

1. **Footprint + gold def + Tunables.** Smallest blast radius. All existing tests green.
2. **`EntityPlacement` + map root + bake skeleton.** Authoring primitives, no map yet.
3. **Bake logic + validation + negative test.** Mirror math, zone classifier, validator. `_test_map_baker_validation` green.
4. **Author `mvp_map.tscn`, bake to `mvp_map.tres`, 4 remaining tests.** Drag placements in editor, click "Bake MVP Map," wire the four loader/mirror/parity/yield tests.

Each chunk independently committable with all tests green at the end.

## Verification

1. Open `res://scripts/_dev/test_resolver_scene.tscn`. Editor log: `[test_resolver] ~95 passed, 0 failed` (90 existing + 5 new).
2. `gdformat --check client/scripts` clean.
3. `gdlint client/scripts` clean.
4. CI proto + gdscript jobs green.
5. Open `res://data/scenarios/mvp_map.tscn` in the editor. Visual sanity check: ghost previews show the full battlefield, axis line visible, no configuration warnings.

## ADRs invoked

- **ADR-0010** (multi-tile occupancy): every placement uses footprint-aware bounds and overlap checks.
- **ADR-0013** (deterministic resolution): the baked `.tres` is itself deterministic — sorted placements, stable mirror math.
- **ADR-0018** (data-driven tunables): map dimensions and starting resources move into Tunables.
- **ADR-0019** (capability composition): `mineral_patch_gold` reuses `resource_source_def`; no new capability shape.
- **ADR-0020** (GDScript-only): all new code is GDScript.
