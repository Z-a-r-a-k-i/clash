@tool
class_name TerrainPatch
extends Node2D

# Authoring-time node for painting a rectangle of terrain tags onto a map
# .tscn (under the scene root's `Terrain` child). The bake step (MapBaker)
# walks these and emits ScenarioTerrainPatch entries in the baked .tres,
# mirroring across the map axis like entity placements. The in-editor
# tinted rect is purely diagnostic; the renderer draws actual terrain.

const DEFAULT_TUNABLES_PATH := "res://data/tunables.tres"
const _EDITOR_FILL := Color(0.45, 0.32, 0.2, 0.45)
const _EDITOR_BORDER := Color(0.65, 0.45, 0.25, 0.9)

@export var rect_position: Vector2i = Vector2i.ZERO:
	set(value):
		rect_position = value
		_snap_world_position()
		queue_redraw()

@export var rect_size: Vector2i = Vector2i.ONE:
	set(value):
		rect_size = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		queue_redraw()

@export var terrain_tags: Array[String] = ["cliff"]:
	set(value):
		terrain_tags = value
		queue_redraw()

# Marks an axis-straddling patch the baker should emit ONCE instead of
# mirroring. Only valid for even-width rects centered on the axis.
@export var on_axis: bool = false


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var tile: float = _tile_size()
	var size := Vector2(rect_size.x * tile, rect_size.y * tile)
	draw_rect(Rect2(Vector2.ZERO, size), _EDITOR_FILL, true)
	draw_rect(Rect2(Vector2.ZERO, size), _EDITOR_BORDER, false, 2.0)


func _snap_world_position() -> void:
	var tile: float = _tile_size()
	position = Vector2(rect_position.x * tile, rect_position.y * tile)


func _tile_size() -> float:
	var tunables: Tunables = load(DEFAULT_TUNABLES_PATH) as Tunables
	if tunables == null:
		return 32.0
	return float(tunables.tile_pixel_size)
