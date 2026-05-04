@tool
class_name MapBaker
extends RefCounted

# Bakes an authored map .tscn (with EntityPlacement children under
# `Placements`) into a ScenarioDef .tres consumable by ScenarioLoader.
#
# Plan-08 chunk 2 ships this skeleton: it instantiates the source scene,
# walks placements verbatim (no mirror logic, no validation), and emits a
# ScenarioDef. Chunks 3 fills in the mirror math + zone classification +
# validation. Chunk 4 authors the actual mvp_map.tscn.


# Save baked output to disk. Returns Error code from ResourceSaver, or
# ERR_INVALID_DATA if the bake itself failed.
static func bake(
	map_scene_path: String,
	output_tres_path: String,
	map_width: int,
	map_height: int,
	starting_resources: Dictionary,
	registry: EntityRegistry
) -> Error:
	var sd := bake_to_resource(map_scene_path, map_width, map_height, starting_resources, registry)
	if sd == null:
		return ERR_INVALID_DATA
	return ResourceSaver.save(sd, output_tres_path)


# In-memory bake: returns the ScenarioDef without writing to disk. Used
# by tests (parity check, validation negatives) so they don't pollute
# the project tree.
static func bake_to_resource(
	map_scene_path: String,
	map_width: int,
	map_height: int,
	starting_resources: Dictionary,
	registry: EntityRegistry
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
	var sd: ScenarioDef = null
	# Always free the instance, even on error.
	var err_msg := ""
	var ok := false
	# Inline try/finally pattern — Godot has no try/finally, so we structure
	# manually and free at the end.
	while true:
		var placements_node := instance.get_node_or_null("Placements")
		if placements_node == null:
			err_msg = "Map scene missing 'Placements' child."
			break
		var placements_out: Array[ScenarioPlacement] = bake_placements(
			placements_node, map_width, registry
		)
		if placements_out == null:
			err_msg = "Placement walk failed (see prior errors)."
			break
		# Stable order for deterministic .tres diffs.
		_sort_placements(placements_out)
		sd = ScenarioDef.new()
		sd.map_width = map_width
		sd.map_height = map_height
		sd.starting_resources_per_player = starting_resources
		sd.placements = placements_out
		ok = true
		break
	instance.queue_free()
	if not ok:
		push_error("[MapBaker] %s" % err_msg)
		return null
	return sd


# Walk EntityPlacement children and emit ScenarioPlacements. Skeleton
# version: copies each placement verbatim (no mirroring, no validation).
# Chunk 3 replaces this with the full pipeline.
static func bake_placements(
	placements_node: Node, _map_width: int, _registry: EntityRegistry
) -> Array[ScenarioPlacement]:
	var out: Array[ScenarioPlacement] = []
	for child in placements_node.get_children():
		if not (child is EntityPlacement):
			continue
		var ep: EntityPlacement = child
		out.append(_make_scenario_placement(ep, ep.tile_position, ep.owner_player_id))
	return out


static func _make_scenario_placement(
	ep: EntityPlacement, tile_pos: Vector2i, owner_id: int
) -> ScenarioPlacement:
	var sp := ScenarioPlacement.new()
	sp.def_id = ep.def_id
	sp.owner_player_id = owner_id
	sp.origin = tile_pos
	if ep.initial_hp_override >= 0:
		sp.initial_hp_override = ep.initial_hp_override
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
