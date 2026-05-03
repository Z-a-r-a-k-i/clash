class_name ConstructionSystem
extends RefCounted

# Drives the BUILD lifecycle for plan node 05.
#
# BUILD has a different shape from TRAIN/RESEARCH: cost is paid up front
# at distribution (a single worker-to-tile commitment, not a queue), and
# progress is tracked on the building entity itself rather than on a
# producer's ProductionState.queue.
#
# Phase 2 hook (`advance_move_phase`): workers with locked_to_building_id
# step toward their building's rect, mirroring how gather_system walks
# workers toward a source. The worker stops on adjacency.
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


# ---------- Internals ----------


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


static func _can_step(actor: Entity, registry: EntityRegistry) -> bool:
	if registry == null:
		return false
	var def: EntityDef = registry.get_by_id(actor.current_def_id)
	if def == null or def.movement == null:
		return false
	return actor.moves_used_this_turn < def.movement.speed_tiles_per_turn
