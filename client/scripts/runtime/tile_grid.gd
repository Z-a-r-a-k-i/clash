class_name TileGrid
extends RefCounted

# The grid data structure for clash. Square tiles; entities occupy a
# rectangular footprint described by (origin: Vector2i, footprint: Vector2i).
#
# Per ADR 0010, every spatial query assumes multi-tile occupancy from day
# one. This class is the single source of truth for "what is where" — the
# resolver, pathfinder, and vision system all consume its API.
#
# Storage:
# - Occupancy is sparse (Dictionary keyed by tile). Empty tiles aren't stored.
# - Terrain tags are sparse too (Dictionary keyed by tile). Most M0 tiles
#   are open ground with no tags; populating only the tagged tiles keeps
#   the grid cheap to iterate.
# - Per-entity rects are also indexed so remove/move are O(footprint),
#   not O(grid).
#
# This class has no Godot Node dependencies and is unit-testable without
# scenes. Rendering is the presentation layer's job (plan node 01 also
# calls for a placeholder render scene; that lives in client/scripts/game/).

var width: int = 0
var height: int = 0

# Internal occupancy: Vector2i tile -> int entity_id. Tiles with no entry are clear.
var _occupancy: Dictionary = {}

# Internal terrain: Vector2i tile -> Array[String]. Tiles with no entry default to no tags.
var _terrain_tags: Dictionary = {}

# Entity index: int entity_id -> Rect2i (origin, footprint as size).
var _entity_rects: Dictionary = {}


func _init(grid_width: int = 0, grid_height: int = 0) -> void:
	width = grid_width
	height = grid_height


# ---------- Cloning ----------


func clone() -> TileGrid:
	# Deep-copy used by Resolver to maintain its pure-function contract.
	# All values stored in the internal Dictionaries are primitive-ish
	# (int, Vector2i, Rect2i, Array[String] of small string lists), so
	# `Dictionary.duplicate(true)` is sufficient for full independence.
	var c := TileGrid.new(width, height)
	c._occupancy = _occupancy.duplicate(true)
	c._terrain_tags = _terrain_tags.duplicate(true)
	c._entity_rects = _entity_rects.duplicate(true)
	return c


# ---------- Bounds ----------


func is_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < width and tile.y < height


func is_rect_in_bounds(rect: Rect2i) -> bool:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false
	if rect.position.x < 0 or rect.position.y < 0:
		return false
	if rect.position.x + rect.size.x > width:
		return false
	if rect.position.y + rect.size.y > height:
		return false
	return true


# ---------- Occupancy queries ----------


func entity_at(tile: Vector2i) -> int:
	# Returns the entity id occupying this tile, or -1 if clear / out of bounds.
	return _occupancy.get(tile, -1)


func is_rect_clear(rect: Rect2i, ignore_entity_id: int = -1) -> bool:
	# True if every tile in `rect` is in-bounds AND either unoccupied OR
	# occupied by `ignore_entity_id` (used during a move to skip "would
	# I collide with myself" checks).
	if not is_rect_in_bounds(rect):
		return false
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var occupant: int = _occupancy.get(Vector2i(x, y), -1)
			if occupant != -1 and occupant != ignore_entity_id:
				return false
	return true


func entity_rect(entity_id: int) -> Rect2i:
	# Returns the entity's rect, or an empty rect (size == 0) if not placed.
	return _entity_rects.get(entity_id, Rect2i())


# ---------- Mutation ----------


func place(entity_id: int, rect: Rect2i) -> bool:
	# Place an entity at `rect`. Fails if entity_id < 0, the rect is out of
	# bounds, or any tile in the rect is already occupied by a different entity.
	# If the entity is already placed, this fails — call move() instead.
	if entity_id < 0:
		return false
	if _entity_rects.has(entity_id):
		return false
	if not is_rect_clear(rect):
		return false
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			_occupancy[Vector2i(x, y)] = entity_id
	_entity_rects[entity_id] = rect
	return true


# Plan node 05: special-case placement allowing rect overlap with one
# existing entity carrying `allow_overlap_id`. Used by BUILD when the
# def has `requires_target_tag` set (refinery on geyser).
#
# The original entity's `_occupancy` entries are PRESERVED — queries
# like `entity_at(tile)` still return the underlying entity. Only the
# new entity's rect is recorded in `_entity_rects`. Code that needs to
# discover the overlay (e.g. gather_system._find_extractor_at) iterates
# entities and matches rect positions.
#
# Returns false if the rect is out of bounds, contains more than one
# distinct existing occupant, or that occupant's id != `allow_overlap_id`.
func place_overlapping(entity_id: int, rect: Rect2i, allow_overlap_id: int) -> bool:
	if entity_id < 0:
		return false
	if _entity_rects.has(entity_id):
		return false
	if not is_rect_in_bounds(rect):
		return false
	# Walk the rect, gathering distinct occupants (ignoring allow_overlap_id).
	var occupants: Dictionary = {}
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var occ: int = _occupancy.get(Vector2i(x, y), -1)
			if occ != -1 and occ != allow_overlap_id:
				occupants[occ] = true
	if not occupants.is_empty():
		# A non-allowed occupant blocks the placement.
		return false
	# Also reject if any OTHER entity already has a rect overlapping this
	# rect (not just _occupancy occupants — a previously place_overlapping'd
	# entity lives in _entity_rects only). This catches the second
	# refinery-on-geyser case: player 0's refinery isn't in _occupancy but
	# is in _entity_rects, and a second player targeting the same geyser
	# must be rejected.
	for existing_id in _entity_rects:
		if existing_id == allow_overlap_id:
			continue
		var existing: Rect2i = _entity_rects[existing_id]
		if existing.intersects(rect):
			return false
	# Record the rect WITHOUT updating _occupancy. The underlying entity
	# (if any) keeps its occupancy entries; the new entity's footprint
	# is discoverable via _entity_rects only.
	_entity_rects[entity_id] = rect
	return true


func remove(entity_id: int) -> bool:
	# Remove an entity. Returns false if it wasn't placed. Only clears
	# `_occupancy` entries that actually point at `entity_id` — overlapping
	# entities (e.g. a refinery placed via place_overlapping on top of a
	# geyser, where _occupancy still points at the geyser) leave the
	# underlying entity's tiles intact.
	if not _entity_rects.has(entity_id):
		return false
	var rect: Rect2i = _entity_rects[entity_id]
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var tile := Vector2i(x, y)
			if _occupancy.get(tile, -1) == entity_id:
				_occupancy.erase(tile)
	_entity_rects.erase(entity_id)
	return true


func move(entity_id: int, new_origin: Vector2i) -> bool:
	# Move an entity to a new origin (footprint stays the same). Atomic:
	# fails without changing state if the destination isn't clear or in
	# bounds. The entity's own current tiles are ignored during the
	# clearance check.
	if not _entity_rects.has(entity_id):
		return false
	var current: Rect2i = _entity_rects[entity_id]
	var target := Rect2i(new_origin, current.size)
	if not is_rect_clear(target, entity_id):
		return false
	# Clear only tiles we actually own (see remove() rationale).
	for x in range(current.position.x, current.position.x + current.size.x):
		for y in range(current.position.y, current.position.y + current.size.y):
			var tile := Vector2i(x, y)
			if _occupancy.get(tile, -1) == entity_id:
				_occupancy.erase(tile)
	# Mark new tiles.
	for x in range(target.position.x, target.position.x + target.size.x):
		for y in range(target.position.y, target.position.y + target.size.y):
			_occupancy[Vector2i(x, y)] = entity_id
	_entity_rects[entity_id] = target
	return true


# ---------- Terrain ----------


func tile_terrain_tags(tile: Vector2i) -> Array[String]:
	if not is_in_bounds(tile):
		return []
	var tags: Array = _terrain_tags.get(tile, [])
	# Coerce to typed Array[String] for callers that expect strict typing.
	var typed: Array[String] = []
	for t in tags:
		typed.append(t)
	return typed


func set_tile_terrain_tags(tile: Vector2i, tags: Array[String]) -> void:
	if not is_in_bounds(tile):
		return
	if tags.is_empty():
		_terrain_tags.erase(tile)
	else:
		_terrain_tags[tile] = tags


# ---------- Distance and adjacency ----------


static func distance_between_rects(a: Rect2i, b: Rect2i) -> int:
	# Chebyshev distance between two rects. 0 means the rects overlap or
	# share at least one tile edge in common. 1 means adjacent (touching
	# diagonally or orthogonally). N means N tiles apart.
	#
	# For two single-tile rects this matches the usual Chebyshev distance
	# (max of |dx|, |dy|).
	var ax1 := a.position.x
	var ay1 := a.position.y
	var ax2 := a.position.x + a.size.x - 1
	var ay2 := a.position.y + a.size.y - 1
	var bx1 := b.position.x
	var by1 := b.position.y
	var bx2 := b.position.x + b.size.x - 1
	var by2 := b.position.y + b.size.y - 1

	var dx := 0
	if ax2 < bx1:
		dx = bx1 - ax2
	elif bx2 < ax1:
		dx = ax1 - bx2

	var dy := 0
	if ay2 < by1:
		dy = by1 - ay2
	elif by2 < ay1:
		dy = ay1 - by2

	return max(dx, dy)


func are_rects_adjacent(a: Rect2i, b: Rect2i) -> bool:
	# True if the two rects are adjacent (Chebyshev distance == 1).
	# Note: returns false for overlapping rects (distance == 0).
	return TileGrid.distance_between_rects(a, b) == 1


# ---------- Iteration helpers ----------


func all_placed_entity_ids() -> Array[int]:
	# Stable iteration order (sorted by id) — important for deterministic
	# resolution per ADR 0013.
	var ids: Array[int] = []
	for k in _entity_rects.keys():
		ids.append(k)
	ids.sort()
	return ids
