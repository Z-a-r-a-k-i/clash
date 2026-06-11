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

# Camera margin in tiles for auto-fit candidates. Final camera bounds still
# clamp to the playable map, so margin is discarded when it would reveal
# outside the map.
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
const _RANGE_CURRENT_COLOR := Color(0.05, 0.55, 1.0, 0.20)
const _RANGE_PROJECTED_COLOR := Color(1.0, 0.74, 0.16, 0.24)
const _BUILD_PLACEMENT_VALID_COLOR := Color(0.0, 0.88, 0.72, 0.30)
const _BUILD_PLACEMENT_INVALID_COLOR := Color(1.0, 0.08, 0.08, 0.30)
const _BUILD_PLACEMENT_GRID_ALPHA := 0.72
const _BUILD_PLACEMENT_BORDER_WIDTH := 2.0
const _BUILD_PLACEMENT_GRID_WIDTH := 1.0
const _ACTION_PREVIEW_COLOR := Color(0.2, 0.95, 0.9, 0.86)
const _ACTION_PREVIEW_STOP_COLOR := Color(1.0, 0.78, 0.12, 0.96)
const _ACTION_PREVIEW_STOP_OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.85)
const _ACTION_PREVIEW_TEXT_COLOR := Color(0.95, 1.0, 1.0, 1.0)
const _ACTION_PREVIEW_LINE_WIDTH := 3.0
const _ACTION_PREVIEW_FONT_SIZE := 18
const _TARGET_INTENT_COLOR := Color(1.0, 0.34, 0.08, 0.92)
const _TARGET_INTENT_LINE_WIDTH := 3.0
const _TARGET_INTENT_DASH_PIXELS := 14.0
const _TARGET_INTENT_GAP_PIXELS := 8.0
const _TARGET_INTENT_RETICLE_RADIUS := 14.0
const _IDLE_WORKER_BADGE_BACK := Color(1.0, 0.62, 0.05, 0.96)
const _IDLE_WORKER_BADGE_OUTLINE := Color(0.0, 0.0, 0.0, 0.82)
const _IDLE_WORKER_BADGE_TEXT := Color(0.08, 0.06, 0.02, 1.0)
const _IDLE_WORKER_BADGE_RADIUS := 13.0
const _IDLE_WORKER_BADGE_FONT_SIZE := 20
const _IDLE_WORKER_BADGE_OFFSET_Y := 30.0
const _PRODUCTION_PROGRESS_BACK := Color(0.0, 0.0, 0.0, 0.68)
const _PRODUCTION_PROGRESS_FILL := Color(0.2, 0.95, 0.45, 0.95)
const _PRODUCTION_PROGRESS_SIZE := Vector2(64.0, 8.0)
const _CONSTRUCTION_PROGRESS_BACK := Color(0.0, 0.0, 0.0, 0.68)
const _CONSTRUCTION_PROGRESS_FILL := Color(0.2, 0.95, 0.45, 0.95)
const _CONSTRUCTION_PROGRESS_PAUSED_FILL := Color(1.0, 0.58, 0.12, 0.96)
const _CONSTRUCTION_PROGRESS_SIZE := Vector2(64.0, 8.0)
const _FOG_OUT_OF_VISION_COLOR := Color(0.0, 0.0, 0.0, 0.22)
const _DEV_PLAYABLE_ZOOM := 1.1
const _MIN_CAMERA_ZOOM := 0.5
const _MAX_CAMERA_ZOOM := 4.0
const _DEFAULT_LOGICAL_VIEWPORT_SIZE := Vector2(1920.0, 1080.0)
const _VIEWPORT_WIDTH_SETTING := "display/window/size/viewport_width"
const _VIEWPORT_HEIGHT_SETTING := "display/window/size/viewport_height"
const _BUILDING_MEMORY_ENTITY := "entity"
const _BUILDING_MEMORY_RECT := "rect"
const _ZOOM_DEBUG_NODE_NAME := "ZoomDebug"
const _ZOOM_DEBUG_OFFSET_LEFT := 12.0
const _ZOOM_DEBUG_OFFSET_TOP := -96.0
const _ZOOM_DEBUG_OFFSET_RIGHT := 372.0
const _ZOOM_DEBUG_OFFSET_BOTTOM := -20.0
const _ZOOM_DEBUG_FONT_SIZE := 18

# Hit flash applied to the target sprite for ~150 ms when ENTITY_DAMAGED
# fires. Quick pulse to white-ish gives a readable "got hit" cue without
# disturbing the team-color modulate when the tween clears.
const _HIT_FLASH_SECONDS := 0.18
const _HIT_FLASH_COLOR := Color(2.5, 2.5, 2.5)
const _RESOLVE_PROFILE_FLAG_PATH := "res://resolver_profile_enabled"
const _RENDER_PROFILE_LOG_PATH := "user://match_renderer_step_latest.log"
const _VISIBILITY_PROFILE_LOG_PATH := "user://match_renderer_visibility_latest.log"

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
var _texture_by_def_id: Dictionary = {}

var _selected_entity_ids: Array[int] = []
var _hover_tile: Vector2i = Vector2i.ZERO
var _has_hover_tile: bool = false
var _selection_box_world_rect: Rect2 = Rect2()
var _has_selection_box: bool = false
var _perspective_player_id: int = 0
var _visibility_by_player: Dictionary = {}
var _seen_tiles_by_player: Dictionary = {}
var _seen_enemy_building_snapshots_by_player: Dictionary = {}
var _event_visible_entity_ids: Dictionary[int, bool] = {}
var _zoom_debug_text: String = ""
var _zoom_debug_visible: bool = false
var _camera_screen_safe_margins: Vector4 = Vector4.ZERO
var _fog_overlay_signature: String = ""
var _has_fog_overlay_cache := false
var _fog_overlay_tile_count := 0
var _range_preview_signature: String = ""

@onready var _entities_root: Node2D = $Entities
@onready var _terrain: TileMapLayer = $Terrain
@onready var _camera: Camera2D = $Camera2D
@onready var _fog_root: Node2D = $Overlays/Fog
@onready var _attack_lines_root: Node2D = $Overlays/AttackLines
@onready var _input_highlights_root: Node2D = $Overlays/Highlights
@onready var _range_previews_root: Node2D = get_node_or_null("Overlays/RangePreviews") as Node2D
@onready var _build_placement_preview_root: Node2D = (
	get_node_or_null("Overlays/BuildPlacementPreview") as Node2D
)
@onready var _action_previews_root: Node2D = get_node_or_null("Overlays/ActionPreviews") as Node2D
@onready var _target_intents_root: Node2D = get_node_or_null("Overlays/TargetIntents") as Node2D
@onready
var _idle_worker_indicators_root: Node2D = get_node_or_null("Overlays/IdleWorkers") as Node2D
@onready
var _production_progress_root: Node2D = get_node_or_null("Overlays/ProductionProgress") as Node2D
@onready var _construction_progress_root: Node2D = (
	get_node_or_null("Overlays/ConstructionProgress") as Node2D
)
@onready var _damage_labels_root: Node2D = $Overlays/DamageLabels
@onready var _combat_log: RichTextLabel = get_node_or_null("HUD/CombatLog") as RichTextLabel
@onready var _zoom_debug: Label = get_node_or_null("HUD/ZoomDebug") as Label


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
		if not _is_renderable_entity(entity):
			continue
		_spawn_entity_view(entity, state)

	_reset_visibility_memory()
	_seed_known_starting_base_snapshots()
	_refresh_all_visibility()
	_rebuild_production_progress()
	_rebuild_construction_progress()
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
	var profile_enabled := FileAccess.file_exists(_RESOLVE_PROFILE_FLAG_PATH)
	var profile_lines: Array[String] = []
	var profile_total_start := Time.get_ticks_usec()
	var profile_step := profile_total_start
	if profile_enabled:
		profile_lines.append(
			"[render_step_profile] captured_at=%s" % Time.get_datetime_string_from_system()
		)
		profile_lines.append("[render_step_profile] events=%d" % events.size())
	_resolve_internal_nodes()
	if profile_enabled:
		profile_lines.append(
			(
				"[render_step_profile] resolve_internal_nodes=%.3fms"
				% (float(Time.get_ticks_usec() - profile_step) / 1000.0)
			)
		)
		profile_step = Time.get_ticks_usec()
	var event_visible_ids: Dictionary[int, bool] = _visible_entity_ids_for_player(
		_perspective_player_id
	)
	if profile_enabled:
		profile_lines.append(
			(
				"[render_step_profile] visible_ids_for_events=%.3fms"
				% (float(Time.get_ticks_usec() - profile_step) / 1000.0)
			)
		)
		profile_step = Time.get_ticks_usec()
	_state = new_state
	if new_state == null:
		if profile_enabled:
			profile_lines.append("[render_step_profile] new_state_null=true")
			_emit_render_step_profile(profile_lines)
		return
	_spawn_added_views(new_state)
	if profile_enabled:
		profile_lines.append(
			(
				"[render_step_profile] spawn_added_views=%.3fms"
				% (float(Time.get_ticks_usec() - profile_step) / 1000.0)
			)
		)
		profile_step = Time.get_ticks_usec()
	_event_visible_entity_ids = event_visible_ids
	for event in events:
		_render_event(event)
	_event_visible_entity_ids = {}
	if profile_enabled:
		profile_lines.append(
			(
				"[render_step_profile] render_events=%.3fms"
				% (float(Time.get_ticks_usec() - profile_step) / 1000.0)
			)
		)
		profile_step = Time.get_ticks_usec()
	_prune_dead_views(new_state)
	if profile_enabled:
		profile_lines.append(
			(
				"[render_step_profile] prune_dead_views=%.3fms"
				% (float(Time.get_ticks_usec() - profile_step) / 1000.0)
			)
		)
		profile_step = Time.get_ticks_usec()
	_update_surviving_views(new_state)
	if profile_enabled:
		profile_lines.append(
			(
				"[render_step_profile] update_surviving_views=%.3fms"
				% (float(Time.get_ticks_usec() - profile_step) / 1000.0)
			)
		)
		profile_step = Time.get_ticks_usec()
	_refresh_all_visibility()
	if profile_enabled:
		profile_lines.append(
			(
				"[render_step_profile] refresh_all_visibility=%.3fms"
				% (float(Time.get_ticks_usec() - profile_step) / 1000.0)
			)
		)
		profile_step = Time.get_ticks_usec()
	_rebuild_production_progress()
	if profile_enabled:
		profile_lines.append(
			(
				"[render_step_profile] rebuild_production_progress=%.3fms"
				% (float(Time.get_ticks_usec() - profile_step) / 1000.0)
			)
		)
		profile_step = Time.get_ticks_usec()
	_rebuild_construction_progress()
	if profile_enabled:
		profile_lines.append(
			(
				"[render_step_profile] rebuild_construction_progress=%.3fms"
				% (float(Time.get_ticks_usec() - profile_step) / 1000.0)
			)
		)
		profile_lines.append(
			(
				"[render_step_profile] total=%.3fms"
				% (float(Time.get_ticks_usec() - profile_total_start) / 1000.0)
			)
		)
		_emit_render_step_profile(profile_lines)


func _emit_render_step_profile(lines: Array[String]) -> void:
	for line in lines:
		print(line)
	var file := FileAccess.open(_RENDER_PROFILE_LOG_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")


func _emit_visibility_profile(lines: Array[String]) -> void:
	for line in lines:
		print(line)
	var file := FileAccess.open(_VISIBILITY_PROFILE_LOG_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")


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


func zoom_debug_text() -> String:
	return _zoom_debug_text


func set_zoom_debug_visible(visible: bool) -> void:
	_zoom_debug_visible = visible
	_resolve_internal_nodes()
	if _zoom_debug != null:
		_zoom_debug.visible = visible


func zoom_debug_visible() -> bool:
	return _zoom_debug_visible


func set_camera_screen_safe_margins(left: float, top: float, right: float, bottom: float) -> void:
	_camera_screen_safe_margins = Vector4(
		maxf(left, 0.0), maxf(top, 0.0), maxf(right, 0.0), maxf(bottom, 0.0)
	)
	_resolve_internal_nodes()
	_apply_camera_screen_offset()
	if _camera != null:
		_set_camera_zoom(_camera.zoom.x)


func camera_screen_safe_margins() -> Vector4:
	return _camera_screen_safe_margins


func screen_to_world(screen_position: Vector2) -> Vector2:
	var viewport: Viewport = _render_viewport()
	if viewport == null:
		return screen_position
	return viewport.get_canvas_transform().affine_inverse() * screen_position


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
	var entity := _state.get_entity_by_id(entity_id)
	var refinery_id: int = _known_covering_refinery_id_for_gas_geyser(
		entity, _perspective_player_id
	)
	if refinery_id >= 0:
		return refinery_id if _is_entity_hit_testable(refinery_id) else -1
	return entity_id if _is_entity_hit_testable(entity_id) else -1


func entity_id_at_world(world_position: Vector2) -> int:
	return entity_id_at_tile(world_to_tile(world_position))


func set_selected_entity_id(entity_id: int) -> void:
	if entity_id < 0:
		_selected_entity_ids.clear()
	else:
		_selected_entity_ids = [entity_id]
	_rebuild_input_highlights()


func set_selected_entity_ids(entity_ids: Array) -> void:
	_selected_entity_ids.clear()
	for raw_entity_id in entity_ids:
		var entity_id: int = int(raw_entity_id)
		if entity_id < 0:
			continue
		if _selected_entity_ids.has(entity_id):
			continue
		_selected_entity_ids.append(entity_id)
	_rebuild_input_highlights()


func set_hover_tile(tile: Vector2i) -> void:
	_hover_tile = tile
	_has_hover_tile = true
	_rebuild_input_highlights()


func clear_input_highlights() -> void:
	_selected_entity_ids.clear()
	_has_hover_tile = false
	_has_selection_box = false
	_clear_input_highlight_nodes()
	_clear_range_preview_nodes()
	_clear_build_placement_preview_nodes()


func input_highlight_count() -> int:
	if _input_highlights_root == null:
		return 0
	return _input_highlights_root.get_child_count()


func set_range_preview_tiles(current_tiles: Array, projected_tiles: Array) -> void:
	_resolve_internal_nodes()
	var signature: String = _range_preview_signature_for(current_tiles, projected_tiles)
	if signature == _range_preview_signature:
		return
	_clear_range_preview_nodes()
	_range_preview_signature = signature
	if _range_previews_root == null:
		return
	for item in current_tiles:
		var tile: Vector2i = item
		_range_previews_root.add_child(
			_highlight_polygon(Rect2i(tile, Vector2i.ONE), _RANGE_CURRENT_COLOR)
		)
	for item in projected_tiles:
		var tile: Vector2i = item
		_range_previews_root.add_child(
			_highlight_polygon(Rect2i(tile, Vector2i.ONE), _RANGE_PROJECTED_COLOR)
		)


func clear_range_preview_tiles() -> void:
	_clear_range_preview_nodes()


func range_preview_tile_count() -> int:
	if _range_previews_root == null:
		return 0
	return _range_previews_root.get_child_count()


func set_selection_box_world_rect(rect: Rect2) -> void:
	_selection_box_world_rect = rect.abs()
	_has_selection_box = (
		_selection_box_world_rect.size.x > 0.0 and _selection_box_world_rect.size.y > 0.0
	)
	_rebuild_input_highlights()


func clear_selection_box() -> void:
	_has_selection_box = false
	_selection_box_world_rect = Rect2()
	_rebuild_input_highlights()


func is_selection_box_visible() -> bool:
	return _has_selection_box


func owned_movable_entity_ids_in_world_rect(world_rect: Rect2, owner_player_id: int) -> Array[int]:
	var out: Array[int] = []
	if _state == null or _registry == null:
		return out
	var query: Rect2 = world_rect.abs()
	if query.size.x <= 0.0 or query.size.y <= 0.0:
		return out
	for entity in _state.entities_sorted_by_id():
		if entity == null or entity.owner_player_id != owner_player_id or entity.current_hp <= 0:
			continue
		if not _is_movable_entity(entity):
			continue
		var entity_rect: Rect2 = _query_entity_world_rect(entity)
		if entity_rect.size.x <= 0.0 or entity_rect.size.y <= 0.0:
			continue
		if query.intersects(entity_rect, true):
			out.append(entity.id)
	return out


func set_build_placement_preview(preview: Dictionary) -> void:
	_resolve_internal_nodes()
	_clear_build_placement_preview_nodes()
	if _build_placement_preview_root == null or preview.is_empty():
		return
	var origin: Vector2i = preview.get("origin", Vector2i.ZERO)
	var footprint: Vector2i = preview.get("footprint", Vector2i.ONE)
	var rect: Rect2i = preview.get("rect", Rect2i(origin, footprint))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var valid: bool = preview.get("valid", false)
	_build_placement_preview_root.add_child(_build_placement_preview_group(rect, valid))


func clear_build_placement_preview() -> void:
	_clear_build_placement_preview_nodes()


func build_placement_preview_count() -> int:
	if _build_placement_preview_root == null:
		return 0
	return _build_placement_preview_root.get_child_count()


func set_action_previews(previews: Array) -> void:
	_resolve_internal_nodes()
	_clear_action_preview_nodes()
	if _action_previews_root == null:
		return
	for preview in previews:
		var preview_dict: Dictionary = preview
		_render_action_preview(preview_dict)


func action_preview_count() -> int:
	if _action_previews_root == null:
		return 0
	return _action_previews_root.get_child_count()


func set_target_intent_previews(previews: Array) -> void:
	_resolve_internal_nodes()
	_clear_target_intent_preview_nodes()
	if _target_intents_root == null:
		return
	for preview in previews:
		var preview_dict: Dictionary = preview
		_render_target_intent_preview(preview_dict)


func target_intent_preview_count() -> int:
	if _target_intents_root == null:
		return 0
	return _target_intents_root.get_child_count()


func set_idle_worker_indicators(indicators: Array[Variant]) -> void:
	_resolve_internal_nodes()
	_clear_idle_worker_indicator_nodes()
	if _idle_worker_indicators_root == null:
		return
	for indicator: Variant in indicators:
		var entity_id: int = _indicator_entity_id(indicator)
		if entity_id < 0:
			continue
		_render_idle_worker_indicator(entity_id)


func idle_worker_indicator_count() -> int:
	if _idle_worker_indicators_root == null:
		return 0
	return _idle_worker_indicators_root.get_child_count()


func action_preview_line_point_count(preview_index: int) -> int:
	if _action_previews_root == null:
		return 0
	if preview_index < 0 or preview_index >= _action_previews_root.get_child_count():
		return 0
	var group: Node = _action_previews_root.get_child(preview_index)
	for child in group.get_children():
		var line: Line2D = child as Line2D
		if line != null:
			return line.points.size()
	return 0


func action_preview_stop_marker_count() -> int:
	if _action_previews_root == null:
		return 0
	var count := 0
	for group in _action_previews_root.get_children():
		for child in group.get_children():
			if child.name == "TurnStopMarker":
				count += 1
	return count


func action_preview_stop_marker_tile(marker_index: int) -> Vector2i:
	if _action_previews_root == null:
		return Vector2i(-999999, -999999)
	var seen := 0
	for group in _action_previews_root.get_children():
		for child in group.get_children():
			if child.name != "TurnStopMarker":
				continue
			if seen == marker_index:
				return child.get_meta("tile", Vector2i(-999999, -999999))
			seen += 1
	return Vector2i(-999999, -999999)


func production_progress_count() -> int:
	if _production_progress_root == null:
		return 0
	return _production_progress_root.get_child_count()


func construction_progress_count() -> int:
	if _construction_progress_root == null:
		return 0
	return _construction_progress_root.get_child_count()


func set_perspective_player_id(player_id: int) -> void:
	_perspective_player_id = player_id
	_refresh_entity_visibility()
	_rebuild_fog_overlay()
	_rebuild_production_progress()
	_rebuild_construction_progress()


func perspective_player_id() -> int:
	return _perspective_player_id


func focus_player_start(player_id: int) -> void:
	_resolve_internal_nodes()
	if _camera == null:
		return
	var bounds: Rect2 = _player_world_bounds(player_id)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		bounds = _map_world_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	_camera.position = bounds.get_center()
	_set_camera_zoom(_DEV_PLAYABLE_ZOOM)


func zoom_camera(multiplier: float) -> void:
	_resolve_internal_nodes()
	if _camera == null or multiplier <= 0.0:
		return
	_set_camera_zoom(_camera.zoom.x * multiplier)


func pan_camera_by_screen_delta(delta: Vector2) -> void:
	_resolve_internal_nodes()
	if _camera == null:
		return
	var safe_zoom: float = maxf(_camera.zoom.x, 0.01)
	_camera.position -= delta / safe_zoom
	_clamp_camera_to_map_bounds()


func is_entity_view_visible(entity_id: int) -> bool:
	var view: EntityView = _views_by_id.get(entity_id)
	return view != null and view.visible


func is_entity_view_silhouette(entity_id: int) -> bool:
	var view: EntityView = _views_by_id.get(entity_id)
	return view != null and view.visible and view.is_fog_silhouette()


func fog_overlay_count() -> int:
	if _fog_root == null:
		return 0
	return _fog_overlay_tile_count


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
	_apply_camera_screen_offset()
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
	if _range_previews_root == null:
		var overlays := get_node_or_null("Overlays") as Node2D
		if overlays != null:
			_range_previews_root = Node2D.new()
			_range_previews_root.name = "RangePreviews"
			overlays.add_child(_range_previews_root)
	if _build_placement_preview_root == null:
		var overlays := get_node_or_null("Overlays") as Node2D
		if overlays != null:
			_build_placement_preview_root = Node2D.new()
			_build_placement_preview_root.name = "BuildPlacementPreview"
			overlays.add_child(_build_placement_preview_root)
	if _action_previews_root == null:
		var overlays := get_node_or_null("Overlays") as Node2D
		if overlays != null:
			_action_previews_root = Node2D.new()
			_action_previews_root.name = "ActionPreviews"
			overlays.add_child(_action_previews_root)
	if _target_intents_root == null:
		var overlays := get_node_or_null("Overlays") as Node2D
		if overlays != null:
			_target_intents_root = Node2D.new()
			_target_intents_root.name = "TargetIntents"
			overlays.add_child(_target_intents_root)
	if _idle_worker_indicators_root == null:
		var overlays := get_node_or_null("Overlays") as Node2D
		if overlays != null:
			_idle_worker_indicators_root = Node2D.new()
			_idle_worker_indicators_root.name = "IdleWorkers"
			overlays.add_child(_idle_worker_indicators_root)
	if _production_progress_root == null:
		var overlays := get_node_or_null("Overlays") as Node2D
		if overlays != null:
			_production_progress_root = Node2D.new()
			_production_progress_root.name = "ProductionProgress"
			overlays.add_child(_production_progress_root)
	if _construction_progress_root == null:
		var overlays := get_node_or_null("Overlays") as Node2D
		if overlays != null:
			_construction_progress_root = Node2D.new()
			_construction_progress_root.name = "ConstructionProgress"
			overlays.add_child(_construction_progress_root)
	if _damage_labels_root == null:
		_damage_labels_root = get_node_or_null("Overlays/DamageLabels") as Node2D
	if _combat_log == null:
		_combat_log = get_node_or_null("HUD/CombatLog") as RichTextLabel
	if _zoom_debug == null:
		_zoom_debug = get_node_or_null("HUD/ZoomDebug") as Label
	if _zoom_debug == null:
		var hud: CanvasLayer = get_node_or_null("HUD") as CanvasLayer
		if hud != null:
			_zoom_debug = Label.new()
			_zoom_debug.name = _ZOOM_DEBUG_NODE_NAME
			_zoom_debug.add_theme_font_size_override("font_size", _ZOOM_DEBUG_FONT_SIZE)
			_zoom_debug.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0, 1.0))
			_zoom_debug.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
			_zoom_debug.add_theme_constant_override("shadow_offset_x", 1)
			_zoom_debug.add_theme_constant_override("shadow_offset_y", 1)
			hud.add_child(_zoom_debug)
	if _zoom_debug != null:
		_configure_zoom_debug_label()


func _configure_zoom_debug_label() -> void:
	_zoom_debug.anchor_left = 0.0
	_zoom_debug.anchor_right = 0.0
	_zoom_debug.anchor_top = 1.0
	_zoom_debug.anchor_bottom = 1.0
	_zoom_debug.offset_left = _ZOOM_DEBUG_OFFSET_LEFT
	_zoom_debug.offset_right = _ZOOM_DEBUG_OFFSET_RIGHT
	_zoom_debug.offset_top = _ZOOM_DEBUG_OFFSET_TOP
	_zoom_debug.offset_bottom = _ZOOM_DEBUG_OFFSET_BOTTOM
	_zoom_debug.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom_debug.visible = _zoom_debug_visible


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
	for root in [
		_fog_root,
		_attack_lines_root,
		_range_previews_root,
		_build_placement_preview_root,
		_action_previews_root,
		_target_intents_root,
		_idle_worker_indicators_root,
		_production_progress_root,
		_construction_progress_root,
		_damage_labels_root,
	]:
		if root == null:
			continue
		for child in root.get_children():
			root.remove_child(child)
			child.queue_free()


func _clear_range_preview_nodes() -> void:
	_range_preview_signature = ""
	if _range_previews_root == null:
		return
	for child in _range_previews_root.get_children():
		_range_previews_root.remove_child(child)
		child.queue_free()


func _range_preview_signature_for(current_tiles: Array, projected_tiles: Array) -> String:
	var parts: Array[String] = ["current"]
	for item in current_tiles:
		var tile: Vector2i = item
		parts.append("%d,%d" % [tile.x, tile.y])
	parts.append("projected")
	for item in projected_tiles:
		var tile: Vector2i = item
		parts.append("%d,%d" % [tile.x, tile.y])
	return "|".join(parts)


func _clear_input_highlight_nodes() -> void:
	if _input_highlights_root == null:
		return
	for child in _input_highlights_root.get_children():
		_input_highlights_root.remove_child(child)
		child.queue_free()


func _clear_action_preview_nodes() -> void:
	if _action_previews_root == null:
		return
	for child in _action_previews_root.get_children():
		_action_previews_root.remove_child(child)
		child.queue_free()


func _clear_target_intent_preview_nodes() -> void:
	if _target_intents_root == null:
		return
	for child in _target_intents_root.get_children():
		_target_intents_root.remove_child(child)
		child.queue_free()


func _clear_idle_worker_indicator_nodes() -> void:
	if _idle_worker_indicators_root == null:
		return
	for child in _idle_worker_indicators_root.get_children():
		_idle_worker_indicators_root.remove_child(child)
		child.queue_free()


func _clear_build_placement_preview_nodes() -> void:
	if _build_placement_preview_root == null:
		return
	for child in _build_placement_preview_root.get_children():
		_build_placement_preview_root.remove_child(child)
		child.queue_free()


func _clear_production_progress_nodes() -> void:
	if _production_progress_root == null:
		return
	for child in _production_progress_root.get_children():
		_production_progress_root.remove_child(child)
		child.queue_free()


func _clear_construction_progress_nodes() -> void:
	if _construction_progress_root == null:
		return
	for child in _construction_progress_root.get_children():
		_construction_progress_root.remove_child(child)
		child.queue_free()


func _rebuild_input_highlights() -> void:
	_resolve_internal_nodes()
	_clear_input_highlight_nodes()
	if _input_highlights_root == null:
		return
	if _state != null and _state.tile_grid != null:
		for entity_id in _selected_entity_ids:
			var selected_rect: Rect2i = _state.tile_grid.entity_rect(entity_id)
			if selected_rect.size.x > 0 and selected_rect.size.y > 0:
				_input_highlights_root.add_child(
					_highlight_polygon(selected_rect, _SELECTED_HIGHLIGHT_COLOR)
				)
	if _has_hover_tile:
		_input_highlights_root.add_child(
			_highlight_polygon(Rect2i(_hover_tile, Vector2i.ONE), _HOVER_HIGHLIGHT_COLOR)
		)
	if _has_selection_box:
		_input_highlights_root.add_child(
			_world_rect_polygon(_selection_box_world_rect, _SELECTED_HIGHLIGHT_COLOR)
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


func _world_rect_polygon(rect: Rect2, color: Color) -> Polygon2D:
	var normalized: Rect2 = rect.abs()
	var poly := Polygon2D.new()
	poly.color = color
	poly.polygon = PackedVector2Array(
		[
			normalized.position,
			Vector2(normalized.end.x, normalized.position.y),
			normalized.end,
			Vector2(normalized.position.x, normalized.end.y),
		]
	)
	return poly


func _build_placement_preview_group(rect: Rect2i, valid: bool) -> Node2D:
	var group := Node2D.new()
	group.name = "BuildPlacementPreview"
	var fill_color: Color = (
		_BUILD_PLACEMENT_VALID_COLOR if valid else _BUILD_PLACEMENT_INVALID_COLOR
	)
	var line_color := Color(fill_color.r, fill_color.g, fill_color.b, _BUILD_PLACEMENT_GRID_ALPHA)
	var x0: float = rect.position.x * _tile_size
	var y0: float = rect.position.y * _tile_size
	var x1: float = (rect.position.x + rect.size.x) * _tile_size
	var y1: float = (rect.position.y + rect.size.y) * _tile_size
	group.add_child(_highlight_polygon(rect, fill_color))
	var border := Line2D.new()
	border.default_color = line_color
	border.width = _BUILD_PLACEMENT_BORDER_WIDTH
	border.points = PackedVector2Array(
		[
			Vector2(x0, y0),
			Vector2(x1, y0),
			Vector2(x1, y1),
			Vector2(x0, y1),
			Vector2(x0, y0),
		]
	)
	group.add_child(border)
	for x in range(rect.position.x + 1, rect.position.x + rect.size.x):
		var x_px: float = x * _tile_size
		group.add_child(
			_build_placement_grid_line(Vector2(x_px, y0), Vector2(x_px, y1), line_color)
		)
	for y in range(rect.position.y + 1, rect.position.y + rect.size.y):
		var y_px: float = y * _tile_size
		group.add_child(
			_build_placement_grid_line(Vector2(x0, y_px), Vector2(x1, y_px), line_color)
		)
	return group


func _build_placement_grid_line(start: Vector2, finish: Vector2, color: Color) -> Line2D:
	var line := Line2D.new()
	line.default_color = color
	line.width = _BUILD_PLACEMENT_GRID_WIDTH
	line.points = PackedVector2Array([start, finish])
	return line


func _render_action_preview(preview: Dictionary) -> void:
	var actor_id: int = preview.get("entity_id", -1)
	var actor_view: EntityView = _views_by_id.get(actor_id)
	if actor_view == null or not actor_view.visible:
		return
	var group := Node2D.new()
	group.name = "ActionPreview_%d" % actor_id
	var preview_color: Color = _ACTION_PREVIEW_COLOR
	if preview.get("future", false):
		preview_color = Color(
			_ACTION_PREVIEW_COLOR.r,
			_ACTION_PREVIEW_COLOR.g,
			_ACTION_PREVIEW_COLOR.b,
			_ACTION_PREVIEW_COLOR.a * 0.62
		)
	var start: Vector2 = actor_view.position
	if preview.has("start_tile"):
		var start_tile: Vector2i = preview.get("start_tile", Vector2i.ZERO)
		start = _tile_center(start_tile)
	var target: Vector2 = start
	var has_target := false
	var line_points: PackedVector2Array = []
	var path: Array = preview.get("path", [])
	if not path.is_empty():
		line_points.append(start)
		for item in path:
			var path_tile: Vector2i = item
			line_points.append(_tile_center(path_tile))
		target = line_points[line_points.size() - 1]
		has_target = true
	var target_entity_id: int = preview.get("target_entity_id", -1)
	if not has_target and target_entity_id >= 0:
		var target_view: EntityView = _views_by_id.get(target_entity_id)
		if target_view != null and target_view.visible:
			target = target_view.position
			has_target = true
	if not has_target and preview.has("target_tile"):
		var target_tile: Vector2i = preview.get("target_tile", Vector2i.ZERO)
		target = _tile_center(target_tile)
		has_target = true
	if has_target:
		if line_points.is_empty():
			line_points = PackedVector2Array([start, target])
		var line := Line2D.new()
		line.default_color = preview_color
		line.width = _ACTION_PREVIEW_LINE_WIDTH
		line.points = line_points
		group.add_child(line)
		if preview.has("turn_stop_tile"):
			var stop_tile: Vector2i = preview.get("turn_stop_tile", Vector2i(-999999, -999999))
			if stop_tile != Vector2i(-999999, -999999):
				var stop_alpha: float = preview_color.a / maxf(_ACTION_PREVIEW_COLOR.a, 0.001)
				group.add_child(_turn_stop_marker(stop_tile, stop_alpha))
		group.add_child(_target_marker(target, preview_color))
	var label := Label.new()
	label.text = _preview_label(preview)
	label.modulate = _ACTION_PREVIEW_TEXT_COLOR
	label.add_theme_font_size_override("font_size", _ACTION_PREVIEW_FONT_SIZE)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(120.0, 0.0)
	label.position = (target if has_target else start) + Vector2(-60.0, -32.0)
	group.add_child(label)
	_action_previews_root.add_child(group)


func _render_target_intent_preview(preview: Dictionary) -> void:
	var actor_id: int = preview.get("entity_id", -1)
	var target_id: int = preview.get("target_entity_id", -1)
	var actor_view: EntityView = _views_by_id.get(actor_id)
	var target_view: EntityView = _views_by_id.get(target_id)
	if actor_view == null or target_view == null:
		return
	if not actor_view.visible or not target_view.visible:
		return
	var start: Vector2 = actor_view.position
	if preview.has("start_tile"):
		var start_tile: Vector2i = preview.get("start_tile", Vector2i.ZERO)
		start = _tile_center(start_tile)
	var target: Vector2 = target_view.position
	var group := Node2D.new()
	group.name = "TargetIntent_%d_%d" % [actor_id, target_id]
	_add_target_intent_dashes(group, start, target)
	group.add_child(_target_intent_reticle(target))
	_target_intents_root.add_child(group)


func _indicator_entity_id(indicator: Variant) -> int:
	if indicator is Dictionary:
		var data: Dictionary = indicator
		return int(data.get("entity_id", -1))
	if indicator is int:
		return int(indicator)
	return -1


func _render_idle_worker_indicator(entity_id: int) -> void:
	var view: EntityView = _views_by_id.get(entity_id)
	if view == null or not view.visible:
		return
	var group := Node2D.new()
	group.name = "IdleWorker_%d" % entity_id
	group.position = view.position + Vector2(0.0, -_IDLE_WORKER_BADGE_OFFSET_Y)
	var outline := Polygon2D.new()
	outline.color = _IDLE_WORKER_BADGE_OUTLINE
	outline.polygon = _regular_polygon_points(_IDLE_WORKER_BADGE_RADIUS + 2.0, 8)
	group.add_child(outline)
	var fill := Polygon2D.new()
	fill.color = _IDLE_WORKER_BADGE_BACK
	fill.polygon = _regular_polygon_points(_IDLE_WORKER_BADGE_RADIUS, 8)
	group.add_child(fill)
	var label := Label.new()
	label.text = "!"
	label.modulate = _IDLE_WORKER_BADGE_TEXT
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", _IDLE_WORKER_BADGE_FONT_SIZE)
	label.add_theme_color_override("font_outline_color", _IDLE_WORKER_BADGE_OUTLINE)
	label.add_theme_constant_override("outline_size", 2)
	label.size = Vector2(_IDLE_WORKER_BADGE_RADIUS * 2.0, _IDLE_WORKER_BADGE_RADIUS * 2.0)
	label.position = -label.size * 0.5
	group.add_child(label)
	_idle_worker_indicators_root.add_child(group)


func _regular_polygon_points(radius: float, sides: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	if sides < 3:
		return points
	for i in range(sides):
		var angle: float = -PI * 0.5 + TAU * float(i) / float(sides)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _add_target_intent_dashes(group: Node2D, start: Vector2, finish: Vector2) -> void:
	var delta: Vector2 = finish - start
	var length: float = delta.length()
	if length <= 0.5:
		return
	var direction: Vector2 = delta / length
	var cursor := 0.0
	var last_end := 0.0
	while cursor < length:
		var segment_end: float = minf(cursor + _TARGET_INTENT_DASH_PIXELS, length)
		_add_target_intent_segment(group, start, direction, cursor, segment_end)
		last_end = segment_end
		cursor += _TARGET_INTENT_DASH_PIXELS + _TARGET_INTENT_GAP_PIXELS
	if last_end < length:
		var final_start: float = maxf(last_end, length - _TARGET_INTENT_DASH_PIXELS)
		_add_target_intent_segment(group, start, direction, final_start, length)


func _add_target_intent_segment(
	group: Node2D, origin: Vector2, direction: Vector2, segment_start: float, segment_end: float
) -> void:
	if segment_end <= segment_start:
		return
	var line := Line2D.new()
	line.name = "TargetIntentLine"
	line.default_color = _TARGET_INTENT_COLOR
	line.width = _TARGET_INTENT_LINE_WIDTH
	line.points = PackedVector2Array(
		[origin + direction * segment_start, origin + direction * segment_end]
	)
	group.add_child(line)


func _target_intent_reticle(marker_position: Vector2) -> Polygon2D:
	var marker := Polygon2D.new()
	marker.name = "TargetReticle"
	marker.color = _TARGET_INTENT_COLOR
	var outer: float = _TARGET_INTENT_RETICLE_RADIUS
	var inner: float = outer * 0.44
	marker.polygon = PackedVector2Array(
		[
			marker_position + Vector2(0.0, -outer),
			marker_position + Vector2(inner, -inner),
			marker_position + Vector2(outer, 0.0),
			marker_position + Vector2(inner, inner),
			marker_position + Vector2(0.0, outer),
			marker_position + Vector2(-inner, inner),
			marker_position + Vector2(-outer, 0.0),
			marker_position + Vector2(-inner, -inner),
		]
	)
	return marker


func _target_marker(marker_position: Vector2, color: Color = _ACTION_PREVIEW_COLOR) -> Polygon2D:
	var marker := Polygon2D.new()
	marker.color = color
	var radius := 7.0
	marker.polygon = PackedVector2Array(
		[
			marker_position + Vector2(0.0, -radius),
			marker_position + Vector2(radius, 0.0),
			marker_position + Vector2(0.0, radius),
			marker_position + Vector2(-radius, 0.0),
		]
	)
	return marker


func _turn_stop_marker(tile: Vector2i, alpha_multiplier: float = 1.0) -> Node2D:
	var group := Node2D.new()
	group.name = "TurnStopMarker"
	group.set_meta("tile", tile)
	var marker_position: Vector2 = _tile_center(tile)
	var outer_radius := 11.0
	var inner_radius := 7.0
	var outline_color := _ACTION_PREVIEW_STOP_OUTLINE_COLOR
	outline_color.a *= alpha_multiplier
	var fill_color := _ACTION_PREVIEW_STOP_COLOR
	fill_color.a *= alpha_multiplier
	var outline := Polygon2D.new()
	outline.color = outline_color
	outline.polygon = PackedVector2Array(
		[
			marker_position + Vector2(-outer_radius, -outer_radius),
			marker_position + Vector2(outer_radius, -outer_radius),
			marker_position + Vector2(outer_radius, outer_radius),
			marker_position + Vector2(-outer_radius, outer_radius),
		]
	)
	group.add_child(outline)
	var fill := Polygon2D.new()
	fill.color = fill_color
	fill.polygon = PackedVector2Array(
		[
			marker_position + Vector2(-inner_radius, -inner_radius),
			marker_position + Vector2(inner_radius, -inner_radius),
			marker_position + Vector2(inner_radius, inner_radius),
			marker_position + Vector2(-inner_radius, inner_radius),
		]
	)
	group.add_child(fill)
	return group


func _preview_label(preview: Dictionary) -> String:
	var kind: String = preview.get("kind", "Action")
	var def_id: String = preview.get("def_id", "")
	var sequence_index: int = preview.get("sequence_index", 0)
	var prefix := ""
	if sequence_index > 0:
		prefix = "%d. " % sequence_index
		if preview.get("future", false):
			prefix = "%d> " % sequence_index
	if def_id != "":
		return "%s%s %s" % [prefix, kind, def_id]
	return "%s%s" % [prefix, kind]


func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile.x + 0.5, tile.y + 0.5) * float(_tile_size)


func _rebuild_production_progress() -> void:
	_resolve_internal_nodes()
	_clear_production_progress_nodes()
	if _state == null or _registry == null or _production_progress_root == null:
		return
	for entity in _state.entities_sorted_by_id():
		if (
			entity == null
			or entity.production_state == null
			or entity.production_state.active.is_empty()
		):
			continue
		if not _is_entity_currently_visible_for_player(entity, _perspective_player_id):
			continue
		var active: Dictionary = entity.production_state.active
		var kind: String = active.get(ProductionState.KEY_KIND, "")
		if kind != ProductionState.KIND_UNIT:
			continue
		var def_id: String = active.get(ProductionState.KEY_DEF_ID, "")
		var total_turns: int = _production_total_turns(kind, def_id)
		if total_turns <= 0:
			continue
		var remaining: int = active.get(ProductionState.KEY_TURNS_REMAINING, total_turns)
		var done_ratio := clampf(float(total_turns - remaining) / float(total_turns), 0.0, 1.0)
		_render_production_progress(entity, done_ratio)


func _production_total_turns(kind: String, def_id: String) -> int:
	if kind != ProductionState.KIND_UNIT or _registry == null:
		return 0
	var def: EntityDef = _registry.get_by_id(def_id)
	if def == null or def.construction == null:
		return 0
	return def.construction.build_time_turns


func _render_production_progress(entity: Entity, done_ratio: float) -> void:
	var def: EntityDef = _def_for_entity(entity)
	if def == null:
		return
	var rect: Rect2 = _entity_world_rect(entity, _state, def)
	var group := Node2D.new()
	group.name = "ProductionProgress_%d" % entity.id
	group.position = rect.get_center() + Vector2(-_PRODUCTION_PROGRESS_SIZE.x / 2.0, -24.0)
	var back := ColorRect.new()
	back.color = _PRODUCTION_PROGRESS_BACK
	back.size = _PRODUCTION_PROGRESS_SIZE
	group.add_child(back)
	var fill := ColorRect.new()
	fill.color = _PRODUCTION_PROGRESS_FILL
	fill.size = Vector2(_PRODUCTION_PROGRESS_SIZE.x * done_ratio, _PRODUCTION_PROGRESS_SIZE.y)
	group.add_child(fill)
	_production_progress_root.add_child(group)


func _rebuild_construction_progress() -> void:
	_resolve_internal_nodes()
	_clear_construction_progress_nodes()
	if _state == null or _registry == null or _construction_progress_root == null:
		return
	for entity in _state.entities_sorted_by_id():
		if entity == null or not entity.is_constructing or entity.current_hp <= 0:
			continue
		if entity.owner_player_id != _perspective_player_id:
			continue
		if not _is_entity_currently_visible_for_player(entity, _perspective_player_id):
			continue
		var total_turns: int = _construction_total_turns(entity)
		if total_turns <= 0:
			continue
		var remaining: int = clampi(entity.construction_turns_remaining, 0, total_turns)
		var done_ratio := clampf(float(total_turns - remaining) / float(total_turns), 0.0, 1.0)
		_render_construction_progress(entity, done_ratio, entity.construction_worker_id < 0)


func _construction_total_turns(entity: Entity) -> int:
	var def := _def_for_entity(entity)
	if def == null or def.construction == null:
		return 0
	return def.construction.build_time_turns


func _render_construction_progress(entity: Entity, done_ratio: float, paused: bool) -> void:
	var def: EntityDef = _def_for_entity(entity)
	if def == null:
		return
	var rect: Rect2 = _entity_world_rect(entity, _state, def)
	var group := Node2D.new()
	group.name = "ConstructionProgress_%d" % entity.id
	group.position = rect.get_center() + Vector2(-_CONSTRUCTION_PROGRESS_SIZE.x / 2.0, -36.0)
	var back := ColorRect.new()
	back.color = _CONSTRUCTION_PROGRESS_BACK
	back.size = _CONSTRUCTION_PROGRESS_SIZE
	group.add_child(back)
	var fill := ColorRect.new()
	fill.color = _CONSTRUCTION_PROGRESS_PAUSED_FILL if paused else _CONSTRUCTION_PROGRESS_FILL
	fill.size = Vector2(_CONSTRUCTION_PROGRESS_SIZE.x * done_ratio, _CONSTRUCTION_PROGRESS_SIZE.y)
	group.add_child(fill)
	_construction_progress_root.add_child(group)


func _spawn_entity_view(entity: Entity, state: MatchState = null) -> void:
	if _entities_root == null or _registry == null:
		return
	# current_def_id tracks transforms (e.g. tank → siege_tank). Falls back
	# to def_id only at spawn time when current_def_id may not have been
	# initialized; the resolver clones it from def_id on entity creation.
	var def_id: String = _def_id_for_entity(entity)
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
		entity,
		def,
		_texture_for_def(def_id),
		_entity_rect_or_default(entity, state, def),
		_tile_size
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
	if _texture_by_def_id.has(def_id):
		return _texture_by_def_id[def_id]
	if _visuals == null:
		return null
	var path: String = _visuals.sprite_paths.get(def_id, "")
	if path == "":
		_texture_by_def_id[def_id] = null
		return null
	var texture := load(path) as Texture2D
	_texture_by_def_id[def_id] = texture
	return texture


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
	var viewport_size := _camera_fit_viewport_size()
	var span_tiles_x: int = max_tile.x - min_tile.x + _CAMERA_MARGIN_TILES * 2
	var span_tiles_y: int = max_tile.y - min_tile.y + _CAMERA_MARGIN_TILES * 2
	var pixel_w: float = max(span_tiles_x, 1) * _tile_size
	var pixel_h: float = max(span_tiles_y, 1) * _tile_size
	var zoom_x: float = viewport_size.x / pixel_w
	var zoom_y: float = viewport_size.y / pixel_h
	_set_camera_zoom(min(zoom_x, zoom_y))


func _camera_fit_viewport_size() -> Vector2:
	var viewport: Viewport = _render_viewport()
	if viewport != null:
		var visible_size: Vector2 = viewport.get_visible_rect().size
		if visible_size.x > 0.0 and visible_size.y > 0.0:
			return Vector2(
				maxf(
					visible_size.x - _camera_screen_safe_margins.x - _camera_screen_safe_margins.z,
					1.0
				),
				maxf(
					visible_size.y - _camera_screen_safe_margins.y - _camera_screen_safe_margins.w,
					1.0
				)
			)
	var width: float = float(
		ProjectSettings.get_setting(_VIEWPORT_WIDTH_SETTING, _DEFAULT_LOGICAL_VIEWPORT_SIZE.x)
	)
	var height: float = float(
		ProjectSettings.get_setting(_VIEWPORT_HEIGHT_SETTING, _DEFAULT_LOGICAL_VIEWPORT_SIZE.y)
	)
	if width <= 0.0 or height <= 0.0:
		return _DEFAULT_LOGICAL_VIEWPORT_SIZE
	return Vector2(
		maxf(width - _camera_screen_safe_margins.x - _camera_screen_safe_margins.z, 1.0),
		maxf(height - _camera_screen_safe_margins.y - _camera_screen_safe_margins.w, 1.0)
	)


func _render_viewport() -> Viewport:
	var parent_viewport: Viewport = get_parent() as Viewport
	return parent_viewport if parent_viewport != null else get_viewport()


func _apply_camera_screen_offset() -> void:
	if _camera == null:
		return
	_camera.offset = Vector2(
		(_camera_screen_safe_margins.x - _camera_screen_safe_margins.z) * 0.5,
		(_camera_screen_safe_margins.y - _camera_screen_safe_margins.w) * 0.5
	)


func _set_camera_zoom(value: float) -> void:
	if _camera == null:
		return
	var min_zoom: float = _camera_min_zoom_for_map()
	var max_zoom: float = maxf(_MAX_CAMERA_ZOOM, min_zoom)
	var zoom: float = clampf(value, min_zoom, max_zoom)
	_camera.zoom = Vector2.ONE * zoom
	_clamp_camera_to_map_bounds()
	_update_zoom_debug_readout()


func _camera_min_zoom_for_map() -> float:
	var min_zoom: float = _MIN_CAMERA_ZOOM
	var map_bounds: Rect2 = _map_world_bounds()
	if map_bounds.size.x <= 0.0 or map_bounds.size.y <= 0.0:
		return _MIN_CAMERA_ZOOM
	var viewport_size: Vector2 = _camera_fit_viewport_size()
	min_zoom = maxf(min_zoom, viewport_size.x / map_bounds.size.x)
	min_zoom = maxf(min_zoom, viewport_size.y / map_bounds.size.y)
	return min_zoom


func _clamp_camera_to_map_bounds() -> void:
	if _camera == null:
		return
	var map_bounds: Rect2 = _map_world_bounds()
	if map_bounds.size.x <= 0.0 or map_bounds.size.y <= 0.0:
		return
	var safe_zoom: float = maxf(_camera.zoom.x, 0.01)
	var visible_size: Vector2 = _camera_fit_viewport_size() / safe_zoom
	var clamped_position: Vector2 = _camera.position
	if visible_size.x >= map_bounds.size.x:
		clamped_position.x = map_bounds.get_center().x
	else:
		var min_x: float = map_bounds.position.x + visible_size.x * 0.5
		var max_x: float = map_bounds.end.x - visible_size.x * 0.5
		clamped_position.x = clampf(clamped_position.x, min_x, max_x)
	if visible_size.y >= map_bounds.size.y:
		clamped_position.y = map_bounds.get_center().y
	else:
		var min_y: float = map_bounds.position.y + visible_size.y * 0.5
		var max_y: float = map_bounds.end.y - visible_size.y * 0.5
		clamped_position.y = clampf(clamped_position.y, min_y, max_y)
	_camera.position = clamped_position


func _update_zoom_debug_readout() -> void:
	if _camera == null:
		_zoom_debug_text = ""
		return
	var tile_px: float = float(_tile_size) * _camera.zoom.x
	_zoom_debug_text = (
		"Zoom %.2fx\nTile %.1f logical px\n1x1 %.1f px | 2x2 %.1f px"
		% [
			_camera.zoom.x,
			tile_px,
			tile_px,
			tile_px * 2.0,
		]
	)
	if _zoom_debug != null:
		_zoom_debug.text = _zoom_debug_text


func _player_world_bounds(player_id: int) -> Rect2:
	var bounds := Rect2()
	var has_bounds := false
	if _state == null or _state.tile_grid == null:
		return bounds
	for entity in _state.entities_sorted_by_id():
		if entity == null or entity.owner_player_id != player_id:
			continue
		if not _is_renderable_entity(entity):
			continue
		var world_rect := _entity_world_rect(entity, _state, _def_for_entity(entity))
		if not has_bounds:
			bounds = world_rect
			has_bounds = true
		else:
			bounds = bounds.merge(world_rect)
	if not has_bounds:
		return bounds
	var visibility: VisionSystem.Visibility = _visibility_by_player.get(player_id)
	if visibility == null and _registry != null:
		visibility = VISION_SYSTEM_SCRIPT.compute_player_visibility(_state, _registry, player_id)
	for entity in _state.entities_sorted_by_id():
		if entity == null or entity.owner_player_id != -1:
			continue
		if not _is_renderable_entity(entity):
			continue
		var def := _def_for_entity(entity)
		if def == null or def.resource_source == null:
			continue
		var rect := _entity_rect_or_default(entity, _state, def)
		if visibility != null and not visibility.is_rect_visible(rect):
			continue
		bounds = bounds.merge(_world_rect_from_grid_rect(rect))
	return bounds


func _entity_world_rect(entity: Entity, state: MatchState, def: EntityDef) -> Rect2:
	var rect: Rect2i = _entity_rect_or_default(entity, state, def)
	return _world_rect_from_grid_rect(rect)


func _world_rect_from_grid_rect(rect: Rect2i) -> Rect2:
	return Rect2(
		Vector2(rect.position.x * _tile_size, rect.position.y * _tile_size),
		Vector2(rect.size.x * _tile_size, rect.size.y * _tile_size)
	)


func _map_world_bounds() -> Rect2:
	if _state == null or _state.tile_grid == null:
		return Rect2()
	return Rect2(
		Vector2.ZERO,
		Vector2(_state.tile_grid.width * _tile_size, _state.tile_grid.height * _tile_size)
	)


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
		if not _is_renderable_entity(entity):
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
		if _is_renderable_entity(entity):
			live_ids[entity.id] = true
	for entity_id in _views_by_id.keys():
		if not live_ids.has(entity_id) and not _has_any_seen_enemy_building_snapshot(entity_id):
			_destroy_entity_view(entity_id)


# Phase 4 of render_step. Push the post-turn state into every surviving
# view (position, sprite swap on transform, modulate). Runs after
# events so attack-line endpoints reflect pre-event positions.
func _update_surviving_views(new_state: MatchState) -> void:
	if _registry == null:
		return
	for entity in new_state.entities_sorted_by_id():
		if not _is_renderable_entity(entity):
			continue
		var view: EntityView = _views_by_id.get(entity.id)
		if view == null:
			continue
		var def := _def_for_entity(entity)
		if def == null:
			continue
		(
			view
			. update_from_state(
				entity,
				def,
				_texture_for_def(entity.current_def_id),
				_entity_rect_or_default(entity, new_state, def),
				_tile_size,
			)
		)


func _reset_visibility_memory() -> void:
	_visibility_by_player.clear()
	_seen_tiles_by_player.clear()
	_seen_enemy_building_snapshots_by_player.clear()
	_fog_overlay_signature = ""
	_has_fog_overlay_cache = false
	_fog_overlay_tile_count = 0
	for player_id in _player_ids():
		_seen_tiles_by_player[player_id] = {}
		_seen_enemy_building_snapshots_by_player[player_id] = {}


func _seed_known_starting_base_snapshots() -> void:
	if _state == null or _registry == null:
		return
	if _state.turn_index != 0:
		return
	for entity in _state.entities_sorted_by_id():
		if not _is_completed_base(entity):
			continue
		var def := _def_for_entity(entity)
		var snapshot := _building_snapshot(entity, _entity_rect_or_default(entity, _state, def))
		if snapshot.is_empty():
			continue
		for player_id in _player_ids():
			if player_id == entity.owner_player_id:
				continue
			var snapshots: Dictionary = _seen_enemy_building_snapshots_by_player.get(player_id, {})
			snapshots[entity.id] = snapshot
			_seen_enemy_building_snapshots_by_player[player_id] = snapshots


func _refresh_all_visibility() -> void:
	if _state == null or _registry == null or _state.tile_grid == null:
		return
	var profile_enabled := FileAccess.file_exists(_RESOLVE_PROFILE_FLAG_PATH)
	var profile_lines: Array[String] = []
	var profile_total_start := Time.get_ticks_usec()
	var profile_step := profile_total_start
	var compute_visibility_usec: int = 0
	var remember_tiles_usec: int = 0
	var snapshot_usec: int = 0
	var player_count := 0
	var visible_tile_count := 0
	if profile_enabled:
		profile_lines.append(
			"[visibility_profile] captured_at=%s" % Time.get_datetime_string_from_system()
		)
		profile_lines.append("[visibility_profile] entities=%d" % _state.entities.size())
	_visibility_by_player.clear()
	for player_id in _player_ids():
		player_count += 1
		var step_start := Time.get_ticks_usec()
		var visibility: VisionSystem.Visibility = VISION_SYSTEM_SCRIPT.compute_player_visibility(
			_state, _registry, player_id
		)
		compute_visibility_usec += Time.get_ticks_usec() - step_start
		_visibility_by_player[player_id] = visibility
		visible_tile_count += visibility.visible_tile_count()
		step_start = Time.get_ticks_usec()
		_remember_visible_tiles(player_id, visibility)
		remember_tiles_usec += Time.get_ticks_usec() - step_start
		step_start = Time.get_ticks_usec()
		_refresh_seen_enemy_building_snapshots(player_id, visibility)
		snapshot_usec += Time.get_ticks_usec() - step_start
	profile_step = Time.get_ticks_usec()
	_refresh_entity_visibility()
	var refresh_entity_visibility_usec := Time.get_ticks_usec() - profile_step
	if profile_enabled:
		profile_lines.append("[visibility_profile] players=%d" % player_count)
		profile_lines.append("[visibility_profile] visible_tiles=%d" % visible_tile_count)
		profile_lines.append(
			(
				"[visibility_profile] compute_player_visibility=%.3fms"
				% (float(compute_visibility_usec) / 1000.0)
			)
		)
		profile_lines.append(
			(
				"[visibility_profile] remember_visible_tiles=%.3fms"
				% (float(remember_tiles_usec) / 1000.0)
			)
		)
		profile_lines.append(
			(
				"[visibility_profile] refresh_seen_enemy_building_snapshots=%.3fms"
				% (float(snapshot_usec) / 1000.0)
			)
		)
		profile_lines.append(
			(
				"[visibility_profile] refresh_entity_visibility=%.3fms"
				% (float(refresh_entity_visibility_usec) / 1000.0)
			)
		)
		profile_step = Time.get_ticks_usec()
	_rebuild_fog_overlay()
	if profile_enabled:
		profile_lines.append(
			(
				"[visibility_profile] rebuild_fog_overlay=%.3fms"
				% (float(Time.get_ticks_usec() - profile_step) / 1000.0)
			)
		)
		var fog_child_count := _fog_root.get_child_count() if _fog_root != null else 0
		profile_lines.append("[visibility_profile] fog_children=%d" % fog_child_count)
		profile_lines.append("[visibility_profile] fog_tiles=%d" % _fog_overlay_tile_count)
		profile_lines.append(
			(
				"[visibility_profile] total=%.3fms"
				% (float(Time.get_ticks_usec() - profile_total_start) / 1000.0)
			)
		)
		_emit_visibility_profile(profile_lines)


func _refresh_entity_visibility() -> void:
	if _state == null:
		return
	var live_ids: Dictionary[int, bool] = {}
	for entity in _state.entities_sorted_by_id():
		live_ids[entity.id] = true
		var view: EntityView = _views_by_id.get(entity.id)
		if view == null:
			continue
		if _known_covering_refinery_id_for_gas_geyser(entity, _perspective_player_id) >= 0:
			view.visible = false
			view.set_fog_silhouette(false)
			continue
		if _is_resource_source(entity):
			view.visible = true
			view.set_fog_silhouette(false)
			continue
		var visible_now := _is_entity_currently_visible_for_player(entity, _perspective_player_id)
		if visible_now:
			view.visible = true
			view.set_fog_silhouette(false)
			continue
		var snapshot: Dictionary = _seen_enemy_building_snapshot(_perspective_player_id, entity.id)
		if not snapshot.is_empty():
			_apply_building_snapshot_to_view(entity.id, snapshot)
			view = _views_by_id.get(entity.id)
			if view != null:
				view.visible = true
				view.set_fog_silhouette(true)
			continue
		view.visible = false
		view.set_fog_silhouette(false)
	var snapshots: Dictionary = _seen_enemy_building_snapshots_by_player.get(
		_perspective_player_id, {}
	)
	for entity_id in snapshots.keys():
		if live_ids.has(entity_id):
			continue
		var snapshot: Dictionary = snapshots.get(entity_id, {})
		if snapshot.is_empty():
			continue
		_apply_building_snapshot_to_view(entity_id, snapshot)
		var ghost_view: EntityView = _views_by_id.get(entity_id)
		if ghost_view != null:
			ghost_view.visible = true
			ghost_view.set_fog_silhouette(true)
	for entity_id in _views_by_id.keys():
		if live_ids.has(entity_id):
			continue
		if _seen_enemy_building_snapshot(_perspective_player_id, entity_id).is_empty():
			if _has_any_seen_enemy_building_snapshot(entity_id):
				var hidden_view: EntityView = _views_by_id.get(entity_id)
				if hidden_view != null:
					hidden_view.visible = false
					hidden_view.set_fog_silhouette(false)
			else:
				_destroy_entity_view(entity_id)


func _rebuild_fog_overlay() -> void:
	_resolve_internal_nodes()
	if _fog_root == null:
		return
	if _state == null or _state.tile_grid == null:
		_clear_fog_overlay()
		_fog_overlay_signature = ""
		_has_fog_overlay_cache = false
		return
	var visibility: VisionSystem.Visibility = _visibility_by_player.get(_perspective_player_id)
	if visibility == null:
		_clear_fog_overlay()
		_fog_overlay_signature = ""
		_has_fog_overlay_cache = false
		return
	var signature: String = _fog_visibility_signature(visibility)
	if _has_fog_overlay_cache and signature == _fog_overlay_signature:
		return
	_fog_overlay_signature = signature
	_has_fog_overlay_cache = true
	_clear_fog_overlay()
	for y in range(_state.tile_grid.height):
		var run_start := -1
		for x in range(_state.tile_grid.width):
			var tile := Vector2i(x, y)
			if not visibility.is_tile_visible(tile):
				_fog_overlay_tile_count += 1
				if run_start < 0:
					run_start = x
				continue
			if run_start >= 0:
				_add_fog_overlay_run(run_start, y, x - run_start)
				run_start = -1
		if run_start >= 0:
			_add_fog_overlay_run(run_start, y, _state.tile_grid.width - run_start)


func _add_fog_overlay_run(start_x: int, y: int, width: int) -> void:
	if _fog_root == null or width <= 0:
		return
	_fog_root.add_child(
		_highlight_polygon(
			Rect2i(Vector2i(start_x, y), Vector2i(width, 1)), _FOG_OUT_OF_VISION_COLOR
		)
	)


func _clear_fog_overlay() -> void:
	_fog_overlay_tile_count = 0
	if _fog_root == null:
		return
	for child in _fog_root.get_children():
		_fog_root.remove_child(child)
		child.queue_free()


func _fog_visibility_signature(visibility: VisionSystem.Visibility) -> String:
	var hash := 17
	var visible_count := 0
	for x in range(_state.tile_grid.width):
		for y in range(_state.tile_grid.height):
			var tile := Vector2i(x, y)
			if not visibility.is_tile_visible(tile):
				continue
			visible_count += 1
			hash = int(hash * 31 + x * 73856093 + y * 19349663)
	return (
		"%d:%d:%d:%d:%d"
		% [
			_perspective_player_id,
			_state.tile_grid.width,
			_state.tile_grid.height,
			visible_count,
			hash,
		]
	)


func _remember_visible_tiles(player_id: int, visibility: VisionSystem.Visibility) -> void:
	var seen: Dictionary = _seen_tiles_by_player.get(player_id, {})
	for tile in visibility.visible_tiles():
		seen[tile] = true
	_seen_tiles_by_player[player_id] = seen


func _refresh_seen_enemy_building_snapshots(
	player_id: int, visibility: VisionSystem.Visibility
) -> void:
	var snapshots: Dictionary = _seen_enemy_building_snapshots_by_player.get(player_id, {})
	var snapshot_ids_to_clear: Array[int] = []
	for entity_id in snapshots.keys():
		var snapshot: Dictionary = snapshots.get(entity_id, {})
		var rect: Rect2i = snapshot.get(_BUILDING_MEMORY_RECT, Rect2i())
		if rect.size.x <= 0 or rect.size.y <= 0:
			snapshot_ids_to_clear.append(entity_id)
			continue
		if not visibility.is_rect_visible(rect):
			continue
		var live_entity: Entity = _state.get_entity_by_id(entity_id)
		if (
			live_entity == null
			or live_entity.owner_player_id == player_id
			or live_entity.owner_player_id < 0
			or not _is_building(live_entity)
			or not VISION_SYSTEM_SCRIPT.is_entity_visible_to_player(
				live_entity, _state, _registry, player_id, visibility
			)
		):
			snapshot_ids_to_clear.append(entity_id)
	for entity_id in snapshot_ids_to_clear:
		snapshots.erase(entity_id)
	for entity in _state.entities_sorted_by_id():
		if entity.owner_player_id == player_id or entity.owner_player_id < 0:
			continue
		if not _is_building(entity):
			continue
		if VISION_SYSTEM_SCRIPT.is_entity_visible_to_player(
			entity, _state, _registry, player_id, visibility
		):
			var def := _def_for_entity(entity)
			snapshots[entity.id] = _building_snapshot(
				entity, _entity_rect_or_default(entity, _state, def)
			)
	_seen_enemy_building_snapshots_by_player[player_id] = snapshots


func _is_entity_hit_testable(entity_id: int) -> bool:
	var entity := _state.get_entity_by_id(entity_id)
	if not _is_renderable_entity(entity):
		return false
	if _known_covering_refinery_id_for_gas_geyser(entity, _perspective_player_id) >= 0:
		return false
	if _is_resource_source(entity):
		return true
	if entity.owner_player_id == _perspective_player_id:
		return true
	return _is_entity_currently_visible_for_player(entity, _perspective_player_id)


func _is_entity_currently_visible_for_player(entity: Entity, player_id: int) -> bool:
	if _is_resource_source(entity):
		return true
	var visibility = _visibility_by_player.get(player_id)
	if visibility == null:
		return entity != null and entity.owner_player_id == player_id
	return VISION_SYSTEM_SCRIPT.is_entity_visible_to_player(
		entity, _state, _registry, player_id, visibility
	)


func _seen_enemy_building_snapshot(player_id: int, entity_id: int) -> Dictionary:
	var snapshots: Dictionary = _seen_enemy_building_snapshots_by_player.get(player_id, {})
	return snapshots.get(entity_id, {})


func _has_any_seen_enemy_building_snapshot(entity_id: int) -> bool:
	for snapshots in _seen_enemy_building_snapshots_by_player.values():
		var player_snapshots: Dictionary = snapshots
		if player_snapshots.has(entity_id):
			return true
	return false


func _building_snapshot(entity: Entity, rect: Rect2i) -> Dictionary:
	if entity == null:
		return {}
	return {
		_BUILDING_MEMORY_ENTITY: entity.clone(),
		_BUILDING_MEMORY_RECT: rect,
	}


func _apply_building_snapshot_to_view(entity_id: int, snapshot: Dictionary) -> void:
	var snapshot_entity: Entity = snapshot.get(_BUILDING_MEMORY_ENTITY) as Entity
	if snapshot_entity == null:
		return
	var rect: Rect2i = snapshot.get(_BUILDING_MEMORY_RECT, Rect2i())
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var def := _def_for_entity(snapshot_entity)
	if def == null:
		return
	var view: EntityView = _views_by_id.get(entity_id)
	if view == null:
		view = _spawn_entity_view_for_snapshot(entity_id)
	if view == null:
		return
	view.update_from_state(
		snapshot_entity, def, _texture_for_def(_def_id_for_entity(snapshot_entity)), rect
	)


func _spawn_entity_view_for_snapshot(entity_id: int) -> EntityView:
	if _entities_root == null or _entity_view_scene == null:
		return null
	var view := _entity_view_scene.instantiate() as EntityView
	if view == null:
		return null
	_entities_root.add_child(view)
	view.bind_entity_id(entity_id)
	_views_by_id[entity_id] = view
	return view


func _is_building(entity: Entity) -> bool:
	var def := _def_for_entity(entity)
	return def != null and def.tags.has("building")


func _is_resource_source(entity: Entity) -> bool:
	var def := _def_for_entity(entity)
	return def != null and def.resource_source != null


func _is_completed_base(entity: Entity) -> bool:
	var def := _def_for_entity(entity)
	return (
		entity != null
		and entity.owner_player_id >= 0
		and entity.current_hp > 0
		and not entity.is_constructing
		and def != null
		and def.id == "base"
	)


func _known_covering_refinery_id_for_gas_geyser(entity: Entity, player_id: int) -> int:
	if entity == null or _state == null:
		return -1
	var def := _def_for_entity(entity)
	if def == null or def.id != "gas_geyser":
		return -1
	var rect: Rect2i = _entity_rect_or_default(entity, _state, def)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return -1
	for other in _state.entities_sorted_by_id():
		if other == null or other.id == entity.id or other.current_hp <= 0:
			continue
		var other_def := _def_for_entity(other)
		if other_def == null or other_def.id != "refinery":
			continue
		var other_rect: Rect2i = _entity_rect_or_default(other, _state, other_def)
		if other_rect.position != rect.position or other_rect.size != rect.size:
			continue
		if other.owner_player_id == player_id:
			return other.id
		if _is_entity_currently_visible_for_player(other, player_id):
			return other.id
		if not _seen_enemy_building_snapshot(player_id, other.id).is_empty():
			return other.id
	var snapshots: Dictionary = _seen_enemy_building_snapshots_by_player.get(player_id, {})
	for entity_id in snapshots.keys():
		var snapshot: Dictionary = snapshots.get(entity_id, {})
		var snapshot_entity: Entity = snapshot.get(_BUILDING_MEMORY_ENTITY) as Entity
		if snapshot_entity == null:
			continue
		var snapshot_def := _def_for_entity(snapshot_entity)
		if snapshot_def == null or snapshot_def.id != "refinery":
			continue
		var snapshot_rect: Rect2i = snapshot.get(_BUILDING_MEMORY_RECT, Rect2i())
		if snapshot_rect.position == rect.position and snapshot_rect.size == rect.size:
			return entity_id
	return -1


func _is_renderable_entity(entity: Entity) -> bool:
	if entity == null:
		return false
	if entity.current_hp > 0:
		return true
	var def := _def_for_entity(entity)
	return def != null and def.resource_source != null


func _is_movable_entity(entity: Entity) -> bool:
	if entity == null:
		return false
	var def := _def_for_entity(entity)
	return def != null and def.movement != null and def.movement.speed_tiles_per_turn > 0


func _query_entity_world_rect(entity: Entity) -> Rect2:
	if entity == null:
		return Rect2()
	var rect: Rect2i = Rect2i()
	if _state != null and _state.tile_grid != null:
		rect = _state.tile_grid.entity_rect(entity.id)
	if rect.size == Vector2i.ZERO:
		var def := _def_for_entity(entity)
		var footprint: Vector2i = def.footprint if def != null else Vector2i.ONE
		if footprint == Vector2i.ZERO:
			footprint = Vector2i.ONE
		rect = Rect2i(entity.origin, footprint)
	return Rect2(Vector2(rect.position) * _tile_size, Vector2(rect.size) * _tile_size)


func _def_for_entity(entity: Entity) -> EntityDef:
	if entity == null or _registry == null:
		return null
	return _registry.get_by_id(_def_id_for_entity(entity))


func _def_id_for_entity(entity: Entity) -> String:
	if entity == null:
		return ""
	return entity.current_def_id if entity.current_def_id != "" else entity.def_id


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


func _visible_entity_ids_for_player(player_id: int) -> Dictionary[int, bool]:
	var out: Dictionary[int, bool] = {}
	if _state == null:
		return out
	for entity in _state.entities_sorted_by_id():
		if _is_entity_currently_visible_for_player(entity, player_id):
			out[entity.id] = true
	return out


func _was_entity_visible_for_event(entity_id: int) -> bool:
	return _event_visible_entity_ids.has(entity_id)


func _forget_seen_enemy_building_snapshot(player_id: int, entity_id: int) -> void:
	var snapshots: Dictionary = _seen_enemy_building_snapshots_by_player.get(player_id, {})
	snapshots.erase(entity_id)
	_seen_enemy_building_snapshots_by_player[player_id] = snapshots


func _render_event(event: ResolverEvent) -> void:
	if event == null:
		return
	match event.type:
		ResolverEvent.Type.ENTITY_DAMAGED:
			var target_visible := _was_entity_visible_for_event(event.target_id)
			if not target_visible:
				return
			var actor_visible := _was_entity_visible_for_event(event.actor_id)
			if actor_visible:
				_render_attack_overlay(event.actor_id, event.target_id)
			_render_damage_label(event.target_id, event.damage)
			if actor_visible:
				_append_combat_log(
					(
						"#%d hit #%d for %d (HP %d)"
						% [event.actor_id, event.target_id, event.damage, event.hp_after]
					)
				)
			else:
				_append_combat_log(
					"#%d took %d damage (HP %d)" % [event.target_id, event.damage, event.hp_after]
				)
		ResolverEvent.Type.ENTITY_DESTROYED:
			if not _was_entity_visible_for_event(event.target_id):
				return
			# Render-order is: spawn → events → prune. The view is still
			# alive at this point (the prune phase below would have removed
			# it post-event). Kick off the fade now so the destruction
			# animation is tied to the event, not to the cleanup pass.
			if _views_by_id.has(event.target_id):
				_destroy_entity_view(event.target_id)
			_forget_seen_enemy_building_snapshot(_perspective_player_id, event.target_id)
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
