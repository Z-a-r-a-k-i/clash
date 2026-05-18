@tool
extends Node

const _REGISTRY_PATH: String = "res://data/entity_registry.tres"
const _TUNABLES_PATH: String = "res://data/tunables.tres"
const _MVP_MAP_PATH: String = "res://data/scenarios/mvp_map.tres"
const _MINERALS_FOR_FIRST_BARRACKS: int = 150


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	_run_all()


func _run_all() -> int:
	var passed: int = 0
	var failed: int = 0
	var fail_names: Array[String] = []
	for test_pair: Array in _all_tests():
		var test_name: String = test_pair[0]
		var fn: Callable = test_pair[1]
		var ok: bool = fn.call()
		if ok:
			passed += 1
		else:
			failed += 1
			fail_names.append(test_name)
	print("[test_m0_playtest_smoke] %d passed, %d failed" % [passed, failed])
	for test_name: String in fail_names:
		push_error("  failed: %s" % test_name)
	return failed


func _all_tests() -> Array:
	return [["m0_playtest_smoke_exercises_mvp_loop", _test_m0_playtest_smoke]]


func _test_m0_playtest_smoke() -> bool:
	var loaded: LoadedScenario = _load_mvp_map()
	if loaded == null or loaded.state == null or loaded.registry == null:
		push_error("[m0_playtest_smoke] failed to load MVP map, registry, or tunables")
		return false
	var state: MatchState = loaded.state
	var registry: EntityRegistry = loaded.registry
	var tunables: Tunables = load(_TUNABLES_PATH) as Tunables
	if tunables == null:
		push_error("[m0_playtest_smoke] failed to load tunables")
		return false
	if not _assert_baseline_map(state):
		return false
	if not _assert_opening_fog(state, registry):
		return false
	state = _drive_p0_gather_until(state, registry, tunables, _MINERALS_FOR_FIRST_BARRACKS)
	if state == null:
		push_error("[m0_playtest_smoke] opening gather did not reach first barracks minerals")
		return false
	var builder: Entity = _first_entity_by_def_owner(state, "worker", 0)
	if builder == null:
		push_error("[m0_playtest_smoke] expected a P0 worker builder")
		return false
	var barracks_origin: Vector2i = _find_clear_build_origin(
		state, registry, "barracks", builder.origin, 12
	)
	if barracks_origin == Vector2i(-1, -1):
		push_error("[m0_playtest_smoke] could not find a clear barracks build tile")
		return false
	var build_result: ResolveResult = _resolve(
		state, registry, tunables, [_build_order(builder.id, "barracks", barracks_origin)], []
	)
	if not _has_event(build_result.events, ResolverEvent.Type.BUILD_STARTED):
		push_error("[m0_playtest_smoke] expected BUILD_STARTED for first barracks")
		return false
	var barracks_id: int = _event_target_with_def(
		build_result.events, ResolverEvent.Type.BUILD_STARTED, "barracks"
	)
	if barracks_id < 0:
		push_error("[m0_playtest_smoke] BUILD_STARTED did not identify the barracks")
		return false
	if _has_event(build_result.events, ResolverEvent.Type.BUILD_COMPLETED):
		state = build_result.new_state
	else:
		state = _resolve_until_event(
			build_result.new_state, registry, tunables, ResolverEvent.Type.BUILD_COMPLETED, 30
		)
	if state == null:
		push_error("[m0_playtest_smoke] barracks did not complete within smoke budget")
		return false
	state = _resolve_until_minerals_at_least(state, registry, tunables, 50, 120)
	if state == null:
		push_error("[m0_playtest_smoke] minerals did not recover enough to train a marine")
		return false
	var train_result: ResolveResult = _resolve(
		state, registry, tunables, [_train_order(barracks_id, "marine")], []
	)
	if not _has_event(train_result.events, ResolverEvent.Type.TRAIN_STARTED):
		push_error("[m0_playtest_smoke] expected TRAIN_STARTED for marine")
		return false
	var train_complete_result: ResolveResult = train_result
	if (
		_event_target_with_def(train_result.events, ResolverEvent.Type.TRAIN_COMPLETED, "marine")
		< 0
	):
		train_complete_result = _resolve_until_event_with_def(
			train_result.new_state,
			registry,
			tunables,
			ResolverEvent.Type.TRAIN_COMPLETED,
			"marine",
			12
		)
	if train_complete_result == null:
		push_error("[m0_playtest_smoke] marine did not complete within smoke budget")
		return false
	state = train_complete_result.new_state
	var marine_id: int = _event_target_with_def(
		train_complete_result.events, ResolverEvent.Type.TRAIN_COMPLETED, "marine"
	)
	if marine_id < 0:
		push_error("[m0_playtest_smoke] TRAIN_COMPLETED did not identify the marine")
		return false
	var marine: Entity = state.get_entity_by_id(marine_id)
	if (
		marine == null
		or marine.def_id != "marine"
		or marine.owner_player_id != 0
		or marine.current_hp <= 0
	):
		push_error("[m0_playtest_smoke] expected the newly trained P0 marine")
		return false
	var enemy_origin: Vector2i = _find_clear_build_origin(
		state, registry, "marine", marine.origin + Vector2i(2, 0), 5
	)
	if enemy_origin == Vector2i(-1, -1):
		push_error("[m0_playtest_smoke] could not place nearby enemy marine")
		return false
	var enemy_id: int = _spawn_entity(state, registry, "marine", 1, enemy_origin)
	if enemy_id < 0:
		push_error("[m0_playtest_smoke] failed to spawn nearby enemy marine")
		return false
	var combat_result: ResolveResult = _resolve(
		state, registry, tunables, [_attack_order(marine.id, enemy_id)], []
	)
	state = combat_result.new_state
	if not _has_event(combat_result.events, ResolverEvent.Type.ENTITY_DAMAGED):
		state = _resolve_until_event(
			state, registry, tunables, ResolverEvent.Type.ENTITY_DAMAGED, 6
		)
		if state == null:
			push_error("[m0_playtest_smoke] expected nearby marine attack to deal damage")
			return false
	var surrender: SubmitTurn = SubmitTurn.new()
	surrender.surrender = true
	var end_result: ResolveResult = Resolver.resolve(
		state, SubmitTurn.new(), surrender, registry, tunables
	)
	if end_result.new_state == null or not end_result.new_state.match_over:
		push_error("[m0_playtest_smoke] expected P1 surrender to end the match")
		return false
	if end_result.new_state.winner_player_id != 0:
		push_error("[m0_playtest_smoke] expected P0 winner after P1 surrender")
		return false
	if not _has_event(end_result.events, ResolverEvent.Type.MATCH_ENDED):
		push_error("[m0_playtest_smoke] expected MATCH_ENDED event after P1 surrender")
		return false
	return true


func _load_mvp_map() -> LoadedScenario:
	var scenario: ScenarioDef = load(_MVP_MAP_PATH) as ScenarioDef
	var registry: EntityRegistry = load(_REGISTRY_PATH) as EntityRegistry
	var tunables: Tunables = load(_TUNABLES_PATH) as Tunables
	if scenario == null or registry == null or tunables == null:
		return null
	return ScenarioLoader.load(scenario, registry, tunables)


func _assert_baseline_map(state: MatchState) -> bool:
	if state.tile_grid == null or state.tile_grid.width != 50 or state.tile_grid.height != 50:
		push_error("[m0_playtest_smoke] expected 50x50 MVP map")
		return false
	if state.players.size() != 2:
		push_error("[m0_playtest_smoke] expected two players")
		return false
	if _entity_count_by_def_owner(state, "base", 0) != 1:
		push_error("[m0_playtest_smoke] expected one P0 base")
		return false
	if _entity_count_by_def_owner(state, "base", 1) != 1:
		push_error("[m0_playtest_smoke] expected one P1 base")
		return false
	if _entity_count_by_def_owner(state, "worker", 0) != 2:
		push_error("[m0_playtest_smoke] expected two P0 workers")
		return false
	if _entity_count_by_def_owner(state, "worker", 1) != 2:
		push_error("[m0_playtest_smoke] expected two P1 workers")
		return false
	var player_0: PlayerState = state.get_player(0)
	var player_1: PlayerState = state.get_player(1)
	if player_0 == null or player_1 == null:
		push_error("[m0_playtest_smoke] expected both player states")
		return false
	if player_0.minerals != 50 or player_1.minerals != 50:
		push_error(
			(
				"[m0_playtest_smoke] expected starting minerals 50/50, got %d/%d"
				% [player_0.minerals, player_1.minerals]
			)
		)
		return false
	return true


func _assert_opening_fog(state: MatchState, registry: EntityRegistry) -> bool:
	var enemy_base: Entity = _first_entity_by_def_owner(state, "base", 1)
	var own_worker: Entity = _first_entity_by_def_owner(state, "worker", 0)
	if enemy_base == null or own_worker == null:
		push_error("[m0_playtest_smoke] missing entities for fog assertion")
		return false
	var visibility: VisionSystem.Visibility = VisionSystem.compute_player_visibility(
		state, registry, 0
	)
	if not VisionSystem.is_entity_visible_to_player(own_worker, state, registry, 0, visibility):
		push_error("[m0_playtest_smoke] P0 worker should be visible to P0")
		return false
	if VisionSystem.is_entity_visible_to_player(enemy_base, state, registry, 0, visibility):
		push_error("[m0_playtest_smoke] P1 base should start outside P0 vision")
		return false
	return true


func _drive_p0_gather_until(
	state: MatchState, registry: EntityRegistry, tunables: Tunables, mineral_target: int
) -> MatchState:
	var workers: Array[Entity] = _entities_by_def_owner(state, "worker", 0)
	var orders: Array[EntityOrder] = []
	for worker: Entity in workers:
		var source: Entity = _nearest_resource_source(state, registry, worker, "minerals")
		if source == null:
			push_error("[m0_playtest_smoke] worker %d had no mineral source" % worker.id)
			return null
		orders.append(_gather_order(worker.id, source.id))
	var result: ResolveResult = _resolve(state, registry, tunables, orders, [])
	if _has_event(result.events, ResolverEvent.Type.ORDER_REJECTED):
		push_error("[m0_playtest_smoke] opening gather orders were rejected")
		return null
	var next_state: MatchState = result.new_state
	return _resolve_until_minerals_at_least(next_state, registry, tunables, mineral_target, 90)


func _resolve_until_minerals_at_least(
	state: MatchState, registry: EntityRegistry, tunables: Tunables, amount: int, max_turns: int
) -> MatchState:
	var current: MatchState = state
	var player: PlayerState = current.get_player(0)
	if player != null and player.minerals >= amount:
		return current
	for _i: int in max_turns:
		current = _resolve(current, registry, tunables, [], []).new_state
		player = current.get_player(0)
		if player != null and player.minerals >= amount:
			return current
	var final_player: PlayerState = current.get_player(0)
	var worker_statuses: Array[String] = []
	for worker: Entity in _entities_by_def_owner(current, "worker", 0):
		var phase: int = -1
		var carrying: int = -1
		var source_id: int = -1
		if worker.gather_state != null:
			phase = worker.gather_state.phase
			carrying = worker.gather_state.carrying_amount
			source_id = worker.gather_state.assigned_source_entity_id
		worker_statuses.append(
			(
				"#%d phase=%d carrying=%d source=%d origin=%s"
				% [worker.id, phase, carrying, source_id, str(worker.origin)]
			)
		)
	push_error(
		(
			"[m0_playtest_smoke] expected at least %d minerals after %d turns, got %d; workers: %s"
			% [
				amount,
				max_turns,
				final_player.minerals if final_player != null else -1,
				"; ".join(worker_statuses),
			]
		)
	)
	return null


func _resolve_until_event(
	state: MatchState,
	registry: EntityRegistry,
	tunables: Tunables,
	event_type: ResolverEvent.Type,
	max_turns: int
) -> MatchState:
	var current: MatchState = state
	for _i: int in max_turns:
		var result: ResolveResult = _resolve(current, registry, tunables, [], [])
		current = result.new_state
		if _has_event(result.events, event_type):
			return current
	return null


func _resolve_until_event_with_def(
	state: MatchState,
	registry: EntityRegistry,
	tunables: Tunables,
	event_type: ResolverEvent.Type,
	def_id: String,
	max_turns: int
) -> ResolveResult:
	var current: MatchState = state
	for _i: int in max_turns:
		var result: ResolveResult = _resolve(current, registry, tunables, [], [])
		current = result.new_state
		if _event_target_with_def(result.events, event_type, def_id) >= 0:
			return result
	return null


func _resolve(
	state: MatchState,
	registry: EntityRegistry,
	tunables: Tunables,
	orders_a: Array[EntityOrder],
	orders_b: Array[EntityOrder]
) -> ResolveResult:
	return Resolver.resolve(state, _submit(orders_a), _submit(orders_b), registry, tunables)


func _submit(orders: Array[EntityOrder] = []) -> SubmitTurn:
	var submit: SubmitTurn = SubmitTurn.new()
	submit.orders = orders
	return submit


func _gather_order(entity_id: int, target_entity_id: int) -> EntityOrder:
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.GATHER
	order.entity_id = entity_id
	order.target_entity_id = target_entity_id
	return order


func _build_order(entity_id: int, def_id: String, target_tile: Vector2i) -> EntityOrder:
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.BUILD
	order.entity_id = entity_id
	order.def_id = def_id
	order.target_tile = target_tile
	return order


func _train_order(entity_id: int, def_id: String) -> EntityOrder:
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.TRAIN
	order.entity_id = entity_id
	order.def_id = def_id
	return order


func _attack_order(entity_id: int, target_entity_id: int) -> EntityOrder:
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.ATTACK
	order.entity_id = entity_id
	order.target_priority_chain = [target_entity_id]
	return order


func _entities_by_def_owner(state: MatchState, def_id: String, owner: int) -> Array[Entity]:
	var out: Array[Entity] = []
	for entity: Entity in state.entities_sorted_by_id():
		if entity.def_id == def_id and entity.owner_player_id == owner and entity.current_hp > 0:
			out.append(entity)
	return out


func _first_entity_by_def_owner(state: MatchState, def_id: String, owner: int) -> Entity:
	for entity: Entity in state.entities_sorted_by_id():
		if entity.def_id == def_id and entity.owner_player_id == owner and entity.current_hp > 0:
			return entity
	return null


func _entity_count_by_def_owner(state: MatchState, def_id: String, owner: int) -> int:
	var count: int = 0
	for entity: Entity in state.entities:
		if entity != null and entity.def_id == def_id and entity.owner_player_id == owner:
			if owner < 0 or entity.current_hp > 0:
				count += 1
	return count


func _nearest_resource_source(
	state: MatchState, registry: EntityRegistry, worker: Entity, resource_type: String
) -> Entity:
	var worker_rect: Rect2i = state.tile_grid.entity_rect(worker.id)
	var best: Entity = null
	var best_distance: int = -1
	for entity: Entity in state.entities_sorted_by_id():
		var def: EntityDef = registry.get_by_id(entity.current_def_id)
		if def == null or def.resource_source == null:
			continue
		if def.resource_source.resource_type != resource_type:
			continue
		if entity.current_resource_amount <= 0:
			continue
		var rect: Rect2i = state.tile_grid.entity_rect(entity.id)
		if rect.size == Vector2i.ZERO:
			continue
		var distance: int = TileGrid.distance_between_rects(worker_rect, rect)
		if best == null or distance < best_distance:
			best = entity
			best_distance = distance
	return best


func _find_clear_build_origin(
	state: MatchState, registry: EntityRegistry, def_id: String, center: Vector2i, radius: int
) -> Vector2i:
	var def: EntityDef = registry.get_by_id(def_id)
	if def == null:
		push_error("[m0_playtest_smoke] registry missing entity def '%s'" % def_id)
		return Vector2i(-1, -1)
	var footprint: Vector2i = Vector2i.ONE
	if def.footprint != Vector2i.ZERO:
		footprint = Vector2i(max(def.footprint.x, 1), max(def.footprint.y, 1))
	for distance: int in range(0, radius + 1):
		for dx: int in range(-distance, distance + 1):
			for dy: int in range(-distance, distance + 1):
				if max(abs(dx), abs(dy)) != distance:
					continue
				var origin: Vector2i = center + Vector2i(dx, dy)
				if state.tile_grid.is_rect_clear(Rect2i(origin, footprint)):
					return origin
	return Vector2i(-1, -1)


func _spawn_entity(
	state: MatchState, registry: EntityRegistry, def_id: String, owner: int, origin: Vector2i
) -> int:
	var def: EntityDef = registry.get_by_id(def_id)
	if def == null:
		push_error("[m0_playtest_smoke] registry missing entity def '%s'" % def_id)
		return -1
	var entity: Entity = Entity.new()
	entity.id = state.allocate_entity_id()
	entity.def_id = def_id
	entity.current_def_id = def_id
	entity.owner_player_id = owner
	entity.origin = origin
	entity.current_layer = "ground"
	if def != null:
		if def.movement != null and def.movement.default_layer != "":
			entity.current_layer = def.movement.default_layer
		if def.health != null:
			entity.current_hp = def.health.max_hp
		if def.production != null:
			entity.production_state = ProductionState.new()
		if def.gather != null:
			entity.gather_state = GatherState.new()
		if def.resource_source != null:
			entity.current_resource_amount = def.resource_source.capacity
	var footprint: Vector2i = Vector2i.ONE
	if def != null and def.footprint != Vector2i.ZERO:
		footprint = Vector2i(max(def.footprint.x, 1), max(def.footprint.y, 1))
	state.entities.append(entity)
	if not state.tile_grid.place(entity.id, Rect2i(origin, footprint)):
		state.entities.erase(entity)
		return -1
	return entity.id


func _has_event(events: Array[ResolverEvent], event_type: ResolverEvent.Type) -> bool:
	for event: ResolverEvent in events:
		if event != null and event.type == event_type:
			return true
	return false


func _event_target_with_def(
	events: Array[ResolverEvent], event_type: ResolverEvent.Type, def_id: String
) -> int:
	for event: ResolverEvent in events:
		if event != null and event.type == event_type and event.def_id == def_id:
			return event.target_id
	return -1
