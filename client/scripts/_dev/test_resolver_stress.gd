@tool
extends Node

const _GRID_WIDTH := 64
const _GRID_HEIGHT := 40
const _UNIT_DEF_ID := "stress_unit"
const _BASE_DEF_ID := "stress_base"
const _BLOCKER_DEF_ID := "stress_blocker"
const _ABILITY_ID := "stress_drill"
const _UNIT_ROWS := 10
const _UNITS_PER_PLAYER := _UNIT_ROWS * 2
const _BLOCKER_COUNT := 16
const _ABILITY_ORDERS_PER_UNIT := 4
const _MAX_RESOLVE_USEC_DEFAULT := 250000
const _BUDGET_ENV_VAR := "RESOLVER_STRESS_BUDGET_USEC"


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	var ok := _test_large_ordered_resolve_stays_under_budget()
	if ok:
		print("[test_resolver_stress] 1 passed, 0 failed")
	else:
		push_error("[test_resolver_stress] 0 passed, 1 failed")


func _all_tests() -> Array:
	return [
		[
			"large_ordered_resolve_stays_under_budget",
			_test_large_ordered_resolve_stays_under_budget
		],
	]


func _test_large_ordered_resolve_stays_under_budget() -> bool:
	var warmup_fixture: Dictionary = _build_stress_fixture()
	var warmup_state: MatchState = warmup_fixture["state"]
	var warmup_submit_a: SubmitTurn = warmup_fixture["submit_a"]
	var warmup_submit_b: SubmitTurn = warmup_fixture["submit_b"]
	var warmup_registry: EntityRegistry = warmup_fixture["registry"]
	var warmup_result: ResolveResult = Resolver.resolve(
		warmup_state, warmup_submit_a, warmup_submit_b, warmup_registry, null
	)
	if warmup_result == null or warmup_result.new_state == null:
		push_error("[test_resolver_stress] warmup resolve failed")
		return false

	var fixture: Dictionary = _build_stress_fixture()
	var state: MatchState = fixture["state"]
	var submit_a: SubmitTurn = fixture["submit_a"]
	var submit_b: SubmitTurn = fixture["submit_b"]
	var registry: EntityRegistry = fixture["registry"]
	var order_count: int = fixture["order_count"]
	var unit_count: int = fixture["unit_count"]
	var blocker_count: int = fixture["blocker_count"]
	var max_resolve_usec := _resolve_budget_usec()

	var start_usec := Time.get_ticks_usec()
	var result: ResolveResult = Resolver.resolve(state, submit_a, submit_b, registry, null)
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	if result == null or result.new_state == null:
		push_error("[test_resolver_stress] measured resolve returned null")
		return false

	var damage_count := _count_events(result.events, ResolverEvent.Type.ENTITY_DAMAGED)
	var move_count := _count_events(result.events, ResolverEvent.Type.ENTITY_MOVED)
	var ability_count := _count_events(result.events, ResolverEvent.Type.ABILITY_USED)
	print(
		(
			(
				"[test_resolver_stress] units=%d blockers=%d orders=%d events=%d "
				+ "damage=%d moves=%d abilities=%d elapsed=%.3fms"
			)
			% [
				unit_count,
				blocker_count,
				order_count,
				result.events.size(),
				damage_count,
				move_count,
				ability_count,
				float(elapsed_usec) / 1000.0,
			]
		)
	)
	if unit_count != _UNITS_PER_PLAYER * 2:
		push_error(
			"[test_resolver_stress] expected %d units, got %d" % [_UNITS_PER_PLAYER * 2, unit_count]
		)
		return false
	if blocker_count != _BLOCKER_COUNT:
		push_error(
			"[test_resolver_stress] expected %d blockers, got %d" % [_BLOCKER_COUNT, blocker_count]
		)
		return false
	if order_count < 200:
		push_error("[test_resolver_stress] expected at least 200 orders, got %d" % order_count)
		return false
	if ability_count < unit_count * _ABILITY_ORDERS_PER_UNIT:
		push_error("[test_resolver_stress] expected each ability order to resolve")
		return false
	if damage_count < unit_count / 2:
		push_error("[test_resolver_stress] expected substantial combat events")
		return false
	if move_count < unit_count / 2:
		push_error("[test_resolver_stress] expected substantial movement events")
		return false
	if result.new_state.match_over:
		push_error("[test_resolver_stress] stress resolve should not end the match")
		return false
	if elapsed_usec > max_resolve_usec:
		push_error(
			(
				"[test_resolver_stress] resolve took %.3fms; budget is %.3fms"
				% [float(elapsed_usec) / 1000.0, float(max_resolve_usec) / 1000.0]
			)
		)
		return false
	return true


func _build_stress_fixture() -> Dictionary:
	var registry := _stress_registry()
	var state := MatchState.new()
	state.players = [_player(0), _player(1)]
	state.tile_grid = TileGrid.new(_GRID_WIDTH, _GRID_HEIGHT)

	_place_entity(state, _BASE_DEF_ID, 0, Vector2i(2, 2), 1500, "structure", Vector2i(4, 4))
	_place_entity(
		state,
		_BASE_DEF_ID,
		1,
		Vector2i(_GRID_WIDTH - 6, _GRID_HEIGHT - 6),
		1500,
		"structure",
		Vector2i(4, 4)
	)
	var blocker_count := _place_blockers(state)

	var p0_units: Array[Entity] = []
	var p0_front_ids: Array[int] = []
	var p0_back_ids: Array[int] = []
	var p1_units: Array[Entity] = []
	var p1_front_ids: Array[int] = []
	var p1_back_ids: Array[int] = []
	for row_index in range(_UNIT_ROWS):
		var y := 5 + row_index * 3
		var p0_back := _place_entity(
			state, _UNIT_DEF_ID, 0, Vector2i(20, y), 1000, "ground", Vector2i.ONE
		)
		var p0_front := _place_entity(
			state, _UNIT_DEF_ID, 0, Vector2i(24, y), 1000, "ground", Vector2i.ONE
		)
		var p1_front := _place_entity(
			state, _UNIT_DEF_ID, 1, Vector2i(40, y), 1000, "ground", Vector2i.ONE
		)
		var p1_back := _place_entity(
			state, _UNIT_DEF_ID, 1, Vector2i(44, y), 1000, "ground", Vector2i.ONE
		)
		p0_units.append(p0_back)
		p0_units.append(p0_front)
		p0_back_ids.append(p0_back.id)
		p0_front_ids.append(p0_front.id)
		p1_units.append(p1_front)
		p1_units.append(p1_back)
		p1_front_ids.append(p1_front.id)
		p1_back_ids.append(p1_back.id)

	var orders_a := _orders_for_units(p0_units, p1_back_ids, p1_front_ids, 50)
	var orders_b := _orders_for_units(p1_units, p0_back_ids, p0_front_ids, 14)
	return {
		"state": state,
		"registry": registry,
		"submit_a": _submit(orders_a),
		"submit_b": _submit(orders_b),
		"unit_count": p0_units.size() + p1_units.size(),
		"blocker_count": blocker_count,
		"order_count": orders_a.size() + orders_b.size(),
	}


func _place_blockers(state: MatchState) -> int:
	var origins: Array[Vector2i] = [
		Vector2i(29, 4),
		Vector2i(34, 4),
		Vector2i(31, 7),
		Vector2i(36, 7),
		Vector2i(29, 10),
		Vector2i(34, 10),
		Vector2i(31, 13),
		Vector2i(36, 13),
		Vector2i(29, 16),
		Vector2i(34, 16),
		Vector2i(31, 19),
		Vector2i(36, 19),
		Vector2i(29, 22),
		Vector2i(34, 22),
		Vector2i(31, 25),
		Vector2i(36, 25),
	]
	var placed := 0
	for origin in origins:
		var blocker := _place_entity(
			state, _BLOCKER_DEF_ID, -1, origin, 5000, "ground", Vector2i(2, 2)
		)
		if blocker != null:
			placed += 1
	return placed


func _orders_for_units(
	units: Array[Entity], enemy_back_ids: Array[int], enemy_front_ids: Array[int], target_x: int
) -> Array[EntityOrder]:
	var orders: Array[EntityOrder] = []
	for index in range(units.size()):
		var unit: Entity = units[index]
		var attack := EntityOrder.new()
		attack.type = EntityOrder.Type.TARGET
		attack.entity_id = unit.id
		attack.target_priority_chain = _rotating_chain(enemy_back_ids, index, 5)
		attack.target_priority_chain.append_array(_rotating_chain(enemy_front_ids, index, 5))
		orders.append(attack)

		for _i in range(_ABILITY_ORDERS_PER_UNIT):
			var ability := EntityOrder.new()
			ability.type = EntityOrder.Type.USE_ABILITY
			ability.entity_id = unit.id
			ability.def_id = _ABILITY_ID
			orders.append(ability)

		var move := EntityOrder.new()
		move.type = EntityOrder.Type.MOVE
		move.entity_id = unit.id
		move.target_tile = Vector2i(target_x, _target_y(unit.origin.y, index))
		orders.append(move)
	return orders


func _target_y(origin_y: int, index: int) -> int:
	var offset := 2 if index % 2 == 0 else -2
	return mini(_GRID_HEIGHT - 2, maxi(1, origin_y + offset))


func _rotating_chain(ids: Array[int], start_index: int, count: int) -> Array[int]:
	var chain: Array[int] = []
	if ids.is_empty():
		return chain
	for i in range(count):
		chain.append(ids[(start_index + i) % ids.size()])
	return chain


func _place_entity(
	state: MatchState,
	def_id: String,
	owner: int,
	origin: Vector2i,
	hp: int,
	layer: String,
	footprint: Vector2i
) -> Entity:
	var entity := Entity.new()
	entity.id = state.allocate_entity_id()
	entity.def_id = def_id
	entity.current_def_id = def_id
	entity.owner_player_id = owner
	entity.origin = origin
	entity.current_hp = hp
	entity.current_layer = layer
	state.entities.append(entity)
	if not state.tile_grid.place(entity.id, Rect2i(origin, footprint)):
		push_error("[test_resolver_stress] failed to place %s at %s" % [def_id, str(origin)])
		state.entities.erase(entity)
		return null
	return entity


func _stress_registry() -> EntityRegistry:
	var unit := EntityDef.new()
	unit.id = _UNIT_DEF_ID
	unit.footprint = Vector2i.ONE
	unit.tags = ["light", "ground"]
	var unit_health := HealthDef.new()
	unit_health.max_hp = 1000
	unit.health = unit_health
	var unit_move := MovementDef.new()
	unit_move.speed_tiles_per_turn = 8
	unit_move.default_layer = "ground"
	unit.movement = unit_move
	var unit_combat := CombatDef.new()
	unit_combat.damage = 4
	unit_combat.attack_range = 20
	unit_combat.target_layers = ["ground"]
	unit.combat = unit_combat
	var unit_vision := VisionDef.new()
	unit_vision.sight_radius = 20
	unit.vision = unit_vision
	var abilities := AbilitiesDef.new()
	abilities.abilities = [_stress_ability()]
	unit.abilities = abilities

	var base := EntityDef.new()
	base.id = _BASE_DEF_ID
	base.footprint = Vector2i(4, 4)
	base.tags = ["building", "structure"]
	var base_health := HealthDef.new()
	base_health.max_hp = 1500
	base.health = base_health

	var blocker := EntityDef.new()
	blocker.id = _BLOCKER_DEF_ID
	blocker.footprint = Vector2i(2, 2)
	blocker.tags = ["building", "blocker"]
	var blocker_health := HealthDef.new()
	blocker_health.max_hp = 5000
	blocker.health = blocker_health

	var registry := EntityRegistry.new()
	registry.entities = [unit, base, blocker]
	return registry


func _stress_ability() -> AbilityDef:
	var ability := AbilityDef.new()
	ability.id = _ABILITY_ID
	ability.display_name = "Stress Drill"
	ability.target_type = "self"
	var effect := StatBuffEffect.new()
	effect.duration_turns = 2
	effect.damage_mult = 1.0
	effect.speed_mult = 1.0
	ability.effect = effect
	return ability


func _player(id: int) -> PlayerState:
	var player := PlayerState.new()
	player.player_id = id
	player.pop_cap = 100
	return player


func _submit(orders: Array[EntityOrder]) -> SubmitTurn:
	var submit := SubmitTurn.new()
	submit.orders = orders
	return submit


func _count_events(events: Array[ResolverEvent], event_type: ResolverEvent.Type) -> int:
	var count := 0
	for event in events:
		if event != null and event.type == event_type:
			count += 1
	return count


func _resolve_budget_usec() -> int:
	var override := OS.get_environment(_BUDGET_ENV_VAR)
	if override.is_valid_int():
		var value := override.to_int()
		if value > 0:
			return value
	return _MAX_RESOLVE_USEC_DEFAULT
