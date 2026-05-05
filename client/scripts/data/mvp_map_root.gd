@tool
class_name MvpMapRoot
extends Node2D

# Root node of the mvp_map .tscn. Editor-only: draws the mirror axis line
# and faded ghost previews of the right-half (which gets generated at
# bake time). Lets the author see the full battlefield while editing
# only the left half.

const DEFAULT_TUNABLES_PATH := "res://data/tunables.tres"
const DEFAULT_REGISTRY_PATH := "res://data/entity_registry.tres"

@export var show_axis_line: bool = true:
	set(value):
		show_axis_line = value
		_request_redraw()

@export var show_mirror_ghosts: bool = true:
	set(value):
		show_mirror_ghosts = value
		_request_redraw()


func _ready() -> void:
	if Engine.is_editor_hint():
		_request_redraw()


# Re-fire when child placements move so the ghosts update live.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var tunables: Tunables = load(DEFAULT_TUNABLES_PATH)
	if tunables == null:
		return
	var size := tunables.tile_pixel_size
	var w := tunables.map_width
	var h := tunables.map_height

	# Map bounds rectangle for visual context.
	draw_rect(Rect2(0, 0, w * size, h * size), Color(1, 1, 1, 0.05), true)
	draw_rect(Rect2(0, 0, w * size, h * size), Color(1, 1, 1, 0.4), false, 2.0)

	if show_axis_line:
		var axis_x: float = w * size / 2.0
		draw_line(Vector2(axis_x, 0), Vector2(axis_x, h * size), Color(1, 0.85, 0.2, 0.8), 2.0)

	if show_mirror_ghosts:
		_draw_mirror_ghosts(size, w)


func _request_redraw() -> void:
	if is_inside_tree():
		queue_redraw()


func _draw_mirror_ghosts(tile_size: int, map_width: int) -> void:
	var placements_node := get_node_or_null("Placements")
	if placements_node == null:
		return
	var registry: EntityRegistry = load(DEFAULT_REGISTRY_PATH)
	# Duck-typed: accept any node carrying the EntityPlacement fields, so
	# this script doesn't depend on the EntityPlacement class being
	# resolvable at parse time (matters during hot-reloads).
	for child in placements_node.get_children():
		if not _is_placement(child):
			continue
		var on_axis_flag: bool = child.on_axis
		if on_axis_flag:
			continue
		var def_id: String = child.def_id
		var owner_id: int = child.owner_player_id
		var tile_pos: Vector2i = child.tile_position
		var footprint := _footprint_for(registry, def_id)
		var mx: int = map_width - tile_pos.x - footprint.x
		var my: int = tile_pos.y
		var rect := Rect2(
			mx * tile_size, my * tile_size, footprint.x * tile_size, footprint.y * tile_size
		)
		var color := _ghost_color(owner_id)
		color.a = 0.18
		draw_rect(rect, color, true)
		color.a = 0.5
		draw_rect(rect, color, false, 1.0)


static func _is_placement(n: Node) -> bool:
	if n == null:
		return false
	return "def_id" in n and "owner_player_id" in n and "tile_position" in n and "on_axis" in n


static func _footprint_for(registry: EntityRegistry, def_id: String) -> Vector2i:
	if registry == null or def_id == "":
		return Vector2i(1, 1)
	var def := registry.get_by_id(def_id)
	return def.footprint if def != null else Vector2i(1, 1)


static func _ghost_color(owner_id: int) -> Color:
	# Reflect ownership: 0 ↔ 1; -1 stays -1.
	var mirror := owner_id
	if owner_id == 0:
		mirror = 1
	elif owner_id == 1:
		mirror = 0
	match mirror:
		0:
			return Color(0.4, 0.5, 1.0)
		1:
			return Color(1.0, 0.4, 0.4)
		_:
			return Color(0.7, 0.7, 0.5)
