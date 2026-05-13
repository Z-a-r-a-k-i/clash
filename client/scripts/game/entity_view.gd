@tool
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
# owner 1 = red, neutral (-1) = untinted. Saturated channels (one channel
# at 1.0, others pulled down) make the team tint read at the small per-
# entity pixel sizes the auto-fit camera produces (~8-16 px). The earlier
# desaturated values washed out against grey placeholder sprites.
const COLOR_PLAYER_0 := Color(0.3, 0.55, 1.0)
const COLOR_PLAYER_1 := Color(1.0, 0.3, 0.3)
const COLOR_NEUTRAL := Color(1.0, 1.0, 1.0)
const COLOR_FOG_SILHOUETTE := Color(0.16, 0.18, 0.20, 0.72)

var _entity_id: int = -1
var _owner_player_id: int = -1
var _fog_silhouette := false

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _label: Label = $Label


func bind_entity_id(id: int) -> void:
	# Bookkeeping so the renderer can find this view by entity id without
	# walking the scene tree by name.
	_entity_id = id


func get_entity_id() -> int:
	return _entity_id


# Push entity state into the visual. Called once at spawn and whenever the
# entity's visible state changes (position, hp, etc.).
#
# `placement_rect` is the canonical tile-space placement from
# state.tile_grid.entity_rect(entity.id) per ADR-0010. Position +
# footprint scaling derive from this rect so overlapping placements,
# rect-altering effects, etc. drive the visual correctly. The renderer
# falls back to entity.origin + def.footprint when no state is available
# at construction time.
func update_from_state(
	entity: Entity, _def: EntityDef, sprite_texture: Texture2D, placement_rect: Rect2i
) -> void:
	if _sprite == null:
		# In editor mode, _ready may not have fired yet; resolve children directly.
		_sprite = get_node_or_null("Sprite2D") as Sprite2D
		_label = get_node_or_null("Label") as Label

	var fp_x: int = max(placement_rect.size.x, 1)
	var fp_y: int = max(placement_rect.size.y, 1)
	var tile_size := _tile_pixel_size()
	_owner_player_id = entity.owner_player_id
	_fog_silhouette = false
	# Position is the center of the placement rect in world pixels.
	var center_x: float = (placement_rect.position.x + fp_x / 2.0) * tile_size
	var center_y: float = (placement_rect.position.y + fp_y / 2.0) * tile_size
	position = Vector2(center_x, center_y)

	if _sprite != null:
		_sprite.texture = sprite_texture
		_sprite.modulate = _color_for_owner(entity.owner_player_id)
		# Scale the sprite so it covers the placement rect in world pixels.
		# Without this, a 4x4 base renders at the same on-screen size as a
		# 1x1 worker (both at native PNG pixel dimensions), so the RTS scale
		# hierarchy collapses and the base reads as small as a mineral patch.
		if sprite_texture != null:
			var tex_size: Vector2 = sprite_texture.get_size()
			if tex_size.x > 0 and tex_size.y > 0:
				var target := Vector2(fp_x * tile_size, fp_y * tile_size)
				_sprite.scale = Vector2(target.x / tex_size.x, target.y / tex_size.y)

	if _label != null:
		# Hidden in the auto-fit view because labels overlap and dominate the
		# composition at default zoom. Plan-07b3 (perspective + fog) reworks
		# the HUD; debug labels light up on hover or via a dev toggle there.
		_label.visible = false
		# current_def_id reflects in-flight transforms (e.g. tank → siege_tank);
		# falls back to def_id if the resolver hasn't initialized current yet.
		var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
		_label.text = "%s #%d" % [def_id, entity.id]


func set_fog_silhouette(enabled: bool) -> void:
	if _sprite == null:
		_sprite = get_node_or_null("Sprite2D") as Sprite2D
	_fog_silhouette = enabled
	if _sprite == null:
		return
	_sprite.modulate = COLOR_FOG_SILHOUETTE if enabled else _color_for_owner(_owner_player_id)


func is_fog_silhouette() -> bool:
	return _fog_silhouette


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
