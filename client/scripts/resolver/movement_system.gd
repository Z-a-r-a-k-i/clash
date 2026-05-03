class_name MovementSystem
extends RefCounted

# Movement system — resolves MOVE / ATTACK_MOVE orders and advances
# persistent move orders.
#
# Per-tick semantics (called from Phase 2 of the resolver tick loop):
# - MOVE: advance one tile toward order.target_tile if the entity has
#   move budget remaining. Ignores enemies along the path.
# - ATTACK_MOVE: if any enemy is in attack range right now, halt this
#   tick (combat already fired in Phase 1). Otherwise advance one tile.
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
	events: Array[ResolverEvent]
) -> void:
	if actor == null or actor.current_hp <= 0:
		return
	if state.tile_grid == null:
		return

	# ATTACK_MOVE halts if there's a target in range — Phase 1 already
	# fired (or had nothing to fire at), and ATTACK_MOVE semantics say
	# "stops to engage if an enemy is in attack range." We still record the
	# order as persistent so the unit resumes toward target_tile once the
	# threat is gone next turn.
	if order.type == EntityOrder.Type.ATTACK_MOVE and _enemy_in_range(state, actor, registry):
		actor.persistent_order = order
		return

	# Move budget check.
	var def: EntityDef = registry.get_by_id(actor.current_def_id) if registry != null else null
	if def == null or def.movement == null:
		return  # Not movement-capable.
	if actor.moves_used_this_turn >= def.movement.speed_tiles_per_turn:
		return

	if step_toward(state, actor, order.target_tile, events):
		actor.moves_used_this_turn += 1
		actor.persistent_order = order
		if actor.origin == order.target_tile:
			actor.persistent_order = null


static func advance_persistent_moves(
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

		# ATTACK_MOVE persistent: halt if an enemy is in range.
		var po: EntityOrder = actor.persistent_order
		if po.type == EntityOrder.Type.ATTACK_MOVE and _enemy_in_range(state, actor, registry):
			continue

		var def: EntityDef = registry.get_by_id(actor.current_def_id) if registry != null else null
		if def == null or def.movement == null:
			continue
		if actor.moves_used_this_turn >= def.movement.speed_tiles_per_turn:
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


# Returns true if any enemy of `actor` is currently within attack range.
# Used by ATTACK_MOVE to decide whether to halt this tick. Reuses the
# combat layer / range checks via CombatSystem._is_valid_target.
static func _enemy_in_range(state: MatchState, actor: Entity, registry: EntityRegistry) -> bool:
	if registry == null:
		return false
	var def: EntityDef = registry.get_by_id(actor.current_def_id)
	if def == null or def.combat == null:
		return false
	var combat: CombatDef = def.combat
	for candidate in state.entities_sorted_by_id():
		if CombatSystem._is_valid_target(state, actor, combat, candidate, registry):
			return true
	return false
