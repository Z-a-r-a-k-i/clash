class_name ProductionSystem
extends RefCounted

# Drives the active+queue production lifecycle for TRAIN / RESEARCH per
# plan node 05. BUILD lives in ConstructionSystem (different shape —
# worker locking, separate progress tracking).
#
# Two entry points:
#  - `try_fill_active_slots` — called from `_state_helpers` after order
#    distribution AND from `advance_queues` after a slot completes.
#    Promotes affordable queue heads into the active slot.
#  - `advance_queues` — EOT hook. Ticks each active slot, finalizes
#    completed ones (spawn unit / apply research), then runs another
#    try-fill so a freshly-emptied slot can immediately install the
#    next queued item the same turn.
#
# Lazy-deduct (per the brainstorming session): TRAIN/RESEARCH orders
# append to `queue` without paying. Cost is deducted at the moment the
# slot transition happens (idle slot + affordable head). Insufficient
# funds → stall (slot stays empty, queue waits, retry next turn).

# Bitmask values for PRODUCTION_STALLED.amount.
const STALL_MINERAL := 1
const STALL_GAS := 2
const STALL_POP := 4


# EOT hook. Called after combat / movement / gather and after
# ConstructionSystem.finalize_completed (so a building completing this
# turn can install its first queue item the same turn).
static func advance_queues(
	state: MatchState, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	# 1. Tick & finalize each active slot.
	for entity in state.entities_sorted_by_id():
		if entity.current_hp <= 0:
			continue
		if entity.production_state == null or entity.production_state.active.is_empty():
			continue
		var active := entity.production_state.active
		var remaining: int = active.get(ProductionState.KEY_TURNS_REMAINING, 0)
		if remaining > 0:
			remaining -= 1
			active[ProductionState.KEY_TURNS_REMAINING] = remaining
		# remaining can be 0 either because we just decremented to 0 OR
		# because a previous turn deferred a spawn (we leave 0 in place
		# while waiting for an adjacent tile to free up).
		if remaining <= 0:
			_finalize_active(state, registry, entity, events)
	# 2. Try to install queue heads into any empty active slots.
	try_fill_active_slots(state, registry, events)


# Promotes affordable queue heads into the active slot. Public — called
# from order distribution as well so an idle producer starts producing
# the same turn the order arrives.
static func try_fill_active_slots(
	state: MatchState, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	for entity in state.entities_sorted_by_id():
		if entity.current_hp <= 0:
			continue
		if entity.production_state == null:
			continue
		if not entity.production_state.active.is_empty():
			continue
		if (
			entity.production_state.queue.is_empty()
			and not _has_repeat_train_head(entity.production_state)
		):
			continue
		_try_fill_one(state, registry, entity, events)


# ---------- Internals ----------


static func _try_fill_one(
	state: MatchState, registry: EntityRegistry, producer: Entity, events: Array[ResolverEvent]
) -> void:
	var using_repeat: bool = producer.production_state.queue.is_empty()
	var head: Dictionary = (
		_repeat_train_head(producer.production_state)
		if using_repeat
		else producer.production_state.queue[0]
	)
	var def_id: String = head.get(ProductionState.KEY_DEF_ID, "")
	var kind: String = head.get(ProductionState.KEY_KIND, "")
	var costs := _lookup_costs(registry, def_id, kind)
	if costs.is_empty():
		# Bad def reference — drop the queue item; misconfigured data
		# shouldn't deadlock the producer.
		if using_repeat:
			producer.production_state.repeat_train_enabled = false
			producer.production_state.repeat_train_def_id = ""
		else:
			producer.production_state.queue.pop_front()
		push_warning(
			"ProductionSystem: queue item %s/%s has no resolvable cost; dropping." % [def_id, kind]
		)
		return
	var player := state.get_player(producer.owner_player_id)
	if player == null:
		if using_repeat:
			producer.production_state.repeat_train_enabled = false
		else:
			producer.production_state.queue.pop_front()
		return
	var stall_mask := _compute_stall_mask(player, costs)
	if stall_mask != 0:
		_emit_stalled_once(producer, def_id, stall_mask, events)
		return
	# Install: deduct, fill active, pop queue head.
	player.minerals -= costs["minerals"] as int
	player.gas -= costs["gas"] as int
	player.pop_used += costs["pop"] as int
	producer.production_state.active = {
		ProductionState.KEY_DEF_ID: def_id,
		ProductionState.KEY_KIND: kind,
		ProductionState.KEY_TURNS_REMAINING: costs["time"] as int,
		ProductionState.KEY_PAID_MINERALS: costs["minerals"] as int,
		ProductionState.KEY_PAID_GAS: costs["gas"] as int,
		ProductionState.KEY_PAID_POP: costs["pop"] as int,
	}
	if not using_repeat:
		producer.production_state.queue.pop_front()
	var ev := ResolverEvent.new()
	if kind == ProductionState.KIND_RESEARCH:
		ev.type = ResolverEvent.Type.RESEARCH_STARTED
	else:
		ev.type = ResolverEvent.Type.TRAIN_STARTED
	ev.actor_id = producer.id
	ev.def_id = def_id
	events.append(ev)


static func _has_repeat_train_head(production_state: ProductionState) -> bool:
	return (
		production_state != null
		and production_state.repeat_train_enabled
		and production_state.repeat_train_def_id != ""
	)


static func _repeat_train_head(production_state: ProductionState) -> Dictionary:
	if not _has_repeat_train_head(production_state):
		return {}
	return {
		ProductionState.KEY_DEF_ID: production_state.repeat_train_def_id,
		ProductionState.KEY_KIND: ProductionState.KIND_UNIT,
	}


# Returns {minerals, gas, pop, time} for the queue item, or empty Dict
# if the def can't be resolved.
static func _lookup_costs(registry: EntityRegistry, def_id: String, kind: String) -> Dictionary:
	if registry == null or def_id == "":
		return {}
	if kind == ProductionState.KIND_RESEARCH:
		var rd := registry.get_research_by_id(def_id)
		if rd == null:
			return {}
		return {
			"minerals": rd.mineral_cost,
			"gas": rd.gas_cost,
			"pop": 0,
			"time": rd.research_time_turns,
		}
	# KIND_UNIT (default).
	var ud := registry.get_by_id(def_id)
	if ud == null or ud.construction == null:
		return {}
	var pop_cost := 0
	if ud.population != null:
		pop_cost = ud.population.pop_cost
	return {
		"minerals": ud.construction.mineral_cost,
		"gas": ud.construction.gas_cost,
		"pop": pop_cost,
		"time": ud.construction.build_time_turns,
	}


static func _compute_stall_mask(player: PlayerState, costs: Dictionary) -> int:
	var mask := 0
	if player.minerals < (costs["minerals"] as int):
		mask |= STALL_MINERAL
	if player.gas < (costs["gas"] as int):
		mask |= STALL_GAS
	if player.pop_used + (costs["pop"] as int) > player.pop_cap:
		mask |= STALL_POP
	return mask


# Append PRODUCTION_STALLED for this producer once per turn. Scans the
# current events list for a prior STALLED with the same actor_id; if
# present, no-op. The events array is per-turn, so this gives the
# desired one-event-per-producer-per-turn behavior.
static func _emit_stalled_once(
	producer: Entity, def_id: String, mask: int, events: Array[ResolverEvent]
) -> void:
	for ev in events:
		if ev.type == ResolverEvent.Type.PRODUCTION_STALLED and ev.actor_id == producer.id:
			return
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.PRODUCTION_STALLED
	ev.actor_id = producer.id
	ev.def_id = def_id
	ev.amount = mask
	events.append(ev)


static func _finalize_active(
	state: MatchState, registry: EntityRegistry, producer: Entity, events: Array[ResolverEvent]
) -> void:
	var active: Dictionary = producer.production_state.active
	var def_id: String = active.get(ProductionState.KEY_DEF_ID, "")
	var kind: String = active.get(ProductionState.KEY_KIND, "")
	if kind == ProductionState.KIND_RESEARCH:
		_finalize_research(state, producer, def_id, events)
	else:
		_finalize_train(state, registry, producer, def_id, events)


static func _finalize_train(
	state: MatchState,
	registry: EntityRegistry,
	producer: Entity,
	def_id: String,
	events: Array[ResolverEvent]
) -> void:
	var unit_def := registry.get_by_id(def_id)
	if unit_def == null:
		# Bad def — drop the active slot so we don't deadlock.
		producer.production_state.active = {}
		return
	var spawn_tile := _find_spawn_tile(state, registry, producer, unit_def)
	if spawn_tile == Vector2i(-1, -1):
		# No adjacent tile free — defer. Keep active in place with
		# turns_remaining = 0 so we'll retry next turn.
		producer.production_state.active[ProductionState.KEY_TURNS_REMAINING] = 0
		_emit_spawn_deferred_once(producer, def_id, events)
		return
	var unit := _spawn_unit(state, unit_def, producer.owner_player_id, spawn_tile)
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.TRAIN_COMPLETED
	ev.actor_id = producer.id
	ev.target_id = unit.id
	ev.def_id = def_id
	events.append(ev)
	producer.production_state.active = {}


static func _finalize_research(
	state: MatchState, producer: Entity, def_id: String, events: Array[ResolverEvent]
) -> void:
	var player := state.get_player(producer.owner_player_id)
	if player != null and not player.unlocked_researches.has(def_id):
		player.unlocked_researches.append(def_id)
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.RESEARCH_COMPLETED
	ev.actor_id = producer.id
	ev.def_id = def_id
	events.append(ev)
	producer.production_state.active = {}


# Find the first free tile adjacent to `producer`'s footprint by walking
# the perimeter clockwise from the top-left corner. Returns
# Vector2i(-1, -1) if none.
static func _find_spawn_tile(
	state: MatchState, registry: EntityRegistry, producer: Entity, unit_def: EntityDef
) -> Vector2i:
	if state.tile_grid == null:
		return Vector2i(-1, -1)
	var rect := state.tile_grid.entity_rect(producer.id)
	if rect.size == Vector2i.ZERO:
		# Fallback to producer.origin + footprint.
		var fp := Vector2i.ONE
		if registry != null:
			var pd := registry.get_by_id(producer.current_def_id)
			if pd != null and pd.footprint != Vector2i.ZERO:
				fp = pd.footprint
		rect = Rect2i(producer.origin, fp)
	var unit_fp := Vector2i.ONE
	if unit_def.footprint != Vector2i.ZERO:
		unit_fp = unit_def.footprint
	# Perimeter walk: top edge L→R, right edge T→B, bottom edge R→L,
	# left edge B→T. Each candidate tile is the would-be unit origin.
	var candidates: Array[Vector2i] = []
	var top := rect.position.y - unit_fp.y
	var bottom := rect.position.y + rect.size.y
	var left := rect.position.x - unit_fp.x
	var right := rect.position.x + rect.size.x
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		candidates.append(Vector2i(x, top))
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		candidates.append(Vector2i(right, y))
	for x in range(rect.position.x + rect.size.x - 1, rect.position.x - 1, -1):
		candidates.append(Vector2i(x, bottom))
	for y in range(rect.position.y + rect.size.y - 1, rect.position.y - 1, -1):
		candidates.append(Vector2i(left, y))
	# Also include the four corners diagonally adjacent.
	candidates.append(Vector2i(left, top))
	candidates.append(Vector2i(right, top))
	candidates.append(Vector2i(right, bottom))
	candidates.append(Vector2i(left, bottom))
	for tile in candidates:
		var unit_rect := Rect2i(tile, unit_fp)
		if (
			state.tile_grid.is_rect_in_bounds(unit_rect)
			and state.tile_grid.is_rect_clear(unit_rect)
		):
			return tile
	return Vector2i(-1, -1)


static func _spawn_unit(
	state: MatchState, unit_def: EntityDef, owner: int, origin: Vector2i
) -> Entity:
	var e := Entity.new()
	e.id = state.allocate_entity_id()
	e.def_id = unit_def.id
	e.current_def_id = unit_def.id
	e.owner_player_id = owner
	e.origin = origin
	e.current_layer = unit_def.movement.default_layer if unit_def.movement != null else "ground"
	if unit_def.health != null:
		e.current_hp = unit_def.health.max_hp
	# Capability-paired runtime state.
	if unit_def.production != null:
		e.production_state = ProductionState.new()
	if unit_def.gather != null:
		e.gather_state = GatherState.new()
	state.entities.append(e)
	var fp := unit_def.footprint if unit_def.footprint != Vector2i.ZERO else Vector2i.ONE
	if state.tile_grid != null:
		state.tile_grid.place(e.id, Rect2i(origin, fp))
	return e


# Same dedup pattern as PRODUCTION_STALLED — at most one SPAWN_DEFERRED
# per producer per turn.
static func _emit_spawn_deferred_once(
	producer: Entity, def_id: String, events: Array[ResolverEvent]
) -> void:
	for ev in events:
		if ev.type == ResolverEvent.Type.SPAWN_DEFERRED and ev.actor_id == producer.id:
			return
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.SPAWN_DEFERRED
	ev.actor_id = producer.id
	ev.def_id = def_id
	events.append(ev)
