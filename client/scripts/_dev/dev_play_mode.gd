class_name DevPlayMode
extends Node

const DEFAULT_SCENARIO_PATH := "res://data/scenarios/mvp_map.tres"
const MATCH_SCENE_PATH := "res://scenes/match.tscn"
const REGISTRY_PATH := "res://data/entity_registry.tres"
const TUNABLES_PATH := "res://data/tunables.tres"
const DEV_TURN_INPUT_SCRIPT := preload("res://scripts/game/dev_turn_input.gd")

@export_file("*.tres") var scenario_path: String = DEFAULT_SCENARIO_PATH

var _renderer: MatchRenderer = null
var _loaded: LoadedScenario = null
var _tunables: Tunables = null
var _input: DevTurnInput = DEV_TURN_INPUT_SCRIPT.new() as DevTurnInput
var _hud_layer: CanvasLayer = null
var _active_label: Label = null
var _selected_label: Label = null
var _queue_label: Label = null
var _status_label: Label = null


func _ready() -> void:
	_build_hud()
	if _loaded == null:
		load_scenario_path(scenario_path)


func load_scenario_path(path: String) -> bool:
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
	_ensure_renderer()
	if _renderer == null:
		return false
	_renderer.bind_state(_loaded.state, _loaded.registry)
	_input.bind_context(_loaded.state, _loaded.registry)
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


func set_active_player_id(player_id: int) -> void:
	_input.set_active_player_id(player_id)
	if _renderer != null:
		_renderer.clear_input_highlights()
	_update_hud()


func select_entity_id(entity_id: int) -> bool:
	var ok: bool = _input.select_entity(entity_id)
	if _renderer != null:
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


func issue_attack_selected(target_entity_id: int) -> bool:
	var ok: bool = _input.issue_attack(target_entity_id)
	_update_hud()
	return ok


func issue_gather_selected(target_entity_id: int) -> bool:
	var ok: bool = _input.issue_gather(target_entity_id)
	_update_hud()
	return ok


func issue_context_at_tile(tile: Vector2i) -> bool:
	if _loaded == null or _loaded.state == null or _loaded.state.tile_grid == null:
		return false
	var target_id: int = _loaded.state.tile_grid.entity_at(tile)
	if target_id >= 0:
		var target: Entity = _loaded.state.get_entity_by_id(target_id)
		if target != null and target.owner_player_id >= 0:
			if target.owner_player_id != _input.active_player_id():
				return issue_attack_selected(target_id)
			return false
		if _is_gather_target(target):
			return issue_gather_selected(target_id)
	return issue_move_selected(tile)


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
	if _renderer != null:
		_renderer.render_step(result.new_state, result.events)
		_renderer.clear_input_highlights()
	_input.bind_context(_loaded.state, _loaded.registry)
	_input.clear_submissions()
	_update_hud("Resolved turn %d." % _loaded.state.turn_index)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if _renderer == null or _loaded == null:
		return
	if event is InputEventMouseMotion:
		var hover_tile: Vector2i = _renderer.world_to_tile(_renderer.get_global_mouse_position())
		_renderer.set_hover_tile(hover_tile)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if not button.pressed:
			return
		var tile: Vector2i = _renderer.world_to_tile(_renderer.get_global_mouse_position())
		var entity_id: int = _renderer.entity_id_at_tile(tile)
		if button.button_index == MOUSE_BUTTON_LEFT:
			if entity_id >= 0:
				select_entity_id(entity_id)
			else:
				_input.clear_selection()
				_renderer.clear_input_highlights()
				_update_hud("Selection cleared.")
		elif button.button_index == MOUSE_BUTTON_RIGHT:
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


func _build_hud() -> void:
	if _hud_layer != null:
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "DevHUD"
	add_child(_hud_layer)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.offset_left = 12.0
	panel.offset_top = 12.0
	panel.offset_right = 360.0
	panel.offset_bottom = 188.0
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

	_active_label = Label.new()
	root.add_child(_active_label)
	_selected_label = Label.new()
	root.add_child(_selected_label)
	_queue_label = Label.new()
	root.add_child(_queue_label)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)
	_update_hud()


func _button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	return button


func _clear_queues_from_hud() -> void:
	_input.clear_submissions()
	_update_hud()


func _surrender_from_hud() -> void:
	_input.surrender_active_player()
	_update_hud()


func _update_hud(override_status: String = "") -> void:
	if _active_label != null:
		_active_label.text = "Active player: P%d" % _input.active_player_id()
	if _selected_label != null:
		var selected: int = _input.selected_entity_id()
		_selected_label.text = "Selected: #%d" % selected if selected >= 0 else "Selected: none"
	if _queue_label != null:
		_queue_label.text = (
			"Queues: P0=%d P1=%d"
			% [
				_input.queued_order_count(0),
				_input.queued_order_count(1),
			]
		)
	if _status_label != null:
		_status_label.text = override_status if override_status != "" else _input.status_message()


func _is_gather_target(entity: Entity) -> bool:
	if entity == null or _loaded == null or _loaded.registry == null:
		return false
	var def_id: String = entity.current_def_id if entity.current_def_id != "" else entity.def_id
	var def: EntityDef = _loaded.registry.get_by_id(def_id)
	if def == null:
		return false
	return def.resource_source != null or def.tags.has("refinery")
