class_name PathfindingSystem
extends RefCounted

# Deterministic A* pathfinding over entity origins. Paths contain origins
# after the actor's current origin; the caller owns movement commitment.

const OPTION_PASSABLE_ENTITY_IDS := "passable_entity_ids"
const OPTION_KNOWN_ENTITY_IDS := "known_entity_ids"
const OPTION_GOAL_RECT := "goal_rect"
const OPTION_GOAL_RANGE := "goal_range"
const OPTION_EXACT_ORIGIN := "exact_origin"

const _NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
]


static func find_path(
	state: MatchState,
	actor: Entity,
	target_origin: Vector2i,
	registry: EntityRegistry,
	options: Dictionary = {}
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if state == null or actor == null or registry == null or state.tile_grid == null:
		return out
	if actor.current_hp <= 0:
		return out
	var footprint: Vector2i = entity_footprint(state, actor, registry)
	if footprint.x <= 0 or footprint.y <= 0:
		return out
	var movement: MovementDef = movement_def_for_entity(actor, registry)
	if movement == null:
		return out

	var goal_rect: Rect2i = options.get(OPTION_GOAL_RECT, Rect2i(target_origin, footprint))
	var goal_range: int = options.get(OPTION_GOAL_RANGE, 0)
	var exact_origin: bool = options.get(OPTION_EXACT_ORIGIN, true)
	var passable_entity_ids: Dictionary = _id_set(options.get(OPTION_PASSABLE_ENTITY_IDS, {}))
	var known_entity_ids: Dictionary = _id_set(options.get(OPTION_KNOWN_ENTITY_IDS, {}))

	var start: Vector2i = actor.origin
	if _is_goal(start, footprint, target_origin, goal_rect, goal_range, exact_origin):
		return out

	var open: Array[Dictionary] = []
	var start_key: String = _key(start)
	var g_score: Dictionary = {start_key: 0}
	var came_from: Dictionary = {}
	var reached: Dictionary = {start_key: start}
	var closed: Dictionary = {}
	open.append(
		_node(
			start,
			0,
			_heuristic(start, footprint, target_origin, goal_rect, exact_origin),
			_manhattan_distance(start, footprint, target_origin, goal_rect, exact_origin)
		)
	)

	var best_origin: Vector2i = start
	var best_distance: int = _goal_distance(
		start, footprint, target_origin, goal_rect, exact_origin
	)
	var best_manhattan: int = _manhattan_distance(
		start, footprint, target_origin, goal_rect, exact_origin
	)
	var best_cost: int = 0

	while not open.is_empty():
		open.sort_custom(_node_less)
		var current_node: Dictionary = open.pop_front()
		var current: Vector2i = current_node["origin"]
		var current_key: String = _key(current)
		if closed.has(current_key):
			continue
		closed[current_key] = true

		var current_cost: int = g_score.get(current_key, 0)
		var current_distance: int = _goal_distance(
			current, footprint, target_origin, goal_rect, exact_origin
		)
		var current_manhattan: int = _manhattan_distance(
			current, footprint, target_origin, goal_rect, exact_origin
		)
		if _is_better_reachable(
			current,
			current_distance,
			current_manhattan,
			current_cost,
			best_origin,
			best_distance,
			best_manhattan,
			best_cost
		):
			best_origin = current
			best_distance = current_distance
			best_manhattan = current_manhattan
			best_cost = current_cost
		if _is_goal(current, footprint, target_origin, goal_rect, goal_range, exact_origin):
			return _reconstruct_path(came_from, reached, current_key)

		for delta in _NEIGHBORS:
			var next: Vector2i = current + delta
			var next_key: String = _key(next)
			if closed.has(next_key):
				continue
			if not can_occupy_origin(
				state, actor, next, registry, passable_entity_ids, known_entity_ids
			):
				continue
			var tentative_cost: int = current_cost + 1
			if g_score.has(next_key) and tentative_cost >= int(g_score[next_key]):
				continue
			came_from[next_key] = current_key
			reached[next_key] = next
			g_score[next_key] = tentative_cost
			var h: int = _heuristic(next, footprint, target_origin, goal_rect, exact_origin)
			var m: int = _manhattan_distance(
				next, footprint, target_origin, goal_rect, exact_origin
			)
			open.append(_node(next, tentative_cost, h, m))

	if best_origin == start:
		return out
	return _reconstruct_path(came_from, reached, _key(best_origin))


static func can_occupy_origin(
	state: MatchState,
	actor: Entity,
	origin: Vector2i,
	registry: EntityRegistry,
	passable_entity_ids: Dictionary = {},
	known_entity_ids: Dictionary = {}
) -> bool:
	if state == null or actor == null or state.tile_grid == null or registry == null:
		return false
	var footprint: Vector2i = entity_footprint(state, actor, registry)
	var rect := Rect2i(origin, footprint)
	if not state.tile_grid.is_rect_in_bounds(rect):
		return false
	var movement: MovementDef = movement_def_for_entity(actor, registry)
	if movement == null:
		return false
	if not _terrain_allows_rect(state.tile_grid, rect, movement):
		return false
	var actor_layer: String = layer_for_entity(actor, registry)
	for entity in state.entities_sorted_by_id():
		if entity == null or entity.id == actor.id:
			continue
		if not known_entity_ids.is_empty() and not known_entity_ids.has(entity.id):
			continue
		if passable_entity_ids.has(entity.id):
			continue
		if not _is_spatial_blocker(entity, registry):
			continue
		if layer_for_entity(entity, registry) != actor_layer:
			continue
		var other_rect: Rect2i = state.tile_grid.entity_rect(entity.id)
		if other_rect.size.x <= 0 or other_rect.size.y <= 0:
			continue
		if other_rect.intersects(rect):
			return false
	return true


static func entity_footprint(
	state: MatchState, entity: Entity, registry: EntityRegistry
) -> Vector2i:
	if state != null and state.tile_grid != null and entity != null:
		var placed_rect: Rect2i = state.tile_grid.entity_rect(entity.id)
		if placed_rect.size.x > 0 and placed_rect.size.y > 0:
			return placed_rect.size
	var def: EntityDef = entity_def_for_entity(entity, registry)
	if def != null and def.footprint != Vector2i.ZERO:
		return def.footprint
	return Vector2i.ONE


static func entity_def_for_entity(entity: Entity, registry: EntityRegistry) -> EntityDef:
	if entity == null or registry == null:
		return null
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	return registry.get_by_id(def_id)


static func movement_def_for_entity(entity: Entity, registry: EntityRegistry) -> MovementDef:
	var def: EntityDef = entity_def_for_entity(entity, registry)
	return def.movement if def != null else null


static func layer_for_entity(entity: Entity, registry: EntityRegistry) -> String:
	if entity == null:
		return "ground"
	if entity.current_layer != "":
		return entity.current_layer
	var movement: MovementDef = movement_def_for_entity(entity, registry)
	if movement != null and movement.default_layer != "":
		return movement.default_layer
	var def: EntityDef = entity_def_for_entity(entity, registry)
	if def != null and def.tags.has("flying"):
		return "flying"
	return "ground"


static func _node(origin: Vector2i, cost: int, heuristic: int, manhattan: int) -> Dictionary:
	return {
		"origin": origin,
		"g": cost,
		"h": heuristic,
		"m": manhattan,
		"f": cost + heuristic,
	}


static func _node_less(a: Dictionary, b: Dictionary) -> bool:
	var af: int = a.get("f", 0)
	var bf: int = b.get("f", 0)
	if af != bf:
		return af < bf
	var ah: int = a.get("h", 0)
	var bh: int = b.get("h", 0)
	if ah != bh:
		return ah < bh
	var am: int = a.get("m", 0)
	var bm: int = b.get("m", 0)
	if am != bm:
		return am < bm
	var ag: int = a.get("g", 0)
	var bg: int = b.get("g", 0)
	if ag != bg:
		return ag < bg
	var ao: Vector2i = a.get("origin", Vector2i.ZERO)
	var bo: Vector2i = b.get("origin", Vector2i.ZERO)
	if ao.y != bo.y:
		return ao.y < bo.y
	return ao.x < bo.x


static func _heuristic(
	origin: Vector2i,
	footprint: Vector2i,
	target_origin: Vector2i,
	goal_rect: Rect2i,
	exact_origin: bool
) -> int:
	if exact_origin:
		return max(abs(origin.x - target_origin.x), abs(origin.y - target_origin.y))
	return TileGrid.distance_between_rects(Rect2i(origin, footprint), goal_rect)


static func _goal_distance(
	origin: Vector2i,
	footprint: Vector2i,
	target_origin: Vector2i,
	goal_rect: Rect2i,
	exact_origin: bool
) -> int:
	if exact_origin:
		return max(abs(origin.x - target_origin.x), abs(origin.y - target_origin.y))
	return TileGrid.distance_between_rects(Rect2i(origin, footprint), goal_rect)


static func _manhattan_distance(
	origin: Vector2i,
	footprint: Vector2i,
	target_origin: Vector2i,
	goal_rect: Rect2i,
	exact_origin: bool
) -> int:
	if exact_origin:
		return abs(origin.x - target_origin.x) + abs(origin.y - target_origin.y)
	var rect := Rect2i(origin, footprint)
	var rect_x2: int = rect.position.x + rect.size.x - 1
	var rect_y2: int = rect.position.y + rect.size.y - 1
	var goal_x2: int = goal_rect.position.x + goal_rect.size.x - 1
	var goal_y2: int = goal_rect.position.y + goal_rect.size.y - 1
	var dx := 0
	if rect_x2 < goal_rect.position.x:
		dx = goal_rect.position.x - rect_x2
	elif goal_x2 < rect.position.x:
		dx = rect.position.x - goal_x2
	var dy := 0
	if rect_y2 < goal_rect.position.y:
		dy = goal_rect.position.y - rect_y2
	elif goal_y2 < rect.position.y:
		dy = rect.position.y - goal_y2
	return dx + dy


static func _is_goal(
	origin: Vector2i,
	footprint: Vector2i,
	target_origin: Vector2i,
	goal_rect: Rect2i,
	goal_range: int,
	exact_origin: bool
) -> bool:
	if exact_origin:
		return origin == target_origin
	return TileGrid.distance_between_rects(Rect2i(origin, footprint), goal_rect) <= goal_range


static func _is_better_reachable(
	origin: Vector2i,
	distance: int,
	manhattan: int,
	cost: int,
	best_origin: Vector2i,
	best_distance: int,
	best_manhattan: int,
	best_cost: int
) -> bool:
	if distance != best_distance:
		return distance < best_distance
	if manhattan != best_manhattan:
		return manhattan < best_manhattan
	if cost != best_cost:
		return cost < best_cost
	if origin.y != best_origin.y:
		return origin.y < best_origin.y
	return origin.x < best_origin.x


static func _reconstruct_path(
	came_from: Dictionary, reached: Dictionary, end_key: String
) -> Array[Vector2i]:
	var reversed: Array[Vector2i] = []
	var current_key: String = end_key
	while came_from.has(current_key):
		reversed.append(reached[current_key])
		current_key = came_from[current_key]
	reversed.reverse()
	return reversed


static func _terrain_allows_rect(grid: TileGrid, rect: Rect2i, movement: MovementDef) -> bool:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var tags: Array[String] = grid.tile_terrain_tags(Vector2i(x, y))
			for blocked_tag in movement.impassable_terrain_tags:
				if tags.has(blocked_tag):
					return false
			if not movement.pathable_terrain_tags.is_empty():
				var has_pathable_tag := false
				for allowed_tag in movement.pathable_terrain_tags:
					if tags.has(allowed_tag):
						has_pathable_tag = true
						break
				if not has_pathable_tag:
					return false
	return true


static func _is_spatial_blocker(entity: Entity, registry: EntityRegistry) -> bool:
	if entity == null:
		return false
	var def: EntityDef = entity_def_for_entity(entity, registry)
	if def != null and def.resource_source != null:
		return true
	return entity.current_hp > 0


static func _id_set(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if value is Dictionary:
		var dict: Dictionary = value
		for key in dict.keys():
			out[int(key)] = true
	elif value is Array:
		var arr: Array = value
		for item in arr:
			out[int(item)] = true
	return out


static func _key(origin: Vector2i) -> String:
	return "%d,%d" % [origin.x, origin.y]
