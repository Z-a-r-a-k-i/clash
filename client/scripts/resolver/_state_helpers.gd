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
# CANCEL, GATHER, TRAIN, RESEARCH, and TARGET focus apply immediately during
# distribution (state mutation, no tick — they're mode changes / standing
# orders, not per-tick actions). Movement
# orders accumulate into per-entity arrays for the tick loop to consume.
# Duplicate move-like orders for the same entity collapse to the latest target.
# The caller
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
		# CANCEL and standing orders apply at distribution time, not in the
		# tick loop.
		if order.type == EntityOrder.Type.CANCEL:
			_handle_cancel_order(state, entity, order, registry, events)
			continue
		if order.type == EntityOrder.Type.SET_RALLY_POINT:
			_handle_set_rally_order(state, entity, order, registry, events)
			continue
		if order.type == EntityOrder.Type.REPEAT_TRAIN_TOGGLE:
			_handle_repeat_train_toggle_order(entity, order, registry, events)
			continue
		if order.type == EntityOrder.Type.TRAIN:
			_handle_train_order(entity, order, registry, events)
			continue
		if order.type == EntityOrder.Type.RESEARCH:
			_handle_research_order(state, entity, order, registry, events)
			continue
		if order.type == EntityOrder.Type.BUILD:
			_handle_build_order(state, entity, order, registry, events)
			continue
		# Build-committed workers reject any tick-action orders, whether
		# the building entity has spawned yet or construction is underway.
		if entity.locked_to_building_id >= 0 or ConstructionSystem.has_pending_build(entity):
			_emit_order_rejected(order.entity_id, "worker_locked", events)
			continue
		if order.type == EntityOrder.Type.GATHER:
			# A GATHER turns into standing state on the worker: we set the
			# assignment + transition the FSM into MOVING_TO_SOURCE; the
			# resolver's gather_system advances it from there each tick.
			# Workers without a gather_state (non-worker units) silently
			# drop the order.
			if entity.gather_state == null:
				push_warning(
					(
						"GATHER for entity %d has no gather_state (not a worker); dropping."
						% order.entity_id
					)
				)
				continue
			var source: Entity = GatherSystem.resolve_source_for_worker(
				state, registry, order.target_entity_id, entity.owner_player_id
			)
			if source == null:
				GatherSystem.clear_assignment(entity)
				_emit_order_rejected(order.entity_id, "bad_gather_target", events)
				continue
			var assigned_source: Entity = GatherSystem.best_source_for_worker(
				state, registry, entity, source
			)
			if assigned_source == null:
				GatherSystem.clear_assignment(entity)
				_emit_order_rejected(order.entity_id, "source_saturated", events)
				continue
			entity.gather_state.assigned_source_entity_id = assigned_source.id
			entity.gather_state.carrying_amount = 0
			entity.gather_state.carrying_resource_type = ""
			if _is_adjacent_to(state, entity, assigned_source):
				entity.gather_state.phase = GatherState.Phase.GATHERING
			else:
				entity.gather_state.phase = GatherState.Phase.MOVING_TO_SOURCE
			continue
		if order.type == EntityOrder.Type.TARGET:
			GatherSystem.clear_assignment(entity)
			if not _can_target_visible_enemy(state, entity, order, registry):
				_emit_order_rejected(order.entity_id, "bad_target", events)
				continue
			_refresh_attack_target_tile(state, entity, order)
			_set_focus_target_from_chain(state, entity, order.target_priority_chain)
			continue
		# Per-tick orders queue up.
		GatherSystem.clear_assignment(entity)
		if (
			(order.type == EntityOrder.Type.MOVE or order.type == EntityOrder.Type.ATTACK_MOVE)
			and order.target_entity_id < 0
			and order.target_priority_chain.is_empty()
		):
			entity.focus_target_entity_id = -1
		if not per_entity.has(order.entity_id):
			per_entity[order.entity_id] = []
		if order.type == EntityOrder.Type.MOVE or order.type == EntityOrder.Type.ATTACK_MOVE:
			_queue_replacing_move(per_entity, order)
		else:
			per_entity[order.entity_id].append(order)


static func _is_adjacent_to(state: MatchState, a: Entity, b: Entity) -> bool:
	if state == null or state.tile_grid == null:
		return false
	var ar: Rect2i = state.tile_grid.entity_rect(a.id)
	var br: Rect2i = state.tile_grid.entity_rect(b.id)
	if ar.size == Vector2i.ZERO or br.size == Vector2i.ZERO:
		return false
	return TileGrid.distance_between_rects(ar, br) <= 1


static func _set_focus_target_from_chain(
	state: MatchState, entity: Entity, target_priority_chain: Array[int]
) -> void:
	entity.focus_target_entity_id = -1
	for target_id in target_priority_chain:
		var target := state.get_entity_by_id(target_id)
		if target == null or target.current_hp <= 0:
			continue
		if target.owner_player_id < 0 or target.owner_player_id == entity.owner_player_id:
			continue
		entity.focus_target_entity_id = target.id
		return


static func _refresh_attack_target_tile(
	state: MatchState, entity: Entity, order: EntityOrder
) -> void:
	if state == null or entity == null or order == null or order.target_priority_chain.is_empty():
		return
	var target := state.get_entity_by_id(order.target_priority_chain[0])
	if target == null or target.current_hp <= 0:
		return
	if target.owner_player_id < 0 or target.owner_player_id == entity.owner_player_id:
		return
	if state.tile_grid != null:
		var target_rect: Rect2i = state.tile_grid.entity_rect(target.id)
		if target_rect.size != Vector2i.ZERO:
			order.target_tile = target_rect.position
			return
	order.target_tile = target.origin


static func _can_target_visible_enemy(
	state: MatchState, entity: Entity, order: EntityOrder, registry: EntityRegistry
) -> bool:
	if state == null or entity == null or order == null or registry == null:
		return false
	if order.target_priority_chain.is_empty():
		return false
	var target: Entity = state.get_entity_by_id(order.target_priority_chain[0])
	if target == null:
		return false
	if target.current_hp <= 0:
		return false
	if target.owner_player_id < 0 or target.owner_player_id == entity.owner_player_id:
		return false
	if not _is_visible_to_player(state, registry, target, entity.owner_player_id):
		return false
	var def: EntityDef = registry.get_by_id(_effective_def_id(entity))
	if def == null or def.combat == null:
		return false
	return def.combat.target_layers.has(target.current_layer)


static func _can_entity_move(entity: Entity, registry: EntityRegistry) -> bool:
	if entity == null or registry == null:
		return false
	var def: EntityDef = registry.get_by_id(_effective_def_id(entity))
	return def != null and def.movement != null and def.movement.speed_tiles_per_turn > 0


static func _queue_replacing_move(per_entity: Dictionary, order: EntityOrder) -> void:
	if not per_entity.has(order.entity_id):
		per_entity[order.entity_id] = []
	var queue: Array = per_entity[order.entity_id]
	for i in range(queue.size() - 1, -1, -1):
		var existing: EntityOrder = queue[i]
		if (
			existing != null
			and (
				existing.type == EntityOrder.Type.MOVE
				or existing.type == EntityOrder.Type.ATTACK_MOVE
			)
		):
			queue.remove_at(i)
	queue.append(order)


static func _is_visible_to_player(
	state: MatchState, registry: EntityRegistry, entity: Entity, player_id: int
) -> bool:
	if entity == null or player_id < 0:
		return false
	if state == null or state.tile_grid == null:
		return true
	var visibility := VisionSystem.compute_player_visibility(state, registry, player_id)
	return VisionSystem.is_entity_visible_to_player(entity, state, registry, player_id, visibility)


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
		_handle_build_resume(state, worker, order, registry, events)
		return
	# New construction.
	if worker.locked_to_building_id >= 0 or ConstructionSystem.has_pending_build(worker):
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
	if state.tile_grid == null:
		_emit_order_rejected(order.entity_id, "off_grid", events)
		return
	var require_tag: String = def.construction.requires_target_tag
	var overlap_target_id := -1
	if require_tag != "":
		overlap_target_id = _find_target_at_tile(state, registry, order.target_tile, require_tag)
		if overlap_target_id < 0:
			_emit_order_rejected(order.entity_id, "missing_target_tag", events)
			return
		var target_rect: Rect2i = state.tile_grid.entity_rect(overlap_target_id)
		if target_rect.size.x <= 0 or target_rect.size.y <= 0:
			_emit_order_rejected(order.entity_id, "missing_target_tag", events)
			return
		rect = Rect2i(target_rect.position, footprint)
		if target_rect.size != rect.size:
			_emit_order_rejected(order.entity_id, "target_footprint_mismatch", events)
			return
		if not state.tile_grid.is_rect_in_bounds(rect):
			_emit_order_rejected(order.entity_id, "off_grid", events)
			return
		if not _can_place_build_rect(state, rect, overlap_target_id):
			_emit_order_rejected(order.entity_id, "tile_occupied", events)
			return
	elif not state.tile_grid.is_rect_in_bounds(rect):
		_emit_order_rejected(order.entity_id, "off_grid", events)
		return
	elif not state.tile_grid.is_rect_clear(rect):
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
	# Deduct now, but don't spawn the building until the worker reaches
	# adjacency and starts construction.
	player.minerals -= def.construction.mineral_cost
	player.gas -= def.construction.gas_cost
	player.pop_used += pop_cost
	worker.pending_build_def_id = def.id
	worker.pending_build_target_tile = rect.position
	worker.pending_build_target_entity_id = overlap_target_id
	GatherSystem.clear_assignment(worker)
	ConstructionSystem.try_start_pending_build(state, worker, registry, events)


static func _handle_build_resume(
	state: MatchState,
	worker: Entity,
	order: EntityOrder,
	registry: EntityRegistry,
	events: Array[ResolverEvent]
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
	if worker.locked_to_building_id >= 0 or ConstructionSystem.has_pending_build(worker):
		_emit_order_rejected(order.entity_id, "worker_locked", events)
		return
	# Resume must use a worker whose tag matches the building def's
	# built_by_tag — same constraint as new construction.
	if registry != null:
		var b_def: EntityDef = registry.get_by_id(building.current_def_id)
		if b_def != null and b_def.construction != null:
			var tag := b_def.construction.built_by_tag
			if tag != "" and not _worker_has_tag(worker, registry, tag):
				_emit_order_rejected(order.entity_id, "wrong_builder", events)
				return
	building.construction_worker_id = worker.id
	worker.locked_to_building_id = building.id
	GatherSystem.clear_assignment(worker)
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


static func _can_place_build_rect(
	state: MatchState, rect: Rect2i, allow_overlap_id: int = -1
) -> bool:
	if state == null or state.tile_grid == null:
		return false
	if allow_overlap_id < 0:
		return state.tile_grid.is_rect_clear(rect)
	if not state.tile_grid.is_rect_in_bounds(rect):
		return false
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var occupant_id: int = state.tile_grid.entity_at(Vector2i(x, y))
			if occupant_id != -1 and occupant_id != allow_overlap_id:
				return false
	for existing_id: int in state.tile_grid.all_placed_entity_ids():
		if existing_id == allow_overlap_id:
			continue
		var existing_rect: Rect2i = state.tile_grid.entity_rect(existing_id)
		if existing_rect.intersects(rect):
			return false
	return true


# RESEARCH handler — appends a queue declaration on the producer's
# ProductionState. Mirrors TRAIN but rejects research items the player
# has already unlocked. Plan node 05 chunk 4.
static func _handle_research_order(
	state: MatchState,
	entity: Entity,
	order: EntityOrder,
	registry: EntityRegistry,
	events: Array[ResolverEvent]
) -> void:
	if entity.production_state == null:
		_emit_order_rejected(order.entity_id, "not_a_producer", events)
		push_warning(
			"RESEARCH for entity %d which has no production capability; dropping." % order.entity_id
		)
		return
	if entity.is_constructing:
		_emit_order_rejected(order.entity_id, "producer_constructing", events)
		return
	if order.def_id == "":
		_emit_order_rejected(order.entity_id, "missing_def_id", events)
		return
	if registry != null:
		var producer_def: EntityDef = registry.get_by_id(entity.current_def_id)
		if (
			producer_def == null
			or producer_def.production == null
			or not producer_def.production.researches.has(order.def_id)
		):
			_emit_order_rejected(order.entity_id, "not_in_researches", events)
			return
	var player := state.get_player(entity.owner_player_id)
	if player != null and player.unlocked_researches.has(order.def_id):
		_emit_order_rejected(order.entity_id, "duplicate_research", events)
		return
	if _player_has_research_in_progress(state, entity.owner_player_id, order.def_id):
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


static func _player_has_research_in_progress(
	state: MatchState, owner_player_id: int, research_id: String
) -> bool:
	if research_id == "":
		return false
	for e in state.entities_sorted_by_id():
		if e == null or e.current_hp <= 0:
			continue
		if e.owner_player_id != owner_player_id:
			continue
		if e.production_state == null:
			continue
		var active: Dictionary = e.production_state.active
		if (
			not active.is_empty()
			and active.get(ProductionState.KEY_KIND, "") == ProductionState.KIND_RESEARCH
			and active.get(ProductionState.KEY_DEF_ID, "") == research_id
		):
			return true
		for item in e.production_state.queue:
			var queued: Dictionary = item
			if (
				queued.get(ProductionState.KEY_KIND, "") == ProductionState.KIND_RESEARCH
				and queued.get(ProductionState.KEY_DEF_ID, "") == research_id
			):
				return true
	return false


# TRAIN handler — appends a queue declaration on the producer's
# ProductionState. No cost is deducted here; ProductionSystem.try_fill
# does that at slot transition. Plan node 05 chunk 2.
static func _handle_train_order(
	entity: Entity, order: EntityOrder, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	if entity.production_state == null:
		_emit_order_rejected(order.entity_id, "not_a_producer", events)
		push_warning(
			"TRAIN for entity %d which has no production capability; dropping." % order.entity_id
		)
		return
	if entity.is_constructing:
		_emit_order_rejected(order.entity_id, "producer_constructing", events)
		return
	if order.def_id == "":
		_emit_order_rejected(order.entity_id, "missing_def_id", events)
		return
	if registry != null:
		var producer_def: EntityDef = registry.get_by_id(entity.current_def_id)
		if (
			producer_def == null
			or producer_def.production == null
			or not producer_def.production.produces.has(order.def_id)
		):
			_emit_order_rejected(order.entity_id, "not_in_produces", events)
			return
	entity.production_state.repeat_train_def_id = order.def_id
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


static func _handle_set_rally_order(
	state: MatchState,
	entity: Entity,
	order: EntityOrder,
	registry: EntityRegistry,
	events: Array[ResolverEvent]
) -> void:
	if entity.production_state == null:
		_emit_order_rejected(order.entity_id, "not_a_producer", events)
		return
	if order.mode == ProductionState.RALLY_MODE_NONE or order.mode == "":
		entity.production_state.rally_mode = ProductionState.RALLY_MODE_NONE
		entity.production_state.rally_target_tile = Vector2i.ZERO
		entity.production_state.rally_target_entity_id = -1
		return
	if order.mode == ProductionState.RALLY_MODE_MOVE:
		if (
			state == null
			or state.tile_grid == null
			or not state.tile_grid.is_in_bounds(order.target_tile)
		):
			_emit_order_rejected(order.entity_id, "bad_rally_tile", events)
			return
		entity.production_state.rally_mode = ProductionState.RALLY_MODE_MOVE
		entity.production_state.rally_target_tile = order.target_tile
		entity.production_state.rally_target_entity_id = -1
		return
	if order.mode == ProductionState.RALLY_MODE_GATHER:
		if (
			GatherSystem.rally_gather_source_for_producer(
				state, registry, entity, order.target_entity_id
			)
			== null
		):
			_emit_order_rejected(order.entity_id, "bad_rally_gather_target", events)
			return
		entity.production_state.rally_mode = ProductionState.RALLY_MODE_GATHER
		entity.production_state.rally_target_tile = Vector2i.ZERO
		entity.production_state.rally_target_entity_id = order.target_entity_id
		return
	_emit_order_rejected(order.entity_id, "bad_rally_mode", events)


static func _handle_repeat_train_toggle_order(
	entity: Entity, order: EntityOrder, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	if entity.production_state == null:
		_emit_order_rejected(order.entity_id, "not_a_producer", events)
		return
	if order.enabled:
		if order.def_id == "":
			_emit_order_rejected(order.entity_id, "missing_def_id", events)
			return
		if registry != null:
			var producer_def: EntityDef = registry.get_by_id(entity.current_def_id)
			if (
				producer_def == null
				or producer_def.production == null
				or not producer_def.production.produces.has(order.def_id)
			):
				_emit_order_rejected(order.entity_id, "not_in_produces", events)
				return
		entity.production_state.repeat_train_def_id = order.def_id
	entity.production_state.repeat_train_enabled = order.enabled


# CANCEL handler — splits the three semantic flavours per plan node 05:
#   cancel_index == -1: clear standing focus intent (and, in chunks 5/6,
#                       cancel a BUILD via the worker).
#   cancel_index == 0:  cancel the active production slot, refund the
#                       paid amounts. Queue head can install same turn
#                       (resolver runs try_fill after distribution).
#   cancel_index >= 1:  remove queue[cancel_index - 1]. No cost
#                       movement (queue items are unpaid).
static func _handle_cancel_order(
	state: MatchState,
	entity: Entity,
	order: EntityOrder,
	registry: EntityRegistry,
	events: Array[ResolverEvent]
) -> void:
	if order.cancel_index < 0:
		entity.focus_target_entity_id = -1
		# If the entity is a worker locked to an in-progress build,
		# cancel the build too: refund full cost, remove the building
		# entity, free the worker. Plan node 05 chunk 6.
		if ConstructionSystem.has_pending_build(entity):
			ConstructionSystem.cancel_pending_build(state, entity, registry, events)
		if entity.locked_to_building_id >= 0:
			_cancel_build_via_worker(state, entity, registry, events)
		return
	if order.cancel_index == 0:
		_cancel_active_production(state, entity, events)
		return
	_cancel_queued_production(entity, order.cancel_index, events)


static func _cancel_build_via_worker(
	state: MatchState, worker: Entity, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	var building := state.get_entity_by_id(worker.locked_to_building_id)
	worker.locked_to_building_id = -1
	if building == null or building.current_hp <= 0 or not building.is_constructing:
		return
	# Refund the cost. BUILD doesn't record paid_* fields (the cost is
	# always the def's mineral/gas/pop_cost since BUILD is eager-deduct
	# at distribution); read it back from the def.
	if registry != null:
		var def: EntityDef = registry.get_by_id(building.current_def_id)
		if def != null and def.construction != null:
			var player := state.get_player(building.owner_player_id)
			if player != null:
				player.minerals += def.construction.mineral_cost
				player.gas += def.construction.gas_cost
				if def.population != null:
					player.pop_used = max(0, player.pop_used - def.population.pop_cost)
	# Remove from grid.
	if state.tile_grid != null:
		state.tile_grid.remove(building.id)
	# Mark dead so subsequent code paths don't see it as live.
	building.current_hp = 0
	building.is_constructing = false
	building.construction_turns_remaining = -1
	building.construction_worker_id = -1
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.BUILD_CANCELLED
	ev.actor_id = building.id
	events.append(ev)


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
