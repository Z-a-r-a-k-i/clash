extends SceneTree

const OUT_DIR := "res://../docs/visual-references"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry: EntityRegistry = load("res://data/entity_registry.tres")
	var tunables: Tunables = load("res://data/tunables.tres")
	var state := _battle_state(registry)
	var renderer: Node3D = (load("res://scenes/match_3d.tscn") as PackedScene).instantiate()
	root.add_child(renderer)
	renderer.bind_state(state, registry)
	renderer.set_turn_playback_enabled(true)
	await _frames(5)
	_capture("battle3d_start.png")
	var orders := SubmitTurn.new()
	for marine_id in [2, 3, 4]:
		var order := EntityOrder.new()
		order.type = EntityOrder.Type.MOVE
		order.entity_id = marine_id
		order.target_tile = Vector2i(10, 4 + marine_id)
		orders.orders.append(order)
	var empty := SubmitTurn.new()
	var result := Resolver.resolve(state, orders, empty, registry, tunables)
	state = result.new_state
	renderer.render_step(state, result.events)
	await _frames(6)
	_capture("battle3d_glide.png")
	await _frames(30)
	_capture("battle3d_fire_a.png")
	await _frames(10)
	_capture("battle3d_fire_b.png")
	await _frames(70)
	result = Resolver.resolve(state, SubmitTurn.new(), SubmitTurn.new(), registry, tunables)
	state = result.new_state
	renderer.render_step(state, result.events)
	await _frames(8)
	_capture("battle3d_fire_c.png")
	await _frames(70)
	_capture("battle3d_after.png")
	quit(0)


func _battle_state(registry: EntityRegistry) -> MatchState:
	var state := MatchState.new()
	state.tile_grid = TileGrid.new(26, 16)
	state.next_entity_id = 1
	for pid in [0, 1]:
		var p := PlayerState.new()
		p.player_id = pid
		p.pop_cap = 50
		state.players.append(p)
	var specs := [
		{"id": 1, "def_id": "base", "owner": 0, "origin": Vector2i(0, 0)},
		{"id": 2, "def_id": "marine", "owner": 0, "origin": Vector2i(7, 6)},
		{"id": 3, "def_id": "marine", "owner": 0, "origin": Vector2i(7, 8)},
		{"id": 4, "def_id": "marine", "owner": 0, "origin": Vector2i(7, 10)},
		{"id": 5, "def_id": "base", "owner": 1, "origin": Vector2i(22, 12)},
		{"id": 6, "def_id": "tank", "owner": 1, "origin": Vector2i(13, 7)},
		{"id": 7, "def_id": "tank", "owner": 1, "origin": Vector2i(13, 10)},
		{"id": 8, "def_id": "worker", "owner": 0, "origin": Vector2i(2, 5)},
		{"id": 9, "def_id": "worker", "owner": 1, "origin": Vector2i(21, 10)},
	]
	for spec in specs:
		var def: EntityDef = registry.get_by_id(spec["def_id"])
		var e := Entity.new()
		e.id = spec["id"]
		e.def_id = spec["def_id"]
		e.current_def_id = e.def_id
		e.owner_player_id = spec["owner"]
		e.origin = spec["origin"]
		e.current_hp = def.health.max_hp if def.health != null else 1
		e.current_layer = "ground"
		state.entities.append(e)
		state.next_entity_id = maxi(state.next_entity_id, e.id + 1)
		state.tile_grid.place(e.id, Rect2i(e.origin, def.footprint))
	return state


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _capture(file_name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + "/" + file_name)
	print("[capture] %s -> %s" % [file_name, error_string(err)])
