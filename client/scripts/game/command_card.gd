class_name CommandCard
extends VBoxContainer

signal attack_move_requested
signal hold_fire_requested(enabled: bool)
signal build_requested(def_id: String)
signal train_requested(def_id: String)
signal research_requested(def_id: String)
signal cancel_requested(cancel_index: int)

var _selection_label: Label = null
var _attack_move_button: Button = null
var _hold_fire_button: Button = null
var _cancel_button: Button = null
var _build_list: VBoxContainer = null
var _train_list: VBoxContainer = null
var _research_list: VBoxContainer = null
var _hold_fire_enabled: bool = false
var _build_options: Array[Dictionary] = []
var _train_options: Array[Dictionary] = []
var _research_options: Array[Dictionary] = []


func _ready() -> void:
	_ensure_ui()


func set_command_state(
	selection_text: String,
	can_attack_move: bool,
	can_hold_fire: bool,
	hold_fire_enabled: bool,
	build_options: Array[Dictionary],
	train_options: Array[Dictionary],
	research_options: Array[Dictionary],
	can_cancel: bool
) -> void:
	_ensure_ui()
	_hold_fire_enabled = hold_fire_enabled
	_build_options = _copy_options(build_options)
	_train_options = _copy_options(train_options)
	_research_options = _copy_options(research_options)
	_selection_label.text = "Command card: %s" % selection_text
	_attack_move_button.disabled = not can_attack_move
	_hold_fire_button.disabled = not can_hold_fire
	_hold_fire_button.text = "Hold Fire: On" if hold_fire_enabled else "Hold Fire: Off"
	_cancel_button.disabled = not can_cancel
	_rebuild_option_buttons(_build_list, _build_options, build_requested)
	_rebuild_option_buttons(_train_list, _train_options, train_requested)
	_rebuild_option_buttons(_research_list, _research_options, research_requested)


func build_option_ids() -> Array[String]:
	return _option_ids(_build_options)


func train_option_ids() -> Array[String]:
	return _option_ids(_train_options)


func research_option_ids() -> Array[String]:
	return _option_ids(_research_options)


func _ensure_ui() -> void:
	if _selection_label != null:
		return
	name = "CommandCard"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_selection_label = Label.new()
	_selection_label.text = "Command card: none"
	add_child(_selection_label)

	var primary_row: HBoxContainer = HBoxContainer.new()
	primary_row.name = "Primary"
	add_child(primary_row)

	_attack_move_button = _button("Attack Move")
	_attack_move_button.pressed.connect(func() -> void: attack_move_requested.emit())
	primary_row.add_child(_attack_move_button)

	_hold_fire_button = _button("Hold Fire: Off")
	_hold_fire_button.pressed.connect(
		func() -> void: hold_fire_requested.emit(not _hold_fire_enabled)
	)
	primary_row.add_child(_hold_fire_button)

	_cancel_button = _button("Cancel")
	_cancel_button.pressed.connect(func() -> void: cancel_requested.emit(-1))
	primary_row.add_child(_cancel_button)

	_build_list = _section("Build")
	add_child(_build_list)
	_train_list = _section("Train")
	add_child(_train_list)
	_research_list = _section("Research")
	add_child(_research_list)


func _section(title: String) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = title
	var label: Label = Label.new()
	label.text = title
	box.add_child(label)
	return box


func _button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		var empty_label: Label = Label.new()
		empty_label.text = "none"
		container.add_child(empty_label)
		return
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
