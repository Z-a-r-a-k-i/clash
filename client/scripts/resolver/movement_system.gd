class_name MovementSystem
extends RefCounted

# Movement system — resolves submitted MOVE and ATTACK_MOVE orders.
#
# Per-tick semantics (called from Phase 3 of the resolver tick loop):
# - MOVE / ATTACK_MOVE: advance one tile toward order.target_tile if the entity has
#   move budget remaining. Ignores enemies along the path.
#
# Per-turn budget: `def.movement.speed_tiles_per_turn` orthogonal steps
# per turn, tracked in octile COST units on Entity.moves_used_this_turn
# (orthogonal step = 2, diagonal = 3, budget = speed * 2; reset at
# end-of-turn). Diagonals therefore cover ~1.41x distance for 1.5x cost
# instead of being free extra distance.
#
const _ABILITY_SYSTEM := preload("res://scripts/resolver/ability_system.gd")
const _MECHANICS_SYSTEM := preload("res://scripts/resolver/mechanics_system.gd")
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
	if not _can_spend_movement(actor, movement_speed):
		return

	var target_tile: Vector2i = _target_tile_for_order(state, actor, order)
	var from_origin: Vector2i = actor.origin
	if step_toward(state, actor, target_tile, events):
		actor.moves_used_this_turn += _PATHFINDING.step_cost(from_origin, actor.origin)


static func resolve_movement_substep(
	state: MatchState,
	per_entity: Dictionary,
	tick: int,
	registry: EntityRegistry,
	_tunables: Tunables,
	events: Array[ResolverEvent],
	fired_before_movement_entity_ids: Dictionary,
	halted_entity_ids: Dictionary,
	sorted_entities: Array[Entity],
	path_cache: Variant = null,
	profile: Variant = null,
	context: Variant = null
) -> bool:
	if state == null or state.tile_grid == null or registry == null:
		return false
	var active_path_cache: Dictionary = path_cache if path_cache is Dictionary else {}
	var profile_mark: int = profile.mark() if profile != null else 0
	var intents: Array[Dictionary] = _movement_intents(
		state,
		per_entity,
		tick,
		registry,
		fired_before_movement_entity_ids,
		halted_entity_ids,
		sorted_entities,
		events,
		context
	)
	if profile != null:
		profile.add("movement.intents_build", profile_mark)
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
	if context is ResolveContext:
		# Stopped movers become hard blockers for everyone else; a changed
		# mover set therefore invalidates cached flow fields.
		context.note_movers(passable_entity_ids)

	# A flow field costs one map-wide BFS, so it only beats per-unit A*
	# when several movers share the same goal (clumped move orders, a
	# mineral line, a construction site). Count goal keys first.
	var flow_goal_counts: Dictionary = {}
	if context is ResolveContext:
		for intent in intents:
			var key: String = _intent_flow_key(state, intent, registry)
			if key != "":
				intent["_flow_key"] = key
				flow_goal_counts[key] = int(flow_goal_counts.get(key, 0)) + 1

	var proposals: Array[Dictionary] = []
	var completed_at_origin := false
	var occupancy_blockers_by_layer: Dictionary = {}
	var planning_passable_by_owner: Dictionary = {}
	for intent in intents:
		var actor: Entity = intent.get("actor") as Entity
		if actor == null:
			continue
		var target_origin: Vector2i = intent.get("target_origin", actor.origin)
		var actor_layer: String = _PATHFINDING.layer_for_entity(actor, registry)
		var footprint: Vector2i = _PATHFINDING.entity_footprint(state, actor, registry)
		# Friendly pass-through (plan m1/06 wave 3): planning treats the
		# actor's own 1x1 units as passable (movers of any owner already
		# are); enemies, buildings, and multi-tile movers keep hard
		# blockers (their sidesteps are too coarse to recover from a
		# blocked plan). The conflict loop still prevents two units
		# ENDING on the same tile.
		var planning_passable: Dictionary = passable_entity_ids
		var blockers_key: String = actor_layer
		if context is ResolveContext and footprint == Vector2i.ONE:
			blockers_key = "%s|%d" % [actor_layer, actor.owner_player_id]
			if not planning_passable_by_owner.has(actor.owner_player_id):
				var merged: Dictionary = passable_entity_ids.duplicate()
				for ally_id in context.allied_unit_ids(actor.owner_player_id):
					merged[ally_id] = true
				planning_passable_by_owner[actor.owner_player_id] = merged
			planning_passable = planning_passable_by_owner[actor.owner_player_id]
		if not occupancy_blockers_by_layer.has(blockers_key):
			if context is ResolveContext:
				occupancy_blockers_by_layer[blockers_key] = {
					"tiles": context.blocker_tiles(actor_layer),
					"passable": planning_passable,
				}
			else:
				occupancy_blockers_by_layer[blockers_key] = _PATHFINDING._occupancy_blockers(
					state, null, registry, actor_layer, passable_entity_ids, {}
				)
		var movement: MovementDef = _PATHFINDING.movement_def_for_entity(actor, registry)
		if movement == null:
			continue
		var options: Dictionary = {
			_PATHFINDING.OPTION_MOVER_IDS: passable_entity_ids,
			_PATHFINDING.OPTION_PASSABLE_ENTITY_IDS: planning_passable,
			_PATHFINDING.OPTION_EXACT_ORIGIN: intent.get("exact_origin", true),
			_PATHFINDING.OPTION_GOAL_RANGE: intent.get("goal_range", 0),
			_PATHFINDING.OPTION_OCCUPANCY_BLOCKERS: occupancy_blockers_by_layer[blockers_key],
			_PATHFINDING.OPTION_COMPLETE_BLOCKED_AT_CURRENT:
			intent.get("complete_blocked_at_current", false),
			_PATHFINDING.OPTION_PROFILE: profile,
		}
		if intent.has("goal_rect"):
			options[_PATHFINDING.OPTION_GOAL_RECT] = intent["goal_rect"]
		var field: Dictionary = {}
		var step: Dictionary = {}
		var use_flow_field: bool = (
			context is ResolveContext
			and footprint == Vector2i.ONE
			and int(flow_goal_counts.get(intent.get("_flow_key", ""), 0)) >= 2
		)
		if profile != null:
			profile_mark = profile.mark()
		if use_flow_field:
			var flow: Dictionary = _flow_next_step(
				context,
				state,
				actor,
				actor_layer,
				target_origin,
				footprint,
				movement,
				options,
				intent,
				active_path_cache,
				profile,
				registry
			)
			step = flow.get("step", {})
			field = flow.get("field", {})
		else:
			step = _cached_next_step(
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
		if profile != null:
			profile.add("movement.step_select", profile_mark)
		if step.is_empty():
			continue
		if step.get("completed_at_origin", false):
			_emit_completed_at_origin(actor, intent, events)
			completed_at_origin = true
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
					# Sidestep candidates are computed lazily on the first
					# conflict loss (most proposals never need them).
					"candidate_origins": [] as Array[Vector2i],
					"candidate_index": 0,
					"candidates_computed": false,
					"state": state,
					"target_origin": target_origin,
					"movement": movement,
					"options": options,
					"field": field,
					"footprint": footprint,
					"intent": intent,
				}
			)
		)
	if proposals.is_empty():
		return completed_at_origin
	_count_profile(profile, "movement.proposals", proposals.size())

	if profile != null:
		profile_mark = profile.mark()
	var winners: Array[Dictionary] = _winning_proposals(state, proposals, registry, events, context)
	if profile != null:
		profile.add("movement.winning_proposals", profile_mark)
	if winners.is_empty():
		return false
	winners = _drop_same_layer_overlapping_winners(winners)
	if winners.is_empty():
		return false
	_count_profile(profile, "movement.winners", winners.size())
	var moves: Dictionary = {}
	for proposal in winners:
		moves[proposal.get("entity_id", -1)] = proposal.get("to_origin", Vector2i.ZERO)
	# allow_overlaps=true is required because different layers legitimately
	# share tiles (flying over ground); same-layer disjointness is enforced
	# by the conflict loop plus the guard above.
	if not state.tile_grid.move_batch(moves, true):
		return false
	winners.sort_custom(_proposal_id_less)
	for proposal in winners:
		_commit_proposal(state, proposal, registry, events, context)
	return true


# Last-line corruption guard: the conflict loop guarantees same-layer
# winners have disjoint target rects, and move_batch(allow_overlaps=true)
# performs no clearance checks of its own. If an upstream bug ever produces
# overlapping same-layer winners, drop the higher-id ones with a warning
# instead of silently corrupting grid occupancy.
static func _drop_same_layer_overlapping_winners(winners: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var claimed_by_layer: Dictionary = {}
	for proposal in winners:
		var layer: String = proposal.get("layer", "ground")
		if not claimed_by_layer.has(layer):
			claimed_by_layer[layer] = {}
		var claimed: Dictionary = claimed_by_layer[layer]
		var target_rect: Rect2i = proposal.get("target_rect", Rect2i())
		var overlaps := false
		for x in range(target_rect.position.x, target_rect.position.x + target_rect.size.x):
			for y in range(target_rect.position.y, target_rect.position.y + target_rect.size.y):
				if claimed.has(Vector2i(x, y)):
					overlaps = true
					break
			if overlaps:
				break
		if overlaps:
			push_warning(
				(
					"MovementSystem: dropped overlapping winner for entity %d at %s"
					% [int(proposal.get("entity_id", -1)), str(target_rect)]
				)
			)
			continue
		for x in range(target_rect.position.x, target_rect.position.x + target_rect.size.x):
			for y in range(target_rect.position.y, target_rect.position.y + target_rect.size.y):
				claimed[Vector2i(x, y)] = true
		out.append(proposal)
	return out


# Flow-field cache key for an intent, or "" when the actor can't use one
# (multi-tile footprint, no movement def).
static func _intent_flow_key(
	state: MatchState, intent: Dictionary, registry: EntityRegistry
) -> String:
	var actor: Entity = intent.get("actor") as Entity
	if actor == null:
		return ""
	if _PATHFINDING.entity_footprint(state, actor, registry) != Vector2i.ONE:
		return ""
	var movement: MovementDef = _PATHFINDING.movement_def_for_entity(actor, registry)
	if movement == null:
		return ""
	var target_origin: Vector2i = intent.get("target_origin", actor.origin)
	var exact_origin: bool = bool(intent.get("exact_origin", true))
	var goal_rect: Rect2i = intent.get("goal_rect", Rect2i(target_origin, Vector2i.ONE))
	var goal_range: int = int(intent.get("goal_range", 0))
	return (
		(_PATHFINDING.flow_field_key(
			_PATHFINDING.layer_for_entity(actor, registry),
			movement,
			target_origin,
			goal_rect,
			goal_range,
			exact_origin
		))
		+ ":o%d" % actor.owner_player_id
	)


# Flow-field step lookup for 1x1 movers. Returns {"step": .., "field": ..};
# an empty step means no move this substep. Falls back to a budgeted A*
# (negative-cached per tick) when the actor is disconnected from the goal
# region.
static func _flow_next_step(
	context: ResolveContext,
	state: MatchState,
	actor: Entity,
	actor_layer: String,
	target_origin: Vector2i,
	footprint: Vector2i,
	movement: MovementDef,
	options: Dictionary,
	intent: Dictionary,
	path_cache: Dictionary,
	profile: Variant,
	registry: EntityRegistry
) -> Dictionary:
	var grid: TileGrid = state.tile_grid
	var goal_rect: Rect2i = options.get(
		_PATHFINDING.OPTION_GOAL_RECT, Rect2i(target_origin, footprint)
	)
	var goal_range: int = options.get(_PATHFINDING.OPTION_GOAL_RANGE, 0)
	var exact_origin: bool = options.get(_PATHFINDING.OPTION_EXACT_ORIGIN, true)
	var complete_blocked_at_current: bool = options.get(
		_PATHFINDING.OPTION_COMPLETE_BLOCKED_AT_CURRENT, false
	)
	var blockers: Dictionary = options.get(_PATHFINDING.OPTION_OCCUPANCY_BLOCKERS, {})
	var blocked_tiles: Dictionary = blockers.get("tiles", {})
	var passable: Dictionary = blockers.get("passable", {})
	var start: Vector2i = actor.origin
	if _PATHFINDING._is_goal(start, footprint, target_origin, goal_rect, goal_range, exact_origin):
		return {}
	# Exact destination occupied by a non-mover and we're adjacent: the move
	# completes where the unit stands (same semantics as find_next_step).
	# Movers-only passability here: a stationary ALLY on the target tile
	# must complete the move, even though routing treats allies as
	# passable (friendly pass-through).
	var completion_passable: Dictionary = options.get(_PATHFINDING.OPTION_MOVER_IDS, passable)
	if (
		exact_origin
		and maxi(abs(start.x - target_origin.x), abs(start.y - target_origin.y)) <= 1
		and _PATHFINDING._tile_blocked(blocked_tiles, completion_passable, target_origin)
	):
		_count_profile(profile, "pathfinding.exact_blocked_adjacent_no_progress")
		if not complete_blocked_at_current:
			return {}
		return {
			"step":
			{
				"next_origin": start,
				"path_distance": 0,
				"completed_at_origin": true,
			}
		}
	var key: String = (
		_PATHFINDING.flow_field_key(
			actor_layer, movement, target_origin, goal_rect, goal_range, exact_origin
		)
		+ ":o%d" % actor.owner_player_id
	)
	var build_blockers: Dictionary = {
		"tiles": blocked_tiles,
		"passable": passable,
		"terrain_blocked": context.terrain_blocked_tiles(movement),
	}
	var field: Dictionary = context.flow_field(
		key,
		func() -> Dictionary:
			return _PATHFINDING.build_flow_field(
				grid, movement, build_blockers, target_origin, goal_rect, goal_range, exact_origin
			)
	)
	if not field.has(start):
		# Disconnected from the goal region. Run one budgeted A* toward the
		# best reachable tile, at most once per tick per (actor, goal).
		var no_progress_key: String = "%s#%d" % [key, actor.id]
		if context.is_no_progress_goal(no_progress_key):
			return {"field": field}
		var step: Dictionary = _cached_next_step(
			grid, actor, target_origin, footprint, movement, options, intent, path_cache
		)
		if step.is_empty():
			_count_profile(profile, "movement.path_cache_miss")
			step = _PATHFINDING.find_next_step(state, actor, target_origin, registry, options)
			_store_path_cache(actor, target_origin, intent, step, path_cache)
		else:
			_count_profile(profile, "movement.path_cache_hit")
		if step.is_empty() or step.get("next_origin", start) == start:
			context.mark_no_progress_goal(no_progress_key)
		return {"step": step, "field": field}
	var current_distance: int = field[start]
	var best: Vector2i = start
	var best_score: Array = []
	for delta in _PATHFINDING._NEIGHBORS:
		var next: Vector2i = start + delta
		if not field.has(next):
			continue
		if _PATHFINDING._diagonal_step_blocked(grid, start, delta, footprint, movement, blockers):
			continue
		if not _can_afford_step(actor, intent, start, next):
			continue
		var next_distance: int = field[next]
		if next_distance >= current_distance:
			continue
		var score: Array = [
			next_distance,
			_PATHFINDING._manhattan_distance(
				next, footprint, target_origin, goal_rect, goal_range, exact_origin
			),
			next.y,
			next.x,
		]
		if best_score.is_empty() or _score_less(score, best_score):
			best = next
			best_score = score
	if best == start:
		return {"field": field}
	return {
		"step": {"next_origin": best, "path_distance": current_distance},
		"field": field,
	}


static func _score_less(a: Array, b: Array) -> bool:
	for index in range(mini(a.size(), b.size())):
		if int(a[index]) != int(b[index]):
			return int(a[index]) < int(b[index])
	return false


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
	# Validate only the immediate next step. Later tiles can be blocked by
	# units that will have moved by the time we get there; re-validating the
	# whole tail every substep just forced constant full re-paths.
	if not _PATHFINDING._can_occupy_origin_with_blockers(
		grid, next_origin, footprint, movement, occupancy_blockers
	):
		path_cache.erase(actor.id)
		return {}
	if _PATHFINDING._diagonal_step_blocked(
		grid, actor.origin, next_origin - actor.origin, footprint, movement, occupancy_blockers
	):
		path_cache.erase(actor.id)
		return {}
	if not _can_afford_step(actor, intent, actor.origin, next_origin):
		# Keep the cache; the next turn's fresh budget can afford it.
		return {"next_origin": actor.origin, "path_distance": 0}
	cached["path"] = path
	path_cache[actor.id] = cached
	return {
		"next_origin": next_origin,
		"path_distance": _PATHFINDING.path_cost(actor.origin, path),
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
	fired_before_movement_entity_ids: Dictionary,
	halted_entity_ids: Dictionary,
	sorted_entities: Array[Entity],
	events: Array[ResolverEvent],
	context: Variant = null
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
			actor, order, registry, fired_before_movement_entity_ids, halted_entity_ids
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
			state, actor, registry, source_assignments, context
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
	actor: Entity,
	order: EntityOrder,
	registry: EntityRegistry,
	fired_before_movement_entity_ids: Dictionary,
	halted_entity_ids: Dictionary
) -> Dictionary:
	if order == null:
		return {}
	if order.type != EntityOrder.Type.MOVE and order.type != EntityOrder.Type.ATTACK_MOVE:
		return {}
	if order.type == EntityOrder.Type.ATTACK_MOVE and halted_entity_ids.has(actor.id):
		return {}
	var budget: int = movement_budget_for_entity(
		actor, registry, fired_before_movement_entity_ids.has(actor.id)
	)
	if not _can_spend_movement(actor, budget):
		return {}
	var goal: Dictionary = _goal_for_order(order)
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
		"complete_blocked_at_current": true,
	}
	if goal.has("goal_rect"):
		intent["goal_rect"] = goal["goal_rect"]
	return intent


static func _goal_for_order(order: EntityOrder) -> Dictionary:
	return _move_goal_for_order(order)


static func _move_goal_for_order(order: EntityOrder) -> Dictionary:
	var fallback: Dictionary = {
		"target_origin": order.target_tile,
		"exact_origin": true,
		"goal_range": 0,
	}
	return fallback


static func _gather_move_intent(
	state: MatchState,
	actor: Entity,
	registry: EntityRegistry,
	source_assignments: Dictionary[int, Array],
	context: Variant = null
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
		state, registry, actor, source, source_assignments, context
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
		"movement_budget": movement_speed_for_entity(actor, registry),
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
		if state.tile_grid.entity_rect(actor.id).intersects(pending_rect):
			# Standing inside the own footprint: walk out to the nearest
			# free ring tile before construction can start.
			var out_tile: Vector2i = ConstructionSystem.step_out_tile(state, actor, pending_rect)
			if out_tile == Vector2i(-1, -1):
				return {}
			return {
				"movement_budget": movement_speed_for_entity(actor, registry),
				"kind": "pending_construction",
				"entity_id": actor.id,
				"actor": actor,
				"target_origin": out_tile,
				"goal_range": 0,
				"exact_origin": true,
			}
		if ConstructionSystem._is_adjacent_to_rect(state, actor, pending_rect):
			ConstructionSystem.try_start_pending_build(state, actor, registry, events)
			return {}
		return {
			"movement_budget": movement_speed_for_entity(actor, registry),
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
		"movement_budget": movement_speed_for_entity(actor, registry),
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
	events: Array[ResolverEvent],
	context: Variant = null
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
		var complete_on_stop: Dictionary = conflict_result.get("complete_on_stop", {})
		var moving_ids: Dictionary = {}
		for entity_id in remaining.keys():
			if not blocked.has(entity_id):
				moving_ids[entity_id] = true
		var non_mover_blockers_by_layer: Dictionary = {}
		if not (context is ResolveContext):
			non_mover_blockers_by_layer = _non_mover_blockers_by_layer(state, registry, moving_ids)
		for entity_id in remaining.keys():
			if blocked.has(entity_id):
				continue
			var proposal: Dictionary = remaining[entity_id]
			var target_blocked: bool
			if context is ResolveContext:
				target_blocked = _target_blocked_by_non_mover_tiles(context, proposal, moving_ids)
			else:
				target_blocked = _target_blocked_by_non_mover(proposal, non_mover_blockers_by_layer)
			if target_blocked:
				blocked[entity_id] = true
		if not blocked.is_empty():
			var blocked_ids: Array[int] = []
			for entity_id in blocked.keys():
				blocked_ids.append(int(entity_id))
			blocked_ids.sort()
			for entity_id in blocked_ids:
				var proposal: Dictionary = remaining.get(entity_id, {})
				if complete_on_stop.has(entity_id):
					proposal["complete_after_move"] = true
				if _advance_proposal_to_next_candidate(proposal):
					continue
				if (
					complete_on_stop.has(entity_id)
					or bool(proposal.get("complete_after_move", false))
				):
					_emit_completed_at_stop(proposal, events)
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


static func _movement_candidate_origins(
	state: MatchState,
	actor: Entity,
	target_origin: Vector2i,
	footprint: Vector2i,
	movement: MovementDef,
	options: Dictionary,
	_intent: Dictionary,
	primary_origin: Vector2i,
	field: Dictionary = {}
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if actor == null or state == null or state.tile_grid == null or movement == null:
		return out
	out.append(primary_origin)
	if footprint != Vector2i.ONE:
		return out
	var occupancy_blockers: Dictionary = options.get(_PATHFINDING.OPTION_OCCUPANCY_BLOCKERS, {})
	var goal_rect: Rect2i = options.get(
		_PATHFINDING.OPTION_GOAL_RECT, Rect2i(target_origin, footprint)
	)
	var goal_range: int = int(options.get(_PATHFINDING.OPTION_GOAL_RANGE, 0))
	var exact_origin: bool = bool(options.get(_PATHFINDING.OPTION_EXACT_ORIGIN, true))
	var current_goal_distance: int = _candidate_goal_distance(
		actor.origin, footprint, target_origin, goal_rect, goal_range, exact_origin, field
	)
	var current_manhattan: int = _PATHFINDING._manhattan_distance(
		actor.origin, footprint, target_origin, goal_rect, goal_range, exact_origin
	)
	var candidates: Array[Dictionary] = []
	for y in range(actor.origin.y - 1, actor.origin.y + 2):
		for x in range(actor.origin.x - 1, actor.origin.x + 2):
			var candidate := Vector2i(x, y)
			if candidate == actor.origin or candidate == primary_origin:
				continue
			if not _PATHFINDING._can_occupy_origin_with_blockers(
				state.tile_grid, candidate, footprint, movement, occupancy_blockers
			):
				continue
			if _PATHFINDING._diagonal_step_blocked(
				state.tile_grid,
				actor.origin,
				candidate - actor.origin,
				footprint,
				movement,
				occupancy_blockers
			):
				continue
			if not _can_afford_step(actor, _intent, actor.origin, candidate):
				continue
			var goal_distance: int = _candidate_goal_distance(
				candidate, footprint, target_origin, goal_rect, goal_range, exact_origin, field
			)
			var manhattan: int = _PATHFINDING._manhattan_distance(
				candidate, footprint, target_origin, goal_rect, goal_range, exact_origin
			)
			if (
				goal_distance > current_goal_distance
				or (goal_distance == current_goal_distance and manhattan >= current_manhattan)
			):
				continue
			(
				candidates
				. append(
					{
						"origin": candidate,
						"goal_distance": goal_distance,
						"manhattan": manhattan,
						"primary_delta": _chebyshev_distance(candidate, primary_origin),
						"direction_delta":
						_direction_delta_score(actor.origin, candidate, target_origin),
						"y": candidate.y,
						"x": candidate.x,
					}
				)
			)
	candidates.sort_custom(_movement_candidate_less)
	for item in candidates:
		var candidate_origin: Vector2i = item.get("origin", primary_origin)
		if not out.has(candidate_origin):
			out.append(candidate_origin)
	return out


# Goal distance for sidestep candidates: true path distance from the flow
# field when one is available, otherwise the legacy chebyshev estimate.
# Field distances stop losers from "sidestepping" into tiles that look
# closer as the crow flies but are actually further along the real path.
static func _candidate_goal_distance(
	origin: Vector2i,
	footprint: Vector2i,
	target_origin: Vector2i,
	goal_rect: Rect2i,
	goal_range: int,
	exact_origin: bool,
	field: Dictionary
) -> int:
	if not field.is_empty():
		# Missing from the field = disconnected from the goal region; never
		# treat it as closer than a connected tile.
		return field.get(origin, 1 << 30)
	return _PATHFINDING._goal_distance(
		origin, footprint, target_origin, goal_rect, goal_range, exact_origin
	)


static func _advance_proposal_to_next_candidate(proposal: Dictionary) -> bool:
	if proposal.is_empty():
		return false
	if not bool(proposal.get("candidates_computed", true)):
		proposal["candidates_computed"] = true
		proposal["candidate_origins"] = _movement_candidate_origins(
			proposal.get("state") as MatchState,
			proposal.get("actor") as Entity,
			proposal.get("target_origin", Vector2i.ZERO),
			proposal.get("footprint", Vector2i.ONE),
			proposal.get("movement") as MovementDef,
			proposal.get("options", {}),
			proposal.get("intent", {}),
			proposal.get("to_origin", Vector2i.ZERO),
			proposal.get("field", {})
		)
	var candidate_origins: Array = proposal.get("candidate_origins", [])
	var next_index: int = int(proposal.get("candidate_index", 0)) + 1
	if next_index < 0 or next_index >= candidate_origins.size():
		return false
	var next_origin: Vector2i = candidate_origins[next_index]
	var footprint: Vector2i = proposal.get("footprint", Vector2i.ONE)
	proposal["candidate_index"] = next_index
	proposal["to_origin"] = next_origin
	proposal["target_rect"] = Rect2i(next_origin, footprint)
	return true


static func _movement_candidate_less(a: Dictionary, b: Dictionary) -> bool:
	for key in ["goal_distance", "manhattan", "primary_delta", "direction_delta", "y", "x"]:
		var a_value: int = int(a.get(key, 0))
		var b_value: int = int(b.get(key, 0))
		if a_value != b_value:
			return a_value < b_value
	return false


static func _direction_delta_score(
	from_origin: Vector2i, candidate_origin: Vector2i, target_origin: Vector2i
) -> int:
	var wanted := Vector2i(
		signi(target_origin.x - from_origin.x), signi(target_origin.y - from_origin.y)
	)
	var actual := candidate_origin - from_origin
	return abs(actual.x - wanted.x) + abs(actual.y - wanted.y)


static func _chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(abs(a.x - b.x), abs(a.y - b.y))


static func _target_conflict_result(remaining: Dictionary) -> Dictionary:
	var losers: Dictionary = {}
	var complete_on_stop: Dictionary = {}
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
			_process_equal_distance_minima(min_ids, component, remaining, losers, complete_on_stop)
	return {"losers": losers, "complete_on_stop": complete_on_stop}


static func _process_equal_distance_minima(
	min_ids: Array[int],
	component: Array[int],
	remaining: Dictionary,
	losers: Dictionary,
	complete_on_stop: Dictionary
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
		if _is_final_exact_target_tie(group, remaining):
			for entity_id in group:
				losers[entity_id] = true
				complete_on_stop[entity_id] = true
			_mark_direct_conflict_losers(group, component, remaining, losers)
			continue
		var winner_ids: Array[int] = _non_conflicting_min_winners(group, remaining)
		if winner_ids.is_empty():
			continue
		for entity_id in group:
			if not winner_ids.has(entity_id):
				losers[entity_id] = true
		_mark_direct_conflict_losers(winner_ids, component, remaining, losers)


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


static func _is_final_exact_target_tie(tied_ids: Array[int], remaining: Dictionary) -> bool:
	if tied_ids.size() <= 1:
		return false
	var target_origin: Vector2i = Vector2i.ZERO
	var has_target: bool = false
	for entity_id in tied_ids:
		var proposal: Dictionary = remaining.get(entity_id, {})
		var intent: Dictionary = proposal.get("intent", {})
		if intent.get("kind", "") != "move":
			return false
		if not intent.get("exact_origin", true) or int(intent.get("goal_range", 0)) != 0:
			return false
		var intent_target: Vector2i = intent.get("target_origin", Vector2i.ZERO)
		if proposal.get("to_origin", Vector2i.ZERO) != intent_target:
			return false
		if not has_target:
			target_origin = intent_target
			has_target = true
		elif intent_target != target_origin:
			return false
	return has_target


static func _emit_completed_at_origin(
	actor: Entity, intent: Dictionary, events: Array[ResolverEvent]
) -> void:
	if actor == null:
		return
	var movement_budget: int = cost_budget(int(intent.get("movement_budget", 0)))
	actor.moves_used_this_turn = max(actor.moves_used_this_turn, movement_budget)
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.MOVE_COMPLETED
	ev.actor_id = actor.id
	ev.from_origin = actor.origin
	ev.to_origin = actor.origin
	events.append(ev)


static func _emit_completed_at_stop(proposal: Dictionary, events: Array[ResolverEvent]) -> void:
	var actor: Entity = proposal.get("actor") as Entity
	if actor == null:
		return
	var intent: Dictionary = proposal.get("intent", {})
	var movement_budget: int = cost_budget(int(intent.get("movement_budget", 0)))
	actor.moves_used_this_turn = max(actor.moves_used_this_turn, movement_budget)
	var stop_origin: Vector2i = proposal.get("from_origin", actor.origin)
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.MOVE_COMPLETED
	ev.actor_id = actor.id
	ev.from_origin = stop_origin
	ev.to_origin = stop_origin
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


# ResolveContext flavour of _target_blocked_by_non_mover: one shared
# blocker-tile map per layer, filtered through the currently-moving ids.
static func _target_blocked_by_non_mover_tiles(
	context: ResolveContext, proposal: Dictionary, moving_ids: Dictionary
) -> bool:
	var target_rect: Rect2i = proposal.get("target_rect", Rect2i())
	var actor_layer: String = proposal.get("layer", "ground")
	var tiles: Dictionary = context.blocker_tiles(actor_layer)
	if tiles.is_empty():
		return false
	for x in range(target_rect.position.x, target_rect.position.x + target_rect.size.x):
		for y in range(target_rect.position.y, target_rect.position.y + target_rect.size.y):
			if _PATHFINDING._tile_blocked(tiles, moving_ids, Vector2i(x, y)):
				return true
	return false


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
	state: MatchState,
	proposal: Dictionary,
	registry: EntityRegistry,
	events: Array[ResolverEvent],
	context: Variant = null
) -> void:
	var actor: Entity = proposal.get("actor") as Entity
	if actor == null:
		return
	var from_origin: Vector2i = proposal.get("from_origin", actor.origin)
	var to_origin: Vector2i = proposal.get("to_origin", actor.origin)
	actor.origin = to_origin
	actor.moves_used_this_turn += _PATHFINDING.step_cost(from_origin, to_origin)
	if context is ResolveContext:
		var footprint: Vector2i = proposal.get("footprint", Vector2i.ONE)
		context.on_entity_moved(
			actor,
			proposal.get("layer", "ground"),
			Rect2i(from_origin, footprint),
			Rect2i(to_origin, footprint)
		)
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
		_emit_move_completed(actor, to_origin, to_origin, events)
	elif kind == "move" and bool(proposal.get("complete_after_move", false)):
		var movement_budget: int = cost_budget(int(intent.get("movement_budget", 0)))
		actor.moves_used_this_turn = max(actor.moves_used_this_turn, movement_budget)
		_emit_move_completed(actor, to_origin, to_origin, events)
	elif kind == "construction":
		var building: Entity = state.get_entity_by_id(intent.get("target_entity_id", -1))
		if building == null or building.current_hp <= 0 or not building.is_constructing:
			actor.locked_to_building_id = -1
	elif kind == "pending_construction":
		ConstructionSystem.try_start_pending_build(state, actor, registry, events)


static func _emit_move_completed(
	actor: Entity, from_origin: Vector2i, to_origin: Vector2i, events: Array[ResolverEvent]
) -> void:
	if actor == null:
		return
	var complete_ev := ResolverEvent.new()
	complete_ev.type = ResolverEvent.Type.MOVE_COMPLETED
	complete_ev.actor_id = actor.id
	complete_ev.from_origin = from_origin
	complete_ev.to_origin = to_origin
	events.append(complete_ev)


static func _action_at(per_entity: Dictionary, entity_id: int, tick: int) -> EntityOrder:
	if not per_entity.has(entity_id):
		return null
	var queue: Array = per_entity[entity_id]
	if tick < 0 or tick >= queue.size():
		return null
	return queue[tick]


static func _can_spend_movement(actor: Entity, movement_budget_tiles: int) -> bool:
	# Affordability of the cheapest (orthogonal) step against the cost-unit
	# budget; per-step diagonal affordability is checked at step selection.
	return (
		movement_budget_tiles > 0
		and (
			actor.moves_used_this_turn + _PATHFINDING.STEP_COST_ORTHOGONAL
			<= cost_budget(movement_budget_tiles)
		)
	)


static func cost_budget(movement_budget_tiles: int) -> int:
	return movement_budget_tiles * _PATHFINDING.STEP_COST_ORTHOGONAL


# Remaining cost-unit budget for the actor of `intent` this turn.
static func _remaining_step_budget(actor: Entity, intent: Dictionary) -> int:
	var budget_tiles: int = int(intent.get("movement_budget", 0))
	return cost_budget(budget_tiles) - actor.moves_used_this_turn


# A step is affordable while at least one orthogonal step of budget
# remains; a final diagonal may overdraw by 1 cost unit (not carried into
# the next turn). This keeps single-step-per-turn behavior intuitive for
# slow units while still charging diagonals 1.5x across a turn.
static func _can_afford_step(
	actor: Entity, intent: Dictionary, _from: Vector2i, _to: Vector2i
) -> bool:
	return _remaining_step_budget(actor, intent) >= _PATHFINDING.STEP_COST_ORTHOGONAL


static func _count_profile(profile: Variant, label: String, amount: int = 1) -> void:
	if profile != null and profile.has_method("count"):
		profile.count(label, amount)


static func _is_spatial_blocker(entity: Entity, registry: EntityRegistry) -> bool:
	return _PATHFINDING._is_spatial_blocker(entity, registry)


static func _proposal_id_less(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("entity_id", -1)) < int(b.get("entity_id", -1))


static func _target_tile_for_order(
	_state: MatchState, _actor: Entity, order: EntityOrder
) -> Vector2i:
	return _move_goal_for_order(order).get("target_origin", order.target_tile)


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
	return _MECHANICS_SYSTEM.movement_speed_for_entity(actor, registry)


static func movement_budget_for_entity(
	actor: Entity, registry: EntityRegistry, fired_before_movement: bool
) -> int:
	return _MECHANICS_SYSTEM.movement_budget_for_entity(actor, registry, fired_before_movement)
