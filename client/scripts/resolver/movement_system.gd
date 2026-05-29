class_name MovementSystem
extends RefCounted

# Movement system — resolves submitted MOVE and MOVE_ONLY orders.
#
# Per-tick semantics (called from Phase 3 of the resolver tick loop):
# - MOVE / MOVE_ONLY: advance one tile toward order.target_tile if the entity has
#   move budget remaining. Ignores enemies along the path.
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

	if step_toward(state, actor, order.target_tile, events):
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
	sorted_entities: Array[Entity]
) -> void:
	if state == null or state.tile_grid == null or registry == null:
		return
	var intents: Array[Dictionary] = _movement_intents(
		state, per_entity, tick, registry, fired_entity_ids, halted_entity_ids, sorted_entities
	)
	if intents.is_empty():
		return
	var passable_entity_ids: Dictionary = {}
	for intent in intents:
		var intent_entity_id: int = intent.get("entity_id", -1)
		if intent_entity_id >= 0:
			passable_entity_ids[intent_entity_id] = true

	var proposals: Array[Dictionary] = []
	for intent in intents:
		var actor: Entity = intent.get("actor") as Entity
		if actor == null:
			continue
		var target_origin: Vector2i = intent.get("target_origin", actor.origin)
		var options: Dictionary = {
			_PATHFINDING.OPTION_PASSABLE_ENTITY_IDS: passable_entity_ids,
			_PATHFINDING.OPTION_EXACT_ORIGIN: intent.get("exact_origin", true),
			_PATHFINDING.OPTION_GOAL_RANGE: intent.get("goal_range", 0),
		}
		if intent.has("goal_rect"):
			options[_PATHFINDING.OPTION_GOAL_RECT] = intent["goal_rect"]
		var path: Array[Vector2i] = _PATHFINDING.find_path(
			state, actor, target_origin, registry, options
		)
		if path.is_empty():
			continue
		var next_origin: Vector2i = path[0]
		if next_origin == actor.origin:
			continue
		var footprint: Vector2i = _PATHFINDING.entity_footprint(state, actor, registry)
		(
			proposals
			. append(
				{
					"entity_id": actor.id,
					"actor": actor,
					"from_origin": actor.origin,
					"to_origin": next_origin,
					"target_rect": Rect2i(next_origin, footprint),
					"layer": _PATHFINDING.layer_for_entity(actor, registry),
					"path_distance": path.size(),
					"intent": intent,
				}
			)
		)
	if proposals.is_empty():
		return

	var winners: Array[Dictionary] = _winning_proposals(state, proposals, registry, events)
	if winners.is_empty():
		return
	var moves: Dictionary = {}
	for proposal in winners:
		moves[proposal.get("entity_id", -1)] = proposal.get("to_origin", Vector2i.ZERO)
	if not state.tile_grid.move_batch(moves, true):
		return
	winners.sort_custom(_proposal_id_less)
	for proposal in winners:
		_commit_proposal(state, proposal, events)


# ---------- Internals ----------


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
	sorted_entities: Array[Entity]
) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	var source_assignments: Dictionary[int, Array] = GatherSystem._source_assignments_by_source(
		state, registry
	)
	for actor in sorted_entities:
		if actor == null or actor.current_hp <= 0:
			continue
		if _ABILITY_SYSTEM.is_casting(actor):
			continue
		var order: EntityOrder = _action_at(per_entity, actor.id, tick)
		var explicit_intent: Dictionary = _explicit_move_intent(
			actor, order, registry, fired_entity_ids, halted_entity_ids
		)
		if not explicit_intent.is_empty():
			intents.append(explicit_intent)
			continue
		if order != null:
			continue
		var gather_intent: Dictionary = _gather_move_intent(
			state, actor, registry, source_assignments
		)
		if not gather_intent.is_empty():
			intents.append(gather_intent)
			continue
		var construction_intent: Dictionary = _construction_move_intent(state, actor, registry)
		if not construction_intent.is_empty():
			intents.append(construction_intent)
	return intents


static func _explicit_move_intent(
	actor: Entity,
	order: EntityOrder,
	registry: EntityRegistry,
	fired_entity_ids: Dictionary,
	halted_entity_ids: Dictionary
) -> Dictionary:
	if order == null:
		return {}
	if order.type != EntityOrder.Type.MOVE and order.type != EntityOrder.Type.MOVE_ONLY:
		return {}
	if order.type == EntityOrder.Type.MOVE and halted_entity_ids.has(actor.id):
		return {}
	var move_only: bool = order.type == EntityOrder.Type.MOVE_ONLY
	var budget: int = movement_budget_for_entity(
		actor, registry, fired_entity_ids.has(actor.id), move_only
	)
	if not _can_spend_movement(actor, budget):
		return {}
	if actor.origin == order.target_tile:
		return {}
	return {
		"kind": "move",
		"entity_id": actor.id,
		"actor": actor,
		"target_origin": order.target_tile,
		"exact_origin": true,
		"goal_range": 0,
		"movement_budget": budget,
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
		GatherSystem._clear_gather_assignment(actor)
		return {}
	if not GatherSystem._is_worker_within_source_cap(source_assignments, registry, actor, source):
		GatherSystem._clear_gather_assignment(actor)
		return {}
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
	state: MatchState, actor: Entity, registry: EntityRegistry
) -> Dictionary:
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
		for entity_id in remaining.keys():
			if blocked.has(entity_id):
				continue
			var proposal: Dictionary = remaining[entity_id]
			if _target_blocked_by_non_mover(state, proposal, registry, moving_ids):
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


static func _target_blocked_by_non_mover(
	state: MatchState, proposal: Dictionary, registry: EntityRegistry, moving_ids: Dictionary
) -> bool:
	var actor: Entity = proposal.get("actor") as Entity
	if actor == null:
		return true
	var target_rect: Rect2i = proposal.get("target_rect", Rect2i())
	var actor_layer: String = _PATHFINDING.layer_for_entity(actor, registry)
	for entity in state.entities_sorted_by_id():
		if entity == null or entity.id == actor.id:
			continue
		if moving_ids.has(entity.id):
			continue
		if not _is_spatial_blocker(entity, registry):
			continue
		if _PATHFINDING.layer_for_entity(entity, registry) != actor_layer:
			continue
		var other_rect: Rect2i = state.tile_grid.entity_rect(entity.id)
		if other_rect.size.x <= 0 or other_rect.size.y <= 0:
			continue
		if other_rect.intersects(target_rect):
			return true
	return false


static func _commit_proposal(
	state: MatchState, proposal: Dictionary, events: Array[ResolverEvent]
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


static func _action_at(per_entity: Dictionary, entity_id: int, tick: int) -> EntityOrder:
	if not per_entity.has(entity_id):
		return null
	var queue: Array = per_entity[entity_id]
	if tick < 0 or tick >= queue.size():
		return null
	return queue[tick]


static func _can_spend_movement(actor: Entity, movement_budget: int) -> bool:
	return movement_budget > 0 and actor.moves_used_this_turn < movement_budget


static func _is_spatial_blocker(entity: Entity, registry: EntityRegistry) -> bool:
	return _PATHFINDING._is_spatial_blocker(entity, registry)


static func _proposal_id_less(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("entity_id", -1)) < int(b.get("entity_id", -1))


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
