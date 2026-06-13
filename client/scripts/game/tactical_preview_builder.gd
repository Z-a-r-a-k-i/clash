class_name TacticalPreviewBuilder
extends RefCounted

const PATHFINDING_SCRIPT := preload("res://scripts/resolver/pathfinding_system.gd")
const MOVEMENT_SYSTEM_SCRIPT := preload("res://scripts/resolver/movement_system.gd")
const NO_STOP_TILE := Vector2i(-999999, -999999)
const MAX_PREVIEW_TURN_STOPS := 16


func attack_range_tiles(
	state: MatchState, registry: EntityRegistry, entity_id: int
) -> Array[Vector2i]:
	var actor: Entity = state.get_entity_by_id(entity_id) if state != null else null
	if actor == null:
		return []
	return attack_range_tiles_from_origin(state, registry, entity_id, actor.origin)


func attack_range_tiles_from_origin(
	state: MatchState, registry: EntityRegistry, entity_id: int, origin: Vector2i
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if state == null or state.tile_grid == null or registry == null:
		return out
	var actor: Entity = state.get_entity_by_id(entity_id)
	if actor == null or actor.current_hp <= 0:
		return out
	var def: EntityDef = PATHFINDING_SCRIPT.entity_def_for_entity(actor, registry)
	if def == null or def.combat == null or def.combat.attack_range < 0:
		return out
	var footprint: Vector2i = PATHFINDING_SCRIPT.entity_footprint(state, actor, registry)
	if footprint.x <= 0 or footprint.y <= 0:
		return out
	var actor_rect := Rect2i(origin, footprint)
	if not state.tile_grid.is_rect_in_bounds(actor_rect):
		return out
	var placed_rect: Rect2i = state.tile_grid.entity_rect(entity_id)
	var attack_range: int = def.combat.attack_range
	var min_x: int = maxi(0, actor_rect.position.x - attack_range)
	var min_y: int = maxi(0, actor_rect.position.y - attack_range)
	var max_x: int = mini(
		state.tile_grid.width - 1, actor_rect.position.x + actor_rect.size.x - 1 + attack_range
	)
	var max_y: int = mini(
		state.tile_grid.height - 1, actor_rect.position.y + actor_rect.size.y - 1 + attack_range
	)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var tile := Vector2i(x, y)
			if actor_rect.has_point(tile) or placed_rect.has_point(tile):
				continue
			if (
				TileGrid.distance_between_rects(actor_rect, Rect2i(tile, Vector2i.ONE))
				<= attack_range
			):
				out.append(tile)
	return out


# Every per-turn stop along `path`, in order; the final element is the
# last reachable tile (the destination when the budget allows). The first
# turn honors budget already spent this turn (moves_used_this_turn and a
# shot via `fired_this_turn`); later turns assume a fresh, unfired
# budget. An exhausted first turn yields a stop at the current position —
# unlike turn_stop_tile_for_path, which reports NO_STOP_TILE for "cannot
# move this turn".
func turn_stops_for_path(
	state: MatchState,
	registry: EntityRegistry,
	entity_id: int,
	path: Array,
	fired_this_turn: bool = false,
	max_stops: int = MAX_PREVIEW_TURN_STOPS
) -> Array[Vector2i]:
	var stops: Array[Vector2i] = []
	if state == null or registry == null or path.is_empty():
		return stops
	var actor: Entity = state.get_entity_by_id(entity_id)
	if actor == null or actor.current_hp <= 0:
		return stops
	var full_budget: int = (
		MOVEMENT_SYSTEM_SCRIPT.movement_budget_for_entity(actor, registry, false)
		* PATHFINDING_SCRIPT.STEP_COST_ORTHOGONAL
	)
	if full_budget < PATHFINDING_SCRIPT.STEP_COST_ORTHOGONAL:
		return stops
	var remaining: int = (
		(
			MOVEMENT_SYSTEM_SCRIPT.movement_budget_for_entity(actor, registry, fired_this_turn)
			* PATHFINDING_SCRIPT.STEP_COST_ORTHOGONAL
		)
		- actor.moves_used_this_turn
	)
	var current: Vector2i = actor.origin
	for item in path:
		var next: Vector2i = item
		var cost: int = PATHFINDING_SCRIPT.step_cost(current, next)
		if cost > full_budget:
			break
		if cost > remaining:
			if stops.size() >= max_stops:
				return stops
			stops.append(current)
			remaining = full_budget
		remaining -= cost
		current = next
	if (
		current != actor.origin
		and stops.size() < max_stops
		and (stops.is_empty() or stops.back() != current)
	):
		stops.append(current)
	return stops


func turn_stop_tile_for_path(
	state: MatchState,
	registry: EntityRegistry,
	entity_id: int,
	path: Array,
	fired_this_turn: bool = false
) -> Vector2i:
	if state == null or registry == null or path.is_empty():
		return NO_STOP_TILE
	var actor: Entity = state.get_entity_by_id(entity_id)
	if actor == null or actor.current_hp <= 0:
		return NO_STOP_TILE
	var movement_budget: int = MOVEMENT_SYSTEM_SCRIPT.movement_budget_for_entity(
		actor, registry, fired_this_turn
	)
	# Budgets are tile counts; consumption is octile cost units.
	var remaining: int = (
		movement_budget * PATHFINDING_SCRIPT.STEP_COST_ORTHOGONAL - actor.moves_used_this_turn
	)
	if remaining < PATHFINDING_SCRIPT.STEP_COST_ORTHOGONAL:
		return NO_STOP_TILE
	var current: Vector2i = actor.origin
	var stop_tile: Vector2i = NO_STOP_TILE
	for item in path:
		var next: Vector2i = item
		var cost: int = PATHFINDING_SCRIPT.step_cost(current, next)
		if cost > remaining:
			break
		remaining -= cost
		current = next
		stop_tile = next
	return stop_tile
