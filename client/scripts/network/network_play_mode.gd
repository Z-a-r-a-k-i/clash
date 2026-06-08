class_name NetworkPlayMode
extends Node

const MESSAGE := preload("res://scripts/network/network_message.gd")
const SURFACE_SCRIPT := preload("res://scripts/network/match_play_surface.gd")
const COMMAND_CARD_SCRIPT := preload("res://scripts/game/command_card.gd")
const COMMAND_OPTION_BUILDER := preload("res://scripts/game/command_option_builder.gd")
const SERVER_SCRIPT := preload("res://scripts/network/network_match_server.gd")
const ACTION_PREVIEW_BUILDER_SCRIPT := preload("res://scripts/game/action_preview_builder.gd")

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
const PENDING_MOVE_ONLY := "move_only"
const PENDING_TARGET := "target"
const PENDING_BUILD := "build"
const PENDING_GATHER := "gather"
const CONTEXT_NONE := "none"
const CONTEXT_MOVE_ONLY := "move_only"
const CONTEXT_TARGET_CHASE := "target_chase"
const CONTEXT_GATHER := "gather"
const CONTEXT_RALLY_MOVE := "rally_move"
const CONTEXT_RALLY_GATHER := "rally_gather"
const CONTEXT_INVALID := "invalid"

var _surface: MatchPlaySurface = null
var _client_controller: NetworkClientController = NetworkClientController.new()
var _client: NetworkClient = null
var _input: DevTurnInput = DevTurnInput.new()
var _action_preview_builder: ActionPreviewBuilder = (
	ACTION_PREVIEW_BUILDER_SCRIPT.new() as ActionPreviewBuilder
)
var _hud_layer: CanvasLayer = null
var _lobby_panel: PanelContainer = null
var _match_hud_panel: PanelContainer = null
var _escape_menu_panel: PanelContainer = null
var _outcome_overlay_panel: PanelContainer = null
var _outcome_title_label: Label = null
var _outcome_detail_label: Label = null
var _lobby_status_label: Label = null
var _match_status_label: Label = null
var _code_label: Label = null
var _slot_label: Label = null
var _resources_label: Label = null
var _submit_label: Label = null
var _submit_button: Button = null
var _show_all_orders_button: BaseButton = null
var _interface_toggle_button: Button = null
var _url_edit: LineEdit = null
var _code_edit: LineEdit = null
var _command_card: Control = null
var _player_slot: int = -1
var _registry: EntityRegistry = null
var _match_code: String = ""
var _match_started: bool = false
var _show_all_orders: bool = false
var _interface_hidden: bool = false
var _is_panning_camera: bool = false
var _left_empty_drag_candidate: bool = false
var _left_empty_drag_moved: bool = false
var _left_empty_drag_start: Vector2 = Vector2.ZERO
var _syncing_submit_button: bool = false
var _server_url_config_path: String = DEFAULT_SERVER_URL_CONFIG_PATH
var _pending_command: String = PENDING_NONE
var _pending_build_def_id: String = ""


func _ready() -> void:
	ensure_initialized()
	call_deferred("_auto_connect_default_server")


func ensure_initialized() -> void:
	_build_surface()
	_build_hud()
	_sync_ui()


func bind_authoritative_snapshot(
	state: MatchState, registry: EntityRegistry, player_slot: int
) -> void:
	_build_surface()
	_registry = registry
	_player_slot = player_slot
	_match_started = true
	_input.set_active_player_id(player_slot)
	_input.bind_context(state, registry)
	_input.clear_submissions()
	_clear_pending_command()
	_client_controller.bind_authoritative_state(state, registry, player_slot)
	if _surface != null:
		_surface.bind_authoritative_state(state, registry, player_slot)
	_update_outcome_overlay(state)
	_refresh_action_previews()
	_sync_ui()
	_update_hud()


func apply_authoritative_result(new_state: MatchState, events: Array) -> void:
	_client_controller.mark_submit_pending(false)
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
	if _show_all_orders_button != null:
		_show_all_orders_button.set_pressed_no_signal(show_all)
	_refresh_action_previews()


func set_interface_hidden(hidden: bool) -> void:
	_interface_hidden = hidden
	_sync_ui()


func select_entity_id(entity_id: int) -> bool:
	var ok: bool = _input.select_entity(entity_id)
	var renderer: MatchRenderer = _renderer()
	if renderer != null:
		_clear_build_placement_preview()
		if ok:
			renderer.set_selected_entity_id(entity_id)
		else:
			renderer.clear_input_highlights()
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_move_selected(tile: Vector2i, queue_requested: bool = false) -> bool:
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_move(tile)
	_input.set_queue_modifier_active(false)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_move_only_selected(tile: Vector2i, queue_requested: bool = false) -> bool:
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_move_only(tile)
	_input.set_queue_modifier_active(false)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_target_chase_selected(target_entity_id: int, queue_requested: bool = false) -> bool:
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_target_chase(target_entity_id)
	_input.set_queue_modifier_active(false)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_attack_selected(target_entity_id: int, queue_requested: bool = false) -> bool:
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_attack(target_entity_id)
	_input.set_queue_modifier_active(false)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_attack_target_selected(target_entity_id: int) -> bool:
	var selected_id: int = _input.selected_entity_id()
	var ok: bool = _input.issue_attack_target(target_entity_id)
	if ok:
		_queue_attack_target_order(selected_id, target_entity_id)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_gather_selected(target_entity_id: int, queue_requested: bool = false) -> bool:
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_gather(target_entity_id)
	_input.set_queue_modifier_active(false)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_rally_move_selected(tile: Vector2i) -> bool:
	var selected_id: int = _input.selected_entity_id()
	var ok: bool = _input.issue_rally_move(tile)
	if ok:
		_queue_rally_move_order(selected_id, tile)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_rally_gather_selected(target_entity_id: int) -> bool:
	var selected_id: int = _input.selected_entity_id()
	var ok: bool = _input.issue_rally_gather(target_entity_id)
	if ok:
		_queue_rally_gather_order(selected_id, target_entity_id)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_build_selected(def_id: String, tile: Vector2i, queue_requested: bool = false) -> bool:
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_build(def_id, tile)
	_input.set_queue_modifier_active(false)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_halt_on_sight_selected(enabled: bool) -> bool:
	var selected_id: int = _input.selected_entity_id()
	var ok: bool = _input.issue_halt_on_sight_toggle(enabled)
	if ok:
		_queue_halt_on_sight_order(selected_id, enabled)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_cancel_selected(cancel_index: int = -1) -> bool:
	var ok: bool = _input.issue_cancel(cancel_index)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_train_selected(def_id: String) -> bool:
	var selected_id: int = _input.selected_entity_id()
	var repeat_enabled: bool = _input.selected_repeat_train_enabled()
	var ok: bool = _input.issue_train(def_id)
	if ok and repeat_enabled:
		_queue_repeat_train_order(selected_id, true, def_id)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_research_selected(def_id: String) -> bool:
	var ok: bool = _input.issue_research(def_id)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_ability_selected(ability_id: String) -> bool:
	var ok: bool = _input.issue_ability(ability_id)
	_refresh_action_previews()
	_update_hud()
	return ok


func issue_repeat_train_selected(enabled: bool) -> bool:
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
	if action == CONTEXT_MOVE_ONLY:
		return issue_move_only_selected(tile, queue_requested)
	if action == CONTEXT_TARGET_CHASE:
		return issue_target_chase_selected(context.get("target_entity_id", -1), queue_requested)
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
			if _input.can_issue_target_chase():
				return _context_result(
					CONTEXT_TARGET_CHASE, Input.CURSOR_CROSS, "", {"target_entity_id": target_id}
				)
			return _context_result(
				CONTEXT_INVALID, Input.CURSOR_FORBIDDEN, "Selected entity cannot chase targets."
			)
		if _is_resource_context_target(target):
			if _selected_can_gather_from(target_id):
				return _context_result(
					CONTEXT_GATHER, Input.CURSOR_POINTING_HAND, "", {"target_entity_id": target_id}
				)
			if _selected_can_rally_gather_to(target_id):
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
	if _input.can_issue_rally_move():
		return _context_result(CONTEXT_RALLY_MOVE, Input.CURSOR_MOVE, "")
	if _input.can_issue_move_only():
		return _context_result(CONTEXT_MOVE_ONLY, Input.CURSOR_MOVE, "")
	return _context_result(CONTEXT_INVALID, Input.CURSOR_FORBIDDEN, "Selected entity cannot move.")


func context_cursor_shape_at_tile(tile: Vector2i) -> int:
	var context: Dictionary = context_action_at_tile(tile)
	return context.get("cursor_shape", Input.CURSOR_ARROW)


func begin_move() -> void:
	if not _input.can_issue_move():
		set_connection_status("Select a movable unit before Attack and Move.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_MOVE
	_pending_build_def_id = ""
	_set_pending_cursor()
	set_connection_status("Click a target tile for Attack and Move.")


func begin_move_only() -> void:
	if not _input.can_issue_move_only():
		set_connection_status("Select a movable unit before MOVE ONLY.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_MOVE_ONLY
	_pending_build_def_id = ""
	_reset_context_cursor()
	set_connection_status("Click a target tile for MOVE ONLY. Unit will not shoot this turn.")


func begin_target() -> void:
	if not _input.can_issue_attack_target():
		set_connection_status("Select a combat unit before TARGET.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_TARGET
	_pending_build_def_id = ""
	_reset_context_cursor()
	set_connection_status("Click an enemy for TARGET.")


func begin_build(def_id: String) -> void:
	_clear_build_placement_preview()
	if not _input.build_option_ids().has(def_id):
		set_connection_status("Selected entity cannot BUILD %s." % def_id)
		return
	_pending_command = PENDING_BUILD
	_pending_build_def_id = def_id
	_reset_context_cursor()
	set_connection_status("Click a placement tile for BUILD %s." % def_id)


func begin_gather() -> void:
	if not _input.can_issue_gather():
		set_connection_status("Select a worker before GATHER.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_GATHER
	_pending_build_def_id = ""
	_reset_context_cursor()
	set_connection_status("Click a mineral patch or refinery to GATHER.")


func confirm_pending_at_tile(tile: Vector2i, queue_requested: bool = false) -> bool:
	if _pending_command == PENDING_MOVE:
		var attack_target_id: int = _entity_id_at_tile(tile)
		var state: MatchState = _current_state()
		var attack_target: Entity = (
			state.get_entity_by_id(attack_target_id) if state != null else null
		)
		if _is_enemy_target(attack_target):
			var attack_ok: bool = issue_attack_selected(attack_target_id, queue_requested)
			if attack_ok:
				_clear_pending_command()
			return attack_ok
		var move_ok: bool = issue_move_selected(tile, queue_requested)
		if move_ok:
			_clear_pending_command()
		return move_ok
	if _pending_command == PENDING_MOVE_ONLY:
		var move_only_ok: bool = issue_move_only_selected(tile, queue_requested)
		if move_only_ok:
			_clear_pending_command()
		return move_only_ok
	if _pending_command == PENDING_TARGET:
		var target_id: int = _entity_id_at_tile(tile)
		var state: MatchState = _current_state()
		var target: Entity = state.get_entity_by_id(target_id) if state != null else null
		if (
			target == null
			or target.owner_player_id < 0
			or target.owner_player_id == _input.active_player_id()
		):
			set_connection_status("Click an enemy to set TARGET.")
			return false
		var target_ok: bool = issue_attack_target_selected(target_id)
		if target_ok:
			_clear_pending_command()
		return target_ok
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
	if _pending_command == PENDING_NONE:
		return
	_clear_pending_command()
	set_connection_status("Pending command cancelled.")


func pending_command_kind() -> String:
	return _pending_command


func pending_cursor_shape() -> int:
	return _pending_cursor_shape()


func submit_queued_turn() -> bool:
	var submit: SubmitTurn = _client_controller.submit_from_input(_input)
	if submit == null:
		set_error(_client_controller.validation_error())
		_update_hud()
		return false
	if _client == null:
		_client_controller.mark_submit_pending(false)
		set_error("not connected")
		_update_hud()
		return false
	var err: Error = _client.submit_turn(submit)
	if err != OK:
		_client_controller.mark_submit_pending(false)
		set_error("submit failed %d" % err)
		_update_hud()
		return false
	if _submit_label != null:
		_submit_label.text = "Submit: pending"
	return true


func cancel_submitted_turn() -> bool:
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
	_update_hud()
	return true


func set_connection_status(status: String) -> void:
	if _lobby_status_label != null:
		_lobby_status_label.text = status
	if _match_status_label != null:
		_match_status_label.text = status


func set_invite_code(code: String) -> void:
	var normalized: String = code.strip_edges().to_upper()
	if normalized != "":
		_match_code = normalized
	if _code_label != null:
		_code_label.text = "Code: %s" % (_match_code if _match_code != "" else "-")
	if _code_edit != null and _match_code != "":
		_code_edit.text = _match_code


func set_error(message: String) -> void:
	set_connection_status("Error: %s" % message)


func set_escape_menu_visible(visible: bool) -> void:
	if _escape_menu_panel != null:
		_escape_menu_panel.visible = visible


func _build_surface() -> void:
	if _surface != null:
		return
	_surface = SURFACE_SCRIPT.new() as MatchPlaySurface
	_surface.name = "MatchPlaySurface"
	add_child(_surface)


func _build_hud() -> void:
	if _hud_layer != null:
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "NetworkHUD"
	add_child(_hud_layer)
	_build_lobby_panel()
	_build_match_hud_panel()
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


func _build_match_hud_panel() -> void:
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
	_match_hud_panel = PanelContainer.new()
	_match_hud_panel.name = "MatchHUD"
	_match_hud_panel.anchor_left = 1.0
	_match_hud_panel.anchor_right = 1.0
	_match_hud_panel.offset_left = -HUD_WIDTH - HUD_MARGIN
	_match_hud_panel.offset_right = -HUD_MARGIN
	_match_hud_panel.offset_top = HUD_MARGIN
	_match_hud_panel.offset_bottom = 520.0
	_hud_layer.add_child(_match_hud_panel)
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 8)
	_match_hud_panel.add_child(root)
	_submit_button = _button("Submit Turn")
	_submit_button.name = "SubmitTurn"
	_submit_button.toggle_mode = true
	_submit_button.custom_minimum_size = Vector2(HUD_WIDTH - HUD_MARGIN * 2.0, 44.0)
	_submit_button.toggled.connect(_submit_toggle_changed)
	root.add_child(_submit_button)
	_match_status_label = _label("Waiting")
	_match_status_label.name = "MatchStatus"
	root.add_child(_match_status_label)
	_code_label = _label("Code: -")
	_code_label.name = "InviteCode"
	root.add_child(_code_label)
	_slot_label = _label("Slot: -")
	_slot_label.name = "PlayerSlot"
	root.add_child(_slot_label)
	_resources_label = _label("Minerals: -  Gas: -  Pop: -/-")
	_resources_label.name = "Resources"
	root.add_child(_resources_label)
	_submit_label = _label("Submit: idle")
	_submit_label.name = "SubmitState"
	root.add_child(_submit_label)
	_show_all_orders_button = CheckButton.new()
	_show_all_orders_button.name = "ShowAllOrders"
	_show_all_orders_button.text = "Show All Orders"
	_show_all_orders_button.toggle_mode = true
	_show_all_orders_button.toggled.connect(set_show_all_orders)
	root.add_child(_show_all_orders_button)
	_command_card = COMMAND_CARD_SCRIPT.new() as Control
	_command_card.name = "CommandCard"
	_command_card.connect("move_requested", Callable(self, "begin_move"))
	_command_card.connect("move_only_requested", Callable(self, "begin_move_only"))
	_command_card.connect("target_requested", Callable(self, "begin_target"))
	_command_card.connect("halt_on_sight_requested", Callable(self, "issue_halt_on_sight_selected"))
	_command_card.connect("gather_requested", Callable(self, "begin_gather"))
	_command_card.connect("build_requested", Callable(self, "begin_build"))
	_command_card.connect("cancel_requested", Callable(self, "issue_cancel_selected"))
	_command_card.connect("train_requested", Callable(self, "issue_train_selected"))
	_command_card.connect("research_requested", Callable(self, "issue_research_selected"))
	_command_card.connect("ability_requested", Callable(self, "issue_ability_selected"))
	_command_card.connect("repeat_train_toggled", Callable(self, "issue_repeat_train_selected"))
	root.add_child(_command_card)


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
		_client.disconnected.connect(func() -> void: set_connection_status("Disconnected"))
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
	_player_slot = -1
	_registry = null
	_match_code = ""
	_match_started = false
	_show_all_orders = false
	_interface_hidden = false
	_client_controller.mark_submit_pending(false)
	_input.clear_submissions()
	_clear_pending_command()
	_reset_left_empty_drag()
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
			if payload.get("accepted", false):
				_client_controller.mark_submit_pending(true)
				_update_hud()
		MESSAGE.CANCEL_SUBMIT_TURN:
			if payload.get("accepted", false):
				_client_controller.mark_submit_pending(false)
				_update_hud()
		MESSAGE.MATCH_ERROR:
			set_error(payload.get("message", payload.get("code", "unknown")))
			_update_hud()
		MESSAGE.DISCONNECT_NOTICE:
			var disconnected_slot: int = payload.get("slot", -1)
			if disconnected_slot >= 0 and disconnected_slot != _player_slot:
				set_connection_status("Opponent left - you win")
			else:
				set_connection_status("Disconnected")


func _sync_ui() -> void:
	if _lobby_panel != null:
		_lobby_panel.visible = not _match_started
	if _match_hud_panel != null:
		_match_hud_panel.visible = _match_started and not _interface_hidden
	if _interface_toggle_button != null:
		_interface_toggle_button.visible = _match_started
		_interface_toggle_button.text = "Show UI" if _interface_hidden else "Hide UI"


func _update_hud() -> void:
	if _slot_label != null:
		_slot_label.text = "Slot: %s" % (str(_player_slot) if _player_slot >= 0 else "-")
	if _resources_label != null:
		var state: MatchState = _current_state()
		var player: PlayerState = state.get_player(_player_slot) if state != null else null
		if player == null:
			_resources_label.text = "Minerals: -  Gas: -  Pop: -/-"
		else:
			_resources_label.text = (
				"Minerals: %d  Gas: %d  Pop: %d/%d"
				% [player.minerals, player.gas, player.pop_used, player.pop_cap]
			)
	if _submit_label != null:
		_submit_label.text = (
			"Submit: pending" if _client_controller.submit_pending() else "Submit: idle"
		)
	if _submit_button != null:
		_syncing_submit_button = true
		_submit_button.set_pressed_no_signal(_client_controller.submit_pending())
		_submit_button.text = (
			"Cancel Submit" if _client_controller.submit_pending() else "Submit Turn"
		)
		_syncing_submit_button = false
	if _show_all_orders_button != null:
		_show_all_orders_button.set_pressed_no_signal(_show_all_orders)
	if _command_card != null:
		_command_card.call(
			"set_command_state",
			_input.selected_entity_label(),
			_input.can_issue_move(),
			_input.can_issue_move_only(),
			_input.can_issue_attack_target(),
			_input.can_issue_halt_on_sight_toggle(),
			_input.can_issue_gather(),
			_input.selected_halt_on_sight(),
			COMMAND_OPTION_BUILDER.build_options(_input, _input.build_option_ids()),
			COMMAND_OPTION_BUILDER.entity_options(_input, _input.train_option_ids()),
			COMMAND_OPTION_BUILDER.research_options(_input, _input.research_option_ids()),
			COMMAND_OPTION_BUILDER.ability_options(_input, _input.ability_option_ids()),
			_input.can_issue_cancel(),
			_input.can_issue_repeat_train_toggle(),
			_input.selected_repeat_train_enabled()
		)


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
		renderer
	)
	renderer.call("set_action_previews", previews)


func _unhandled_input(event: InputEvent) -> void:
	var cancel_pressed: bool = event.is_action_pressed("ui_cancel")
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		cancel_pressed = (
			cancel_pressed
			or (key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE)
		)
	if cancel_pressed:
		set_escape_menu_visible(not (_escape_menu_panel != null and _escape_menu_panel.visible))
		var viewport: Viewport = get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return
	if not _match_started or _surface == null or _surface.renderer() == null:
		return
	if _escape_menu_panel != null and _escape_menu_panel.visible:
		_reset_left_empty_drag()
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_A:
			begin_move()
			var viewport: Viewport = get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if (
			_left_empty_drag_candidate
			and (
				_left_empty_drag_moved
				or (
					motion.button_mask & MOUSE_BUTTON_MASK_LEFT != 0
					and motion.position.distance_to(_left_empty_drag_start) >= CAMERA_DRAG_THRESHOLD
				)
			)
		):
			_left_empty_drag_moved = true
			_is_panning_camera = true
		if _is_panning_camera:
			_surface.renderer().pan_camera_by_screen_delta(motion.relative)
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
			if _left_empty_drag_candidate:
				if not _left_empty_drag_moved:
					_input.clear_selection()
					_surface.renderer().clear_input_highlights()
					_refresh_action_previews()
					_update_hud()
				_reset_left_empty_drag()
				return
			_reset_left_empty_drag()
		if not button.pressed:
			return
		var tile: Vector2i = _surface.renderer().world_to_tile(_event_world_position(button))
		var entity_id: int = _surface.renderer().entity_id_at_tile(tile)
		if button.button_index == MOUSE_BUTTON_LEFT:
			if _pending_command != PENDING_NONE:
				confirm_pending_at_tile(tile, button.shift_pressed)
				return
			if entity_id >= 0:
				select_entity_id(entity_id)
			else:
				_left_empty_drag_candidate = true
				_left_empty_drag_moved = false
				_left_empty_drag_start = button.position
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			if _pending_command != PENDING_NONE:
				cancel_pending_command()
				return
			issue_context_at_tile(tile, button.shift_pressed)


func _event_world_position(event: InputEventMouse) -> Vector2:
	var renderer: MatchRenderer = _renderer()
	if renderer == null or renderer.get_viewport() == null:
		return event.position
	if DisplayServer.get_name() == "headless":
		return event.position
	return renderer.get_global_mouse_position()


func _reset_left_empty_drag() -> void:
	_left_empty_drag_candidate = false
	_left_empty_drag_moved = false
	_left_empty_drag_start = Vector2.ZERO
	_is_panning_camera = false


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
	if _pending_command == PENDING_MOVE:
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
	if not _input.can_issue_rally_gather():
		return false
	return _selected_can_gather_target_valid(target_entity_id)


func _selected_can_gather_target_valid(target_entity_id: int) -> bool:
	var state: MatchState = _current_state()
	var actor: Entity = _selected_entity()
	if state == null or _registry == null or actor == null:
		return false
	var target: Entity = state.get_entity_by_id(target_entity_id)
	if not _is_resource_context_target(target):
		return false
	return (
		GatherSystem.resolve_source_for_worker(
			state, _registry, target_entity_id, actor.owner_player_id
		)
		!= null
	)


func _is_resource_context_target(entity: Entity) -> bool:
	if entity == null or _registry == null:
		return false
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	var def: EntityDef = _registry.get_by_id(def_id)
	if def == null:
		return false
	return def.resource_source != null or def.tags.has("refinery") or def.tags.has("extractor")


func _queue_attack_target_order(entity_id: int, target_entity_id: int) -> void:
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.ATTACK
	order.entity_id = entity_id
	order.target_priority_chain = [target_entity_id]
	order.target_tile = _order_target_tile(target_entity_id)
	_queue_network_standing_order(order)


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


func _queue_halt_on_sight_order(entity_id: int, enabled: bool) -> void:
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.HALT_ON_SIGHT_TOGGLE
	order.entity_id = entity_id
	order.halt_on_sight = enabled
	_queue_network_standing_order(order)


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
	var state: MatchState = _current_state()
	var entity: Entity = state.get_entity_by_id(entity_id) if state != null else null
	if (
		entity != null
		and entity.production_state != null
		and entity.production_state.repeat_train_def_id != ""
	):
		return entity.production_state.repeat_train_def_id
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


func _move_button_pressed() -> void:
	set_connection_status("Right-click a tile for Attack and Move.")


func _move_only_button_pressed() -> void:
	set_connection_status("Right-click a tile for Move Only.")


func _submit_toggle_changed(pressed: bool) -> void:
	if _syncing_submit_button:
		return
	var ok: bool = submit_queued_turn() if pressed else cancel_submitted_turn()
	if not ok and _submit_button != null:
		_syncing_submit_button = true
		_submit_button.set_pressed_no_signal(_client_controller.submit_pending())
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
