@tool
extends Node

const VisionSystemScript := preload("res://scripts/runtime/vision_system.gd")


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	_run_all()


func _run_all() -> int:
	var passed := 0
	var failed := 0
	var fail_names: Array[String] = []
	for test_pair in _all_tests():
		var test_name: String = test_pair[0]
		var fn: Callable = test_pair[1]
		var ok: bool = fn.call()
		if ok:
			passed += 1
		else:
			failed += 1
			fail_names.append(test_name)
	print("[test_vision_system] %d passed, %d failed" % [passed, failed])
	for test_name in fail_names:
		push_error("  failed: %s" % test_name)
	return failed


func _all_tests() -> Array:
	return [
		["vision_reveals_footprint_and_radius", _test_reveals_footprint_and_radius],
		["vision_clips_to_map_bounds", _test_clips_to_map_bounds],
		["vision_hidden_enemy_requires_detector", _test_hidden_enemy_requires_detector],
		["vision_owned_entities_are_visible", _test_owned_entities_are_visible],
	]


func _test_reveals_footprint_and_radius() -> bool:
	var registry := _registry(
		[
			_def("watcher", Vector2i(2, 2), 2),
		]
	)
	var state := _state(
		[
			{"id": 1, "def_id": "watcher", "owner": 0, "origin": Vector2i(4, 4)},
		],
		registry,
		12,
		12
	)
	var visibility := VisionSystemScript.compute_player_visibility(state, registry, 0)
	var ok := true
	if not visibility.is_tile_visible(Vector2i(4, 4)):
		push_error("entity footprint tile should be visible")
		ok = false
	if not visibility.is_tile_visible(Vector2i(2, 4)):
		push_error("tile within Chebyshev radius from footprint should be visible")
		ok = false
	if visibility.is_tile_visible(Vector2i(1, 4)):
		push_error("tile outside Chebyshev radius should not be visible")
		ok = false
	return ok


func _test_clips_to_map_bounds() -> bool:
	var registry := _registry([_def("scout", Vector2i.ONE, 3)])
	var state := _state(
		[
			{"id": 1, "def_id": "scout", "owner": 0, "origin": Vector2i(0, 0)},
		],
		registry,
		5,
		5
	)
	var visibility := VisionSystemScript.compute_player_visibility(state, registry, 0)
	for tile in visibility.visible_tiles():
		if tile.x < 0 or tile.y < 0 or tile.x >= 5 or tile.y >= 5:
			push_error("visibility included out-of-bounds tile %s" % str(tile))
			return false
	if not visibility.is_tile_visible(Vector2i(0, 0)):
		push_error("origin tile should be visible")
		return false
	if visibility.is_tile_visible(Vector2i(-1, 0)):
		push_error("out-of-bounds tile should not be visible")
		return false
	return true


func _test_hidden_enemy_requires_detector() -> bool:
	var registry := _registry(
		[
			_def("detector", Vector2i.ONE, 6, 2),
			_def("scout", Vector2i.ONE, 6, 0),
			_def("burrowed", Vector2i.ONE, 0, 0),
		]
	)
	var detected_state := _state(
		[
			{"id": 1, "def_id": "detector", "owner": 0, "origin": Vector2i(5, 5)},
			{"id": 2, "def_id": "burrowed", "owner": 1, "origin": Vector2i(7, 5), "hidden": true},
		],
		registry,
		12,
		12
	)
	var detected_visibility := VisionSystemScript.compute_player_visibility(
		detected_state, registry, 0
	)
	if not VisionSystemScript.is_entity_visible_to_player(
		detected_state.entities[1], detected_state, registry, 0, detected_visibility
	):
		push_error("hidden enemy inside detector radius should be visible")
		return false

	var sight_only_state := _state(
		[
			{"id": 1, "def_id": "scout", "owner": 0, "origin": Vector2i(5, 5)},
			{"id": 2, "def_id": "burrowed", "owner": 1, "origin": Vector2i(7, 5), "hidden": true},
		],
		registry,
		12,
		12
	)
	var sight_visibility := VisionSystemScript.compute_player_visibility(
		sight_only_state, registry, 0
	)
	if VisionSystemScript.is_entity_visible_to_player(
		sight_only_state.entities[1], sight_only_state, registry, 0, sight_visibility
	):
		push_error("hidden enemy inside normal sight but outside detection should stay hidden")
		return false
	return true


func _test_owned_entities_are_visible() -> bool:
	var registry := _registry([_def("worker", Vector2i.ONE, 0)])
	var state := _state(
		[
			{"id": 1, "def_id": "worker", "owner": 0, "origin": Vector2i(4, 4)},
		],
		registry,
		8,
		8
	)
	var visibility := VisionSystemScript.compute_player_visibility(state, registry, 0)
	return VisionSystemScript.is_entity_visible_to_player(
		state.entities[0], state, registry, 0, visibility
	)


func _state(entity_specs: Array, registry: EntityRegistry, w: int, h: int) -> MatchState:
	var state := MatchState.new()
	state.tile_grid = TileGrid.new(w, h)
	for pid in [0, 1]:
		var player := PlayerState.new()
		player.player_id = pid
		state.players.append(player)
	for spec in entity_specs:
		var entity := Entity.new()
		entity.id = spec.get("id", state.next_entity_id)
		state.next_entity_id = max(state.next_entity_id, entity.id + 1)
		entity.def_id = spec.get("def_id", "")
		entity.current_def_id = entity.def_id
		entity.owner_player_id = spec.get("owner", -1)
		entity.origin = spec.get("origin", Vector2i.ZERO)
		entity.current_hp = spec.get("hp", 50)
		entity.is_hidden = spec.get("hidden", false)
		state.entities.append(entity)
		var def := registry.get_by_id(entity.current_def_id)
		state.tile_grid.place(entity.id, Rect2i(entity.origin, def.footprint))
	return state


func _registry(defs: Array[EntityDef]) -> EntityRegistry:
	var registry := EntityRegistry.new()
	registry.entities = defs
	return registry


func _def(
	id: String, footprint: Vector2i, sight_radius: int, detection_radius: int = 0
) -> EntityDef:
	var def := EntityDef.new()
	def.id = id
	def.footprint = footprint
	def.health = HealthDef.new()
	def.health.max_hp = 50
	def.vision = VisionDef.new()
	def.vision.sight_radius = sight_radius
	def.vision.detection_radius = detection_radius
	return def
