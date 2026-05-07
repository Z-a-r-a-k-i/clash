@tool
class_name MatchRenderer
extends Node2D

# Renders a MatchState to screen. Reads ResolveResult.events to render
# attack overlays + destruction effects. Pure consumer of state — never
# writes back. The resolver remains a pure function (ADR-0013).
#
# Plan node: plan/m0/07-dev-play-mode/07b1-renderer-and-camera.md
#
# Chunk 4 fills in render_step() with attack overlays + reconciliation.

const ENTITY_VIEW_SCENE_PATH := "res://scenes/entity_view.tscn"
const DEFAULT_VISUALS_PATH := "res://data/entity_visuals.tres"
const DEFAULT_TUNABLES_PATH := "res://data/tunables.tres"

# Camera margin in tiles around the map bounds when auto-fitting.
const _CAMERA_MARGIN_TILES := 3

# Terrain fallback color for chunk-3. Plan-07b3 (perspective + fog) replaces
# this with a real TileMapLayer paint pass once a tileset exists.
const _TERRAIN_FALLBACK_COLOR := Color(0.32, 0.36, 0.30)
const _TERRAIN_FALLBACK_NODE_NAME := "TerrainFallback"

var _state: MatchState = null
var _registry: EntityRegistry = null
var _visuals: EntityVisuals = null
var _tile_size: int = 32

# entity id -> EntityView node.
var _views_by_id: Dictionary = {}

# Cached PackedScene for spawning entity views without reloading per call.
var _entity_view_scene: PackedScene = null

@onready var _entities_root: Node2D = $Entities
@onready var _terrain: TileMapLayer = $Terrain
@onready var _camera: Camera2D = $Camera2D


# Initial bind: take a freshly-loaded MatchState and populate the scene
# tree to match. Replaces any existing rendered state.
func bind_state(state: MatchState, registry: EntityRegistry) -> void:
	_resolve_internal_nodes()
	_clear_existing_views()

	_state = state
	_registry = registry
	if _visuals == null:
		_visuals = load(DEFAULT_VISUALS_PATH) as EntityVisuals
	if _entity_view_scene == null:
		_entity_view_scene = load(ENTITY_VIEW_SCENE_PATH) as PackedScene
	_tile_size = _read_tile_size()

	if state == null or registry == null:
		return

	_paint_terrain_fallback(state)

	for entity in state.entities:
		_spawn_entity_view(entity)

	_fit_camera_to_state(state)


func get_entity_view(entity_id: int) -> EntityView:
	return _views_by_id.get(entity_id)


func entity_view_count() -> int:
	return _views_by_id.size()


# Apply a turn's resolution: reconcile entity views vs new_state, render
# the events list (attack lines, damage labels, destruction fades).
func render_step(new_state: MatchState, _events: Array) -> void:
	_state = new_state
	# chunk 4: reconcile views, render events, append to combat log


# ---------- Internals ----------


# Manual node resolution because tests construct the renderer outside the
# scene tree where @onready doesn't fire. Idempotent.
func _resolve_internal_nodes() -> void:
	if _entities_root == null:
		_entities_root = get_node_or_null("Entities") as Node2D
	if _terrain == null:
		_terrain = get_node_or_null("Terrain") as TileMapLayer
	if _camera == null:
		_camera = get_node_or_null("Camera2D") as Camera2D


func _clear_existing_views() -> void:
	if _entities_root == null:
		return
	for child in _entities_root.get_children():
		_entities_root.remove_child(child)
		child.queue_free()
	_views_by_id.clear()


func _spawn_entity_view(entity: Entity) -> void:
	if _entities_root == null or _registry == null:
		return
	var def: EntityDef = _registry.get_by_id(entity.def_id)
	if def == null:
		return
	if _entity_view_scene == null:
		return
	var view := _entity_view_scene.instantiate() as EntityView
	if view == null:
		return
	_entities_root.add_child(view)
	view.bind_entity_id(entity.id)
	view.update_from_state(entity, def, _texture_for_def(entity.def_id))
	_views_by_id[entity.id] = view


func _texture_for_def(def_id: String) -> Texture2D:
	if _visuals == null:
		return null
	var path: String = _visuals.sprite_paths.get(def_id, "")
	if path == "":
		return null
	return load(path) as Texture2D


func _fit_camera_to_state(state: MatchState) -> void:
	if _camera == null or state == null or state.tile_grid == null:
		return
	var w: int = state.tile_grid.width
	var h: int = state.tile_grid.height
	# Center on map midpoint.
	_camera.position = Vector2(w * _tile_size / 2.0, h * _tile_size / 2.0)
	# Zoom to fit the whole grid inside the viewport with a small margin.
	# Camera2D's `zoom` is a multiplier — values > 1 zoom in, < 1 zoom out.
	# We want to see (w + margin*2) tiles horizontally inside the viewport
	# width, so zoom = viewport_w / desired_pixel_extent.
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		viewport_size = Vector2(1280, 720)  # editor default before window settles
	var pixel_w: float = (w + _CAMERA_MARGIN_TILES * 2) * _tile_size
	var pixel_h: float = (h + _CAMERA_MARGIN_TILES * 2) * _tile_size
	var zoom_x: float = viewport_size.x / pixel_w
	var zoom_y: float = viewport_size.y / pixel_h
	var zoom_factor: float = min(zoom_x, zoom_y)
	_camera.zoom = Vector2(zoom_factor, zoom_factor)


# Solid-color rect under entities until a real TileSet is wired up. Sized
# to the map's pixel bounds. Re-creates the node on every bind_state so
# scenario changes resize it correctly.
func _paint_terrain_fallback(state: MatchState) -> void:
	var existing := get_node_or_null(_TERRAIN_FALLBACK_NODE_NAME)
	if existing != null:
		existing.queue_free()
	if state == null or state.tile_grid == null:
		return
	var w_px: float = state.tile_grid.width * _tile_size
	var h_px: float = state.tile_grid.height * _tile_size
	var bg := Polygon2D.new()
	bg.name = _TERRAIN_FALLBACK_NODE_NAME
	bg.color = _TERRAIN_FALLBACK_COLOR
	bg.polygon = PackedVector2Array(
		[
			Vector2(0, 0),
			Vector2(w_px, 0),
			Vector2(w_px, h_px),
			Vector2(0, h_px),
		]
	)
	add_child(bg)
	# Render behind every other child (Camera2D ignored — non-visual).
	move_child(bg, 0)


func _read_tile_size() -> int:
	var tunables: Tunables = load(DEFAULT_TUNABLES_PATH) as Tunables
	if tunables == null:
		return 32
	return tunables.tile_pixel_size
