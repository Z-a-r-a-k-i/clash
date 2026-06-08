class_name MovementSystem
extends RefCounted

# Movement system — resolves submitted MOVE and MOVE_ONLY orders.
#
# Per-tick semantics (called from Phase 3 of the resolver tick loop):
# - MOVE / MOVE_ONLY: advance one tile toward order.target_tile if the entity has
#   move budget remaining. Ignores enemies along the path.
# - MOVE with target_priority_chain chases the first live enemy in the chain and
#   falls back to order.target_tile if none is still alive.
#
# Per-turn budget: an entity can move at most `def.movement.speed_tiles_per_turn`
# tiles in one turn, accumulated across all ticks. Tracked via
# Entity.moves_used_this_turn (reset at end-of-turn).
#
const _ABILITY_SYSTEM := preload("res://scripts/resolver/ability_system.gd")
const _PATHFINDING := preload("res://scripts/resolver/pathfinding_system.gd")


static func resolve_move(
	state: MatchState,
	actor: Entity,
	order: EntityOrder,
	registry: EntityRegistry,
	_tunables: Tunables,
	events: Array[ResolverEvent],
	movement_budget: int = -1
) -> void:
	if actor == null or actor.current_hp <= 0:
		return
	if state.tile_grid == null:
		return

	# Move budget check.
	var movement_speed: int = (
		movement_speed_for_entity(actor, registry) if movement_budget < 0 else movement_budget
	)
	if movement_speed <= 0:
		return  # Not movement-capable.
	if actor.moves_used_this_turn >= movement_speed:
		return

	var target_tile: Vector2i = _target_tile_for_order(state, actor, order)
	if step_toward(state, actor, target_tile, events):
		actor.moves_used_this_turn += 1


static func resolve_movement_substep(
	state: MatchState,
	per_entity: Dictionary,
	tick: int,
	registry: EntityRegistry,
	_tunables: Tunables,
	events: Array[ResolverEvent],
	fired_entity_ids: Dictionary,
	halted_entity_ids: Dictionary,
	sorted_entities: Array[Entity],
	path_cache: Variant = null,
	profile: Variant = null
) -> bool:
	if state == null or state.tile_grid == null or registry == null:
		return false
	var active_path_cache: Dictionary = path_cache if path_cache is Dictionary else {}
	var intents: Array[Dictionary] = _movement_intents(
		state,
		per_entity,
		tick,
		registry,
		fired_entity_ids,
		halted_entity_ids,
		sorted_entities,
		events
	)
	if intents.is_empty():
		return false
	_count_profile(profile, "movement.intents", intents.size())
	var passable_entity_ids: Dictionary = {}
	for intent in intents:
		var intent_entity_id: int = intent.get("entity_id", -1)
		if intent_entity_id >= 0:
			passable_entity_ids[intent_entity_id] = true
		var kind: String = intent.get("kind", "")
		if kind != "":
			_count_profile(profile, "movement.intent.%s" % kind)
		if bool(intent.get("exact_origin", true)):
			_count_profile(profile, "movement.intent.exact")
		else:
			_count_profile(profile, "movement.intent.inexact")

	var proposals: Array[Dictionary] = []
	var occupancy_blockers_by_layer: Dictionary = {}
	for intent in intents:
		var actor: Entity = intent.get("actor") as Entity
		if actor == null:
			continue
		var target_origin: Vector2i = intent.get("target_origin", actor.origin)
		var actor_layer: String = _PATHFINDING.layer_for_entity(actor, registry)
		if not occupancy_blockers_by_layer.has(actor_layer):
			occupancy_blockers_by_layer[actor_layer] = _PATHFINDING._occupancy_blockers(
				state, null, registry, actor_layer, passable_entity_ids, {}
			)
		var footprint: Vector2i = _PATHFINDING.entity_footprint(state, actor, registry)
		var movement: MovementDef = _PATHFINDING.movement_def_for_entity(actor, registry)
		if movement == null:
			continue
		var options: Dictionary = {
			_PATHFINDING.OPTION_PASSABLE_ENTITY_IDS: passable_entity_ids,
			_PATHFINDING.OPTION_EXACT_ORIGIN: intent.get("exact_origin", true),
			_PATHFINDING.OPTION_GOAL_RANGE: intent.get("goal_range", 0),
			_PATHFINDING.OPTION_OCCUPANCY_BLOCKERS: occupancy_blockers_by_layer[actor_layer],
			_PATHFINDING.OPTION_PROFILE: profile,
		}
		if intent.has("goal_rect"):
			options[_PATHFINDING.OPTION_GOAL_RECT] = intent["goal_rect"]
		var step: Dictionary = _cached_next_step(
			state.tile_grid,
			actor,
			target_origin,
			footprint,
			movement,
			options,
			intent,
			active_path_cache
		)
		if step.is_empty():
			_count_profile(profile, "movement.path_cache_miss")
			step = _PATHFINDING.find_next_step(state, actor, target_origin, registry, options)
			_store_path_cache(actor, target_origin, intent, step, active_path_cache)
		else:
			_count_profile(profile, "movement.path_cache_hit")
		if step.is_empty():
			continue
		var next_origin: Vector2i = step.get("next_origin", actor.origin)
		if next_origin == actor.origin:
			continue
		(
			proposals
			. append(
				{
					"entity_id": actor.id,
					"actor": actor,
					"from_origin": actor.origin,
					"to_origin": next_origin,
					"target_rect": Rect2i(next_origin, footprint),
					"layer": actor_layer,
					"path_distance": int(step.get("path_distance", 1)),
					"intent": intent,
				}
			)
		)
	if proposals.is_empty():
		return false
	_count_profile(profile, "movement.proposals", proposals.size())

	var winners: Array[Dictionary] = _winning_proposals(state, proposals, registry, events)
	if winners.is_empty():
		return false
	_count_profile(profile, "movement.winners", winners.size())
	var moves: Dictionary = {}
	for proposal in winners:
		moves[proposal.get("entity_id", -1)] = proposal.get("to_origin", Vector2i.ZERO)
	if not state.tile_grid.move_batch(moves, true):
		return false
	winners.sort_custom(_proposal_id_less)
	for proposal in winners:
		_commit_proposal(state, proposal, registry, events)
	return true


# ---------- Internals ----------


static func _cached_next_step(
	grid: TileGrid,
	actor: Entity,
	target_origin: Vector2i,
	footprint: Vector2i,
	movement: MovementDef,
	options: Dictionary,
	intent: Dictionary,
	path_cache: Dictionary
) -> Dictionary:
	if grid == null or actor == null or not path_cache.has(actor.id):
		return {}
	var cached: Dictionary = path_cache.get(actor.id, {})
	if cached.get("target_origin", Vector2i.ZERO) != target_origin:
		return {}
	if bool(cached.get("exact_origin", true)) != bool(intent.get("exact_origin", true)):
		return {}
	if int(cached.get("goal_range", 0)) != int(intent.get("goal_range", 0)):
		return {}
	if bool(cached.get("has_goal_rect", false)) != intent.has("goal_rect"):
		return {}
	if intent.has("goal_rect") and cached.get("goal_rect", Rect2i()) != intent["goal_rect"]:
		return {}
	var path: Array = cached.get("path", [])
	while not path.is_empty() and path[0] == actor.origin:
		path.remove_at(0)
	if path.is_empty():
		path_cache.erase(actor.id)
		return {}
	var next_origin: Vector2i = path[0]
	var occupancy_blockers: Dictionary = options.get(_PATHFINDING.OPTION_OCCUPANCY_BLOCKERS, {})
	for path_origin in path:
		var path_origin_vec: Vector2i = path_origin
		if not _PATHFINDING._can_occupy_origin_with_blockers(
			grid, path_origin_vec, footprint, movement, occupancy_blockers
		):
			path_cache.erase(actor.id)
			return {}
	cached["path"] = path
	path_cache[actor.id] = cached
	return {
		"next_origin": next_origin,
		"path_distance": path.size(),
	}


static func _store_path_cache(
	actor: Entity,
	target_origin: Vector2i,
	intent: Dictionary,
	step: Dictionary,
	path_cache: Dictionary
) -> void:
	if actor == null:
		return
	if step.is_empty() or not step.has("path"):
		path_cache.erase(actor.id)
		return
	var raw_path: Array = step["path"]
	var cached_path: Array[Vector2i] = []
	for item in raw_path:
		cached_path.append(item)
	path_cache[actor.id] = {
		"target_origin": target_origin,
		"exact_origin": bool(intent.get("exact_origin", true)),
		"goal_range": int(intent.get("goal_range", 0)),
		"has_goal_rect": intent.has("goal_rect"),
		"goal_rect": intent.get("goal_rect", Rect2i()),
		"path": cached_path,
	}


static func has_fresh_order_at(per_entity: Dictionary, entity_id: int, tick: int) -> bool:
	if not per_entity.has(entity_id):
		return false
	var queue: Array = per_entity[entity_id]
	if tick < 0 or tick >= queue.size():
		return false
	var order: EntityOrder = queue[tick]
	return order != null


static func _movement_intents(
	state: MatchState,
	per_entity: Dictionary,
	tick: int,
	registry: EntityRegistry,
	fired_entity_ids: Dictionary,
	halted_entity_ids: Dictionary,
	sorted_entities: Array[Entity],
	events: Array[ResolverEvent]
) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	var source_assignments: Dictionary[int, Array] = {}
	var has_source_assignments := false
	for actor in sorted_entities:
		if actor == null or actor.current_hp <= 0:
			continue
		if _ABILITY_SYSTEM.is_casting(actor):
			continue
		var order: EntityOrder = _action_at(per_entity, actor.id, tick)
		var explicit_intent: Dictionary = _explicit_move_intent(
			state, actor, order, registry, fired_entity_ids, halted_entity_ids
		)
		if not explicit_intent.is_empty():
			intents.append(explicit_intent)
			continue
		if order != null:
			continue
		if (
			actor.gather_state != null
			and actor.gather_state.phase == GatherState.Phase.MOVING_TO_SOURCE
			and not has_source_assignments
		):
			source_assignments = GatherSystem._source_assignments_by_source(state, registry)
			has_source_assignments = true
		var gather_intent: Dictionary = _gather_move_intent(
			state, actor, registry, source_assignments
		)
		if not gather_intent.is_empty():
			intents.append(gather_intent)
			continue
		var construction_intent: Dictionary = _construction_move_intent(
			state, actor, registry, events
		)
		if not construction_intent.is_empty():
			intents.append(construction_intent)
	return intents


static func _explicit_move_intent(
	state: MatchState,
	actor: Entity,
	order: EntityOrder,
	registry: EntityRegistry,
	fired_entity_ids: Dictionary,
	halted_entity_ids: Dictionary
) -> Dictionary:
	if order == null:
		return {}
	if (
		order.type != EntityOrder.Type.MOVE
		and order.type != EntityOrder.Type.MOVE_ONLY
		and order.type != EntityOrder.Type.ATTACK
	):
		return {}
	if order.type == EntityOrder.Type.ATTACK and fired_entity_ids.has(actor.id):
		return {}
	if (
		order.type == EntityOrder.Type.MOVE
		and halted_entity_ids.has(actor.id)
		and order.target_priority_chain.is_empty()
	):
		return {}
	var move_only: bool = order.type == EntityOrder.Type.MOVE_ONLY
	var budget: int = movement_budget_for_entity(
		actor, registry, fired_entity_ids.has(actor.id), move_only
	)
	if not _can_spend_movement(actor, budget):
		return {}
	var goal: Dictionary = _goal_for_order(state, actor, order, registry)
	var target_origin: Vector2i = goal.get("target_origin", order.target_tile)
	if actor.origin == target_origin and bool(goal.get("exact_origin", true)):
		return {}
	var intent: Dictionary = {
		"kind": "move",
		"entity_id": actor.id,
		"actor": actor,
		"target_origin": target_origin,
		"exact_origin": goal.get("exact_origin", true),
		"goal_range": goal.get("goal_range", 0),
		"movement_budget": budget,
	}
	if goal.has("goal_rect"):
		intent["goal_rect"] = goal["goal_rect"]
	return intent


static func _goal_for_order(
	state: MatchState, actor: Entity, order: EntityOrder, registry: EntityRegistry
) -> Dictionary:
	if order != null and order.type == EntityOrder.Type.ATTACK:
		return _attack_goal_for_order(state, actor, order, registry)
	return _move_goal_for_order(state, actor, order)


static func _move_goal_for_order(
	state: MatchState, actor: Entity, order: EntityOrder
) -> Dictionary:
	var fallback: Dictionary = {
		"target_origin": order.target_tile,
		"exact_origin": true,
		"goal_range": 0,
	}
	if (
		state == null
		or state.tile_grid == null
		or actor == null
		or order == null
		or order.type != EntityOrder.Type.MOVE
		or order.target_priority_chain.is_empty()
	):
		return fallback
	for target_id in order.target_priority_chain:
		var target: Entity = state.get_entity_by_id(target_id)
		if target == null or target.current_hp <= 0:
			continue
		if target.owner_player_id < 0 or target.owner_player_id == actor.owner_player_id:
			continue
		var target_rect: Rect2i = state.tile_grid.entity_rect(target.id)
		if target_rect.size == Vector2i.ZERO:
			target_rect = Rect2i(target.origin, Vector2i.ONE)
		return {
			"target_origin": target_rect.position,
			"goal_rect": target_rect,
			"exact_origin": false,
			"goal_range": 1,
		}
	return fallback


static func _attack_goal_for_order(
	state: MatchState, actor: Entity, order: EntityOrder, registry: EntityRegistry
) -> Dictionary:
	var fallback: Dictionary = {
		"target_origin": order.target_tile,
		"goal_rect": Rect2i(order.target_tile, Vector2i.ONE),
		"exact_origin": false,
		"goal_range": _attack_range_for_entity(actor, registry),
	}
	if (
		state == null
		or state.tile_grid == null
		or actor == null
		or order == null
		or order.target_priority_chain.is_empty()
	):
		return fallback
	var target: Entity = state.get_entity_by_id(order.target_priority_chain[0])
	if target == null or not _is_attack_targetable(actor, target, registry):
		return fallback
	var target_rect: Rect2i = state.tile_grid.entity_rect(target.id)
	if target_rect.size == Vector2i.ZERO:
		target_rect = Rect2i(target.origin, _PATHFINDING.entity_footprint(state, target, registry))
	return {
		"target_origin": target_rect.position,
		"goal_rect": target_rect,
		"exact_origin": false,
		"goal_range": _attack_range_for_entity(actor, registry),
	}


static func _gather_move_intent(
	state: MatchState,
	actor: Entity,
	registry: EntityRegistry,
	source_assignments: Dictionary[int, Array]
) -> Dictionary:
	if actor.gather_state == null:
		return {}
	if actor.gather_state.phase != GatherState.Phase.MOVING_TO_SOURCE:
		return {}
	if not _can_spend_movement(actor, movement_speed_for_entity(actor, registry)):
		return {}
	var source: Entity = GatherSystem._resolve_source(
		state, registry, actor.gather_state.assigned_source_entity_id, actor.owner_player_id
	)
	if source == null:
		GatherSystem.clear_assignment(actor)
		return {}
	var assigned_source: Entity = GatherSystem.best_source_for_worker(
		state, registry, actor, source, source_assignments
	)
	if assigned_source == null:
		GatherSystem.clear_assignment(actor)
		return {}
	if assigned_source.id != source.id:
		actor.gather_state.assigned_source_entity_id = assigned_source.id
		GatherSystem.replace_assignment_in_map(source_assignments, actor.id, assigned_source.id)
		source = assigned_source
	if GatherSystem._is_adjacent_to(state, actor, source):
		actor.gather_state.phase = GatherState.Phase.GATHERING
		return {}
	var source_rect: Rect2i = state.tile_grid.entity_rect(source.id)
	if source_rect.size.x <= 0 or source_rect.size.y <= 0:
		return {}
	return {
		"kind": "gather",
		"entity_id": actor.id,
		"actor": actor,
		"target_origin": source_rect.position,
		"target_entity_id": source.id,
		"goal_rect": source_rect,
		"goal_range": 1,
		"exact_origin": false,
	}


static func _construction_move_intent(
	state: MatchState, actor: Entity, registry: EntityRegistry, events: Array[ResolverEvent]
) -> Dictionary:
	if ConstructionSystem.has_pending_build(actor):
		if ConstructionSystem.try_start_pending_build(state, actor, registry, events):
			return {}
		if not ConstructionSystem.has_pending_build(actor):
			return {}
		if not _can_spend_movement(actor, movement_speed_for_entity(actor, registry)):
			return {}
		var pending_layout: Dictionary = ConstructionSystem._pending_build_layout(
			state, actor, registry
		)
		if not pending_layout.get("valid", false):
			return {}
		var pending_rect: Rect2i = pending_layout["rect"]
		if ConstructionSystem._is_adjacent_to_rect(state, actor, pending_rect):
			ConstructionSystem.try_start_pending_build(state, actor, registry, events)
			return {}
		return {
			"kind": "pending_construction",
			"entity_id": actor.id,
			"actor": actor,
			"target_origin": pending_rect.position,
			"goal_rect": pending_rect,
			"goal_range": 1,
			"exact_origin": false,
		}
	if actor.locked_to_building_id < 0:
		return {}
	if not _can_spend_movement(actor, movement_speed_for_entity(actor, registry)):
		return {}
	var building: Entity = state.get_entity_by_id(actor.locked_to_building_id)
	if building == null or building.current_hp <= 0:
		actor.locked_to_building_id = -1
		return {}
	if not building.is_constructing:
		actor.locked_to_building_id = -1
		return {}
	if ConstructionSystem._is_adjacent_to(state, actor, building):
		return {}
	var building_rect: Rect2i = state.tile_grid.entity_rect(building.id)
	if building_rect.size.x <= 0 or building_rect.size.y <= 0:
		return {}
	return {
		"kind": "construction",
		"entity_id": actor.id,
		"actor": actor,
		"target_origin": building_rect.position,
		"target_entity_id": building.id,
		"goal_rect": building_rect,
		"goal_range": 1,
		"exact_origin": false,
	}


static func _winning_proposals(
	state: MatchState,
	proposals: Array[Dictionary],
	registry: EntityRegistry,
	events: Array[ResolverEvent]
) -> Array[Dictionary]:
	var remaining: Dictionary = {}
	for proposal in proposals:
		var entity_id: int = proposal.get("entity_id", -1)
		if entity_id >= 0:
			remaining[entity_id] = proposal
	var changed := true
	while changed:
		changed = false
		var conflict_result: Dictionary = _target_conflict_result(remaining)
		var blocked: Dictionary = conflict_result.get("losers", {})
		_emit_completed_tied_moves(conflict_result.get("completed", {}), remaining, events)
		var moving_ids: Dictionary = {}
		for entity_id in remaining.keys():
			if not blocked.has(entity_id):
				moving_ids[entity_id] = true
		var non_mover_blockers_by_layer: Dictionary = _non_mover_blockers_by_layer(
			state, registry, moving_ids
		)
		for entity_id in remaining.keys():
			if blocked.has(entity_id):
				continue
			var proposal: Dictionary = remaining[entity_id]
			if _target_blocked_by_non_mover(proposal, non_mover_blockers_by_layer):
				blocked[entity_id] = true
		if not blocked.is_empty():
			for entity_id in blocked.keys():
				remaining.erase(entity_id)
			changed = true
	var winners: Array[Dictionary] = []
	var ids: Array[int] = []
	for entity_id in remaining.keys():
		ids.append(int(entity_id))
	ids.sort()
	for entity_id in ids:
		winners.append(remaining[entity_id])
	return winners


static func _target_conflict_result(remaining: Dictionary) -> Dictionary:
	var losers: Dictionary = {}
	var completed: Dictionary = {}
	var ids: Array[int] = []
	for entity_id in remaining.keys():
		ids.append(int(entity_id))
	ids.sort()
	var visited: Dictionary = {}
	for start_id in ids:
		if visited.has(start_id):
			continue
		var component: Array[int] = _proposal_conflict_component(start_id, remaining)
		for entity_id in component:
			visited[entity_id] = true
		if component.size() <= 1:
			continue
		var min_distance: int = 0
		var min_ids: Array[int] = []
		for entity_id in component:
			var proposal: Dictionary = remaining[entity_id]
			var distance: int = proposal.get("path_distance", 0)
			if min_ids.is_empty() or distance < min_distance:
				min_distance = distance
				min_ids = [entity_id]
			elif distance == min_distance:
				min_ids.append(entity_id)
		if min_ids.size() == 1:
			var winner_id: int = min_ids[0]
			var single_winner_ids: Array[int] = [winner_id]
			_mark_direct_conflict_losers(single_winner_ids, component, remaining, losers)
		else:
			_process_equal_distance_minima(min_ids, component, remaining, losers, completed)
	return {"losers": losers, "completed": completed}


static func _process_equal_distance_minima(
	min_ids: Array[int],
	component: Array[int],
	remaining: Dictionary,
	losers: Dictionary,
	completed: Dictionary
) -> void:
	var visited: Dictionary = {}
	for start_id in min_ids:
		if visited.has(start_id):
			continue
		var group: Array[int] = _min_conflict_group(start_id, min_ids, remaining)
		for entity_id in group:
			visited[entity_id] = true
		if group.size() <= 1:
			_mark_direct_conflict_losers(group, component, remaining, losers)
			continue
		var winner_ids: Array[int] = _non_conflicting_min_winners(group, remaining)
		if winner_ids.size() <= 1:
			for entity_id in group:
				losers[entity_id] = true
			_mark_direct_conflict_losers(group, component, remaining, losers)
			_mark_completed_same_target_tie_groups(group, remaining, completed)
			continue
		_mark_direct_conflict_losers(winner_ids, component, remaining, losers)
		for entity_id in group:
			if not winner_ids.has(entity_id):
				losers[entity_id] = true


static func _min_conflict_group(
	start_id: int, candidate_ids: Array[int], remaining: Dictionary
) -> Array[int]:
	var group: Array[int] = []
	var queue: Array[int] = [start_id]
	var seen: Dictionary = {start_id: true}
	while not queue.is_empty():
		var current_id: int = queue.pop_front()
		group.append(current_id)
		for other_id in candidate_ids:
			if seen.has(other_id):
				continue
			if _proposals_directly_conflict(current_id, other_id, remaining):
				seen[other_id] = true
				queue.append(other_id)
	group.sort()
	return group


static func _non_conflicting_min_winners(group: Array[int], remaining: Dictionary) -> Array[int]:
	var candidates: Array[int] = group.duplicate()
	var winners: Array[int] = []
	while not candidates.is_empty():
		var best_id: int = candidates[0]
		var best_degree: int = _min_conflict_degree(best_id, candidates, remaining)
		for candidate_id in candidates:
			var degree: int = _min_conflict_degree(candidate_id, candidates, remaining)
			if degree < best_degree or (degree == best_degree and candidate_id < best_id):
				best_id = candidate_id
				best_degree = degree
		winners.append(best_id)
		var next_candidates: Array[int] = []
		for candidate_id in candidates:
			if candidate_id == best_id:
				continue
			if not _proposals_directly_conflict(best_id, candidate_id, remaining):
				next_candidates.append(candidate_id)
		candidates = next_candidates
	winners.sort()
	return winners


static func _min_conflict_degree(
	entity_id: int, candidate_ids: Array[int], remaining: Dictionary
) -> int:
	var degree: int = 0
	for candidate_id in candidate_ids:
		if (
			candidate_id != entity_id
			and _proposals_directly_conflict(entity_id, candidate_id, remaining)
		):
			degree += 1
	return degree


static func _mark_direct_conflict_losers(
	blocker_ids: Array[int], component: Array[int], remaining: Dictionary, losers: Dictionary
) -> void:
	for entity_id in component:
		if blocker_ids.has(entity_id):
			continue
		if _has_direct_conflict_with_any(entity_id, blocker_ids, remaining):
			losers[entity_id] = true


static func _has_direct_conflict_with_any(
	entity_id: int, candidate_ids: Array[int], remaining: Dictionary
) -> bool:
	for candidate_id in candidate_ids:
		if candidate_id == entity_id:
			continue
		if _proposals_directly_conflict(entity_id, candidate_id, remaining):
			return true
	return false


static func _proposals_directly_conflict(a_id: int, b_id: int, remaining: Dictionary) -> bool:
	var a: Dictionary = remaining.get(a_id, {})
	var b: Dictionary = remaining.get(b_id, {})
	var a_rect: Rect2i = a.get("target_rect", Rect2i())
	var b_rect: Rect2i = b.get("target_rect", Rect2i())
	return a.get("layer", "ground") == b.get("layer", "ground") and a_rect.intersects(b_rect)


static func _mark_completed_same_target_tie_groups(
	tied_ids: Array[int], remaining: Dictionary, completed: Dictionary
) -> void:
	var visited: Dictionary = {}
	for start_id in tied_ids:
		if visited.has(start_id):
			continue
		var group: Array[int] = []
		var queue: Array[int] = [start_id]
		visited[start_id] = true
		while not queue.is_empty():
			var current_id: int = queue.pop_front()
			group.append(current_id)
			for other_id in tied_ids:
				if visited.has(other_id):
					continue
				if _proposals_directly_conflict(current_id, other_id, remaining):
					visited[other_id] = true
					queue.append(other_id)
		group.sort()
		for completed_id in _completed_same_target_tie_ids(group, remaining):
			completed[completed_id] = true


static func _completed_same_target_tie_ids(
	tied_ids: Array[int], remaining: Dictionary
) -> Array[int]:
	if tied_ids.size() <= 1:
		return []
	var target_origin: Vector2i = Vector2i.ZERO
	var has_target: bool = false
	for entity_id in tied_ids:
		var proposal: Dictionary = remaining.get(entity_id, {})
		var intent: Dictionary = proposal.get("intent", {})
		if intent.get("kind", "") != "move":
			return []
		if not intent.get("exact_origin", true) or int(intent.get("goal_range", 0)) != 0:
			return []
		var intent_target: Vector2i = intent.get("target_origin", Vector2i.ZERO)
		if proposal.get("to_origin", Vector2i.ZERO) != intent_target:
			return []
		if not has_target:
			target_origin = intent_target
			has_target = true
		elif intent_target != target_origin:
			return []
	return tied_ids.duplicate()


static func _emit_completed_tied_moves(
	completed_ids: Dictionary, remaining: Dictionary, events: Array[ResolverEvent]
) -> void:
	var ids: Array[int] = []
	for entity_id in completed_ids.keys():
		ids.append(int(entity_id))
	ids.sort()
	for entity_id in ids:
		var proposal: Dictionary = remaining.get(entity_id, {})
		var actor: Entity = proposal.get("actor") as Entity
		if actor == null:
			continue
		var intent: Dictionary = proposal.get("intent", {})
		var movement_budget: int = int(intent.get("movement_budget", actor.moves_used_this_turn))
		actor.moves_used_this_turn = max(actor.moves_used_this_turn, movement_budget)
		var ev := ResolverEvent.new()
		ev.type = ResolverEvent.Type.MOVE_COMPLETED
		ev.actor_id = actor.id
		ev.from_origin = proposal.get("from_origin", actor.origin)
		ev.to_origin = intent.get("target_origin", actor.origin)
		events.append(ev)


static func _proposal_conflict_component(start_id: int, remaining: Dictionary) -> Array[int]:
	var component: Array[int] = []
	var queue: Array[int] = [start_id]
	var seen: Dictionary = {start_id: true}
	while not queue.is_empty():
		var current_id: int = queue.pop_front()
		component.append(current_id)
		var current: Dictionary = remaining[current_id]
		var current_rect: Rect2i = current.get("target_rect", Rect2i())
		for other_id in remaining.keys():
			var candidate_id: int = int(other_id)
			if seen.has(candidate_id):
				continue
			var other: Dictionary = remaining[candidate_id]
			var other_rect: Rect2i = other.get("target_rect", Rect2i())
			if (
				current.get("layer", "ground") == other.get("layer", "ground")
				and current_rect.intersects(other_rect)
			):
				seen[candidate_id] = true
				queue.append(candidate_id)
	component.sort()
	return component


static func _non_mover_blockers_by_layer(
	state: MatchState, registry: EntityRegistry, moving_ids: Dictionary
) -> Dictionary:
	var out: Dictionary = {}
	if state == null or state.tile_grid == null or registry == null:
		return out
	for entity in state.entities_sorted_by_id():
		if entity == null:
			continue
		if moving_ids.has(entity.id):
			continue
		if not _is_spatial_blocker(entity, registry):
			continue
		var other_rect: Rect2i = state.tile_grid.entity_rect(entity.id)
		if other_rect.size.x <= 0 or other_rect.size.y <= 0:
			continue
		var layer: String = _PATHFINDING.layer_for_entity(entity, registry)
		if not out.has(layer):
			out[layer] = []
		out[layer].append(other_rect)
	return out


static func _target_blocked_by_non_mover(
	proposal: Dictionary, non_mover_blockers_by_layer: Dictionary
) -> bool:
	var target_rect: Rect2i = proposal.get("target_rect", Rect2i())
	var actor_layer: String = proposal.get("layer", "ground")
	var blocker_rects: Array = non_mover_blockers_by_layer.get(actor_layer, [])
	for other_rect in blocker_rects:
		if other_rect.intersects(target_rect):
			return true
	return false


static func _commit_proposal(
	state: MatchState, proposal: Dictionary, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	var actor: Entity = proposal.get("actor") as Entity
	if actor == null:
		return
	var from_origin: Vector2i = proposal.get("from_origin", actor.origin)
	var to_origin: Vector2i = proposal.get("to_origin", actor.origin)
	actor.origin = to_origin
	actor.moves_used_this_turn += 1
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.ENTITY_MOVED
	ev.actor_id = actor.id
	ev.from_origin = from_origin
	ev.to_origin = to_origin
	events.append(ev)

	var intent: Dictionary = proposal.get("intent", {})
	var kind: String = intent.get("kind", "")
	if kind == "gather":
		var source: Entity = state.get_entity_by_id(intent.get("target_entity_id", -1))
		if source != null and GatherSystem._is_adjacent_to(state, actor, source):
			actor.gather_state.phase = GatherState.Phase.GATHERING
	elif (
		kind == "move"
		and intent.get("exact_origin", true)
		and to_origin == intent.get("target_origin", to_origin)
	):
		var complete_ev := ResolverEvent.new()
		complete_ev.type = ResolverEvent.Type.MOVE_COMPLETED
		complete_ev.actor_id = actor.id
		complete_ev.from_origin = to_origin
		complete_ev.to_origin = to_origin
		events.append(complete_ev)
	elif kind == "construction":
		var building: Entity = state.get_entity_by_id(intent.get("target_entity_id", -1))
		if building == null or building.current_hp <= 0 or not building.is_constructing:
			actor.locked_to_building_id = -1
	elif kind == "pending_construction":
		ConstructionSystem.try_start_pending_build(state, actor, registry, events)


static func _action_at(per_entity: Dictionary, entity_id: int, tick: int) -> EntityOrder:
	if not per_entity.has(entity_id):
		return null
	var queue: Array = per_entity[entity_id]
	if tick < 0 or tick >= queue.size():
		return null
	return queue[tick]


static func _can_spend_movement(actor: Entity, movement_budget: int) -> bool:
	return movement_budget > 0 and actor.moves_used_this_turn < movement_budget


static func _count_profile(profile: Variant, label: String, amount: int = 1) -> void:
	if profile != null and profile.has_method("count"):
		profile.count(label, amount)


static func _is_spatial_blocker(entity: Entity, registry: EntityRegistry) -> bool:
	return _PATHFINDING._is_spatial_blocker(entity, registry)


static func _proposal_id_less(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("entity_id", -1)) < int(b.get("entity_id", -1))


static func _target_tile_for_order(
	state: MatchState, actor: Entity, order: EntityOrder
) -> Vector2i:
	return _move_goal_for_order(state, actor, order).get("target_origin", order.target_tile)


# Try to advance one tile toward `target_tile`. Returns true on success.
# Tries the diagonal step first; on collision falls back to axis-aligned.
static func step_toward(
	state: MatchState, actor: Entity, target_tile: Vector2i, events: Array[ResolverEvent]
) -> bool:
	if actor.origin == target_tile:
		return false  # Already there.

	var dx := signi(target_tile.x - actor.origin.x)
	var dy := signi(target_tile.y - actor.origin.y)

	# Candidate steps in priority order: diagonal, then x-axis, then y-axis.
	# Each is a delta from current origin.
	var candidates: Array[Vector2i] = []
	if dx != 0 and dy != 0:
		candidates.append(Vector2i(dx, dy))
	if dx != 0:
		candidates.append(Vector2i(dx, 0))
	if dy != 0:
		candidates.append(Vector2i(0, dy))

	for delta in candidates:
		var new_origin := actor.origin + delta
		if state.tile_grid.move(actor.id, new_origin):
			var ev := ResolverEvent.new()
			ev.type = ResolverEvent.Type.ENTITY_MOVED
			ev.actor_id = actor.id
			ev.from_origin = actor.origin
			ev.to_origin = new_origin
			actor.origin = new_origin
			events.append(ev)
			return true

	return false


static func movement_speed_for_entity(actor: Entity, registry: EntityRegistry) -> int:
	if actor == null or registry == null:
		return 0
	var def: EntityDef = registry.get_by_id(actor.current_def_id)
	if def == null or def.movement == null:
		return 0
	var speed: float = float(def.movement.speed_tiles_per_turn)
	for buff in actor.active_buffs:
		if buff != null:
			speed *= buff.speed_mult
	return max(0, int(round(speed)))


static func _attack_range_for_entity(actor: Entity, registry: EntityRegistry) -> int:
	if actor == null or registry == null:
		return 0
	var def: EntityDef = registry.get_by_id(actor.current_def_id)
	if def == null or def.combat == null:
		return 0
	return def.combat.attack_range


static func _is_attack_targetable(actor: Entity, target: Entity, registry: EntityRegistry) -> bool:
	if actor == null or target == null or registry == null:
		return false
	if target.current_hp <= 0:
		return false
	if target.owner_player_id < 0 or target.owner_player_id == actor.owner_player_id:
		return false
	var def: EntityDef = registry.get_by_id(actor.current_def_id)
	if def == null or def.combat == null:
		return false
	return def.combat.target_layers.has(target.current_layer)


static func movement_budget_for_entity(
	actor: Entity, registry: EntityRegistry, fired_this_turn: bool, move_only: bool
) -> int:
	var speed: int = movement_speed_for_entity(actor, registry)
	if speed <= 0:
		return 0
	if move_only or not fired_this_turn:
		return speed
	var def: EntityDef = registry.get_by_id(actor.current_def_id) if registry != null else null
	var fraction: float = 0.5
	if def != null and def.movement != null:
		fraction = clampf(def.movement.post_shot_move_fraction, 0.0, 1.0)
	return max(0, int(floor(float(speed) * fraction)))
