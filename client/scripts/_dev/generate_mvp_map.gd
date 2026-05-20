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
#   - P0 main base at (12, 22), mirrored to P1 at (34, 22).
#   - Bases face each other across the center of the map.
#   - Each player starts with 4 workers between the base and resources.
#   - Each base has exactly 8 mineral patches + 1 geyser behind it, on
#     the outside edge away from the opponent.
#   - No natural, third, gold base, obstacle, or terrain feature yet.
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


func _all_placements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	# ---------- P0 Main (base, workers, minerals, geyser) ----------
	# Base 4x4 at (12, 22) → occupies x=12..15, y=22..25.
	# P1 is the exact horizontal mirror at x=34..37.
	out.append({"name": "P0Main", "def_id": "base", "owner": 0, "tile": Vector2i(12, 22)})
	# 4 starting workers sit between the base and its back resource line.
	out.append({"name": "P0Worker_1", "def_id": "worker", "owner": 0, "tile": Vector2i(9, 21)})
	out.append({"name": "P0Worker_2", "def_id": "worker", "owner": 0, "tile": Vector2i(10, 21)})
	out.append({"name": "P0Worker_3", "def_id": "worker", "owner": 0, "tile": Vector2i(9, 26)})
	out.append({"name": "P0Worker_4", "def_id": "worker", "owner": 0, "tile": Vector2i(10, 26)})
	# Main mineral cluster — 8 patches behind the base, split into two rows.
	# 1x3 footprint: row at y=18 occupies y=18..20; row at y=27 occupies y=27..29.
	for i in range(4):
		(
			out
			. append(
				{
					"name": "P0MainMineral_top_%d" % i,
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
					"name": "P0MainMineral_bot_%d" % i,
					"def_id": "mineral_patch",
					"owner": -1,
					"tile": Vector2i(7 + i, 27),
				}
			)
		)
	# Main geyser 3x3 at (6, 22) — behind the base, between mineral rows.
	out.append(
		{"name": "P0MainGeyser", "def_id": "gas_geyser", "owner": -1, "tile": Vector2i(6, 22)}
	)

	return out
