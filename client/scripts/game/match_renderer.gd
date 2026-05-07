@tool
class_name MatchRenderer
extends Node2D

# Renders a MatchState to screen. Reads ResolveResult.events to render
# attack overlays + destruction effects. Pure consumer of state — never
# writes back. The resolver remains a pure function (ADR-0013).
#
# Plan node: plan/m0/07-dev-play-mode/07b1-renderer-and-camera.md

const ENTITY_VIEW_SCENE_PATH := "res://scenes/entity_view.tscn"
const DEFAULT_VISUALS_PATH := "res://data/entity_visuals.tres"
const DEFAULT_TUNABLES_PATH := "res://data/tunables.tres"

# Camera margin in tiles around the map bounds when auto-fitting.
const _CAMERA_MARGIN_TILES := 3

# Terrain fallback color for chunk-3. Plan-07b3 (perspective + fog) replaces
# this with a real TileMapLayer paint pass once a tileset exists.
const _TERRAIN_FALLBACK_COLOR := Color(0.32, 0.36, 0.30)
const _TERRAIN_FALLBACK_NODE_NAME := "TerrainFallback"

# Attack overlay tunables. Lines fade out over a fixed wall-clock duration
# regardless of turn pacing — animations are decoupled from logic per
# ADR-0013 (resolver determinism). Plan-07b2 introduces step pacing.
const _ATTACK_LINE_COLOR := Color(1.0, 0.95, 0.4)
const _ATTACK_LINE_WIDTH := 4.0
const _ATTACK_LINE_FADE_SECONDS := 1.6
const _DAMAGE_LABEL_COLOR := Color(1.0, 1.0, 0.4)
const _DAMAGE_LABEL_OUTLINE_COLOR := Color(0.0, 0.0, 0.0)
const _DAMAGE_LABEL_OUTLINE_SIZE := 6
const _DAMAGE_LABEL_FONT_SIZE := 28
const _DAMAGE_LABEL_FADE_SECONDS := 1.4
const _DAMAGE_LABEL_RISE_PIXELS := 32.0
const _DAMAGE_LABEL_OFFSET_Y := -28.0
const _DESTRUCTION_FADE_SECONDS := 0.5
const _COMBAT_LOG_MAX_LINES := 50

# Hit flash applied to the target sprite for ~150 ms when ENTITY_DAMAGED
# fires. Quick pulse to white-ish gives a readable "got hit" cue without
# disturbing the team-color modulate when the tween clears.
const _HIT_FLASH_SECONDS := 0.18
const _HIT_FLASH_COLOR := Color(2.5, 2.5, 2.5)

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
@onready var _attack_lines_root: Node2D = $Overlays/AttackLines
@onready var _damage_labels_root: Node2D = $Overlays/DamageLabels
@onready var _combat_log: RichTextLabel = $HUD/CombatLog


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
# Events are processed in emission order (canonical replay order from
# ResolveResult.events). Reconciliation runs first so spawn-then-damage
# in the same step shows the spawn before the hit, not the other way.
func render_step(new_state: MatchState, events: Array) -> void:
	_resolve_internal_nodes()
	_state = new_state
	if new_state == null:
		return
	_reconcile_views(new_state)
	for event in events:
		_render_event(event)


# Lookup helper for tests — fastest way to assert on overlay state.
func attack_line_count() -> int:
	if _attack_lines_root == null:
		return 0
	return _attack_lines_root.get_child_count()


func damage_label_count() -> int:
	if _damage_labels_root == null:
		return 0
	return _damage_labels_root.get_child_count()


func combat_log_text() -> String:
	if _combat_log == null:
		return ""
	return _combat_log.get_parsed_text()


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
	if _attack_lines_root == null:
		_attack_lines_root = get_node_or_null("Overlays/AttackLines") as Node2D
	if _damage_labels_root == null:
		_damage_labels_root = get_node_or_null("Overlays/DamageLabels") as Node2D
	if _combat_log == null:
		_combat_log = get_node_or_null("HUD/CombatLog") as RichTextLabel


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
	# Frame the entity bounding box (with a margin) rather than the whole
	# map. Combat scenarios typically use a fraction of the map, so a
	# map-centered camera leaves entities clustered in a corner.
	# Frame the union of (full map) and (entity bounding box) so combat
	# scenarios that cluster entities into one corner of a large map
	# don't get pushed off-screen by an over-tight bbox fit, while
	# whole-map scenarios still fill the frame edge-to-edge.
	var min_tile := Vector2i.ZERO
	var max_tile := Vector2i(state.tile_grid.width, state.tile_grid.height)
	for entity in state.entities:
		var def: EntityDef = _registry.get_by_id(entity.def_id) if _registry != null else null
		var fp: Vector2i = def.footprint if def != null else Vector2i.ONE
		min_tile.x = min(min_tile.x, entity.origin.x)
		min_tile.y = min(min_tile.y, entity.origin.y)
		max_tile.x = max(max_tile.x, entity.origin.x + fp.x)
		max_tile.y = max(max_tile.y, entity.origin.y + fp.y)
	var center_tile := Vector2((min_tile.x + max_tile.x) / 2.0, (min_tile.y + max_tile.y) / 2.0)
	_camera.position = center_tile * _tile_size
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		viewport_size = Vector2(1280, 720)
	var span_tiles_x: int = max_tile.x - min_tile.x + _CAMERA_MARGIN_TILES * 2
	var span_tiles_y: int = max_tile.y - min_tile.y + _CAMERA_MARGIN_TILES * 2
	var pixel_w: float = max(span_tiles_x, 1) * _tile_size
	var pixel_h: float = max(span_tiles_y, 1) * _tile_size
	var zoom_x: float = viewport_size.x / pixel_w
	var zoom_y: float = viewport_size.y / pixel_h
	_camera.zoom = Vector2.ONE * min(zoom_x, zoom_y)


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


# Walk the new state and reconcile EntityView nodes:
# - Entities present in new_state but no view → spawn one (covers SPAWN
#   without us having to read the SPAWN event explicitly).
# - Views whose entity is gone from new_state → fade and despawn.
# - Views still present → push the new state into the existing view (covers
#   ENTITY_MOVED and HP changes that any subsequent damage-label render
#   should sit on top of).
func _reconcile_views(new_state: MatchState) -> void:
	var live_ids: Dictionary = {}
	for entity in new_state.entities:
		live_ids[entity.id] = true
		if not _views_by_id.has(entity.id):
			_spawn_entity_view(entity)
		else:
			var view: EntityView = _views_by_id[entity.id]
			if view != null and _registry != null:
				var def: EntityDef = _registry.get_by_id(entity.def_id)
				if def != null:
					view.update_from_state(entity, def, _texture_for_def(entity.def_id))
	# Drop views whose entity disappeared this step. Use a copy of the keys
	# so we can mutate _views_by_id during iteration.
	for entity_id in _views_by_id.keys():
		if not live_ids.has(entity_id):
			_destroy_entity_view(entity_id)


func _destroy_entity_view(entity_id: int) -> void:
	var view: EntityView = _views_by_id.get(entity_id)
	_views_by_id.erase(entity_id)
	if view == null:
		return
	view.fade_out_and_despawn(_DESTRUCTION_FADE_SECONDS)


func _render_event(event: ResolverEvent) -> void:
	if event == null:
		return
	match event.type:
		ResolverEvent.Type.ENTITY_DAMAGED:
			_render_attack_overlay(event.actor_id, event.target_id)
			_render_damage_label(event.target_id, event.damage)
			_append_combat_log(
				(
					"#%d hit #%d for %d (HP %d)"
					% [event.actor_id, event.target_id, event.damage, event.hp_after]
				)
			)
		ResolverEvent.Type.ENTITY_DESTROYED:
			# Reconciliation already removed the view; this path covers the
			# rare case where the entity is destroyed but somehow still
			# appears in new_state.entities (shouldn't happen, but handle).
			if _views_by_id.has(event.target_id):
				_destroy_entity_view(event.target_id)
			_append_combat_log("#%d destroyed" % event.target_id)
		ResolverEvent.Type.MATCH_ENDED:
			_append_combat_log("Match ended — winner: P%d" % event.winner_player_id)
		_:
			# Other event types are silent at chunk 4 — production /
			# build / move events get HUD treatment in 07b3+.
			pass


func _render_attack_overlay(actor_id: int, target_id: int) -> void:
	if _attack_lines_root == null:
		return
	var actor_view: EntityView = _views_by_id.get(actor_id)
	var target_view: EntityView = _views_by_id.get(target_id)
	if actor_view == null or target_view == null:
		return
	var line := Line2D.new()
	line.default_color = _ATTACK_LINE_COLOR
	line.width = _ATTACK_LINE_WIDTH
	line.points = PackedVector2Array([actor_view.position, target_view.position])
	_attack_lines_root.add_child(line)
	# Fade out then free. Tweens only run when the node is in a SceneTree
	# under a running game; in @tool tests we still create the line but
	# skip the tween.
	if line.is_inside_tree() and not Engine.is_editor_hint():
		var tween := line.create_tween()
		tween.tween_property(line, "modulate:a", 0.0, _ATTACK_LINE_FADE_SECONDS)
		tween.tween_callback(line.queue_free)


func _render_damage_label(target_id: int, damage: int) -> void:
	if _damage_labels_root == null:
		return
	var view: EntityView = _views_by_id.get(target_id)
	if view == null:
		return
	var label := Label.new()
	label.text = "-%d" % damage
	label.modulate = _DAMAGE_LABEL_COLOR
	label.add_theme_color_override("font_outline_color", _DAMAGE_LABEL_OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", _DAMAGE_LABEL_OUTLINE_SIZE)
	label.add_theme_font_size_override("font_size", _DAMAGE_LABEL_FONT_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(80.0, 0.0)
	# Center the label horizontally on the target, then offset up so the
	# number floats above the sprite silhouette rather than inside it.
	label.position = view.position + Vector2(-40.0, _DAMAGE_LABEL_OFFSET_Y)
	_damage_labels_root.add_child(label)
	# Brief hit flash on the target sprite — adds the "obvious flash" the
	# spec calls out for action visibility. Skipped in @tool tests since
	# Tween needs a running tree.
	_flash_target_sprite(view)
	if label.is_inside_tree() and not Engine.is_editor_hint():
		var tween := label.create_tween()
		tween.set_parallel(true)
		tween.tween_property(
			label,
			"position:y",
			label.position.y - _DAMAGE_LABEL_RISE_PIXELS,
			_DAMAGE_LABEL_FADE_SECONDS
		)
		tween.tween_property(label, "modulate:a", 0.0, _DAMAGE_LABEL_FADE_SECONDS)
		tween.chain().tween_callback(label.queue_free)


func _flash_target_sprite(view: EntityView) -> void:
	if view == null or Engine.is_editor_hint():
		return
	var sprite: Sprite2D = view.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	var original := sprite.modulate
	sprite.modulate = _HIT_FLASH_COLOR
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate", original, _HIT_FLASH_SECONDS)


func _append_combat_log(line: String) -> void:
	if _combat_log == null:
		return
	_combat_log.append_text(line + "\n")
	# Cap line count so the log doesn't grow without bound across long
	# matches. RichTextLabel doesn't expose a "drop oldest line" API, so
	# we recompute from the parsed text when the cap is hit.
	var parsed := _combat_log.get_parsed_text()
	var lines := parsed.split("\n", false)
	if lines.size() > _COMBAT_LOG_MAX_LINES:
		var trimmed := lines.slice(lines.size() - _COMBAT_LOG_MAX_LINES)
		_combat_log.clear()
		_combat_log.append_text("\n".join(trimmed) + "\n")
