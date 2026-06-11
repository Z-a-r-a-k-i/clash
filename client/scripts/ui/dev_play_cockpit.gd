@tool
class_name DevPlayCockpit
extends Control

signal move_requested
signal target_requested
signal gather_requested
signal build_requested(def_id: String)
signal train_requested(def_id: String)
signal research_requested(def_id: String)
signal ability_requested(def_id: String)
signal cancel_requested(cancel_index: int)
signal repeat_train_toggled(enabled: bool)
signal resolve_requested
signal show_all_orders_toggled(enabled: bool)

const FONT_SIZE := 18
const SMALL_FONT_SIZE := 15
const BUTTON_MIN_HEIGHT := 36.0

var _active_player_label: Label = null
var _turn_label: Label = null
var _resources_label: Label = null
var _population_label: Label = null
var _queue_label: Label = null
var _match_label: Label = null
var _selection_label: Label = null
var _selection_details_label: Label = null
var _selection_intent_label: Label = null
var _status_label: Label = null
var _command_panel: Control = null
var _move_button: Button = null
var _target_button: Button = null
var _gather_button: Button = null
var _cancel_button: Button = null
var _resolve_button: Button = null
var _repeat_train_toggle: CheckBox = null
var _show_all_orders_toggle: CheckBox = null
var _action_row: HBoxContainer = null
var _state_row: HBoxContainer = null
var _build_list: VBoxContainer = null
var _train_list: VBoxContainer = null
var _research_list: VBoxContainer = null
var _ability_list: VBoxContainer = null
var _build_options: Array[Dictionary] = []
var _train_options: Array[Dictionary] = []
var _research_options: Array[Dictionary] = []
var _ability_options: Array[Dictionary] = []
var _repeat_train_enabled: bool = false
var _signals_wired: bool = false


func _ready() -> void:
	_resolve_nodes()
	_wire_signals()
	_apply_theme()


func set_match_state(
	active_player_id: int,
	turn_index: int,
	minerals: int,
	gas: int,
	pop_used: int,
	pop_cap: int,
	queued_orders: int,
	match_over: bool,
	winner_player_id: int
) -> void:
	_resolve_nodes()
	_active_player_label.text = "P%d" % active_player_id
	_turn_label.text = "Turn %d" % turn_index
	_resources_label.text = "Minerals %d   Gas %d" % [minerals, gas]
	_population_label.text = "Pop %d/%d" % [pop_used, pop_cap]
	_queue_label.text = "Queued %d" % queued_orders
	if match_over:
		_match_label.text = (
			"Winner P%d" % winner_player_id if winner_player_id >= 0 else "Match over"
		)
	else:
		_match_label.text = "Planning"


func set_status_text(text: String) -> void:
	_resolve_nodes()
	_status_label.text = text


func set_selection_details(details_text: String, intent_text: String) -> void:
	_resolve_nodes()
	_selection_details_label.text = details_text
	_selection_details_label.visible = details_text != ""
	_selection_intent_label.text = intent_text
	_selection_intent_label.visible = intent_text != ""


func set_show_all_orders_enabled(enabled: bool) -> void:
	_resolve_nodes()
	_show_all_orders_toggle.set_pressed_no_signal(enabled)


func command_surface_visible() -> bool:
	_resolve_nodes()
	return _command_panel.visible


func set_command_state(
	selection_text: String,
	can_move: bool,
	can_target: bool,
	can_gather: bool,
	build_options: Array[Dictionary],
	train_options: Array[Dictionary],
	research_options: Array[Dictionary],
	ability_options: Array[Dictionary],
	can_cancel: bool,
	can_repeat_train: bool = false,
	repeat_train_enabled: bool = false
) -> void:
	_resolve_nodes()
	_repeat_train_enabled = repeat_train_enabled
	_build_options = _copy_options(build_options)
	_train_options = _copy_options(train_options)
	_research_options = _copy_options(research_options)
	_ability_options = _copy_options(ability_options)
	_selection_label.text = selection_text
	_move_button.visible = can_move
	_move_button.disabled = false
	_target_button.visible = can_target
	_target_button.disabled = false
	_gather_button.visible = can_gather
	_gather_button.disabled = false
	_cancel_button.visible = can_cancel
	_cancel_button.disabled = false
	_repeat_train_toggle.visible = can_repeat_train
	_repeat_train_toggle.set_pressed_no_signal(repeat_train_enabled)
	_rebuild_option_buttons(_build_list, _build_options, build_requested)
	_rebuild_option_buttons(_train_list, _train_options, train_requested)
	_rebuild_option_buttons(_research_list, _research_options, research_requested)
	_rebuild_option_buttons(_ability_list, _ability_options, ability_requested)
	_action_row.visible = can_move or can_gather
	_state_row.visible = can_target or can_cancel or can_repeat_train
	_command_panel.visible = (
		_action_row.visible
		or _state_row.visible
		or not _build_options.is_empty()
		or not _train_options.is_empty()
		or not _research_options.is_empty()
		or not _ability_options.is_empty()
	)


func build_option_ids() -> Array[String]:
	return _option_ids(_build_options)


func train_option_ids() -> Array[String]:
	return _option_ids(_train_options)


func research_option_ids() -> Array[String]:
	return _option_ids(_research_options)


func ability_option_ids() -> Array[String]:
	return _option_ids(_ability_options)


func _resolve_nodes() -> void:
	if _active_player_label != null:
		return
	_active_player_label = get_node("TopBar/Row/ActivePlayer") as Label
	_turn_label = get_node("TopBar/Row/Turn") as Label
	_resources_label = get_node("TopBar/Row/Resources") as Label
	_population_label = get_node("TopBar/Row/Population") as Label
	_queue_label = get_node("TopBar/Row/Queue") as Label
	_match_label = get_node("TopBar/Row/MatchState") as Label
	_selection_label = get_node("BottomDeck/Row/SelectionPanel/Selection") as Label
	_selection_details_label = get_node("BottomDeck/Row/SelectionPanel/Details") as Label
	_selection_intent_label = get_node("BottomDeck/Row/SelectionPanel/Intent") as Label
	_status_label = get_node("BottomDeck/Row/SelectionPanel/Status") as Label
	_command_panel = get_node("BottomDeck/Row/CommandPanel") as Control
	_move_button = get_node("BottomDeck/Row/CommandPanel/ActionRow/Move") as Button
	_gather_button = get_node("BottomDeck/Row/CommandPanel/ActionRow/Gather") as Button
	_target_button = get_node("BottomDeck/Row/CommandPanel/StateRow/Attack") as Button
	_cancel_button = get_node("BottomDeck/Row/CommandPanel/StateRow/Cancel") as Button
	_repeat_train_toggle = (
		get_node("BottomDeck/Row/CommandPanel/StateRow/RepeatTrain") as CheckBox
	)
	_build_list = get_node("BottomDeck/Row/CommandPanel/OptionColumns/Build") as VBoxContainer
	_train_list = get_node("BottomDeck/Row/CommandPanel/OptionColumns/Train") as VBoxContainer
	_research_list = (
		get_node("BottomDeck/Row/CommandPanel/OptionColumns/Research") as VBoxContainer
	)
	_ability_list = (
		get_node("BottomDeck/Row/CommandPanel/OptionColumns/Abilities") as VBoxContainer
	)
	_action_row = get_node("BottomDeck/Row/CommandPanel/ActionRow") as HBoxContainer
	_state_row = get_node("BottomDeck/Row/CommandPanel/StateRow") as HBoxContainer
	_resolve_button = get_node("BottomDeck/Row/ResolvePanel/Resolve") as Button
	_show_all_orders_toggle = (get_node("BottomDeck/Row/ResolvePanel/ShowAllOrders") as CheckBox)
	_wire_signals()


func _wire_signals() -> void:
	if _signals_wired:
		return
	_signals_wired = true
	_move_button.pressed.connect(func() -> void: move_requested.emit())
	_target_button.pressed.connect(func() -> void: target_requested.emit())
	_gather_button.pressed.connect(func() -> void: gather_requested.emit())
	_cancel_button.pressed.connect(func() -> void: cancel_requested.emit(-1))
	_resolve_button.pressed.connect(func() -> void: resolve_requested.emit())
	_repeat_train_toggle.toggled.connect(
		func(enabled: bool) -> void: repeat_train_toggled.emit(enabled)
	)
	_show_all_orders_toggle.toggled.connect(
		func(enabled: bool) -> void: show_all_orders_toggled.emit(enabled)
	)


func _apply_theme() -> void:
	for label in find_children("*", "Label", true, false):
		var typed_label: Label = label as Label
		if typed_label != null:
			typed_label.add_theme_font_size_override("font_size", FONT_SIZE)
	for button in find_children("*", "Button", true, false):
		var typed_button: Button = button as Button
		if typed_button != null:
			typed_button.custom_minimum_size = Vector2(0.0, BUTTON_MIN_HEIGHT)
			typed_button.add_theme_font_size_override("font_size", FONT_SIZE)
	for toggle in find_children("*", "CheckBox", true, false):
		var typed_toggle: CheckBox = toggle as CheckBox
		if typed_toggle != null:
			typed_toggle.custom_minimum_size = Vector2(0.0, BUTTON_MIN_HEIGHT)
			typed_toggle.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_status_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_selection_details_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_selection_intent_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)


func _rebuild_option_buttons(
	container: VBoxContainer, options: Array[Dictionary], signal_to_emit: Signal
) -> void:
	if container == null:
		return
	while container.get_child_count() > 1:
		var child: Node = container.get_child(1)
		container.remove_child(child)
		child.queue_free()
	if options.is_empty():
		container.visible = false
		return
	container.visible = true
	for option in options:
		_add_option_button(container, option, signal_to_emit)


func _add_option_button(
	container: VBoxContainer, option: Dictionary, signal_to_emit: Signal
) -> void:
	var def_id: String = option.get("id", "")
	if def_id == "":
		return
	var label: String = option.get("label", def_id)
	var button: Button = Button.new()
	button.text = label
	button.disabled = option.get("disabled", false)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0.0, BUTTON_MIN_HEIGHT)
	button.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	button.pressed.connect(func() -> void: signal_to_emit.emit(def_id))
	container.add_child(button)


func _copy_options(options: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for option in options:
		out.append(option.duplicate())
	return out


func _option_ids(options: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for option in options:
		var def_id: String = option.get("id", "")
		if def_id != "":
			out.append(def_id)
	return out
