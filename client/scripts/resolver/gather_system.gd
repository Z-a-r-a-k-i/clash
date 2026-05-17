class_name GatherSystem
extends RefCounted

# Worker gather pipeline — drives the IDLE → MOVING_TO_SOURCE → GATHERING
# → MOVING_TO_BASE → DEPOSITING → MOVING_TO_SOURCE loop on each entity
# with a non-null `gather_state`. Per plan/m0/04 + the brainstorming
# session: trip-cycle simulated, idle on invalidation, tag-driven sinks.
#
# The resolver dispatches in two stages every tick:
#  - advance_move_phase (Phase 2 of the resolver loop): MOVING_TO_SOURCE
#    and MOVING_TO_BASE workers step toward their target one tile per
#    tick; reaching the target advances the FSM phase.
#  - advance_state_phase (Phase 3, after persistent moves): GATHERING
#    yields a tick of resources from the source; DEPOSITING is instant
#    and credits the player's pool.
#
# Refinery gating: a GATHER order targeting a refinery (`extractor` tag)
# is translated to the underlying geyser. A geyser without a covering
# refinery yields no gather.

const _SOURCE_TYPE_MINERALS := "minerals"
const _SOURCE_TYPE_GAS := "gas"


# Phase 2 hook — called per tick alongside MOVE / ATTACK_MOVE resolution.
# Walks workers in their travel phases one step.
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
		if actor.gather_state == null:
			continue
		# A fresh per-tick order takes priority over auto-advance.
		if MovementSystem.has_fresh_order_at(per_entity, actor.id, tick):
			continue
		var phase := actor.gather_state.phase
		if phase == GatherState.Phase.MOVING_TO_SOURCE:
			_step_to_source(state, actor, registry, events)
		elif phase == GatherState.Phase.MOVING_TO_BASE:
			_step_to_base(state, actor, registry, events)


# Phase 3 hook — called per tick after persistent-move advance.
# GATHERING yields to cargo + decrements source capacity; DEPOSITING is
# instant and credits the player.
static func advance_state_phase(
	state: MatchState, registry: EntityRegistry, _tunables: Tunables, events: Array[ResolverEvent]
) -> void:
	for actor in state.entities_sorted_by_id():
		if actor.current_hp <= 0:
			continue
		if actor.gather_state == null:
			continue
		var phase := actor.gather_state.phase
		if phase == GatherState.Phase.GATHERING:
			_tick_gather(state, actor, registry, events)
		elif phase == GatherState.Phase.DEPOSITING:
			_tick_deposit(state, actor, registry, events)


# ---------- Phase 2: travel ----------


static func _step_to_source(
	state: MatchState, actor: Entity, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	var source := _resolve_source(
		state, registry, actor.gather_state.assigned_source_entity_id, actor.owner_player_id
	)
	if source == null:
		# Source destroyed / refinery missing — idle in place.
		actor.gather_state.phase = GatherState.Phase.IDLE
		return
	if _is_adjacent_to(state, actor, source):
		actor.gather_state.phase = GatherState.Phase.GATHERING
		return
	if not _can_step(actor, registry):
		return
	var target_tile := _approach_tile_for(state, source)
	if MovementSystem.step_toward(state, actor, target_tile, events):
		actor.moves_used_this_turn += 1
		# Re-check adjacency after the step so we transition the same tick
		# we land in range.
		if _is_adjacent_to(state, actor, source):
			actor.gather_state.phase = GatherState.Phase.GATHERING


static func _step_to_base(
	state: MatchState, actor: Entity, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	var sink := _nearest_deposit_sink(state, registry, actor)
	if sink == null:
		# No bases left — hold cargo, idle.
		actor.gather_state.phase = GatherState.Phase.IDLE
		return
	if _is_adjacent_to(state, actor, sink):
		actor.gather_state.phase = GatherState.Phase.DEPOSITING
		return
	if not _can_step(actor, registry):
		return
	var target_tile := _approach_tile_for(state, sink)
	if MovementSystem.step_toward(state, actor, target_tile, events):
		actor.moves_used_this_turn += 1
		if _is_adjacent_to(state, actor, sink):
			actor.gather_state.phase = GatherState.Phase.DEPOSITING


# ---------- Phase 3: gather + deposit ticks ----------


static func _tick_gather(
	state: MatchState, actor: Entity, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	var source := _resolve_source(
		state, registry, actor.gather_state.assigned_source_entity_id, actor.owner_player_id
	)
	if source == null:
		# Source went away mid-cycle — head back if we have cargo, idle if not.
		if actor.gather_state.carrying_amount > 0:
			actor.gather_state.phase = GatherState.Phase.MOVING_TO_BASE
		else:
			actor.gather_state.phase = GatherState.Phase.IDLE
		return
	# Range check — a fresh MOVE / nudged origin could leave the worker
	# in GATHERING phase while no longer next to the source. Don't drain
	# from afar; transition back into travel.
	if not _is_adjacent_to(state, actor, source):
		var carry_cap_now := _worker_carry_cap(actor, registry)
		if actor.gather_state.carrying_amount >= carry_cap_now and carry_cap_now > 0:
			actor.gather_state.phase = GatherState.Phase.MOVING_TO_BASE
		else:
			actor.gather_state.phase = GatherState.Phase.MOVING_TO_SOURCE
		return
	# Cargo full? Head back.
	var carry_cap := _worker_carry_cap(actor, registry)
	if actor.gather_state.carrying_amount >= carry_cap:
		actor.gather_state.phase = GatherState.Phase.MOVING_TO_BASE
		return
	# Drain a tick from the source.
	var source_def: EntityDef = (
		registry.get_by_id(source.current_def_id) if registry != null else null
	)
	if source_def == null or source_def.resource_source == null:
		actor.gather_state.phase = GatherState.Phase.IDLE
		return
	var rsd: ResourceSourceDef = source_def.resource_source
	var yield_amount: int = rsd.yield_per_worker_per_turn
	if yield_amount <= 0:
		# A misconfigured source with zero yield would loop the worker in
		# GATHERING forever. Bail out to MOVING_TO_BASE if we have cargo,
		# otherwise IDLE.
		if actor.gather_state.carrying_amount > 0:
			actor.gather_state.phase = GatherState.Phase.MOVING_TO_BASE
		else:
			actor.gather_state.phase = GatherState.Phase.IDLE
		return
	# Already drained? Head home with whatever cargo we have.
	if source.current_resource_amount == 0:
		if actor.gather_state.carrying_amount > 0:
			actor.gather_state.phase = GatherState.Phase.MOVING_TO_BASE
		else:
			actor.gather_state.phase = GatherState.Phase.IDLE
		return
	# Compute the actual harvest before mutating anything: cap by carry
	# space AND by source remaining (-1 = infinite). Doing it in one shot
	# keeps the source from being over-drained when carry_cap is the
	# binding constraint.
	var carry_remaining := carry_cap - actor.gather_state.carrying_amount
	var actual_harvest: int = min(yield_amount, carry_remaining)
	if source.current_resource_amount > 0:
		actual_harvest = min(actual_harvest, source.current_resource_amount)
	if actual_harvest <= 0:
		actor.gather_state.phase = GatherState.Phase.MOVING_TO_BASE
		return
	if source.current_resource_amount > 0:
		source.current_resource_amount -= actual_harvest
	actor.gather_state.carrying_amount += actual_harvest
	actor.gather_state.carrying_resource_type = rsd.resource_type
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.WORKER_GATHERED
	ev.actor_id = actor.id
	ev.target_id = source.id
	ev.amount = actual_harvest
	events.append(ev)
	# Did this tick deplete the source?
	if source.current_resource_amount == 0:
		var dep := ResolverEvent.new()
		dep.type = ResolverEvent.Type.RESOURCE_DEPLETED
		dep.target_id = source.id
		events.append(dep)
		actor.gather_state.phase = GatherState.Phase.MOVING_TO_BASE
		return
	# Carrying full? Head back.
	if actor.gather_state.carrying_amount >= carry_cap:
		actor.gather_state.phase = GatherState.Phase.MOVING_TO_BASE


static func _tick_deposit(
	state: MatchState, actor: Entity, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	var sink := _nearest_deposit_sink(state, registry, actor)
	if sink == null or not _is_adjacent_to(state, actor, sink):
		# Drifted out of range somehow; head back.
		actor.gather_state.phase = GatherState.Phase.MOVING_TO_BASE
		return
	var amount := actor.gather_state.carrying_amount
	var resource_type := actor.gather_state.carrying_resource_type
	if amount > 0:
		var player := state.get_player(actor.owner_player_id)
		if player != null:
			if resource_type == _SOURCE_TYPE_MINERALS:
				player.minerals += amount
			elif resource_type == _SOURCE_TYPE_GAS:
				player.gas += amount
		var ev := ResolverEvent.new()
		ev.type = ResolverEvent.Type.WORKER_DEPOSITED
		ev.actor_id = actor.id
		ev.target_id = sink.id
		ev.def_id = resource_type
		ev.amount = amount
		events.append(ev)
	actor.gather_state.carrying_amount = 0
	actor.gather_state.carrying_resource_type = ""
	# Loop back to the assigned source if it's still valid; otherwise idle.
	var source := _resolve_source(
		state, registry, actor.gather_state.assigned_source_entity_id, actor.owner_player_id
	)
	if source != null:
		actor.gather_state.phase = GatherState.Phase.MOVING_TO_SOURCE
	else:
		actor.gather_state.phase = GatherState.Phase.IDLE


# ---------- Helpers ----------


# Resolve a target entity id to a usable resource source. Handles
# refinery → underlying-geyser translation. Returns null if the source
# is gone, or if it's a geyser without a covering refinery owned by the
# worker. `owner_id` is the worker's `owner_player_id`: a refinery owned
# by another player does NOT enable gas extraction for this worker.
static func _resolve_source(
	state: MatchState, registry: EntityRegistry, target_entity_id: int, owner_id: int
) -> Entity:
	if target_entity_id < 0 or registry == null:
		return null
	var target := state.get_entity_by_id(target_entity_id)
	if target == null:
		return null
	var def: EntityDef = registry.get_by_id(target.current_def_id)
	if def == null:
		return null
	if state.tile_grid == null or state.tile_grid.entity_rect(target.id).size == Vector2i.ZERO:
		return null
	# Path 1: target IS a resource source.
	if def.resource_source != null:
		if target.current_resource_amount == 0:
			return null
		var rsd: ResourceSourceDef = def.resource_source
		if not rsd.requires_extractor:
			return target  # mineral patch, etc.
		# Geyser: only usable if a covering refinery owned by `owner_id`
		# exists.
		var extractor := _find_extractor_at(state, registry, target, owner_id)
		if extractor == null:
			return null
		return target
	if target.current_hp <= 0:
		return null
	# Path 2: target is a refinery (extractor) — translate to its geyser.
	# The refinery must belong to the worker.
	if def.tags.has("extractor"):
		if target.owner_player_id != owner_id:
			return null
		return _find_geyser_under(state, registry, target)
	return null


# Look for an entity owned by `owner_id` at the same tile as `geyser`
# carrying the `extractor` tag. The construction system places refineries
# on top of a geyser, so they share the same origin.
static func _find_extractor_at(
	state: MatchState, registry: EntityRegistry, geyser: Entity, owner_id: int
) -> Entity:
	if state.tile_grid == null:
		return null
	var geyser_rect := state.tile_grid.entity_rect(geyser.id)
	if geyser_rect.size == Vector2i.ZERO:
		return null
	for e in state.entities_sorted_by_id():
		if e.id == geyser.id or e.current_hp <= 0:
			continue
		if e.owner_player_id != owner_id:
			continue
		var def: EntityDef = registry.get_by_id(e.current_def_id) if registry != null else null
		if def == null or not def.tags.has("extractor"):
			continue
		var rect := state.tile_grid.entity_rect(e.id)
		if rect.size == Vector2i.ZERO:
			continue
		if rect.position == geyser_rect.position:
			return e
	return null


# Inverse of _find_extractor_at: given a refinery, find the geyser it
# was built on.
static func _find_geyser_under(
	state: MatchState, registry: EntityRegistry, refinery: Entity
) -> Entity:
	if state.tile_grid == null:
		return null
	var rect := state.tile_grid.entity_rect(refinery.id)
	if rect.size == Vector2i.ZERO:
		return null
	for e in state.entities_sorted_by_id():
		if e.id == refinery.id:
			continue
		var def: EntityDef = registry.get_by_id(e.current_def_id) if registry != null else null
		if def == null or def.resource_source == null:
			continue
		var rsd: ResourceSourceDef = def.resource_source
		if not rsd.requires_extractor:
			continue
		var er := state.tile_grid.entity_rect(e.id)
		if er.size != Vector2i.ZERO and er.position == rect.position:
			return e
	return null


# Nearest owned `deposit_sink` building. Ties broken by id (stable
# iteration order from `entities_sorted_by_id`).
static func _nearest_deposit_sink(
	state: MatchState, registry: EntityRegistry, worker: Entity
) -> Entity:
	if state.tile_grid == null or registry == null:
		return null
	var best: Entity = null
	var best_dist := -1
	var worker_rect := state.tile_grid.entity_rect(worker.id)
	if worker_rect.size == Vector2i.ZERO:
		return null
	for e in state.entities_sorted_by_id():
		if e.id == worker.id or e.current_hp <= 0:
			continue
		if e.owner_player_id != worker.owner_player_id:
			continue
		var def: EntityDef = registry.get_by_id(e.current_def_id)
		if def == null or not def.tags.has("deposit_sink"):
			continue
		var rect := state.tile_grid.entity_rect(e.id)
		if rect.size == Vector2i.ZERO:
			continue
		var d := TileGrid.distance_between_rects(worker_rect, rect)
		if d < 0:
			continue
		if best == null or d < best_dist:
			best = e
			best_dist = d
	return best


static func _is_adjacent_to(state: MatchState, a: Entity, b: Entity) -> bool:
	if state.tile_grid == null:
		return false
	var ar := state.tile_grid.entity_rect(a.id)
	var br := state.tile_grid.entity_rect(b.id)
	if ar.size == Vector2i.ZERO or br.size == Vector2i.ZERO:
		return false
	return TileGrid.distance_between_rects(ar, br) <= 1


# Approach a target rect: aim at its origin tile. _step_toward handles
# one-tile-at-a-time movement; once the worker becomes adjacent (rect
# distance ≤ 1) the FSM advances.
static func _approach_tile_for(state: MatchState, target: Entity) -> Vector2i:
	if state.tile_grid == null:
		return target.origin
	var target_rect: Rect2i = state.tile_grid.entity_rect(target.id)
	if target_rect.size == Vector2i.ZERO:
		return target.origin
	return target_rect.position


static func _can_step(actor: Entity, registry: EntityRegistry) -> bool:
	if registry == null:
		return false
	var def: EntityDef = registry.get_by_id(actor.current_def_id)
	if def == null or def.movement == null:
		return false
	return actor.moves_used_this_turn < def.movement.speed_tiles_per_turn


static func _worker_carry_cap(actor: Entity, registry: EntityRegistry) -> int:
	if registry == null:
		return 0
	var def: EntityDef = registry.get_by_id(actor.current_def_id)
	if def == null or def.gather == null:
		return 0
	return def.gather.carry_amount
