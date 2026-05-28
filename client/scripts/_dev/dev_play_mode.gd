class_name DevPlayMode
extends Node

const DEFAULT_SCENARIO_PATH := "res://data/scenarios/mvp_map.tres"
const MATCH_SCENE_PATH := "res://scenes/match.tscn"
const REGISTRY_PATH := "res://data/entity_registry.tres"
const TUNABLES_PATH := "res://data/tunables.tres"
const DEV_TURN_INPUT_SCRIPT := preload("res://scripts/game/dev_turn_input.gd")
const COMMAND_CARD_SCRIPT := preload("res://scripts/game/command_card.gd")
const PENDING_NONE := ""
const PENDING_MOVE := "move"
const PENDING_MOVE_ONLY := "move_only"
const PENDING_TARGET := "target"
const PENDING_BUILD := "build"
const PENDING_GATHER := "gather"
const HUD_MARGIN := 12.0
const HUD_WIDTH := 440.0
const HUD_HEIGHT := 560.0
const CAMERA_ZOOM_STEP := 1.15
const CAMERA_DRAG_THRESHOLD := 4.0

@export_file("*.tres") var scenario_path: String = DEFAULT_SCENARIO_PATH

var _renderer: MatchRenderer = null
var _loaded: LoadedScenario = null
var _tunables: Tunables = null
var _input: DevTurnInput = DEV_TURN_INPUT_SCRIPT.new() as DevTurnInput
var _hud_layer: CanvasLayer = null
var _active_label: Label = null
var _resources_label: Label = null
var _queue_label: Label = null
var _status_label: Label = null
var _command_card: Control = null
var _pending_command: String = PENDING_NONE
var _pending_build_def_id: String = ""
var _is_panning_camera: bool = false
var _left_empty_drag_candidate: bool = false
var _left_empty_drag_moved: bool = false
var _left_empty_drag_start: Vector2 = Vector2.ZERO
var _show_all_friendly_action_previews: bool = false


func _ready() -> void:
	_build_hud()
	if _loaded == null:
		load_scenario_path(scenario_path)


func load_scenario_path(path: String) -> bool:
	_build_hud()
	var scenario: ScenarioDef = load(path) as ScenarioDef
	var registry: EntityRegistry = load(REGISTRY_PATH) as EntityRegistry
	_tunables = load(TUNABLES_PATH) as Tunables
	if scenario == null or registry == null or _tunables == null:
		push_error("DevPlayMode: missing scenario, registry, or tunables.")
		return false
	_loaded = ScenarioLoader.load(scenario, registry, _tunables)
	if _loaded == null:
		push_error("DevPlayMode: ScenarioLoader returned null.")
		return false
	_clear_pending_command()
	_ensure_renderer()
	if _renderer == null:
		return false
	_renderer.bind_state(_loaded.state, _loaded.registry)
	_renderer.set_perspective_player_id(_input.active_player_id())
	_renderer.focus_player_start(_input.active_player_id())
	_input.bind_context(_loaded.state, _loaded.registry)
	_input.clear_submissions()
	_update_hud()
	return true


func current_state() -> MatchState:
	if _loaded == null:
		return null
	return _loaded.state


func renderer() -> MatchRenderer:
	return _renderer


func input_model() -> DevTurnInput:
	return _input


func command_card() -> Control:
	return _command_card


func pending_command_kind() -> String:
	return _pending_command


func set_show_all_friendly_action_previews(enabled: bool) -> void:
	_show_all_friendly_action_previews = enabled
	_refresh_action_previews()


func set_active_player_id(player_id: int) -> void:
	_input.set_active_player_id(player_id)
	_clear_pending_command()
	if _renderer != null:
		_renderer.set_perspective_player_id(player_id)
		_renderer.focus_player_start(player_id)
		_renderer.clear_input_highlights()
	_update_hud()


func select_entity_id(entity_id: int) -> bool:
	var ok: bool = _input.select_entity(entity_id)
	if _renderer != null:
		_clear_build_placement_preview()
		if ok:
			_renderer.set_selected_entity_id(entity_id)
		else:
			_renderer.clear_input_highlights()
	_update_hud()
	return ok


func issue_move_selected(tile: Vector2i) -> bool:
	var ok: bool = _input.issue_move(tile)
	_update_hud()
	return ok


func issue_move_only_selected(tile: Vector2i) -> bool:
	var ok: bool = _input.issue_move_only(tile)
	_update_hud()
	return ok


func issue_attack_selected(target_entity_id: int) -> bool:
	var ok: bool = _input.issue_attack(target_entity_id)
	_update_hud()
	return ok


func issue_attack_target_selected(target_entity_id: int) -> bool:
	var ok: bool = _input.issue_attack_target(target_entity_id)
	_update_hud()
	return ok


func issue_gather_selected(target_entity_id: int) -> bool:
	var ok: bool = _input.issue_gather(target_entity_id)
	_update_hud()
	return ok


func issue_halt_on_sight_selected(enabled: bool) -> bool:
	var ok: bool = _input.issue_halt_on_sight_toggle(enabled)
	_update_hud()
	return ok


func issue_build_selected(def_id: String, tile: Vector2i) -> bool:
	var ok: bool = _input.issue_build(def_id, tile)
	_update_hud()
	return ok


func issue_train_selected(def_id: String) -> bool:
	var ok: bool = _input.issue_train(def_id)
	_update_hud()
	return ok


func issue_research_selected(def_id: String) -> bool:
	var ok: bool = _input.issue_research(def_id)
	_update_hud()
	return ok


func issue_ability_selected(ability_id: String) -> bool:
	var ok: bool = _input.issue_ability(ability_id)
	_update_hud()
	return ok


func issue_cancel_selected(cancel_index: int = -1) -> bool:
	var ok: bool = _input.issue_cancel(cancel_index)
	_update_hud()
	return ok


func issue_context_at_tile(tile: Vector2i) -> bool:
	if _loaded == null or _loaded.state == null or _loaded.state.tile_grid == null:
		return false
	var target_id: int = (
		_renderer.entity_id_at_tile(tile)
		if _renderer != null
		else _loaded.state.tile_grid.entity_at(tile)
	)
	if target_id >= 0:
		var target: Entity = _loaded.state.get_entity_by_id(target_id)
		if target != null and target.owner_player_id >= 0:
			if target.owner_player_id != _input.active_player_id():
				return issue_attack_target_selected(target_id)
			return false
		if _is_gather_target(target):
			return issue_gather_selected(target_id)
	return issue_move_selected(tile)


func begin_move() -> void:
	if not _input.can_issue_move():
		_update_hud("Select a movable unit before Attack and Move.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_MOVE
	_pending_build_def_id = ""
	_update_hud("Click a target tile for Attack and Move.")


func begin_move_only() -> void:
	if not _input.can_issue_move_only():
		_update_hud("Select a movable unit before MOVE ONLY.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_MOVE_ONLY
	_pending_build_def_id = ""
	_update_hud("Click a target tile for MOVE ONLY. Unit will not shoot this turn.")


func begin_target() -> void:
	if not _input.can_issue_attack_target():
		_update_hud("Select a combat unit before TARGET.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_TARGET
	_pending_build_def_id = ""
	_update_hud("Click an enemy for TARGET.")


func begin_build(def_id: String) -> void:
	_clear_build_placement_preview()
	if not _input.build_option_ids().has(def_id):
		_update_hud("Selected entity cannot BUILD %s." % def_id)
		return
	_pending_command = PENDING_BUILD
	_pending_build_def_id = def_id
	_update_hud("Click a placement tile for BUILD %s." % def_id)


func confirm_pending_at_tile(tile: Vector2i) -> bool:
	if _pending_command == PENDING_MOVE:
		var move_ok: bool = issue_move_selected(tile)
		if move_ok:
			_clear_pending_command()
			_update_hud()
		return move_ok
	if _pending_command == PENDING_MOVE_ONLY:
		var move_only_ok: bool = issue_move_only_selected(tile)
		if move_only_ok:
			_clear_pending_command()
			_update_hud()
		return move_only_ok
	if _pending_command == PENDING_TARGET:
		var target_id: int = (
			_renderer.entity_id_at_tile(tile)
			if _renderer != null
			else _loaded.state.tile_grid.entity_at(tile)
		)
		var target: Entity = _loaded.state.get_entity_by_id(target_id)
		if (
			target == null
			or target.owner_player_id < 0
			or target.owner_player_id == _input.active_player_id()
		):
			_update_hud("Click an enemy to set TARGET.")
			return false
		var target_ok: bool = issue_attack_target_selected(target_id)
		if target_ok:
			_clear_pending_command()
			_update_hud()
		return target_ok
	if _pending_command == PENDING_BUILD:
		var build_ok: bool = issue_build_selected(_pending_build_def_id, tile)
		if build_ok:
			_clear_pending_command()
			_update_hud()
		return build_ok
	if _pending_command == PENDING_GATHER:
		if _loaded == null or _loaded.state == null:
			return false
		var target_id: int = (
			_renderer.entity_id_at_tile(tile)
			if _renderer != null
			else _loaded.state.tile_grid.entity_at(tile)
		)
		var target: Entity = _loaded.state.get_entity_by_id(target_id)
		if not _is_gather_target(target):
			_update_hud("Click a mineral patch or refinery to GATHER.")
			return false
		var gather_ok: bool = issue_gather_selected(target_id)
		if gather_ok:
			_clear_pending_command()
			_update_hud()
		return gather_ok
	return false


func cancel_pending_command() -> void:
	if _pending_command == PENDING_NONE:
		return
	_clear_pending_command()
	_update_hud("Pending command cancelled.")


func pending_order_count(player_id: int) -> int:
	return _input.queued_order_count(player_id)


func resolve_turn() -> bool:
	if _loaded == null or _loaded.state == null or _loaded.registry == null or _tunables == null:
		return false
	var result: ResolveResult = Resolver.resolve(
		_loaded.state,
		_input.submit_for_player(0),
		_input.submit_for_player(1),
		_loaded.registry,
		_tunables
	)
	if result == null or result.new_state == null:
		return false
	_loaded.state = result.new_state
	_clear_pending_command()
	if _renderer != null:
		_renderer.render_step(result.new_state, result.events)
		_renderer.clear_input_highlights()
	_input.bind_context(_loaded.state, _loaded.registry)
	_input.clear_submissions(false)
	_input.queue_move_assists_for_next_turn()
	_update_hud("Resolved turn %d." % _loaded.state.turn_index)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if _renderer == null or _loaded == null:
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
			_renderer.pan_camera_by_screen_delta(motion.relative)
			return
		var hover_tile: Vector2i = _renderer.world_to_tile(_event_world_position(motion))
		_set_hover_tile(hover_tile)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_renderer.zoom_camera(CAMERA_ZOOM_STEP)
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_renderer.zoom_camera(1.0 / CAMERA_ZOOM_STEP)
			return
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning_camera = button.pressed
			return
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			if _left_empty_drag_candidate:
				if not _left_empty_drag_moved:
					_input.clear_selection()
					_renderer.clear_input_highlights()
					_update_hud("Selection cleared.")
				_reset_left_empty_drag()
				return
			_reset_left_empty_drag()
		if not button.pressed:
			return
		var tile: Vector2i = _renderer.world_to_tile(_event_world_position(button))
		var entity_id: int = _renderer.entity_id_at_tile(tile)
		if button.button_index == MOUSE_BUTTON_LEFT:
			if _pending_command != PENDING_NONE:
				confirm_pending_at_tile(tile)
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
			issue_context_at_tile(tile)


func _ensure_renderer() -> void:
	if _renderer != null:
		return
	var packed: PackedScene = load(MATCH_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("DevPlayMode: failed to load %s" % MATCH_SCENE_PATH)
		return
	_renderer = packed.instantiate() as MatchRenderer
	if _renderer == null:
		push_error("DevPlayMode: match scene root is not a MatchRenderer.")
		return
	add_child(_renderer)


func _event_world_position(event: InputEventMouse) -> Vector2:
	if _renderer == null:
		return event.position
	if _renderer.get_viewport() == null:
		return event.position
	return _renderer.get_global_mouse_position()


func _reset_left_empty_drag() -> void:
	_left_empty_drag_candidate = false
	_left_empty_drag_moved = false
	_left_empty_drag_start = Vector2.ZERO
	_is_panning_camera = false


func _set_hover_tile(tile: Vector2i) -> void:
	if _renderer == null:
		return
	_renderer.set_hover_tile(tile)
	if _pending_command == PENDING_BUILD:
		_refresh_build_placement_preview(tile)
	else:
		_clear_build_placement_preview()


func _build_hud() -> void:
	if _hud_layer != null:
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "DevHUD"
	add_child(_hud_layer)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -HUD_WIDTH - HUD_MARGIN
	panel.offset_top = HUD_MARGIN
	panel.offset_right = -HUD_MARGIN
	panel.offset_bottom = HUD_MARGIN + HUD_HEIGHT
	_hud_layer.add_child(panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Root"
	panel.add_child(root)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.name = "Buttons"
	root.add_child(buttons)

	var p0_button: Button = _button("P0")
	p0_button.pressed.connect(func() -> void: set_active_player_id(0))
	buttons.add_child(p0_button)

	var p1_button: Button = _button("P1")
	p1_button.pressed.connect(func() -> void: set_active_player_id(1))
	buttons.add_child(p1_button)

	var resolve_button: Button = _button("Resolve")
	resolve_button.pressed.connect(resolve_turn)
	buttons.add_child(resolve_button)

	var clear_button: Button = _button("Clear")
	clear_button.pressed.connect(_clear_queues_from_hud)
	buttons.add_child(clear_button)

	var surrender_button: Button = _button("Surrender")
	surrender_button.pressed.connect(_surrender_from_hud)
	buttons.add_child(surrender_button)

	var preview_toggle := CheckBox.new()
	preview_toggle.name = "ShowFriendlyPreviews"
	preview_toggle.text = "Show all friendly orders"
	preview_toggle.button_pressed = _show_all_friendly_action_previews
	preview_toggle.add_theme_font_size_override("font_size", 18)
	preview_toggle.toggled.connect(set_show_all_friendly_action_previews)
	root.add_child(preview_toggle)

	_active_label = Label.new()
	_active_label.name = "ActivePlayer"
	_style_label(_active_label)
	root.add_child(_active_label)
	_resources_label = Label.new()
	_resources_label.name = "Resources"
	_style_label(_resources_label)
	root.add_child(_resources_label)
	_queue_label = Label.new()
	_queue_label.name = "QueuedOrders"
	_style_label(_queue_label)
	root.add_child(_queue_label)
	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(_status_label)
	root.add_child(_status_label)

	_command_card = COMMAND_CARD_SCRIPT.new() as Control
	_command_card.connect("move_requested", Callable(self, "begin_move"))
	_command_card.connect("move_only_requested", Callable(self, "begin_move_only"))
	_command_card.connect("target_requested", Callable(self, "begin_target"))
	_command_card.connect("halt_on_sight_requested", Callable(self, "issue_halt_on_sight_selected"))
	_command_card.connect("gather_requested", Callable(self, "begin_gather"))
	_command_card.connect("build_requested", Callable(self, "begin_build"))
	_command_card.connect("train_requested", Callable(self, "issue_train_selected"))
	_command_card.connect("research_requested", Callable(self, "issue_research_selected"))
	_command_card.connect("ability_requested", Callable(self, "issue_ability_selected"))
	_command_card.connect("cancel_requested", Callable(self, "issue_cancel_selected"))
	root.add_child(_command_card)
	_update_hud()


func _button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 34.0)
	button.add_theme_font_size_override("font_size", 18)
	return button


func _style_label(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 18)


func _clear_queues_from_hud() -> void:
	_input.clear_submissions()
	_clear_pending_command()
	_update_hud()


func _surrender_from_hud() -> void:
	_input.surrender_active_player()
	_update_hud()


func _update_hud(override_status: String = "") -> void:
	if _active_label != null:
		_active_label.text = "Active player: P%d" % _input.active_player_id()
	if _resources_label != null:
		var player := (
			_loaded.state.get_player(_input.active_player_id()) if _loaded != null else null
		)
		if player == null:
			_resources_label.text = ""
		else:
			_resources_label.text = (
				"Minerals: %d  Gas: %d  Pop: %d/%d"
				% [player.minerals, player.gas, player.pop_used, player.pop_cap]
			)
	if _queue_label != null:
		var queued: int = _input.queued_order_count(_input.active_player_id())
		_queue_label.visible = queued > 0
		_queue_label.text = ("Queued this turn: %d action%s" % [queued, "" if queued == 1 else "s"])
	if _status_label != null:
		var status_message: String = _input.status_message()
		if override_status != "":
			_status_label.text = override_status
		elif (
			_pending_command != PENDING_NONE
			and status_message != ""
			and not status_message.begins_with("Queued")
			and not status_message.begins_with("Selected")
		):
			_status_label.text = status_message
		elif _pending_command == PENDING_MOVE:
			_status_label.text = "Pending Attack and Move: click target tile."
		elif _pending_command == PENDING_MOVE_ONLY:
			_status_label.text = "Pending MOVE ONLY: click target tile. Unit will not shoot."
		elif _pending_command == PENDING_TARGET:
			_status_label.text = "Pending TARGET: click an enemy."
		elif _pending_command == PENDING_BUILD:
			_status_label.text = "Pending BUILD %s: click placement tile." % _pending_build_def_id
		elif _pending_command == PENDING_GATHER:
			_status_label.text = "Pending GATHER: click a mineral patch or refinery."
		else:
			_status_label.text = status_message
	_refresh_command_card()
	_refresh_action_previews()


func _is_gather_target(entity: Entity) -> bool:
	if entity == null or _loaded == null or _loaded.registry == null:
		return false
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	var def: EntityDef = _loaded.registry.get_by_id(def_id)
	if def == null:
		return false
	return def.resource_source != null or def.tags.has("refinery")


func _clear_pending_command() -> void:
	_pending_command = PENDING_NONE
	_pending_build_def_id = ""
	_clear_build_placement_preview()


func begin_gather() -> void:
	if not _input.can_issue_gather():
		_update_hud("Select a worker before GATHER.")
		return
	_clear_build_placement_preview()
	_pending_command = PENDING_GATHER
	_pending_build_def_id = ""
	_update_hud("Click a mineral patch or refinery to GATHER.")


func _refresh_build_placement_preview(tile: Vector2i) -> void:
	if _renderer == null or not _renderer.has_method("set_build_placement_preview"):
		return
	if _pending_command != PENDING_BUILD or _pending_build_def_id == "":
		_clear_build_placement_preview()
		return
	var preview: Dictionary = _input.build_placement_preview(_pending_build_def_id, tile)
	_renderer.call("set_build_placement_preview", preview)


func _clear_build_placement_preview() -> void:
	if _renderer == null or not _renderer.has_method("clear_build_placement_preview"):
		return
	_renderer.call("clear_build_placement_preview")


func _refresh_command_card() -> void:
	if _command_card == null:
		return
	_command_card.call(
		"set_command_state",
		_input.selected_entity_label(),
		_input.can_issue_move(),
		_input.can_issue_move_only(),
		_input.can_issue_attack_target(),
		_input.can_issue_halt_on_sight_toggle(),
		_input.can_issue_gather(),
		_input.selected_halt_on_sight(),
		_build_options(_input.build_option_ids()),
		_entity_options(_input.train_option_ids()),
		_research_options(_input.research_option_ids()),
		_ability_options(_input.ability_option_ids()),
		_input.can_issue_cancel()
	)


func _refresh_action_previews() -> void:
	if _renderer == null or not _renderer.has_method("set_action_previews"):
		return
	var previews: Array[Dictionary] = []
	var selected_id: int = _input.selected_entity_id()
	previews.append_array(_previews_for_entity(selected_id))
	if _show_all_friendly_action_previews:
		if _loaded == null or _loaded.state == null:
			_renderer.call("set_action_previews", previews)
			return
		var active_player_id: int = _input.active_player_id()
		var seen: Dictionary[int, bool] = {}
		if selected_id >= 0:
			seen[selected_id] = true
		for entity in _loaded.state.entities_sorted_by_id():
			if entity == null or entity.owner_player_id != active_player_id or seen.has(entity.id):
				continue
			var entity_previews: Array[Dictionary] = _previews_for_entity(entity.id)
			if entity_previews.is_empty():
				continue
			previews.append_array(entity_previews)
			seen[entity.id] = true
	_renderer.call("set_action_previews", previews)


func _previews_for_entity(entity_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if entity_id < 0 or _loaded == null or _loaded.state == null:
		return out
	for queued in _queued_orders_for_entity(entity_id):
		var queued_preview: Dictionary = _preview_for_order(queued)
		if not queued_preview.is_empty():
			out.append(queued_preview)
	if not out.is_empty():
		return out
	var entity: Entity = _loaded.state.get_entity_by_id(entity_id)
	if entity == null:
		return out
	if out.is_empty():
		var shot_target_id: int = _attack_target_for_entity(entity.id)
		if shot_target_id >= 0:
			out.append(
				{"entity_id": entity.id, "kind": "Idle + Shoot", "target_entity_id": shot_target_id}
			)
		elif _will_halt_on_sight(entity.id):
			var visible_enemy_id := _visible_enemy_for_entity(entity)
			out.append(
				{"entity_id": entity.id, "kind": "Halted", "target_entity_id": visible_enemy_id}
			)
	if entity.focus_target_entity_id >= 0:
		(
			out
			. append(
				{
					"entity_id": entity.id,
					"kind": "Target",
					"target_entity_id": entity.focus_target_entity_id,
				}
			)
		)
	if (
		entity.gather_state != null
		and entity.gather_state.phase != GatherState.Phase.IDLE
		and entity.gather_state.assigned_source_entity_id >= 0
	):
		(
			out
			. append(
				{
					"entity_id": entity.id,
					"kind": "Gather",
					"target_entity_id": entity.gather_state.assigned_source_entity_id,
				}
			)
		)
	return out


func _queued_orders_for_entity(entity_id: int) -> Array[EntityOrder]:
	var out: Array[EntityOrder] = []
	var submit: SubmitTurn = _input.submit_for_player(_input.active_player_id())
	for order in submit.orders:
		if order != null and order.entity_id == entity_id:
			out.append(order)
	return out


func _preview_for_order(order: EntityOrder) -> Dictionary:
	if order == null:
		return {}
	match order.type:
		EntityOrder.Type.MOVE:
			var kind: String = "Attack and Move"
			if _will_halt_on_sight(order.entity_id):
				kind = (
					"Shoot + Hold" if _attack_target_for_entity(order.entity_id) >= 0 else "Halted"
				)
			elif _attack_target_for_entity(order.entity_id) >= 0:
				kind = "Shoot + Move"
			return {"entity_id": order.entity_id, "kind": kind, "target_tile": order.target_tile}
		EntityOrder.Type.MOVE_ONLY:
			return {
				"entity_id": order.entity_id, "kind": "Move Only", "target_tile": order.target_tile
			}
		EntityOrder.Type.ATTACK:
			var target_id := -1
			if not order.target_priority_chain.is_empty():
				target_id = order.target_priority_chain[0]
			return {"entity_id": order.entity_id, "kind": "Target", "target_entity_id": target_id}
		EntityOrder.Type.GATHER:
			return {
				"entity_id": order.entity_id,
				"kind": "Gather",
				"target_entity_id": order.target_entity_id,
			}
		EntityOrder.Type.BUILD:
			return {
				"entity_id": order.entity_id,
				"kind": "Build",
				"target_tile": order.target_tile,
				"def_id": order.def_id,
			}
		EntityOrder.Type.TRAIN:
			return {"entity_id": order.entity_id, "kind": "Train", "def_id": order.def_id}
		EntityOrder.Type.RESEARCH:
			return {"entity_id": order.entity_id, "kind": "Research", "def_id": order.def_id}
		EntityOrder.Type.USE_ABILITY:
			return {"entity_id": order.entity_id, "kind": "Ability", "def_id": order.def_id}
		_:
			return {}


func _attack_target_for_entity(entity_id: int) -> int:
	if _loaded == null or _loaded.state == null or _loaded.registry == null:
		return -1
	var actor := _loaded.state.get_entity_by_id(entity_id)
	if not _can_preview_attack(actor):
		return -1
	var def := _loaded.registry.get_by_id(
		actor.current_def_id if actor.current_def_id != "" else actor.def_id
	)
	if def == null or def.combat == null:
		return -1
	if actor.focus_target_entity_id >= 0:
		var focus := _loaded.state.get_entity_by_id(actor.focus_target_entity_id)
		if _is_attack_target_in_range(actor, focus, def.combat):
			return focus.id
	var closest_id := -1
	var closest_dist := -1
	for candidate in _loaded.state.entities_sorted_by_id():
		if not _is_attack_target_in_range(actor, candidate, def.combat):
			continue
		var dist := _entity_distance(actor, candidate)
		if closest_id < 0 or dist < closest_dist:
			closest_id = candidate.id
			closest_dist = dist
	return closest_id


func _will_halt_on_sight(entity_id: int) -> bool:
	if _loaded == null or _loaded.state == null or _loaded.registry == null:
		return false
	var actor := _loaded.state.get_entity_by_id(entity_id)
	if not _can_preview_attack(actor) or not actor.halt_on_sight:
		return false
	return _visible_enemy_for_entity(actor) >= 0


func _can_preview_attack(entity: Entity) -> bool:
	if entity == null or entity.current_hp <= 0:
		return false
	if entity.ability_cast != null:
		return false
	if entity.gather_state != null and entity.gather_state.phase != GatherState.Phase.IDLE:
		return false
	if entity.locked_to_building_id >= 0 or entity.is_constructing:
		return false
	return true


func _visible_enemy_for_entity(actor: Entity) -> int:
	if actor == null or _loaded == null or _loaded.state == null or _loaded.registry == null:
		return -1
	var visibility := VisionSystem.compute_player_visibility(
		_loaded.state, _loaded.registry, actor.owner_player_id
	)
	for candidate in _loaded.state.entities_sorted_by_id():
		if candidate == null or candidate.current_hp <= 0:
			continue
		if candidate.owner_player_id < 0 or candidate.owner_player_id == actor.owner_player_id:
			continue
		if VisionSystem.is_entity_visible_to_player(
			candidate, _loaded.state, _loaded.registry, actor.owner_player_id, visibility
		):
			return candidate.id
	return -1


func _is_attack_target_in_range(actor: Entity, target: Entity, combat: CombatDef) -> bool:
	if actor == null or target == null or combat == null:
		return false
	if target.id == actor.id or target.current_hp <= 0:
		return false
	if target.owner_player_id < 0 or target.owner_player_id == actor.owner_player_id:
		return false
	if not combat.target_layers.has(target.current_layer):
		return false
	var dist := _entity_distance(actor, target)
	return dist >= 0 and dist <= combat.attack_range


func _entity_distance(a: Entity, b: Entity) -> int:
	if _loaded == null or _loaded.state == null or _loaded.registry == null:
		return -1
	var a_rect := _entity_rect(a)
	var b_rect := _entity_rect(b)
	if a_rect.size == Vector2i.ZERO or b_rect.size == Vector2i.ZERO:
		return -1
	return TileGrid.distance_between_rects(a_rect, b_rect)


func _entity_rect(entity: Entity) -> Rect2i:
	if entity == null or _loaded == null or _loaded.state == null or _loaded.registry == null:
		return Rect2i()
	if _loaded.state.tile_grid != null:
		var rect := _loaded.state.tile_grid.entity_rect(entity.id)
		if rect.size != Vector2i.ZERO:
			return rect
	var def := _loaded.registry.get_by_id(
		entity.current_def_id if entity.current_def_id != "" else entity.def_id
	)
	if def == null:
		return Rect2i()
	return Rect2i(entity.origin, def.footprint)


func _build_options(ids: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids:
		var def_id: String = id
		(
			out
			. append(
				{
					"id": def_id,
					"label": _input.label_for_entity_def_id_with_cost(def_id),
					"disabled": not _input.can_afford_build(def_id),
				}
			)
		)
	return out


func _entity_options(ids: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids:
		var def_id: String = id
		out.append({"id": def_id, "label": _input.label_for_entity_def_id_with_cost(def_id)})
	return out


func _research_options(ids: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids:
		var research_id: String = id
		out.append(
			{"id": research_id, "label": _input.label_for_research_id_with_cost(research_id)}
		)
	return out


func _ability_options(ids: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids:
		var ability_id: String = id
		out.append({"id": ability_id, "label": _input.label_for_ability_id(ability_id)})
	return out
