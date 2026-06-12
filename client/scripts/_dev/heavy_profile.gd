extends SceneTree

# Heavy mid-game reproduction of the playtest slowdown: arena map,
# ~40 gathering workers per side, two armies focus-firing. Run with
# RESOLVER_PROFILE=1 to get per-phase breakdowns.


func _init() -> void:
	var registry: EntityRegistry = load("res://data/entity_registry.tres")
	var tunables: Tunables = load("res://data/tunables.tres")
	var scenario: ScenarioDef = load("res://data/scenarios/arena_1v1.tres")
	var loaded := ScenarioLoader.load(scenario, registry, tunables)
	var state: MatchState = loaded.state

	# Bulk up: workers around each main + armies meeting mid-map.
	var p0_workers := _spawn_many(state, registry, "worker", 0, Vector2i(6, 14), 36)
	var p1_workers := _spawn_many(state, registry, "worker", 1, Vector2i(66, 42), 36)
	var p0_marines := _spawn_many(state, registry, "marine", 0, Vector2i(30, 28), 8)
	var p1_marines := _spawn_many(state, registry, "marine", 1, Vector2i(40, 30), 8)
	var p0_tanks := _spawn_many(state, registry, "tank", 0, Vector2i(28, 33), 3)
	var p1_tanks := _spawn_many(state, registry, "tank", 1, Vector2i(44, 27), 3)
	print(
		(
			"entities=%d workers=%d/%d marines=%d/%d"
			% [
				state.entities.size(),
				p0_workers.size(),
				p1_workers.size(),
				p0_marines.size(),
				p1_marines.size(),
			]
		)
	)

	var minerals_p0: Array[int] = _resource_ids_near(state, registry, Vector2i(8, 8))
	var minerals_p1: Array[int] = _resource_ids_near(state, registry, Vector2i(70, 50))

	for turn in range(8):
		var submit_a := SubmitTurn.new()
		var submit_b := SubmitTurn.new()
		# Workers gather: ordered once on turn 0 (standing FSM carries on),
		# like real play.
		if turn == 0:
			_queue_gather(submit_a, p0_workers, minerals_p0)
			_queue_gather(submit_b, p1_workers, minerals_p1)
		# Everyone focus-fires one enemy + armies push into each other:
		# the "multiple units target a unit" hang from the playtest.
		_queue_focus(submit_a, p0_marines + p0_tanks, p1_marines[0])
		_queue_focus(submit_b, p1_marines + p1_tanks, p0_marines[0])
		var start := Time.get_ticks_usec()
		var result := Resolver.resolve(state, submit_a, submit_b, registry, tunables)
		var ms := float(Time.get_ticks_usec() - start) / 1000.0
		state = result.new_state
		print(">>> turn %d: %.0f ms, events=%d" % [turn, ms, result.events.size()])
	quit(0)


func _spawn_many(
	state: MatchState,
	registry: EntityRegistry,
	def_id: String,
	owner: int,
	around: Vector2i,
	count: int
) -> Array[int]:
	var def: EntityDef = registry.get_by_id(def_id)
	var out: Array[int] = []
	var placed := 0
	var radius := 1
	while placed < count and radius < 20:
		for y in range(around.y - radius, around.y + radius + 1):
			for x in range(around.x - radius, around.x + radius + 1):
				if placed >= count:
					break
				var tile := Vector2i(x, y)
				if not state.tile_grid.is_in_bounds(tile):
					continue
				if not state.tile_grid.is_in_bounds(tile + def.footprint - Vector2i.ONE):
					continue
				var e := Entity.new()
				e.id = state.allocate_entity_id()
				e.def_id = def_id
				e.current_def_id = def_id
				e.owner_player_id = owner
				e.origin = tile
				e.current_hp = def.health.max_hp
				e.current_layer = "ground"
				if def_id == "worker":
					e.gather_state = GatherState.new()
				if not state.tile_grid.place(e.id, Rect2i(tile, def.footprint)):
					continue
				state.entities.append(e)
				out.append(e.id)
				placed += 1
		radius += 1
	return out


func _resource_ids_near(
	state: MatchState, registry: EntityRegistry, around: Vector2i
) -> Array[int]:
	var out: Array[int] = []
	for entity in state.entities_sorted_by_id():
		var def: EntityDef = registry.get_by_id(entity.def_id)
		if def == null or def.resource_source == null:
			continue
		if def.resource_source.resource_type != "minerals":
			continue
		if Vector2(entity.origin).distance_to(Vector2(around)) < 25.0:
			out.append(entity.id)
	return out


func _queue_gather(submit: SubmitTurn, worker_ids: Array[int], mineral_ids: Array[int]) -> void:
	if mineral_ids.is_empty():
		return
	for i in range(worker_ids.size()):
		var order := EntityOrder.new()
		order.type = EntityOrder.Type.GATHER
		order.entity_id = worker_ids[i]
		order.target_entity_id = mineral_ids[i % mineral_ids.size()]
		submit.orders.append(order)


func _queue_focus(submit: SubmitTurn, attacker_ids: Array[int], target_id: int) -> void:
	for attacker_id in attacker_ids:
		var order := EntityOrder.new()
		order.type = EntityOrder.Type.TARGET
		order.entity_id = attacker_id
		order.target_entity_id = target_id
		submit.orders.append(order)
