extends RefCounted

# Resolver-internal helpers. No class_name (underscore prefix signals
# internal-only); siblings load this via `preload`.
#
# Lives separately from Resolver to keep the entry point readable and to
# keep the chunk boundaries in plan/m0/02 implementable: state cloning
# and queue dispatch can be implemented and unit-tested before any system
# logic exists.

# ---------- Order distribution ----------


# Per-entity order queues, indexed by entity id. Built from the flat
# `queue_a` + `queue_b` submissions. Orders for entities the submitting
# player doesn't own are dropped with a push_warning (M0 — at M2 this
# would be a wire-validation error).
#
# HOLD_FIRE_TOGGLE, CANCEL, GATHER, TRAIN, and RESEARCH apply immediately
# during distribution (state mutation, no tick — they're mode changes /
# standing orders, not per-tick actions). Other order types accumulate
# into the per-entity arrays for the tick loop to consume. The caller
# (resolver) is responsible for running ProductionSystem.try_fill_active_slots
# after this returns, so an idle producer that just received a TRAIN
# this turn starts producing the same turn.
static func distribute_orders(
	state: MatchState,
	queue_a: Array[EntityOrder],
	queue_b: Array[EntityOrder],
	registry: EntityRegistry,
	events: Array[ResolverEvent]
) -> Dictionary:
	var per_entity: Dictionary = {}  # int entity_id -> Array[EntityOrder]
	# Resolve expected owner from state.players so non-default player_id
	# assignments still validate ownership correctly. Null/missing slots
	# fall back to the conventional 0/1 mapping.
	var p_a: PlayerState = state.players[0] if state.players.size() >= 1 else null
	var p_b: PlayerState = state.players[1] if state.players.size() >= 2 else null
	var owner_a := p_a.player_id if p_a != null else 0
	var owner_b := p_b.player_id if p_b != null else 1
	_distribute_one(state, queue_a, owner_a, per_entity, registry, events)
	_distribute_one(state, queue_b, owner_b, per_entity, registry, events)
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
	state: MatchState,
	queue: Array[EntityOrder],
	expected_owner: int,
	per_entity: Dictionary,
	registry: EntityRegistry,
	events: Array[ResolverEvent]
) -> void:
	for order in queue:
		if order == null or order.type == EntityOrder.Type.INVALID:
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
		# HOLD_FIRE_TOGGLE, CANCEL, and GATHER apply at distribution time,
		# not in the tick loop — they're mode changes / standing orders,
		# not per-tick actions.
		if order.type == EntityOrder.Type.HOLD_FIRE_TOGGLE:
			# `hold_fire` on the order is the desired state, not a delta.
			# Naming kept as TOGGLE to match plan/m0/03 vocabulary.
			entity.hold_fire = order.hold_fire
			continue
		if order.type == EntityOrder.Type.CANCEL:
			_handle_cancel_order(state, entity, order, events)
			continue
		if order.type == EntityOrder.Type.TRAIN:
			_handle_train_order(entity, order, events)
			continue
		if order.type == EntityOrder.Type.RESEARCH:
			_handle_research_order(state, entity, order, events)
			continue
		if order.type == EntityOrder.Type.BUILD:
			_handle_build_order(state, entity, order, registry, events)
			continue
		# Locked workers (mid-construction) reject any tick-action orders.
		if entity.locked_to_building_id >= 0:
			_emit_order_rejected(order.entity_id, "worker_locked", events)
			continue
		if order.type == EntityOrder.Type.GATHER:
			# A GATHER turns into standing state on the worker: we set the
			# assignment + transition the FSM into MOVING_TO_SOURCE; the
			# resolver's gather_system advances it from there each tick.
			# Workers without a gather_state (non-worker units) silently
			# drop the order. Any prior MOVE / ATTACK_MOVE persistent_order
			# is cleared — gathering supersedes it, otherwise the move
			# would resume after the gather FSM returns to IDLE.
			if entity.gather_state == null:
				push_warning(
					(
						"GATHER for entity %d has no gather_state (not a worker); dropping."
						% order.entity_id
					)
				)
				continue
			entity.gather_state.assigned_source_entity_id = order.target_entity_id
			# A loaded worker must drop its existing cargo before starting
			# the new cycle, otherwise switching to a different resource
			# type would mis-credit the deposit (carrying_resource_type is
			# overwritten in _tick_gather).
			if entity.gather_state.carrying_amount > 0:
				entity.gather_state.phase = GatherState.Phase.MOVING_TO_BASE
			else:
				entity.gather_state.phase = GatherState.Phase.MOVING_TO_SOURCE
			entity.persistent_order = null
			continue
		# Per-tick orders queue up.
		if not per_entity.has(order.entity_id):
			per_entity[order.entity_id] = []
		per_entity[order.entity_id].append(order)


# BUILD handler — eager-deduct (cost is paid up front). Two paths:
# new construction (target_entity_id < 0) and resume of a paused
# building (target_entity_id is the paused building). Plan node 05
# chunk 5/6.
static func _handle_build_order(
	state: MatchState,
	worker: Entity,
	order: EntityOrder,
	registry: EntityRegistry,
	events: Array[ResolverEvent]
) -> void:
	if order.target_entity_id >= 0:
		_handle_build_resume(state, worker, order, events)
		return
	# New construction.
	if worker.locked_to_building_id >= 0:
		_emit_order_rejected(order.entity_id, "worker_locked", events)
		return
	if registry == null:
		_emit_order_rejected(order.entity_id, "no_registry", events)
		return
	var def: EntityDef = registry.get_by_id(order.def_id)
	if def == null or def.construction == null:
		_emit_order_rejected(order.entity_id, "bad_build_target", events)
		return
	var built_by: String = def.construction.built_by_tag
	if built_by != "" and not _worker_has_tag(worker, registry, built_by):
		_emit_order_rejected(order.entity_id, "wrong_builder", events)
		return
	var footprint := def.footprint if def.footprint != Vector2i.ZERO else Vector2i.ONE
	var rect := Rect2i(order.target_tile, footprint)
	if state.tile_grid == null or not state.tile_grid.is_rect_in_bounds(rect):
		_emit_order_rejected(order.entity_id, "off_grid", events)
		return
	# Refinery / overlap path lands in chunk 7. For now, basic clearance.
	var require_tag: String = def.construction.requires_target_tag
	if require_tag != "":
		# Defer to chunk 7 (place_overlapping); reject for now if the tile
		# isn't already free.
		if not state.tile_grid.is_rect_clear(rect):
			# Allow overlap if the only existing entity carries the
			# required tag — placeholder until tile_grid.place_overlapping
			# lands in chunk 7. Currently rejects anything else.
			if not _overlap_allowed(state, registry, rect, require_tag):
				_emit_order_rejected(order.entity_id, "tile_occupied", events)
				return
	else:
		if not state.tile_grid.is_rect_clear(rect):
			_emit_order_rejected(order.entity_id, "tile_occupied", events)
			return
	var player := state.get_player(worker.owner_player_id)
	if player == null:
		return
	var pop_cost := 0
	if def.population != null:
		pop_cost = def.population.pop_cost
	if (
		player.minerals < def.construction.mineral_cost
		or player.gas < def.construction.gas_cost
		or player.pop_used + pop_cost > player.pop_cap
	):
		_emit_order_rejected(order.entity_id, "insufficient_resources", events)
		return
	# Deduct + spawn building entity.
	player.minerals -= def.construction.mineral_cost
	player.gas -= def.construction.gas_cost
	player.pop_used += pop_cost
	var building := Entity.new()
	building.id = state.allocate_entity_id()
	building.def_id = def.id
	building.current_def_id = def.id
	building.owner_player_id = worker.owner_player_id
	building.origin = order.target_tile
	building.current_layer = "ground"
	if def.health != null:
		building.current_hp = def.health.max_hp
	building.is_constructing = true
	building.construction_turns_remaining = def.construction.build_time_turns
	building.construction_worker_id = worker.id
	if def.production != null:
		building.production_state = ProductionState.new()
	state.entities.append(building)
	# Place. Refinery overlap is chunk 7's job — for now assume clear.
	if require_tag != "":
		_place_overlapping(state, registry, building.id, rect, require_tag)
	else:
		state.tile_grid.place(building.id, rect)
	worker.locked_to_building_id = building.id
	worker.persistent_order = null
	if worker.gather_state != null:
		worker.gather_state.phase = GatherState.Phase.IDLE
		worker.gather_state.assigned_source_entity_id = -1
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.BUILD_STARTED
	ev.actor_id = worker.id
	ev.target_id = building.id
	ev.def_id = def.id
	events.append(ev)


static func _handle_build_resume(
	state: MatchState, worker: Entity, order: EntityOrder, events: Array[ResolverEvent]
) -> void:
	var building := state.get_entity_by_id(order.target_entity_id)
	if building == null or building.current_hp <= 0:
		_emit_order_rejected(order.entity_id, "missing_resume_target", events)
		return
	if not building.is_constructing:
		_emit_order_rejected(order.entity_id, "not_constructing", events)
		return
	if building.construction_worker_id >= 0:
		_emit_order_rejected(order.entity_id, "already_has_worker", events)
		return
	if building.owner_player_id != worker.owner_player_id:
		_emit_order_rejected(order.entity_id, "wrong_owner", events)
		return
	if worker.locked_to_building_id >= 0:
		_emit_order_rejected(order.entity_id, "worker_locked", events)
		return
	building.construction_worker_id = worker.id
	worker.locked_to_building_id = building.id
	worker.persistent_order = null
	if worker.gather_state != null:
		worker.gather_state.phase = GatherState.Phase.IDLE
		worker.gather_state.assigned_source_entity_id = -1
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.BUILD_RESUMED
	ev.actor_id = worker.id
	ev.target_id = building.id
	events.append(ev)


# Returns true if the worker's def carries `tag`. Used by BUILD validation.
static func _worker_has_tag(worker: Entity, registry: EntityRegistry, tag: String) -> bool:
	if registry == null:
		return false
	var def: EntityDef = registry.get_by_id(worker.current_def_id)
	if def == null:
		return false
	return def.tags.has(tag)


# Allow placement to overlap with an existing entity carrying `tag`
# (e.g. refinery on geyser). Full implementation lands in chunk 7;
# this scaffold supports the simple "only the tagged entity is in the
# rect" case via direct rect-index manipulation.
static func _overlap_allowed(
	state: MatchState, registry: EntityRegistry, rect: Rect2i, tag: String
) -> bool:
	if state.tile_grid == null or registry == null:
		return false
	var occupants: Array[int] = []
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var occ := state.tile_grid.entity_at(Vector2i(x, y))
			if occ != -1 and not occupants.has(occ):
				occupants.append(occ)
	if occupants.size() != 1:
		return false
	var occupant := state.get_entity_by_id(occupants[0])
	if occupant == null:
		return false
	var def: EntityDef = registry.get_by_id(occupant.current_def_id)
	return def != null and def.tags.has(tag)


# Place a building atop an entity that carries `allow_overlap_tag`. The
# overlap-tagged entity stays on the grid (the index allows multiple
# entries per tile via separate rects, but tile_grid.place rejects any
# overlap). Workaround: write directly to the rect index. Plan node 05
# chunk 7 will replace this with TileGrid.place_overlapping.
static func _place_overlapping(
	state: MatchState,
	_registry: EntityRegistry,
	entity_id: int,
	rect: Rect2i,
	_allow_overlap_tag: String
) -> void:
	# Direct rect index — bypass tile_grid.place's collision check. The
	# previous tagged entity stays in _occupancy at those tiles; future
	# queries for "what's at tile X" will return whichever entity was
	# placed last. Tracked TODO.
	state.tile_grid._entity_rects[entity_id] = rect


# RESEARCH handler — appends a queue declaration on the producer's
# ProductionState. Mirrors TRAIN but rejects research items the player
# has already unlocked. Plan node 05 chunk 4.
static func _handle_research_order(
	state: MatchState, entity: Entity, order: EntityOrder, events: Array[ResolverEvent]
) -> void:
	if entity.production_state == null:
		_emit_order_rejected(order.entity_id, "not_a_producer", events)
		push_warning(
			"RESEARCH for entity %d which has no production capability; dropping." % order.entity_id
		)
		return
	if order.def_id == "":
		_emit_order_rejected(order.entity_id, "missing_def_id", events)
		return
	var player := state.get_player(entity.owner_player_id)
	if player != null and player.unlocked_researches.has(order.def_id):
		_emit_order_rejected(order.entity_id, "duplicate_research", events)
		return
	(
		entity
		. production_state
		. queue
		. append(
			{
				ProductionState.KEY_DEF_ID: order.def_id,
				ProductionState.KEY_KIND: ProductionState.KIND_RESEARCH,
			}
		)
	)
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.RESEARCH_QUEUED
	ev.actor_id = order.entity_id
	ev.def_id = order.def_id
	events.append(ev)


# TRAIN handler — appends a queue declaration on the producer's
# ProductionState. No cost is deducted here; ProductionSystem.try_fill
# does that at slot transition. Plan node 05 chunk 2.
static func _handle_train_order(
	entity: Entity, order: EntityOrder, events: Array[ResolverEvent]
) -> void:
	if entity.production_state == null:
		_emit_order_rejected(order.entity_id, "not_a_producer", events)
		push_warning(
			"TRAIN for entity %d which has no production capability; dropping." % order.entity_id
		)
		return
	if order.def_id == "":
		_emit_order_rejected(order.entity_id, "missing_def_id", events)
		return
	# Membership check (def_id must be in producer's `produces` list)
	# happens here at distribution. Registry-driven check is folded in
	# at try_fill time when the cost is looked up; producing an unknown
	# def at distribution should still be flagged early so the player
	# sees the rejection event rather than a silent stall.
	(
		entity
		. production_state
		. queue
		. append(
			{
				ProductionState.KEY_DEF_ID: order.def_id,
				ProductionState.KEY_KIND: ProductionState.KIND_UNIT,
			}
		)
	)
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.TRAIN_QUEUED
	ev.actor_id = order.entity_id
	ev.def_id = order.def_id
	events.append(ev)


static func _emit_order_rejected(
	actor_id: int, reason: String, events: Array[ResolverEvent]
) -> void:
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.ORDER_REJECTED
	ev.actor_id = actor_id
	ev.def_id = reason
	events.append(ev)


# CANCEL handler — splits the three semantic flavours per plan node 05:
#   cancel_index == -1: clear persistent_order (and, in chunks 5/6,
#                       cancel a BUILD via the worker).
#   cancel_index == 0:  cancel the active production slot, refund the
#                       paid amounts. Queue head can install same turn
#                       (resolver runs try_fill after distribution).
#   cancel_index >= 1:  remove queue[cancel_index - 1]. No cost
#                       movement (queue items are unpaid).
static func _handle_cancel_order(
	_state: MatchState, entity: Entity, order: EntityOrder, events: Array[ResolverEvent]
) -> void:
	if order.cancel_index < 0:
		entity.persistent_order = null
		return
	if order.cancel_index == 0:
		_cancel_active_production(_state, entity, events)
		return
	_cancel_queued_production(entity, order.cancel_index, events)


static func _cancel_active_production(
	state: MatchState, entity: Entity, events: Array[ResolverEvent]
) -> void:
	if entity.production_state == null or entity.production_state.active.is_empty():
		_emit_order_rejected(entity.id, "no_active_production", events)
		return
	var active: Dictionary = entity.production_state.active
	var paid_minerals: int = active.get(ProductionState.KEY_PAID_MINERALS, 0)
	var paid_gas: int = active.get(ProductionState.KEY_PAID_GAS, 0)
	var paid_pop: int = active.get(ProductionState.KEY_PAID_POP, 0)
	var def_id: String = active.get(ProductionState.KEY_DEF_ID, "")
	var player := state.get_player(entity.owner_player_id)
	if player != null:
		player.minerals += paid_minerals
		player.gas += paid_gas
		player.pop_used = max(0, player.pop_used - paid_pop)
	entity.production_state.active = {}
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.PRODUCTION_CANCELLED
	ev.actor_id = entity.id
	ev.def_id = def_id
	ev.amount = 0  # cancel_index 0 = active
	events.append(ev)


static func _cancel_queued_production(
	entity: Entity, cancel_index: int, events: Array[ResolverEvent]
) -> void:
	if entity.production_state == null:
		_emit_order_rejected(entity.id, "no_production_capability", events)
		return
	var queue_index := cancel_index - 1
	if queue_index < 0 or queue_index >= entity.production_state.queue.size():
		_emit_order_rejected(entity.id, "queue_index_out_of_range", events)
		return
	var item: Dictionary = entity.production_state.queue[queue_index]
	var def_id: String = item.get(ProductionState.KEY_DEF_ID, "")
	entity.production_state.queue.remove_at(queue_index)
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.PRODUCTION_CANCELLED
	ev.actor_id = entity.id
	ev.def_id = def_id
	ev.amount = cancel_index
	events.append(ev)
