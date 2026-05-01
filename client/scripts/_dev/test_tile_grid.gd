@tool
extends Node

# Smoke-test runner for TileGrid.
#
# Trigger the same way as the placeholder data generator: attach this
# script to a node in a fresh scene, save, open. The @tool _enter_tree
# runs the asserts and prints results.
#
# Companion scene: res://scripts/_dev/test_tile_grid_scene.tscn (created
# alongside this script). To re-run after edits, switch to a different
# scene then back to this one — opening an already-current scene is a
# no-op.


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	var passed := 0
	var failed := 0
	var fail_names: Array[String] = []

	for test_pair in [
		["place_in_bounds", _test_place_in_bounds],
		["place_out_of_bounds_rejected", _test_place_out_of_bounds_rejected],
		["place_overlap_rejected", _test_place_overlap_rejected],
		["place_double_rejected", _test_place_double_rejected],
		["entity_at_after_place", _test_entity_at_after_place],
		["entity_rect_after_place", _test_entity_rect_after_place],
		["remove", _test_remove],
		["remove_unknown_returns_false", _test_remove_unknown],
		["move_to_clear", _test_move_to_clear],
		["move_to_blocked_rejected", _test_move_to_blocked_rejected],
		["move_does_not_self_collide", _test_move_does_not_self_collide],
		["distance_overlap_zero", _test_distance_overlap_zero],
		["distance_adjacent_diagonal_one", _test_distance_adjacent_diagonal],
		["distance_adjacent_orthogonal_one", _test_distance_adjacent_orthogonal],
		["distance_one_tile_gap_two", _test_distance_one_tile_gap],
		["distance_far", _test_distance_far],
		["adjacency_diagonal", _test_adjacency_diagonal],
		["adjacency_orthogonal", _test_adjacency_orthogonal],
		["adjacency_one_tile_gap_false", _test_adjacency_one_tile_gap],
		["terrain_tags_round_trip", _test_terrain_tags],
		["all_placed_entity_ids_sorted", _test_iter_sorted],
	]:
		var test_name: String = test_pair[0]
		var fn: Callable = test_pair[1]
		var ok: bool = fn.call()
		if ok:
			passed += 1
		else:
			failed += 1
			fail_names.append(test_name)

	print("[test_tile_grid] %d passed, %d failed" % [passed, failed])
	for test_name in fail_names:
		push_error("  failed: %s" % test_name)


# ---------- Placement / bounds / overlap ----------


func _test_place_in_bounds() -> bool:
	var g := TileGrid.new(20, 20)
	return g.place(1, Rect2i(5, 5, 2, 2))


func _test_place_out_of_bounds_rejected() -> bool:
	var g := TileGrid.new(10, 10)
	return not g.place(1, Rect2i(9, 9, 2, 2))


func _test_place_overlap_rejected() -> bool:
	var g := TileGrid.new(20, 20)
	g.place(1, Rect2i(5, 5, 3, 3))
	return not g.place(2, Rect2i(6, 6, 2, 2))


func _test_place_double_rejected() -> bool:
	var g := TileGrid.new(20, 20)
	g.place(1, Rect2i(0, 0, 1, 1))
	return not g.place(1, Rect2i(2, 2, 1, 1))


func _test_entity_at_after_place() -> bool:
	var g := TileGrid.new(20, 20)
	g.place(7, Rect2i(3, 4, 2, 2))
	return (
		g.entity_at(Vector2i(3, 4)) == 7
		and g.entity_at(Vector2i(4, 5)) == 7
		and g.entity_at(Vector2i(5, 5)) == -1
		and g.entity_at(Vector2i(0, 0)) == -1
	)


func _test_entity_rect_after_place() -> bool:
	var g := TileGrid.new(20, 20)
	g.place(7, Rect2i(3, 4, 2, 2))
	var rect := g.entity_rect(7)
	return rect.position == Vector2i(3, 4) and rect.size == Vector2i(2, 2)


# ---------- Remove / move ----------


func _test_remove() -> bool:
	var g := TileGrid.new(10, 10)
	g.place(1, Rect2i(0, 0, 2, 2))
	if not g.remove(1):
		return false
	return g.entity_at(Vector2i(0, 0)) == -1 and g.entity_at(Vector2i(1, 1)) == -1


func _test_remove_unknown() -> bool:
	var g := TileGrid.new(10, 10)
	return not g.remove(999)


func _test_move_to_clear() -> bool:
	var g := TileGrid.new(20, 20)
	g.place(1, Rect2i(0, 0, 2, 2))
	if not g.move(1, Vector2i(5, 5)):
		return false
	return g.entity_at(Vector2i(5, 5)) == 1 and g.entity_at(Vector2i(0, 0)) == -1


func _test_move_to_blocked_rejected() -> bool:
	var g := TileGrid.new(20, 20)
	g.place(1, Rect2i(0, 0, 2, 2))
	g.place(2, Rect2i(5, 5, 2, 2))
	if g.move(1, Vector2i(5, 5)):
		return false
	# Original position must be unchanged.
	return g.entity_at(Vector2i(0, 0)) == 1


func _test_move_does_not_self_collide() -> bool:
	# Moving by 1 tile should be valid even though current footprint overlaps target footprint.
	var g := TileGrid.new(20, 20)
	g.place(1, Rect2i(5, 5, 2, 2))
	if not g.move(1, Vector2i(6, 5)):
		return false
	return g.entity_at(Vector2i(7, 6)) == 1 and g.entity_at(Vector2i(5, 5)) == -1


# ---------- Distance / adjacency ----------
#
# Chebyshev distance in tile units. 0 = overlap or share a tile.
# 1 = tiles touch corner-to-corner or edge-to-edge (no gap).
# 2+ = at least N-1 tiles of gap.


func _test_distance_overlap_zero() -> bool:
	var a := Rect2i(0, 0, 3, 3)
	var b := Rect2i(2, 2, 3, 3)
	return TileGrid.distance_between_rects(a, b) == 0


func _test_distance_adjacent_diagonal() -> bool:
	# Two 2x2 rects at (0,0)-(1,1) and (2,2)-(3,3). Tile (1,1) is corner-adjacent to (2,2).
	var a := Rect2i(0, 0, 2, 2)
	var b := Rect2i(2, 2, 2, 2)
	return TileGrid.distance_between_rects(a, b) == 1


func _test_distance_adjacent_orthogonal() -> bool:
	# (0,0)-(1,1) and (2,0)-(3,1). Tile (1,0) is edge-adjacent to (2,0).
	var a := Rect2i(0, 0, 2, 2)
	var b := Rect2i(2, 0, 2, 2)
	return TileGrid.distance_between_rects(a, b) == 1


func _test_distance_one_tile_gap() -> bool:
	# (0,0)-(1,1) and (3,3)-(4,4). One tile of gap at (2,2). Distance = 2.
	var a := Rect2i(0, 0, 2, 2)
	var b := Rect2i(3, 3, 2, 2)
	return TileGrid.distance_between_rects(a, b) == 2


func _test_distance_far() -> bool:
	var a := Rect2i(0, 0, 2, 2)
	var b := Rect2i(10, 0, 2, 2)
	# a.x range [0,1], b.x range [10,11]. dx = 10 - 1 = 9. dy = 0.
	return TileGrid.distance_between_rects(a, b) == 9


func _test_adjacency_diagonal() -> bool:
	var a := Rect2i(0, 0, 2, 2)
	var b := Rect2i(2, 2, 2, 2)
	return TileGrid.new().are_rects_adjacent(a, b)


func _test_adjacency_orthogonal() -> bool:
	var a := Rect2i(0, 0, 2, 2)
	var b := Rect2i(2, 0, 2, 2)
	return TileGrid.new().are_rects_adjacent(a, b)


func _test_adjacency_one_tile_gap() -> bool:
	# A one-tile gap means distance 2, NOT adjacent.
	var a := Rect2i(0, 0, 2, 2)
	var b := Rect2i(0, 3, 2, 2)
	return not TileGrid.new().are_rects_adjacent(a, b)


# ---------- Terrain ----------


func _test_terrain_tags() -> bool:
	var g := TileGrid.new(10, 10)
	var tags: Array[String] = ["water", "blocks_burrowed"]
	g.set_tile_terrain_tags(Vector2i(5, 5), tags)
	var read := g.tile_terrain_tags(Vector2i(5, 5))
	if read.size() != 2:
		return false
	return "water" in read and "blocks_burrowed" in read


# ---------- Iteration ----------


func _test_iter_sorted() -> bool:
	var g := TileGrid.new(20, 20)
	g.place(7, Rect2i(0, 0, 1, 1))
	g.place(3, Rect2i(2, 2, 1, 1))
	g.place(15, Rect2i(4, 4, 1, 1))
	g.place(5, Rect2i(6, 6, 1, 1))
	var ids := g.all_placed_entity_ids()
	return ids == [3, 5, 7, 15]
