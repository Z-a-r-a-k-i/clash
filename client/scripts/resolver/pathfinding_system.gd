class_name PathfindingSystem
extends RefCounted

# Deterministic A* pathfinding over entity origins. Paths contain origins
# after the actor's current origin; the caller owns movement commitment.

const OPTION_PASSABLE_ENTITY_IDS := "passable_entity_ids"
const OPTION_KNOWN_ENTITY_IDS := "known_entity_ids"
const OPTION_GOAL_RECT := "goal_rect"
const OPTION_GOAL_RANGE := "goal_range"
const OPTION_EXACT_ORIGIN := "exact_origin"
const OPTION_OCCUPANCY_BLOCKERS := "occupancy_blockers"
const OPTION_COMPLETE_BLOCKED_AT_CURRENT := "complete_blocked_at_current"
# Movers-only id set for exact-target completion checks: with friendly
# pass-through, allies are passable for ROUTING but an exact MOVE target
# occupied by a stationary ally must still complete-adjacent instead of
# walking into it forever.
const OPTION_MOVER_IDS := "mover_ids"
const OPTION_MAX_EXPANSIONS := "max_expansions"
const OPTION_PROFILE := "_profile"

# Integer octile step costs: diagonals cover ~1.41x the distance of an
# orthogonal step, so they cost 1.5x (3 vs 2). Movement budgets are
# tracked in these cost units (speed_tiles_per_turn * STEP_COST_ORTHOGONAL
# per turn); path distances from A* and flow fields use them too, so
# conflict resolution compares like with like.
const STEP_COST_ORTHOGONAL := 2
const STEP_COST_DIAGONAL := 3

# A* expansion budget: generous for normal paths, but prevents the
# unreachable-goal worst case from flooding the entire map per call.
const _EXPANSION_CAP_PER_DISTANCE := 4
const _EXPANSION_CAP_BASE := 64

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
	var profile: Variant = options.get(OPTION_PROFILE, null)
	var actor_layer: String = layer_for_entity(actor, registry)
	var occupancy_blockers: Dictionary = options.get(OPTION_OCCUPANCY_BLOCKERS, {})
	if occupancy_blockers.is_empty():
		var passable_entity_ids: Dictionary = _id_set(options.get(OPTION_PASSABLE_ENTITY_IDS, {}))
		var known_entity_ids: Dictionary = _id_set(options.get(OPTION_KNOWN_ENTITY_IDS, {}))
		occupancy_blockers = _occupancy_blockers(
			state, actor, registry, actor_layer, passable_entity_ids, known_entity_ids
		)

	var start: Vector2i = actor.origin
	if _is_goal(start, footprint, target_origin, goal_rect, goal_range, exact_origin):
		return out
	var exact_target_blocked := (
		exact_origin
		and not _can_occupy_origin_with_blockers(
			state.tile_grid, target_origin, footprint, movement, occupancy_blockers
		)
	)

	var grid_width: int = max(1, state.tile_grid.width)
	var open: Array[Dictionary] = []
	var start_key: int = _key(start, grid_width)
	var g_score: Dictionary = {start_key: 0}
	var came_from: Dictionary = {}
	var reached: Dictionary = {start_key: start}
	var closed: Dictionary = {}
	_heap_push_open(
		open,
		_node(
			start,
			0,
			_heuristic(start, footprint, target_origin, goal_rect, goal_range, exact_origin),
			_manhattan_distance(
				start, footprint, target_origin, goal_rect, goal_range, exact_origin
			)
		)
	)

	var best_origin: Vector2i = start
	var best_distance: int = _goal_distance(
		start, footprint, target_origin, goal_rect, goal_range, exact_origin
	)
	var best_manhattan: int = _manhattan_distance(
		start, footprint, target_origin, goal_rect, goal_range, exact_origin
	)
	var best_cost: int = 0
	var expanded_nodes := 0
	# Generous enough for long walled detours (scales with the map), but
	# still prevents the unreachable-goal worst case from flooding the
	# entire grid several times over.
	var max_expansions: int = options.get(
		OPTION_MAX_EXPANSIONS,
		maxi(
			_EXPANSION_CAP_PER_DISTANCE * best_distance + _EXPANSION_CAP_BASE,
			grid_width * state.tile_grid.height / 2
		)
	)

	while not open.is_empty():
		var current_node: Dictionary = _heap_pop_open(open)
		var current: Vector2i = current_node["origin"]
		var current_key: int = _key(current, grid_width)
		if closed.has(current_key):
			continue
		closed[current_key] = true
		expanded_nodes += 1
		if expanded_nodes > max_expansions:
			_count_profile(profile, "pathfinding.expansion_cap_hit")
			break

		var current_cost: int = g_score.get(current_key, 0)
		var current_distance: int = _goal_distance(
			current, footprint, target_origin, goal_rect, goal_range, exact_origin
		)
		var current_manhattan: int = _manhattan_distance(
			current, footprint, target_origin, goal_rect, goal_range, exact_origin
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
			_count_profile(profile, "pathfinding.expanded_nodes", expanded_nodes)
			_count_profile(profile, "pathfinding.full_path_success")
			return _reconstruct_path(came_from, reached, current_key)

		for delta in _NEIGHBORS:
			var next: Vector2i = current + delta
			var next_key: int = _key(next, grid_width)
			if closed.has(next_key):
				continue
			if not _can_occupy_origin_with_blockers(
				state.tile_grid, next, footprint, movement, occupancy_blockers
			):
				continue
			if _diagonal_step_blocked(
				state.tile_grid, current, delta, footprint, movement, occupancy_blockers
			):
				continue
			var tentative_cost: int = current_cost + step_cost(current, next)
			if g_score.has(next_key) and tentative_cost >= int(g_score[next_key]):
				continue
			came_from[next_key] = current_key
			reached[next_key] = next
			g_score[next_key] = tentative_cost
			var h: int = _heuristic(
				next, footprint, target_origin, goal_rect, goal_range, exact_origin
			)
			var m: int = _manhattan_distance(
				next, footprint, target_origin, goal_rect, goal_range, exact_origin
			)
			_heap_push_open(open, _node(next, tentative_cost, h, m))
		if (
			exact_target_blocked
			and best_distance <= 1
			and (open.is_empty() or int(open[0].get("f", 0)) > best_cost + best_distance)
		):
			_count_profile(profile, "pathfinding.exact_blocked_early_exit")
			_count_profile(profile, "pathfinding.expanded_nodes", expanded_nodes)
			if best_origin == start:
				_count_profile(profile, "pathfinding.full_path_no_progress")
				return out
			_count_profile(profile, "pathfinding.full_path_best_reachable")
			return _reconstruct_path(came_from, reached, _key(best_origin, grid_width))

	if best_origin == start:
		_count_profile(profile, "pathfinding.expanded_nodes", expanded_nodes)
		_count_profile(profile, "pathfinding.full_path_no_progress")
		return out
	_count_profile(profile, "pathfinding.expanded_nodes", expanded_nodes)
	_count_profile(profile, "pathfinding.full_path_best_reachable")
	return _reconstruct_path(came_from, reached, _key(best_origin, grid_width))


static func find_next_step(
	state: MatchState,
	actor: Entity,
	target_origin: Vector2i,
	registry: EntityRegistry,
	options: Dictionary = {}
) -> Dictionary:
	if state == null or actor == null or registry == null or state.tile_grid == null:
		return {}
	if actor.current_hp <= 0:
		return {}
	var footprint: Vector2i = entity_footprint(state, actor, registry)
	if footprint.x <= 0 or footprint.y <= 0:
		return {}
	var movement: MovementDef = movement_def_for_entity(actor, registry)
	if movement == null:
		return {}

	var goal_rect: Rect2i = options.get(OPTION_GOAL_RECT, Rect2i(target_origin, footprint))
	var goal_range: int = options.get(OPTION_GOAL_RANGE, 0)
	var exact_origin: bool = options.get(OPTION_EXACT_ORIGIN, true)
	var complete_blocked_at_current: bool = options.get(OPTION_COMPLETE_BLOCKED_AT_CURRENT, false)
	var profile: Variant = options.get(OPTION_PROFILE, null)
	var occupancy_blockers: Dictionary = options.get(OPTION_OCCUPANCY_BLOCKERS, {})
	if occupancy_blockers.is_empty():
		var passable_entity_ids: Dictionary = _id_set(options.get(OPTION_PASSABLE_ENTITY_IDS, {}))
		var known_entity_ids: Dictionary = _id_set(options.get(OPTION_KNOWN_ENTITY_IDS, {}))
		occupancy_blockers = _occupancy_blockers(
			state,
			actor,
			registry,
			layer_for_entity(actor, registry),
			passable_entity_ids,
			known_entity_ids
		)
	var start: Vector2i = actor.origin
	if _is_goal(start, footprint, target_origin, goal_rect, goal_range, exact_origin):
		return {}
	var completion_blockers: Dictionary = occupancy_blockers
	if options.has(OPTION_MOVER_IDS):
		completion_blockers = {
			"tiles": occupancy_blockers.get("tiles", {}),
			"passable": _id_set(options.get(OPTION_MOVER_IDS, {})),
			"terrain_blocked": occupancy_blockers.get("terrain_blocked"),
		}
	if (
		exact_origin
		and (
			_chebyshev_to_goal(start, footprint, target_origin, goal_rect, goal_range, exact_origin)
			<= 1
		)
		and not _can_occupy_origin_with_blockers(
			state.tile_grid, target_origin, footprint, movement, completion_blockers
		)
	):
		_count_profile(profile, "pathfinding.exact_blocked_adjacent_no_progress")
		if not complete_blocked_at_current:
			return {}
		return {
			"next_origin": start,
			"path_distance": 0,
			"path": [],
			"completed_at_origin": true,
		}

	var direct_path: Array[Vector2i] = _monotonic_path(
		state.tile_grid,
		start,
		target_origin,
		footprint,
		movement,
		occupancy_blockers,
		goal_rect,
		goal_range,
		exact_origin
	)
	if not direct_path.is_empty():
		_count_profile(profile, "pathfinding.monotonic_success")
		return {
			"next_origin": direct_path[0],
			"path_distance": path_cost(start, direct_path),
			"path": direct_path,
		}

	var path_options: Dictionary = options.duplicate()
	path_options[OPTION_OCCUPANCY_BLOCKERS] = occupancy_blockers
	var path_start := Time.get_ticks_usec() if profile != null else 0
	var path: Array[Vector2i] = find_path(state, actor, target_origin, registry, path_options)
	if profile != null:
		_add_profile(profile, "pathfinding.full_path", path_start)
	if path.is_empty():
		_count_profile(profile, "pathfinding.empty")
		return {}
	_count_profile(profile, "pathfinding.full_path_used")
	return {
		"next_origin": path[0],
		"path_distance": path_cost(start, path),
		"path": path,
	}


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
	var blockers: Dictionary = _occupancy_blockers(
		state,
		actor,
		registry,
		layer_for_entity(actor, registry),
		passable_entity_ids,
		known_entity_ids
	)
	return _can_occupy_origin_with_blockers(state.tile_grid, origin, footprint, movement, blockers)


static func _occupancy_blockers(
	state: MatchState,
	actor: Entity,
	registry: EntityRegistry,
	actor_layer: String,
	passable_entity_ids: Dictionary,
	known_entity_ids: Dictionary
) -> Dictionary:
	var blocked_tiles: Dictionary = {}
	if state == null or state.tile_grid == null or registry == null:
		return {"tiles": blocked_tiles}
	for entity in state.entities_sorted_by_id():
		if entity == null:
			continue
		if actor != null and entity.id == actor.id:
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
		for x in range(other_rect.position.x, other_rect.position.x + other_rect.size.x):
			for y in range(other_rect.position.y, other_rect.position.y + other_rect.size.y):
				blocked_tiles[Vector2i(x, y)] = true
	return {"tiles": blocked_tiles}


static func filterable_occupancy_blocker_tiles(
	state: MatchState,
	registry: EntityRegistry,
	actor_layer: String,
	known_entity_ids: Dictionary = {}
) -> Dictionary:
	var blocked_tiles: Dictionary = {}
	if state == null or state.tile_grid == null or registry == null:
		return blocked_tiles
	for entity in state.entities_sorted_by_id():
		if entity == null:
			continue
		if not known_entity_ids.is_empty() and not known_entity_ids.has(entity.id):
			continue
		if not _is_spatial_blocker(entity, registry):
			continue
		if layer_for_entity(entity, registry) != actor_layer:
			continue
		var other_rect: Rect2i = state.tile_grid.entity_rect(entity.id)
		if other_rect.size.x <= 0 or other_rect.size.y <= 0:
			continue
		for x in range(other_rect.position.x, other_rect.position.x + other_rect.size.x):
			for y in range(other_rect.position.y, other_rect.position.y + other_rect.size.y):
				var tile := Vector2i(x, y)
				var ids: Variant = blocked_tiles.get(tile)
				if ids is Dictionary:
					ids[entity.id] = true
				else:
					blocked_tiles[tile] = {entity.id: true}
	return blocked_tiles


static func _can_occupy_origin_with_blockers(
	grid: TileGrid,
	origin: Vector2i,
	footprint: Vector2i,
	movement: MovementDef,
	occupancy_blockers: Dictionary
) -> bool:
	if grid == null or movement == null:
		return false
	var blocked_tiles: Dictionary = occupancy_blockers.get("tiles", {})
	var passable: Dictionary = occupancy_blockers.get("passable", {})
	if (
		footprint == Vector2i.ONE
		and movement.impassable_terrain_tags.is_empty()
		and movement.pathable_terrain_tags.is_empty()
	):
		if not grid.is_in_bounds(origin):
			return false
		return not _tile_blocked(blocked_tiles, passable, origin)
	var rect := Rect2i(origin, footprint)
	if not grid.is_rect_in_bounds(rect):
		return false
	if not _terrain_allows_rect(grid, rect, movement):
		return false
	if not blocked_tiles.is_empty():
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for y in range(rect.position.y, rect.position.y + rect.size.y):
				if _tile_blocked(blocked_tiles, passable, Vector2i(x, y)):
					return false
	return true


# Supports both blocker-tile formats:
# - legacy: tile -> true (passable ids already excluded at build time)
# - ResolveContext: tile -> {entity_id: true}, filtered through `passable`
#   at query time so one shared map serves changing passable sets.
static func _tile_blocked(blocked_tiles: Dictionary, passable: Dictionary, tile: Vector2i) -> bool:
	var ids: Variant = blocked_tiles.get(tile)
	if ids == null:
		return false
	if ids is Dictionary:
		var ids_dict: Dictionary = ids
		if passable.is_empty():
			return not ids_dict.is_empty()
		for entity_id in ids_dict:
			if not passable.has(entity_id):
				return true
		return false
	return true


# No squeezing through corner seams: a diagonal step is blocked when
# BOTH orthogonally-adjacent cells are blocked, so units can never slip
# between two blocked tiles that touch only at a corner (cliff seams,
# building corners). Rounding a single corner stays allowed — that is
# normal smooth movement. Mover-occupied cells stay passable through the
# usual `passable` set.
static func _diagonal_step_blocked(
	grid: TileGrid,
	from: Vector2i,
	delta: Vector2i,
	footprint: Vector2i,
	movement: MovementDef,
	occupancy_blockers: Dictionary
) -> bool:
	if delta.x == 0 or delta.y == 0:
		return false
	if _can_occupy_origin_with_blockers(
		grid, from + Vector2i(delta.x, 0), footprint, movement, occupancy_blockers
	):
		return false
	return not _can_occupy_origin_with_blockers(
		grid, from + Vector2i(0, delta.y), footprint, movement, occupancy_blockers
	)


# ---------- Flow fields ----------
#
# A flow field is a multi-source BFS distance map computed once per goal
# and shared by every 1x1 unit headed there, across all movement substeps
# of a turn. It replaces per-unit per-substep A* (which flooded the whole
# reachable map whenever the goal was occupied or unreachable).
#
# Static blockers stop propagation; tiles occupied by movers (the
# `passable` set) are flowed through — they are expected to vacate, and
# the per-substep conflict resolution remains the collision authority.


static func flow_field_key(
	layer: String,
	movement: MovementDef,
	target_origin: Vector2i,
	goal_rect: Rect2i,
	goal_range: int,
	exact_origin: bool
) -> String:
	var terrain_sig := ""
	if (
		movement != null
		and not (
			movement.impassable_terrain_tags.is_empty()
			and movement.pathable_terrain_tags.is_empty()
		)
	):
		terrain_sig = (
			"|".join(movement.impassable_terrain_tags)
			+ "/"
			+ "|".join(movement.pathable_terrain_tags)
		)
	if exact_origin:
		return "%s:e:%d,%d:%s" % [layer, target_origin.x, target_origin.y, terrain_sig]
	return (
		"%s:r:%d,%d,%d,%d:%d:%s"
		% [
			layer,
			goal_rect.position.x,
			goal_rect.position.y,
			goal_rect.size.x,
			goal_rect.size.y,
			goal_range,
			terrain_sig,
		]
	)


static func build_flow_field(
	grid: TileGrid,
	movement: MovementDef,
	occupancy_blockers: Dictionary,
	target_origin: Vector2i,
	goal_rect: Rect2i,
	goal_range: int,
	exact_origin: bool
) -> Dictionary:
	var dist: Dictionary = {}
	if grid == null or movement == null:
		return dist
	var blocked_tiles: Dictionary = occupancy_blockers.get("tiles", {})
	var passable: Dictionary = occupancy_blockers.get("passable", {})
	var check_terrain: bool = not (
		movement.impassable_terrain_tags.is_empty() and movement.pathable_terrain_tags.is_empty()
	)
	var fast_terrain: bool = occupancy_blockers.get("terrain_blocked") is Dictionary
	var terrain_blocked: Dictionary = (
		occupancy_blockers.get("terrain_blocked") if fast_terrain else {}
	)
	var width: int = grid.width
	var height: int = grid.height
	# Flat-array Dijkstra: per-tile Dictionary[Vector2i] hashing dominated
	# build time at map scale (playtest 2026-06-12). Static blockers and
	# terrain are pre-rendered into one byte mask, distances into a packed
	# int array, and only reachable tiles convert back to the Dictionary
	# the consumers expect.
	var blocked_mask := PackedByteArray()
	blocked_mask.resize(width * height)
	if fast_terrain:
		for tile: Vector2i in terrain_blocked:
			if tile.x >= 0 and tile.x < width and tile.y >= 0 and tile.y < height:
				blocked_mask[tile.y * width + tile.x] = 1
	elif check_terrain:
		for y in range(height):
			for x in range(width):
				if not _terrain_allows_rect(grid, Rect2i(x, y, 1, 1), movement):
					blocked_mask[y * width + x] = 1
	for tile: Vector2i in blocked_tiles:
		if tile.x < 0 or tile.x >= width or tile.y < 0 or tile.y >= height:
			continue
		if blocked_mask[tile.y * width + tile.x] == 1:
			continue
		if _tile_blocked(blocked_tiles, passable, tile):
			blocked_mask[tile.y * width + tile.x] = 1
	var dist_arr := PackedInt32Array()
	dist_arr.resize(width * height)
	dist_arr.fill(-1)
	# Octile costs (2 orthogonal / 3 diagonal) need a small-cost Dijkstra;
	# Dial's bucket queue keeps it deterministic and O(nodes).
	var buckets: Array = []
	for seed in _flow_field_seeds(target_origin, goal_rect, goal_range, exact_origin):
		if not grid.is_in_bounds(seed):
			continue
		var seed_index: int = seed.y * width + seed.x
		if fast_terrain or check_terrain:
			# Terrain-blocked seeds never participate; statically occupied
			# seeds keep distance 0 below.
			if fast_terrain:
				if terrain_blocked.has(seed):
					continue
			elif not _terrain_allows_rect(grid, Rect2i(seed, Vector2i.ONE), movement):
				continue
		if dist_arr[seed_index] != -1:
			continue
		dist_arr[seed_index] = 0
		# A statically blocked seed keeps distance 0 but does not propagate
		# (no pathing through a parked unit ring) — except the exact-origin
		# goal itself, which must propagate so units can approach a blocked
		# destination and complete adjacent to it.
		if exact_origin or blocked_mask[seed_index] == 0:
			_bucket_push(buckets, 0, seed_index)
	var cost := 0
	while cost < buckets.size():
		var bucket: Variant = buckets[cost]
		if bucket == null:
			cost += 1
			continue
		var head := 0
		while head < bucket.size():
			var current_index: int = bucket[head]
			head += 1
			if dist_arr[current_index] != cost:
				continue  # stale entry; a cheaper route claimed this tile
			var cx: int = current_index % width
			var cy: int = current_index / width
			for delta in _NEIGHBORS:
				var nx: int = cx + delta.x
				var ny: int = cy + delta.y
				if nx < 0 or nx >= width or ny < 0 or ny >= height:
					continue
				var next_index: int = ny * width + nx
				if blocked_mask[next_index] == 1:
					continue
				if delta.x != 0 and delta.y != 0:
					# Corner-seam rule: the diagonal is blocked when BOTH
					# orthogonally adjacent cells are blocked.
					var side_a: int = cy * width + nx
					if blocked_mask[side_a] == 1:
						var side_b: int = ny * width + cx
						if blocked_mask[side_b] == 1:
							continue
					var next_cost_d: int = cost + STEP_COST_DIAGONAL
					var seen_d: int = dist_arr[next_index]
					if seen_d != -1 and seen_d <= next_cost_d:
						continue
					dist_arr[next_index] = next_cost_d
					_bucket_push(buckets, next_cost_d, next_index)
				else:
					var next_cost_o: int = cost + STEP_COST_ORTHOGONAL
					var seen_o: int = dist_arr[next_index]
					if seen_o != -1 and seen_o <= next_cost_o:
						continue
					dist_arr[next_index] = next_cost_o
					_bucket_push(buckets, next_cost_o, next_index)
		cost += 1
	for index in range(width * height):
		var value: int = dist_arr[index]
		if value != -1:
			dist[Vector2i(index % width, index / width)] = value
	return dist


static func _bucket_push(buckets: Array, cost: int, tile_index: int) -> void:
	while buckets.size() <= cost:
		buckets.append(null)
	if buckets[cost] == null:
		buckets[cost] = PackedInt32Array()
	buckets[cost].append(tile_index)


static func _flow_field_seeds(
	target_origin: Vector2i, goal_rect: Rect2i, goal_range: int, exact_origin: bool
) -> Array[Vector2i]:
	var seeds: Array[Vector2i] = []
	if exact_origin:
		seeds.append(target_origin)
		return seeds
	var min_x: int = goal_rect.position.x - goal_range
	var min_y: int = goal_rect.position.y - goal_range
	var max_x: int = goal_rect.position.x + goal_rect.size.x - 1 + goal_range
	var max_y: int = goal_rect.position.y + goal_rect.size.y - 1 + goal_range
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			seeds.append(Vector2i(x, y))
	return seeds


static func _monotonic_path(
	grid: TileGrid,
	start: Vector2i,
	target_origin: Vector2i,
	footprint: Vector2i,
	movement: MovementDef,
	occupancy_blockers: Dictionary,
	goal_rect: Rect2i,
	goal_range: int,
	exact_origin: bool
) -> Array[Vector2i]:
	if exact_origin and footprint == Vector2i.ONE:
		var straight_path: Array[Vector2i] = _exact_straight_monotonic_path(
			grid, start, target_origin, footprint, movement, occupancy_blockers
		)
		if not straight_path.is_empty():
			return straight_path
	var path: Array[Vector2i] = []
	var current: Vector2i = start
	var guard: int = max(grid.width, grid.height) + max(footprint.x, footprint.y) + goal_range
	while not _is_goal(current, footprint, target_origin, goal_rect, goal_range, exact_origin):
		if path.size() > guard:
			return []
		var next_origin: Vector2i = _monotonic_next_origin(
			grid,
			current,
			target_origin,
			footprint,
			movement,
			occupancy_blockers,
			goal_rect,
			goal_range,
			exact_origin
		)
		if next_origin == current:
			return []
		current = next_origin
		path.append(current)
	return path


static func _exact_straight_monotonic_path(
	grid: TileGrid,
	start: Vector2i,
	target_origin: Vector2i,
	footprint: Vector2i,
	movement: MovementDef,
	occupancy_blockers: Dictionary
) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current: Vector2i = start
	var guard: int = max(grid.width, grid.height) + max(footprint.x, footprint.y)
	while current != target_origin:
		if path.size() > guard:
			return []
		var delta := Vector2i(
			signi(target_origin.x - current.x), signi(target_origin.y - current.y)
		)
		if delta == Vector2i.ZERO:
			return []
		var next: Vector2i = current + delta
		if not _can_occupy_origin_with_blockers(
			grid, next, footprint, movement, occupancy_blockers
		):
			return []
		if _diagonal_step_blocked(grid, current, delta, footprint, movement, occupancy_blockers):
			return []
		current = next
		path.append(current)
	return path


static func _monotonic_next_origin(
	grid: TileGrid,
	current: Vector2i,
	target_origin: Vector2i,
	footprint: Vector2i,
	movement: MovementDef,
	occupancy_blockers: Dictionary,
	goal_rect: Rect2i,
	goal_range: int,
	exact_origin: bool
) -> Vector2i:
	if exact_origin:
		return _exact_monotonic_next_origin(
			grid, current, target_origin, footprint, movement, occupancy_blockers
		)
	var current_distance: int = _goal_distance(
		current, footprint, target_origin, goal_rect, goal_range, exact_origin
	)
	var current_manhattan: int = _manhattan_distance(
		current, footprint, target_origin, goal_rect, goal_range, exact_origin
	)
	var best_origin: Vector2i = current
	var best_distance: int = current_distance
	var best_manhattan: int = current_manhattan
	var has_candidate := false
	for delta in _NEIGHBORS:
		var next: Vector2i = current + delta
		if not _can_occupy_origin_with_blockers(
			grid, next, footprint, movement, occupancy_blockers
		):
			continue
		if _diagonal_step_blocked(grid, current, delta, footprint, movement, occupancy_blockers):
			continue
		var next_distance: int = _goal_distance(
			next, footprint, target_origin, goal_rect, goal_range, exact_origin
		)
		var next_manhattan: int = _manhattan_distance(
			next, footprint, target_origin, goal_rect, goal_range, exact_origin
		)
		if next_distance > current_distance:
			continue
		if next_distance == current_distance and next_manhattan >= current_manhattan:
			continue
		if (
			not has_candidate
			or _is_better_reachable(
				next,
				next_distance,
				next_manhattan,
				1,
				best_origin,
				best_distance,
				best_manhattan,
				1
			)
		):
			has_candidate = true
			best_origin = next
			best_distance = next_distance
			best_manhattan = next_manhattan
	return best_origin


static func _exact_monotonic_next_origin(
	grid: TileGrid,
	current: Vector2i,
	target_origin: Vector2i,
	footprint: Vector2i,
	movement: MovementDef,
	occupancy_blockers: Dictionary
) -> Vector2i:
	var current_dx: int = abs(current.x - target_origin.x)
	var current_dy: int = abs(current.y - target_origin.y)
	var current_distance: int = max(current_dx, current_dy)
	var current_manhattan: int = current_dx + current_dy
	var best_origin: Vector2i = current
	var best_distance: int = current_distance
	var best_manhattan: int = current_manhattan
	var has_candidate := false
	for delta in _NEIGHBORS:
		var next: Vector2i = current + delta
		if not _can_occupy_origin_with_blockers(
			grid, next, footprint, movement, occupancy_blockers
		):
			continue
		if _diagonal_step_blocked(grid, current, delta, footprint, movement, occupancy_blockers):
			continue
		var next_dx: int = abs(next.x - target_origin.x)
		var next_dy: int = abs(next.y - target_origin.y)
		var next_distance: int = max(next_dx, next_dy)
		var next_manhattan: int = next_dx + next_dy
		if next_distance > current_distance:
			continue
		if next_distance == current_distance and next_manhattan >= current_manhattan:
			continue
		if (
			not has_candidate
			or next_distance < best_distance
			or (
				next_distance == best_distance
				and (
					next_manhattan < best_manhattan
					or (
						next_manhattan == best_manhattan
						and (
							next.y < best_origin.y
							or (next.y == best_origin.y and next.x < best_origin.x)
						)
					)
				)
			)
		):
			has_candidate = true
			best_origin = next
			best_distance = next_distance
			best_manhattan = next_manhattan
	return best_origin


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


static func _heap_push_open(open: Array[Dictionary], item: Dictionary) -> void:
	open.append(item)
	var child: int = open.size() - 1
	while child > 0:
		var parent: int = int(floor(float(child - 1) * 0.5))
		if not _node_less(open[child], open[parent]):
			return
		var parent_node: Dictionary = open[parent]
		open[parent] = open[child]
		open[child] = parent_node
		child = parent


static func _heap_pop_open(open: Array[Dictionary]) -> Dictionary:
	var root: Dictionary = open[0]
	var last: Dictionary = open.pop_back()
	if not open.is_empty():
		open[0] = last
		_heap_sift_down_open(open, 0)
	return root


static func _heap_sift_down_open(open: Array[Dictionary], start_index: int) -> void:
	var parent: int = start_index
	while true:
		var left: int = parent * 2 + 1
		var right: int = left + 1
		var best: int = parent
		if left < open.size() and _node_less(open[left], open[best]):
			best = left
		if right < open.size() and _node_less(open[right], open[best]):
			best = right
		if best == parent:
			return
		var parent_node: Dictionary = open[parent]
		open[parent] = open[best]
		open[best] = parent_node
		parent = best


static func _heuristic(
	origin: Vector2i,
	footprint: Vector2i,
	target_origin: Vector2i,
	goal_rect: Rect2i,
	goal_range: int,
	exact_origin: bool
) -> int:
	# Cost-units heuristic: every step costs at least STEP_COST_ORTHOGONAL
	# and reduces chebyshev distance by at most 1, so this is admissible
	# and consistent under octile step costs.
	return (
		STEP_COST_ORTHOGONAL
		* _chebyshev_to_goal(origin, footprint, target_origin, goal_rect, goal_range, exact_origin)
	)


static func _goal_distance(
	origin: Vector2i,
	footprint: Vector2i,
	target_origin: Vector2i,
	goal_rect: Rect2i,
	goal_range: int,
	exact_origin: bool
) -> int:
	return _chebyshev_to_goal(origin, footprint, target_origin, goal_rect, goal_range, exact_origin)


static func _chebyshev_to_goal(
	origin: Vector2i,
	footprint: Vector2i,
	target_origin: Vector2i,
	goal_rect: Rect2i,
	goal_range: int,
	exact_origin: bool
) -> int:
	if exact_origin:
		return max(abs(origin.x - target_origin.x), abs(origin.y - target_origin.y))
	return max(
		0, TileGrid.distance_between_rects(Rect2i(origin, footprint), goal_rect) - goal_range
	)


static func _manhattan_distance(
	origin: Vector2i,
	footprint: Vector2i,
	target_origin: Vector2i,
	goal_rect: Rect2i,
	goal_range: int,
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
	return max(0, dx + dy - goal_range)


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
	came_from: Dictionary, reached: Dictionary, end_key: int
) -> Array[Vector2i]:
	var reversed: Array[Vector2i] = []
	var current_key: int = end_key
	while came_from.has(current_key):
		reversed.append(reached[current_key])
		current_key = came_from[current_key]
	reversed.reverse()
	return reversed


static func _terrain_allows_rect(grid: TileGrid, rect: Rect2i, movement: MovementDef) -> bool:
	if movement.impassable_terrain_tags.is_empty() and movement.pathable_terrain_tags.is_empty():
		return true
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


static func _add_profile(profile: Variant, label: String, start_usec: int) -> void:
	if profile != null and profile.has_method("add"):
		profile.add(label, start_usec)


static func _count_profile(profile: Variant, label: String, amount: int = 1) -> void:
	if profile != null and profile.has_method("count"):
		profile.count(label, amount)


static func _key(origin: Vector2i, grid_width: int) -> int:
	return origin.y * grid_width + origin.x


static func step_cost(from: Vector2i, to: Vector2i) -> int:
	if from.x != to.x and from.y != to.y:
		return STEP_COST_DIAGONAL
	return STEP_COST_ORTHOGONAL


# Total cost of a path (array of origins after `start`).
static func path_cost(start: Vector2i, path: Array) -> int:
	var total := 0
	var current := start
	for item in path:
		var next: Vector2i = item
		total += step_cost(current, next)
		current = next
	return total
