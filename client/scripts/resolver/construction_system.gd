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
		if MovementSystem._has_fresh_order_at(per_entity, actor.id, tick):
			continue
		var building := state.get_entity_by_id(actor.locked_to_building_id)
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
		var building_rect := state.tile_grid.entity_rect(building.id)
		if building_rect.size == Vector2i.ZERO:
			continue
		if MovementSystem._step_toward(state, actor, building_rect.position, events):
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
		var worker_id := entity.construction_worker_id
		var worker: Entity = state.get_entity_by_id(worker_id) if worker_id >= 0 else null
		var paused := worker == null or worker.current_hp <= 0
		if not paused:
			# Worker must also be adjacent. If they wandered off (only
			# possible via a forced unlock path), pause too.
			paused = not _is_adjacent_to(state, worker, entity)
		if paused:
			if worker_id >= 0:
				entity.construction_worker_id = -1
				if worker != null and worker.current_hp > 0:
					# The worker entity is alive but no longer adjacent —
					# we don't unlink locked_to_building_id; resume picks
					# up the link via target_entity_id. M0 doesn't yet
					# expose ways to forcibly unlock a still-walking
					# worker, so this branch is mostly defensive.
					pass
				var ev := ResolverEvent.new()
				ev.type = ResolverEvent.Type.BUILD_PAUSED
				ev.actor_id = entity.id
				events.append(ev)
			continue
		# Tick.
		entity.construction_turns_remaining -= 1
		var prog := ResolverEvent.new()
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
		var player := state.get_player(building.owner_player_id)
		if player != null:
			player.pop_cap += def.population.pop_provides
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.BUILD_COMPLETED
	ev.actor_id = building.id
	if def != null:
		ev.def_id = def.id
	events.append(ev)


static func _is_adjacent_to(state: MatchState, a: Entity, b: Entity) -> bool:
	if state.tile_grid == null:
		return false
	var ar := state.tile_grid.entity_rect(a.id)
	var br := state.tile_grid.entity_rect(b.id)
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
