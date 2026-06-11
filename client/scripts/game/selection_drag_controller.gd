class_name SelectionDragController
extends RefCounted

var threshold_pixels: float = 4.0

var _active: bool = false
var _dragging: bool = false
var _additive: bool = false
var _start_screen: Vector2 = Vector2.ZERO
var _start_world: Vector2 = Vector2.ZERO
var _current_world: Vector2 = Vector2.ZERO


func begin(screen_position: Vector2, world_position: Vector2, additive: bool) -> void:
	_active = true
	_dragging = false
	_additive = additive
	_start_screen = screen_position
	_start_world = world_position
	_current_world = world_position


func update(screen_position: Vector2, world_position: Vector2) -> bool:
	if not _active:
		return false
	_current_world = world_position
	if _dragging:
		return true
	if screen_position.distance_to(_start_screen) >= threshold_pixels:
		_dragging = true
	return _dragging


func release(screen_position: Vector2, world_position: Vector2) -> Dictionary:
	var was_active: bool = _active
	var was_dragging: bool = update(screen_position, world_position) if _active else false
	var result: Dictionary = {
		"active": was_active,
		"dragging": was_dragging,
		"additive": _additive,
		"world_rect": selection_world_rect(),
	}
	reset()
	return result


func active() -> bool:
	return _active


func dragging() -> bool:
	return _dragging


func additive() -> bool:
	return _additive


func selection_world_rect() -> Rect2:
	return Rect2(_start_world, _current_world - _start_world).abs()


func reset() -> void:
	_active = false
	_dragging = false
	_additive = false
	_start_screen = Vector2.ZERO
	_start_world = Vector2.ZERO
	_current_world = Vector2.ZERO
