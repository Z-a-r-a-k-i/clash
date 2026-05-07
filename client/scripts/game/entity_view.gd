class_name EntityView
extends Node2D

# Dumb visual representation of a single Entity. Holds a Sprite2D and a
# Label child. Zero game logic — the renderer pushes state in via
# update_from_state(). Swappable to a mesh-based view post-M0 without
# touching the renderer's sync code.
#
# Plan node: plan/m0/07-dev-play-mode/07b1-renderer-and-camera.md

# Reference colors — kept here rather than in Tunables since they describe
# the renderer's visual language, not gameplay tunables. Owner 0 = blue,
# owner 1 = red, neutral (-1) = untinted.
const COLOR_PLAYER_0 := Color(0.55, 0.7, 1.0)
const COLOR_PLAYER_1 := Color(1.0, 0.55, 0.55)
const COLOR_NEUTRAL := Color(1.0, 1.0, 1.0)

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _label: Label = $Label

var _entity_id: int = -1


func bind_entity_id(id: int) -> void:
	# Bookkeeping so the renderer can find this view by entity id without
	# walking the scene tree by name.
	_entity_id = id


func get_entity_id() -> int:
	return _entity_id


# Push entity state into the visual. Called once at spawn and whenever the
# entity's visible state changes (position, hp, etc.).
func update_from_state(entity: Entity, def: EntityDef, sprite_texture: Texture2D) -> void:
	if _sprite == null:
		# In editor mode, _ready may not have fired yet; resolve children directly.
		_sprite = get_node_or_null("Sprite2D") as Sprite2D
		_label = get_node_or_null("Label") as Label

	if _sprite != null:
		_sprite.texture = sprite_texture
		_sprite.modulate = _color_for_owner(entity.owner_player_id)

	if _label != null:
		_label.text = "%s #%d" % [entity.def_id, entity.id]

	# Position is the center of the entity's footprint, in world pixels.
	var footprint := def.footprint if def != null else Vector2i(1, 1)
	var fp_x: int = max(footprint.x, 1)
	var fp_y: int = max(footprint.y, 1)
	var tile_size := _tile_pixel_size()
	var center_x: float = (entity.origin.x + fp_x / 2.0) * tile_size
	var center_y: float = (entity.origin.y + fp_y / 2.0) * tile_size
	position = Vector2(center_x, center_y)


# Trigger the destruction fade. The view stays alive for the fade duration,
# then frees itself. The renderer should still treat the entity as removed
# from the scene from the moment fade starts.
func fade_out_and_despawn(duration_seconds: float = 1.0) -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, duration_seconds)
	tween.tween_callback(queue_free)


static func _color_for_owner(owner_player_id: int) -> Color:
	match owner_player_id:
		0:
			return COLOR_PLAYER_0
		1:
			return COLOR_PLAYER_1
		_:
			return COLOR_NEUTRAL


static func _tile_pixel_size() -> int:
	var tunables: Tunables = load("res://data/tunables.tres")
	if tunables == null:
		return 32
	return tunables.tile_pixel_size
