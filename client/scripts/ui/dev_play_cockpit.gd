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
signal idle_workers_requested

# HP readout severity steps (behavioral thresholds, not styling).
const HP_WARN_RATIO := 0.5
const HP_CRIT_RATIO := 0.25

var _top_bar: PanelContainer = null
var _bottom_deck: PanelContainer = null
var _selection_panel: PanelContainer = null
var _command_panel: PanelContainer = null
var _build_panel: PanelContainer = null
var _resolve_panel: PanelContainer = null
var _active_player_label: Label = null
var _turn_label: Label = null
var _submit_state_label: Label = null
var _idle_workers_button: Button = null
var _minerals_value_label: Label = null
var _minerals_income_label: Label = null
var _minerals_committed_label: Label = null
var _gas_value_label: Label = null
var _gas_income_label: Label = null
var _gas_committed_label: Label = null
var _supply_value_label: Label = null
var _supply_committed_label: Label = null
var _outcome_label: Label = null
var _selection_label: Label = null
var _stats_block: VBoxContainer = null
var _hp_row: HBoxContainer = null
var _hp_bar: ProgressBar = null
var _hp_label: Label = null
var _stat_row_label: Label = null
var _status_row: HBoxContainer = null
var _context_row_label: Label = null
var _preview_row_label: Label = null
var _production_strip: VBoxContainer = null
var _production_items: HBoxContainer = null
var _selection_details_label: Label = null
var _selection_intent_label: Label = null
var _status_label: Label = null
var _command_grid: GridContainer = null
var _production_controls: HBoxContainer = null
var _move_button: Button = null
var _target_button: Button = null
var _gather_button: Button = null
var _unit_cancel_button: Button = null
var _build_cancel_button: Button = null
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
	_minerals_value_label.text = "%d" % minerals
	_gas_value_label.text = "%d" % gas
	_supply_value_label.text = "%d/%d" % [pop_used, pop_cap]
	var supply_color: Color = (
		UiTokens.COLOR_DANGER if pop_cap > 0 and pop_used >= pop_cap else UiTokens.COLOR_TEXT
	)
	_supply_value_label.add_theme_color_override("font_color", supply_color)
	if match_over:
		_outcome_label.visible = true
		_outcome_label.text = (
			"Winner %s" % _player_label(winner_player_id) if winner_player_id >= 0 else "Match over"
		)
	else:
		_outcome_label.visible = false
		_outcome_label.text = ""


# economy keys: income_minerals, income_gas, income_known, committed_minerals,
# committed_gas, committed_pop. Missing keys hide the matching sub-label, so
# callers that never report economy keep today's plain top bar.
func set_economy_state(economy: Dictionary) -> void:
	_resolve_nodes()
	var income_known: bool = economy.get("income_known", false)
	_set_income_label(_minerals_income_label, income_known, int(economy.get("income_minerals", 0)))
	_set_income_label(_gas_income_label, income_known, int(economy.get("income_gas", 0)))
	_set_committed_label(_minerals_committed_label, int(economy.get("committed_minerals", 0)), "-")
	_set_committed_label(_gas_committed_label, int(economy.get("committed_gas", 0)), "-")
	_set_committed_label(_supply_committed_label, int(economy.get("committed_pop", 0)), "+")


func set_submit_state_text(text: String) -> void:
	_resolve_nodes()
	_submit_state_label.text = text
	_submit_state_label.visible = text != ""


func set_idle_worker_state(idle_count: int) -> void:
	_resolve_nodes()
	_idle_workers_button.visible = idle_count > 0
	_idle_workers_button.text = "Idle %d" % idle_count


# stats keys (all optional; an empty dictionary hides the whole block):
# hp/hp_max, damage/range/speed, statuses ([{id, duration}], duration -1 means
# indefinite), worker_state, gatherers ({assigned, cap}), damage_preview
# ({target_label, amount}).
func set_selection_stats(stats: Dictionary) -> void:
	_resolve_nodes()
	var hp_max: int = int(stats.get("hp_max", 0))
	_hp_row.visible = hp_max > 0
	if hp_max > 0:
		var hp: int = int(stats.get("hp", 0))
		_hp_bar.max_value = float(hp_max)
		_hp_bar.value = float(hp)
		_hp_bar.add_theme_stylebox_override(
			"fill", UiTokens.bar_style(_hp_fill_color(float(hp) / float(hp_max)))
		)
		_hp_label.text = "%d/%d" % [hp, hp_max]
	var stat_parts: Array[String] = []
	if stats.has("damage"):
		stat_parts.append("DMG %d" % int(stats.get("damage", 0)))
	if stats.has("range"):
		stat_parts.append("RNG %d" % int(stats.get("range", 0)))
	if stats.has("speed"):
		stat_parts.append("SPD %d" % int(stats.get("speed", 0)))
	_stat_row_label.text = " · ".join(stat_parts)
	_stat_row_label.visible = not stat_parts.is_empty()
	_clear_children(_status_row)
	var statuses: Array = stats.get("statuses", [])
	for status in statuses:
		_status_row.add_child(_make_status_chip(status))
	_status_row.visible = not statuses.is_empty()
	var context_parts: Array[String] = []
	var worker_state: String = str(stats.get("worker_state", ""))
	if worker_state != "":
		context_parts.append(worker_state)
	var gatherers: Dictionary = stats.get("gatherers", {})
	if not gatherers.is_empty():
		context_parts.append(
			"Workers %d/%d" % [int(gatherers.get("assigned", 0)), int(gatherers.get("cap", 0))]
		)
	_context_row_label.text = " · ".join(context_parts)
	_context_row_label.visible = not context_parts.is_empty()
	var damage_preview: Dictionary = stats.get("damage_preview", {})
	if damage_preview.is_empty():
		_preview_row_label.visible = false
		_preview_row_label.text = ""
	else:
		_preview_row_label.visible = true
		_preview_row_label.text = (
			"→ %d dmg vs %s"
			% [int(damage_preview.get("amount", 0)), str(damage_preview.get("target_label", ""))]
		)
	_stats_block.visible = (
		_hp_row.visible
		or _stat_row_label.visible
		or _status_row.visible
		or _context_row_label.visible
		or _preview_row_label.visible
	)


# production keys: visible, active ({label, turns_remaining, total_turns}),
# queue ([{label}]), pending ([{label}] — this-turn orders, not yet
# cancellable), pending_cancel_indices (already-queued CANCEL orders).
# The active chip cancels with index 0, queue chip i with index i + 1.
func set_production_state(production: Dictionary) -> void:
	_resolve_nodes()
	_clear_children(_production_items)
	var active: Dictionary = production.get("active", {})
	var queue: Array = production.get("queue", [])
	var pending: Array = production.get("pending", [])
	var pending_cancels: Array = production.get("pending_cancel_indices", [])
	_production_strip.visible = (
		bool(production.get("visible", false))
		and (not active.is_empty() or not queue.is_empty() or not pending.is_empty())
	)
	if not _production_strip.visible:
		return
	if not active.is_empty():
		_production_items.add_child(_make_active_chip(active, pending_cancels.has(0)))
	for queue_index in queue.size():
		var cancel_index: int = queue_index + 1
		_production_items.add_child(
			_make_queue_chip(queue[queue_index], cancel_index, pending_cancels.has(cancel_index))
		)
	for item in pending:
		_production_items.add_child(_make_pending_chip(item))


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


func set_turn_action_state(
	text: String, disabled: bool = false, pressed: bool = false, toggle_mode: bool = false
) -> void:
	_resolve_nodes()
	_resolve_button.toggle_mode = toggle_mode
	_resolve_button.set_pressed_no_signal(pressed)
	_resolve_button.text = text
	_resolve_button.disabled = disabled


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
	can_unit_cancel: bool,
	can_repeat_train: bool = false,
	repeat_train_enabled: bool = false,
	can_build_cancel: bool = false,
	use_split_cancel: bool = false
) -> void:
	_resolve_nodes()
	_repeat_train_enabled = repeat_train_enabled
	_build_options = _copy_options(build_options)
	_train_options = _copy_options(train_options)
	_research_options = _copy_options(research_options)
	_ability_options = _copy_options(ability_options)
	var show_build_cancel: bool = (
		can_build_cancel
		or (
			can_unit_cancel
			and not use_split_cancel
			and not can_move
			and not can_target
			and not can_gather
		)
	)
	var show_unit_cancel: bool = can_unit_cancel and not show_build_cancel
	_selection_label.text = selection_text
	_move_button.visible = can_move
	_move_button.disabled = false
	_target_button.visible = can_target
	_target_button.disabled = false
	_gather_button.visible = can_gather
	_gather_button.disabled = false
	_unit_cancel_button.visible = show_unit_cancel
	_unit_cancel_button.disabled = false
	_build_cancel_button.visible = show_build_cancel
	_build_cancel_button.disabled = false
	_repeat_train_toggle.visible = can_repeat_train
	_repeat_train_toggle.set_pressed_no_signal(repeat_train_enabled)
	_production_controls.visible = show_build_cancel or can_repeat_train
	_rebuild_option_buttons(_build_list, _build_options, build_requested)
	_rebuild_option_buttons(_train_list, _train_options, train_requested)
	_rebuild_option_buttons(_research_list, _research_options, research_requested)
	_rebuild_option_buttons(_ability_list, _ability_options, ability_requested)
	_command_grid.visible = can_move or can_target or can_gather or show_unit_cancel
	_command_panel.visible = _command_grid.visible
	_build_panel.visible = (
		show_build_cancel
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
	_submit_state_label = get_node("TopBar/Row/SubmitState") as Label
	_idle_workers_button = get_node("TopBar/Row/IdleWorkers") as Button
	_minerals_value_label = get_node("TopBar/Row/MineralsCluster/Value") as Label
	_minerals_income_label = get_node("TopBar/Row/MineralsCluster/Income") as Label
	_minerals_committed_label = get_node("TopBar/Row/MineralsCluster/Committed") as Label
	_gas_value_label = get_node("TopBar/Row/GasCluster/Value") as Label
	_gas_income_label = get_node("TopBar/Row/GasCluster/Income") as Label
	_gas_committed_label = get_node("TopBar/Row/GasCluster/Committed") as Label
	_supply_value_label = get_node("TopBar/Row/SupplyCluster/Value") as Label
	_supply_committed_label = get_node("TopBar/Row/SupplyCluster/Committed") as Label
	_outcome_label = get_node("TopBar/Row/Outcome") as Label
	_selection_label = get_node("BottomDeck/Row/SelectionPanel/Stack/Selection") as Label
	_stats_block = get_node("BottomDeck/Row/SelectionPanel/Stack/StatsBlock") as VBoxContainer
	_hp_row = get_node("BottomDeck/Row/SelectionPanel/Stack/StatsBlock/HpRow") as HBoxContainer
	_hp_bar = get_node("BottomDeck/Row/SelectionPanel/Stack/StatsBlock/HpRow/HpBar") as ProgressBar
	_hp_label = get_node("BottomDeck/Row/SelectionPanel/Stack/StatsBlock/HpRow/HpLabel") as Label
	_stat_row_label = get_node("BottomDeck/Row/SelectionPanel/Stack/StatsBlock/StatRow") as Label
	_status_row = (
		get_node("BottomDeck/Row/SelectionPanel/Stack/StatsBlock/StatusRow") as HBoxContainer
	)
	_context_row_label = (
		get_node("BottomDeck/Row/SelectionPanel/Stack/StatsBlock/ContextRow") as Label
	)
	_preview_row_label = (
		get_node("BottomDeck/Row/SelectionPanel/Stack/StatsBlock/PreviewRow") as Label
	)
	_production_strip = (
		get_node("BottomDeck/Row/SelectionPanel/Stack/ProductionStrip") as VBoxContainer
	)
	_production_items = (
		get_node("BottomDeck/Row/SelectionPanel/Stack/ProductionStrip/Items") as HBoxContainer
	)
	_selection_details_label = get_node("BottomDeck/Row/SelectionPanel/Stack/Details") as Label
	_selection_intent_label = get_node("BottomDeck/Row/SelectionPanel/Stack/Intent") as Label
	_status_label = get_node("BottomDeck/Row/SelectionPanel/Stack/Status") as Label
	_command_grid = get_node("BottomDeck/Row/CommandPanel/Stack/CommandGrid") as GridContainer
	_move_button = get_node("BottomDeck/Row/CommandPanel/Stack/CommandGrid/Move") as Button
	_target_button = get_node("BottomDeck/Row/CommandPanel/Stack/CommandGrid/Attack") as Button
	_gather_button = get_node("BottomDeck/Row/CommandPanel/Stack/CommandGrid/Gather") as Button
	_unit_cancel_button = (
		get_node("BottomDeck/Row/CommandPanel/Stack/CommandGrid/Cancel") as Button
	)
	_production_controls = (
		get_node("BottomDeck/Row/BuildPanel/Stack/ProductionControls") as HBoxContainer
	)
	_build_cancel_button = (
		get_node("BottomDeck/Row/BuildPanel/Stack/ProductionControls/Cancel") as Button
	)
	_repeat_train_toggle = (
		get_node("BottomDeck/Row/BuildPanel/Stack/ProductionControls/RepeatTrain") as CheckBox
	)
	_build_list = (get_node("BottomDeck/Row/BuildPanel/Stack/OptionColumns/Build") as VBoxContainer)
	_train_list = (get_node("BottomDeck/Row/BuildPanel/Stack/OptionColumns/Train") as VBoxContainer)
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
	_unit_cancel_button.pressed.connect(func() -> void: cancel_requested.emit(-1))
	_build_cancel_button.pressed.connect(func() -> void: cancel_requested.emit(-1))
	_resolve_button.pressed.connect(func() -> void: resolve_requested.emit())
	_idle_workers_button.pressed.connect(func() -> void: idle_workers_requested.emit())
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
	_top_bar.add_theme_stylebox_override("panel", UiTokens.panel_style(true))
	_bottom_deck.add_theme_stylebox_override("panel", UiTokens.panel_style(true))
	for panel in [_selection_panel, _command_panel, _build_panel, _resolve_panel]:
		panel.add_theme_stylebox_override("panel", UiTokens.panel_style(false))
	_apply_spacing()
	for label in find_children("*", "Label", true, false):
		var typed_label: Label = label as Label
		if typed_label != null:
			typed_label.add_theme_font_size_override("font_size", UiTokens.FONT_BODY)
			typed_label.add_theme_color_override("font_color", UiTokens.COLOR_TEXT)
	for header in [
		get_node_or_null("BottomDeck/Row/SelectionPanel/Stack/Header"),
		get_node_or_null("BottomDeck/Row/CommandPanel/Stack/Header"),
		get_node_or_null("BottomDeck/Row/BuildPanel/Stack/Header"),
		get_node_or_null("BottomDeck/Row/ResolvePanel/Stack/Header"),
		get_node_or_null("BottomDeck/Row/SelectionPanel/Stack/ProductionStrip/StripHeader"),
	]:
		_style_caption_label(header as Label, true)
	for button in find_children("*", "Button", true, false):
		var typed_button: Button = button as Button
		if typed_button != null:
			_style_button(typed_button, false)
	_style_button(_resolve_button, true)
	_style_idle_button()
	for toggle in find_children("*", "CheckBox", true, false):
		var typed_toggle: CheckBox = toggle as CheckBox
		if typed_toggle != null:
			_style_toggle(typed_toggle)
	_apply_top_bar_theme()
	_apply_selection_theme()


func _apply_spacing() -> void:
	var separations: Dictionary = {
		"TopBar/Row": UiTokens.SPACE_4,
		"TopBar/Row/MineralsCluster": UiTokens.SPACE_1,
		"TopBar/Row/GasCluster": UiTokens.SPACE_1,
		"TopBar/Row/SupplyCluster": UiTokens.SPACE_1,
		"BottomDeck/Row": UiTokens.SPACE_3,
		"BottomDeck/Row/SelectionPanel/Stack": UiTokens.SPACE_1,
		"BottomDeck/Row/SelectionPanel/Stack/StatsBlock": UiTokens.SPACE_1,
		"BottomDeck/Row/SelectionPanel/Stack/StatsBlock/HpRow": UiTokens.SPACE_2,
		"BottomDeck/Row/SelectionPanel/Stack/StatsBlock/StatusRow": UiTokens.SPACE_1,
		"BottomDeck/Row/SelectionPanel/Stack/ProductionStrip": UiTokens.SPACE_1,
		"BottomDeck/Row/SelectionPanel/Stack/ProductionStrip/Items": UiTokens.SPACE_2,
		"BottomDeck/Row/CommandPanel/Stack": UiTokens.SPACE_2,
		"BottomDeck/Row/BuildPanel/Stack": UiTokens.SPACE_1,
		"BottomDeck/Row/BuildPanel/Stack/ProductionControls": UiTokens.SPACE_1,
		"BottomDeck/Row/BuildPanel/Stack/OptionColumns": UiTokens.SPACE_2,
		"BottomDeck/Row/ResolvePanel/Stack": UiTokens.SPACE_2,
	}
	for path: String in separations:
		var container: Control = get_node_or_null(path) as Control
		if container != null:
			container.add_theme_constant_override("separation", separations[path])
	for column in ["Build", "Train", "Research", "Abilities"]:
		var column_box: Control = (
			get_node_or_null("BottomDeck/Row/BuildPanel/Stack/OptionColumns/%s" % column) as Control
		)
		if column_box != null:
			column_box.add_theme_constant_override("separation", UiTokens.SPACE_1)
		var button_grid: Control = (
			get_node_or_null("BottomDeck/Row/BuildPanel/Stack/OptionColumns/%s/Buttons" % column)
			as Control
		)
		if button_grid != null:
			button_grid.add_theme_constant_override("h_separation", UiTokens.SPACE_1)
			button_grid.add_theme_constant_override("v_separation", UiTokens.SPACE_1)
	if _command_grid != null:
		_command_grid.add_theme_constant_override("h_separation", UiTokens.SPACE_1)
		_command_grid.add_theme_constant_override("v_separation", UiTokens.SPACE_1)


func _apply_top_bar_theme() -> void:
	_active_player_label.add_theme_font_size_override("font_size", UiTokens.FONT_EMPHASIS)
	_style_caption_label(_turn_label, false)
	_turn_label.add_theme_font_size_override("font_size", UiTokens.FONT_BODY)
	_style_caption_label(_submit_state_label, false)
	_outcome_label.add_theme_font_size_override("font_size", UiTokens.FONT_EMPHASIS)
	_outcome_label.add_theme_color_override("font_color", UiTokens.COLOR_ACCENT)
	var swatch_colors: Dictionary = {
		"TopBar/Row/MineralsCluster/Swatch": UiTokens.COLOR_ACCENT,
		"TopBar/Row/GasCluster/Swatch": UiTokens.COLOR_ACCENT_MAGENTA,
	}
	for path: String in swatch_colors:
		var swatch: ColorRect = get_node_or_null(path) as ColorRect
		if swatch != null:
			swatch.color = swatch_colors[path]
			swatch.custom_minimum_size = Vector2(UiTokens.SWATCH, UiTokens.SWATCH)
	for cluster in ["MineralsCluster", "GasCluster", "SupplyCluster"]:
		_style_caption_label(get_node_or_null("TopBar/Row/%s/Caption" % cluster) as Label, true)
		var value_label: Label = get_node_or_null("TopBar/Row/%s/Value" % cluster) as Label
		if value_label != null:
			value_label.add_theme_font_size_override("font_size", UiTokens.FONT_EMPHASIS)
	for income_label in [_minerals_income_label, _gas_income_label]:
		income_label.add_theme_font_size_override("font_size", UiTokens.FONT_CAPTION)
		income_label.add_theme_color_override("font_color", UiTokens.COLOR_SUCCESS)
	for committed_label in [_minerals_committed_label, _gas_committed_label]:
		committed_label.add_theme_font_size_override("font_size", UiTokens.FONT_CAPTION)
		committed_label.add_theme_color_override("font_color", UiTokens.COLOR_AMBER)
	_supply_committed_label.add_theme_font_size_override("font_size", UiTokens.FONT_CAPTION)
	_supply_committed_label.add_theme_color_override("font_color", UiTokens.COLOR_AMBER)


func _apply_selection_theme() -> void:
	_selection_label.add_theme_font_size_override("font_size", UiTokens.FONT_EMPHASIS)
	_status_label.add_theme_font_size_override("font_size", UiTokens.FONT_BODY)
	_selection_details_label.add_theme_font_size_override("font_size", UiTokens.FONT_BODY)
	_selection_details_label.add_theme_color_override("font_color", UiTokens.COLOR_TEXT_MUTED)
	_selection_intent_label.add_theme_font_size_override("font_size", UiTokens.FONT_CAPTION)
	_selection_intent_label.add_theme_color_override("font_color", UiTokens.COLOR_TEXT_FAINT)
	_hp_bar.custom_minimum_size = Vector2(0.0, UiTokens.BAR_H)
	_hp_bar.add_theme_stylebox_override(
		"background", UiTokens.bar_style(UiTokens.COLOR_PROGRESS_BACK)
	)
	_hp_bar.add_theme_stylebox_override("fill", UiTokens.bar_style(UiTokens.COLOR_HP_HIGH))
	_style_caption_label(_hp_label, false)
	_stat_row_label.add_theme_font_size_override("font_size", UiTokens.FONT_BODY)
	_context_row_label.add_theme_font_size_override("font_size", UiTokens.FONT_BODY)
	_context_row_label.add_theme_color_override("font_color", UiTokens.COLOR_TEXT_MUTED)
	_preview_row_label.add_theme_font_size_override("font_size", UiTokens.FONT_BODY)
	_preview_row_label.add_theme_color_override("font_color", UiTokens.COLOR_AMBER)


func _style_caption_label(label: Label, uppercase: bool) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", UiTokens.FONT_CAPTION)
	label.add_theme_color_override("font_color", UiTokens.COLOR_TEXT_MUTED)
	label.uppercase = uppercase


func _style_button(button: Button, is_resolve: bool) -> void:
	if button == null:
		return
	button.custom_minimum_size = Vector2(0.0, UiTokens.CONTROL_H_LG)
	button.add_theme_font_size_override(
		"font_size", UiTokens.FONT_EMPHASIS if is_resolve else UiTokens.FONT_BODY
	)
	button.add_theme_color_override("font_color", UiTokens.COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", UiTokens.COLOR_TEXT_FAINT)
	var base_color: Color = UiTokens.COLOR_AMBER if is_resolve else UiTokens.COLOR_SURFACE_RAISED
	var hover_color: Color = (
		UiTokens.hover_color(UiTokens.COLOR_AMBER) if is_resolve else UiTokens.COLOR_SURFACE_HOVER
	)
	var border_color: Color = (
		UiTokens.COLOR_AMBER_BORDER if is_resolve else UiTokens.COLOR_BORDER_HOT
	)
	button.add_theme_stylebox_override("normal", UiTokens.button_style(base_color, border_color))
	var hover_style: StyleBoxFlat = UiTokens.button_style(hover_color, border_color)
	hover_style.set_border_width_all(UiTokens.BORDER_W_HOT)
	button.add_theme_stylebox_override("hover", hover_style)
	var pressed_style: StyleBoxFlat = UiTokens.button_style(
		UiTokens.pressed_color(hover_color), border_color
	)
	pressed_style.set_border_width_all(UiTokens.BORDER_W_HOT)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override(
		"disabled", UiTokens.button_style(UiTokens.COLOR_SURFACE, UiTokens.COLOR_BORDER)
	)


func _style_idle_button() -> void:
	if _idle_workers_button == null:
		return
	_idle_workers_button.add_theme_stylebox_override(
		"normal", UiTokens.button_style(UiTokens.COLOR_SURFACE_RAISED, UiTokens.COLOR_ACCENT)
	)
	var hover_style: StyleBoxFlat = UiTokens.button_style(
		UiTokens.COLOR_SURFACE_HOVER, UiTokens.COLOR_ACCENT
	)
	hover_style.set_border_width_all(UiTokens.BORDER_W_HOT)
	_idle_workers_button.add_theme_stylebox_override("hover", hover_style)


func _style_toggle(toggle: CheckBox) -> void:
	if toggle == null:
		return
	toggle.custom_minimum_size = Vector2(0.0, UiTokens.CONTROL_H_LG)
	toggle.add_theme_font_size_override("font_size", UiTokens.FONT_BODY)
	toggle.add_theme_color_override("font_color", UiTokens.COLOR_TEXT)
	var normal_style: StyleBoxFlat = UiTokens.button_style(
		UiTokens.COLOR_SURFACE_RAISED, UiTokens.COLOR_BORDER_HOT
	)
	var hover_style: StyleBoxFlat = UiTokens.button_style(
		UiTokens.COLOR_SURFACE_HOVER, UiTokens.COLOR_BORDER_HOT
	)
	var pressed_style: StyleBoxFlat = UiTokens.button_style(
		UiTokens.pressed_color(UiTokens.COLOR_SURFACE_HOVER), UiTokens.COLOR_BORDER_HOT
	)
	toggle.add_theme_stylebox_override("normal", normal_style)
	toggle.add_theme_stylebox_override("hover", hover_style)
	toggle.add_theme_stylebox_override("pressed", pressed_style)
	toggle.add_theme_stylebox_override("hover_pressed", hover_style)
	toggle.add_theme_stylebox_override(
		"disabled", UiTokens.button_style(UiTokens.COLOR_SURFACE, UiTokens.COLOR_BORDER)
	)


func _set_income_label(label: Label, income_known: bool, amount: int) -> void:
	if label == null:
		return
	label.visible = income_known
	label.text = "+%d/turn" % amount if income_known else ""


func _set_committed_label(label: Label, amount: int, prefix: String) -> void:
	if label == null:
		return
	label.visible = amount > 0
	label.text = "%s%d" % [prefix, amount] if amount > 0 else ""


func _hp_fill_color(ratio: float) -> Color:
	if ratio <= HP_CRIT_RATIO:
		return UiTokens.COLOR_HP_LOW
	if ratio <= HP_WARN_RATIO:
		return UiTokens.COLOR_AMBER
	return UiTokens.COLOR_HP_HIGH


func _make_status_chip(status: Dictionary) -> Control:
	var duration: int = int(status.get("duration", 0))
	var duration_text: String = "∞" if duration < 0 else "%d" % duration
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override(
		"panel", _chip_style(UiTokens.COLOR_SURFACE_RAISED, UiTokens.COLOR_BORDER_HOT)
	)
	var label := Label.new()
	label.text = "%s %s" % [str(status.get("id", "")).to_upper(), duration_text]
	label.add_theme_font_size_override("font_size", UiTokens.FONT_CAPTION)
	label.add_theme_color_override("font_color", UiTokens.COLOR_TEXT)
	chip.add_child(label)
	return chip


func _make_active_chip(active: Dictionary, cancel_pending: bool) -> Control:
	var total_turns: int = maxi(int(active.get("total_turns", 0)), 1)
	var turns_remaining: int = clampi(int(active.get("turns_remaining", 0)), 0, total_turns)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override(
		"panel", _chip_style(UiTokens.COLOR_SURFACE_RAISED, UiTokens.COLOR_BORDER)
	)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", UiTokens.SPACE_1)
	chip.add_child(stack)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", UiTokens.SPACE_1)
	stack.add_child(title_row)
	title_row.add_child(
		_make_chip_label(
			"%s · %dt" % [str(active.get("label", "")), turns_remaining], cancel_pending
		)
	)
	title_row.add_child(_make_chip_cancel_button(0, cancel_pending))
	var progress := ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(0.0, UiTokens.SPACE_2)
	progress.max_value = float(total_turns)
	progress.value = float(total_turns - turns_remaining)
	progress.add_theme_stylebox_override(
		"background", UiTokens.bar_style(UiTokens.COLOR_PROGRESS_BACK)
	)
	progress.add_theme_stylebox_override("fill", UiTokens.bar_style(UiTokens.COLOR_ACCENT))
	stack.add_child(progress)
	return chip


func _make_queue_chip(item: Dictionary, cancel_index: int, cancel_pending: bool) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override(
		"panel", _chip_style(UiTokens.COLOR_SURFACE, UiTokens.COLOR_BORDER)
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.SPACE_1)
	chip.add_child(row)
	row.add_child(_make_chip_label(str(item.get("label", "")), cancel_pending))
	row.add_child(_make_chip_cancel_button(cancel_index, cancel_pending))
	return chip


func _make_pending_chip(item: Dictionary) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override(
		"panel", _chip_style(UiTokens.COLOR_SURFACE, UiTokens.COLOR_BORDER)
	)
	var label := _make_chip_label(str(item.get("label", "")), true)
	label.tooltip_text = "Ordered this turn — joins the queue on resolve"
	chip.add_child(label)
	return chip


func _make_chip_label(text: String, faint: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UiTokens.FONT_CAPTION)
	label.add_theme_color_override(
		"font_color", UiTokens.COLOR_TEXT_FAINT if faint else UiTokens.COLOR_TEXT
	)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


func _make_chip_cancel_button(cancel_index: int, cancel_pending: bool) -> Button:
	var button := Button.new()
	button.text = "✕"
	button.disabled = cancel_pending
	button.tooltip_text = ("Cancel pending" if cancel_pending else "Cancel (refunds paid costs)")
	button.custom_minimum_size = Vector2(UiTokens.CONTROL_H_SM, UiTokens.CONTROL_H_SM)
	button.add_theme_font_size_override("font_size", UiTokens.FONT_CAPTION)
	button.add_theme_color_override("font_color", UiTokens.COLOR_DANGER)
	button.add_theme_color_override("font_disabled_color", UiTokens.COLOR_TEXT_FAINT)
	button.add_theme_stylebox_override(
		"normal", _chip_style(UiTokens.COLOR_SURFACE, UiTokens.COLOR_BORDER)
	)
	button.add_theme_stylebox_override(
		"hover", _chip_style(UiTokens.COLOR_SURFACE_HOVER, UiTokens.COLOR_DANGER)
	)
	button.add_theme_stylebox_override(
		"pressed", _chip_style(UiTokens.COLOR_SURFACE_HOVER, UiTokens.COLOR_DANGER)
	)
	button.add_theme_stylebox_override(
		"disabled", _chip_style(UiTokens.COLOR_SURFACE, UiTokens.COLOR_BORDER)
	)
	button.pressed.connect(func() -> void: cancel_requested.emit(cancel_index))
	return button


func _chip_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(UiTokens.BORDER_W)
	style.set_corner_radius_all(UiTokens.RADIUS_SM)
	style.content_margin_left = UiTokens.SPACE_2
	style.content_margin_right = UiTokens.SPACE_2
	style.content_margin_top = UiTokens.SPACE_1
	style.content_margin_bottom = UiTokens.SPACE_1
	return style


func _clear_children(container: Node) -> void:
	if container == null:
		return
	while container.get_child_count() > 0:
		var child: Node = container.get_child(0)
		container.remove_child(child)
		child.queue_free()


func _rebuild_option_buttons(
	container: VBoxContainer, options: Array[Dictionary], signal_to_emit: Signal
) -> void:
	if container == null:
		return
	var button_grid: GridContainer = container.get_node_or_null("Buttons") as GridContainer
	if button_grid == null:
		return
	_clear_children(button_grid)
	if options.is_empty():
		container.visible = false
		return
	container.visible = true
	for option in options:
		_add_option_button(button_grid, option, signal_to_emit)


func _add_option_button(container: Container, option: Dictionary, signal_to_emit: Signal) -> void:
	var def_id: String = option.get("id", "")
	if def_id == "":
		return
	var label: String = option.get("label", def_id)
	var button: Button = Button.new()
	button.text = label
	button.disabled = option.get("disabled", false)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(button, false)
	button.custom_minimum_size = Vector2(0.0, UiTokens.CONTROL_H_MD)
	button.add_theme_font_size_override("font_size", UiTokens.FONT_BODY)
	button.pressed.connect(func() -> void: signal_to_emit.emit(def_id))
	container.add_child(button)


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
