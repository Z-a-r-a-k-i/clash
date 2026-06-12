extends SceneTree

# One-shot generator that produces the canonical arena_1v1.tscn at
# res://data/scenarios/arena_1v1.tscn (plan/m1/03). Run via:
#   godot --headless --path client --script scripts/_dev/generate_arena_map.gd
#
# Like generate_mvp_map.gd, the output .tscn is the authoring
# source-of-truth; subsequent edits happen in the editor, and the baker
# (run_arena_bake.gd) mirrors the LEFT half across the vertical axis.
#
# Layout (80x60, left half; mirrored for P1). Players start with ONE
# pre-built base (the main); the natural is an unclaimed resource field
# they expand to by building a new base.
# - MAIN    base (8,8) on a roomy 20x20 plateau; 8 minerals + geyser
#           behind it. Two short walls leave TWO entrances: a 6-tall
#           east gap and a 6-wide south gap — defendable, but flankable.
# - NATURAL resource field to the south in a soft pocket (one short east
#           wall, open north and south).
# - LANES   an on-axis north block, a mid-field island per side, and an
#           on-axis south block split the open ground into north /
#           center / south attack lanes around the contested golds.

const MAP_SCENE_PATH := "res://data/scenarios/arena_1v1.tscn"
const ROOT_SCRIPT_PATH := "res://scripts/data/mvp_map_root.gd"
const PLACEMENT_SCRIPT_PATH := "res://scripts/data/entity_placement.gd"
const TERRAIN_PATCH_SCRIPT_PATH := "res://scripts/data/terrain_patch.gd"

const MAP_WIDTH := 80
const MAP_HEIGHT := 60


func _init() -> void:
	var root_script: GDScript = load(ROOT_SCRIPT_PATH)
	var placement_script: GDScript = load(PLACEMENT_SCRIPT_PATH)
	var terrain_script: GDScript = load(TERRAIN_PATCH_SCRIPT_PATH)
	if root_script == null or placement_script == null or terrain_script == null:
		print("FAIL: failed to load required scripts")
		quit(1)
		return

	var root := Node2D.new()
	root.set_script(root_script)
	root.name = "Arena1v1"

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

	var terrain := Node2D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	terrain.owner = root
	for spec in _all_terrain():
		var tp := Node2D.new()
		tp.set_script(terrain_script)
		tp.name = spec["name"]
		tp.rect_position = spec["position"]
		tp.rect_size = spec["size"]
		tp.terrain_tags = spec.get("tags", ["cliff"] as Array[String])
		tp.on_axis = spec.get("on_axis", false)
		terrain.add_child(tp)
		tp.owner = root

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		print("FAIL: pack failed")
		quit(1)
		return
	if ResourceSaver.save(packed, MAP_SCENE_PATH) != OK:
		print("FAIL: save failed")
		quit(1)
		return
	print(
		(
			"OK: wrote %s with %d placements, %d terrain patches"
			% [MAP_SCENE_PATH, placements.get_child_count(), terrain.get_child_count()]
		)
	)
	quit(0)


func _all_placements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	# ---------- MAIN (roomy plateau, two entrances) ----------
	out.append({"name": "P0Main", "def_id": "base", "owner": 0, "tile": Vector2i(8, 8)})
	for i in range(8):
		(
			out
			. append(
				{
					"name": "P0MainMineral_%d" % (i + 1),
					"def_id": "mineral_patch",
					"owner": -1,
					"tile": Vector2i(6 + i, 5),
				}
			)
		)
	out.append(
		{"name": "P0MainGeyser", "def_id": "gas_geyser", "owner": -1, "tile": Vector2i(3, 3)}
	)
	for i in range(4):
		(
			out
			. append(
				{
					"name": "P0Worker_%d" % (i + 1),
					"def_id": "worker",
					"owner": 0,
					"tile": Vector2i(8 + i, 13),
				}
			)
		)

	# ---------- NATURAL (resource field only; players expand here) ----------
	for i in range(4):
		(
			out
			. append(
				{
					"name": "P0NaturalMineral_west_%d" % (i + 1),
					"def_id": "mineral_patch",
					"owner": -1,
					"tile": Vector2i(5, 26 + i),
				}
			)
		)
	for i in range(4):
		(
			out
			. append(
				{
					"name": "P0NaturalMineral_south_%d" % (i + 1),
					"def_id": "mineral_patch",
					"owner": -1,
					"tile": Vector2i(6 + i, 32),
				}
			)
		)
	out.append(
		{"name": "P0NaturalGeyser", "def_id": "gas_geyser", "owner": -1, "tile": Vector2i(2, 29)}
	)

	# ---------- CENTER (contested golds near the axis) ----------
	(
		out
		. append(
			{
				"name": "CenterGold_north",
				"def_id": "mineral_patch_gold",
				"owner": -1,
				"tile": Vector2i(38, 29),
			}
		)
	)
	(
		out
		. append(
			{
				"name": "CenterGold_south",
				"def_id": "mineral_patch_gold",
				"owner": -1,
				"tile": Vector2i(38, 31),
			}
		)
	)

	return out


func _all_terrain() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# Main east wall: x=18..19, y=0..11; the 6-tall east entrance is the
	# gap y=12..17 between this wall and the south wall.
	out.append({"name": "MainWallEast", "position": Vector2i(18, 0), "size": Vector2i(2, 12)})
	# Main south wall: x=0..11, y=18..19; the 6-wide south entrance is the
	# gap x=12..17.
	out.append({"name": "MainWallSouth", "position": Vector2i(0, 18), "size": Vector2i(12, 2)})
	# Natural pocket wall: a single short segment east of the field; the
	# pocket stays open north and south.
	out.append({"name": "NaturalWallEast", "position": Vector2i(16, 26), "size": Vector2i(2, 8)})
	# Mid-field island: separates the natural lane from the center golds.
	out.append({"name": "MidIsland", "position": Vector2i(26, 24), "size": Vector2i(4, 8)})
	# On-axis north block: splits the top into two attack lanes.
	(
		out
		. append(
			{
				"name": "NorthBlock",
				"position": Vector2i(36, 10),
				"size": Vector2i(8, 6),
				"on_axis": true,
			}
		)
	)
	# On-axis south block: splits the bottom lane.
	(
		out
		. append(
			{
				"name": "SouthBlock",
				"position": Vector2i(37, 44),
				"size": Vector2i(6, 6),
				"on_axis": true,
			}
		)
	)
	return out
