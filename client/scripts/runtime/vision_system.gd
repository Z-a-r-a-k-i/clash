@tool
class_name VisionSystem
extends RefCounted


class Visibility:
	extends RefCounted

	# Visibility is stored as merged per-row x-intervals instead of a
	# tile dictionary. A unit's sight area (chebyshev radius around its
	# rect) is exactly a rectangle, so marking costs O(rows), not
	# O(area) — the per-tile dictionary was the resolver's single
	# biggest cost at scale. Intervals are Vector2i(x_start, x_end),
	# inclusive, merged lazily on first query.

	# row y -> Array of Vector2i(x1, x2), possibly unmerged until queried.
	var _visible_rows: Dictionary = {}
	var _detected_rows: Dictionary = {}
	var _visible_merged: bool = true
	var _detected_merged: bool = true

	func mark_visible(tile: Vector2i) -> void:
		mark_visible_span(tile.y, tile.x, tile.x)

	func mark_detected(tile: Vector2i) -> void:
		mark_detected_span(tile.y, tile.x, tile.x)

	func mark_visible_span(row: int, x_start: int, x_end: int) -> void:
		if x_end < x_start:
			return
		if not _visible_rows.has(row):
			_visible_rows[row] = [] as Array[Vector2i]
		_visible_rows[row].append(Vector2i(x_start, x_end))
		_visible_merged = false

	func mark_detected_span(row: int, x_start: int, x_end: int) -> void:
		if x_end < x_start:
			return
		if not _detected_rows.has(row):
			_detected_rows[row] = [] as Array[Vector2i]
		_detected_rows[row].append(Vector2i(x_start, x_end))
		_detected_merged = false

	func is_tile_visible(tile: Vector2i) -> bool:
		_ensure_visible_merged()
		return _row_has_x(_visible_rows, tile.y, tile.x)

	func is_tile_detected(tile: Vector2i) -> bool:
		_ensure_detected_merged()
		return _row_has_x(_detected_rows, tile.y, tile.x)

	func is_rect_visible(rect: Rect2i) -> bool:
		if rect.size.x <= 0 or rect.size.y <= 0:
			return false
		_ensure_visible_merged()
		return _rect_overlaps_rows(_visible_rows, rect)

	func is_rect_detected(rect: Rect2i) -> bool:
		if rect.size.x <= 0 or rect.size.y <= 0:
			return false
		_ensure_detected_merged()
		return _rect_overlaps_rows(_detected_rows, rect)

	func visible_tiles() -> Array[Vector2i]:
		_ensure_visible_merged()
		var out: Array[Vector2i] = []
		for row in _visible_rows:
			for span in _visible_rows[row]:
				for x in range(span.x, span.y + 1):
					out.append(Vector2i(x, row))
		return out

	func visible_tile_count() -> int:
		_ensure_visible_merged()
		var count := 0
		for row in _visible_rows:
			for span in _visible_rows[row]:
				count += span.y - span.x + 1
		return count

	func _ensure_visible_merged() -> void:
		if _visible_merged:
			return
		_merge_rows(_visible_rows)
		_visible_merged = true

	func _ensure_detected_merged() -> void:
		if _detected_merged:
			return
		_merge_rows(_detected_rows)
		_detected_merged = true

	static func _merge_rows(rows: Dictionary) -> void:
		for row in rows:
			var spans: Array[Vector2i] = rows[row]
			if spans.size() <= 1:
				continue
			spans.sort()
			var merged: Array[Vector2i] = [spans[0]]
			for index in range(1, spans.size()):
				var span: Vector2i = spans[index]
				var last: Vector2i = merged[merged.size() - 1]
				if span.x <= last.y + 1:
					merged[merged.size() - 1] = Vector2i(last.x, maxi(last.y, span.y))
				else:
					merged.append(span)
			rows[row] = merged

	static func _row_has_x(rows: Dictionary, row: int, x: int) -> bool:
		var spans: Variant = rows.get(row)
		if spans == null:
			return false
		for span in spans:
			if x < span.x:
				return false
			if x <= span.y:
				return true
		return false

	static func _rect_overlaps_rows(rows: Dictionary, rect: Rect2i) -> bool:
		var x1: int = rect.position.x
		var x2: int = rect.position.x + rect.size.x - 1
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var spans: Variant = rows.get(y)
			if spans == null:
				continue
			for span in spans:
				if span.x > x2:
					break
				if span.y >= x1:
					return true
		return false


static func compute_player_visibility(
	state: MatchState, registry: EntityRegistry, player_id: int
) -> Visibility:
	var visibility := Visibility.new()
	if state == null or registry == null or state.tile_grid == null:
		return visibility
	for entity in state.entities_sorted_by_id():
		var def := _def_for_entity(entity, registry)
		if not _is_present_entity(entity, def) or entity.owner_player_id != player_id:
			continue
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
	if entity == null:
		return false
	var def := _def_for_entity(entity, registry)
	if not _is_present_entity(entity, def):
		return false
	if entity.owner_player_id == player_id:
		return true
	if state == null or registry == null or state.tile_grid == null or visibility == null:
		return false
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
	# Chebyshev distance <= radius around a rect is exactly the rect grown
	# by `radius`, so the sight area is one clamped rectangle of row spans.
	var safe_radius: int = max(radius, 0)
	var min_x: int = maxi(rect.position.x - safe_radius, 0)
	var min_y: int = maxi(rect.position.y - safe_radius, 0)
	var max_x: int = mini(rect.position.x + rect.size.x - 1 + safe_radius, grid.width - 1)
	var max_y: int = mini(rect.position.y + rect.size.y - 1 + safe_radius, grid.height - 1)
	for y in range(min_y, max_y + 1):
		if detector:
			visibility.mark_detected_span(y, min_x, max_x)
		else:
			visibility.mark_visible_span(y, min_x, max_x)


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


static func _is_present_entity(entity: Entity, def: EntityDef) -> bool:
	if entity == null:
		return false
	if entity.current_hp > 0:
		return true
	return def != null and def.resource_source != null
