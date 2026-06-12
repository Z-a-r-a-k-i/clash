class_name ResolveContext
extends RefCounted

# Per-resolve cache hub. Resolver.resolve() creates one ResolveContext per
# call and threads it through the systems so per-tick/per-substep work stops
# recomputing global derived state from scratch:
#
# - Player visibility: computed lazily, invalidated per player when one of
#   that player's entities moves, spawns, or dies (own sight changes).
#   Enemy positions are always read live from the grid at query time, so
#   other players' caches stay valid.
# - Sorted entities: rebuilt only when the entity array grows.
# - Blocker tiles per layer: tile -> {entity_id: true} for every spatial
#   blocker, maintained incrementally on move/death and caught up on spawn.
#   Queries filter through a passable-id set, so the same structure serves
#   pathfinding (movers passable) and conflict checks (movers excluded).
# - Flow fields: one multi-source BFS distance field per movement goal,
#   shared by every unit headed there and across substeps; rebuilt only
#   when the blocker landscape changes (versioned).
#
# Everything here is derived state. The MatchState stays the single source
# of truth; dropping the context entirely only costs performance.

var state: MatchState
var registry: EntityRegistry

var _visibility_by_player: Dictionary = {}
var _visibility_dirty: Dictionary = {}

var _sorted_entities: Array[Entity] = []
var _sorted_entity_count: int = -1

# layer -> {tile: {entity_id: true}}
var _blocker_tiles_by_layer: Dictionary = {}
var _blocker_entity_count: int = -1
var _blockers_version: int = 0

# field cache key -> {"version": int, "field": {tile: int}}
var _flow_fields: Dictionary = {}

# Per-tick negative cache for A*-fallback "no progress" results, so an
# unreachable goal is established once per tick instead of per substep.
var _no_progress_goals: Dictionary = {}

# Mover ids of the current movement substep (passable for planning).
var _last_mover_ids: Dictionary = {}


func _init(p_state: MatchState, p_registry: EntityRegistry) -> void:
	state = p_state
	registry = p_registry


# Called by the resolver at every tick boundary. Drops the per-tick
# negative cache and rebuilds blockers lazily so changes that lack
# explicit hooks (distribution, gather source depletion, ...) are picked
# up. Visibility is NOT dirtied here — entity moves/spawns/deaths and
# ability def swaps invalidate it through their hooks, so an unchanged
# player keeps their computed visibility across ticks.
func begin_tick() -> void:
	_no_progress_goals.clear()
	_blocker_tiles_by_layer.clear()
	_blocker_entity_count = -1
	_blockers_version += 1


# ---------- Visibility ----------


func visibility_for(player_id: int) -> VisionSystem.Visibility:
	if player_id < 0:
		return null
	if _visibility_by_player.has(player_id) and not _visibility_dirty.get(player_id, false):
		return _visibility_by_player[player_id]
	var visibility := VisionSystem.compute_player_visibility(state, registry, player_id)
	_visibility_by_player[player_id] = visibility
	_visibility_dirty[player_id] = false
	return visibility


func invalidate_visibility_for(player_id: int) -> void:
	if player_id >= 0:
		_visibility_dirty[player_id] = true


# ---------- Sorted entities ----------


func sorted_entities() -> Array[Entity]:
	if _sorted_entity_count != state.entities.size():
		_sorted_entities = state.entities_sorted_by_id()
		_sorted_entity_count = state.entities.size()
	return _sorted_entities


# ---------- Blocker tiles ----------


func blockers_version() -> int:
	_catch_up_blocker_spawns()
	return _blockers_version


# Tile -> {entity_id: true} of every spatial blocker on `layer`. Callers
# decide which ids are passable (e.g. fellow movers) at query time via
# PathfindingSystem.is_tile_blocked().
func blocker_tiles(layer: String) -> Dictionary:
	_catch_up_blocker_spawns()
	if not _blocker_tiles_by_layer.has(layer):
		_blocker_tiles_by_layer[layer] = _build_blocker_tiles(layer)
	return _blocker_tiles_by_layer[layer]


func _build_blocker_tiles(layer: String) -> Dictionary:
	var tiles: Dictionary = {}
	if state == null or state.tile_grid == null or registry == null:
		return tiles
	for entity in sorted_entities():
		if not PathfindingSystem._is_spatial_blocker(entity, registry):
			continue
		if PathfindingSystem.layer_for_entity(entity, registry) != layer:
			continue
		var rect: Rect2i = state.tile_grid.entity_rect(entity.id)
		_add_blocker_rect(tiles, entity.id, rect)
	return tiles


# Entities appended to state.entities since the last build (construction
# starts mid-tick) are folded in without a full rebuild.
func _catch_up_blocker_spawns() -> void:
	var count := state.entities.size()
	if _blocker_entity_count < 0:
		_blocker_entity_count = count
		return
	if count == _blocker_entity_count:
		return
	for index in range(_blocker_entity_count, count):
		var entity: Entity = state.entities[index]
		if entity == null or not PathfindingSystem._is_spatial_blocker(entity, registry):
			continue
		var layer := PathfindingSystem.layer_for_entity(entity, registry)
		if _blocker_tiles_by_layer.has(layer):
			var rect: Rect2i = state.tile_grid.entity_rect(entity.id)
			_add_blocker_rect(_blocker_tiles_by_layer[layer], entity.id, rect)
		invalidate_visibility_for(entity.owner_player_id)
	_blocker_entity_count = count
	_blockers_version += 1


func on_entity_moved(entity: Entity, layer: String, old_rect: Rect2i, new_rect: Rect2i) -> void:
	if _blocker_tiles_by_layer.has(layer):
		var tiles: Dictionary = _blocker_tiles_by_layer[layer]
		_remove_blocker_rect(tiles, entity.id, old_rect)
		_add_blocker_rect(tiles, entity.id, new_rect)
	invalidate_visibility_for(entity.owner_player_id)


func on_entity_removed(entity_id: int, layer: String, rect: Rect2i, owner_player_id: int) -> void:
	if _blocker_tiles_by_layer.has(layer):
		_remove_blocker_rect(_blocker_tiles_by_layer[layer], entity_id, rect)
	_blockers_version += 1
	invalidate_visibility_for(owner_player_id)


static func _add_blocker_rect(tiles: Dictionary, entity_id: int, rect: Rect2i) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var tile := Vector2i(x, y)
			var ids: Variant = tiles.get(tile)
			if ids is Dictionary:
				ids[entity_id] = true
			else:
				tiles[tile] = {entity_id: true}


static func _remove_blocker_rect(tiles: Dictionary, entity_id: int, rect: Rect2i) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var tile := Vector2i(x, y)
			var ids: Variant = tiles.get(tile)
			if ids is Dictionary:
				ids.erase(entity_id)
				if ids.is_empty():
					tiles.erase(tile)


# Called once per movement substep with the ids of every entity that has
# a movement intent. A change in the mover set changes who counts as a
# hard blocker, so cached flow fields must be rebuilt.
func note_movers(mover_ids: Dictionary) -> void:
	if mover_ids.size() == _last_mover_ids.size():
		var same := true
		for entity_id in mover_ids:
			if not _last_mover_ids.has(entity_id):
				same = false
				break
		if same:
			return
	_last_mover_ids = mover_ids.duplicate()
	_blockers_version += 1


# Ids treated as passable for planning (the current movement-intent set).
func mover_passable() -> Dictionary:
	return _last_mover_ids


# ---------- Flow fields ----------


# Returns the cached distance field for `key`, rebuilding it through
# `build_callable` when the blocker landscape changed since it was built.
func flow_field(key: String, build_callable: Callable) -> Dictionary:
	var version := blockers_version()
	var entry: Dictionary = _flow_fields.get(key, {})
	if not entry.is_empty() and int(entry.get("version", -1)) == version:
		return entry.get("field", {})
	var field: Dictionary = build_callable.call()
	_flow_fields[key] = {"version": version, "field": field}
	return field


# ---------- A*-fallback negative cache (per tick) ----------


func is_no_progress_goal(key: String) -> bool:
	return _no_progress_goals.has(key)


func mark_no_progress_goal(key: String) -> void:
	_no_progress_goals[key] = true
