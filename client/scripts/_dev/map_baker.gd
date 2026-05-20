@tool
class_name MapBaker
extends RefCounted

# Bakes an authored map .tscn (with EntityPlacement children under
# `Placements`) into a ScenarioDef .tres consumable by ScenarioLoader.
#
# The map is authored as the LEFT half (or axis-straddling neutrals);
# the baker generates the right half by mirroring across the vertical
# axis at x = map_width / 2. Owner 0 ↔ 1 swap; -1 stays neutral.
#
# Validation is all-or-nothing — any placement violation aborts the
# bake with a clear error pointing at the offending node path. No
# partial output is written to disk.

# Zone classification for pre-mirror validation.
const ZONE_LEFT := 0  # right edge ≤ axis: emit source + mirror
const ZONE_AXIS := 1  # even-footprint, centered, neutral: emit source ONCE
const ZONE_INVALID := 2  # right-half, axis-crossing without on_axis, etc.


# Save baked output to disk. Returns Error code from ResourceSaver, or
# ERR_INVALID_DATA if the bake itself failed.
static func bake(
	map_scene_path: String,
	output_tres_path: String,
	map_width: int,
	map_height: int,
	starting_resources: Dictionary,
	registry: EntityRegistry,
	auto_start_workers_on_minerals: bool = false
) -> Error:
	var sd := bake_to_resource(
		map_scene_path,
		map_width,
		map_height,
		starting_resources,
		registry,
		auto_start_workers_on_minerals
	)
	if sd == null:
		return ERR_INVALID_DATA
	return ResourceSaver.save(sd, output_tres_path)


# In-memory bake from a scene path. Returns null on any failure.
static func bake_to_resource(
	map_scene_path: String,
	map_width: int,
	map_height: int,
	starting_resources: Dictionary,
	registry: EntityRegistry,
	auto_start_workers_on_minerals: bool = false
) -> ScenarioDef:
	if not ResourceLoader.exists(map_scene_path):
		push_error("[MapBaker] Map scene not found: %s" % map_scene_path)
		return null
	var packed: PackedScene = load(map_scene_path)
	if packed == null:
		push_error("[MapBaker] Failed to load map scene: %s" % map_scene_path)
		return null
	var instance := packed.instantiate()
	if instance == null:
		push_error("[MapBaker] Failed to instantiate map scene: %s" % map_scene_path)
		return null
	var sd := bake_to_resource_from_scene(
		instance,
		map_width,
		map_height,
		starting_resources,
		registry,
		auto_start_workers_on_minerals
	)
	instance.queue_free()
	return sd


# In-memory bake from an already-instantiated scene root. Used by tests
# that build a synthetic map tree without writing a .tscn.
static func bake_to_resource_from_scene(
	scene_root: Node,
	map_width: int,
	map_height: int,
	starting_resources: Dictionary,
	registry: EntityRegistry,
	auto_start_workers_on_minerals: bool = false
) -> ScenarioDef:
	if scene_root == null:
		push_error("[MapBaker] scene_root is null.")
		return null
	if registry == null:
		push_error("[MapBaker] registry is null.")
		return null
	if map_width <= 0 or map_height <= 0:
		push_error("[MapBaker] invalid dimensions: %d x %d" % [map_width, map_height])
		return null
	if map_width % 2 != 0:
		push_error(
			(
				(
					"[MapBaker] map_width must be even (got %d). The mirror axis sits "
					+ "between tile (map_width/2 - 1) and (map_width/2)."
				)
				% map_width
			)
		)
		return null
	var placements_node := scene_root.get_node_or_null("Placements")
	if placements_node == null:
		push_error("[MapBaker] scene root missing 'Placements' child.")
		return null

	var result := bake_placements_with_mirror(placements_node, map_width, map_height, registry)
	if not result["ok"]:
		push_error("[MapBaker] %s" % result["error"])
		return null
	var placements: Array[ScenarioPlacement] = result["placements"]
	_sort_placements(placements)

	var sd := ScenarioDef.new()
	sd.map_width = map_width
	sd.map_height = map_height
	sd.starting_resources_per_player = starting_resources
	sd.auto_start_workers_on_minerals = auto_start_workers_on_minerals
	sd.placements = placements
	return sd


# Walk EntityPlacement children, validate, and emit ScenarioPlacements
# (sources + mirrors). Returns:
#   {ok: bool, placements: Array[ScenarioPlacement], error: String}
#
# Children are duck-typed (treated as EntityPlacement-shaped) — accepts
# anything with the expected fields. This avoids requiring the
# EntityPlacement class to be resolvable at parse time, which matters
# for incremental editor reloads.
static func bake_placements_with_mirror(
	placements_node: Node, map_width: int, map_height: int, registry: EntityRegistry
) -> Dictionary:
	var out: Array[ScenarioPlacement] = []
	for child in placements_node.get_children():
		if not _is_placement_node(child):
			continue
		var node_path: String = str(child.get_path()) if child.is_inside_tree() else child.name
		var def_id: String = child.def_id
		var owner_id: int = child.owner_player_id
		var tile_pos: Vector2i = child.tile_position
		var on_axis: bool = child.on_axis
		var hp_override: int = child.initial_hp_override
		var def: EntityDef = registry.get_by_id(def_id)
		if def == null:
			return _fail("Unknown def_id '%s' on %s" % [def_id, node_path])
		var footprint := Vector2i(max(def.footprint.x, 1), max(def.footprint.y, 1))
		if not _in_bounds(tile_pos, footprint, map_width, map_height):
			return _fail(
				(
					"Placement out of bounds at %s (tile=%s, footprint=%s)"
					% [node_path, str(tile_pos), str(footprint)]
				)
			)
		var zone := _classify_zone(tile_pos, footprint, on_axis, owner_id, map_width)
		match zone:
			ZONE_LEFT:
				out.append(_make_placement(def_id, tile_pos, owner_id, hp_override))
				var mirror_x := mirror_x_for(tile_pos.x, footprint.x, map_width)
				var mirror_owner := mirror_owner_for(owner_id)
				out.append(
					_make_placement(
						def_id, Vector2i(mirror_x, tile_pos.y), mirror_owner, hp_override
					)
				)
			ZONE_AXIS:
				out.append(_make_placement(def_id, tile_pos, owner_id, hp_override))
			_:
				return _fail(
					(
						(
							"Right-half or misaligned placement on %s "
							+ "(tile=%s, footprint=%s, on_axis=%s, owner=%d). "
							+ "Author the LEFT half only; or set on_axis=true for "
							+ "even-footprint neutrals centered on the axis."
						)
						% [
							node_path,
							str(tile_pos),
							str(footprint),
							str(on_axis),
							owner_id,
						]
					)
				)
	return {"ok": true, "placements": out, "error": ""}


# ---------- Pure helpers ----------


static func mirror_x_for(source_x: int, footprint_x: int, map_width: int) -> int:
	# Reflects a left-half source x across the vertical axis between
	# tile (map_width/2 - 1) and (map_width/2).
	# Source occupies [source_x, source_x + footprint_x - 1].
	# Mirror occupies [mirror_x, mirror_x + footprint_x - 1].
	# mirror_x = map_width - source_x - footprint_x.
	return map_width - source_x - footprint_x


static func mirror_owner_for(owner_id: int) -> int:
	if owner_id == 0:
		return 1
	if owner_id == 1:
		return 0
	return owner_id  # -1 (neutral) stays -1


# Duck-typed: accepts any node carrying the EntityPlacement fields.
static func _is_placement_node(n: Node) -> bool:
	if n == null:
		return false
	# Use the script class lookup via "in" — present iff fields exist.
	return (
		"def_id" in n
		and "owner_player_id" in n
		and "tile_position" in n
		and "on_axis" in n
		and "initial_hp_override" in n
	)


# Pure: classify a placement by its position + footprint + flags.
static func _classify_zone(
	tile_pos: Vector2i, footprint: Vector2i, on_axis: bool, owner_id: int, map_width: int
) -> int:
	var half: int = map_width / 2
	var right_edge_exclusive := tile_pos.x + footprint.x
	# LEFT: source's right edge does not cross the axis.
	if right_edge_exclusive <= half:
		return ZONE_LEFT
	# AXIS: even footprint, centered exactly on the axis, neutral owner.
	if on_axis and footprint.x % 2 == 0 and tile_pos.x == half - footprint.x / 2 and owner_id == -1:
		return ZONE_AXIS
	return ZONE_INVALID


static func _in_bounds(origin: Vector2i, footprint: Vector2i, w: int, h: int) -> bool:
	if origin.x < 0 or origin.y < 0:
		return false
	if origin.x + footprint.x > w:
		return false
	if origin.y + footprint.y > h:
		return false
	return true


static func _fail(msg: String) -> Dictionary:
	return {
		"ok": false,
		"placements": [] as Array[ScenarioPlacement],
		"error": msg,
	}


static func _make_placement(
	def_id: String, tile_pos: Vector2i, owner_id: int, hp_override: int
) -> ScenarioPlacement:
	var sp := ScenarioPlacement.new()
	sp.def_id = def_id
	sp.owner_player_id = owner_id
	sp.origin = tile_pos
	if hp_override >= 0:
		sp.initial_hp_override = hp_override
	return sp


static func _sort_placements(placements: Array[ScenarioPlacement]) -> void:
	placements.sort_custom(
		func(a: ScenarioPlacement, b: ScenarioPlacement) -> bool:
			if a.owner_player_id != b.owner_player_id:
				return a.owner_player_id < b.owner_player_id
			if a.def_id != b.def_id:
				return a.def_id < b.def_id
			if a.origin.x != b.origin.x:
				return a.origin.x < b.origin.x
			return a.origin.y < b.origin.y
	)
