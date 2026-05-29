class_name ConstructionSystem
extends RefCounted

# Drives the BUILD lifecycle for plan node 05.
#
# BUILD has a different shape from TRAIN/RESEARCH: cost is paid up front
# at distribution (a single worker-to-tile commitment, not a queue), and
# progress is tracked on the building entity itself rather than on a
# producer's ProductionState.queue.
#
# Phase 2 hook (`advance_move_phase`): pending build workers step toward
# the requested site until they can start construction. Once a building
# entity exists, workers with locked_to_building_id step toward that
# building's rect. Both mirror how gather_system walks workers toward a
# source. The worker stops on adjacency.
#
# EOT hook (`finalize_completed`): for each entity with `is_constructing`,
# checks worker presence and adjacency. If the worker is dead/missing or
# not adjacent, pause (set construction_worker_id = -1, emit BUILD_PAUSED).
# Otherwise decrement `construction_turns_remaining`; on hit-zero, finalize
# (apply pop_provides, free worker, emit BUILD_COMPLETED).
#
# This system is invoked from EndOfTurnSystem BEFORE ProductionSystem so a
# building completing this turn can install its first queue item the same
# turn (try_fill skips entities with is_constructing).


# Phase 2 hook — called per tick, alongside MovementSystem.resolve_move
# and GatherSystem.advance_move_phase.
static func advance_move_phase(
	state: MatchState,
	per_entity: Dictionary,
	tick: int,
	registry: EntityRegistry,
	_tunables: Tunables,
	events: Array[ResolverEvent]
) -> void:
	if state.tile_grid == null:
		return
	for actor in state.entities_sorted_by_id():
		if actor.current_hp <= 0:
			if has_pending_build(actor):
				cancel_pending_build(state, actor, registry, events)
			continue
		if has_pending_build(actor):
			_advance_pending_build_worker(state, per_entity, tick, actor, registry, events)
			continue
		if actor.locked_to_building_id < 0:
			continue
		# Fresh per-tick orders take priority over auto-step. Locked
		# workers reject new orders at distribution, but a CANCEL
		# distributed at this tick could have just freed the worker
		# (see _state_helpers cancel-via-worker path).
		if MovementSystem.has_fresh_order_at(per_entity, actor.id, tick):
			continue
		var building: Entity = state.get_entity_by_id(actor.locked_to_building_id)
		if building == null or building.current_hp <= 0:
			# Building gone — release the worker.
			actor.locked_to_building_id = -1
			continue
		if not building.is_constructing:
			# Already complete; release the worker.
			actor.locked_to_building_id = -1
			continue
		if _is_adjacent_to(state, actor, building):
			continue  # arrived; just hold position
		if not _can_step(actor, registry):
			continue
		var building_rect: Rect2i = state.tile_grid.entity_rect(building.id)
		if building_rect.size == Vector2i.ZERO:
			continue
		if MovementSystem.step_toward(state, actor, building_rect.position, events):
			actor.moves_used_this_turn += 1


# EOT hook — runs before ProductionSystem.advance_queues so a freshly
# completed building can install its first queue item this turn.
static func finalize_completed(
	state: MatchState, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	for entity in state.entities_sorted_by_id():
		if entity.current_hp <= 0:
			continue
		if not entity.is_constructing:
			continue
		var worker_id: int = entity.construction_worker_id
		var worker: Entity = state.get_entity_by_id(worker_id) if worker_id >= 0 else null
		# Three cases:
		#   1. Worker missing or dead → unlink and pause permanently
		#      until a resume order arrives.
		#   2. Worker alive but not adjacent (walking) → pause this
		#      turn but KEEP the link so finalize resumes once the
		#      worker arrives. Without this, a long walk turns into a
		#      "stuck forever" pause that requires a manual re-issue.
		#   3. Worker alive + adjacent → tick progress and finalize on
		#      hit-zero.
		if worker == null or worker.current_hp <= 0:
			if worker_id >= 0:
				entity.construction_worker_id = -1
				var ev: ResolverEvent = ResolverEvent.new()
				ev.type = ResolverEvent.Type.BUILD_PAUSED
				ev.actor_id = entity.id
				events.append(ev)
			continue
		if not _is_adjacent_to(state, worker, entity):
			# Worker still en-route. No progress this turn, but the link
			# is preserved — advance_move_phase keeps stepping them, and
			# next EOT we'll re-evaluate. No event spam every turn while
			# walking; BUILD_PROGRESSED simply doesn't fire.
			continue
		# Tick.
		entity.construction_turns_remaining -= 1
		var prog: ResolverEvent = ResolverEvent.new()
		prog.type = ResolverEvent.Type.BUILD_PROGRESSED
		prog.actor_id = entity.id
		prog.amount = entity.construction_turns_remaining
		events.append(prog)
		if entity.construction_turns_remaining <= 0:
			_finalize(state, registry, entity, worker, events)


static func has_pending_build(worker: Entity) -> bool:
	return worker != null and worker.pending_build_def_id != ""


static func try_start_pending_build(
	state: MatchState, worker: Entity, registry: EntityRegistry, events: Array[ResolverEvent]
) -> bool:
	if not has_pending_build(worker):
		return false
	var layout: Dictionary = _pending_build_layout(state, worker, registry)
	if not layout.get("valid", false):
		var reason: String = layout.get("reason", "bad_build_target")
		_reject_pending_build(state, worker, registry, reason, events)
		return false
	var rect: Rect2i = layout["rect"]
	if not _is_adjacent_to_rect(state, worker, rect):
		return false
	var def: EntityDef = layout["def"]
	var overlap_target_id: int = layout.get("overlap_target_id", -1)
	var building := Entity.new()
	building.id = state.allocate_entity_id()
	building.def_id = def.id
	building.current_def_id = def.id
	building.owner_player_id = worker.owner_player_id
	building.origin = rect.position
	building.current_layer = "ground"
	if def.health != null:
		building.current_hp = def.health.max_hp
	building.is_constructing = true
	building.construction_turns_remaining = def.construction.build_time_turns
	building.construction_worker_id = worker.id
	if def.production != null:
		building.production_state = ProductionState.new()
	state.entities.append(building)
	var placed: bool
	if overlap_target_id >= 0:
		placed = state.tile_grid.place_overlapping(building.id, rect, overlap_target_id)
	else:
		placed = state.tile_grid.place(building.id, rect)
	if not placed:
		state.entities.erase(building)
		_reject_pending_build(state, worker, registry, "tile_occupied", events)
		return false
	worker.locked_to_building_id = building.id
	_clear_pending_build(worker)
	_interrupt_gather_assignment(worker)
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.BUILD_STARTED
	ev.actor_id = worker.id
	ev.target_id = building.id
	ev.def_id = def.id
	events.append(ev)
	return true


static func cancel_pending_build(
	state: MatchState, worker: Entity, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	if not has_pending_build(worker):
		return
	var def_id: String = worker.pending_build_def_id
	_refund_pending_build_cost(state, worker, registry)
	_clear_pending_build(worker)
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.BUILD_CANCELLED
	ev.actor_id = worker.id
	ev.def_id = def_id
	events.append(ev)


# ---------- Internals ----------


static func _advance_pending_build_worker(
	state: MatchState,
	per_entity: Dictionary,
	tick: int,
	actor: Entity,
	registry: EntityRegistry,
	events: Array[ResolverEvent]
) -> void:
	# Fresh per-tick orders take priority over auto-step. Pending-build
	# workers reject new orders at distribution, but a CANCEL distributed
	# at this tick could have just freed the worker.
	if MovementSystem.has_fresh_order_at(per_entity, actor.id, tick):
		return
	if try_start_pending_build(state, actor, registry, events):
		return
	if not has_pending_build(actor):
		return
	if not _can_step(actor, registry):
		return
	var layout: Dictionary = _pending_build_layout(state, actor, registry)
	if not layout.get("valid", false):
		var reason: String = layout.get("reason", "bad_build_target")
		_reject_pending_build(state, actor, registry, reason, events)
		return
	var target_rect: Rect2i = layout["rect"]
	if MovementSystem.step_toward(state, actor, target_rect.position, events):
		actor.moves_used_this_turn += 1
		try_start_pending_build(state, actor, registry, events)


static func _pending_build_layout(
	state: MatchState, worker: Entity, registry: EntityRegistry
) -> Dictionary:
	var out: Dictionary = {
		"valid": false,
		"reason": "bad_build_target",
	}
	if state == null or state.tile_grid == null:
		out["reason"] = "off_grid"
		return out
	if registry == null:
		out["reason"] = "no_registry"
		return out
	var def: EntityDef = registry.get_by_id(worker.pending_build_def_id)
	if def == null or def.construction == null:
		out["reason"] = "bad_build_target"
		return out
	var footprint: Vector2i = def.footprint
	if footprint == Vector2i.ZERO:
		footprint = Vector2i.ONE
	var rect := Rect2i(worker.pending_build_target_tile, footprint)
	var overlap_target_id: int = -1
	var require_tag: String = def.construction.requires_target_tag
	if require_tag != "":
		overlap_target_id = worker.pending_build_target_entity_id
		if overlap_target_id < 0:
			overlap_target_id = _find_target_at_tile(
				state, registry, worker.pending_build_target_tile, require_tag
			)
		var target: Entity = state.get_entity_by_id(overlap_target_id)
		if target == null:
			out["reason"] = "missing_target_tag"
			return out
		var target_def: EntityDef = registry.get_by_id(_effective_def_id(target))
		if target_def == null or not target_def.tags.has(require_tag):
			out["reason"] = "missing_target_tag"
			return out
		if target.current_hp <= 0 and target_def.resource_source == null:
			out["reason"] = "missing_target_tag"
			return out
		var target_rect: Rect2i = state.tile_grid.entity_rect(overlap_target_id)
		if target_rect.size.x <= 0 or target_rect.size.y <= 0:
			out["reason"] = "missing_target_tag"
			return out
		rect = Rect2i(target_rect.position, footprint)
		if target_rect.size != rect.size:
			out["reason"] = "target_footprint_mismatch"
			return out
	if not state.tile_grid.is_rect_in_bounds(rect):
		out["reason"] = "off_grid"
		return out
	out["valid"] = true
	out["reason"] = ""
	out["def"] = def
	out["rect"] = rect
	out["overlap_target_id"] = overlap_target_id
	return out


static func _reject_pending_build(
	state: MatchState,
	worker: Entity,
	registry: EntityRegistry,
	reason: String,
	events: Array[ResolverEvent]
) -> void:
	_refund_pending_build_cost(state, worker, registry)
	_clear_pending_build(worker)
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.ORDER_REJECTED
	ev.actor_id = worker.id
	ev.def_id = reason
	events.append(ev)


static func _refund_pending_build_cost(
	state: MatchState, worker: Entity, registry: EntityRegistry
) -> void:
	if state == null or worker == null or registry == null:
		return
	var def: EntityDef = registry.get_by_id(worker.pending_build_def_id)
	if def == null or def.construction == null:
		return
	var player: PlayerState = state.get_player(worker.owner_player_id)
	if player == null:
		return
	player.minerals += def.construction.mineral_cost
	player.gas += def.construction.gas_cost
	if def.population != null:
		player.pop_used = max(0, player.pop_used - def.population.pop_cost)


static func _clear_pending_build(worker: Entity) -> void:
	if worker == null:
		return
	worker.pending_build_def_id = ""
	worker.pending_build_target_tile = Vector2i.ZERO
	worker.pending_build_target_entity_id = -1


static func _interrupt_gather_assignment(entity: Entity) -> void:
	if entity == null or entity.gather_state == null:
		return
	entity.gather_state.phase = GatherState.Phase.IDLE
	entity.gather_state.assigned_source_entity_id = -1
	entity.gather_state.carrying_amount = 0
	entity.gather_state.carrying_resource_type = ""


static func _find_target_at_tile(
	state: MatchState, registry: EntityRegistry, tile: Vector2i, tag: String
) -> int:
	if state.tile_grid == null or registry == null:
		return -1
	if not state.tile_grid.is_in_bounds(tile):
		return -1
	var matching_ids: Array[int] = []
	for occupant_id in state.tile_grid.entities_at(tile):
		var occupant: Entity = state.get_entity_by_id(occupant_id)
		if occupant == null:
			continue
		var def: EntityDef = registry.get_by_id(_effective_def_id(occupant))
		if def != null and def.tags.has(tag):
			matching_ids.append(occupant.id)
	if matching_ids.size() != 1:
		return -1
	return matching_ids[0]


static func _effective_def_id(entity: Entity) -> String:
	if entity == null:
		return ""
	if entity.current_def_id != "":
		return entity.current_def_id
	return entity.def_id


static func _finalize(
	state: MatchState,
	registry: EntityRegistry,
	building: Entity,
	worker: Entity,
	events: Array[ResolverEvent]
) -> void:
	building.is_constructing = false
	building.construction_turns_remaining = -1
	building.construction_worker_id = -1
	if worker != null:
		worker.locked_to_building_id = -1
	# Apply pop_provides if the def carries population.
	var def: EntityDef = registry.get_by_id(building.current_def_id) if registry != null else null
	if def != null and def.population != null:
		var player: PlayerState = state.get_player(building.owner_player_id)
		if player != null:
			player.pop_cap += def.population.pop_provides
	var ev: ResolverEvent = ResolverEvent.new()
	ev.type = ResolverEvent.Type.BUILD_COMPLETED
	ev.actor_id = building.id
	if def != null:
		ev.def_id = def.id
	events.append(ev)


static func _is_adjacent_to(state: MatchState, a: Entity, b: Entity) -> bool:
	if state.tile_grid == null:
		return false
	var ar: Rect2i = state.tile_grid.entity_rect(a.id)
	var br: Rect2i = state.tile_grid.entity_rect(b.id)
	if ar.size == Vector2i.ZERO or br.size == Vector2i.ZERO:
		return false
	return TileGrid.distance_between_rects(ar, br) <= 1


static func _is_adjacent_to_rect(state: MatchState, entity: Entity, rect: Rect2i) -> bool:
	if state == null or state.tile_grid == null or entity == null:
		return false
	var entity_rect: Rect2i = state.tile_grid.entity_rect(entity.id)
	if entity_rect.size == Vector2i.ZERO or rect.size == Vector2i.ZERO:
		return false
	return TileGrid.distance_between_rects(entity_rect, rect) <= 1


static func _can_step(actor: Entity, registry: EntityRegistry) -> bool:
	if registry == null:
		return false
	var def: EntityDef = registry.get_by_id(actor.current_def_id)
	if def == null or def.movement == null:
		return false
	return actor.moves_used_this_turn < def.movement.speed_tiles_per_turn
