class_name NetworkPlayMode
extends Node

const MESSAGE := preload("res://scripts/network/network_message.gd")
const SURFACE_SCRIPT := preload("res://scripts/network/match_play_surface.gd")
const COMMAND_OPTION_BUILDER := preload("res://scripts/game/command_option_builder.gd")
const SERVER_SCRIPT := preload("res://scripts/network/network_match_server.gd")
const SHARED_COCKPIT_SCENE := preload("res://scenes/ui/dev_play_cockpit.tscn")

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
var _client_controller: NetworkClientController = NetworkClientController.new()
var _client: NetworkClient = null
var _input: DevTurnInput = DevTurnInput.new()
var _controller: MatchSessionController = MatchSessionController.new()
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
var _syncing_submit_button: bool = false
var _submit_in_flight: bool = false
var _server_url_config_path: String = DEFAULT_SERVER_URL_CONFIG_PATH


func _init() -> void:
	_controller.setup(self, _input, CAMERA_DRAG_THRESHOLD)


func _ready() -> void:
	_controller.setup(self, _input, CAMERA_DRAG_THRESHOLD)
	var viewport: Viewport = get_viewport()
	var sync: Callable = Callable(_controller, "sync_game_viewport_rect")
	if viewport != null and not viewport.size_changed.is_connected(sync):
		viewport.size_changed.connect(sync)
	ensure_initialized()
	call_deferred("_auto_connect_default_server")


func ensure_initialized() -> void:
	_controller.setup(self, _input, CAMERA_DRAG_THRESHOLD)
	_build_surface()
	_build_hud()
	_controller.sync_game_viewport_rect()
	_sync_ui()


func bind_authoritative_snapshot(
	state: MatchState, registry: EntityRegistry, player_slot: int
) -> void:
	_controller.reset_selection_drag()
	_build_surface()
	_registry = registry
	_player_slot = player_slot
	_match_started = true
	_input.set_active_player_id(player_slot)
	_input.bind_context(state, registry)
	_input.clear_submissions()
	_controller.clear_pending_command()
	_submit_in_flight = false
	_client_controller.bind_authoritative_state(state, registry, player_slot)
	if _surface != null:
		_surface.bind_authoritative_state(state, registry, player_slot)
	_controller.sync_selection_highlights()
	_update_outcome_overlay(state)
	_controller.refresh_action_previews()
	_sync_ui()
	_update_hud()


func apply_authoritative_result(new_state: MatchState, events: Array) -> void:
	_controller.reset_selection_drag()
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
	_controller.clear_pending_command()
	_input.apply_resolve_events(_typed_events(events))
	_input.queue_rally_orders_for_train_completed(_typed_events(events))
	_input.queue_move_assists_for_next_turn()
	_input.promote_future_orders_for_next_turn()
	if _surface != null:
		_surface.render_authoritative_result(new_state, events)
	_controller.sync_selection_highlights()
	_update_outcome_overlay(new_state)
	_controller.refresh_action_previews()
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
	_controller.set_show_all_orders(show_all)
	if _cockpit != null:
		_cockpit.set_show_all_orders_enabled(show_all)
	_controller.refresh_action_previews()


func set_interface_hidden(hidden: bool) -> void:
	_interface_hidden = hidden
	_sync_ui()


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
	_controller.ensure_game_viewport()
	_surface = SURFACE_SCRIPT.new() as MatchPlaySurface
	_surface.name = "MatchPlaySurface"
	if _controller.game_viewport() != null:
		_controller.game_viewport().add_child(_surface)
	else:
		add_child(_surface)


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
	_controller.set_show_all_orders(false)
	_interface_hidden = false
	_client_controller.bind_authoritative_state(null, null, -1)
	_input.clear_submissions()
	_input.clear_selection()
	_controller.clear_pending_command()
	_submit_in_flight = false
	_controller.reset_selection_drag()
	_controller.sync_selection_highlights()
	_controller.refresh_action_previews()
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
	var idle_worker_ids: Array[int] = _controller.active_idle_worker_ids()
	_controller.refresh_idle_worker_indicators(idle_worker_ids)
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
		_cockpit.set_selection_details(_controller.selection_resource_text(), "")
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


func _renderer() -> MatchRenderer:
	if _surface == null:
		return null
	return _surface.renderer()


func _current_state() -> MatchState:
	if _surface == null:
		return null
	return _surface.current_state()


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


# ---------- MatchSessionController delegation ----------
# Public/test-visible API stays on the mode; the shared core lives in
# MatchSessionController (plan/m1/00). The session_* methods below are the
# duck-typed delegate contract the controller calls back into.


func _unhandled_input(event: InputEvent) -> void:
	_controller.handle_unhandled_input(event)


func select_entity_id(entity_id: int) -> bool:
	return _controller.select_entity_id(entity_id)


func issue_move_selected(tile: Vector2i, queue_requested: bool = false) -> bool:
	return _controller.issue_move_selected(tile, queue_requested)


func issue_attack_move_selected(tile: Vector2i, queue_requested: bool = false) -> bool:
	return _controller.issue_attack_move_selected(tile, queue_requested)


func issue_attack_selected(target_entity_id: int, queue_requested: bool = false) -> bool:
	return _controller.issue_attack_selected(target_entity_id, queue_requested)


func issue_gather_selected(target_entity_id: int, queue_requested: bool = false) -> bool:
	return _controller.issue_gather_selected(target_entity_id, queue_requested)


func issue_rally_move_selected(tile: Vector2i) -> bool:
	return _controller.issue_rally_move_selected(tile)


func issue_rally_gather_selected(target_entity_id: int) -> bool:
	return _controller.issue_rally_gather_selected(target_entity_id)


func issue_build_selected(def_id: String, tile: Vector2i, queue_requested: bool = false) -> bool:
	return _controller.issue_build_selected(def_id, tile, queue_requested)


func issue_cancel_selected(cancel_index: int = -1) -> bool:
	return _controller.issue_cancel_selected(cancel_index)


func issue_train_selected(def_id: String) -> bool:
	return _controller.issue_train_selected(def_id)


func issue_research_selected(def_id: String) -> bool:
	return _controller.issue_research_selected(def_id)


func issue_ability_selected(ability_id: String) -> bool:
	return _controller.issue_ability_selected(ability_id)


func issue_repeat_train_selected(enabled: bool) -> bool:
	return _controller.issue_repeat_train_selected(enabled)


func issue_context_at_tile(tile: Vector2i, queue_requested: bool = false) -> bool:
	return _controller.issue_context_at_tile(tile, queue_requested)


func context_action_at_tile(tile: Vector2i) -> Dictionary:
	return _controller.context_action_at_tile(tile)


func context_cursor_shape_at_tile(tile: Vector2i) -> int:
	return _controller.context_cursor_shape_at_tile(tile)


func begin_move() -> void:
	_controller.begin_move()


func begin_target() -> void:
	_controller.begin_target()


func begin_build(def_id: String) -> void:
	_controller.begin_build(def_id)


func begin_gather() -> void:
	_controller.begin_gather()


func confirm_pending_at_tile(tile: Vector2i, queue_requested: bool = false) -> bool:
	return _controller.confirm_pending_at_tile(tile, queue_requested)


func cancel_pending_command() -> void:
	_controller.cancel_pending_command()


func pending_command_kind() -> String:
	return _controller.pending_command_kind()


func pending_cursor_shape() -> int:
	return _controller.pending_cursor_shape()


func _set_hover_tile(tile: Vector2i) -> void:
	_controller.set_hover_tile(tile)


func _game_viewport_screen_rect() -> Rect2:
	return _controller.game_viewport_screen_rect()


func _screen_to_game_viewport_position(screen_position: Vector2) -> Vector2:
	return _controller.screen_to_game_viewport_position(screen_position)


func _refresh_action_previews() -> void:
	_controller.refresh_action_previews()


# ---------- session_* delegate contract ----------


func session_state() -> MatchState:
	return _current_state()


func session_registry() -> EntityRegistry:
	return _registry


func session_renderer() -> MatchRenderer:
	return _renderer()


func session_local_player_id() -> int:
	return _player_slot


func session_cockpit() -> Control:
	return _cockpit


func session_input_enabled() -> bool:
	return _match_started and _surface != null and _surface.renderer() != null


func session_is_blocking_overlay_visible() -> bool:
	return _escape_menu_panel != null and _escape_menu_panel.visible


func session_reject_edit() -> bool:
	return _reject_edit_while_submit_sending()


func session_reject_context_query() -> bool:
	return false


func session_show_status(message: String) -> void:
	set_connection_status(message)


func session_update_hud() -> void:
	_update_hud()


func session_on_escape() -> void:
	set_escape_menu_visible(not (_escape_menu_panel != null and _escape_menu_panel.visible))


func session_handle_mode_key_input(_event: InputEventKey) -> bool:
	return false


func session_on_hover_tile(_tile: Vector2i) -> void:
	pass


func session_on_pointer_exited_viewport() -> void:
	pass


# Network standing orders piggyback on order issuance: rally and repeat-train
# state must be re-sent every turn, so successful issues queue the matching
# standing order into the submit.
func session_on_order_issued(kind: String, context: Dictionary, ok: bool) -> void:
	if not ok:
		return
	match kind:
		"rally_move":
			_queue_rally_move_order(
				context.get("selected_id", -1), context.get("tile", Vector2i.ZERO)
			)
		"rally_gather":
			_queue_rally_gather_order(
				context.get("selected_id", -1), context.get("target_entity_id", -1)
			)
		"repeat_train":
			_queue_repeat_train_order(context.get("selected_id", -1), context.get("enabled", false))
		"train":
			if context.get("repeat_enabled", false):
				_queue_repeat_train_order(
					context.get("selected_id", -1), true, context.get("def_id", "")
				)
