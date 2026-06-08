class_name ActionPreviewBuilder
extends RefCounted

const PATHFINDING_SCRIPT := preload("res://scripts/resolver/pathfinding_system.gd")

var _state: MatchState = null
var _registry: EntityRegistry = null
var _input: DevTurnInput = null
var _player_id: int = 0
var _renderer: MatchRenderer = null
var _visibility_by_player: Dictionary[int, VisionSystem.Visibility] = {}


func build(
	state: MatchState,
	registry: EntityRegistry,
	input: DevTurnInput,
	player_id: int,
	selected_entity_id: int,
	include_all_friendly: bool = false,
	renderer: MatchRenderer = null
) -> Array[Dictionary]:
	_state = state
	_registry = registry
	_input = input
	_player_id = player_id
	_renderer = renderer
	_visibility_by_player.clear()
	var previews: Array[Dictionary] = []
	previews.append_array(_previews_for_entity(selected_entity_id))
	if include_all_friendly:
		if _state == null:
			return previews
		var seen: Dictionary[int, bool] = {}
		if selected_entity_id >= 0:
			seen[selected_entity_id] = true
		for entity in _state.entities_sorted_by_id():
			if entity == null or entity.owner_player_id != _player_id or seen.has(entity.id):
				continue
			var entity_previews: Array[Dictionary] = _previews_for_entity(entity.id)
			if entity_previews.is_empty():
				continue
			previews.append_array(entity_previews)
			seen[entity.id] = true
	return previews


func _previews_for_entity(entity_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if entity_id < 0 or _state == null or _input == null:
		return out
	var sequence_index: int = 1
	var has_planned_tile: bool = false
	var planned_tile: Vector2i = Vector2i.ZERO
	for queued in _queued_orders_for_entity(entity_id):
		var queued_preview: Dictionary = _preview_for_order(queued, planned_tile, has_planned_tile)
		if not queued_preview.is_empty():
			queued_preview["sequence_index"] = sequence_index
			queued_preview["future"] = false
			out.append(queued_preview)
			if _preview_keeps_planned_tile(queued_preview, has_planned_tile):
				planned_tile = _preview_planned_tile_value(queued_preview, planned_tile)
				has_planned_tile = true
			sequence_index += 1
	for future in _future_orders_for_entity(entity_id):
		var future_preview: Dictionary = _preview_for_order(future, planned_tile, has_planned_tile)
		if not future_preview.is_empty():
			future_preview["sequence_index"] = sequence_index
			future_preview["future"] = true
			out.append(future_preview)
			if _preview_keeps_planned_tile(future_preview, has_planned_tile):
				planned_tile = _preview_planned_tile_value(future_preview, planned_tile)
				has_planned_tile = true
			sequence_index += 1
	var rally_preview: Dictionary = _rally_preview_for_entity(entity_id)
	if not rally_preview.is_empty():
		out.append(rally_preview)
	if not out.is_empty():
		return out
	var entity: Entity = _state.get_entity_by_id(entity_id)
	if entity == null:
		return out
	var shot_target_id: int = _attack_target_for_entity(entity.id)
	if shot_target_id >= 0:
		out.append(
			{"entity_id": entity.id, "kind": "Idle + Shoot", "target_entity_id": shot_target_id}
		)
	elif _will_halt_on_sight(entity.id):
		var visible_enemy_id: int = _visible_enemy_for_entity(entity)
		out.append({"entity_id": entity.id, "kind": "Halted", "target_entity_id": visible_enemy_id})
	if entity.focus_target_entity_id >= 0:
		(
			out
			. append(
				{
					"entity_id": entity.id,
					"kind": "Target",
					"target_entity_id": entity.focus_target_entity_id,
				}
			)
		)
	if (
		entity.gather_state != null
		and entity.gather_state.phase != GatherState.Phase.IDLE
		and entity.gather_state.assigned_source_entity_id >= 0
	):
		(
			out
			. append(
				{
					"entity_id": entity.id,
					"kind": "Gather",
					"target_entity_id": entity.gather_state.assigned_source_entity_id,
				}
			)
		)
	return out


func _rally_preview_for_entity(entity_id: int) -> Dictionary:
	if entity_id < 0 or _state == null:
		return {}
	var entity: Entity = _state.get_entity_by_id(entity_id)
	if entity == null or entity.production_state == null:
		return {}
	var mode: String = entity.production_state.rally_mode
	if mode == ProductionState.RALLY_MODE_MOVE:
		return {
			"entity_id": entity.id,
			"kind": "Rally",
			"target_tile": entity.production_state.rally_target_tile,
		}
	if mode == ProductionState.RALLY_MODE_GATHER:
		return {
			"entity_id": entity.id,
			"kind": "Rally Gather",
			"target_entity_id": entity.production_state.rally_target_entity_id,
		}
	return {}


func _queued_orders_for_entity(entity_id: int) -> Array[EntityOrder]:
	var out: Array[EntityOrder] = []
	if _input == null:
		return out
	var submit: SubmitTurn = _input.submit_for_player(_player_id)
	for order in submit.orders:
		if order != null and order.entity_id == entity_id:
			out.append(order)
	return out


func _future_orders_for_entity(entity_id: int) -> Array[EntityOrder]:
	if _input == null:
		var empty: Array[EntityOrder] = []
		return empty
	return _input.future_orders_for_entity(entity_id)


func _preview_for_order(
	order: EntityOrder, start_tile: Vector2i = Vector2i.ZERO, has_start_tile: bool = false
) -> Dictionary:
	if order == null:
		return {}
	var preview: Dictionary = {}
	match order.type:
		EntityOrder.Type.MOVE:
			var kind: String = "Attack and Move"
			if _will_halt_on_sight(order.entity_id) and order.target_priority_chain.is_empty():
				kind = (
					"Shoot + Hold" if _attack_target_for_entity(order.entity_id) >= 0 else "Halted"
				)
				preview = _halted_move_preview(order.entity_id, kind)
			elif _attack_target_for_entity(order.entity_id) >= 0:
				preview = _move_preview(order, "Shoot + Move", start_tile, has_start_tile)
			else:
				preview = _move_preview(order, kind, start_tile, has_start_tile)
		EntityOrder.Type.MOVE_ONLY:
			preview = _move_preview(order, "Move Only", start_tile, has_start_tile)
		EntityOrder.Type.ATTACK_TARGET:
			preview = _targeted_attack_preview(order, start_tile, has_start_tile)
		EntityOrder.Type.ATTACK:
			var target_id: int = -1
			if not order.target_priority_chain.is_empty():
				target_id = order.target_priority_chain[0]
			preview = {
				"entity_id": order.entity_id,
				"kind": "Target",
				"target_entity_id": target_id,
			}
		EntityOrder.Type.GATHER:
			preview = _gather_preview(order, start_tile, has_start_tile)
		EntityOrder.Type.BUILD:
			preview = _build_preview(order, start_tile, has_start_tile)
		EntityOrder.Type.TRAIN:
			preview = {"entity_id": order.entity_id, "kind": "Train", "def_id": order.def_id}
		EntityOrder.Type.RESEARCH:
			preview = {"entity_id": order.entity_id, "kind": "Research", "def_id": order.def_id}
		EntityOrder.Type.USE_ABILITY:
			preview = {"entity_id": order.entity_id, "kind": "Ability", "def_id": order.def_id}
		_:
			preview = {}
	if not preview.is_empty() and has_start_tile:
		preview["start_tile"] = start_tile
	return preview


func _halted_move_preview(entity_id: int, kind: String) -> Dictionary:
	var preview: Dictionary = {
		"entity_id": entity_id,
		"kind": kind,
	}
	var target_id: int = _attack_target_for_entity(entity_id)
	if target_id < 0:
		var actor: Entity = _state.get_entity_by_id(entity_id) if _state != null else null
		target_id = _visible_enemy_for_entity(actor)
	if target_id >= 0:
		preview["target_entity_id"] = target_id
	return preview


func _move_preview(
	order: EntityOrder,
	kind: String,
	start_tile: Vector2i = Vector2i.ZERO,
	has_start_tile: bool = false
) -> Dictionary:
	var preview: Dictionary = {
		"entity_id": order.entity_id,
		"kind": kind,
		"target_tile": order.target_tile,
	}
	var actor: Entity = _state.get_entity_by_id(order.entity_id) if _state != null else null
	if actor == null or _registry == null:
		return preview
	var goal: Dictionary = _move_preview_goal(order, actor)
	var target_origin: Vector2i = goal.get("target_origin", order.target_tile)
	preview["target_tile"] = target_origin
	if goal.has("target_entity_id"):
		preview["target_entity_id"] = goal["target_entity_id"]
	var start_origin: Vector2i = start_tile if has_start_tile else actor.origin
	if not _should_preview_move_path(order, actor, start_origin, target_origin):
		return preview
	var path_actor: Entity = _preview_actor_at(actor, start_tile, has_start_tile)
	var options: Dictionary = _path_preview_options(actor.owner_player_id)
	if goal.has("goal_rect"):
		options[PATHFINDING_SCRIPT.OPTION_GOAL_RECT] = goal["goal_rect"]
		options[PATHFINDING_SCRIPT.OPTION_GOAL_RANGE] = goal.get("goal_range", 0)
		options[PATHFINDING_SCRIPT.OPTION_EXACT_ORIGIN] = goal.get("exact_origin", true)
	var path: Array[Vector2i] = PATHFINDING_SCRIPT.find_path(
		_state, path_actor, target_origin, _registry, options
	)
	if not path.is_empty():
		preview["path"] = path
	return preview


func _targeted_attack_preview(
	order: EntityOrder, start_tile: Vector2i = Vector2i.ZERO, has_start_tile: bool = false
) -> Dictionary:
	var target_id: int = -1
	if order != null and not order.target_priority_chain.is_empty():
		target_id = order.target_priority_chain[0]
	var preview: Dictionary = {
		"entity_id": order.entity_id,
		"kind": "Target",
		"target_entity_id": target_id,
		"target_tile": order.target_tile,
	}
	var actor: Entity = _state.get_entity_by_id(order.entity_id) if _state != null else null
	if actor == null or _registry == null:
		return preview
	var goal: Dictionary = _targeted_attack_preview_goal(order, actor)
	var target_origin: Vector2i = goal.get("target_origin", order.target_tile)
	preview["target_tile"] = target_origin
	if goal.has("target_entity_id"):
		preview["target_entity_id"] = goal["target_entity_id"]
	var start_origin: Vector2i = start_tile if has_start_tile else actor.origin
	if start_origin == target_origin or not _can_preview_spend_movement(actor):
		return preview
	var path_actor: Entity = _preview_actor_at(actor, start_tile, has_start_tile)
	var options: Dictionary = _path_preview_options(actor.owner_player_id)
	options[PATHFINDING_SCRIPT.OPTION_GOAL_RECT] = goal.get(
		"goal_rect", Rect2i(target_origin, Vector2i.ONE)
	)
	options[PATHFINDING_SCRIPT.OPTION_GOAL_RANGE] = goal.get(
		"goal_range", _attack_range_for_entity(actor)
	)
	options[PATHFINDING_SCRIPT.OPTION_EXACT_ORIGIN] = goal.get("exact_origin", false)
	var path: Array[Vector2i] = PATHFINDING_SCRIPT.find_path(
		_state, path_actor, target_origin, _registry, options
	)
	if not path.is_empty():
		preview["path"] = path
	return preview


func _targeted_attack_preview_goal(order: EntityOrder, actor: Entity) -> Dictionary:
	var fallback_target_id: int = -1
	if order != null and not order.target_priority_chain.is_empty():
		fallback_target_id = order.target_priority_chain[0]
	var fallback: Dictionary = {
		"target_origin": order.target_tile,
		"target_entity_id": fallback_target_id,
		"goal_rect": Rect2i(order.target_tile, Vector2i.ONE),
		"exact_origin": false,
		"goal_range": _attack_range_for_entity(actor),
	}
	if (
		order == null
		or actor == null
		or order.target_priority_chain.is_empty()
		or _state == null
		or _state.tile_grid == null
	):
		return fallback
	var target: Entity = _state.get_entity_by_id(order.target_priority_chain[0])
	if target == null or target.current_hp <= 0:
		return fallback
	if target.owner_player_id < 0 or target.owner_player_id == actor.owner_player_id:
		return fallback
	if not _can_attack_layer(actor, target):
		return fallback
	var target_rect: Rect2i = _entity_rect(target)
	if target_rect.size == Vector2i.ZERO:
		target_rect = Rect2i(
			target.origin, PATHFINDING_SCRIPT.entity_footprint(_state, target, _registry)
		)
	return {
		"target_origin": target_rect.position,
		"target_entity_id": target.id,
		"goal_rect": target_rect,
		"exact_origin": false,
		"goal_range": _attack_range_for_entity(actor),
	}


func _move_preview_goal(order: EntityOrder, actor: Entity) -> Dictionary:
	var fallback: Dictionary = {
		"target_origin": order.target_tile,
		"exact_origin": true,
		"goal_range": 0,
	}
	if (
		order == null
		or actor == null
		or order.type != EntityOrder.Type.MOVE
		or order.target_priority_chain.is_empty()
		or _state == null
		or _state.tile_grid == null
	):
		return fallback
	for target_id in order.target_priority_chain:
		var target: Entity = _state.get_entity_by_id(target_id)
		if target == null or target.current_hp <= 0:
			continue
		if target.owner_player_id < 0 or target.owner_player_id == actor.owner_player_id:
			continue
		var target_rect: Rect2i = _entity_rect(target)
		if target_rect.size == Vector2i.ZERO:
			target_rect = Rect2i(target.origin, Vector2i.ONE)
		return {
			"target_origin": target_rect.position,
			"target_entity_id": target.id,
			"goal_rect": target_rect,
			"exact_origin": false,
			"goal_range": 1,
		}
	return fallback


func _gather_preview(
	order: EntityOrder, start_tile: Vector2i = Vector2i.ZERO, has_start_tile: bool = false
) -> Dictionary:
	var preview: Dictionary = {
		"entity_id": order.entity_id,
		"kind": "Gather",
		"target_entity_id": order.target_entity_id,
	}
	var actor: Entity = _state.get_entity_by_id(order.entity_id) if _state != null else null
	var target: Entity = _state.get_entity_by_id(order.target_entity_id) if _state != null else null
	if actor == null or target == null or _registry == null:
		return preview
	var target_rect: Rect2i = _entity_rect(target)
	if target_rect.size == Vector2i.ZERO:
		return preview
	var options: Dictionary = _path_preview_options(actor.owner_player_id)
	options[PATHFINDING_SCRIPT.OPTION_GOAL_RECT] = target_rect
	options[PATHFINDING_SCRIPT.OPTION_GOAL_RANGE] = 1
	options[PATHFINDING_SCRIPT.OPTION_EXACT_ORIGIN] = false
	var path_actor: Entity = _preview_actor_at(actor, start_tile, has_start_tile)
	var handoff_tile: Vector2i = path_actor.origin
	var path: Array[Vector2i] = PATHFINDING_SCRIPT.find_path(
		_state, path_actor, target_rect.position, _registry, options
	)
	if not path.is_empty():
		preview["path"] = path
		handoff_tile = path[path.size() - 1]
	preview["handoff_tile"] = handoff_tile
	return preview


func _build_preview(
	order: EntityOrder, start_tile: Vector2i = Vector2i.ZERO, has_start_tile: bool = false
) -> Dictionary:
	var preview: Dictionary = {
		"entity_id": order.entity_id,
		"kind": "Build",
		"target_tile": order.target_tile,
		"def_id": order.def_id,
	}
	var actor: Entity = _state.get_entity_by_id(order.entity_id) if _state != null else null
	if actor == null or _registry == null:
		return preview
	var def: EntityDef = _registry.get_by_id(order.def_id)
	var footprint: Vector2i = def.footprint if def != null else Vector2i.ONE
	if footprint == Vector2i.ZERO:
		footprint = Vector2i.ONE
	var build_rect: Rect2i = Rect2i(order.target_tile, footprint)
	var options: Dictionary = _path_preview_options(actor.owner_player_id)
	options[PATHFINDING_SCRIPT.OPTION_GOAL_RECT] = build_rect
	options[PATHFINDING_SCRIPT.OPTION_GOAL_RANGE] = 1
	options[PATHFINDING_SCRIPT.OPTION_EXACT_ORIGIN] = false
	var path_actor: Entity = _preview_actor_at(actor, start_tile, has_start_tile)
	var handoff_tile: Vector2i = path_actor.origin
	var path: Array[Vector2i] = PATHFINDING_SCRIPT.find_path(
		_state, path_actor, order.target_tile, _registry, options
	)
	if not path.is_empty():
		preview["path"] = path
		handoff_tile = path[path.size() - 1]
	preview["handoff_tile"] = handoff_tile
	return preview


func _preview_actor_at(actor: Entity, start_tile: Vector2i, has_start_tile: bool) -> Entity:
	if actor == null or not has_start_tile:
		return actor
	var preview_actor: Entity = actor.clone()
	preview_actor.origin = start_tile
	return preview_actor


func _should_preview_move_path(
	order: EntityOrder, actor: Entity, start_origin: Vector2i, target_origin: Vector2i
) -> bool:
	if order == null or actor == null:
		return false
	if not _can_preview_spend_movement(actor):
		return false
	if actor.ability_cast != null:
		return false
	if (
		order.type == EntityOrder.Type.MOVE
		and _will_halt_on_sight(actor.id)
		and order.target_priority_chain.is_empty()
	):
		return false
	return start_origin != target_origin


func _preview_keeps_planned_tile(preview: Dictionary, has_planned_tile: bool) -> bool:
	return preview.has("handoff_tile") or preview.has("target_tile") or has_planned_tile


func _preview_planned_tile_value(preview: Dictionary, fallback: Vector2i) -> Vector2i:
	if preview.has("handoff_tile"):
		return preview.get("handoff_tile", fallback)
	return preview.get("target_tile", fallback)


func _path_preview_options(player_id: int) -> Dictionary:
	return {
		PATHFINDING_SCRIPT.OPTION_KNOWN_ENTITY_IDS: _preview_known_entity_ids(player_id),
		PATHFINDING_SCRIPT.OPTION_PASSABLE_ENTITY_IDS: _preview_passable_entity_ids(),
	}


func _preview_known_entity_ids(player_id: int) -> Dictionary:
	var known: Dictionary = {}
	if _state == null:
		return known
	for entity in _state.entities_sorted_by_id():
		if entity == null:
			continue
		if entity.owner_player_id == player_id or entity.owner_player_id < 0:
			known[entity.id] = true
			continue
		if _renderer != null and _renderer.is_entity_view_visible(entity.id):
			known[entity.id] = true
	return known


func _preview_passable_entity_ids() -> Dictionary:
	var passable: Dictionary = {}
	if _state == null or _input == null:
		return passable
	var submit: SubmitTurn = _input.submit_for_player(_player_id)
	for order in submit.orders:
		if order == null:
			continue
		if _is_preview_explicit_mover(order):
			passable[order.entity_id] = true
	for entity in _state.entities_sorted_by_id():
		if entity == null or entity.current_hp <= 0:
			continue
		if _is_preview_gather_travel(entity):
			passable[entity.id] = true
		if _is_preview_construction_travel(entity):
			passable[entity.id] = true
	return passable


func _is_preview_explicit_mover(order: EntityOrder) -> bool:
	if order.type != EntityOrder.Type.MOVE and order.type != EntityOrder.Type.MOVE_ONLY:
		return false
	var actor: Entity = _state.get_entity_by_id(order.entity_id) if _state != null else null
	if not _can_preview_spend_movement(actor):
		return false
	if actor.ability_cast != null:
		return false
	if order.type == EntityOrder.Type.MOVE and _will_halt_on_sight(actor.id):
		return false
	return actor.origin != order.target_tile


func _is_preview_gather_travel(entity: Entity) -> bool:
	return (
		entity.gather_state != null
		and entity.gather_state.phase == GatherState.Phase.MOVING_TO_SOURCE
		and _can_preview_spend_movement(entity)
	)


func _is_preview_construction_travel(entity: Entity) -> bool:
	if entity.locked_to_building_id < 0 or not _can_preview_spend_movement(entity):
		return false
	var building: Entity = (
		_state.get_entity_by_id(entity.locked_to_building_id) if _state != null else null
	)
	if building == null or building.current_hp <= 0 or not building.is_constructing:
		return false
	return not _are_entities_adjacent(entity, building)


func _attack_range_for_entity(actor: Entity) -> int:
	if actor == null or _registry == null:
		return 1
	var def: EntityDef = _registry.get_by_id(
		actor.current_def_id if actor.current_def_id != "" else actor.def_id
	)
	if def == null or def.combat == null:
		return 1
	return def.combat.attack_range


func _can_attack_layer(actor: Entity, target: Entity) -> bool:
	if actor == null or target == null or _registry == null:
		return false
	var def: EntityDef = _registry.get_by_id(
		actor.current_def_id if actor.current_def_id != "" else actor.def_id
	)
	if def == null or def.combat == null:
		return false
	if def.combat.target_layers.size() == 0:
		return true
	return def.combat.target_layers.has(target.current_layer)


func _can_preview_spend_movement(entity: Entity) -> bool:
	if entity == null or entity.current_hp <= 0 or _state == null or _registry == null:
		return false
	var movement: MovementDef = PATHFINDING_SCRIPT.movement_def_for_entity(entity, _registry)
	return movement != null and entity.moves_used_this_turn < movement.speed_tiles_per_turn


func _are_entities_adjacent(a: Entity, b: Entity) -> bool:
	if _state == null or _state.tile_grid == null:
		return false
	var a_rect: Rect2i = _state.tile_grid.entity_rect(a.id)
	var b_rect: Rect2i = _state.tile_grid.entity_rect(b.id)
	if a_rect.size == Vector2i.ZERO or b_rect.size == Vector2i.ZERO:
		return false
	return TileGrid.distance_between_rects(a_rect, b_rect) <= 1


func _attack_target_for_entity(entity_id: int) -> int:
	if _state == null or _registry == null:
		return -1
	var actor: Entity = _state.get_entity_by_id(entity_id)
	if not _can_preview_attack(actor):
		return -1
	var def: EntityDef = _registry.get_by_id(
		actor.current_def_id if actor.current_def_id != "" else actor.def_id
	)
	if def == null or def.combat == null:
		return -1
	if actor.focus_target_entity_id >= 0:
		var focus: Entity = _state.get_entity_by_id(actor.focus_target_entity_id)
		if _is_attack_target_in_range(actor, focus, def.combat):
			return focus.id
	var closest_id: int = -1
	var closest_dist: int = -1
	for candidate in _state.entities_sorted_by_id():
		if not _is_attack_target_in_range(actor, candidate, def.combat):
			continue
		var dist: int = _entity_distance(actor, candidate)
		if closest_id < 0 or dist < closest_dist:
			closest_id = candidate.id
			closest_dist = dist
	return closest_id


func _will_halt_on_sight(entity_id: int) -> bool:
	if _state == null or _registry == null:
		return false
	var actor: Entity = _state.get_entity_by_id(entity_id)
	if not _can_preview_attack(actor) or not actor.halt_on_sight:
		return false
	return _visible_enemy_for_entity(actor) >= 0


func _can_preview_attack(entity: Entity) -> bool:
	if entity == null or entity.current_hp <= 0:
		return false
	if entity.ability_cast != null:
		return false
	if entity.gather_state != null and entity.gather_state.phase != GatherState.Phase.IDLE:
		return false
	if (
		ConstructionSystem.has_pending_build(entity)
		or entity.locked_to_building_id >= 0
		or entity.is_constructing
	):
		return false
	return true


func _visible_enemy_for_entity(actor: Entity) -> int:
	if actor == null or _state == null or _registry == null:
		return -1
	var visibility: VisionSystem.Visibility = _visibility_for_player(actor.owner_player_id)
	for candidate in _state.entities_sorted_by_id():
		if candidate == null or candidate.current_hp <= 0:
			continue
		if candidate.owner_player_id < 0 or candidate.owner_player_id == actor.owner_player_id:
			continue
		if VisionSystem.is_entity_visible_to_player(
			candidate, _state, _registry, actor.owner_player_id, visibility
		):
			return candidate.id
	return -1


func _visibility_for_player(player_id: int) -> VisionSystem.Visibility:
	if _state == null or _registry == null:
		return null
	if _visibility_by_player.has(player_id):
		return _visibility_by_player[player_id]
	var visibility: VisionSystem.Visibility = VisionSystem.compute_player_visibility(
		_state, _registry, player_id
	)
	_visibility_by_player[player_id] = visibility
	return visibility


func _is_attack_target_in_range(actor: Entity, target: Entity, combat: CombatDef) -> bool:
	if actor == null or target == null or combat == null:
		return false
	if target.id == actor.id or target.current_hp <= 0:
		return false
	if target.owner_player_id < 0 or target.owner_player_id == actor.owner_player_id:
		return false
	if not combat.target_layers.has(target.current_layer):
		return false
	var dist: int = _entity_distance(actor, target)
	return dist >= 0 and dist <= combat.attack_range


func _entity_distance(a: Entity, b: Entity) -> int:
	if _state == null or _registry == null:
		return -1
	var a_rect: Rect2i = _entity_rect(a)
	var b_rect: Rect2i = _entity_rect(b)
	if a_rect.size == Vector2i.ZERO or b_rect.size == Vector2i.ZERO:
		return -1
	return TileGrid.distance_between_rects(a_rect, b_rect)


func _entity_rect(entity: Entity) -> Rect2i:
	if entity == null or _state == null or _registry == null:
		return Rect2i()
	if _state.tile_grid != null:
		var rect: Rect2i = _state.tile_grid.entity_rect(entity.id)
		if rect.size != Vector2i.ZERO:
			return rect
	var def: EntityDef = _registry.get_by_id(
		entity.current_def_id if entity.current_def_id != "" else entity.def_id
	)
	if def == null:
		return Rect2i()
	return Rect2i(entity.origin, def.footprint)
