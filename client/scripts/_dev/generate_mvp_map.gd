extends SceneTree

# One-shot generator that produces the canonical mvp_map.tscn at
# res://data/scenarios/mvp_map.tscn. Run via:
#   godot --headless --path client --script scripts/_dev/generate_mvp_map.gd
#
# The output .tscn is the source-of-truth for map authoring. Subsequent
# edits should happen in the Godot editor (drag placements, tweak fields)
# rather than re-running this generator. The generator is kept in the
# repo so the map can be re-bootstrapped from scratch if needed.
#
# Layout (50x50, left half):
#   - P1 main (base + 8 patches + geyser + 2 workers) center-left at y=22-26
#   - P1 natural (6 patches + geyser) forward, around x=15-21
#   - P1 expansion (6 patches + geyser) top-left corner around x=3-9
#   - Golden (4 patches + 1 geyser) near axis around x=20-22
#
# All placements live on the LEFT half. Baker generates the right half.

const MAP_SCENE_PATH := "res://data/scenarios/mvp_map.tscn"
const ROOT_SCRIPT_PATH := "res://scripts/data/mvp_map_root.gd"
const PLACEMENT_SCRIPT_PATH := "res://scripts/data/entity_placement.gd"


func _init() -> void:
	var root_script: GDScript = load(ROOT_SCRIPT_PATH)
	var placement_script: GDScript = load(PLACEMENT_SCRIPT_PATH)
	if root_script == null or placement_script == null:
		print("FAIL: failed to load required scripts")
		quit(1)
		return

	var root := Node2D.new()
	root.set_script(root_script)
	root.name = "MvpMap"

	var placements := Node2D.new()
	placements.name = "Placements"
	root.add_child(placements)
	placements.owner = root

	for spec in _all_placements():
		var ep := Node2D.new()
		ep.set_script(placement_script)
		ep.name = spec["name"]
		ep.def_id = spec["def_id"]
		ep.owner_player_id = spec["owner"]
		ep.tile_position = spec["tile"]
		ep.on_axis = spec.get("on_axis", false)
		placements.add_child(ep)
		ep.owner = root

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		print("FAIL: pack returned %d" % pack_err)
		quit(1)
		return

	var save_err := ResourceSaver.save(packed, MAP_SCENE_PATH)
	if save_err != OK:
		print("FAIL: ResourceSaver.save returned %d" % save_err)
		quit(1)
		return

	print("OK: wrote %s with %d placements" % [MAP_SCENE_PATH, placements.get_child_count()])
	quit(0)


func _all_placements() -> Array:
	var out: Array = []

	# ---------- P1 Main (base, workers, minerals, geyser) ----------
	# Base 4x4 at (2, 22) → occupies x=2..5, y=22..25.
	out.append({"name": "P1Main", "def_id": "base", "owner": 0, "tile": Vector2i(2, 22)})
	# 2 starting workers, just east of the base, in the gap between
	# main mineral rows.
	out.append({"name": "P1Worker_1", "def_id": "worker", "owner": 0, "tile": Vector2i(6, 22)})
	out.append({"name": "P1Worker_2", "def_id": "worker", "owner": 0, "tile": Vector2i(6, 25)})
	# Main mineral cluster — 8 patches in two rows of 4 at y=18 and y=24.
	# 1x3 footprint: row at y=18 occupies y=18..20; row at y=24 occupies y=24..26.
	for i in range(4):
		(
			out
			. append(
				{
					"name": "P1MainMineral_top_%d" % i,
					"def_id": "mineral_patch",
					"owner": -1,
					"tile": Vector2i(7 + i, 18),
				}
			)
		)
	for i in range(4):
		(
			out
			. append(
				{
					"name": "P1MainMineral_bot_%d" % i,
					"def_id": "mineral_patch",
					"owner": -1,
					"tile": Vector2i(7 + i, 24),
				}
			)
		)
	# Main geyser 3x3 at (12, 22) — east of mineral cluster.
	out.append(
		{"name": "P1MainGeyser", "def_id": "gas_geyser", "owner": -1, "tile": Vector2i(12, 22)}
	)

	# ---------- P1 Natural (forward of main) ----------
	# 6 mineral patches in two rows of 3 at y=21 and y=27.
	# 1x3 footprint: y=21 occupies y=21..23; y=27 occupies y=27..29.
	for i in range(3):
		(
			out
			. append(
				{
					"name": "P1NaturalMineral_top_%d" % i,
					"def_id": "mineral_patch",
					"owner": -1,
					"tile": Vector2i(15 + i, 21),
				}
			)
		)
	for i in range(3):
		(
			out
			. append(
				{
					"name": "P1NaturalMineral_bot_%d" % i,
					"def_id": "mineral_patch",
					"owner": -1,
					"tile": Vector2i(15 + i, 27),
				}
			)
		)
	# Natural geyser 3x3 at (15, 30) — south of natural minerals, sharing
	# x=15-17 column. Sits clear of the golden cluster (x=21-22, y=22-28).
	(
		out
		. append(
			{
				"name": "P1NaturalGeyser",
				"def_id": "gas_geyser",
				"owner": -1,
				"tile": Vector2i(15, 30),
			}
		)
	)

	# ---------- P1 Expansion (top-left) ----------
	# 6 patches in two rows of 3 at y=4 and y=8.
	for i in range(3):
		(
			out
			. append(
				{
					"name": "P1ExpMineral_top_%d" % i,
					"def_id": "mineral_patch",
					"owner": -1,
					"tile": Vector2i(3 + i, 4),
				}
			)
		)
	for i in range(3):
		(
			out
			. append(
				{
					"name": "P1ExpMineral_bot_%d" % i,
					"def_id": "mineral_patch",
					"owner": -1,
					"tile": Vector2i(3 + i, 9),
				}
			)
		)
	# Expansion geyser 3x3 at (7, 5).
	out.append({"name": "P1ExpGeyser", "def_id": "gas_geyser", "owner": -1, "tile": Vector2i(7, 5)})

	# ---------- Golden (contested neutral, near axis) ----------
	# 4 golden patches at x=21, 22 / y=22, 26 (left half, mirrored to right).
	out.append(
		{
			"name": "Golden_Min_TL",
			"def_id": "mineral_patch_gold",
			"owner": -1,
			"tile": Vector2i(21, 22)
		}
	)
	out.append(
		{
			"name": "Golden_Min_TR",
			"def_id": "mineral_patch_gold",
			"owner": -1,
			"tile": Vector2i(22, 22)
		}
	)
	out.append(
		{
			"name": "Golden_Min_BL",
			"def_id": "mineral_patch_gold",
			"owner": -1,
			"tile": Vector2i(21, 26)
		}
	)
	out.append(
		{
			"name": "Golden_Min_BR",
			"def_id": "mineral_patch_gold",
			"owner": -1,
			"tile": Vector2i(22, 26)
		}
	)
	# Golden geyser 3x3 at (20, 30) (paired with mirror — odd footprint,
	# can't sit on axis).
	(
		out
		. append(
			{
				"name": "Golden_Geyser_L",
				"def_id": "gas_geyser",
				"owner": -1,
				"tile": Vector2i(20, 30),
			}
		)
	)

	return out
