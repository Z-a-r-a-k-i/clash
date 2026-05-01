extends RefCounted

# Resolver-internal helpers. No class_name (underscore prefix signals
# internal-only); siblings load this via `preload`.
#
# Lives separately from Resolver to keep the entry point readable and to
# keep the chunk boundaries in plan/m0/02 implementable: state cloning
# and queue dispatch can be implemented and unit-tested before any system
# logic exists.

# ---------- Surrender detection ----------


# Player-level orders short-circuit normal resolution. Returns true if any
# order in the queue is SURRENDER (entity_id is -1 for player-level orders).
static func has_surrender(queue: Array[EntityOrder]) -> bool:
	for o in queue:
		if o != null and o.type == EntityOrder.Type.SURRENDER:
			return true
	return false


# ---------- Order distribution ----------


# Per-entity order queues, indexed by entity id. Built from the flat
# `queue_a` + `queue_b` submissions. Orders for entities the submitting
# player doesn't own are dropped with a push_warning (M0 — at M2 this
# would be a wire-validation error).
#
# HOLD_FIRE_TOGGLE and CANCEL apply immediately during distribution
# (state mutation, no tick — they're not "actions" but mode changes).
# Other order types accumulate into the per-entity arrays for the tick
# loop to consume.
static func distribute_orders(
	state: MatchState, queue_a: Array[EntityOrder], queue_b: Array[EntityOrder]
) -> Dictionary:
	var per_entity: Dictionary = {}  # int entity_id -> Array[EntityOrder]
	# Resolve expected owner from state.players so non-default player_id
	# assignments still validate ownership correctly. Null/missing slots
	# fall back to the conventional 0/1 mapping.
	var p_a: PlayerState = state.players[0] if state.players.size() >= 1 else null
	var p_b: PlayerState = state.players[1] if state.players.size() >= 2 else null
	var owner_a := p_a.player_id if p_a != null else 0
	var owner_b := p_b.player_id if p_b != null else 1
	_distribute_one(state, queue_a, owner_a, per_entity)
	_distribute_one(state, queue_b, owner_b, per_entity)
	return per_entity


# ---------- Tick helpers ----------


# Returns the maximum action queue length across all entities. Determines
# how many ticks the resolver iterates per ADR 0004.
static func max_queue_length(per_entity: Dictionary) -> int:
	var n := 0
	for entity_id in per_entity:
		var queue: Array = per_entity[entity_id]
		if queue.size() > n:
			n = queue.size()
	return n


# Returns the action at tick `t` (0-indexed) for the given entity, or
# null if the entity has no order at that tick (queue exhausted).
static func action_at(per_entity: Dictionary, entity_id: int, tick: int) -> EntityOrder:
	if not per_entity.has(entity_id):
		return null
	var queue: Array = per_entity[entity_id]
	if tick >= queue.size():
		return null
	return queue[tick]


# ---------- Internals ----------


static func _distribute_one(
	state: MatchState, queue: Array[EntityOrder], expected_owner: int, per_entity: Dictionary
) -> void:
	for order in queue:
		if order == null or order.type == EntityOrder.Type.INVALID:
			continue
		# Player-level orders (SURRENDER) handled separately by Resolver.
		if order.type == EntityOrder.Type.SURRENDER:
			continue
		var entity := state.get_entity_by_id(order.entity_id)
		if entity == null:
			push_warning("Order references missing entity id %d; dropping." % order.entity_id)
			continue
		if entity.owner_player_id != expected_owner:
			push_warning(
				(
					"Order from player %d targets entity %d owned by player %d; dropping."
					% [expected_owner, order.entity_id, entity.owner_player_id]
				)
			)
			continue
		# HOLD_FIRE_TOGGLE and CANCEL apply at distribution time, not in the
		# tick loop — they're mode changes, not actions.
		if order.type == EntityOrder.Type.HOLD_FIRE_TOGGLE:
			# `hold_fire` on the order is the desired state, not a delta.
			# Naming kept as TOGGLE to match plan/m0/03 vocabulary.
			entity.hold_fire = order.hold_fire
			continue
		if order.type == EntityOrder.Type.CANCEL:
			if order.cancel_index < 0:
				entity.persistent_order = null
			else:
				# M0 stub: cancel-by-queue-index for production isn't wired
				# yet (plan node 05's job). Surface the gap so it's visible.
				push_warning(
					(
						(
							"CANCEL with cancel_index=%d is not yet handled "
							+ "(production cancel arrives with plan node 05); dropping."
						)
						% order.cancel_index
					)
				)
			continue
		# Per-tick orders queue up.
		if not per_entity.has(order.entity_id):
			per_entity[order.entity_id] = []
		per_entity[order.entity_id].append(order)
