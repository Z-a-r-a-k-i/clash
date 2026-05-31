extends SceneTree

const MATCH_SCENE_PATH := "res://scenes/match.tscn"
const GRID_WIDTH := 64
const GRID_HEIGHT := 40
const UNITS_PER_PLAYER := 15


func _init() -> void:
	var renderer := _make_renderer()
	if renderer == null:
		quit(1)
		return
	var registry := _registry()
	var state := _state()
	renderer.bind_state(state, registry)
	renderer.call("set_perspective_player_id", 0)

	var result: ResolveResult = Resolver.resolve(
		state, SubmitTurn.new(), SubmitTurn.new(), registry, null
	)
	if result == null or result.new_state == null:
		push_error("[profile_renderer_no_movement] resolver returned null")
		_free_renderer(renderer)
		quit(1)
		return

	_measure_render_step(renderer, "resolved_same_layout", result.new_state, result.events)
	_measure_render_step(renderer, "same_state_cache_hit", result.new_state, [])
	_free_renderer(renderer)
	quit(0)


func _make_renderer() -> MatchRenderer:
	var scene: PackedScene = load(MATCH_SCENE_PATH)
	if scene == null:
		push_error("[profile_renderer_no_movement] could not load %s" % MATCH_SCENE_PATH)
		return null
	var renderer: MatchRenderer = scene.instantiate() as MatchRenderer
	if renderer == null:
		push_error(
			"[profile_renderer_no_movement] match scene did not instantiate as MatchRenderer"
		)
		return null
	root.add_child(renderer)
	return renderer


func _free_renderer(renderer: MatchRenderer) -> void:
	if renderer == null:
		return
	if renderer.is_inside_tree():
		root.remove_child(renderer)
	renderer.queue_free()


func _measure_render_step(
	renderer: MatchRenderer, label: String, state: MatchState, events: Array[ResolverEvent]
) -> void:
	var start_usec := Time.get_ticks_usec()
	renderer.render_step(state, events)
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	var fog_root := renderer.get_node_or_null("Overlays/Fog")
	var fog_children := fog_root.get_child_count() if fog_root != null else 0
	print(
		(
			(
				"[profile_renderer_no_movement] case=%s elapsed=%.3fms events=%d "
				+ "entities=%d fog_tiles=%d fog_children=%d"
			)
			% [
				label,
				float(elapsed_usec) / 1000.0,
				events.size(),
				state.entities.size(),
				renderer.fog_overlay_count(),
				fog_children,
			]
		)
	)


func _state() -> MatchState:
	var state := MatchState.new()
	state.tile_grid = TileGrid.new(GRID_WIDTH, GRID_HEIGHT)
	state.players = [_player(0), _player(1)]
	_place_entity(state, "base", 0, Vector2i(2, 2), Vector2i(4, 4))
	_place_entity(state, "base", 1, Vector2i(GRID_WIDTH - 6, GRID_HEIGHT - 6), Vector2i(4, 4))
	for index in range(UNITS_PER_PLAYER):
		var y := 5 + index * 2
		_place_entity(state, "marine", 0, Vector2i(14 + index % 3, y), Vector2i.ONE)
		_place_entity(state, "marine", 1, Vector2i(46 + index % 3, y), Vector2i.ONE)
	for blocker_index in range(8):
		var y := 5 + blocker_index * 4
		_place_entity(state, "blocker", -1, Vector2i(30, y), Vector2i(2, 2))
	return state


func _place_entity(
	state: MatchState, def_id: String, owner: int, origin: Vector2i, footprint: Vector2i
) -> void:
	var entity := Entity.new()
	entity.id = state.allocate_entity_id()
	entity.def_id = def_id
	entity.current_def_id = def_id
	entity.owner_player_id = owner
	entity.origin = origin
	entity.current_hp = 1000
	entity.current_layer = "ground"
	state.entities.append(entity)
	if not state.tile_grid.place(entity.id, Rect2i(origin, footprint)):
		push_error(
			"[profile_renderer_no_movement] failed to place %s at %s" % [def_id, str(origin)]
		)


func _registry() -> EntityRegistry:
	var registry := EntityRegistry.new()
	registry.entities = [
		_def("base", Vector2i(4, 4), 10, ["building", "structure"]),
		_def("marine", Vector2i.ONE, 4, ["ground"]),
		_def("blocker", Vector2i(2, 2), 0, ["building", "blocker"]),
	]
	return registry


func _def(id: String, footprint: Vector2i, sight_radius: int, tags: Array[String]) -> EntityDef:
	var def := EntityDef.new()
	def.id = id
	def.footprint = footprint
	def.tags = tags
	def.health = HealthDef.new()
	def.health.max_hp = 1000
	def.vision = VisionDef.new()
	def.vision.sight_radius = sight_radius
	return def


func _player(id: int) -> PlayerState:
	var player := PlayerState.new()
	player.player_id = id
	player.pop_cap = 30
	player.pop_used = 30
	return player
