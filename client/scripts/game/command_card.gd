class_name CommandCard
extends VBoxContainer

signal move_requested
signal target_requested
signal hold_fire_requested(enabled: bool)
signal gather_requested
signal build_requested(def_id: String)
signal train_requested(def_id: String)
signal research_requested(def_id: String)
signal ability_requested(def_id: String)
signal cancel_requested(cancel_index: int)

const DEV_FONT_SIZE := 18
const DEV_BUTTON_MIN_HEIGHT := 34.0

var _selection_label: Label = null
var _move_button: Button = null
var _target_button: Button = null
var _hold_fire_button: Button = null
var _gather_button: Button = null
var _cancel_button: Button = null
var _primary_row: HBoxContainer = null
var _build_list: VBoxContainer = null
var _train_list: VBoxContainer = null
var _research_list: VBoxContainer = null
var _ability_list: VBoxContainer = null
var _hold_fire_enabled: bool = false
var _build_options: Array[Dictionary] = []
var _train_options: Array[Dictionary] = []
var _research_options: Array[Dictionary] = []
var _ability_options: Array[Dictionary] = []


func _ready() -> void:
	_ensure_ui()


func set_command_state(
	selection_text: String,
	can_move: bool,
	can_target: bool,
	can_hold_fire: bool,
	can_gather: bool,
	hold_fire_enabled: bool,
	build_options: Array[Dictionary],
	train_options: Array[Dictionary],
	research_options: Array[Dictionary],
	ability_options: Array[Dictionary],
	can_cancel: bool
) -> void:
	_ensure_ui()
	_hold_fire_enabled = hold_fire_enabled
	_build_options = _copy_options(build_options)
	_train_options = _copy_options(train_options)
	_research_options = _copy_options(research_options)
	_ability_options = _copy_options(ability_options)
	_selection_label.text = selection_text
	_move_button.visible = can_move
	_move_button.disabled = false
	_target_button.visible = can_target
	_target_button.disabled = false
	_hold_fire_button.visible = can_hold_fire
	_hold_fire_button.disabled = false
	_hold_fire_button.text = "Hold Fire: On" if hold_fire_enabled else "Hold Fire: Off"
	_gather_button.visible = can_gather
	_gather_button.disabled = false
	_cancel_button.visible = can_cancel
	_cancel_button.disabled = false
	_rebuild_option_buttons(_build_list, _build_options, build_requested)
	_rebuild_option_buttons(_train_list, _train_options, train_requested)
	_rebuild_option_buttons(_research_list, _research_options, research_requested)
	_rebuild_option_buttons(_ability_list, _ability_options, ability_requested)
	_primary_row.visible = can_move or can_target or can_hold_fire or can_gather or can_cancel
	visible = (
		_primary_row.visible
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


func _ensure_ui() -> void:
	if _selection_label != null:
		return
	name = "CommandCard"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_selection_label = Label.new()
	_selection_label.text = "Command card: none"
	_style_label(_selection_label)
	add_child(_selection_label)

	_primary_row = HBoxContainer.new()
	_primary_row.name = "Primary"
	add_child(_primary_row)

	_move_button = _button("Move")
	_move_button.pressed.connect(func() -> void: move_requested.emit())
	_primary_row.add_child(_move_button)

	_target_button = _button("Target")
	_target_button.pressed.connect(func() -> void: target_requested.emit())
	_primary_row.add_child(_target_button)

	_hold_fire_button = _button("Hold Fire: Off")
	_hold_fire_button.pressed.connect(
		func() -> void: hold_fire_requested.emit(not _hold_fire_enabled)
	)
	_primary_row.add_child(_hold_fire_button)

	_gather_button = _button("Gather")
	_gather_button.pressed.connect(func() -> void: gather_requested.emit())
	_primary_row.add_child(_gather_button)

	_cancel_button = _button("Cancel")
	_cancel_button.pressed.connect(func() -> void: cancel_requested.emit(-1))
	_primary_row.add_child(_cancel_button)

	_build_list = _section("Build")
	add_child(_build_list)
	_train_list = _section("Train")
	add_child(_train_list)
	_research_list = _section("Research")
	add_child(_research_list)
	_ability_list = _section("Abilities")
	add_child(_ability_list)


func _section(title: String) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = title
	var label: Label = Label.new()
	label.text = title
	_style_label(label)
	box.add_child(label)
	return box


func _button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0.0, DEV_BUTTON_MIN_HEIGHT)
	button.add_theme_font_size_override("font_size", DEV_FONT_SIZE)
	return button


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
	var button: Button = _button(label)
	button.disabled = option.get("disabled", false)
	button.pressed.connect(func() -> void: signal_to_emit.emit(def_id))
	container.add_child(button)


func _copy_options(options: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for option in options:
		out.append(option.duplicate())
	return out


func _style_label(label: Label) -> void:
	label.add_theme_font_size_override("font_size", DEV_FONT_SIZE)


func _option_ids(options: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for option in options:
		var def_id: String = option.get("id", "")
		if def_id != "":
			out.append(def_id)
	return out
