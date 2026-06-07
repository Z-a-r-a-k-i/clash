class_name NetworkPlayMode
extends Node

const MESSAGE := preload("res://scripts/network/network_message.gd")
const SURFACE_SCRIPT := preload("res://scripts/network/match_play_surface.gd")
const COMMAND_CARD_SCRIPT := preload("res://scripts/game/command_card.gd")
const SERVER_SCRIPT := preload("res://scripts/network/network_match_server.gd")

const HUD_WIDTH: float = 420.0
const HUD_MARGIN: float = 12.0

var _surface: MatchPlaySurface = null
var _client_controller: NetworkClientController = NetworkClientController.new()
var _client: NetworkClient = null
var _input: DevTurnInput = DevTurnInput.new()
var _hud_layer: CanvasLayer = null
var _status_label: Label = null
var _code_label: Label = null
var _slot_label: Label = null
var _submit_label: Label = null
var _url_edit: LineEdit = null
var _code_edit: LineEdit = null
var _command_card: Control = null
var _player_slot: int = -1
var _registry: EntityRegistry = null


func _ready() -> void:
	_build_surface()
	_build_hud()


func bind_authoritative_snapshot(
	state: MatchState, registry: EntityRegistry, player_slot: int
) -> void:
	_build_surface()
	_registry = registry
	_player_slot = player_slot
	_input.set_active_player_id(player_slot)
	_input.bind_context(state, registry)
	_input.clear_submissions()
	_client_controller.bind_authoritative_state(state, registry, player_slot)
	if _surface != null:
		_surface.bind_authoritative_state(state, registry, player_slot)
	_update_hud()


func apply_authoritative_result(new_state: MatchState, events: Array) -> void:
	if new_state == null:
		set_error("missing authoritative state")
		return
	if _registry == null:
		set_error("missing registry")
		return
	_client_controller.mark_submit_pending(false)
	_client_controller.bind_authoritative_state(new_state, _registry, _player_slot)
	_input.bind_context(new_state, _registry)
	_input.clear_submissions(false, false)
	_input.apply_resolve_events(_typed_events(events))
	_input.queue_rally_orders_for_train_completed(_typed_events(events))
	_input.queue_move_assists_for_next_turn()
	_input.promote_future_orders_for_next_turn()
	if _surface != null:
		_surface.render_authoritative_result(new_state, events)
	_update_hud()


func player_slot() -> int:
	return _player_slot


func can_submit_turn(submit: SubmitTurn) -> bool:
	return _client_controller.can_submit_turn(submit)


func input_model() -> DevTurnInput:
	return _input


func select_entity_id(entity_id: int) -> bool:
	var ok: bool = _input.select_entity(entity_id)
	if _surface != null and _surface.renderer() != null:
		if ok:
			_surface.renderer().set_selected_entity_id(entity_id)
		else:
			_surface.renderer().clear_input_highlights()
	_update_hud()
	return ok


func issue_move_selected(tile: Vector2i, queue_requested: bool = false) -> bool:
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_move(tile)
	_input.set_queue_modifier_active(false)
	_update_hud()
	return ok


func issue_move_only_selected(tile: Vector2i, queue_requested: bool = false) -> bool:
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_move_only(tile)
	_input.set_queue_modifier_active(false)
	_update_hud()
	return ok


func issue_target_chase_selected(target_entity_id: int, queue_requested: bool = false) -> bool:
	_input.set_queue_modifier_active(queue_requested)
	var ok: bool = _input.issue_target_chase(target_entity_id)
	_input.set_queue_modifier_active(false)
	_update_hud()
	return ok


func issue_halt_on_sight_selected(enabled: bool) -> bool:
	var ok: bool = _input.issue_halt_on_sight_toggle(enabled)
	_update_hud()
	return ok


func issue_cancel_selected(cancel_index: int = -1) -> bool:
	var ok: bool = _input.issue_cancel(cancel_index)
	_update_hud()
	return ok


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


func set_connection_status(status: String) -> void:
	if _status_label != null:
		_status_label.text = status


func set_invite_code(code: String) -> void:
	if _code_label != null:
		_code_label.text = "Code: %s" % (code if code != "" else "-")


func set_error(message: String) -> void:
	if _status_label != null:
		_status_label.text = "Error: %s" % message


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
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -HUD_WIDTH - HUD_MARGIN
	panel.offset_right = -HUD_MARGIN
	panel.offset_top = HUD_MARGIN
	panel.offset_bottom = 300.0
	_hud_layer.add_child(panel)
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Root"
	panel.add_child(root)
	_url_edit = LineEdit.new()
	_url_edit.name = "ServerUrl"
	var default_url: String = _default_server_url()
	_url_edit.placeholder_text = default_url
	_url_edit.text = default_url
	root.add_child(_url_edit)
	var connection_row: HBoxContainer = HBoxContainer.new()
	connection_row.name = "Connection"
	root.add_child(connection_row)
	var connect_button: Button = _button("Connect")
	connect_button.pressed.connect(_connect_pressed)
	connection_row.add_child(connect_button)
	var create_button: Button = _button("Create")
	create_button.pressed.connect(_create_pressed)
	connection_row.add_child(create_button)
	_code_edit = LineEdit.new()
	_code_edit.name = "JoinCode"
	_code_edit.placeholder_text = "Code"
	_code_edit.custom_minimum_size = Vector2(100.0, 32.0)
	connection_row.add_child(_code_edit)
	var join_button: Button = _button("Join")
	join_button.pressed.connect(_join_pressed)
	connection_row.add_child(join_button)
	var submit_button: Button = _button("Submit")
	submit_button.name = "SubmitTurn"
	submit_button.pressed.connect(submit_queued_turn)
	root.add_child(submit_button)
	_status_label = _label("Status: disconnected")
	_status_label.name = "Status"
	root.add_child(_status_label)
	_code_label = _label("Code: -")
	_code_label.name = "InviteCode"
	root.add_child(_code_label)
	_slot_label = _label("Slot: -")
	_slot_label.name = "PlayerSlot"
	root.add_child(_slot_label)
	_submit_label = _label("Submit: idle")
	_submit_label.name = "SubmitState"
	root.add_child(_submit_label)
	_command_card = COMMAND_CARD_SCRIPT.new() as Control
	_command_card.name = "CommandCard"
	_command_card.connect("move_requested", Callable(self, "_move_button_pressed"))
	_command_card.connect("move_only_requested", Callable(self, "_move_only_button_pressed"))
	_command_card.connect("halt_on_sight_requested", Callable(self, "issue_halt_on_sight_selected"))
	_command_card.connect("cancel_requested", Callable(self, "issue_cancel_selected"))
	root.add_child(_command_card)
	_update_hud()


func _connect_pressed() -> void:
	if _client == null:
		_client = NetworkClient.new()
		_client.name = "NetworkClient"
		_client.connected_to_server.connect(func() -> void: set_connection_status("Connected"))
		_client.message_received.connect(_handle_network_message)
		_client.disconnected.connect(func() -> void: set_connection_status("Disconnected"))
		add_child(_client)
	var err: Error = _client.connect_to_server(_url_edit.text)
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


func _handle_network_message(message: Dictionary) -> void:
	var kind: String = MESSAGE.kind(message)
	var payload: Dictionary = MESSAGE.payload(message)
	match kind:
		MESSAGE.MATCH_JOINED:
			_player_slot = payload.get("player_slot", -1)
			set_invite_code(payload.get("code", ""))
			_update_hud()
		MESSAGE.TURN_STARTED:
			var state: MatchState = payload.get("match_state") as MatchState
			var registry: EntityRegistry = payload.get("registry") as EntityRegistry
			if registry != null:
				_registry = registry
			if state != null and _registry != null:
				bind_authoritative_snapshot(state, _registry, _player_slot)
			set_connection_status("Turn %d" % payload.get("turn_index", -1))
		MESSAGE.TURN_RESOLVED:
			apply_authoritative_result(
				payload.get("match_state") as MatchState, payload.get("events", [])
			)
		MESSAGE.MATCH_ERROR:
			set_error(payload.get("message", payload.get("code", "unknown")))
		MESSAGE.DISCONNECT_NOTICE:
			set_connection_status("Opponent disconnected")


func _update_hud() -> void:
	if _slot_label != null:
		_slot_label.text = "Slot: %s" % (str(_player_slot) if _player_slot >= 0 else "-")
	if _submit_label != null:
		_submit_label.text = (
			"Submit: pending" if _client_controller.submit_pending() else "Submit: idle"
		)
	if _command_card != null:
		var empty_options: Array[Dictionary] = []
		_command_card.call(
			"set_command_state",
			_input.selected_entity_label(),
			_input.can_issue_move(),
			_input.can_issue_move_only(),
			_input.can_issue_attack_target(),
			_input.can_issue_halt_on_sight_toggle(),
			_input.can_issue_gather(),
			false,
			empty_options,
			empty_options,
			empty_options,
			empty_options,
			_input.can_issue_cancel()
		)


func _unhandled_input(event: InputEvent) -> void:
	if _surface == null or _surface.renderer() == null:
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if not button.pressed:
			return
		var tile: Vector2i = _surface.renderer().world_to_tile(_event_world_position(button))
		var entity_id: int = _surface.renderer().entity_id_at_tile(tile)
		if button.button_index == MOUSE_BUTTON_LEFT:
			if entity_id >= 0:
				select_entity_id(entity_id)
			else:
				_input.clear_selection()
				_surface.renderer().clear_input_highlights()
				_update_hud()
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			if entity_id >= 0:
				var state: MatchState = _surface.current_state()
				var target: Entity = state.get_entity_by_id(entity_id) if state != null else null
				if (
					target != null
					and target.owner_player_id >= 0
					and target.owner_player_id != _player_slot
				):
					issue_target_chase_selected(entity_id, button.shift_pressed)
					return
			issue_move_only_selected(tile, button.shift_pressed)
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var hover_tile: Vector2i = _surface.renderer().world_to_tile(_event_world_position(motion))
		_surface.renderer().set_hover_tile(hover_tile)


func _event_world_position(event: InputEventMouse) -> Vector2:
	if _surface == null or _surface.renderer() == null:
		return event.position
	var renderer: MatchRenderer = _surface.renderer()
	if renderer.get_viewport() == null:
		return event.position
	return renderer.get_global_mouse_position()


func _typed_events(events: Array) -> Array[ResolverEvent]:
	var out: Array[ResolverEvent] = []
	for item in events:
		var event: ResolverEvent = item as ResolverEvent
		if event != null:
			out.append(event)
	return out


func _move_button_pressed() -> void:
	if _status_label != null:
		_status_label.text = "Right-click a tile for Attack and Move."


func _move_only_button_pressed() -> void:
	if _status_label != null:
		_status_label.text = "Right-click a tile for Move Only."


func _default_server_url() -> String:
	var server_defaults: NetworkMatchServer = SERVER_SCRIPT.new()
	var default_port: int = server_defaults.port
	server_defaults.free()
	return "ws://127.0.0.1:%d" % default_port


func _button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(72.0, 34.0)
	return button


func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
