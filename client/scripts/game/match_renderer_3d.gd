class_name MatchRenderer3D
extends Node3D

# 3D presentation layer (3d-renderer branch). Duck-type compatible with
# the MatchRenderer contract the play modes and MatchSessionController
# drive: bind_state / render_step (+ turn playback), camera pan/zoom,
# screen↔world↔tile mapping, hit tests, selection/hover, previews, fog.
#
# Coordinate contract: "world positions" exchanged with the controller
# stay in the 2D pixel space (tile * 32) so DevTurnInput and the preview
# builders keep working unchanged; internally one tile = 1.0 world unit
# on the ground plane (x = tile.x, z = tile.y).
#
# Known phase-1 gaps vs the 2D renderer (tracked in plan/m1/04):
# - no last-seen enemy building ghosts (live silhouettes only)
# - no refinery-covers-geyser hit-test aliasing
# - production/construction progress bars not rendered yet

const WORLD_PX := 32.0

const VISION_SYSTEM_SCRIPT := preload("res://scripts/runtime/vision_system.gd")

const _GROUND_COLOR := Color(0.007, 0.010, 0.022)
const _GRID_EMISSION := Color(0.05, 0.35, 0.55)
const _CLIFF_COLOR := Color(0.10, 0.12, 0.20)
const _CLIFF_EDGE := Color(0.58, 0.45, 1.0)
const _CLIFF_HEIGHT := 0.55
const _FOG_COLOR := Color(0.0, 0.01, 0.04, 0.55)
const _HOVER_COLOR := Color(1.0, 1.0, 1.0, 0.18)
const _RANGE_CURRENT_COLOR := Color(0.05, 0.55, 1.0, 0.25)
const _RANGE_PROJECTED_COLOR := Color(1.0, 0.74, 0.16, 0.28)
const _BUILD_VALID_COLOR := Color(0.0, 0.88, 0.72, 0.35)
const _BUILD_INVALID_COLOR := Color(1.0, 0.08, 0.08, 0.35)
const _SELECTION_BOX_COLOR := Color(0.2, 0.9, 1.0, 0.9)
const _TARGET_INTENT_COLOR := Color(1.0, 0.34, 0.08)
const _IDLE_BADGE_COLOR := Color(1.0, 0.62, 0.05)
const _DAMAGE_LABEL_COLOR := Color(1.0, 1.0, 0.4)
const _PREVIEW_COLOR_BY_KIND := {
	"Attack": Color(1.0, 0.34, 0.08),
	"Gather": Color(0.2, 0.95, 0.6),
	"Rally": Color(0.7, 0.5, 1.0),
	"Rally Gather": Color(0.7, 0.5, 1.0),
}
const _PREVIEW_DEFAULT_COLOR := Color(0.2, 0.95, 0.9)

const _CAMERA_PITCH_DEGREES := 54.0
const _MIN_BOOM := 6.0
const _MAX_BOOM := 90.0
const _COMBAT_LOG_MAX_LINES := 50

const _PLAYBACK_MOVE_BEAT_SECONDS := 0.11
const _PLAYBACK_VOLLEY_BEAT_SECONDS := 0.22
const _PLAYBACK_BUDGET_SECONDS := 1.5
const _TRACER_COLOR := Color(1.0, 0.92, 0.55)
const _EXPLOSION_COLOR := Color(1.0, 0.62, 0.25)

var _state: MatchState = null
var _registry: EntityRegistry = null
var _views_by_id: Dictionary[int, EntityView3D] = {}
var _perspective_player_id: int = 0
var _selected_entity_ids: Array[int] = []
var _combat_log_lines: Array[String] = []
var _visibility_by_player: Dictionary = {}
var _seen_tiles_by_player: Dictionary = {}
var _event_visible_entity_ids: Dictionary[int, bool] = {}

var _camera_rig: Node3D = null
var _camera: Camera3D = null
var _boom: float = 30.0
var _entities_root: Node3D = null
var _terrain_root: Node3D = null
var _fog_root: Node3D = null
var _effects_root: Node3D = null
var _hover_quad: MeshInstance3D = null
var _range_root: Node3D = null
var _action_previews_root: Node3D = null
var _target_intents_root: Node3D = null
var _build_preview_root: Node3D = null
var _idle_badges_root: Node3D = null
var _selection_box_root: Node3D = null
var _scene_built: bool = false

# Turn playback state (same beat model as the 2D renderer).
var _playback_enabled: bool = false
var _playback_active: bool = false
var _playback_beats: Array[Dictionary] = []
var _playback_beat_index: int = -1
var _playback_beat_elapsed: float = 0.0
var _playback_final_state: MatchState = null
var _playback_glides: Array[Dictionary] = []


func _ready() -> void:
	set_process(false)
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		_playback_enabled = true


func _process(delta: float) -> void:
	advance_turn_playback(delta)


# ---------- Bind / render ----------


func bind_state(state: MatchState, registry: EntityRegistry) -> void:
	_build_scene()
	_clear_existing_views()
	_state = state
	_registry = registry
	_seen_tiles_by_player = {}
	_combat_log_lines = []
	if state == null or registry == null:
		return
	_build_terrain(state)
	for entity in state.entities_sorted_by_id():
		if not _is_renderable_entity(entity):
			continue
		_spawn_entity_view(entity, state)
	_refresh_all_visibility()
	_fit_camera_to_state(state)


func render_step(new_state: MatchState, events: Array[ResolverEvent]) -> void:
	if _playback_active:
		_finish_playback()
	if _playback_enabled and new_state != null and not events.is_empty():
		_render_step_animated(new_state, events)
		return
	_render_step_sync(new_state, events)


func _render_step_sync(new_state: MatchState, events: Array[ResolverEvent]) -> void:
	_build_scene()
	_event_visible_entity_ids = _visible_entity_ids_for_player(_perspective_player_id)
	_state = new_state
	if new_state == null:
		return
	_spawn_added_views(new_state)
	for event in events:
		_render_event(event)
	_event_visible_entity_ids = {}
	_prune_dead_views(new_state)
	_update_surviving_views(new_state)
	_refresh_all_visibility()


func get_entity_view(entity_id: int) -> EntityView3D:
	return _views_by_id.get(entity_id)


func entity_view_count() -> int:
	return _views_by_id.size()


func combat_log_text() -> String:
	return "\n".join(_combat_log_lines)


func combat_log_line_count() -> int:
	return _combat_log_lines.size()


# ---------- Camera + coordinate mapping ----------


func screen_to_world(screen_position: Vector2) -> Vector2:
	if _camera == null:
		return screen_position
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001:
		return Vector2(origin.x, origin.z) * WORLD_PX
	var t := -origin.y / direction.y
	var hit := origin + direction * t
	return Vector2(hit.x, hit.z) * WORLD_PX


func world_to_tile(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / WORLD_PX), floori(world_position.y / WORLD_PX))


func zoom_camera(multiplier: float) -> void:
	_boom = clampf(_boom / maxf(multiplier, 0.01), _MIN_BOOM, _MAX_BOOM)
	_apply_camera()


func pan_camera_by_screen_delta(delta: Vector2) -> void:
	if _camera_rig == null:
		return
	var scale_factor := _boom * 0.0016
	_camera_rig.position -= Vector3(delta.x * scale_factor, 0.0, delta.y * scale_factor)
	_clamp_camera_focus()
	_apply_camera()


func focus_player_start(player_id: int) -> void:
	if _state == null:
		return
	for entity in _state.entities_sorted_by_id():
		if entity.owner_player_id != player_id:
			continue
		var def := _def_for_entity(entity)
		if def != null and def.id == "base":
			var rect := _entity_rect_or_default(entity, _state, def)
			_camera_rig.position = Vector3(
				rect.position.x + rect.size.x * 0.5, 0.0, rect.position.y + rect.size.y * 0.5
			)
			_boom = 22.0
			_clamp_camera_focus()
			_apply_camera()
			return


func set_camera_screen_safe_margins(_l: float, _t: float, _r: float, _b: float) -> void:
	pass


func set_zoom_debug_visible(_visible: bool) -> void:
	pass


# ---------- Hit tests ----------


func entity_id_at_tile(tile: Vector2i) -> int:
	if _state == null or _state.tile_grid == null:
		return -1
	var entity_id: int = _state.tile_grid.entity_at(tile)
	if entity_id < 0:
		return -1
	return entity_id if _is_entity_hit_testable(entity_id) else -1


func entity_id_at_world(world_position: Vector2) -> int:
	return entity_id_at_tile(world_to_tile(world_position))


func owned_movable_entity_ids_in_world_rect(world_rect: Rect2, owner_player_id: int) -> Array[int]:
	var out: Array[int] = []
	if _state == null:
		return out
	for entity in _state.entities_sorted_by_id():
		if entity.owner_player_id != owner_player_id:
			continue
		var def := _def_for_entity(entity)
		if def == null or def.movement == null:
			continue
		var view: EntityView3D = _views_by_id.get(entity.id)
		if view == null or not view.visible:
			continue
		var rect := _entity_rect_or_default(entity, _state, def)
		var world := Rect2(Vector2(rect.position) * WORLD_PX, Vector2(rect.size) * WORLD_PX)
		if world_rect.intersects(world):
			out.append(entity.id)
	return out


func is_entity_view_visible(entity_id: int) -> bool:
	var view: EntityView3D = _views_by_id.get(entity_id)
	return view != null and view.visible and not view.is_fog_silhouette()


func is_entity_view_silhouette(entity_id: int) -> bool:
	var view: EntityView3D = _views_by_id.get(entity_id)
	return view != null and view.visible and view.is_fog_silhouette()


# ---------- Selection / hover / previews ----------


func set_perspective_player_id(player_id: int) -> void:
	if player_id == _perspective_player_id:
		return
	_perspective_player_id = player_id
	_refresh_all_visibility()


func perspective_player_id() -> int:
	return _perspective_player_id


func set_selected_entity_id(entity_id: int) -> void:
	var ids: Array[int] = []
	if entity_id >= 0:
		ids.append(entity_id)
	set_selected_entity_ids(ids)


func set_selected_entity_ids(entity_ids: Array) -> void:
	_selected_entity_ids = []
	for entity_id in entity_ids:
		_selected_entity_ids.append(int(entity_id))
	for id in _views_by_id:
		_views_by_id[id].set_selected(_selected_entity_ids.has(id))


func set_hover_tile(tile: Vector2i) -> void:
	_build_scene()
	_hover_quad.visible = true
	_hover_quad.position = Vector3(tile.x + 0.5, 0.02, tile.y + 0.5)


func clear_input_highlights() -> void:
	if _hover_quad != null:
		_hover_quad.visible = false
	set_selected_entity_ids([])


func set_selection_box_world_rect(rect: Rect2) -> void:
	_build_scene()
	_clear_children(_selection_box_root)
	var ground := Rect2(rect.position / WORLD_PX, rect.size / WORLD_PX)
	var points := PackedVector3Array(
		[
			Vector3(ground.position.x, 0.03, ground.position.y),
			Vector3(ground.end.x, 0.03, ground.position.y),
			Vector3(ground.end.x, 0.03, ground.end.y),
			Vector3(ground.position.x, 0.03, ground.end.y),
			Vector3(ground.position.x, 0.03, ground.position.y),
		]
	)
	_selection_box_root.add_child(_polyline(points, _SELECTION_BOX_COLOR))


func clear_selection_box() -> void:
	_clear_children(_selection_box_root)


func is_selection_box_visible() -> bool:
	return _selection_box_root != null and _selection_box_root.get_child_count() > 0


func set_range_preview_tiles(current_tiles: Array, projected_tiles: Array) -> void:
	_build_scene()
	_clear_children(_range_root)
	if not current_tiles.is_empty():
		_range_root.add_child(_tile_quads(current_tiles, _RANGE_CURRENT_COLOR))
	if not projected_tiles.is_empty():
		_range_root.add_child(_tile_quads(projected_tiles, _RANGE_PROJECTED_COLOR))


func clear_range_preview_tiles() -> void:
	_clear_children(_range_root)


func range_preview_tile_count() -> int:
	return 0 if _range_root == null else _range_root.get_child_count()


func set_action_previews(previews: Array) -> void:
	_build_scene()
	_clear_children(_action_previews_root)
	for preview in previews:
		var preview_dict: Dictionary = preview
		_render_action_preview(preview_dict)


func action_preview_count() -> int:
	return 0 if _action_previews_root == null else _action_previews_root.get_child_count()


func set_target_intent_previews(previews: Array) -> void:
	_build_scene()
	_clear_children(_target_intents_root)
	for preview in previews:
		var preview_dict: Dictionary = preview
		var actor_view: EntityView3D = _views_by_id.get(preview_dict.get("entity_id", -1))
		var target_view: EntityView3D = _views_by_id.get(preview_dict.get("target_entity_id", -1))
		if actor_view == null or target_view == null:
			continue
		if not actor_view.visible or not target_view.visible:
			continue
		var points := PackedVector3Array(
			[
				actor_view.position + Vector3(0.0, 0.05, 0.0),
				target_view.position + Vector3(0.0, 0.05, 0.0),
			]
		)
		_target_intents_root.add_child(_polyline(points, _TARGET_INTENT_COLOR))


func target_intent_preview_count() -> int:
	return 0 if _target_intents_root == null else _target_intents_root.get_child_count()


func set_build_placement_preview(preview: Dictionary) -> void:
	_build_scene()
	_clear_children(_build_preview_root)
	if preview.is_empty():
		return
	var origin: Vector2i = preview.get("origin", Vector2i.ZERO)
	var footprint: Vector2i = preview.get("footprint", Vector2i.ONE)
	var rect: Rect2i = preview.get("rect", Rect2i(origin, footprint))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var valid: bool = preview.get("valid", false)
	var box := BoxMesh.new()
	box.size = Vector3(rect.size.x, 0.5, rect.size.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _BUILD_VALID_COLOR if valid else _BUILD_INVALID_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = mat
	var node := MeshInstance3D.new()
	node.mesh = box
	node.position = Vector3(
		rect.position.x + rect.size.x * 0.5, 0.25, rect.position.y + rect.size.y * 0.5
	)
	_build_preview_root.add_child(node)


func clear_build_placement_preview() -> void:
	_clear_children(_build_preview_root)


func build_placement_preview_count() -> int:
	return 0 if _build_preview_root == null else _build_preview_root.get_child_count()


func set_idle_worker_indicators(indicators: Array[Variant]) -> void:
	_build_scene()
	_clear_children(_idle_badges_root)
	for indicator in indicators:
		var entity_id := _indicator_entity_id(indicator)
		var view: EntityView3D = _views_by_id.get(entity_id)
		if view == null or not view.visible:
			continue
		var quad := QuadMesh.new()
		quad.size = Vector2(0.34, 0.34)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _IDLE_BADGE_COLOR
		mat.emission_enabled = true
		mat.emission = _IDLE_BADGE_COLOR
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		quad.material = mat
		var node := MeshInstance3D.new()
		node.mesh = quad
		node.position = view.position + Vector3(0.0, view.model_height() + 0.7, 0.0)
		_idle_badges_root.add_child(node)


func idle_worker_indicator_count() -> int:
	return 0 if _idle_badges_root == null else _idle_badges_root.get_child_count()


# ---------- Fog queries ----------


func is_tile_currently_visible(player_id: int, tile: Vector2i) -> bool:
	var visibility: VisionSystem.Visibility = _visibility_by_player.get(player_id)
	return visibility != null and visibility.is_tile_visible(tile)


func is_tile_previously_seen(player_id: int, tile: Vector2i) -> bool:
	var seen: Dictionary = _seen_tiles_by_player.get(player_id, {})
	return seen.has(tile)


func fog_overlay_count() -> int:
	return 0 if _fog_root == null else _fog_root.get_child_count()


# ---------- Turn playback ----------


func set_turn_playback_enabled(enabled: bool) -> void:
	_playback_enabled = enabled
	if not enabled and _playback_active:
		_finish_playback()


func is_turn_playback_active() -> bool:
	return _playback_active


func skip_turn_playback() -> void:
	if _playback_active:
		_finish_playback()


func _render_step_animated(new_state: MatchState, events: Array[ResolverEvent]) -> void:
	_build_scene()
	_event_visible_entity_ids = _visible_entity_ids_for_player(_perspective_player_id)
	_state = new_state
	var pre_existing: Dictionary = _views_by_id.duplicate()
	_spawn_added_views(new_state)
	_refresh_all_visibility()
	_playback_final_state = new_state
	_playback_beats = _build_playback_beats(events)
	for beat in _playback_beats:
		beat["pre_existing"] = pre_existing
	var total := 0.0
	for beat in _playback_beats:
		total += beat["duration"]
	if total > _PLAYBACK_BUDGET_SECONDS:
		var time_scale := _PLAYBACK_BUDGET_SECONDS / total
		for beat in _playback_beats:
			beat["duration"] = float(beat["duration"]) * time_scale
	_playback_active = true
	_playback_beat_index = -1
	_playback_beat_elapsed = 0.0
	_playback_glides = []
	set_process(true)
	_advance_to_next_beat()


static func _build_playback_beats(events: Array[ResolverEvent]) -> Array[Dictionary]:
	var beats: Array[Dictionary] = []
	var current: Dictionary = {}
	for event in events:
		if event == null:
			continue
		match event.type:
			ResolverEvent.Type.ENTITY_MOVED:
				if current.get("kind", "") == "move" and not current["actors"].has(event.actor_id):
					current["events"].append(event)
					current["actors"][event.actor_id] = true
				else:
					current = {
						"kind": "move",
						"duration": _PLAYBACK_MOVE_BEAT_SECONDS,
						"events": [event],
						"actors": {event.actor_id: true},
					}
					beats.append(current)
			ResolverEvent.Type.ENTITY_DAMAGED:
				if (
					current.get("kind", "") == "volley"
					and not current["actors"].has(event.actor_id)
				):
					current["events"].append(event)
					current["actors"][event.actor_id] = true
				else:
					current = {
						"kind": "volley",
						"duration": _PLAYBACK_VOLLEY_BEAT_SECONDS,
						"events": [event],
						"actors": {event.actor_id: true},
					}
					beats.append(current)
			ResolverEvent.Type.ENTITY_DESTROYED:
				if current.get("kind", "") == "volley":
					current["events"].append(event)
				else:
					current = {
						"kind": "volley",
						"duration": _PLAYBACK_VOLLEY_BEAT_SECONDS,
						"events": [event],
						"actors": {},
					}
					beats.append(current)
			_:
				if current.get("kind", "") == "instant":
					current["events"].append(event)
				else:
					current = {"kind": "instant", "duration": 0.0, "events": [event]}
					beats.append(current)
	return beats


func advance_turn_playback(delta: float) -> void:
	if not _playback_active:
		return
	var remaining := delta
	while _playback_active and remaining > 0.0:
		var beat: Dictionary = _playback_beats[_playback_beat_index]
		var duration: float = beat["duration"]
		_playback_beat_elapsed += remaining
		if _playback_beat_elapsed < duration:
			_update_current_beat(clampf(_playback_beat_elapsed / duration, 0.0, 1.0))
			return
		remaining = _playback_beat_elapsed - duration
		_complete_current_beat()
		_advance_to_next_beat()


func _advance_to_next_beat() -> void:
	while _playback_active:
		_playback_beat_index += 1
		_playback_beat_elapsed = 0.0
		if _playback_beat_index >= _playback_beats.size():
			_end_playback()
			return
		var beat: Dictionary = _playback_beats[_playback_beat_index]
		_begin_beat(beat)
		if float(beat["duration"]) > 0.0:
			return
		_complete_current_beat()


func _begin_beat(beat: Dictionary) -> void:
	var kind: String = beat["kind"]
	if kind == "move":
		_playback_glides = []
		var pre_existing: Dictionary = beat.get("pre_existing", {})
		for event: ResolverEvent in beat["events"]:
			var view: EntityView3D = _views_by_id.get(event.actor_id)
			if view == null or not pre_existing.has(event.actor_id):
				continue
			var step := event.to_origin - event.from_origin
			view.face_direction(Vector2(step))
			var to := view.position + Vector3(step.x, 0.0, step.y)
			_playback_glides.append({"view": view, "from": view.position, "to": to})
	elif kind == "volley":
		for event: ResolverEvent in beat["events"]:
			if event.type != ResolverEvent.Type.ENTITY_DAMAGED:
				continue
			if not _was_entity_visible_for_event(event.target_id):
				continue
			var target_view: EntityView3D = _views_by_id.get(event.target_id)
			var actor_view: EntityView3D = _views_by_id.get(event.actor_id)
			if not _was_entity_visible_for_event(event.actor_id):
				actor_view = null
			if actor_view == null or target_view == null:
				continue
			var aim := Vector2(
				target_view.position.x - actor_view.position.x,
				target_view.position.z - actor_view.position.z
			)
			actor_view.face_direction(aim)
			_spawn_tracer(
				actor_view.position + Vector3(0.0, actor_view.model_height() * 0.55, 0.0),
				target_view.position + Vector3(0.0, target_view.model_height() * 0.45, 0.0),
				float(beat["duration"]) * 0.8
			)
	else:
		for event: ResolverEvent in beat["events"]:
			_render_event(event)


func _update_current_beat(progress: float) -> void:
	for glide in _playback_glides:
		var view: EntityView3D = glide["view"]
		if is_instance_valid(view):
			view.position = (glide["from"] as Vector3).lerp(glide["to"], progress)


func _complete_current_beat() -> void:
	var beat: Dictionary = _playback_beats[_playback_beat_index]
	var kind: String = beat["kind"]
	if kind == "move":
		_update_current_beat(1.0)
		_playback_glides = []
	elif kind == "volley":
		for event: ResolverEvent in beat["events"]:
			if event.type == ResolverEvent.Type.ENTITY_DAMAGED:
				_render_damage_event(event)
			elif event.type == ResolverEvent.Type.ENTITY_DESTROYED:
				var view: EntityView3D = _views_by_id.get(event.target_id)
				if view != null and _was_entity_visible_for_event(event.target_id):
					_spawn_explosion(view.position + Vector3(0.0, 0.3, 0.0))
				_render_event(event)


func _end_playback() -> void:
	_playback_active = false
	set_process(false)
	_playback_beats = []
	_playback_glides = []
	_playback_beat_index = -1
	_event_visible_entity_ids = {}
	var final_state := _playback_final_state
	_playback_final_state = null
	if final_state == null:
		return
	_prune_dead_views(final_state)
	_update_surviving_views(final_state)
	_refresh_all_visibility()


func _finish_playback() -> void:
	if not _playback_active:
		return
	while _playback_beat_index < _playback_beats.size():
		var beat: Dictionary = _playback_beats[_playback_beat_index]
		if beat["kind"] == "volley":
			for event: ResolverEvent in beat["events"]:
				if event.type == ResolverEvent.Type.ENTITY_DAMAGED:
					_append_damage_log(event)
				elif event.type == ResolverEvent.Type.ENTITY_DESTROYED:
					_render_event(event)
		elif beat["kind"] == "instant":
			for event: ResolverEvent in beat["events"]:
				_render_event(event)
		_playback_beat_index += 1
		_playback_beat_elapsed = 0.0
	_end_playback()


# ---------- Internals: scene ----------


func _build_scene() -> void:
	if _scene_built:
		return
	_scene_built = true

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.013, 0.028)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.6, 0.85)
	env.ambient_light_energy = 0.2
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.05
	env.ssao_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 8.0, 6.0)
	fill.light_color = Color(0.3, 0.7, 1.0)
	fill.light_energy = 0.6
	fill.omni_range = 30.0
	add_child(fill)

	_terrain_root = _add_root("Terrain")
	_fog_root = _add_root("Fog")
	_entities_root = _add_root("Entities")
	_range_root = _add_root("RangePreview")
	_action_previews_root = _add_root("ActionPreviews")
	_target_intents_root = _add_root("TargetIntents")
	_build_preview_root = _add_root("BuildPreview")
	_idle_badges_root = _add_root("IdleBadges")
	_selection_box_root = _add_root("SelectionBox")
	_effects_root = _add_root("Effects")

	_hover_quad = MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = _flat_material(_HOVER_COLOR)
	_hover_quad.mesh = quad
	_hover_quad.visible = false
	add_child(_hover_quad)

	_camera_rig = Node3D.new()
	_camera_rig.name = "CameraRig"
	add_child(_camera_rig)
	_camera = Camera3D.new()
	_camera.fov = 42.0
	_camera_rig.add_child(_camera)
	_apply_camera()
	_camera.current = true


func _add_root(node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	add_child(node)
	return node


func _apply_camera() -> void:
	if _camera == null:
		return
	var pitch := deg_to_rad(_CAMERA_PITCH_DEGREES)
	_camera.position = Vector3(0.0, _boom * sin(pitch), _boom * cos(pitch))
	_camera.look_at_from_position(
		_camera_rig.global_position + _camera.position, _camera_rig.global_position
	)


func _clamp_camera_focus() -> void:
	if _state == null or _state.tile_grid == null or _camera_rig == null:
		return
	_camera_rig.position.x = clampf(_camera_rig.position.x, 0.0, float(_state.tile_grid.width))
	_camera_rig.position.z = clampf(_camera_rig.position.z, 0.0, float(_state.tile_grid.height))


func _fit_camera_to_state(state: MatchState) -> void:
	if state == null or state.tile_grid == null or _camera_rig == null:
		return
	_camera_rig.position = Vector3(state.tile_grid.width * 0.5, 0.0, state.tile_grid.height * 0.5)
	_boom = clampf(maxf(state.tile_grid.width, state.tile_grid.height) * 0.8, _MIN_BOOM, _MAX_BOOM)
	_apply_camera()


func _build_terrain(state: MatchState) -> void:
	_clear_children(_terrain_root)
	if state.tile_grid == null:
		return
	var width := state.tile_grid.width
	var height := state.tile_grid.height

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, height)
	var shader := Shader.new()
	shader.code = (
		"""
shader_type spatial;
render_mode specular_disabled;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = abs(fract(wpos.xz) - 0.5);
	float line = 1.0 - smoothstep(0.0, 0.025, 0.5 - max(g.x, g.y));
	ALBEDO = vec3(%f, %f, %f);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	EMISSION = vec3(%f, %f, %f) * line * 0.10;
}
"""
		% [
			_GROUND_COLOR.r,
			_GROUND_COLOR.g,
			_GROUND_COLOR.b,
			_GRID_EMISSION.r,
			_GRID_EMISSION.g,
			_GRID_EMISSION.b
		]
	)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	ground.material_override = mat
	ground.mesh = plane
	ground.position = Vector3(width * 0.5, 0.0, height * 0.5)
	_terrain_root.add_child(ground)

	# Cliff tiles as merged row-run boxes with a faint violet emissive.
	var cliff_mat := StandardMaterial3D.new()
	cliff_mat.albedo_color = _CLIFF_COLOR
	cliff_mat.emission_enabled = true
	cliff_mat.emission = _CLIFF_EDGE
	cliff_mat.emission_energy_multiplier = 0.12
	var tiles: Array[Vector2i] = state.tile_grid.terrain_tiles()
	var lookup: Dictionary = {}
	for tile in tiles:
		lookup[tile] = true
	for tile in tiles:
		if lookup.get(tile + Vector2i.LEFT, false):
			continue
		var run := 1
		while lookup.get(tile + Vector2i(run, 0), false):
			run += 1
		var box := BoxMesh.new()
		box.size = Vector3(run, _CLIFF_HEIGHT, 1.0)
		box.material = cliff_mat
		var node := MeshInstance3D.new()
		node.mesh = box
		node.position = Vector3(tile.x + run * 0.5, _CLIFF_HEIGHT * 0.5, tile.y + 0.5)
		_terrain_root.add_child(node)


# ---------- Internals: views ----------


func _clear_existing_views() -> void:
	for id in _views_by_id:
		var view: EntityView3D = _views_by_id[id]
		if is_instance_valid(view):
			view.queue_free()
	_views_by_id = {}


func _spawn_entity_view(entity: Entity, state: MatchState) -> void:
	var def := _def_for_entity(entity)
	if def == null or _entities_root == null:
		return
	var view := EntityView3D.new()
	_entities_root.add_child(view)
	view.bind_entity_id(entity.id)
	view.update_from_state(
		entity, def, _visual_key_for_entity(entity), _entity_rect_or_default(entity, state, def)
	)
	_views_by_id[entity.id] = view


func _spawn_added_views(new_state: MatchState) -> void:
	for entity in new_state.entities_sorted_by_id():
		if not _is_renderable_entity(entity):
			continue
		if not _views_by_id.has(entity.id):
			_spawn_entity_view(entity, new_state)


func _prune_dead_views(new_state: MatchState) -> void:
	var live_ids: Dictionary = {}
	for entity in new_state.entities_sorted_by_id():
		if _is_renderable_entity(entity):
			live_ids[entity.id] = true
	for entity_id in _views_by_id.keys():
		if not live_ids.has(entity_id):
			_destroy_entity_view(entity_id)


func _destroy_entity_view(entity_id: int) -> void:
	var view: EntityView3D = _views_by_id.get(entity_id)
	if view == null:
		return
	_views_by_id.erase(entity_id)
	view.fade_out_and_despawn(0.5)


func _update_surviving_views(new_state: MatchState) -> void:
	if _registry == null:
		return
	for entity in new_state.entities_sorted_by_id():
		if not _is_renderable_entity(entity):
			continue
		var view: EntityView3D = _views_by_id.get(entity.id)
		if view == null:
			continue
		var def := _def_for_entity(entity)
		if def == null:
			continue
		view.update_from_state(
			entity,
			def,
			_visual_key_for_entity(entity),
			_entity_rect_or_default(entity, new_state, def)
		)
		view.set_selected(_selected_entity_ids.has(entity.id))


# ---------- Internals: events / effects ----------


func _render_event(event: ResolverEvent) -> void:
	if event == null:
		return
	match event.type:
		ResolverEvent.Type.ENTITY_DAMAGED:
			if _was_entity_visible_for_event(event.target_id):
				var actor_view: EntityView3D = _views_by_id.get(event.actor_id)
				var target_view: EntityView3D = _views_by_id.get(event.target_id)
				if (
					actor_view != null
					and target_view != null
					and _was_entity_visible_for_event(event.actor_id)
				):
					_spawn_tracer(
						actor_view.position + Vector3(0.0, actor_view.model_height() * 0.55, 0.0),
						target_view.position + Vector3(0.0, target_view.model_height() * 0.45, 0.0),
						0.16
					)
				_render_damage_event(event)
		ResolverEvent.Type.ENTITY_DESTROYED:
			if not _was_entity_visible_for_event(event.target_id):
				return
			var view: EntityView3D = _views_by_id.get(event.target_id)
			if view != null:
				_spawn_explosion(view.position + Vector3(0.0, 0.3, 0.0))
				_destroy_entity_view(event.target_id)
			_append_combat_log("#%d destroyed" % event.target_id)
		ResolverEvent.Type.MATCH_ENDED:
			if event.winner_player_id < 0:
				_append_combat_log("Match ended — draw")
			else:
				_append_combat_log("Match ended — winner: P%d" % event.winner_player_id)
		_:
			pass


func _render_damage_event(event: ResolverEvent) -> void:
	if not _was_entity_visible_for_event(event.target_id):
		return
	var view: EntityView3D = _views_by_id.get(event.target_id)
	if view != null:
		view.flash_hit()
		_spawn_damage_label(view, event.damage)
	_append_damage_log(event)


func _append_damage_log(event: ResolverEvent) -> void:
	if not _was_entity_visible_for_event(event.target_id):
		return
	if _was_entity_visible_for_event(event.actor_id):
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


func _append_combat_log(line: String) -> void:
	_combat_log_lines.append(line)
	if _combat_log_lines.size() > _COMBAT_LOG_MAX_LINES:
		var overflow: int = _combat_log_lines.size() - _COMBAT_LOG_MAX_LINES
		_combat_log_lines = _combat_log_lines.slice(overflow)


func _spawn_damage_label(view: EntityView3D, damage: int) -> void:
	if _effects_root == null:
		return
	var label := Label3D.new()
	label.text = "-%d" % damage
	label.modulate = _DAMAGE_LABEL_COLOR
	label.font_size = 64
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = view.position + Vector3(0.0, view.model_height() + 0.5, 0.0)
	_effects_root.add_child(label)
	if not label.is_inside_tree() or Engine.is_editor_hint():
		return
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 0.8, 1.2)
	tween.tween_property(label, "modulate:a", 0.0, 1.2)
	tween.chain().tween_callback(label.queue_free)


func _spawn_tracer(from: Vector3, to: Vector3, duration: float) -> void:
	if _effects_root == null:
		return
	var bolt := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _TRACER_COLOR
	mat.emission_enabled = true
	mat.emission = _TRACER_COLOR
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	bolt.mesh = mesh
	bolt.position = from
	_effects_root.add_child(bolt)
	if not bolt.is_inside_tree() or Engine.is_editor_hint():
		bolt.queue_free()
		return
	var tween := bolt.create_tween()
	tween.tween_property(bolt, "position", to, maxf(duration, 0.05))
	tween.tween_callback(bolt.queue_free)


func _spawn_explosion(at: Vector3) -> void:
	if _effects_root == null:
		return
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.18
	torus.outer_radius = 0.28
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _EXPLOSION_COLOR
	mat.emission_enabled = true
	mat.emission = _EXPLOSION_COLOR
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torus.material = mat
	ring.mesh = torus
	ring.position = at
	_effects_root.add_child(ring)
	if not ring.is_inside_tree() or Engine.is_editor_hint():
		ring.queue_free()
		return
	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * 4.0, 0.4)
	tween.tween_property(ring, "transparency", 1.0, 0.4)
	tween.chain().tween_callback(ring.queue_free)


# ---------- Internals: visibility / fog ----------


func _visible_entity_ids_for_player(player_id: int) -> Dictionary[int, bool]:
	var out: Dictionary[int, bool] = {}
	if _state == null or _registry == null:
		return out
	var visibility: VisionSystem.Visibility = VISION_SYSTEM_SCRIPT.compute_player_visibility(
		_state, _registry, player_id
	)
	for entity in _state.entities_sorted_by_id():
		if VISION_SYSTEM_SCRIPT.is_entity_visible_to_player(
			entity, _state, _registry, player_id, visibility
		):
			out[entity.id] = true
	return out


func _was_entity_visible_for_event(entity_id: int) -> bool:
	return _event_visible_entity_ids.get(entity_id, false)


func _refresh_all_visibility() -> void:
	if _state == null or _registry == null:
		return
	var visibility: VisionSystem.Visibility = VISION_SYSTEM_SCRIPT.compute_player_visibility(
		_state, _registry, _perspective_player_id
	)
	_visibility_by_player[_perspective_player_id] = visibility
	var seen: Dictionary = _seen_tiles_by_player.get(_perspective_player_id, {})
	for tile in visibility.visible_tiles():
		seen[tile] = true
	_seen_tiles_by_player[_perspective_player_id] = seen

	for entity_id in _views_by_id:
		var view: EntityView3D = _views_by_id[entity_id]
		var entity := _state.get_entity_by_id(entity_id)
		if entity == null:
			continue
		var def := _def_for_entity(entity)
		var owned := entity.owner_player_id == _perspective_player_id
		var resource := def != null and def.resource_source != null
		var currently_visible: bool = (
			owned
			or (VISION_SYSTEM_SCRIPT.is_entity_visible_to_player(
				entity, _state, _registry, _perspective_player_id, visibility
			))
		)
		var building := def != null and def.tags.has("building")
		if currently_visible:
			view.visible = true
			view.set_fog_silhouette(false)
		elif resource:
			view.visible = true
			view.set_fog_silhouette(false)
		elif building and _rect_previously_seen(_entity_rect_or_default(entity, _state, def)):
			view.visible = true
			view.set_fog_silhouette(true)
		else:
			view.visible = false
	_rebuild_fog_overlay(visibility)


func _rect_previously_seen(rect: Rect2i) -> bool:
	var seen: Dictionary = _seen_tiles_by_player.get(_perspective_player_id, {})
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			if seen.has(Vector2i(x, y)):
				return true
	return false


func _rebuild_fog_overlay(visibility: VisionSystem.Visibility) -> void:
	_clear_children(_fog_root)
	if _state == null or _state.tile_grid == null:
		return
	var tiles: Array = []
	for y in range(_state.tile_grid.height):
		var run_start := -1
		for x in range(_state.tile_grid.width):
			var fogged := not visibility.is_tile_visible(Vector2i(x, y))
			if fogged and run_start < 0:
				run_start = x
			elif not fogged and run_start >= 0:
				tiles.append(Rect2i(run_start, y, x - run_start, 1))
				run_start = -1
		if run_start >= 0:
			tiles.append(Rect2i(run_start, y, _state.tile_grid.width - run_start, 1))
	if tiles.is_empty():
		return
	# One mesh for the whole overlay: a quad per fogged run.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rect: Rect2i in tiles:
		var x0 := float(rect.position.x)
		var x1 := float(rect.end.x)
		var z0 := float(rect.position.y)
		var z1 := float(rect.end.y)
		var y := 0.05
		surface.add_vertex(Vector3(x0, y, z0))
		surface.add_vertex(Vector3(x1, y, z0))
		surface.add_vertex(Vector3(x1, y, z1))
		surface.add_vertex(Vector3(x0, y, z0))
		surface.add_vertex(Vector3(x1, y, z1))
		surface.add_vertex(Vector3(x0, y, z1))
	var mesh := surface.commit()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _flat_material(_FOG_COLOR)
	_fog_root.add_child(node)


# ---------- Internals: preview drawing ----------


func _render_action_preview(preview: Dictionary) -> void:
	var color: Color = _PREVIEW_COLOR_BY_KIND.get(preview.get("kind", ""), _PREVIEW_DEFAULT_COLOR)
	var path: Array = preview.get("path", [])
	var points := PackedVector3Array()
	for tile in path:
		var t: Vector2i = tile
		points.append(Vector3(t.x + 0.5, 0.06, t.y + 0.5))
	if points.size() < 2 and preview.has("target_tile"):
		var view: EntityView3D = _views_by_id.get(preview.get("entity_id", -1))
		var target: Vector2i = preview.get("target_tile", Vector2i.ZERO)
		if view != null:
			points = PackedVector3Array(
				[
					view.position + Vector3(0.0, 0.06, 0.0),
					Vector3(target.x + 0.5, 0.06, target.y + 0.5),
				]
			)
	if points.size() >= 2:
		_action_previews_root.add_child(_polyline(points, color))


func _polyline(points: PackedVector3Array, color: Color) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	return node


func _tile_quads(tiles: Array, color: Color) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tile in tiles:
		var t: Vector2i = tile
		var y := 0.04
		surface.add_vertex(Vector3(t.x, y, t.y))
		surface.add_vertex(Vector3(t.x + 1, y, t.y))
		surface.add_vertex(Vector3(t.x + 1, y, t.y + 1))
		surface.add_vertex(Vector3(t.x, y, t.y))
		surface.add_vertex(Vector3(t.x + 1, y, t.y + 1))
		surface.add_vertex(Vector3(t.x, y, t.y + 1))
	var node := MeshInstance3D.new()
	node.mesh = surface.commit()
	node.material_override = _flat_material(color)
	return node


func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


# ---------- Internals: shared helpers ----------


func _clear_children(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		child.queue_free()
		root.remove_child(child)


func _indicator_entity_id(indicator: Variant) -> int:
	if indicator is Dictionary:
		return int((indicator as Dictionary).get("entity_id", -1))
	if indicator is int or indicator is float:
		return int(indicator)
	return -1


func _is_entity_hit_testable(entity_id: int) -> bool:
	var entity := _state.get_entity_by_id(entity_id)
	if not _is_renderable_entity(entity):
		return false
	var def := _def_for_entity(entity)
	if def != null and def.resource_source != null:
		return true
	if entity.owner_player_id == _perspective_player_id:
		return true
	var visibility: VisionSystem.Visibility = _visibility_by_player.get(_perspective_player_id)
	if visibility == null:
		return false
	return VISION_SYSTEM_SCRIPT.is_entity_visible_to_player(
		entity, _state, _registry, _perspective_player_id, visibility
	)


func _is_renderable_entity(entity: Entity) -> bool:
	if entity == null:
		return false
	var def := _def_for_entity(entity)
	if def == null:
		return false
	if def.resource_source != null:
		return true
	return entity.current_hp > 0


func _entity_rect_or_default(entity: Entity, state: MatchState, def: EntityDef) -> Rect2i:
	if state != null and state.tile_grid != null:
		var rect: Rect2i = state.tile_grid.entity_rect(entity.id)
		if rect.size.x > 0 and rect.size.y > 0:
			return rect
	var fp: Vector2i = def.footprint if def != null else Vector2i.ONE
	return Rect2i(entity.origin, Vector2i(maxi(fp.x, 1), maxi(fp.y, 1)))


func _def_for_entity(entity: Entity) -> EntityDef:
	if entity == null or _registry == null:
		return null
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	return _registry.get_by_id(def_id)


# Statuses may carry a presentation sprite_key (sieged tank renders the
# turret model); the last one applied wins.
func _visual_key_for_entity(entity: Entity) -> String:
	var key: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	for status in entity.statuses:
		if status != null and status.sprite_key != "":
			key = status.sprite_key
	return key
