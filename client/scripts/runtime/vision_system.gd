@tool
class_name VisionSystem
extends RefCounted


class Visibility:
	extends RefCounted

	var _visible_tiles: Dictionary = {}
	var _detected_tiles: Dictionary = {}

	func mark_visible(tile: Vector2i) -> void:
		_visible_tiles[tile] = true

	func mark_detected(tile: Vector2i) -> void:
		_detected_tiles[tile] = true

	func is_tile_visible(tile: Vector2i) -> bool:
		return _visible_tiles.has(tile)

	func is_tile_detected(tile: Vector2i) -> bool:
		return _detected_tiles.has(tile)

	func is_rect_visible(rect: Rect2i) -> bool:
		if rect.size.x <= 0 or rect.size.y <= 0:
			return false
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for y in range(rect.position.y, rect.position.y + rect.size.y):
				if is_tile_visible(Vector2i(x, y)):
					return true
		return false

	func is_rect_detected(rect: Rect2i) -> bool:
		if rect.size.x <= 0 or rect.size.y <= 0:
			return false
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for y in range(rect.position.y, rect.position.y + rect.size.y):
				if is_tile_detected(Vector2i(x, y)):
					return true
		return false

	func visible_tiles() -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for tile in _visible_tiles.keys():
			out.append(tile)
		return out

	func visible_tile_count() -> int:
		return _visible_tiles.size()


static func compute_player_visibility(
	state: MatchState, registry: EntityRegistry, player_id: int
) -> Visibility:
	var visibility := Visibility.new()
	if state == null or registry == null or state.tile_grid == null:
		return visibility
	for entity in state.entities_sorted_by_id():
		if entity.current_hp <= 0 or entity.owner_player_id != player_id:
			continue
		var def := _def_for_entity(entity, registry)
		if def == null or def.vision == null:
			continue
		var rect := _entity_rect(entity, state, def)
		_mark_radius(visibility, state.tile_grid, rect, def.vision.sight_radius, false)
		if def.vision.detection_radius > 0:
			_mark_radius(visibility, state.tile_grid, rect, def.vision.detection_radius, true)
	return visibility


static func is_entity_visible_to_player(
	entity: Entity,
	state: MatchState,
	registry: EntityRegistry,
	player_id: int,
	visibility: Visibility
) -> bool:
	if entity == null or entity.current_hp <= 0:
		return false
	if entity.owner_player_id == player_id:
		return true
	if state == null or registry == null or state.tile_grid == null or visibility == null:
		return false
	var def := _def_for_entity(entity, registry)
	if def == null:
		return false
	var rect := _entity_rect(entity, state, def)
	if entity.is_hidden and not visibility.is_rect_detected(rect):
		return false
	return visibility.is_rect_visible(rect)


static func _mark_radius(
	visibility: Visibility, grid: TileGrid, rect: Rect2i, radius: int, detector: bool
) -> void:
	if visibility == null or grid == null or rect.size.x <= 0 or rect.size.y <= 0:
		return
	var safe_radius: int = max(radius, 0)
	var min_x: int = rect.position.x - safe_radius
	var min_y: int = rect.position.y - safe_radius
	var max_x: int = rect.position.x + rect.size.x + safe_radius
	var max_y: int = rect.position.y + rect.size.y + safe_radius
	for x in range(min_x, max_x):
		for y in range(min_y, max_y):
			var tile := Vector2i(x, y)
			if not grid.is_in_bounds(tile):
				continue
			if _tile_distance_to_rect(tile, rect) > safe_radius:
				continue
			if detector:
				visibility.mark_detected(tile)
			else:
				visibility.mark_visible(tile)


static func _tile_distance_to_rect(tile: Vector2i, rect: Rect2i) -> int:
	var dx := 0
	if tile.x < rect.position.x:
		dx = rect.position.x - tile.x
	elif tile.x >= rect.position.x + rect.size.x:
		dx = tile.x - (rect.position.x + rect.size.x - 1)
	var dy := 0
	if tile.y < rect.position.y:
		dy = rect.position.y - tile.y
	elif tile.y >= rect.position.y + rect.size.y:
		dy = tile.y - (rect.position.y + rect.size.y - 1)
	return max(dx, dy)


static func _entity_rect(entity: Entity, state: MatchState, def: EntityDef) -> Rect2i:
	if state != null and state.tile_grid != null:
		var rect := state.tile_grid.entity_rect(entity.id)
		if rect.size.x > 0 and rect.size.y > 0:
			return rect
	var fp: Vector2i = def.footprint if def != null else Vector2i.ONE
	return Rect2i(entity.origin, Vector2i(max(fp.x, 1), max(fp.y, 1)))


static func _def_for_entity(entity: Entity, registry: EntityRegistry) -> EntityDef:
	if entity == null or registry == null:
		return null
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	return registry.get_by_id(def_id)
