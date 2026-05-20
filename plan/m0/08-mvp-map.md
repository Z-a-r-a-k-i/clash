---
status: done
depends_on:
  - ./00-config-and-tunables.md
  - ./01-tile-grid-and-occupancy.md
  - ./07-dev-play-mode/07a-scenario-loader-and-save-load.md
---

# MVP map: authoring + baking

A single hand-authored 50×50 map plus the authoring pipeline that produces it.
Plan-07a shipped scenario load/save; this node ships the actual battlefield.
The current first-playtest map is intentionally simple: two mirrored main bases
face each other, and each base has its resource line behind it on the outside
edge away from the opponent.

## Goals

1. Author the map in the **Godot 2D scene editor** (drag, snap, multi-select) rather than hand-editing `.tres` text.
2. Author **half the map only**; the other half is a guaranteed mirror — fairness enforced by the build step, not eyeballed.
3. Produce a single `mvp_map.tres` that `ScenarioLoader.load()` consumes without changes — the resolver remains unaware of authoring details.
4. Catch authoring mistakes (out-of-bounds, unknown def_id, right-half placements, axis violations) at bake time with clear errors pointing to the offending node.
5. Keep map output deterministic so tests catch stale bakes and unfair
   placement drift.

## Non-goals

- **No renderer.** Visual representation is plan-07b's territory.
- **No UI.** Manual turn advance, perspective toggle, debugger — all 07b.
- **No additional maps.** One map for M0; map selection / multiple maps post-M0.
- **No terrain types beyond ground.** Choke points emerge from where players build defensive structures, not from authored cliffs/ramps.
- **No fog-of-war asymmetric vision rules.** Existing vision system handles fog uniformly per ADR-0016.

## Topology

Two-player symmetric layout, vertical mirror across the **left↔right axis** (axis
line between `x=24` and `x=25` for a 50-wide map). Each player gets:

- **Main** — 1 base, 4 workers, 8 standard mineral patches, and 1 gas geyser.
- **Back resource line** — minerals and geyser are placed on the outside/back
  side of the base, away from the opponent, so the opening view reads like a
  StarCraft-style main.
- **Opening economy** — the MVP scenario auto-starts those workers on nearby
  minerals so the first playtest begins with a readable economy loop already in
  motion.

No natural, third, contested gold, ramps, cliffs, or blockers are placed yet.
Total: 28 entities in the baked output, 14 authored on the left half.

```text
                              x=24│x=25
   ┌──────────────────────────────┼──────────────────────────────┐
   │                                                              │
   │ minerals  P0 main                    P1 main  minerals       │
   │ geyser    workers        open        workers   geyser        │
   │ minerals  base           field       base      minerals      │
   │                                                              │
   │                                                              │
   └──────────────────────────────┼──────────────────────────────┘
```

### Why this shape

- Makes the first playtest visually legible before adding strategic map layers.
- Keeps both sides perfectly mirrored for fairness.
- Puts resources behind the base instead of between the base and enemy, matching
  the expected RTS opening shape.
- Avoids blockers until movement/pathfinding can support authored lanes without
  units getting stuck.

## Authoring pipeline

### Source: `mvp_map.tscn`

Authored in Godot's 2D scene editor. Structure:

```text
MvpMap (Node2D, @tool, script: mvp_map_root.gd)
└── Placements (Node2D)
    ├── P0Main (EntityPlacement, def_id=base, owner_player_id=0, tile_position=(12,22))
    ├── P0MainMinerals_1..8 (EntityPlacement, def_id=mineral_patch, owner_player_id=-1, ...)
    ├── P0MainGeyser (EntityPlacement, def_id=gas_geyser, owner_player_id=-1, ...)
    └── P0Worker_1..4 (EntityPlacement, def_id=worker, owner_player_id=0)
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
2. Draw faded ghost previews of every left-half placement reflected to the right half.
3. Validate via `_get_configuration_warnings()`: every placement must be on the left half OR on-axis; `def_id` must resolve in the registry; no two placements may overlap.

### Baker (`client/scripts/_dev/map_baker.gd`)

```gdscript
@tool
class_name MapBaker
extends RefCounted

static func bake(
    map_scene_path: String,
    output_tres_path: String,
    map_width: int,
    map_height: int,
    starting_resources: Dictionary,
    registry: EntityRegistry,
    auto_start_workers_on_minerals: bool = false
) -> Error

static func bake_to_resource(...) -> ScenarioDef  # for tests, no disk write
```

**Algorithm:**

1. Instantiate `map_scene_path`, walk `$Placements` children.
2. For each placement, classify into one of three zones:
   - **Left half** (`tile_position.x + footprint.x ≤ map_width / 2`): emit source + mirror.
   - **On-axis** (`on_axis=true` AND `footprint.x` even AND properly centered): emit once.
   - **Invalid** (anything else): return `ERR_INVALID_DATA` with the node path.
3. Mirror math: `mirror_x = map_width - source.tile_position.x - footprint.x`. `mirror_owner = 1 - owner` for owner ∈ {0, 1}, else `owner` unchanged (e.g. neutrals at -1 stay -1).
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
| 3×3 (odd width) | **No.** Cannot be on-axis. | Use paired pattern: author one near axis, baker mirrors. |

**Owner rule:** an `on_axis=true` placement must have `owner_player_id = -1`. A player-owned axis-straddling entity would be nonsensical (which player owns it?).

## Existing gold mineral def: `mineral_patch_gold.tres`

Near-clone of `mineral_patch.tres`. `resource_source.capacity = 2400` (was 1500 — +60% matches SC2 gold:standard ratio). `yield_per_worker_per_turn = 2` (vs 1 standard) — gold mines faster, not just lasts longer. This def remains registered and covered by tests, but the simplified first-playtest map does not place gold patches yet.

Footprint: `Vector2i(1, 3)`. Tags include `"golden"`.

Registered in `entity_registry.tres` alongside `mineral_patch`.

## Updated existing footprint: `mineral_patch`

`Vector2i(2, 1)` → `Vector2i(1, 3)`. Reason: workers must stand on adjacent tiles to gather, and a taller patch gives more adjacency points without forcing wide horizontal sprawl. This change required re-positioning patches in `economy_full_base.tres`; folded into the same chunk to keep tests green.

## Tunables additions

```gdscript
@export var map_width: int = 50
@export var map_height: int = 50
```

Per-scenario starting resources still come from `ScenarioDef.starting_resources_per_player`; Tunables provides the defaults. Mineral / gas yields stay on each entity def, not in Tunables, per ADR-0019.

## Tests (5 new)

| Name | Asserts |
|---|---|
| `mvp_map_loads` | Loading `mvp_map.tres` produces 50×50 grid, 2 players, exactly 28 expected entities, and four auto-started mineral workers per player. |
| `mvp_map_simple_facing_bases` | Bases face each other on the same row, and each side's resources are behind its base. |
| `mvp_map_is_mirror` | Every player-0 entity has a player-1 counterpart at the mirrored tile coords. Every neutral has a mirror neutral or sits on-axis. |
| `mvp_map_bake_parity` | Re-baking the source `.tscn` matches the checked-in `.tres`. Catches stale-bake commits. |
| `golden_minerals_higher_yield` | Keeps the existing gold mineral def covered even though the simplified playtest map no longer places gold patches. |
| `map_baker_validation` | The baker rejects: right-half placements, unknown `def_id`, axis-crossing without `on_axis=true`, on-axis placements with player owner. |

## Done when

- [x] All capability sub-resource GDScript classes wired to bake step.
- [x] `EntityPlacement`, `MvpMapRoot` `@tool` scripts in `client/scripts/data/`.
- [x] `MapBaker` static class in `client/scripts/_dev/`.
- [x] `client/addons/clash_dev/plugin.gd` + `plugin.cfg` register the "Bake MVP Map" Tools menu item.
- [x] `mvp_map.tscn` authored with 14 left-half placements.
- [x] `mvp_map.tres` baked, 28 entities total.
- [x] `mvp_map.tres` auto-starts four workers per player on nearby minerals.
- [x] `mineral_patch_gold.tres` registered, footprint 1×3, capacity 2400, yield 2.
- [x] `mineral_patch.tres` footprint updated to 1×3.
- [x] `economy_full_base.tres` patch positions adjusted for new footprint.
- [x] Tunables `map_width` / `map_height` defaults set to 50.
- [x] All 5 new tests pass; existing ~90 resolver tests still pass.
- [x] gdformat / gdlint clean.

## ADRs invoked

- **ADR-0010** (multi-tile occupancy): every placement uses footprint-aware bounds and overlap checks.
- **ADR-0013** (deterministic resolution): the baked `.tres` is itself deterministic — sorted placements, stable mirror math.
- **ADR-0018** (data-driven tunables): map dimensions and starting resources move into Tunables.
- **ADR-0019** (capability composition): `mineral_patch_gold` reuses `resource_source_def`; no new capability shape.
- **ADR-0020** (GDScript-only): all new code is GDScript.

## Artifacts

- PR [#8](https://github.com/Z-a-r-a-k-i/clash/pull/8) — merged 2026-05-05
- Merge commit `ed59aa4`
