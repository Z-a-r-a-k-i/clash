---
status: done
---

# 1v1 map — three bases per player (SC2-inspired)

A real competitive layout to replace the facing-playtest map: each player has
a **main**, a **natural**, and a **third**, with chokes and a contested
center. Inspired by SC2 1v1 staples (main/nat/third economy arc, defensible
natural choke, increasingly exposed third).

## Layout sketch

- Rotational (180°) symmetry for fairness — both spawns see identical
  distances and resource geometry. A baked symmetry check belongs in tests,
  not in code review.
- Per player:
  - **Main**: base + ~8 mineral patches + 1 geyser, single choke out.
  - **Natural**: directly outside the main's choke; ~8 patches + 1 geyser;
    its own wider choke toward the map.
  - **Third**: along the map edge or toward center — farther, harder to hold;
    ~6 patches + 1 geyser.
- **Center**: open engagement ground with 2 contested golden mineral patches
  (`mineral_patch_gold` already exists) as the fight-worth-taking objective.
- Chokes are impassable-terrain bands (cliff/water tags) — the terrain tag
  system already gates movement; this map is the first real consumer.
  No ramps/high-ground mechanics at M1 (vision-over-cliff rules are a later
  design node); chokes + distance do the strategic work.
- Size: roughly 1.5–2× the current MVP map; exact tile dims tuned so the
  cross-map attack distance ≈ 2–3 turns of marine movement (speeds are
  per-turn tile budgets — distance IS tempo in a WeGo game).

## Build

- Author via the existing baker pipeline (`map_baker.gd`,
  `generate_mvp_map.gd`, plan-08 conventions) → a `ScenarioDef` .tres like
  `mvp_map`, loadable in dev play, network play, and the simulator.
- The scenario loader and renderer already handle everything needed; this is
  a content + tooling node, not an engine node.

## Done when

- [x] Map loads in dev play and network play; full match playable on it.
- [x] Symmetry test: per-player resource counts, base geometry, and spawn
      distances are mirror-identical.
- [ ] Choke widths verified: a sieged tank + small force can hold the natural
      choke against a frontal marine attack of equal value (playtest note —
      pending a human playtest).
- [ ] Simulator (node 02) defaults to this map (the simulator does not
      exist yet; dev play and the network server default to it already).

## Artifacts

- Terrain plumbing end-to-end: `ScenarioTerrainPatch` (+ `terrain_patches`
  on `ScenarioDef`), `TerrainPatch` authoring node, `MapBaker` terrain
  mirroring/validation (including placement-on-terrain bake failures),
  `ScenarioLoader` grid application, `TileGrid.terrain_tiles()`, renderer
  placeholder paint, ground units carry `impassable_terrain_tags=["cliff"]`,
  and BUILD placement rejects `UNBUILDABLE_TERRAIN_TAGS` tiles.
- `generate_arena_map.gd` → `arena_1v1.tscn` (authoring canon) and
  `run_arena_bake.gd` → `arena_1v1.tres` (72x56; main/natural/third per
  player; walled main with a 4-wide choke; on-axis center cliff block; two
  golden patches per side near the axis).
- Symmetry decision: kept the baker's horizontal mirror (equally fair to
  both players) instead of adding a 180-degree rotation mode.
- Tests: `test_arena_map.gd` (symmetry, terrain round-trip, ground-vs-air
  choke pathing, build rejection on cliffs, bake rejection, full-resolve
  smoke), wired into `make test`.
- Dev play and the network hub/server default to `arena_1v1.tres`;
  `mvp_map` remains for existing regressions.
