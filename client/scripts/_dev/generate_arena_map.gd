extends SceneTree

# One-shot generator that produces the canonical arena_1v1.tscn at
# res://data/scenarios/arena_1v1.tscn (plan/m1/03). Run via:
#   godot --headless --path client --script scripts/_dev/generate_arena_map.gd
#
# Like generate_mvp_map.gd, the output .tscn is the authoring
# source-of-truth; subsequent edits happen in the editor, and the baker
# (run_arena_bake.gd) mirrors the LEFT half across the vertical axis.
#
# Layout (72x56, left half; mirrored for P1):
# - MAIN    base (6,6), 8 minerals + geyser behind it, walled plateau with
#           a single 4-wide choke opening south toward the natural.
# - NATURAL base (8,20) outside the main choke; 8 minerals + geyser; a
#           wall segment east leaves a wider 6-tile choke to the open map.
# - THIRD   base (6,38) along the south edge; 6 minerals + geyser; open
#           approach — held by map control, not walls.
# - CENTER  2 golden mineral patches per side near the axis, plus an
#           on-axis cliff block splitting the north into two lanes.

const MAP_SCENE_PATH := "res://data/scenarios/arena_1v1.tscn"
const ROOT_SCRIPT_PATH := "res://scripts/data/mvp_map_root.gd"
const PLACEMENT_SCRIPT_PATH := "res://scripts/data/entity_placement.gd"
const TERRAIN_PATCH_SCRIPT_PATH := "res://scripts/data/terrain_patch.gd"

const MAP_WIDTH := 72
const MAP_HEIGHT := 56


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

	# ---------- MAIN (walled plateau, choke south) ----------
	out.append({"name": "P0Main", "def_id": "base", "owner": 0, "tile": Vector2i(6, 6)})
	for i in range(4):
		(
			out
			. append(
				{
					"name": "P0MainMineral_top_%d" % (i + 1),
					"def_id": "mineral_patch",
					"owner": -1,
					"tile": Vector2i(5 + i, 4),
				}
			)
		)
	for i in range(4):
		(
			out
			. append(
				{
					"name": "P0MainMineral_west_%d" % (i + 1),
					"def_id": "mineral_patch",
					"owner": -1,
					"tile": Vector2i(4, 6 + i),
				}
			)
		)
	out.append(
		{"name": "P0MainGeyser", "def_id": "gas_geyser", "owner": -1, "tile": Vector2i(2, 2)}
	)
	for i in range(4):
		(
			out
			. append(
				{
					"name": "P0Worker_%d" % (i + 1),
					"def_id": "worker",
					"owner": 0,
					"tile": Vector2i(6 + i, 10),
				}
			)
		)

	# ---------- NATURAL (outside the main choke) ----------
	out.append({"name": "P0Natural", "def_id": "base", "owner": 0, "tile": Vector2i(8, 20)})
	for i in range(4):
		(
			out
			. append(
				{
					"name": "P0NaturalMineral_west_%d" % (i + 1),
					"def_id": "mineral_patch",
					"owner": -1,
					"tile": Vector2i(5, 19 + i),
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
					"tile": Vector2i(6 + i, 25),
				}
			)
		)
	out.append(
		{"name": "P0NaturalGeyser", "def_id": "gas_geyser", "owner": -1, "tile": Vector2i(2, 21)}
	)

	# ---------- THIRD (south edge, open) ----------
	out.append({"name": "P0Third", "def_id": "base", "owner": 0, "tile": Vector2i(6, 38)})
	for i in range(6):
		(
			out
			. append(
				{
					"name": "P0ThirdMineral_%d" % (i + 1),
					"def_id": "mineral_patch",
					"owner": -1,
					"tile": Vector2i(5 + i, 36),
				}
			)
		)
	out.append(
		{"name": "P0ThirdGeyser", "def_id": "gas_geyser", "owner": -1, "tile": Vector2i(2, 39)}
	)

	# ---------- CENTER (contested golds near the axis) ----------
	(
		out
		. append(
			{
				"name": "CenterGold_north",
				"def_id": "mineral_patch_gold",
				"owner": -1,
				"tile": Vector2i(34, 27),
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
				"tile": Vector2i(34, 29),
			}
		)
	)

	return out


func _all_terrain() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# Main plateau east wall: seals x=14..15 down to y=15.
	out.append({"name": "MainWallEast", "position": Vector2i(14, 0), "size": Vector2i(2, 16)})
	# Main plateau south wall: x=0..9, leaving the 4-wide choke x=10..13.
	out.append({"name": "MainWallSouth", "position": Vector2i(0, 14), "size": Vector2i(10, 2)})
	# Natural east wall: y=16..23, leaving a wider gap south of it.
	out.append({"name": "NaturalWallEast", "position": Vector2i(16, 16), "size": Vector2i(2, 8)})
	# On-axis center block: splits the north into two attack lanes.
	(
		out
		. append(
			{
				"name": "CenterBlock",
				"position": Vector2i(32, 10),
				"size": Vector2i(8, 4),
				"on_axis": true,
			}
		)
	)
	return out
