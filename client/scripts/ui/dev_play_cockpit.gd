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

const FONT_SIZE := 16
const SMALL_FONT_SIZE := 14
const HEADER_FONT_SIZE := 12
const BUTTON_MIN_HEIGHT := 32.0
const OPTION_BUTTON_MIN_HEIGHT := 28.0

const COLOR_PANEL_BACK := Color(0.025, 0.038, 0.070, 0.96)
const COLOR_PANEL_BACK_DARK := Color(0.010, 0.018, 0.034, 0.98)
const COLOR_PANEL_BORDER := Color(0.220, 0.330, 0.430, 0.92)
const COLOR_PANEL_BORDER_HOT := Color(0.290, 0.820, 0.940, 0.70)
const COLOR_TEXT := Color(0.900, 0.940, 0.980, 1.0)
const COLOR_TEXT_MUTED := Color(0.580, 0.710, 0.840, 1.0)
const COLOR_BUTTON := Color(0.050, 0.080, 0.130, 1.0)
const COLOR_BUTTON_HOVER := Color(0.075, 0.130, 0.200, 1.0)
const COLOR_COMMAND_BORDER := Color(0.250, 0.760, 0.900, 0.82)
const COLOR_AMBER := Color(0.720, 0.330, 0.040, 1.0)
const COLOR_AMBER_HOVER := Color(0.880, 0.460, 0.080, 1.0)
const COLOR_AMBER_BORDER := Color(0.970, 0.720, 0.250, 1.0)

var _top_bar: PanelContainer = null
var _bottom_deck: PanelContainer = null
var _selection_panel: PanelContainer = null
var _command_panel: PanelContainer = null
var _build_panel: PanelContainer = null
var _resolve_panel: PanelContainer = null
var _active_player_label: Label = null
var _turn_label: Label = null
var _resources_label: Label = null
var _population_label: Label = null
var _outcome_label: Label = null
var _selection_label: Label = null
var _selection_details_label: Label = null
var _selection_intent_label: Label = null
var _status_label: Label = null
var _command_grid: GridContainer = null
var _production_controls: HBoxContainer = null
var _move_button: Button = null
var _target_button: Button = null
var _gather_button: Button = null
var _cancel_button: Button = null
var _resolve_button: Button = null
var _repeat_train_toggle: CheckBox = null
var _show_all_orders_toggle: CheckBox = null
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
var _theme_applied: bool = false


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
	match_over: bool,
	winner_player_id: int
) -> void:
	_resolve_nodes()
	_active_player_label.text = _player_label(active_player_id)
	_turn_label.text = "Turn %d" % turn_index
	_resources_label.text = "Minerals %d   Gas %d" % [minerals, gas]
	_population_label.text = "Pop %d/%d" % [pop_used, pop_cap]
	if match_over:
		_outcome_label.visible = true
		_outcome_label.text = (
			"Winner %s" % _player_label(winner_player_id) if winner_player_id >= 0 else "Match over"
		)
	else:
		_outcome_label.visible = false
		_outcome_label.text = ""


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
	return _command_panel.visible or _build_panel.visible


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
	_production_controls.visible = can_cancel or can_repeat_train
	_rebuild_option_buttons(_build_list, _build_options, build_requested)
	_rebuild_option_buttons(_train_list, _train_options, train_requested)
	_rebuild_option_buttons(_research_list, _research_options, research_requested)
	_rebuild_option_buttons(_ability_list, _ability_options, ability_requested)
	_command_grid.visible = can_move or can_target or can_gather
	_command_panel.visible = _command_grid.visible
	_build_panel.visible = (
		can_cancel
		or can_repeat_train
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
		_apply_theme()
		return
	_top_bar = get_node("TopBar") as PanelContainer
	_bottom_deck = get_node("BottomDeck") as PanelContainer
	_selection_panel = get_node("BottomDeck/Row/SelectionPanel") as PanelContainer
	_command_panel = get_node("BottomDeck/Row/CommandPanel") as PanelContainer
	_build_panel = get_node("BottomDeck/Row/BuildPanel") as PanelContainer
	_resolve_panel = get_node("BottomDeck/Row/ResolvePanel") as PanelContainer
	_active_player_label = get_node("TopBar/Row/ActivePlayer") as Label
	_turn_label = get_node("TopBar/Row/Turn") as Label
	_resources_label = get_node("TopBar/Row/Resources") as Label
	_population_label = get_node("TopBar/Row/Population") as Label
	_outcome_label = get_node("TopBar/Row/Outcome") as Label
	_selection_label = get_node("BottomDeck/Row/SelectionPanel/Stack/Selection") as Label
	_selection_details_label = get_node("BottomDeck/Row/SelectionPanel/Stack/Details") as Label
	_selection_intent_label = get_node("BottomDeck/Row/SelectionPanel/Stack/Intent") as Label
	_status_label = get_node("BottomDeck/Row/SelectionPanel/Stack/Status") as Label
	_command_grid = get_node("BottomDeck/Row/CommandPanel/Stack/CommandGrid") as GridContainer
	_move_button = get_node("BottomDeck/Row/CommandPanel/Stack/CommandGrid/Move") as Button
	_target_button = get_node("BottomDeck/Row/CommandPanel/Stack/CommandGrid/Attack") as Button
	_gather_button = get_node("BottomDeck/Row/CommandPanel/Stack/CommandGrid/Gather") as Button
	_production_controls = (
		get_node("BottomDeck/Row/BuildPanel/Stack/ProductionControls") as HBoxContainer
	)
	_cancel_button = (
		get_node("BottomDeck/Row/BuildPanel/Stack/ProductionControls/Cancel") as Button
	)
	_repeat_train_toggle = (
		get_node("BottomDeck/Row/BuildPanel/Stack/ProductionControls/RepeatTrain") as CheckBox
	)
	_build_list = (
		get_node("BottomDeck/Row/BuildPanel/Stack/OptionColumns/Build") as VBoxContainer
	)
	_train_list = (
		get_node("BottomDeck/Row/BuildPanel/Stack/OptionColumns/Train") as VBoxContainer
	)
	_research_list = (
		get_node("BottomDeck/Row/BuildPanel/Stack/OptionColumns/Research") as VBoxContainer
	)
	_ability_list = (
		get_node("BottomDeck/Row/BuildPanel/Stack/OptionColumns/Abilities") as VBoxContainer
	)
	_resolve_button = get_node("BottomDeck/Row/ResolvePanel/Stack/Resolve") as Button
	_show_all_orders_toggle = (
		get_node("BottomDeck/Row/ResolvePanel/Stack/ShowAllOrders") as CheckBox
	)
	_wire_signals()
	_apply_theme()


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
	if _theme_applied:
		return
	_theme_applied = true
	_apply_panel_style(_top_bar, true)
	_apply_panel_style(_bottom_deck, true)
	_apply_panel_style(_selection_panel, false)
	_apply_panel_style(_command_panel, false)
	_apply_panel_style(_build_panel, false)
	_apply_panel_style(_resolve_panel, false)
	for label in find_children("*", "Label", true, false):
		var typed_label: Label = label as Label
		if typed_label != null:
			typed_label.add_theme_font_size_override("font_size", FONT_SIZE)
			typed_label.add_theme_color_override("font_color", COLOR_TEXT)
	for header in [
		get_node_or_null("BottomDeck/Row/SelectionPanel/Stack/Header"),
		get_node_or_null("BottomDeck/Row/CommandPanel/Stack/Header"),
		get_node_or_null("BottomDeck/Row/BuildPanel/Stack/Header"),
		get_node_or_null("BottomDeck/Row/ResolvePanel/Stack/Header"),
	]:
		var header_label: Label = header as Label
		if header_label != null:
			header_label.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
			header_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	for button in find_children("*", "Button", true, false):
		var typed_button: Button = button as Button
		if typed_button != null:
			_apply_button_style(typed_button, false)
	_apply_button_style(_resolve_button, true)
	for toggle in find_children("*", "CheckBox", true, false):
		var typed_toggle: CheckBox = toggle as CheckBox
		if typed_toggle != null:
			_apply_toggle_style(typed_toggle)
	_status_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_selection_details_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_selection_details_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	_selection_intent_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_selection_intent_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)


func _rebuild_option_buttons(
	container: VBoxContainer, options: Array[Dictionary], signal_to_emit: Signal
) -> void:
	if container == null:
		return
	var button_grid: GridContainer = container.get_node_or_null("Buttons") as GridContainer
	if button_grid == null:
		return
	while button_grid.get_child_count() > 0:
		var child: Node = button_grid.get_child(0)
		button_grid.remove_child(child)
		child.queue_free()
	if options.is_empty():
		container.visible = false
		return
	container.visible = true
	for option in options:
		_add_option_button(button_grid, option, signal_to_emit)


func _add_option_button(
	container: Container, option: Dictionary, signal_to_emit: Signal
) -> void:
	var def_id: String = option.get("id", "")
	if def_id == "":
		return
	var label: String = option.get("label", def_id)
	var button: Button = Button.new()
	button.text = label
	button.disabled = option.get("disabled", false)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0.0, OPTION_BUTTON_MIN_HEIGHT)
	button.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_apply_button_style(button, false)
	button.pressed.connect(func() -> void: signal_to_emit.emit(def_id))
	container.add_child(button)


func _apply_panel_style(panel: PanelContainer, outer: bool) -> void:
	if panel == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BACK_DARK if outer else COLOR_PANEL_BACK
	style.border_color = COLOR_PANEL_BORDER_HOT if outer else COLOR_PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 7.0
	style.content_margin_top = 6.0
	style.content_margin_right = 7.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)


func _apply_button_style(button: Button, is_resolve: bool) -> void:
	if button == null:
		return
	button.custom_minimum_size = Vector2(0.0, BUTTON_MIN_HEIGHT)
	button.add_theme_font_size_override("font_size", FONT_SIZE if is_resolve else SMALL_FONT_SIZE)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	var normal_color: Color = COLOR_AMBER if is_resolve else COLOR_BUTTON
	var hover_color: Color = COLOR_AMBER_HOVER if is_resolve else COLOR_BUTTON_HOVER
	var border_color: Color = COLOR_AMBER_BORDER if is_resolve else COLOR_COMMAND_BORDER
	button.add_theme_stylebox_override("normal", _button_style(normal_color, border_color))
	button.add_theme_stylebox_override("hover", _button_style(hover_color, border_color))
	button.add_theme_stylebox_override(
		"pressed", _button_style(hover_color.darkened(0.18), border_color)
	)
	button.add_theme_stylebox_override(
		"disabled", _button_style(COLOR_BUTTON.darkened(0.35), COLOR_PANEL_BORDER)
	)


func _apply_toggle_style(toggle: CheckBox) -> void:
	if toggle == null:
		return
	toggle.custom_minimum_size = Vector2(0.0, BUTTON_MIN_HEIGHT)
	toggle.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	toggle.add_theme_color_override("font_color", COLOR_TEXT)
	toggle.add_theme_stylebox_override("normal", _button_style(COLOR_BUTTON, COLOR_COMMAND_BORDER))
	toggle.add_theme_stylebox_override(
		"hover", _button_style(COLOR_BUTTON_HOVER, COLOR_COMMAND_BORDER)
	)
	toggle.add_theme_stylebox_override(
		"pressed", _button_style(COLOR_BUTTON_HOVER.darkened(0.18), COLOR_COMMAND_BORDER)
	)
	toggle.add_theme_stylebox_override(
		"hover_pressed", _button_style(COLOR_BUTTON_HOVER, COLOR_COMMAND_BORDER)
	)
	toggle.add_theme_stylebox_override(
		"disabled", _button_style(COLOR_BUTTON.darkened(0.35), COLOR_PANEL_BORDER)
	)


func _button_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8.0
	style.content_margin_top = 5.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 5.0
	return style


func _player_label(player_id: int) -> String:
	return "P%d" % (player_id + 1)


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
