@tool
class_name EntityPlacement
extends Node2D

# Authoring-time node for placing an entity on the mvp_map .tscn. The bake
# step (MapBaker) walks these and emits a flat Array[ScenarioPlacement] in
# the baked .tres. Visual presence in the editor is purely diagnostic —
# the renderer (plan-07b) draws the actual game art.

const DEFAULT_TUNABLES_PATH := "res://data/tunables.tres"
const DEFAULT_REGISTRY_PATH := "res://data/entity_registry.tres"

@export var def_id: String = "":
	set(value):
		def_id = value
		_request_redraw()

@export var owner_player_id: int = -1:
	set(value):
		owner_player_id = value
		_request_redraw()

# Grid position. Editor sync is one-way: editing tile_position in the
# Inspector snaps the world position. Free-dragging the node does NOT
# update tile_position — author either edits the field directly or uses
# the snap-to-grid drag (TBD when authoring the actual map).
@export var tile_position: Vector2i = Vector2i.ZERO:
	set(value):
		tile_position = value
		_snap_world_position()
		_request_redraw()

# -1 means "use def's max_hp default". Useful for scripted scenarios that
# want a building to start at, say, 50% hp.
@export var initial_hp_override: int = -1

# Marks an axis-straddling neutral that the baker should emit ONCE
# instead of mirroring. Only valid for even-footprint, owner=-1 placements
# centered on the axis. Validated at bake time.
@export var on_axis: bool = false:
	set(value):
		on_axis = value
		_request_redraw()


func _ready() -> void:
	if Engine.is_editor_hint():
		_snap_world_position()
		_request_redraw()


# ---------- Internals ----------


func _snap_world_position() -> void:
	if not is_inside_tree():
		return
	var size := _tile_pixel_size()
	position = Vector2(tile_position.x * size, tile_position.y * size)


func _request_redraw() -> void:
	if is_inside_tree():
		queue_redraw()


func _tile_pixel_size() -> int:
	var tunables: Tunables = load(DEFAULT_TUNABLES_PATH)
	return tunables.tile_pixel_size if tunables != null else 32


func _footprint_from_registry() -> Vector2i:
	if def_id == "":
		return Vector2i(1, 1)
	var registry: EntityRegistry = load(DEFAULT_REGISTRY_PATH)
	if registry == null:
		return Vector2i(1, 1)
	var def := registry.get_by_id(def_id)
	return def.footprint if def != null else Vector2i(1, 1)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var size := _tile_pixel_size()
	var footprint := _footprint_from_registry()
	var rect := Rect2(0, 0, footprint.x * size, footprint.y * size)

	var fill := _owner_color()
	fill.a = 0.35
	draw_rect(rect, fill, true)
	draw_rect(rect, _owner_color(), false, 2.0)

	var font := ThemeDB.fallback_font
	if font == null:
		return
	var label := def_id if def_id != "" else "?"
	if on_axis:
		label += " [axis]"
	draw_string(font, Vector2(4, 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


func _owner_color() -> Color:
	match owner_player_id:
		0:
			return Color(0.4, 0.5, 1.0)
		1:
			return Color(1.0, 0.4, 0.4)
		_:
			return Color(0.7, 0.7, 0.5)
