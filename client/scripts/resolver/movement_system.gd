class_name MovementSystem
extends RefCounted

# Movement system — resolves MOVE orders and advances persistent moves.
#
# Per-tick semantics (called from Phase 2 of the resolver tick loop):
# - MOVE: advance one tile toward order.target_tile if the entity has
#   move budget remaining. Ignores enemies along the path.
#
# Persistent moves (Phase 3): for each entity with `persistent_order` set
# and no fresh order at this tick, advance one tile toward the persistent
# target. Clears the order on arrival or on the entity's death.
#
# Per-turn budget: an entity can move at most `def.movement.speed_tiles_per_turn`
# tiles in one turn, accumulated across all ticks. Tracked via
# Entity.moves_used_this_turn (reset at end-of-turn).
#
# Pathfinding: M0 ships a Chebyshev one-step heuristic. If the diagonal
# step toward the target collides, fall back to axis-aligned. No A* yet —
# that's a future plan-node concern when terrain features arrive.


static func resolve_move(
	state: MatchState,
	actor: Entity,
	order: EntityOrder,
	registry: EntityRegistry,
	_tunables: Tunables,
	events: Array[ResolverEvent],
	movement_budget: int = -1,
	persist: bool = true
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
		if persist:
			actor.persistent_order = order
			if actor.origin == order.target_tile:
				actor.persistent_order = null


static func advance_persistent_moves(
	state: MatchState,
	per_entity: Dictionary,
	tick: int,
	registry: EntityRegistry,
	_tunables: Tunables,
	events: Array[ResolverEvent],
	fired_entity_ids: Dictionary = {},
	halted_entity_ids: Dictionary = {}
) -> void:
	if state.tile_grid == null:
		return
	for actor in state.entities_sorted_by_id():
		if actor.current_hp <= 0:
			continue
		if actor.persistent_order == null:
			continue
		# Skip entities that had a fresh order at this tick — Phase 2
		# already handled them.
		if has_fresh_order_at(per_entity, actor.id, tick):
			continue
		# Skip workers actively gathering. GatherSystem.advance_move_phase
		# already stepped them in Phase 2; advancing a stale persistent_order
		# here would double-step.
		if actor.gather_state != null and actor.gather_state.phase != GatherState.Phase.IDLE:
			continue
		if halted_entity_ids.has(actor.id):
			continue

		var po: EntityOrder = actor.persistent_order
		var movement_speed: int = movement_budget_for_entity(
			actor, registry, fired_entity_ids.has(actor.id), false
		)
		if movement_speed <= 0:
			continue
		if actor.moves_used_this_turn >= movement_speed:
			continue

		if step_toward(state, actor, po.target_tile, events):
			actor.moves_used_this_turn += 1
			if actor.origin == po.target_tile:
				actor.persistent_order = null


# ---------- Internals ----------


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


# Lookup-only helper — does this entity have a queued action at this tick?
static func has_fresh_order_at(per_entity: Dictionary, entity_id: int, tick: int) -> bool:
	if not per_entity.has(entity_id):
		return false
	var queue: Array = per_entity[entity_id]
	if tick >= queue.size():
		return false
	var o: EntityOrder = queue[tick]
	return o != null


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
	var speed := movement_speed_for_entity(actor, registry)
	if speed <= 0:
		return 0
	if move_only or not fired_this_turn:
		return speed
	var def: EntityDef = registry.get_by_id(actor.current_def_id) if registry != null else null
	var fraction := 0.5
	if def != null and def.movement != null:
		fraction = clampf(def.movement.post_shot_move_fraction, 0.0, 1.0)
	return max(0, int(floor(float(speed) * fraction)))
