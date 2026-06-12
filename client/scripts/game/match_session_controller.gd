class_name MatchSessionController
extends RefCounted

# Shared match-session core for the play modes (plan/m1/00). Owns everything
# between raw input and "an order was queued": selection (click/box/drag),
# context right-click resolution, the pending-command state machine, the
# issue_* family, action/target previews, idle-worker indicators, camera
# pan/zoom, hover, and the game SubViewport.
#
# The host (dev play mode, network play mode, later an AI-driven mode) is a
# Node that forwards `_unhandled_input` to `handle_unhandled_input()` and
# implements the duck-typed `session_*` delegate contract:
#
#   session_state() -> MatchState
#   session_registry() -> EntityRegistry
#   session_renderer() -> MatchRenderer
#   session_local_player_id() -> int           (-1 = no active match)
#   session_cockpit() -> Control               (may be null)
#   session_input_enabled() -> bool            (gate for world input)
#   session_reject_edit() -> bool              (true = edits blocked now;
#                                               host shows its own message)
#   session_show_status(message: String)
#   session_update_hud()                       (host HUD body; previews and
#                                               idle workers live HERE, so the
#                                               host must not re-refresh them)
#   session_on_escape()
#   session_handle_mode_key_input(event: InputEventKey) -> bool
#   session_on_hover_tile(tile: Vector2i)
#   session_on_pointer_exited_viewport()
#   session_on_order_issued(kind: String, context: Dictionary, ok: bool)
#
# Behavior notes (intentional unifications of pre-split drift):
# - Box selection filters through DevTurnInput.can_select_movable_entity and
#   dedupes (was dev-only).
# - Selection changes refresh action previews (was network-only).
# - select_entity_id resets the context cursor on failure (was dev-only) AND
#   refreshes previews (was network-only).
# - Viewport math uses the local-rect-aware versions (was network-only).

const _SELECTION_DRAG_CONTROLLER_SCRIPT: Script = preload(
	"res://scripts/game/selection_drag_controller.gd"
)
const _ACTION_PREVIEW_BUILDER_SCRIPT := preload("res://scripts/game/action_preview_builder.gd")

const PENDING_NONE := ""
const PENDING_MOVE := "move"
const PENDING_TARGET := "target"
const PENDING_BUILD := "build"
const PENDING_GATHER := "gather"
const CONTEXT_NONE := "none"
const CONTEXT_MOVE := "move"
const CONTEXT_ATTACK := "attack"
const CONTEXT_GATHER := "gather"
const CONTEXT_RALLY_MOVE := "rally_move"
const CONTEXT_RALLY_GATHER := "rally_gather"
const CONTEXT_INVALID := "invalid"
const CAMERA_ZOOM_STEP: float = 1.15
const FALLBACK_TOP_HUD_HEIGHT: float = 46.0
const FALLBACK_BOTTOM_HUD_HEIGHT: float = 190.0
const GAME_VIEWPORT_MARGIN_LEFT: float = 0.0
const GAME_VIEWPORT_MARGIN_RIGHT: float = 0.0

var _host: Node = null
var _input: DevTurnInput = null
var _game_viewport_container: SubViewportContainer = null
var _game_viewport: SubViewport = null
var _selection_drag: Variant = _SELECTION_DRAG_CONTROLLER_SCRIPT.new()
var _action_preview_builder: ActionPreviewBuilder = (
	_ACTION_PREVIEW_BUILDER_SCRIPT.new() as ActionPreviewBuilder
)
var _show_all_orders: bool = false
var _is_panning_camera: bool = false
var _pending_command: String = PENDING_NONE
var _pending_build_def_id: String = ""
var _hover_tile: Vector2i = Vector2i.ZERO
var _has_hover_tile: bool = false


func setup(host: Node, input: DevTurnInput, drag_threshold_pixels: float) -> void:
	_host = host
	_input = input
	_selection_drag.threshold_pixels = drag_threshold_pixels


func input_model() -> DevTurnInput:
	return _input


func set_show_all_orders(show_all: bool) -> void:
	_show_all_orders = show_all


func show_all_orders() -> bool:
	return _show_all_orders


# ---------- Game viewport ----------


func game_viewport() -> SubViewport:
	return _game_viewport


func ensure_game_viewport() -> void:
	if _game_viewport_container != null and _game_viewport != null:
		sync_game_viewport_rect()
		return
	_game_viewport_container = SubViewportContainer.new()
	_game_viewport_container.name = "GameViewportContainer"
	_game_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_viewport_container.stretch = false
	_game_viewport_container.anchor_left = 0.0
	_game_viewport_container.anchor_right = 0.0
	_game_viewport_container.anchor_top = 0.0
	_game_viewport_container.anchor_bottom = 0.0
	_game_viewport_container.offset_left = GAME_VIEWPORT_MARGIN_LEFT
	_game_viewport_container.offset_top = _top_hud_height()
	_game_viewport_container.offset_right = -GAME_VIEWPORT_MARGIN_RIGHT
	_game_viewport_container.offset_bottom = -_bottom_hud_height()
	_host.add_child(_game_viewport_container)

	_game_viewport = SubViewport.new()
	_game_viewport.name = "GameViewport"
	_game_viewport.disable_3d = true
	_game_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_game_viewport_container.add_child(_game_viewport)
	sync_game_viewport_rect()


func sync_game_viewport_rect() -> void:
	if _game_viewport_container == null:
		return
	var top_hud_height: float = _top_hud_height()
	var bottom_hud_height: float = _bottom_hud_height()
	_game_viewport_container.offset_left = GAME_VIEWPORT_MARGIN_LEFT
	_game_viewport_container.offset_top = top_hud_height
	_game_viewport_container.offset_right = -GAME_VIEWPORT_MARGIN_RIGHT
	_game_viewport_container.offset_bottom = -bottom_hud_height
	if _game_viewport == null:
		return
	var viewport_size: Vector2 = _root_viewport_size()
	var game_width: float = maxf(
		viewport_size.x - GAME_VIEWPORT_MARGIN_LEFT - GAME_VIEWPORT_MARGIN_RIGHT, 1.0
	)
	var game_height: float = maxf(viewport_size.y - top_hud_height - bottom_hud_height, 1.0)
	_game_viewport_container.position = Vector2(GAME_VIEWPORT_MARGIN_LEFT, top_hud_height)
	_game_viewport_container.size = Vector2(game_width, game_height)
	_game_viewport.size = Vector2i(roundi(game_width), roundi(game_height))


func game_viewport_screen_rect() -> Rect2:
	var viewport_size: Vector2 = _root_viewport_size()
	var top_hud_height: float = _top_hud_height()
	var bottom_hud_height: float = _bottom_hud_height()
	var position: Vector2 = Vector2(GAME_VIEWPORT_MARGIN_LEFT, top_hud_height)
	var size: Vector2 = Vector2(
		maxf(viewport_size.x - GAME_VIEWPORT_MARGIN_LEFT - GAME_VIEWPORT_MARGIN_RIGHT, 1.0),
		maxf(viewport_size.y - top_hud_height - bottom_hud_height, 1.0)
	)
	return Rect2(position, size)


func screen_to_game_viewport_position(screen_position: Vector2) -> Vector2:
	var game_rect: Rect2 = game_viewport_screen_rect()
	var local_rect: Rect2 = _game_viewport_local_rect(game_rect)
	# Keep viewport-local positions unchanged; screen/global positions subtract
	# the game_viewport_screen_rect() offset.
	if local_rect.has_point(screen_position) and not game_rect.has_point(screen_position):
		return screen_position
	return screen_position - game_rect.position


func _game_viewport_local_rect(game_rect: Rect2) -> Rect2:
	return Rect2(Vector2.ZERO, game_rect.size)


func _event_inside_game_viewport(event: InputEventMouse) -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	var game_rect: Rect2 = game_viewport_screen_rect()
	return (
		game_rect.has_point(event.position)
		or _game_viewport_local_rect(game_rect).has_point(event.position)
	)


func _event_world_position(event: InputEventMouse) -> Vector2:
	var renderer: MatchRenderer = _renderer()
	if renderer == null:
		return event.position
	if renderer.get_viewport() == null:
		return event.position
	if DisplayServer.get_name() == "headless":
		return event.position
	var game_position: Vector2 = screen_to_game_viewport_position(event.position)
	if renderer.has_method("screen_to_world"):
		return renderer.call("screen_to_world", game_position)
	return renderer.get_global_mouse_position()


func _root_viewport_size() -> Vector2:
	var viewport: Viewport = _host.get_viewport() if _host != null else null
	if viewport != null:
		var size: Vector2 = viewport.get_visible_rect().size
		if size.x > 0.0 and size.y > 0.0:
			return size
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080.0))
	)


func _top_hud_height() -> float:
	var cockpit: Control = _host.session_cockpit() if _host != null else null
	var top_bar: Control = null
	if cockpit != null:
		top_bar = cockpit.get_node_or_null("TopBar") as Control
	if top_bar == null:
		return FALLBACK_TOP_HUD_HEIGHT
	return maxf(top_bar.offset_bottom - top_bar.offset_top, 1.0)


func _bottom_hud_height() -> float:
	var cockpit: Control = _host.session_cockpit() if _host != null else null
	var bottom_deck: Control = null
	if cockpit != null:
		bottom_deck = cockpit.get_node_or_null("BottomDeck") as Control
	if bottom_deck == null:
		return FALLBACK_BOTTOM_HUD_HEIGHT
	return maxf(bottom_deck.offset_bottom - bottom_deck.offset_top, 1.0)


# ---------- Input routing ----------


func handle_unhandled_input(event: InputEvent) -> void:
	var cancel_pressed: bool = event.is_action_pressed("ui_cancel")
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		cancel_pressed = (
			cancel_pressed
			or (key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE)
		)
	if cancel_pressed:
		reset_selection_drag()
		_host.session_on_escape()
		_set_event_handled()
		return
	if not _host.session_input_enabled():
		return
	if _host.session_is_blocking_overlay_visible():
		reset_selection_drag()
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if _host.session_handle_mode_key_input(key_event):
			_set_event_handled()
			return
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_A:
			begin_target()
			_set_event_handled()
			return
	if event is InputEventMouse and not _event_inside_game_viewport(event as InputEventMouse):
		reset_selection_drag()
		_has_hover_tile = false
		_host.session_on_pointer_exited_viewport()
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _is_panning_camera:
			_renderer().pan_camera_by_screen_delta(motion.relative)
			return
		if _selection_drag.active() and motion.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
			var drag_world: Vector2 = _event_world_position(motion)
			if _selection_drag.update(motion.position, drag_world):
				_renderer().set_selection_box_world_rect(_selection_drag.selection_world_rect())
				return
		var hover_tile: Vector2i = _renderer().world_to_tile(_event_world_position(motion))
		set_hover_tile(hover_tile)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_renderer().zoom_camera(CAMERA_ZOOM_STEP)
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_renderer().zoom_camera(1.0 / CAMERA_ZOOM_STEP)
			return
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning_camera = button.pressed
			return
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			if _selection_drag.active():
				var release: Dictionary = _selection_drag.release(
					button.position, _event_world_position(button)
				)
				_renderer().clear_selection_box()
				if release.get("dragging", false):
					_apply_box_selection(
						release.get("world_rect", Rect2()), release.get("additive", false)
					)
				else:
					var release_tile: Vector2i = _renderer().world_to_tile(
						_event_world_position(button)
					)
					_apply_click_selection(release_tile, release.get("additive", false))
				return
			reset_selection_drag()
		if not button.pressed:
			return
		var tile: Vector2i = _renderer().world_to_tile(_event_world_position(button))
		_host.session_on_hover_tile(tile)
		if button.button_index == MOUSE_BUTTON_LEFT:
			if _pending_command != PENDING_NONE:
				confirm_pending_at_tile(tile, button.shift_pressed)
				return
			if _host.session_reject_edit():
				return
			_selection_drag.begin(
				button.position, _event_world_position(button), button.shift_pressed
			)
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			if _pending_command != PENDING_NONE:
				cancel_pending_command()
				return
			issue_context_at_tile(tile, button.shift_pressed)


func _set_event_handled() -> void:
	var viewport: Viewport = _host.get_viewport() if _host != null else null
	if viewport != null:
		viewport.set_input_as_handled()


# ---------- Selection ----------


func select_entity_id(entity_id: int) -> bool:
	if _host.session_reject_edit():
		return false
	var ok: bool = _input.select_entity(entity_id)
	var renderer: MatchRenderer = _renderer()
	if renderer != null:
		_clear_build_placement_preview()
		if ok:
			sync_selection_highlights()
		else:
			renderer.clear_input_highlights()
	if not ok:
		_reset_context_cursor()
	refresh_action_previews()
	_host.session_update_hud()
	return ok


func _apply_box_selection(world_rect: Rect2, additive: bool) -> void:
	if _host.session_reject_edit():
		return
	var renderer: MatchRenderer = _renderer()
	if renderer == null:
		return
	var ids: Array[int] = renderer.owned_movable_entity_ids_in_world_rect(
		world_rect, _input.active_player_id()
	)
	ids = _movable_selection_ids(ids)
	var ok: bool = (
		_input.add_entities_to_selection(ids) if additive else _input.select_entities(ids)
	)
	if ok or not additive:
		sync_selection_highlights()
	_clear_build_placement_preview()
	refresh_action_previews()
	_host.session_update_hud()


func _apply_click_selection(tile: Vector2i, additive: bool) -> void:
	if _host.session_reject_edit():
		return
	var renderer: MatchRenderer = _renderer()
	var entity_id: int = renderer.entity_id_at_tile(tile) if renderer != null else -1
	if additive:
		if entity_id >= 0 and _input.toggle_entity_selection(entity_id):
			sync_selection_highlights()
			_clear_build_placement_preview()
			refresh_action_previews()
		_host.session_update_hud()
		return
	if entity_id >= 0:
		select_entity_id(entity_id)
		return
	_input.clear_selection()
	if renderer != null:
		renderer.clear_input_highlights()
	_reset_context_cursor()
	refresh_action_previews()
	_host.session_show_status("Selection cleared.")
	_host.session_update_hud()


func _movable_selection_ids(entity_ids: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for entity_id in entity_ids:
		if out.has(entity_id):
			continue
		if _input.can_select_movable_entity(entity_id):
			out.append(entity_id)
	return out


func sync_selection_highlights() -> void:
	var renderer: MatchRenderer = _renderer()
	if renderer == null:
		return
	renderer.set_selected_entity_ids(_input.selected_entity_ids())


func reset_selection_drag() -> void:
	if _selection_drag != null:
		_selection_drag.reset()
	var renderer: MatchRenderer = _renderer()
	if renderer != null:
		renderer.clear_selection_box()
	_is_panning_camera = false


# "Minerals remaining: N" / "Gas remaining: unlimited" for a selected
# resource source, "" otherwise. Shared by both play modes' HUDs.
func selection_resource_text() -> String:
	if _input.selected_entity_ids().size() != 1:
		return ""
	var entity: Entity = _input.resource_source_entity(_input.selected_entity_id())
	if entity == null:
		return ""
	var registry: EntityRegistry = _host.session_registry()
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	var def: EntityDef = registry.get_by_id(def_id) if registry != null else null
	if def == null or def.resource_source == null:
		return ""
	var resource_name: String = def.resource_source.resource_type.capitalize()
	if entity.current_resource_amount < 0:
		return "%s remaining: unlimited" % resource_name
	return "%s remaining: %d" % [resource_name, entity.current_resource_amount]


func selected_entity() -> Entity:
	var state: MatchState = _host.session_state()
	if state == null:
		return null
	var entity_id: int = _input.selected_entity_id()
	if entity_id < 0:
		return null
	return state.get_entity_by_id(entity_id)


# ---------- Issue family ----------


func issue_move_selected(tile: Vector2i, queue_requested: bool = false) -> bool:
	if _host.session_reject_edit():
		return false
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_move(tile)
	_input.set_queue_modifier_active(false)
	_after_order_issued("move", {"tile": tile}, ok)
	return ok


func issue_attack_move_selected(tile: Vector2i, queue_requested: bool = false) -> bool:
	if _host.session_reject_edit():
		return false
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_attack_move(tile)
	_input.set_queue_modifier_active(false)
	_after_order_issued("attack_move", {"tile": tile}, ok)
	return ok


func issue_attack_selected(target_entity_id: int, queue_requested: bool = false) -> bool:
	if _host.session_reject_edit():
		return false
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_target(target_entity_id)
	_input.set_queue_modifier_active(false)
	_after_order_issued("target", {"target_entity_id": target_entity_id}, ok)
	return ok


func issue_gather_selected(target_entity_id: int, queue_requested: bool = false) -> bool:
	if _host.session_reject_edit():
		return false
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_gather(target_entity_id)
	_input.set_queue_modifier_active(false)
	_after_order_issued("gather", {"target_entity_id": target_entity_id}, ok)
	return ok


func issue_rally_move_selected(tile: Vector2i) -> bool:
	if _host.session_reject_edit():
		return false
	var selected_id: int = _input.selected_entity_id()
	var ok: bool = _input.issue_rally_move(tile)
	_after_order_issued("rally_move", {"selected_id": selected_id, "tile": tile}, ok)
	return ok


func issue_rally_gather_selected(target_entity_id: int) -> bool:
	if _host.session_reject_edit():
		return false
	var selected_id: int = _input.selected_entity_id()
	var ok: bool = _input.issue_rally_gather(target_entity_id)
	_after_order_issued(
		"rally_gather", {"selected_id": selected_id, "target_entity_id": target_entity_id}, ok
	)
	return ok


func issue_build_selected(def_id: String, tile: Vector2i, queue_requested: bool = false) -> bool:
	if _host.session_reject_edit():
		return false
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_build(def_id, tile)
	_input.set_queue_modifier_active(false)
	_after_order_issued("build", {"def_id": def_id, "tile": tile}, ok)
	return ok


func issue_cancel_selected(cancel_index: int = -1) -> bool:
	if _host.session_reject_edit():
		return false
	var ok: bool = _input.issue_cancel(cancel_index)
	_after_order_issued("cancel", {"cancel_index": cancel_index}, ok)
	return ok


func issue_train_selected(def_id: String) -> bool:
	if _host.session_reject_edit():
		return false
	var selected_id: int = _input.selected_entity_id()
	var repeat_enabled: bool = _input.selected_repeat_train_enabled()
	var ok: bool = _input.issue_train(def_id)
	_after_order_issued(
		"train",
		{"selected_id": selected_id, "def_id": def_id, "repeat_enabled": repeat_enabled},
		ok
	)
	return ok


func issue_research_selected(def_id: String) -> bool:
	if _host.session_reject_edit():
		return false
	var ok: bool = _input.issue_research(def_id)
	_after_order_issued("research", {"def_id": def_id}, ok)
	return ok


func issue_ability_selected(ability_id: String) -> bool:
	if _host.session_reject_edit():
		return false
	var ok: bool = _input.issue_ability(ability_id)
	_after_order_issued("ability", {"ability_id": ability_id}, ok)
	return ok


func issue_repeat_train_selected(enabled: bool) -> bool:
	if _host.session_reject_edit():
		return false
	var selected_id: int = _input.selected_entity_id()
	var ok: bool = _input.issue_repeat_train_toggle(enabled)
	_after_order_issued("repeat_train", {"selected_id": selected_id, "enabled": enabled}, ok)
	return ok


func _after_order_issued(kind: String, context: Dictionary, ok: bool) -> void:
	_host.session_on_order_issued(kind, context, ok)
	refresh_action_previews()
	_host.session_update_hud()


# ---------- Context actions ----------


func issue_context_at_tile(tile: Vector2i, queue_requested: bool = false) -> bool:
	var context: Dictionary = context_action_at_tile(tile)
	var action: String = context.get("action", CONTEXT_NONE)
	if action == CONTEXT_MOVE:
		return issue_move_selected(tile, queue_requested)
	if action == CONTEXT_ATTACK:
		return issue_attack_selected(context.get("target_entity_id", -1), queue_requested)
	if action == CONTEXT_GATHER:
		return issue_gather_selected(context.get("target_entity_id", -1), queue_requested)
	if action == CONTEXT_RALLY_MOVE:
		return issue_rally_move_selected(tile)
	if action == CONTEXT_RALLY_GATHER:
		return issue_rally_gather_selected(context.get("target_entity_id", -1))
	var message: String = context.get("message", "")
	if message != "":
		_host.session_show_status(message)
	return false


func context_action_at_tile(tile: Vector2i) -> Dictionary:
	if _host.session_reject_context_query():
		return _context_result(CONTEXT_NONE, Input.CURSOR_ARROW, "")
	if _pending_command != PENDING_NONE:
		return _context_result(CONTEXT_NONE, Input.CURSOR_ARROW, "")
	var state: MatchState = _host.session_state()
	if state == null or state.tile_grid == null:
		return _context_result(CONTEXT_NONE, Input.CURSOR_ARROW, "")
	if not state.tile_grid.is_in_bounds(tile):
		return _context_result(CONTEXT_NONE, Input.CURSOR_ARROW, "")
	if selected_entity() == null:
		return _context_result(CONTEXT_NONE, Input.CURSOR_ARROW, "")
	var target_id: int = _entity_id_at_tile(tile)
	if target_id >= 0:
		var target: Entity = state.get_entity_by_id(target_id)
		if target == null:
			return _context_result(CONTEXT_INVALID, Input.CURSOR_FORBIDDEN, "Invalid target.")
		if _is_enemy_target(target):
			if _input.can_issue_target():
				return _context_result(
					CONTEXT_ATTACK, Input.CURSOR_CROSS, "", {"target_entity_id": target_id}
				)
			return _context_result(
				CONTEXT_INVALID, Input.CURSOR_FORBIDDEN, "Selected entity cannot attack."
			)
		if _is_resource_context_target(target):
			if _selected_can_gather_from(target_id):
				return _context_result(
					CONTEXT_GATHER, Input.CURSOR_POINTING_HAND, "", {"target_entity_id": target_id}
				)
			if not _input.has_multiple_selection() and _selected_can_rally_gather_to(target_id):
				return _context_result(
					CONTEXT_RALLY_GATHER,
					Input.CURSOR_POINTING_HAND,
					"",
					{"target_entity_id": target_id}
				)
			return _context_result(
				CONTEXT_INVALID,
				Input.CURSOR_FORBIDDEN,
				"That resource target is not valid for the selected entity."
			)
		return _context_result(CONTEXT_INVALID, Input.CURSOR_FORBIDDEN, "Target tile is occupied.")
	if not _input.has_multiple_selection() and _input.can_issue_rally_move():
		return _context_result(CONTEXT_RALLY_MOVE, Input.CURSOR_MOVE, "")
	if _input.can_issue_move():
		return _context_result(CONTEXT_MOVE, Input.CURSOR_MOVE, "")
	return _context_result(CONTEXT_INVALID, Input.CURSOR_FORBIDDEN, "Selected entity cannot move.")


func context_cursor_shape_at_tile(tile: Vector2i) -> int:
	var context: Dictionary = context_action_at_tile(tile)
	return context.get("cursor_shape", Input.CURSOR_ARROW)


func _context_result(
	action: String, cursor_shape: int, message: String, extra: Dictionary = {}
) -> Dictionary:
	var out: Dictionary = {"action": action, "cursor_shape": cursor_shape, "message": message}
	for key in extra:
		out[key] = extra[key]
	return out


func _is_enemy_target(entity: Entity) -> bool:
	return (
		entity != null
		and entity.current_hp > 0
		and entity.owner_player_id >= 0
		and entity.owner_player_id != _input.active_player_id()
	)


func _is_resource_context_target(entity: Entity) -> bool:
	var registry: EntityRegistry = _host.session_registry()
	if entity == null or registry == null:
		return false
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	var def: EntityDef = registry.get_by_id(def_id)
	if def == null:
		return false
	return def.resource_source != null or def.tags.has("refinery") or def.tags.has("extractor")


func _selected_can_gather_from(target_entity_id: int) -> bool:
	if not _input.can_issue_gather():
		return false
	return _selected_can_gather_target_valid(target_entity_id)


func _selected_can_rally_gather_to(target_entity_id: int) -> bool:
	return _input.can_issue_rally_gather_to(target_entity_id)


func _selected_can_gather_target_valid(target_entity_id: int) -> bool:
	var state: MatchState = _host.session_state()
	var registry: EntityRegistry = _host.session_registry()
	if state == null or registry == null:
		return false
	var target: Entity = state.get_entity_by_id(target_entity_id)
	if not _is_resource_context_target(target):
		return false
	for entity_id in _input.selected_entity_ids():
		var actor: Entity = state.get_entity_by_id(entity_id)
		if actor == null:
			continue
		if (
			GatherSystem.resolve_source_for_worker(
				state, registry, target_entity_id, actor.owner_player_id
			)
			!= null
		):
			return true
	return false


func _entity_id_at_tile(tile: Vector2i) -> int:
	var state: MatchState = _host.session_state()
	if state == null or state.tile_grid == null:
		return -1
	if not state.tile_grid.is_in_bounds(tile):
		return -1
	var renderer: MatchRenderer = _renderer()
	if renderer != null:
		return renderer.entity_id_at_tile(tile)
	return state.tile_grid.entity_at(tile)


# ---------- Pending commands ----------


func begin_move() -> void:
	if _host.session_reject_edit():
		return
	if not _input.can_issue_move():
		_host.session_show_status("Select a movable unit before Move.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_MOVE
	_pending_build_def_id = ""
	_set_pending_cursor()
	_host.session_show_status("Click a target tile for Move.")


func begin_target() -> void:
	if _host.session_reject_edit():
		return
	if not _input.can_issue_target():
		_host.session_show_status("Select a combat unit before Attack.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_TARGET
	_pending_build_def_id = ""
	_set_pending_cursor()
	_host.session_show_status("Click an enemy or destination tile for Attack.")


func begin_build(def_id: String) -> void:
	if _host.session_reject_edit():
		return
	_clear_build_placement_preview()
	if not _input.build_option_ids().has(def_id):
		_host.session_show_status("Selected entity cannot BUILD %s." % def_id)
		return
	_pending_command = PENDING_BUILD
	_pending_build_def_id = def_id
	_reset_context_cursor()
	_host.session_show_status("Click a placement tile for BUILD %s." % def_id)


func begin_gather() -> void:
	if _host.session_reject_edit():
		return
	if not _input.can_issue_gather():
		_host.session_show_status("Select a worker before GATHER.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_GATHER
	_pending_build_def_id = ""
	_reset_context_cursor()
	_host.session_show_status("Click a mineral patch or refinery to GATHER.")


func confirm_pending_at_tile(tile: Vector2i, queue_requested: bool = false) -> bool:
	if _host.session_reject_edit():
		return false
	if _pending_command == PENDING_MOVE:
		var move_ok: bool = issue_move_selected(tile, queue_requested)
		if move_ok:
			clear_pending_command()
		return move_ok
	if _pending_command == PENDING_TARGET:
		var target_id: int = _entity_id_at_tile(tile)
		var state: MatchState = _host.session_state()
		var target: Entity = state.get_entity_by_id(target_id) if state != null else null
		if (
			target != null
			and target.owner_player_id >= 0
			and target.owner_player_id != _input.active_player_id()
		):
			var target_ok: bool = issue_attack_selected(target_id, queue_requested)
			if target_ok:
				clear_pending_command()
			return target_ok
		var attack_move_ok: bool = issue_attack_move_selected(tile, queue_requested)
		if attack_move_ok:
			clear_pending_command()
		return attack_move_ok
	if _pending_command == PENDING_BUILD:
		var build_ok: bool = issue_build_selected(_pending_build_def_id, tile, queue_requested)
		if build_ok:
			clear_pending_command()
		return build_ok
	if _pending_command == PENDING_GATHER:
		var gather_target_id: int = _entity_id_at_tile(tile)
		if not _selected_can_gather_from(gather_target_id):
			_host.session_show_status("Click a mineral patch or refinery to GATHER.")
			return false
		var gather_ok: bool = issue_gather_selected(gather_target_id, queue_requested)
		if gather_ok:
			clear_pending_command()
		return gather_ok
	return false


func cancel_pending_command() -> void:
	if _host.session_reject_edit():
		return
	if _pending_command == PENDING_NONE:
		return
	clear_pending_command()
	_host.session_show_status("Pending command cancelled.")


func clear_pending_command() -> void:
	_pending_command = PENDING_NONE
	_pending_build_def_id = ""
	_clear_build_placement_preview()
	_reset_context_cursor()


func pending_command_kind() -> String:
	return _pending_command


func pending_build_def_id() -> String:
	return _pending_build_def_id


func pending_cursor_shape() -> int:
	return _pending_cursor_shape()


func _set_pending_cursor() -> void:
	Input.set_default_cursor_shape(_pending_cursor_shape())


func _pending_cursor_shape() -> int:
	if _pending_command == PENDING_TARGET:
		return Input.CURSOR_CROSS
	return Input.CURSOR_ARROW


func _reset_context_cursor() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _update_context_cursor_for_tile(tile: Vector2i) -> void:
	if _pending_command != PENDING_NONE:
		_set_pending_cursor()
		return
	Input.set_default_cursor_shape(context_cursor_shape_at_tile(tile))


# ---------- Hover + previews ----------


func set_hover_tile(tile: Vector2i) -> void:
	var renderer: MatchRenderer = _renderer()
	if renderer == null:
		return
	_hover_tile = tile
	_has_hover_tile = true
	renderer.set_hover_tile(tile)
	if _pending_command == PENDING_BUILD:
		_refresh_build_placement_preview(tile)
		_reset_context_cursor()
	else:
		_clear_build_placement_preview()
		_update_context_cursor_for_tile(tile)
	_host.session_on_hover_tile(tile)


func _refresh_build_placement_preview(tile: Vector2i) -> void:
	var renderer: MatchRenderer = _renderer()
	if renderer == null or not renderer.has_method("set_build_placement_preview"):
		return
	if _pending_command != PENDING_BUILD or _pending_build_def_id == "":
		_clear_build_placement_preview()
		return
	var preview: Dictionary = _input.build_placement_preview(_pending_build_def_id, tile)
	renderer.call("set_build_placement_preview", preview)


func _clear_build_placement_preview() -> void:
	var renderer: MatchRenderer = _renderer()
	if renderer == null or not renderer.has_method("clear_build_placement_preview"):
		return
	renderer.call("clear_build_placement_preview")


func refresh_action_previews() -> void:
	var renderer: MatchRenderer = _renderer()
	if renderer == null:
		return
	var state: MatchState = _host.session_state()
	var registry: EntityRegistry = _host.session_registry()
	var player_id: int = _host.session_local_player_id()
	if renderer.has_method("set_action_previews"):
		var previews: Array[Dictionary] = _action_preview_builder.build(
			state,
			registry,
			_input,
			player_id,
			_input.selected_entity_id(),
			_show_all_orders,
			renderer,
			_input.selected_entity_ids()
		)
		renderer.call("set_action_previews", previews)
	if renderer.has_method("set_target_intent_previews"):
		var target_intents: Array[Dictionary] = _action_preview_builder.build_target_intents(
			state,
			registry,
			_input,
			player_id,
			_input.selected_entity_id(),
			_show_all_orders,
			renderer,
			_input.selected_entity_ids()
		)
		renderer.call("set_target_intent_previews", target_intents)


# ---------- HUD payloads ----------


# Economy summary for the cockpit top bar: last-resolve income plus the
# cost of this turn's queued production orders, for the local player.
func economy_payload() -> Dictionary:
	var player_id: int = _host.session_local_player_id() if _host != null else -1
	if player_id < 0 or _input == null:
		return {}
	var income: Dictionary = _input.last_income_for_player(player_id)
	var committed: Dictionary = _input.committed_spend_for_player(player_id)
	return {
		"income_minerals": income.get("minerals", 0),
		"income_gas": income.get("gas", 0),
		"income_known": income.get("known", false),
		"committed_minerals": committed.get("minerals", 0),
		"committed_gas": committed.get("gas", 0),
		"committed_pop": committed.get("pop", 0),
	}


# Live stats for the cockpit selection panel: effective combat values,
# statuses with durations, worker context, source occupancy, and a damage
# preview against the hovered/ordered target. {} for empty/multi selection.
func selection_stats_payload() -> Dictionary:
	var state: MatchState = _host.session_state()
	var registry: EntityRegistry = _host.session_registry()
	if state == null or registry == null or _input.selected_entity_ids().size() != 1:
		return {}
	var entity: Entity = selected_entity()
	if entity == null:
		return {}
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	var def: EntityDef = registry.get_by_id(def_id)
	if def == null:
		return {}
	var stats: Dictionary = {}
	if def.health != null and def.health.max_hp > 0:
		stats["hp"] = entity.current_hp
		stats["hp_max"] = def.health.max_hp
	var combat: CombatDef = MechanicsSystem.combat_def_for_entity(entity, registry)
	if combat != null:
		stats["damage"] = MechanicsSystem.effective_damage(entity, combat)
		stats["range"] = MechanicsSystem.effective_attack_range(entity, combat)
	if def.movement != null:
		stats["speed"] = MechanicsSystem.movement_speed_for_entity(entity, registry)
	var statuses: Array[Dictionary] = []
	for status: StatusEffect in entity.statuses:
		if status != null and status.status_id != "":
			statuses.append({"id": status.status_id, "duration": status.duration_turns})
	if not statuses.is_empty():
		stats["statuses"] = statuses
	var worker_state: String = _worker_state_text(entity, state, registry)
	if worker_state != "":
		stats["worker_state"] = worker_state
	var occupancy: Dictionary = GatherSystem.gatherer_occupancy(
		state, registry, entity.id, _host.session_local_player_id()
	)
	if not occupancy.is_empty():
		stats["gatherers"] = {"assigned": occupancy["assigned"], "cap": occupancy["cap"]}
	var preview: Dictionary = _damage_preview_payload(entity, state, registry)
	if not preview.is_empty():
		stats["damage_preview"] = preview
	return stats


func _worker_state_text(entity: Entity, state: MatchState, registry: EntityRegistry) -> String:
	if entity.pending_build_def_id != "":
		return "Building %s" % _def_display_label(registry, entity.pending_build_def_id)
	if entity.locked_to_building_id >= 0:
		var building: Entity = state.get_entity_by_id(entity.locked_to_building_id)
		if building != null:
			return "Building %s" % _def_display_label(registry, building.current_def_id)
		return "Building"
	if entity.gather_state != null and entity.gather_state.phase != GatherState.Phase.IDLE:
		var source: Entity = state.get_entity_by_id(entity.gather_state.assigned_source_entity_id)
		var kind: String = "resources"
		if source != null:
			var source_def: EntityDef = registry.get_by_id(source.current_def_id)
			if source_def != null and source_def.resource_source != null:
				kind = source_def.resource_source.resource_type
		return "Gathering %s" % kind
	return ""


func _damage_preview_payload(
	entity: Entity, state: MatchState, registry: EntityRegistry
) -> Dictionary:
	var target: Entity = _damage_preview_target(entity, state)
	if target == null or target.id == entity.id or target.current_hp <= 0:
		return {}
	var amount: int = CombatSystem.preview_damage(entity, target, registry)
	if amount <= 0:
		return {}
	return {
		"amount": amount,
		"target_label": _def_display_label(registry, target.current_def_id),
	}


# Preview target priority: enemy under the cursor while picking an attack
# target, then the unit's standing focus target, then the newest queued
# TARGET order's primary target.
func _damage_preview_target(entity: Entity, state: MatchState) -> Entity:
	if _pending_command == PENDING_TARGET and _has_hover_tile and state.tile_grid != null:
		var hovered_id: int = state.tile_grid.entity_at(_hover_tile)
		if hovered_id >= 0:
			var hovered: Entity = state.get_entity_by_id(hovered_id)
			if hovered != null and hovered.owner_player_id != entity.owner_player_id:
				return hovered
	if entity.focus_target_entity_id >= 0:
		return state.get_entity_by_id(entity.focus_target_entity_id)
	var player_id: int = _host.session_local_player_id()
	if player_id < 0:
		return null
	var orders: Array[EntityOrder] = _input.submit_for_player(player_id).orders
	for order_index in range(orders.size() - 1, -1, -1):
		var order: EntityOrder = orders[order_index]
		if (
			order != null
			and order.entity_id == entity.id
			and order.type == EntityOrder.Type.TARGET
			and not order.target_priority_chain.is_empty()
		):
			return state.get_entity_by_id(order.target_priority_chain[0])
	return null


func _def_display_label(registry: EntityRegistry, def_id: String) -> String:
	var def: EntityDef = registry.get_by_id(def_id) if registry != null else null
	if def != null and def.display_name != "":
		return def.display_name
	return def_id.capitalize()


# ---------- Idle workers ----------


func active_idle_worker_ids() -> Array[int]:
	var out: Array[int] = []
	var state: MatchState = _host.session_state()
	var registry: EntityRegistry = _host.session_registry()
	if state == null or registry == null or _host.session_local_player_id() < 0:
		return out
	var candidates: Array[Entity] = []
	var candidate_ids: Array[int] = []
	for entity: Entity in state.entities_sorted_by_id():
		if _is_active_idle_worker_candidate(entity):
			candidates.append(entity)
			candidate_ids.append(entity.id)
	_input.prune_move_assists_for_entities(candidate_ids)
	for entity: Entity in candidates:
		if not _input.has_move_assist_for_entity(entity.id):
			out.append(entity.id)
	return out


func _is_active_idle_worker_candidate(entity: Entity) -> bool:
	var registry: EntityRegistry = _host.session_registry()
	if (
		entity == null
		or entity.current_hp <= 0
		or entity.owner_player_id != _host.session_local_player_id()
	):
		return false
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	var def: EntityDef = registry.get_by_id(def_id)
	if def == null or def.gather == null or entity.gather_state == null:
		return false
	if entity.gather_state.phase != GatherState.Phase.IDLE:
		return false
	if _has_current_submitted_order_for_entity(entity.id):
		return false
	if _input.future_order_count_for_entity(entity.id) > 0:
		return false
	if (
		ConstructionSystem.has_pending_build(entity)
		or entity.locked_to_building_id >= 0
		or entity.is_constructing
	):
		return false
	if entity.ability_cast != null:
		return false
	return true


func _has_current_submitted_order_for_entity(entity_id: int) -> bool:
	var player_id: int = _host.session_local_player_id()
	if player_id < 0:
		return false
	var submit: SubmitTurn = _input.submit_for_player(player_id)
	for order: EntityOrder in submit.orders:
		if order != null and order.entity_id == entity_id:
			return true
	return false


func refresh_idle_worker_indicators(idle_worker_ids: Array[int]) -> void:
	var renderer: MatchRenderer = _renderer()
	if renderer == null or not renderer.has_method("set_idle_worker_indicators"):
		return
	var indicators: Array[Variant] = []
	for entity_id: int in idle_worker_ids:
		indicators.append({"entity_id": entity_id})
	renderer.call("set_idle_worker_indicators", indicators)


# ---------- Internals ----------


func _renderer() -> MatchRenderer:
	return _host.session_renderer() if _host != null else null
