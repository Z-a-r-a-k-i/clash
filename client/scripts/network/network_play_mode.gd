class_name NetworkPlayMode
extends Node

const MESSAGE := preload("res://scripts/network/network_message.gd")
const SURFACE_SCRIPT := preload("res://scripts/network/match_play_surface.gd")
const COMMAND_OPTION_BUILDER := preload("res://scripts/game/command_option_builder.gd")
const SERVER_SCRIPT := preload("res://scripts/network/network_match_server.gd")
const ACTION_PREVIEW_BUILDER_SCRIPT := preload("res://scripts/game/action_preview_builder.gd")
const SHARED_COCKPIT_SCENE := preload("res://scenes/ui/dev_play_cockpit.tscn")
const SELECTION_DRAG_CONTROLLER_SCRIPT: Script = preload(
	"res://scripts/game/selection_drag_controller.gd"
)

const LOBBY_WIDTH: float = 460.0
const HUD_WIDTH: float = 420.0
const HUD_MARGIN: float = 12.0
const ESCAPE_MENU_WIDTH: float = 340.0
const ESCAPE_MENU_HEIGHT: float = 220.0
const CAMERA_ZOOM_STEP: float = 1.15
const CAMERA_DRAG_THRESHOLD: float = 8.0
const SERVER_URL_CONFIG_SECTION := "network"
const SERVER_URL_CONFIG_KEY := "server_url"
const DEFAULT_SERVER_URL_CONFIG_PATH := "user://network_client.cfg"
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
const FALLBACK_TOP_HUD_HEIGHT: float = 46.0
const FALLBACK_BOTTOM_HUD_HEIGHT: float = 190.0
const GAME_VIEWPORT_MARGIN_LEFT: float = 0.0
const GAME_VIEWPORT_MARGIN_RIGHT: float = 0.0

var _surface: MatchPlaySurface = null
var _game_viewport_container: SubViewportContainer = null
var _game_viewport: SubViewport = null
var _client_controller: NetworkClientController = NetworkClientController.new()
var _client: NetworkClient = null
var _input: DevTurnInput = DevTurnInput.new()
var _action_preview_builder: ActionPreviewBuilder = (
	ACTION_PREVIEW_BUILDER_SCRIPT.new() as ActionPreviewBuilder
)
var _hud_layer: CanvasLayer = null
var _lobby_panel: PanelContainer = null
var _cockpit: DevPlayCockpit = null
var _escape_menu_panel: PanelContainer = null
var _outcome_overlay_panel: PanelContainer = null
var _outcome_title_label: Label = null
var _outcome_detail_label: Label = null
var _lobby_status_label: Label = null
var _submit_button: Button = null
var _show_all_orders_button: BaseButton = null
var _interface_toggle_button: Button = null
var _url_edit: LineEdit = null
var _code_edit: LineEdit = null
var _player_slot: int = -1
var _registry: EntityRegistry = null
var _match_code: String = ""
var _connection_status: String = "Disconnected"
var _match_started: bool = false
var _show_all_orders: bool = false
var _interface_hidden: bool = false
var _is_panning_camera: bool = false
var _selection_drag: Variant = SELECTION_DRAG_CONTROLLER_SCRIPT.new()
var _syncing_submit_button: bool = false
var _submit_in_flight: bool = false
var _server_url_config_path: String = DEFAULT_SERVER_URL_CONFIG_PATH
var _pending_command: String = PENDING_NONE
var _pending_build_def_id: String = ""


func _ready() -> void:
	_selection_drag.threshold_pixels = CAMERA_DRAG_THRESHOLD
	var viewport: Viewport = get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_sync_game_viewport_rect):
		viewport.size_changed.connect(_sync_game_viewport_rect)
	ensure_initialized()
	call_deferred("_auto_connect_default_server")


func ensure_initialized() -> void:
	_build_surface()
	_build_hud()
	_sync_game_viewport_rect()
	_sync_ui()


func bind_authoritative_snapshot(
	state: MatchState, registry: EntityRegistry, player_slot: int
) -> void:
	_reset_selection_drag()
	_build_surface()
	_registry = registry
	_player_slot = player_slot
	_match_started = true
	_input.set_active_player_id(player_slot)
	_input.bind_context(state, registry)
	_input.clear_submissions()
	_clear_pending_command()
	_submit_in_flight = false
	_client_controller.bind_authoritative_state(state, registry, player_slot)
	if _surface != null:
		_surface.bind_authoritative_state(state, registry, player_slot)
	_sync_selection_highlights()
	_update_outcome_overlay(state)
	_refresh_action_previews()
	_sync_ui()
	_update_hud()


func apply_authoritative_result(new_state: MatchState, events: Array) -> void:
	_reset_selection_drag()
	_client_controller.mark_submit_pending(false)
	_submit_in_flight = false
	if new_state == null:
		set_error("missing authoritative state")
		_update_hud()
		return
	if _registry == null:
		set_error("missing registry")
		_update_hud()
		return
	_client_controller.bind_authoritative_state(new_state, _registry, _player_slot)
	_input.bind_context(new_state, _registry)
	_input.clear_submissions(false, false)
	_clear_pending_command()
	_input.apply_resolve_events(_typed_events(events))
	_input.queue_rally_orders_for_train_completed(_typed_events(events))
	_input.queue_move_assists_for_next_turn()
	_input.promote_future_orders_for_next_turn()
	if _surface != null:
		_surface.render_authoritative_result(new_state, events)
	_sync_selection_highlights()
	_update_outcome_overlay(new_state)
	_refresh_action_previews()
	_update_hud()


func player_slot() -> int:
	return _player_slot


func can_submit_turn(submit: SubmitTurn) -> bool:
	return _client_controller.can_submit_turn(submit)


func input_model() -> DevTurnInput:
	return _input


func server_url() -> String:
	if _url_edit != null:
		return _url_edit.text
	return _remembered_server_url()


func set_server_url_config_path(path: String) -> void:
	_server_url_config_path = path
	if _url_edit != null:
		_url_edit.text = _remembered_server_url()


func remember_server_url(url: String) -> void:
	var normalized: String = url.strip_edges()
	if normalized == "":
		return
	var config: ConfigFile = ConfigFile.new()
	config.set_value(SERVER_URL_CONFIG_SECTION, SERVER_URL_CONFIG_KEY, normalized)
	var absolute_dir: String = (
		ProjectSettings.globalize_path(_server_url_config_path).get_base_dir()
	)
	if absolute_dir != "":
		DirAccess.make_dir_recursive_absolute(absolute_dir)
	var err: Error = config.save(_server_url_config_path)
	if err != OK:
		push_warning("NetworkPlayMode: could not remember server URL: %d" % err)


func set_show_all_orders(show_all: bool) -> void:
	_show_all_orders = show_all
	if _cockpit != null:
		_cockpit.set_show_all_orders_enabled(show_all)
	_refresh_action_previews()


func set_interface_hidden(hidden: bool) -> void:
	_interface_hidden = hidden
	_sync_ui()


func select_entity_id(entity_id: int) -> bool:
	if _reject_edit_while_submit_sending():
		return false
	var ok: bool = _input.select_entity(entity_id)
	var renderer: MatchRenderer = _renderer()
	if renderer != null:
		_clear_build_placement_preview()
		if ok:
			_sync_selection_highlights()
		else:
			renderer.clear_input_highlights()
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_move_selected(tile: Vector2i, queue_requested: bool = false) -> bool:
	if _reject_edit_while_submit_sending():
		return false
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_move(tile)
	_input.set_queue_modifier_active(false)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_attack_move_selected(tile: Vector2i, queue_requested: bool = false) -> bool:
	if _reject_edit_while_submit_sending():
		return false
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_attack_move(tile)
	_input.set_queue_modifier_active(false)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_attack_selected(target_entity_id: int, queue_requested: bool = false) -> bool:
	if _reject_edit_while_submit_sending():
		return false
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_target(target_entity_id)
	_input.set_queue_modifier_active(false)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_gather_selected(target_entity_id: int, queue_requested: bool = false) -> bool:
	if _reject_edit_while_submit_sending():
		return false
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_gather(target_entity_id)
	_input.set_queue_modifier_active(false)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_rally_move_selected(tile: Vector2i) -> bool:
	if _reject_edit_while_submit_sending():
		return false
	var selected_id: int = _input.selected_entity_id()
	var ok: bool = _input.issue_rally_move(tile)
	if ok:
		_queue_rally_move_order(selected_id, tile)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_rally_gather_selected(target_entity_id: int) -> bool:
	if _reject_edit_while_submit_sending():
		return false
	var selected_id: int = _input.selected_entity_id()
	var ok: bool = _input.issue_rally_gather(target_entity_id)
	if ok:
		_queue_rally_gather_order(selected_id, target_entity_id)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_build_selected(def_id: String, tile: Vector2i, queue_requested: bool = false) -> bool:
	if _reject_edit_while_submit_sending():
		return false
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_build(def_id, tile)
	_input.set_queue_modifier_active(false)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_cancel_selected(cancel_index: int = -1) -> bool:
	if _reject_edit_while_submit_sending():
		return false
	var ok: bool = _input.issue_cancel(cancel_index)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_train_selected(def_id: String) -> bool:
	if _reject_edit_while_submit_sending():
		return false
	var selected_id: int = _input.selected_entity_id()
	var repeat_enabled: bool = _input.selected_repeat_train_enabled()
	var ok: bool = _input.issue_train(def_id)
	if ok and repeat_enabled:
		_queue_repeat_train_order(selected_id, true, def_id)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_research_selected(def_id: String) -> bool:
	if _reject_edit_while_submit_sending():
		return false
	var ok: bool = _input.issue_research(def_id)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_ability_selected(ability_id: String) -> bool:
	if _reject_edit_while_submit_sending():
		return false
	var ok: bool = _input.issue_ability(ability_id)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_repeat_train_selected(enabled: bool) -> bool:
	if _reject_edit_while_submit_sending():
		return false
	var selected_id: int = _input.selected_entity_id()
	var ok: bool = _input.issue_repeat_train_toggle(enabled)
	if ok:
		_queue_repeat_train_order(selected_id, enabled)
	_refresh_action_previews()
	_update_hud()
	return ok


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
		set_connection_status(message)
	return false


func context_action_at_tile(tile: Vector2i) -> Dictionary:
	if _pending_command != PENDING_NONE:
		return _context_result(CONTEXT_NONE, Input.CURSOR_ARROW, "")
	var state: MatchState = _current_state()
	if state == null or state.tile_grid == null:
		return _context_result(CONTEXT_NONE, Input.CURSOR_ARROW, "")
	if not state.tile_grid.is_in_bounds(tile):
		return _context_result(CONTEXT_NONE, Input.CURSOR_ARROW, "")
	if _selected_entity() == null:
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


func begin_move() -> void:
	if _reject_edit_while_submit_sending():
		return
	if not _input.can_issue_move():
		set_connection_status("Select a movable unit before Move.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_MOVE
	_pending_build_def_id = ""
	_set_pending_cursor()
	set_connection_status("Click a target tile for Move.")


func begin_target() -> void:
	if _reject_edit_while_submit_sending():
		return
	if not _input.can_issue_target():
		set_connection_status("Select a combat unit before Attack.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_TARGET
	_pending_build_def_id = ""
	_set_pending_cursor()
	set_connection_status("Click an enemy or destination tile for Attack.")


func begin_build(def_id: String) -> void:
	if _reject_edit_while_submit_sending():
		return
	_clear_build_placement_preview()
	if not _input.build_option_ids().has(def_id):
		set_connection_status("Selected entity cannot BUILD %s." % def_id)
		return
	_pending_command = PENDING_BUILD
	_pending_build_def_id = def_id
	_reset_context_cursor()
	set_connection_status("Click a placement tile for BUILD %s." % def_id)


func begin_gather() -> void:
	if _reject_edit_while_submit_sending():
		return
	if not _input.can_issue_gather():
		set_connection_status("Select a worker before GATHER.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_GATHER
	_pending_build_def_id = ""
	_reset_context_cursor()
	set_connection_status("Click a mineral patch or refinery to GATHER.")


func confirm_pending_at_tile(tile: Vector2i, queue_requested: bool = false) -> bool:
	if _reject_edit_while_submit_sending():
		return false
	if _pending_command == PENDING_MOVE:
		var move_ok: bool = issue_move_selected(tile, queue_requested)
		if move_ok:
			_clear_pending_command()
		return move_ok
	if _pending_command == PENDING_TARGET:
		var target_id: int = _entity_id_at_tile(tile)
		var state: MatchState = _current_state()
		var target: Entity = state.get_entity_by_id(target_id) if state != null else null
		if (
			target != null
			and target.owner_player_id >= 0
			and target.owner_player_id != _input.active_player_id()
		):
			var target_ok: bool = issue_attack_selected(target_id, queue_requested)
			if target_ok:
				_clear_pending_command()
			return target_ok
		var attack_move_ok: bool = issue_attack_move_selected(tile, queue_requested)
		if attack_move_ok:
			_clear_pending_command()
		return attack_move_ok
	if _pending_command == PENDING_BUILD:
		var build_ok: bool = issue_build_selected(_pending_build_def_id, tile, queue_requested)
		if build_ok:
			_clear_pending_command()
		return build_ok
	if _pending_command == PENDING_GATHER:
		var gather_target_id: int = _entity_id_at_tile(tile)
		if not _selected_can_gather_from(gather_target_id):
			set_connection_status("Click a mineral patch or refinery to GATHER.")
			return false
		var gather_ok: bool = issue_gather_selected(gather_target_id, queue_requested)
		if gather_ok:
			_clear_pending_command()
		return gather_ok
	return false


func cancel_pending_command() -> void:
	if _reject_edit_while_submit_sending():
		return
	if _pending_command == PENDING_NONE:
		return
	_clear_pending_command()
	set_connection_status("Pending command cancelled.")


func pending_command_kind() -> String:
	return _pending_command


func pending_cursor_shape() -> int:
	return _pending_cursor_shape()


func submit_queued_turn() -> bool:
	if _submit_in_flight:
		set_connection_status("Submit already sending.")
		_update_hud()
		return false
	var submit: SubmitTurn = _client_controller.submit_from_input(_input)
	if submit == null:
		set_error(_client_controller.validation_error())
		_update_hud()
		return false
	if _client == null:
		_client_controller.mark_submit_pending(false)
		_submit_in_flight = false
		set_error("not connected")
		_update_hud()
		return false
	print("NetworkPlayMode: sending submit %s" % _submit_summary(submit))
	var err: Error = _client.submit_turn(submit)
	if err != OK:
		_client_controller.mark_submit_pending(false)
		_submit_in_flight = false
		set_error("submit failed %d" % err)
		_update_hud()
		return false
	_submit_in_flight = true
	set_connection_status("Submit sent. Waiting for server.")
	_update_hud()
	return true


func cancel_submitted_turn() -> bool:
	if _submit_in_flight:
		set_connection_status("Submit sent. Waiting for server.")
		_update_hud()
		return false
	if not _client_controller.submit_pending():
		_update_hud()
		return true
	if _client == null:
		set_error("not connected")
		_update_hud()
		return false
	var err: Error = _client.cancel_submit_turn()
	if err != OK:
		set_error("cancel submit failed %d" % err)
		_update_hud()
		return false
	_client_controller.mark_submit_pending(false)
	_submit_in_flight = false
	_update_hud()
	return true


func _reject_edit_while_submit_sending() -> bool:
	if not _submit_in_flight:
		return false
	set_connection_status("Submit sent. Waiting for server.")
	_update_hud()
	return true


func set_connection_status(status: String) -> void:
	_connection_status = status
	if _lobby_status_label != null:
		_lobby_status_label.text = status
	_update_hud()


func set_invite_code(code: String) -> void:
	var normalized: String = code.strip_edges().to_upper()
	if normalized != "":
		_match_code = normalized
	if _code_edit != null and _match_code != "":
		_code_edit.text = _match_code
	_update_hud()


func set_error(message: String) -> void:
	set_connection_status("Error: %s" % message)


func set_escape_menu_visible(visible: bool) -> void:
	if _escape_menu_panel != null:
		_escape_menu_panel.visible = visible


func _build_surface() -> void:
	if _surface != null:
		return
	_ensure_game_viewport()
	_surface = SURFACE_SCRIPT.new() as MatchPlaySurface
	_surface.name = "MatchPlaySurface"
	if _game_viewport != null:
		_game_viewport.add_child(_surface)
	else:
		add_child(_surface)


func _ensure_game_viewport() -> void:
	if _game_viewport_container != null and _game_viewport != null:
		_sync_game_viewport_rect()
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
	add_child(_game_viewport_container)

	_game_viewport = SubViewport.new()
	_game_viewport.name = "GameViewport"
	_game_viewport.disable_3d = true
	_game_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_game_viewport_container.add_child(_game_viewport)
	_sync_game_viewport_rect()


func _sync_game_viewport_rect() -> void:
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


func _root_viewport_size() -> Vector2:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		var size: Vector2 = viewport.get_visible_rect().size
		if size.x > 0.0 and size.y > 0.0:
			return size
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080.0))
	)


func _top_hud_height() -> float:
	var top_bar: Control = null
	if _cockpit != null:
		top_bar = _cockpit.get_node_or_null("TopBar") as Control
	if top_bar == null:
		return FALLBACK_TOP_HUD_HEIGHT
	return maxf(top_bar.offset_bottom - top_bar.offset_top, 1.0)


func _bottom_hud_height() -> float:
	var bottom_deck: Control = null
	if _cockpit != null:
		bottom_deck = _cockpit.get_node_or_null("BottomDeck") as Control
	if bottom_deck == null:
		return FALLBACK_BOTTOM_HUD_HEIGHT
	return maxf(bottom_deck.offset_bottom - bottom_deck.offset_top, 1.0)


func _build_hud() -> void:
	if _hud_layer != null:
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "NetworkHUD"
	add_child(_hud_layer)
	_build_lobby_panel()
	_build_cockpit()
	_build_outcome_overlay()
	_build_escape_menu()


func _build_lobby_panel() -> void:
	_lobby_panel = PanelContainer.new()
	_lobby_panel.name = "LobbyPanel"
	_lobby_panel.anchor_left = 0.5
	_lobby_panel.anchor_right = 0.5
	_lobby_panel.anchor_top = 0.5
	_lobby_panel.anchor_bottom = 0.5
	_lobby_panel.offset_left = LOBBY_WIDTH * -0.5
	_lobby_panel.offset_right = LOBBY_WIDTH * 0.5
	_lobby_panel.offset_top = -190.0
	_lobby_panel.offset_bottom = 190.0
	_hud_layer.add_child(_lobby_panel)
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 10)
	_lobby_panel.add_child(root)
	var title: Label = _label("Multiplayer")
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)
	_url_edit = LineEdit.new()
	_url_edit.name = "ServerUrl"
	var default_url: String = _remembered_server_url()
	_url_edit.placeholder_text = _default_server_url()
	_url_edit.text = default_url
	root.add_child(_url_edit)
	var connect_button: Button = _button("Connect")
	connect_button.name = "ConnectButton"
	connect_button.pressed.connect(_connect_pressed)
	root.add_child(connect_button)
	var create_button: Button = _button("Create Match")
	create_button.name = "CreateMatch"
	create_button.pressed.connect(_create_pressed)
	root.add_child(create_button)
	var join_row: HBoxContainer = HBoxContainer.new()
	join_row.name = "JoinRow"
	root.add_child(join_row)
	_code_edit = LineEdit.new()
	_code_edit.name = "JoinCode"
	_code_edit.placeholder_text = "Code"
	_code_edit.custom_minimum_size = Vector2(160.0, 34.0)
	join_row.add_child(_code_edit)
	var join_button: Button = _button("Join")
	join_button.name = "JoinMatch"
	join_button.pressed.connect(_join_pressed)
	join_row.add_child(join_button)
	_lobby_status_label = _label("Disconnected")
	_lobby_status_label.name = "LobbyStatus"
	root.add_child(_lobby_status_label)
	var main_menu_button: Button = _button("Main Menu")
	main_menu_button.name = "MainMenu"
	main_menu_button.pressed.connect(_main_menu_pressed)
	root.add_child(main_menu_button)


func _build_cockpit() -> void:
	_interface_toggle_button = _button("Hide UI")
	_interface_toggle_button.name = "InterfaceToggle"
	_interface_toggle_button.anchor_left = 0.0
	_interface_toggle_button.anchor_right = 0.0
	_interface_toggle_button.offset_left = HUD_MARGIN
	_interface_toggle_button.offset_right = HUD_MARGIN + 120.0
	_interface_toggle_button.offset_top = HUD_MARGIN
	_interface_toggle_button.offset_bottom = HUD_MARGIN + 34.0
	_interface_toggle_button.pressed.connect(_interface_toggle_pressed)
	_hud_layer.add_child(_interface_toggle_button)
	_cockpit = SHARED_COCKPIT_SCENE.instantiate() as DevPlayCockpit
	if _cockpit == null:
		push_error("NetworkPlayMode: failed to instantiate shared cockpit HUD.")
		return
	_cockpit.name = "DevPlayCockpit"
	_cockpit.visible = false
	_cockpit.connect("move_requested", Callable(self, "begin_move"))
	_cockpit.connect("target_requested", Callable(self, "begin_target"))
	_cockpit.connect("gather_requested", Callable(self, "begin_gather"))
	_cockpit.connect("build_requested", Callable(self, "begin_build"))
	_cockpit.connect("cancel_requested", Callable(self, "issue_cancel_selected"))
	_cockpit.connect("train_requested", Callable(self, "issue_train_selected"))
	_cockpit.connect("research_requested", Callable(self, "issue_research_selected"))
	_cockpit.connect("ability_requested", Callable(self, "issue_ability_selected"))
	_cockpit.connect("repeat_train_toggled", Callable(self, "issue_repeat_train_selected"))
	_cockpit.connect("resolve_requested", Callable(self, "_submit_turn_button_pressed"))
	_cockpit.connect("show_all_orders_toggled", Callable(self, "set_show_all_orders"))
	_hud_layer.add_child(_cockpit)
	_submit_button = _cockpit.find_child("Resolve", true, false) as Button
	_show_all_orders_button = _cockpit.find_child("ShowAllOrders", true, false) as BaseButton
	_cockpit.set_turn_action_state("Submit Turn", false, false, true)


func _build_outcome_overlay() -> void:
	_outcome_overlay_panel = PanelContainer.new()
	_outcome_overlay_panel.name = "OutcomeOverlay"
	_outcome_overlay_panel.anchor_left = 0.5
	_outcome_overlay_panel.anchor_right = 0.5
	_outcome_overlay_panel.anchor_top = 0.5
	_outcome_overlay_panel.anchor_bottom = 0.5
	_outcome_overlay_panel.offset_left = -180.0
	_outcome_overlay_panel.offset_right = 180.0
	_outcome_overlay_panel.offset_top = -76.0
	_outcome_overlay_panel.offset_bottom = 76.0
	_outcome_overlay_panel.visible = false
	_hud_layer.add_child(_outcome_overlay_panel)
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 8)
	_outcome_overlay_panel.add_child(root)
	_outcome_title_label = _label("")
	_outcome_title_label.name = "OutcomeTitle"
	_outcome_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outcome_title_label.add_theme_font_size_override("font_size", 36)
	root.add_child(_outcome_title_label)
	_outcome_detail_label = _label("")
	_outcome_detail_label.name = "OutcomeDetail"
	_outcome_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_outcome_detail_label)


func _build_escape_menu() -> void:
	_escape_menu_panel = PanelContainer.new()
	_escape_menu_panel.name = "EscapeMenu"
	_escape_menu_panel.anchor_left = 0.5
	_escape_menu_panel.anchor_right = 0.5
	_escape_menu_panel.anchor_top = 0.5
	_escape_menu_panel.anchor_bottom = 0.5
	_escape_menu_panel.offset_left = ESCAPE_MENU_WIDTH * -0.5
	_escape_menu_panel.offset_right = ESCAPE_MENU_WIDTH * 0.5
	_escape_menu_panel.offset_top = ESCAPE_MENU_HEIGHT * -0.5
	_escape_menu_panel.offset_bottom = ESCAPE_MENU_HEIGHT * 0.5
	_escape_menu_panel.visible = false
	_hud_layer.add_child(_escape_menu_panel)
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 10)
	_escape_menu_panel.add_child(root)
	var title: Label = _label("Menu")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var resume_button: Button = _button("Resume")
	resume_button.pressed.connect(func() -> void: set_escape_menu_visible(false))
	root.add_child(resume_button)
	var leave_button: Button = _button("Leave Match")
	leave_button.name = "LeaveMatch"
	leave_button.pressed.connect(_leave_match_pressed)
	root.add_child(leave_button)
	var main_button: Button = _button("Main Menu")
	main_button.name = "MainMenu"
	main_button.pressed.connect(_main_menu_pressed)
	root.add_child(main_button)


func _connect_pressed() -> void:
	if _client == null:
		_client = NetworkClient.new()
		_client.name = "NetworkClient"
		_client.connected_to_server.connect(
			func() -> void: set_connection_status("Connected. Create match or enter a code.")
		)
		_client.message_received.connect(_handle_network_message)
		_client.disconnected.connect(func() -> void: _reset_local_match_state())
		add_child(_client)
	var url: String = _url_edit.text.strip_edges()
	if url == "":
		url = _default_server_url()
		_url_edit.text = url
	remember_server_url(url)
	var err: Error = _client.connect_to_server(url)
	if err == OK:
		set_connection_status("Connecting")
	else:
		set_error("connect failed %d" % err)


func _create_pressed() -> void:
	if _client == null:
		set_error("not connected")
		return
	var err: Error = _client.create_match()
	if err != OK:
		set_error("create failed %d" % err)


func _join_pressed() -> void:
	if _client == null:
		set_error("not connected")
		return
	var err: Error = _client.join_match(_code_edit.text)
	if err != OK:
		set_error("join failed %d" % err)


func _leave_match_pressed() -> void:
	if _client != null:
		_client.disconnect_from_server()
	_reset_local_match_state()


func _reset_local_match_state() -> void:
	_player_slot = -1
	_registry = null
	_match_code = ""
	_match_started = false
	_show_all_orders = false
	_interface_hidden = false
	_client_controller.bind_authoritative_state(null, null, -1)
	_input.clear_submissions()
	_input.clear_selection()
	_clear_pending_command()
	_submit_in_flight = false
	_reset_selection_drag()
	_sync_selection_highlights()
	_refresh_action_previews()
	_update_outcome_overlay(null)
	set_escape_menu_visible(false)
	set_connection_status("Disconnected")
	_sync_ui()
	_update_hud()


func _main_menu_pressed() -> void:
	if _client != null:
		_client.disconnect_from_server()
	var err: Error = get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if err != OK:
		push_error("NetworkPlayMode: failed to return to main menu: %d" % err)


func _handle_network_message(message: Dictionary) -> void:
	var kind: String = MESSAGE.kind(message)
	var payload: Dictionary = MESSAGE.payload(message)
	match kind:
		MESSAGE.MATCH_JOINED:
			_player_slot = payload.get("player_slot", -1)
			set_invite_code(payload.get("code", ""))
			if int(payload.get("player_count", 0)) < 2:
				set_connection_status("Created. Share code %s." % _match_code)
			else:
				set_connection_status("Joined code %s." % _match_code)
			_update_hud()
		MESSAGE.TURN_STARTED:
			_client_controller.mark_submit_pending(false)
			_submit_in_flight = false
			set_invite_code(payload.get("code", _match_code))
			var state: MatchState = payload.get("match_state") as MatchState
			var registry: EntityRegistry = payload.get("registry") as EntityRegistry
			if registry != null:
				_registry = registry
			if state != null and _registry != null and not _match_started:
				bind_authoritative_snapshot(state, _registry, _player_slot)
			var turn_index: int = payload.get("turn_index", -1)
			var status: String = "Turn %d" % turn_index
			if _match_code != "":
				status = "Turn %d - Code %s" % [turn_index, _match_code]
			set_connection_status(status)
			_update_hud()
		MESSAGE.TURN_RESOLVED:
			apply_authoritative_result(
				payload.get("match_state") as MatchState, payload.get("events", [])
			)
		MESSAGE.SUBMIT_TURN:
			_submit_in_flight = false
			if payload.get("accepted", false):
				_client_controller.mark_submit_pending(true)
				set_connection_status("Submitted. Waiting for opponent.")
				_update_hud()
			else:
				_client_controller.mark_submit_pending(false)
				set_error(payload.get("message", payload.get("code", "submit rejected")))
				_update_hud()
		MESSAGE.CANCEL_SUBMIT_TURN:
			if payload.get("accepted", false):
				_client_controller.mark_submit_pending(false)
				_submit_in_flight = false
				_update_hud()
		MESSAGE.MATCH_ERROR:
			_client_controller.mark_submit_pending(false)
			_submit_in_flight = false
			set_error(payload.get("message", payload.get("code", "unknown")))
			_update_hud()
		MESSAGE.DISCONNECT_NOTICE:
			_client_controller.mark_submit_pending(false)
			_submit_in_flight = false
			var disconnected_slot: int = payload.get("slot", -1)
			if disconnected_slot >= 0 and disconnected_slot != _player_slot:
				set_connection_status("Opponent left - you win")
			else:
				set_connection_status("Disconnected")
			_update_hud()


func _sync_ui() -> void:
	if _lobby_panel != null:
		_lobby_panel.visible = not _match_started
	if _cockpit != null:
		_cockpit.visible = _match_started and not _interface_hidden
	if _interface_toggle_button != null:
		_interface_toggle_button.visible = _match_started
		_interface_toggle_button.text = "Show UI" if _interface_hidden else "Hide UI"


func _update_hud() -> void:
	var state: MatchState = _current_state()
	var player: PlayerState = state.get_player(_player_slot) if state != null else null
	var idle_worker_ids: Array[int] = _active_idle_worker_ids()
	_refresh_idle_worker_indicators(idle_worker_ids)
	var submit_state_text: String = _submit_state_text()
	if _submit_button != null:
		var submit_active: bool = _client_controller.submit_pending() or _submit_in_flight
		_syncing_submit_button = true
		if _cockpit != null:
			_cockpit.set_turn_action_state(
				"Cancel Submit" if submit_active else "Submit Turn",
				_submit_in_flight,
				submit_active,
				true
			)
		_syncing_submit_button = false
	if _cockpit != null:
		_cockpit.set_match_state(
			_player_slot,
			state.turn_index if state != null else 0,
			player.minerals if player != null else 0,
			player.gas if player != null else 0,
			player.pop_used if player != null else 0,
			player.pop_cap if player != null else 0,
			state.match_over if state != null else false,
			state.winner_player_id if state != null else -1
		)
		_cockpit.set_show_all_orders_enabled(_show_all_orders)
		_cockpit.set_status_text(_network_cockpit_status_text(idle_worker_ids, submit_state_text))
		_cockpit.set_selection_details("", "")
		_cockpit.set_command_state(
			_input.selected_entity_label(),
			_input.can_issue_move(),
			_input.can_issue_target(),
			_input.can_issue_gather(),
			COMMAND_OPTION_BUILDER.build_options(_input, _input.build_option_ids()),
			COMMAND_OPTION_BUILDER.entity_options(_input, _input.train_option_ids()),
			COMMAND_OPTION_BUILDER.research_options(_input, _input.research_option_ids()),
			COMMAND_OPTION_BUILDER.ability_options(_input, _input.ability_option_ids()),
			_input.can_issue_unit_cancel(),
			_input.can_issue_repeat_train_toggle(),
			_input.selected_repeat_train_enabled(),
			_input.can_issue_build_cancel(),
			true
		)


func _submit_state_text() -> String:
	if _submit_in_flight:
		return "Submit: sending"
	return "Submit: pending" if _client_controller.submit_pending() else "Submit: idle"


func _network_cockpit_status_text(idle_worker_ids: Array[int], submit_state_text: String) -> String:
	var lines: Array[String] = []
	if _connection_status != "":
		lines.append(_connection_status)
	lines.append("Code: %s" % (_match_code if _match_code != "" else "-"))
	lines.append("Slot: %s" % (_player_label(_player_slot) if _player_slot >= 0 else "-"))
	lines.append(submit_state_text)
	if idle_worker_ids.size() > 0:
		lines.append("Idle workers: %d" % idle_worker_ids.size())
	return "\n".join(lines)


func _player_label(player_id: int) -> String:
	return "P%d" % (player_id + 1)


func _update_outcome_overlay(state: MatchState) -> void:
	if _outcome_overlay_panel == null:
		return
	if state == null or not state.match_over:
		_outcome_overlay_panel.visible = false
		return
	_outcome_overlay_panel.visible = true
	var title: String = "Draw"
	if state.winner_player_id >= 0:
		title = "Victory" if state.winner_player_id == _player_slot else "Defeat"
	if _outcome_title_label != null:
		_outcome_title_label.text = title
	if _outcome_detail_label != null:
		if state.winner_player_id >= 0:
			_outcome_detail_label.text = "Winner: P%d" % state.winner_player_id
		else:
			_outcome_detail_label.text = "No winner"


func _refresh_action_previews() -> void:
	var renderer: MatchRenderer = _renderer()
	if renderer == null or not renderer.has_method("set_action_previews"):
		return
	var state: MatchState = _surface.current_state() if _surface != null else null
	var previews: Array[Dictionary] = _action_preview_builder.build(
		state,
		_registry,
		_input,
		_player_slot,
		_input.selected_entity_id(),
		_show_all_orders,
		renderer,
		_input.selected_entity_ids()
	)
	renderer.call("set_action_previews", previews)


func _active_idle_worker_ids() -> Array[int]:
	var out: Array[int] = []
	var state: MatchState = _current_state()
	if state == null or _registry == null or _player_slot < 0:
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
	if entity == null or entity.current_hp <= 0 or entity.owner_player_id != _player_slot:
		return false
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	var def: EntityDef = _registry.get_by_id(def_id)
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
	if _player_slot < 0:
		return false
	var submit: SubmitTurn = _input.submit_for_player(_player_slot)
	for order: EntityOrder in submit.orders:
		if order != null and order.entity_id == entity_id:
			return true
	return false


func _refresh_idle_worker_indicators(idle_worker_ids: Array[int]) -> void:
	var renderer: MatchRenderer = _renderer()
	if renderer == null or not renderer.has_method("set_idle_worker_indicators"):
		return
	var indicators: Array[Variant] = []
	for entity_id: int in idle_worker_ids:
		indicators.append({"entity_id": entity_id})
	renderer.call("set_idle_worker_indicators", indicators)


func _unhandled_input(event: InputEvent) -> void:
	var cancel_pressed: bool = event.is_action_pressed("ui_cancel")
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		cancel_pressed = (
			cancel_pressed
			or (key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE)
		)
	if cancel_pressed:
		_reset_selection_drag()
		set_escape_menu_visible(not (_escape_menu_panel != null and _escape_menu_panel.visible))
		var viewport: Viewport = get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return
	if not _match_started or _surface == null or _surface.renderer() == null:
		return
	if _escape_menu_panel != null and _escape_menu_panel.visible:
		_reset_selection_drag()
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_A:
			begin_target()
			var viewport: Viewport = get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()
			return
	if event is InputEventMouse and not _event_inside_game_viewport(event as InputEventMouse):
		_reset_selection_drag()
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _is_panning_camera:
			_surface.renderer().pan_camera_by_screen_delta(motion.relative)
			return
		if _selection_drag.active() and motion.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
			var drag_world: Vector2 = _event_world_position(motion)
			if _selection_drag.update(motion.position, drag_world):
				_surface.renderer().set_selection_box_world_rect(
					_selection_drag.selection_world_rect()
				)
				return
		var hover_tile: Vector2i = _surface.renderer().world_to_tile(_event_world_position(motion))
		_set_hover_tile(hover_tile)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_surface.renderer().zoom_camera(CAMERA_ZOOM_STEP)
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_surface.renderer().zoom_camera(1.0 / CAMERA_ZOOM_STEP)
			return
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning_camera = button.pressed
			return
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			if _selection_drag.active():
				var release: Dictionary = _selection_drag.release(
					button.position, _event_world_position(button)
				)
				_surface.renderer().clear_selection_box()
				if release.get("dragging", false):
					_apply_box_selection(
						release.get("world_rect", Rect2()), release.get("additive", false)
					)
				else:
					var release_tile: Vector2i = _surface.renderer().world_to_tile(
						_event_world_position(button)
					)
					_apply_click_selection(release_tile, release.get("additive", false))
				return
			_reset_selection_drag()
		if not button.pressed:
			return
		var tile: Vector2i = _surface.renderer().world_to_tile(_event_world_position(button))
		if button.button_index == MOUSE_BUTTON_LEFT:
			if _pending_command != PENDING_NONE:
				confirm_pending_at_tile(tile, button.shift_pressed)
				return
			if _reject_edit_while_submit_sending():
				return
			_selection_drag.begin(
				button.position, _event_world_position(button), button.shift_pressed
			)
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			if _pending_command != PENDING_NONE:
				cancel_pending_command()
				return
			issue_context_at_tile(tile, button.shift_pressed)


func _event_world_position(event: InputEventMouse) -> Vector2:
	var renderer: MatchRenderer = _renderer()
	if renderer == null:
		return event.position
	if renderer.get_viewport() == null:
		return event.position
	if DisplayServer.get_name() == "headless":
		return event.position
	var game_position: Vector2 = _screen_to_game_viewport_position(event.position)
	if renderer.has_method("screen_to_world"):
		return renderer.call("screen_to_world", game_position)
	return renderer.get_global_mouse_position()


func _event_inside_game_viewport(event: InputEventMouse) -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	var game_rect: Rect2 = _game_viewport_screen_rect()
	return (
		game_rect.has_point(event.position)
		or _game_viewport_local_rect(game_rect).has_point(event.position)
	)


func _screen_to_game_viewport_position(screen_position: Vector2) -> Vector2:
	var game_rect: Rect2 = _game_viewport_screen_rect()
	var local_rect: Rect2 = _game_viewport_local_rect(game_rect)
	if local_rect.has_point(screen_position) and not game_rect.has_point(screen_position):
		return screen_position
	return screen_position - game_rect.position


func _game_viewport_screen_rect() -> Rect2:
	var viewport_size: Vector2 = _root_viewport_size()
	var top_hud_height: float = _top_hud_height()
	var bottom_hud_height: float = _bottom_hud_height()
	var position: Vector2 = Vector2(GAME_VIEWPORT_MARGIN_LEFT, top_hud_height)
	var size: Vector2 = Vector2(
		maxf(viewport_size.x - GAME_VIEWPORT_MARGIN_LEFT - GAME_VIEWPORT_MARGIN_RIGHT, 1.0),
		maxf(viewport_size.y - top_hud_height - bottom_hud_height, 1.0)
	)
	return Rect2(position, size)


func _game_viewport_local_rect(game_rect: Rect2) -> Rect2:
	return Rect2(Vector2.ZERO, game_rect.size)


func _reset_selection_drag() -> void:
	if _selection_drag != null:
		_selection_drag.reset()
	var renderer: MatchRenderer = _renderer()
	if renderer != null:
		renderer.clear_selection_box()
	_is_panning_camera = false


func _apply_click_selection(tile: Vector2i, additive: bool) -> void:
	if _reject_edit_while_submit_sending():
		return
	var renderer: MatchRenderer = _renderer()
	var entity_id: int = renderer.entity_id_at_tile(tile) if renderer != null else -1
	if additive:
		if entity_id >= 0 and _input.toggle_entity_selection(entity_id):
			_sync_selection_highlights()
			_clear_build_placement_preview()
			_refresh_action_previews()
			_update_hud()
		return
	if entity_id >= 0:
		select_entity_id(entity_id)
		return
	_input.clear_selection()
	if renderer != null:
		renderer.clear_input_highlights()
	_reset_context_cursor()
	_refresh_action_previews()
	_update_hud()


func _apply_box_selection(world_rect: Rect2, additive: bool) -> void:
	if _reject_edit_while_submit_sending():
		return
	var renderer: MatchRenderer = _renderer()
	if renderer == null:
		return
	var ids: Array[int] = renderer.owned_movable_entity_ids_in_world_rect(
		world_rect, _input.active_player_id()
	)
	var ok: bool = (
		_input.add_entities_to_selection(ids) if additive else _input.select_entities(ids)
	)
	if ok or not additive:
		_sync_selection_highlights()
	_clear_build_placement_preview()
	_refresh_action_previews()
	_update_hud()


func _sync_selection_highlights() -> void:
	var renderer: MatchRenderer = _renderer()
	if renderer == null:
		return
	renderer.set_selected_entity_ids(_input.selected_entity_ids())


func _renderer() -> MatchRenderer:
	if _surface == null:
		return null
	return _surface.renderer()


func _set_hover_tile(tile: Vector2i) -> void:
	var renderer: MatchRenderer = _renderer()
	if renderer == null:
		return
	renderer.set_hover_tile(tile)
	if _pending_command == PENDING_BUILD:
		_refresh_build_placement_preview(tile)
		_reset_context_cursor()
	else:
		_clear_build_placement_preview()
		_update_context_cursor_for_tile(tile)


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


func _context_result(
	action: String, cursor_shape: int, message: String, extra: Dictionary = {}
) -> Dictionary:
	var out: Dictionary = {"action": action, "cursor_shape": cursor_shape, "message": message}
	for key in extra:
		out[key] = extra[key]
	return out


func _update_context_cursor_for_tile(tile: Vector2i) -> void:
	if _pending_command != PENDING_NONE:
		_set_pending_cursor()
		return
	Input.set_default_cursor_shape(context_cursor_shape_at_tile(tile))


func _set_pending_cursor() -> void:
	Input.set_default_cursor_shape(_pending_cursor_shape())


func _pending_cursor_shape() -> int:
	if _pending_command == PENDING_TARGET:
		return Input.CURSOR_CROSS
	return Input.CURSOR_ARROW


func _reset_context_cursor() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _clear_pending_command() -> void:
	_pending_command = PENDING_NONE
	_pending_build_def_id = ""
	_clear_build_placement_preview()
	_reset_context_cursor()


func _current_state() -> MatchState:
	if _surface == null:
		return null
	return _surface.current_state()


func _selected_entity() -> Entity:
	var state: MatchState = _current_state()
	if state == null:
		return null
	var entity_id: int = _input.selected_entity_id()
	if entity_id < 0:
		return null
	return state.get_entity_by_id(entity_id)


func _entity_id_at_tile(tile: Vector2i) -> int:
	var state: MatchState = _current_state()
	if state == null or state.tile_grid == null:
		return -1
	if not state.tile_grid.is_in_bounds(tile):
		return -1
	var renderer: MatchRenderer = _renderer()
	if renderer != null:
		return renderer.entity_id_at_tile(tile)
	return state.tile_grid.entity_at(tile)


func _is_enemy_target(entity: Entity) -> bool:
	return (
		entity != null
		and entity.current_hp > 0
		and entity.owner_player_id >= 0
		and entity.owner_player_id != _input.active_player_id()
	)


func _selected_can_gather_from(target_entity_id: int) -> bool:
	if not _input.can_issue_gather():
		return false
	return _selected_can_gather_target_valid(target_entity_id)


func _selected_can_rally_gather_to(target_entity_id: int) -> bool:
	return _input.can_issue_rally_gather_to(target_entity_id)


func _selected_can_gather_target_valid(target_entity_id: int) -> bool:
	var state: MatchState = _current_state()
	if state == null or _registry == null:
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
				state, _registry, target_entity_id, actor.owner_player_id
			)
			!= null
		):
			return true
	return false


func _is_resource_context_target(entity: Entity) -> bool:
	if entity == null or _registry == null:
		return false
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	var def: EntityDef = _registry.get_by_id(def_id)
	if def == null:
		return false
	return def.resource_source != null or def.tags.has("refinery") or def.tags.has("extractor")


func _order_target_tile(target_entity_id: int) -> Vector2i:
	var state: MatchState = _current_state()
	if state == null:
		return Vector2i.ZERO
	var target: Entity = state.get_entity_by_id(target_entity_id)
	if target == null:
		return Vector2i.ZERO
	if state.tile_grid != null:
		var rect: Rect2i = state.tile_grid.entity_rect(target.id)
		if rect.size != Vector2i.ZERO:
			return rect.position
	return target.origin


func _queue_rally_move_order(entity_id: int, tile: Vector2i) -> void:
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.SET_RALLY_POINT
	order.entity_id = entity_id
	order.mode = ProductionState.RALLY_MODE_MOVE
	order.target_tile = tile
	_queue_network_standing_order(order)


func _queue_rally_gather_order(entity_id: int, target_entity_id: int) -> void:
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.SET_RALLY_POINT
	order.entity_id = entity_id
	order.mode = ProductionState.RALLY_MODE_GATHER
	order.target_entity_id = target_entity_id
	_queue_network_standing_order(order)


func _queue_repeat_train_order(
	entity_id: int, enabled: bool, preferred_def_id: String = ""
) -> void:
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.REPEAT_TRAIN_TOGGLE
	order.entity_id = entity_id
	order.enabled = enabled
	order.def_id = _repeat_train_def_id_for_entity(entity_id, preferred_def_id) if enabled else ""
	_queue_network_standing_order(order)


func _queue_network_standing_order(order: EntityOrder) -> void:
	if order == null or order.entity_id < 0 or _player_slot < 0:
		return
	var submit: SubmitTurn = _input.submit_for_player(_player_slot)
	var replace_index: int = _standing_order_index(submit.orders, order)
	if replace_index >= 0:
		submit.orders[replace_index] = order
	else:
		submit.orders.append(order)


func _standing_order_index(orders: Array[EntityOrder], order: EntityOrder) -> int:
	for i in orders.size():
		var existing: EntityOrder = orders[i]
		if existing == null or existing.entity_id != order.entity_id:
			continue
		if existing.type == order.type:
			return i
	return -1


func _repeat_train_def_id_for_entity(entity_id: int, preferred_def_id: String = "") -> String:
	if preferred_def_id != "":
		return preferred_def_id
	var submit: SubmitTurn = _input.submit_for_player(_player_slot) if _player_slot >= 0 else null
	if submit != null:
		for i in range(submit.orders.size() - 1, -1, -1):
			var order: EntityOrder = submit.orders[i]
			if (
				order != null
				and order.entity_id == entity_id
				and order.type == EntityOrder.Type.TRAIN
				and order.def_id != ""
			):
				return order.def_id
	var state: MatchState = _current_state()
	var entity: Entity = state.get_entity_by_id(entity_id) if state != null else null
	if (
		entity != null
		and entity.production_state != null
		and entity.production_state.repeat_train_def_id != ""
	):
		return entity.production_state.repeat_train_def_id
	if entity_id == _input.selected_entity_id():
		var train_ids: Array[String] = _input.train_option_ids()
		if not train_ids.is_empty():
			return train_ids[0]
	return ""


func _typed_events(events: Array) -> Array[ResolverEvent]:
	var out: Array[ResolverEvent] = []
	for item in events:
		var event: ResolverEvent = item as ResolverEvent
		if event != null:
			out.append(event)
	return out


func _submit_summary(submit: SubmitTurn) -> String:
	if submit == null:
		return "slot=%d turn=-1 orders=0 []" % _player_slot
	var state: MatchState = _current_state()
	var turn_index: int = state.turn_index if state != null else -1
	var parts: Array[String] = []
	for order: EntityOrder in submit.orders:
		if order == null:
			parts.append("null")
			continue
		parts.append("%s#%d" % [_order_type_label(order.type), order.entity_id])
	return (
		"slot=%d turn=%d orders=%d [%s]"
		% [_player_slot, turn_index, submit.orders.size(), ", ".join(parts)]
	)


func _order_type_label(order_type: int) -> String:
	match order_type:
		EntityOrder.Type.MOVE:
			return "MOVE"
		EntityOrder.Type.ATTACK_MOVE:
			return "ATTACK_MOVE"
		EntityOrder.Type.TARGET:
			return "TARGET"
		EntityOrder.Type.BUILD:
			return "BUILD"
		EntityOrder.Type.TRAIN:
			return "TRAIN"
		EntityOrder.Type.RESEARCH:
			return "RESEARCH"
		EntityOrder.Type.CANCEL:
			return "CANCEL"
		EntityOrder.Type.GATHER:
			return "GATHER"
		EntityOrder.Type.USE_ABILITY:
			return "USE_ABILITY"
		EntityOrder.Type.SET_RALLY_POINT:
			return "SET_RALLY_POINT"
		EntityOrder.Type.REPEAT_TRAIN_TOGGLE:
			return "REPEAT_TRAIN_TOGGLE"
		_:
			return "INVALID"


func _move_button_pressed() -> void:
	set_connection_status("Right-click a tile for Move.")


func _submit_turn_button_pressed() -> void:
	if _syncing_submit_button:
		return
	var submit_active: bool = _client_controller.submit_pending() or _submit_in_flight
	var ok: bool = cancel_submitted_turn() if submit_active else submit_queued_turn()
	if not ok and _submit_button != null:
		_syncing_submit_button = true
		_submit_button.set_pressed_no_signal(
			_client_controller.submit_pending() or _submit_in_flight
		)
		_syncing_submit_button = false


func _interface_toggle_pressed() -> void:
	set_interface_hidden(not _interface_hidden)


func _auto_connect_default_server() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene != self:
		return
	if _client != null:
		return
	_connect_pressed()


func _remembered_server_url() -> String:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(_server_url_config_path)
	if err != OK:
		return _default_server_url()
	var raw: Variant = config.get_value(
		SERVER_URL_CONFIG_SECTION, SERVER_URL_CONFIG_KEY, _default_server_url()
	)
	var url: String = str(raw).strip_edges()
	return url if url != "" else _default_server_url()


func _default_server_url() -> String:
	var server_defaults: NetworkMatchServer = SERVER_SCRIPT.new()
	var default_port: int = server_defaults.port
	server_defaults.free()
	return "ws://127.0.0.1:%d" % default_port


func _button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(120.0, 34.0)
	return button


func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
