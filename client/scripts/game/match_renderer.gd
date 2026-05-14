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
const VISION_SYSTEM_SCRIPT := preload("res://scripts/runtime/vision_system.gd")

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
const _SELECTED_HIGHLIGHT_COLOR := Color(0.1, 0.85, 1.0, 0.32)
const _HOVER_HIGHLIGHT_COLOR := Color(1.0, 1.0, 1.0, 0.22)
const _FOG_UNSEEN_COLOR := Color(0.0, 0.0, 0.0, 0.62)
const _FOG_SEEN_COLOR := Color(0.0, 0.0, 0.0, 0.34)

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
var _views_by_id: Dictionary[int, EntityView] = {}

# Authoritative log line buffer. RichTextLabel can't trim oldest lines on
# its own, so we own the cap here and re-render from the buffer when it
# changes.
var _combat_log_lines: Array[String] = []

# Cached PackedScene for spawning entity views without reloading per call.
var _entity_view_scene: PackedScene = null

var _selected_entity_id: int = -1
var _hover_tile: Vector2i = Vector2i.ZERO
var _has_hover_tile: bool = false
var _perspective_player_id: int = 0
var _visibility_by_player: Dictionary = {}
var _seen_tiles_by_player: Dictionary = {}
var _seen_enemy_buildings_by_player: Dictionary = {}

@onready var _entities_root: Node2D = $Entities
@onready var _terrain: TileMapLayer = $Terrain
@onready var _camera: Camera2D = $Camera2D
@onready var _fog_root: Node2D = $Overlays/Fog
@onready var _attack_lines_root: Node2D = $Overlays/AttackLines
@onready var _input_highlights_root: Node2D = $Overlays/Highlights
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

	# entities_sorted_by_id filters null slots that MatchState.clone()
	# preserves to keep positional indices stable. Iterating raw
	# state.entities would crash on those nulls.
	for entity in state.entities_sorted_by_id():
		if entity.current_hp <= 0:
			continue
		_spawn_entity_view(entity, state)

	_reset_visibility_memory()
	_refresh_all_visibility()
	_fit_camera_to_state(state)


func get_entity_view(entity_id: int) -> EntityView:
	return _views_by_id.get(entity_id)


func entity_view_count() -> int:
	return _views_by_id.size()


# Apply a turn's resolution. The order matters: events run between the
# spawn-new-views pass and the prune-dead-views pass so that a fatal
# attack (ENTITY_DAMAGED followed by ENTITY_DESTROYED) still has a live
# target view to draw the line + damage label against. Pruning before
# events would erase the target before the attack overlay could find it.
# Position updates run last so attack-line endpoints reflect the
# pre-event positions captured at the previous render_step / bind_state.
func render_step(new_state: MatchState, events: Array[ResolverEvent]) -> void:
	_resolve_internal_nodes()
	_state = new_state
	if new_state == null:
		return
	_spawn_added_views(new_state)
	for event in events:
		_render_event(event)
	_prune_dead_views(new_state)
	_update_surviving_views(new_state)
	_refresh_all_visibility()


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
	# Read from our own buffer rather than RichTextLabel.get_parsed_text()
	# so tests don't depend on BBCode-stripped output and so the answer
	# matches what _append_combat_log thinks it stored.
	return "\n".join(_combat_log_lines)


func combat_log_line_count() -> int:
	return _combat_log_lines.size()


func world_to_tile(world_position: Vector2) -> Vector2i:
	var safe_tile_size: int = max(_tile_size, 1)
	return Vector2i(
		floori(world_position.x / safe_tile_size), floori(world_position.y / safe_tile_size)
	)


func entity_id_at_tile(tile: Vector2i) -> int:
	if _state == null or _state.tile_grid == null:
		return -1
	var entity_id: int = _state.tile_grid.entity_at(tile)
	if entity_id < 0:
		return -1
	return entity_id if _is_entity_hit_testable(entity_id) else -1


func entity_id_at_world(world_position: Vector2) -> int:
	return entity_id_at_tile(world_to_tile(world_position))


func set_selected_entity_id(entity_id: int) -> void:
	_selected_entity_id = entity_id
	_rebuild_input_highlights()


func set_hover_tile(tile: Vector2i) -> void:
	_hover_tile = tile
	_has_hover_tile = true
	_rebuild_input_highlights()


func clear_input_highlights() -> void:
	_selected_entity_id = -1
	_has_hover_tile = false
	_clear_input_highlight_nodes()


func input_highlight_count() -> int:
	if _input_highlights_root == null:
		return 0
	return _input_highlights_root.get_child_count()


func set_perspective_player_id(player_id: int) -> void:
	_perspective_player_id = player_id
	_refresh_entity_visibility()
	_rebuild_fog_overlay()


func perspective_player_id() -> int:
	return _perspective_player_id


func is_entity_view_visible(entity_id: int) -> bool:
	var view: EntityView = _views_by_id.get(entity_id)
	return view != null and view.visible


func is_entity_view_silhouette(entity_id: int) -> bool:
	var view: EntityView = _views_by_id.get(entity_id)
	return view != null and view.visible and view.is_fog_silhouette()


func fog_overlay_count() -> int:
	if _fog_root == null:
		return 0
	return _fog_root.get_child_count()


func is_tile_currently_visible(player_id: int, tile: Vector2i) -> bool:
	var visibility = _visibility_by_player.get(player_id)
	if visibility == null:
		return false
	return visibility.is_tile_visible(tile)


func is_tile_previously_seen(player_id: int, tile: Vector2i) -> bool:
	var seen: Dictionary = _seen_tiles_by_player.get(player_id, {})
	return seen.has(tile)


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
	if _fog_root == null:
		_fog_root = get_node_or_null("Overlays/Fog") as Node2D
	if _fog_root == null:
		var overlays_for_fog := get_node_or_null("Overlays") as Node2D
		if overlays_for_fog != null:
			_fog_root = Node2D.new()
			_fog_root.name = "Fog"
			overlays_for_fog.add_child(_fog_root)
			overlays_for_fog.move_child(_fog_root, 0)
	if _attack_lines_root == null:
		_attack_lines_root = get_node_or_null("Overlays/AttackLines") as Node2D
	if _input_highlights_root == null:
		_input_highlights_root = get_node_or_null("Overlays/Highlights") as Node2D
	if _input_highlights_root == null:
		var overlays := get_node_or_null("Overlays") as Node2D
		if overlays != null:
			_input_highlights_root = Node2D.new()
			_input_highlights_root.name = "Highlights"
			overlays.add_child(_input_highlights_root)
	if _damage_labels_root == null:
		_damage_labels_root = get_node_or_null("Overlays/DamageLabels") as Node2D
	if _combat_log == null:
		_combat_log = get_node_or_null("HUD/CombatLog") as RichTextLabel


func _clear_existing_views() -> void:
	if _entities_root != null:
		for child in _entities_root.get_children():
			_entities_root.remove_child(child)
			child.queue_free()
	_views_by_id.clear()
	# Also drop overlays + log so a re-bind to a different scenario
	# doesn't carry over lingering attack lines, damage labels, or log
	# entries from the previous match.
	_clear_overlay_roots()
	_combat_log_lines.clear()
	if _combat_log != null:
		_combat_log.clear()
	clear_input_highlights()


func _clear_overlay_roots() -> void:
	for root in [_fog_root, _attack_lines_root, _damage_labels_root]:
		if root == null:
			continue
		for child in root.get_children():
			root.remove_child(child)
			child.queue_free()


func _clear_input_highlight_nodes() -> void:
	if _input_highlights_root == null:
		return
	for child in _input_highlights_root.get_children():
		_input_highlights_root.remove_child(child)
		child.queue_free()


func _rebuild_input_highlights() -> void:
	_resolve_internal_nodes()
	_clear_input_highlight_nodes()
	if _input_highlights_root == null:
		return
	if _state != null and _state.tile_grid != null and _selected_entity_id >= 0:
		var selected_rect: Rect2i = _state.tile_grid.entity_rect(_selected_entity_id)
		if selected_rect.size.x > 0 and selected_rect.size.y > 0:
			_input_highlights_root.add_child(
				_highlight_polygon(selected_rect, _SELECTED_HIGHLIGHT_COLOR)
			)
	if _has_hover_tile:
		_input_highlights_root.add_child(
			_highlight_polygon(Rect2i(_hover_tile, Vector2i.ONE), _HOVER_HIGHLIGHT_COLOR)
		)


func _highlight_polygon(rect: Rect2i, color: Color) -> Polygon2D:
	var x0: float = rect.position.x * _tile_size
	var y0: float = rect.position.y * _tile_size
	var x1: float = (rect.position.x + rect.size.x) * _tile_size
	var y1: float = (rect.position.y + rect.size.y) * _tile_size
	var poly := Polygon2D.new()
	poly.color = color
	poly.polygon = PackedVector2Array(
		[
			Vector2(x0, y0),
			Vector2(x1, y0),
			Vector2(x1, y1),
			Vector2(x0, y1),
		]
	)
	return poly


func _spawn_entity_view(entity: Entity, state: MatchState = null) -> void:
	if _entities_root == null or _registry == null:
		return
	# current_def_id tracks transforms (e.g. tank → siege_tank). Falls back
	# to def_id only at spawn time when current_def_id may not have been
	# initialized; the resolver clones it from def_id on entity creation.
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	var def: EntityDef = _registry.get_by_id(def_id)
	if def == null:
		return
	if _entity_view_scene == null:
		return
	var view := _entity_view_scene.instantiate() as EntityView
	if view == null:
		return
	_entities_root.add_child(view)
	view.bind_entity_id(entity.id)
	view.update_from_state(
		entity, def, _texture_for_def(def_id), _entity_rect_or_default(entity, state, def)
	)
	_views_by_id[entity.id] = view


# ADR-0010 says state.tile_grid.entity_rect(id) is the canonical placement
# source. Falls back to entity.origin + def.footprint only when no state
# is supplied (e.g., bind_state for an entity not yet placed) so callers
# don't have to pass state on the spawn path. Returns Rect2i.
func _entity_rect_or_default(entity: Entity, state: MatchState, def: EntityDef) -> Rect2i:
	if state != null and state.tile_grid != null:
		var rect: Rect2i = state.tile_grid.entity_rect(entity.id)
		if rect.size.x > 0 and rect.size.y > 0:
			return rect
	var fp: Vector2i = def.footprint if def != null else Vector2i.ONE
	return Rect2i(entity.origin, Vector2i(max(fp.x, 1), max(fp.y, 1)))


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
	# entities_sorted_by_id filters null slots that MatchState.clone()
	# preserves; iterating raw state.entities would crash here.
	for entity in state.entities_sorted_by_id():
		var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
		var def: EntityDef = _registry.get_by_id(def_id) if _registry != null else null
		var fp: Vector2i = def.footprint if def != null else Vector2i.ONE
		min_tile.x = min(min_tile.x, entity.origin.x)
		min_tile.y = min(min_tile.y, entity.origin.y)
		max_tile.x = max(max_tile.x, entity.origin.x + fp.x)
		max_tile.y = max(max_tile.y, entity.origin.y + fp.y)
	var center_tile := Vector2((min_tile.x + max_tile.x) / 2.0, (min_tile.y + max_tile.y) / 2.0)
	_camera.position = center_tile * _tile_size
	var viewport_size := Vector2(1280, 720)
	if is_inside_tree():
		viewport_size = get_viewport_rect().size
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


# Phase 1 of render_step. Spawn views for entities that appeared in
# new_state without a prior view. Doesn't update positions on existing
# views (that runs after events so attack lines are drawn at pre-event
# positions, not post-move ones) and doesn't prune anything (so
# fatal-target views survive long enough for ENTITY_DAMAGED /
# ENTITY_DESTROYED events to render against them).
func _spawn_added_views(new_state: MatchState) -> void:
	for entity in new_state.entities_sorted_by_id():
		if entity.current_hp <= 0:
			continue
		if not _views_by_id.has(entity.id):
			_spawn_entity_view(entity, new_state)


# Phase 3 of render_step. Drop views whose entity is missing from
# new_state or whose hp dropped to 0 this turn (resolver keeps the
# record around until end-of-turn cleanup). ENTITY_DESTROYED events
# already kicked off a fade for the killed entities; this call is the
# net for entities removed without an explicit destruction event.
func _prune_dead_views(new_state: MatchState) -> void:
	var live_ids: Dictionary[int, bool] = {}
	for entity in new_state.entities_sorted_by_id():
		if entity.current_hp > 0:
			live_ids[entity.id] = true
	for entity_id in _views_by_id.keys():
		if not live_ids.has(entity_id):
			_destroy_entity_view(entity_id)


# Phase 4 of render_step. Push the post-turn state into every surviving
# view (position, sprite swap on transform, modulate). Runs after
# events so attack-line endpoints reflect pre-event positions.
func _update_surviving_views(new_state: MatchState) -> void:
	if _registry == null:
		return
	for entity in new_state.entities_sorted_by_id():
		if entity.current_hp <= 0:
			continue
		var view: EntityView = _views_by_id.get(entity.id)
		if view == null:
			continue
		var def: EntityDef = _registry.get_by_id(entity.current_def_id)
		if def == null:
			continue
		(
			view
			. update_from_state(
				entity,
				def,
				_texture_for_def(entity.current_def_id),
				_entity_rect_or_default(entity, new_state, def),
			)
		)


func _reset_visibility_memory() -> void:
	_visibility_by_player.clear()
	_seen_tiles_by_player.clear()
	_seen_enemy_buildings_by_player.clear()
	for player_id in _player_ids():
		_seen_tiles_by_player[player_id] = {}
		_seen_enemy_buildings_by_player[player_id] = {}


func _refresh_all_visibility() -> void:
	if _state == null or _registry == null or _state.tile_grid == null:
		return
	_visibility_by_player.clear()
	for player_id in _player_ids():
		var visibility: VisionSystem.Visibility = VISION_SYSTEM_SCRIPT.compute_player_visibility(
			_state, _registry, player_id
		)
		_visibility_by_player[player_id] = visibility
		_remember_visible_tiles(player_id, visibility)
		_remember_visible_enemy_buildings(player_id, visibility)
	_refresh_entity_visibility()
	_rebuild_fog_overlay()


func _refresh_entity_visibility() -> void:
	if _state == null:
		return
	for entity in _state.entities_sorted_by_id():
		var view: EntityView = _views_by_id.get(entity.id)
		if view == null:
			continue
		var visible_now := _is_entity_currently_visible_for_player(entity, _perspective_player_id)
		var silhouette := false
		if not visible_now and _is_seen_enemy_building(_perspective_player_id, entity):
			silhouette = true
		view.visible = visible_now or silhouette
		view.set_fog_silhouette(silhouette)


func _rebuild_fog_overlay() -> void:
	_resolve_internal_nodes()
	if _fog_root == null:
		return
	for child in _fog_root.get_children():
		_fog_root.remove_child(child)
		child.queue_free()
	if _state == null or _state.tile_grid == null:
		return
	var visibility: VisionSystem.Visibility = _visibility_by_player.get(_perspective_player_id)
	if visibility == null:
		return
	for x in range(_state.tile_grid.width):
		for y in range(_state.tile_grid.height):
			var tile := Vector2i(x, y)
			if visibility.is_tile_visible(tile):
				continue
			var color := (
				_FOG_SEEN_COLOR
				if is_tile_previously_seen(_perspective_player_id, tile)
				else _FOG_UNSEEN_COLOR
			)
			_fog_root.add_child(_highlight_polygon(Rect2i(tile, Vector2i.ONE), color))


func _remember_visible_tiles(player_id: int, visibility: VisionSystem.Visibility) -> void:
	var seen: Dictionary = _seen_tiles_by_player.get(player_id, {})
	for tile in visibility.visible_tiles():
		seen[tile] = true
	_seen_tiles_by_player[player_id] = seen


func _remember_visible_enemy_buildings(player_id: int, visibility: VisionSystem.Visibility) -> void:
	var seen: Dictionary = _seen_enemy_buildings_by_player.get(player_id, {})
	for entity in _state.entities_sorted_by_id():
		if entity.owner_player_id == player_id or entity.owner_player_id < 0:
			continue
		if not _is_building(entity):
			continue
		if VISION_SYSTEM_SCRIPT.is_entity_visible_to_player(
			entity, _state, _registry, player_id, visibility
		):
			seen[entity.id] = true
	_seen_enemy_buildings_by_player[player_id] = seen


func _is_entity_hit_testable(entity_id: int) -> bool:
	var entity := _state.get_entity_by_id(entity_id)
	if entity == null or entity.current_hp <= 0:
		return false
	if entity.owner_player_id == _perspective_player_id:
		return true
	return _is_entity_currently_visible_for_player(entity, _perspective_player_id)


func _is_entity_currently_visible_for_player(entity: Entity, player_id: int) -> bool:
	var visibility = _visibility_by_player.get(player_id)
	if visibility == null:
		return entity != null and entity.owner_player_id == player_id
	return VISION_SYSTEM_SCRIPT.is_entity_visible_to_player(
		entity, _state, _registry, player_id, visibility
	)


func _is_seen_enemy_building(player_id: int, entity: Entity) -> bool:
	if entity == null or entity.owner_player_id == player_id or entity.owner_player_id < 0:
		return false
	if not _is_building(entity):
		return false
	var seen: Dictionary = _seen_enemy_buildings_by_player.get(player_id, {})
	return seen.has(entity.id)


func _is_building(entity: Entity) -> bool:
	if entity == null or _registry == null:
		return false
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	var def: EntityDef = _registry.get_by_id(def_id)
	return def != null and def.tags.has("building")


func _player_ids() -> Array[int]:
	var ids: Array[int] = []
	if _state != null:
		for player in _state.players:
			if player != null:
				ids.append(player.player_id)
	if ids.is_empty():
		ids = [0, 1]
	return ids


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
			# Render-order is: spawn → events → prune. The view is still
			# alive at this point (the prune phase below would have removed
			# it post-event). Kick off the fade now so the destruction
			# animation is tied to the event, not to the cleanup pass.
			if _views_by_id.has(event.target_id):
				_destroy_entity_view(event.target_id)
			_append_combat_log("#%d destroyed" % event.target_id)
		ResolverEvent.Type.MATCH_ENDED:
			# winner_player_id == -1 is the resolver's draw/unknown sentinel.
			# Render that explicitly rather than printing "P-1" as if it
			# were a real player.
			if event.winner_player_id < 0:
				_append_combat_log("Match ended — draw")
			else:
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
	# Maintain our own bounded buffer so the cap is exact and testable.
	# RichTextLabel.get_parsed_text() strips BBCode and may not preserve
	# trailing newlines, which made the previous "split-and-trim"
	# approach a no-op past the cap.
	_combat_log_lines.append(line)
	if _combat_log_lines.size() > _COMBAT_LOG_MAX_LINES:
		var overflow: int = _combat_log_lines.size() - _COMBAT_LOG_MAX_LINES
		_combat_log_lines = _combat_log_lines.slice(overflow)
	if _combat_log == null:
		return
	_combat_log.clear()
	_combat_log.append_text("\n".join(_combat_log_lines))
