class_name GatherSystem
extends RefCounted

# Worker gather pipeline — drives the IDLE → MOVING_TO_SOURCE → GATHERING
# loop on each entity with a non-null `gather_state`. Workers stay beside
# their assigned source and credit resources directly each gather tick.
#
# The resolver dispatches in two stages every tick:
#  - advance_move_phase (Phase 2 of the resolver loop): MOVING_TO_SOURCE
#    workers step toward their target one tile per tick; reaching the
#    target advances the FSM phase.
#  - advance_state_phase (after movement): GATHERING
#    yields a tick of resources from the source and credits the player's
#    pool immediately.
#
# Refinery gating: a GATHER order targeting a refinery (`extractor` tag)
# is translated to the underlying geyser. A geyser without a covering
# refinery yields no gather.

const _SOURCE_TYPE_MINERALS := "minerals"
const _SOURCE_TYPE_GAS := "gas"
const RALLY_GATHER_MAX_PATH_TILES := 12
# A resource is gatherable only while it sits within this many tiles
# (rect-to-rect chebyshev) of one of the owner's completed bases —
# rallying/gathering works from ANY owned base, and far-away resources
# stay invalid until a base is built nearby (plan m1/06 wave 3).
const GATHER_BASE_PROXIMITY_TILES := 10
const _PATHFINDING := preload("res://scripts/resolver/pathfinding_system.gd")
const _PRODUCTION := preload("res://scripts/resolver/production_system.gd")


# Phase 2 hook — called per tick alongside MOVE resolution.
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
	var source_assignments: Dictionary[int, Array] = _source_assignments_by_source(state, registry)
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
			_step_to_source(state, actor, registry, events, source_assignments)


# Phase 3 hook — called per tick after movement.
# GATHERING yields resources directly and decrements source capacity.
static func advance_state_phase(
	state: MatchState, registry: EntityRegistry, _tunables: Tunables, events: Array[ResolverEvent]
) -> void:
	var source_assignments: Dictionary[int, Array] = _source_assignments_by_source(state, registry)
	for actor in state.entities_sorted_by_id():
		if actor.current_hp <= 0:
			continue
		if actor.gather_state == null:
			continue
		var phase := actor.gather_state.phase
		if phase == GatherState.Phase.GATHERING:
			_tick_gather(state, actor, registry, events, source_assignments)


# ---------- Phase 2: travel ----------


static func _step_to_source(
	state: MatchState,
	actor: Entity,
	registry: EntityRegistry,
	events: Array[ResolverEvent],
	source_assignments: Dictionary[int, Array]
) -> void:
	var source: Entity = _resolve_source(
		state, registry, actor.gather_state.assigned_source_entity_id, actor.owner_player_id
	)
	if source == null:
		# Source destroyed / refinery missing — idle in place.
		clear_assignment(actor)
		return
	var assigned_source: Entity = best_source_for_worker(
		state, registry, actor, source, source_assignments
	)
	if assigned_source == null:
		clear_assignment(actor)
		return
	if assigned_source.id != source.id:
		actor.gather_state.assigned_source_entity_id = assigned_source.id
		replace_assignment_in_map(source_assignments, actor.id, assigned_source.id)
		source = assigned_source
	if _is_adjacent_to(state, actor, source):
		actor.gather_state.phase = GatherState.Phase.GATHERING
		return
	if not _can_step(actor, registry):
		return
	var source_rect: Rect2i = state.tile_grid.entity_rect(source.id)
	if source_rect.size == Vector2i.ZERO:
		return
	var step: Dictionary = (
		_PATHFINDING
		. find_next_step(
			state,
			actor,
			source_rect.position,
			registry,
			{
				_PATHFINDING.OPTION_GOAL_RECT: source_rect,
				_PATHFINDING.OPTION_GOAL_RANGE: 1,
				_PATHFINDING.OPTION_EXACT_ORIGIN: false,
			}
		)
	)
	if step.is_empty():
		return
	var new_origin: Vector2i = step.get("next_origin", actor.origin)
	if new_origin == actor.origin:
		return
	if state.tile_grid.move(actor.id, new_origin):
		var ev := ResolverEvent.new()
		ev.type = ResolverEvent.Type.ENTITY_MOVED
		ev.actor_id = actor.id
		ev.from_origin = actor.origin
		ev.to_origin = new_origin
		actor.origin = new_origin
		events.append(ev)
		actor.moves_used_this_turn += PathfindingSystem.step_cost(ev.from_origin, new_origin)
		# Re-check adjacency after the step so we transition the same tick
		# we land in range.
		if _is_adjacent_to(state, actor, source):
			actor.gather_state.phase = GatherState.Phase.GATHERING


# ---------- Phase 3: gather ticks ----------


static func _tick_gather(
	state: MatchState,
	actor: Entity,
	registry: EntityRegistry,
	events: Array[ResolverEvent],
	source_assignments: Dictionary[int, Array]
) -> void:
	var source: Entity = _resolve_source(
		state, registry, actor.gather_state.assigned_source_entity_id, actor.owner_player_id
	)
	if source == null:
		clear_assignment(actor)
		return
	if not _is_worker_within_source_cap(source_assignments, registry, actor, source):
		clear_assignment(actor)
		return
	# Range check — a fresh MOVE / nudged origin could leave the worker
	# in GATHERING phase while no longer next to the source. Don't drain
	# from afar; transition back into travel.
	if not _is_adjacent_to(state, actor, source):
		actor.gather_state.phase = GatherState.Phase.MOVING_TO_SOURCE
		return
	# Drain a tick from the source.
	var source_def: EntityDef = (
		registry.get_by_id(source.current_def_id) if registry != null else null
	)
	if source_def == null or source_def.resource_source == null:
		clear_assignment(actor)
		return
	var rsd: ResourceSourceDef = source_def.resource_source
	var yield_amount: int = rsd.yield_per_worker_per_turn * _worker_gather_rate(actor, registry)
	if yield_amount <= 0:
		# A misconfigured source with zero yield would loop the worker in
		# GATHERING forever.
		clear_assignment(actor)
		return
	# Already drained.
	if source.current_resource_amount == 0:
		clear_assignment(actor)
		return
	# Compute the actual harvest before mutating anything: cap by source
	# remaining (-1 = infinite).
	var actual_harvest: int = yield_amount
	if source.current_resource_amount > 0:
		actual_harvest = min(actual_harvest, source.current_resource_amount)
	if actual_harvest <= 0:
		clear_assignment(actor)
		return
	if source.current_resource_amount > 0:
		source.current_resource_amount -= actual_harvest
	var player: PlayerState = state.get_player(actor.owner_player_id)
	if player != null:
		if rsd.resource_type == _SOURCE_TYPE_MINERALS:
			player.minerals += actual_harvest
		elif rsd.resource_type == _SOURCE_TYPE_GAS:
			player.gas += actual_harvest
	actor.gather_state.carrying_amount = 0
	actor.gather_state.carrying_resource_type = ""
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
		clear_assignment(actor)
		return


# ---------- Helpers ----------


static func resolve_source_for_worker(
	state: MatchState, registry: EntityRegistry, target_entity_id: int, owner_id: int
) -> Entity:
	return _resolve_source(state, registry, target_entity_id, owner_id)


static func source_has_open_slot(
	state: MatchState, registry: EntityRegistry, source: Entity, actor_id: int = -1
) -> bool:
	var cap: int = source_gatherer_cap(registry, source)
	if cap <= 0:
		return false
	var source_assignments: Dictionary[int, Array] = _source_assignments_by_source(state, registry)
	return _assigned_gatherer_count_for_source(source_assignments, source.id, actor_id) < cap


static func best_source_for_worker(
	state: MatchState,
	registry: EntityRegistry,
	actor: Entity,
	requested_source: Entity,
	source_assignments: Dictionary[int, Array] = {},
	context: Variant = null
) -> Entity:
	return _best_source_for_worker(
		state, registry, actor, requested_source, source_assignments, -1, context
	)


static func best_rally_source_for_worker(
	state: MatchState,
	registry: EntityRegistry,
	actor: Entity,
	requested_source: Entity,
	source_assignments: Dictionary[int, Array] = {}
) -> Entity:
	return _best_source_for_worker(
		state, registry, actor, requested_source, source_assignments, RALLY_GATHER_MAX_PATH_TILES
	)


static func rally_gather_source_for_producer(
	state: MatchState, registry: EntityRegistry, producer: Entity, target_entity_id: int
) -> Entity:
	if state == null or registry == null or producer == null:
		return null
	var source: Entity = resolve_source_for_worker(
		state, registry, target_entity_id, producer.owner_player_id
	)
	if source == null:
		return null
	if not source_near_owned_base(state, registry, producer.owner_player_id, source):
		return null
	return source


static func _best_source_for_worker(
	state: MatchState,
	registry: EntityRegistry,
	actor: Entity,
	requested_source: Entity,
	source_assignments: Dictionary[int, Array],
	max_path_tiles: int,
	context: Variant = null
) -> Entity:
	if state == null or registry == null or actor == null or requested_source == null:
		return null
	var assignments: Dictionary[int, Array] = (
		source_assignments
		if not source_assignments.is_empty()
		else _source_assignments_by_source(state, registry)
	)
	if _source_is_available_to_worker(
		state, registry, actor, requested_source, assignments, max_path_tiles, context
	):
		return requested_source
	var requested_type: String = _resource_type_for_source(registry, requested_source)
	if requested_type == "":
		return null
	var best: Entity = null
	var best_distance: int = -1
	# The context caches the (small) resource-source list; without it we
	# fall back to scanning every entity. Either way each candidate is
	# re-validated through _resolve_source (depletion, extractors).
	var candidates: Array[Entity] = (
		context.resource_sources() if context is ResolveContext else state.entities_sorted_by_id()
	)
	for candidate in candidates:
		if candidate == null or candidate.id == requested_source.id:
			continue
		var source: Entity = _resolve_source(state, registry, candidate.id, actor.owner_player_id)
		if source == null or source.id != candidate.id:
			continue
		if _resource_type_for_source(registry, source) != requested_type:
			continue
		if not source_near_owned_base(state, registry, actor.owner_player_id, source):
			continue
		var distance: int = _path_distance_to_source(state, registry, actor, source, context)
		if distance < 0:
			continue
		if max_path_tiles >= 0 and distance > max_path_tiles:
			continue
		var cap: int = source_gatherer_cap(registry, source)
		if cap <= 0:
			continue
		if _assigned_gatherer_count_for_source(assignments, source.id, actor.id) >= cap:
			continue
		if (
			best == null
			or distance < best_distance
			or (distance == best_distance and source.id < best.id)
		):
			best = source
			best_distance = distance
	return best


static func replace_assignment_in_map(
	source_assignments: Dictionary[int, Array], actor_id: int, source_id: int
) -> void:
	for key in source_assignments.keys():
		var worker_ids: Array = source_assignments[key]
		worker_ids.erase(actor_id)
		source_assignments[key] = worker_ids
	if source_id < 0:
		return
	if not source_assignments.has(source_id):
		source_assignments[source_id] = []
	var assigned: Array = source_assignments[source_id]
	if not assigned.has(actor_id):
		assigned.append(actor_id)
	source_assignments[source_id] = assigned


static func source_gatherer_cap(registry: EntityRegistry, source: Entity) -> int:
	if registry == null or source == null:
		return 0
	var def: EntityDef = registry.get_by_id(source.current_def_id)
	if def == null or def.resource_source == null:
		return 0
	return max(0, def.resource_source.max_gatherers)


static func clear_assignment(actor: Entity) -> void:
	if actor == null or actor.gather_state == null:
		return
	actor.gather_state.phase = GatherState.Phase.IDLE
	actor.gather_state.assigned_source_entity_id = -1
	actor.gather_state.carrying_amount = 0
	actor.gather_state.carrying_resource_type = ""


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


static func _source_assignments_by_source(
	state: MatchState, registry: EntityRegistry
) -> Dictionary[int, Array]:
	var assignments: Dictionary[int, Array] = {}
	if state == null:
		return assignments
	for worker: Entity in state.entities_sorted_by_id():
		if worker == null or worker.current_hp <= 0:
			continue
		if worker.gather_state == null:
			continue
		var phase: int = worker.gather_state.phase
		if phase != GatherState.Phase.MOVING_TO_SOURCE and phase != GatherState.Phase.GATHERING:
			continue
		var assigned_source: Entity = _resolve_source(
			state, registry, worker.gather_state.assigned_source_entity_id, worker.owner_player_id
		)
		if assigned_source == null:
			continue
		if not assignments.has(assigned_source.id):
			assignments[assigned_source.id] = []
		var worker_ids: Array = assignments[assigned_source.id]
		worker_ids.append(worker.id)
	return assignments


static func _assigned_gatherer_count_for_source(
	source_assignments: Dictionary[int, Array], source_id: int, excluded_actor_id: int = -1
) -> int:
	var worker_ids: Array = source_assignments.get(source_id, [])
	var count: int = worker_ids.size()
	if excluded_actor_id >= 0 and worker_ids.has(excluded_actor_id):
		count -= 1
	return count


static func source_near_owned_base(
	state: MatchState,
	registry: EntityRegistry,
	owner_id: int,
	source: Entity,
	max_tiles: int = GATHER_BASE_PROXIMITY_TILES
) -> bool:
	if state == null or registry == null or source == null or state.tile_grid == null:
		return false
	var source_rect: Rect2i = state.tile_grid.entity_rect(source.id)
	if source_rect.size == Vector2i.ZERO:
		return false
	for entity in state.entities_sorted_by_id():
		if entity.owner_player_id != owner_id or entity.current_hp <= 0:
			continue
		if entity.is_constructing:
			continue
		var def: EntityDef = registry.get_by_id(entity.current_def_id)
		if def == null or def.id != "base":
			continue
		var base_rect: Rect2i = state.tile_grid.entity_rect(entity.id)
		if base_rect.size == Vector2i.ZERO:
			continue
		if TileGrid.distance_between_rects(source_rect, base_rect) <= max_tiles:
			return true
	return false


static func _source_is_available_to_worker(
	state: MatchState,
	registry: EntityRegistry,
	actor: Entity,
	source: Entity,
	source_assignments: Dictionary[int, Array],
	max_path_tiles: int = -1,
	context: Variant = null
) -> bool:
	var cap: int = source_gatherer_cap(registry, source)
	if cap <= 0:
		return false
	if _assigned_gatherer_count_for_source(source_assignments, source.id, actor.id) >= cap:
		return false
	if not source_near_owned_base(state, registry, actor.owner_player_id, source):
		return false
	var distance: int = _path_distance_to_source(state, registry, actor, source, context)
	if distance < 0:
		return false
	return max_path_tiles < 0 or distance <= max_path_tiles


static func _resource_type_for_source(registry: EntityRegistry, source: Entity) -> String:
	if registry == null or source == null:
		return ""
	var def: EntityDef = registry.get_by_id(source.current_def_id)
	if def == null or def.resource_source == null:
		return ""
	return def.resource_source.resource_type


static func _path_distance_to_source(
	state: MatchState,
	registry: EntityRegistry,
	actor: Entity,
	source: Entity,
	context: Variant = null
) -> int:
	if state == null or state.tile_grid == null or actor == null or source == null:
		return -1
	var actor_rect: Rect2i = _entity_rect_for_pathing(state, registry, actor)
	var source_rect: Rect2i = state.tile_grid.entity_rect(source.id)
	if actor_rect.size == Vector2i.ZERO or source_rect.size == Vector2i.ZERO:
		return -1
	if TileGrid.distance_between_rects(actor_rect, source_rect) <= 1:
		return 0
	var movement: MovementDef = _PATHFINDING.movement_def_for_entity(actor, registry)
	if movement == null:
		return -1
	if context is ResolveContext and actor_rect.size == Vector2i.ONE:
		# One shared flow field per source answers the distance for every
		# worker; replaces a per-worker per-source A* flood.
		var layer: String = _PATHFINDING.layer_for_entity(actor, registry)
		var key: String = _PATHFINDING.flow_field_key(
			layer, movement, source_rect.position, source_rect, 1, false
		)
		var grid: TileGrid = state.tile_grid
		var blockers: Dictionary = {
			"tiles": context.blocker_tiles(layer),
			"passable": context.mover_passable(),
			"terrain_blocked": context.terrain_blocked_tiles(movement),
		}
		var field: Dictionary = context.flow_field(
			key,
			func() -> Dictionary:
				return _PATHFINDING.build_flow_field(
					grid, movement, blockers, source_rect.position, source_rect, 1, false
				)
		)
		var field_distance: int = field.get(actor.origin, -1)
		if field_distance >= 0:
			return field_distance
		# The shared field can't bake per-worker passability, so the asking
		# worker's own tile may be missing (it blocks itself). Derive from
		# the best adjacent field value instead.
		var best: int = -1
		for delta in _PATHFINDING._NEIGHBORS:
			var neighbor_distance: Variant = field.get(actor.origin + delta)
			if neighbor_distance == null:
				continue
			if best < 0 or int(neighbor_distance) + 1 < best:
				best = int(neighbor_distance) + 1
		return best
	var options: Dictionary = {
		_PATHFINDING.OPTION_GOAL_RECT: source_rect,
		_PATHFINDING.OPTION_GOAL_RANGE: 1,
		_PATHFINDING.OPTION_EXACT_ORIGIN: false,
	}
	var path: Array[Vector2i] = _PATHFINDING.find_path(
		state, actor, source_rect.position, registry, options
	)
	return path.size() if not path.is_empty() else -1


static func _entity_rect_for_pathing(
	state: MatchState, registry: EntityRegistry, entity: Entity
) -> Rect2i:
	if state == null or entity == null:
		return Rect2i()
	if state.tile_grid != null:
		var placed_rect: Rect2i = state.tile_grid.entity_rect(entity.id)
		if placed_rect.size != Vector2i.ZERO:
			return placed_rect
	var footprint := Vector2i.ONE
	if registry != null:
		var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
		var def: EntityDef = registry.get_by_id(def_id)
		if def != null and def.footprint != Vector2i.ZERO:
			footprint = def.footprint
	return Rect2i(entity.origin, footprint)


static func _rally_worker_probe_for_producer(
	state: MatchState, registry: EntityRegistry, producer: Entity
) -> Entity:
	var producer_def_id: String = (
		producer.current_def_id if producer != null and producer.current_def_id != "" else ""
	)
	if producer_def_id == "" and producer != null:
		producer_def_id = producer.def_id
	var producer_def: EntityDef = (
		registry.get_by_id(producer_def_id) if registry != null and producer != null else null
	)
	if producer_def == null or producer_def.production == null:
		return null
	for def_id in producer_def.production.produces:
		var unit_def: EntityDef = registry.get_by_id(def_id) if registry != null else null
		if unit_def == null or unit_def.gather == null:
			continue
		var spawn_tile: Vector2i = _PRODUCTION.find_spawn_tile(state, registry, producer, unit_def)
		if spawn_tile == Vector2i(-1, -1):
			continue
		var probe := Entity.new()
		probe.id = -1000000 - producer.id
		probe.def_id = unit_def.id
		probe.current_def_id = unit_def.id
		probe.owner_player_id = producer.owner_player_id
		probe.origin = spawn_tile
		probe.current_hp = 1
		probe.current_layer = (
			unit_def.movement.default_layer
			if unit_def.movement != null and unit_def.movement.default_layer != ""
			else "ground"
		)
		return probe
	return null


static func _is_worker_within_source_cap(
	source_assignments: Dictionary[int, Array],
	registry: EntityRegistry,
	actor: Entity,
	source: Entity
) -> bool:
	var cap: int = source_gatherer_cap(registry, source)
	if cap <= 0:
		return false
	var rank: int = 0
	var worker_ids: Array = source_assignments.get(source.id, [])
	for worker_id: int in worker_ids:
		if worker_id == actor.id:
			return rank < cap
		rank += 1
	return false


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
	return (
		actor.moves_used_this_turn + PathfindingSystem.STEP_COST_ORTHOGONAL
		<= def.movement.speed_tiles_per_turn * PathfindingSystem.STEP_COST_ORTHOGONAL
	)


static func _worker_gather_rate(actor: Entity, registry: EntityRegistry) -> int:
	if registry == null:
		return 0
	var def: EntityDef = registry.get_by_id(actor.current_def_id)
	if def == null or def.gather == null:
		return 0
	return max(0, def.gather.gather_per_turn)
