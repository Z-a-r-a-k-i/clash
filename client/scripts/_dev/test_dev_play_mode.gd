@tool
extends Node

const DEV_PLAY_MODE_PATH := "res://scripts/_dev/dev_play_mode.gd"
const COMBAT_SCENARIO_PATH := "res://data/scenarios/combat_marines_vs_tanks.tres"
const MVP_SCENARIO_PATH := "res://data/scenarios/mvp_map.tres"


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	_run_all()


func _run_all() -> int:
	var passed := 0
	var failed := 0
	var fail_names: Array[String] = []
	for test_pair in _all_tests():
		var test_name: String = test_pair[0]
		var fn: Callable = test_pair[1]
		var ok: bool = fn.call()
		if ok:
			passed += 1
		else:
			failed += 1
			fail_names.append(test_name)
	print("[test_dev_play_mode] %d passed, %d failed" % [passed, failed])
	for test_name in fail_names:
		push_error("  failed: %s" % test_name)
	return failed


func _all_tests() -> Array:
	return [
		["dev_play_mode_loads_scenario_and_binds_renderer", _test_loads_scenario],
		["dev_play_mode_queues_and_resolves_turn", _test_queues_and_resolves_turn],
		["dev_play_mode_routes_context_actions", _test_routes_context_actions],
		[
			"dev_play_mode_switches_input_and_render_perspective",
			_test_switches_input_and_render_perspective
		],
		["dev_play_mode_command_card_tracks_selection", _test_command_card_tracks_selection],
		["dev_play_mode_routes_command_card_orders", _test_routes_command_card_orders],
	]


func _test_loads_scenario() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	var ok: bool = mode.load_scenario_path(COMBAT_SCENARIO_PATH)
	if not ok:
		push_error("load_scenario_path returned false")
		_free_mode(mode)
		return false
	if mode.current_state() == null or mode.current_state().entities.size() != 4:
		push_error("expected combat scenario to load four entities")
		_free_mode(mode)
		return false
	if mode.renderer() == null or mode.renderer().entity_view_count() != 4:
		push_error("expected renderer to bind four entity views")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_queues_and_resolves_turn() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	if not mode.select_entity_id(1):
		push_error("expected P0 marine #1 to be selectable")
		_free_mode(mode)
		return false
	if not mode.issue_attack_selected(4):
		push_error("expected ATTACK against P1 siege tank #4 to queue")
		_free_mode(mode)
		return false
	if mode.pending_order_count(0) != 1:
		push_error("expected one queued P0 order before resolve")
		_free_mode(mode)
		return false
	if not mode.resolve_turn():
		push_error("resolve_turn returned false")
		_free_mode(mode)
		return false
	if mode.current_state().turn_index != 1:
		push_error("expected turn index 1 after resolve, got %d" % mode.current_state().turn_index)
		_free_mode(mode)
		return false
	if mode.pending_order_count(0) != 0 or mode.pending_order_count(1) != 0:
		push_error("resolve_turn should clear both player queues")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_routes_context_actions() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(1)
	mode.select_entity_id(4)
	if not mode.issue_context_at_tile(Vector2i(5, 10)):
		push_error("right-clicking visible enemy-occupied tile should queue ATTACK")
		_free_mode(mode)
		return false
	var attack_order: EntityOrder = mode.input_model().submit_for_player(1).orders[0]
	if attack_order.type != EntityOrder.Type.ATTACK or attack_order.target_priority_chain != [1]:
		push_error("context enemy action should be ATTACK on #1")
		_free_mode(mode)
		return false
	mode.input_model().clear_submissions()
	mode.set_active_player_id(0)
	mode.select_entity_id(1)
	if not mode.issue_context_at_tile(Vector2i(9, 10)):
		push_error("right-clicking empty tile should queue MOVE")
		_free_mode(mode)
		return false
	var move_order: EntityOrder = mode.input_model().submit_for_player(0).orders[0]
	if move_order.type != EntityOrder.Type.MOVE or move_order.target_tile != Vector2i(9, 10):
		push_error("context empty-tile action should be MOVE to (9, 10)")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_switches_input_and_render_perspective() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	if not mode.select_entity_id(1):
		push_error("expected P0 marine #1 to be selectable")
		_free_mode(mode)
		return false
	mode.set_active_player_id(1)
	var ok: bool = true
	if mode.input_model().active_player_id() != 1:
		push_error("input model did not switch to P1")
		ok = false
	if mode.input_model().selected_entity_id() != -1:
		push_error("selection should clear when switching away from owner")
		ok = false
	if mode.renderer().call("perspective_player_id") != 1:
		push_error("renderer perspective should follow active player")
		ok = false
	_free_mode(mode)
	return ok


func _test_command_card_tracks_selection() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a P0 worker on mvp_map")
		_free_mode(mode)
		return false
	var card: Control = mode.command_card()
	if card == null:
		push_error("expected command card to exist")
		_free_mode(mode)
		return false
	if not _command_card_ids(card, "build_option_ids").has("barracks"):
		push_error("worker command card should expose barracks build option")
		_free_mode(mode)
		return false
	mode.set_active_player_id(1)
	if not _command_card_ids(card, "build_option_ids").is_empty():
		push_error("switching player should refresh command card after selection clears")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_routes_command_card_orders() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a P0 worker on mvp_map")
		_free_mode(mode)
		return false
	var card: Control = mode.command_card()
	if card == null:
		push_error("expected command card to exist")
		_free_mode(mode)
		return false
	card.emit_signal("attack_move_requested")
	if mode.pending_command_kind() != "attack_move":
		push_error("attack-move signal should enter pending attack_move mode")
		_free_mode(mode)
		return false
	if not mode.confirm_pending_at_tile(Vector2i(9, 22)):
		push_error("pending attack-move click should queue ATTACK_MOVE")
		_free_mode(mode)
		return false
	var attack_move: EntityOrder = mode.input_model().submit_for_player(0).orders[0]
	if attack_move.type != EntityOrder.Type.ATTACK_MOVE:
		push_error("expected ATTACK_MOVE after pending click")
		_free_mode(mode)
		return false
	card.emit_signal("hold_fire_requested", true)
	card.emit_signal("cancel_requested", -1)
	var orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if orders[1].type != EntityOrder.Type.HOLD_FIRE_TOGGLE or not orders[1].hold_fire:
		push_error("hold-fire signal should queue HOLD_FIRE_TOGGLE(true)")
		_free_mode(mode)
		return false
	if orders[2].type != EntityOrder.Type.CANCEL or orders[2].cancel_index != -1:
		push_error("cancel signal should queue CANCEL(-1)")
		_free_mode(mode)
		return false
	mode.input_model().clear_submissions()
	card.emit_signal("build_requested", "barracks")
	if mode.pending_command_kind() != "build":
		push_error("build signal should enter pending build mode")
		_free_mode(mode)
		return false
	if not mode.confirm_pending_at_tile(Vector2i(12, 2)):
		push_error("pending build click should queue BUILD")
		_free_mode(mode)
		return false
	var build: EntityOrder = mode.input_model().submit_for_player(0).orders[0]
	if build.type != EntityOrder.Type.BUILD or build.def_id != "barracks":
		push_error("expected BUILD barracks after pending click")
		_free_mode(mode)
		return false
	mode.input_model().clear_submissions()
	var barracks_id: int = _add_runtime_entity(mode.current_state(), "barracks", 0, Vector2i(16, 2))
	if barracks_id < 0 or not mode.select_entity_id(barracks_id):
		push_error("expected to select injected barracks")
		_free_mode(mode)
		return false
	card.emit_signal("train_requested", "marine")
	card.emit_signal("research_requested", "stim_research")
	orders = mode.input_model().submit_for_player(0).orders
	if orders[0].type != EntityOrder.Type.TRAIN or orders[0].def_id != "marine":
		push_error("train signal should queue TRAIN marine")
		_free_mode(mode)
		return false
	if orders[1].type != EntityOrder.Type.RESEARCH or orders[1].def_id != "stim_research":
		push_error("research signal should queue RESEARCH stim_research")
		_free_mode(mode)
		return false
	mode.input_model().clear_submissions()
	mode.current_state().get_player(0).unlocked_researches.append("stim_research")
	var marine_id: int = _add_runtime_entity(mode.current_state(), "marine", 0, Vector2i(21, 2))
	if marine_id < 0 or not mode.select_entity_id(marine_id):
		push_error("expected to select injected marine")
		_free_mode(mode)
		return false
	if not _command_card_ids(card, "ability_option_ids").has("stim"):
		push_error("marine command card should expose stim ability")
		_free_mode(mode)
		return false
	card.emit_signal("ability_requested", "stim")
	orders = mode.input_model().submit_for_player(0).orders
	if orders[0].type != EntityOrder.Type.USE_ABILITY or orders[0].def_id != "stim":
		push_error("ability signal should queue USE_ABILITY stim")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _make_mode() -> Node:
	var script: Script = load(DEV_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % DEV_PLAY_MODE_PATH)
		return null
	return script.new()


func _find_entity_id(state: MatchState, def_id: String, owner: int) -> int:
	if state == null:
		return -1
	for entity in state.entities_sorted_by_id():
		if entity.def_id == def_id and entity.owner_player_id == owner and entity.current_hp > 0:
			return entity.id
	return -1


func _add_runtime_entity(state: MatchState, def_id: String, owner: int, origin: Vector2i) -> int:
	if state == null or state.tile_grid == null:
		return -1
	var entity: Entity = Entity.new()
	entity.id = state.allocate_entity_id()
	entity.def_id = def_id
	entity.current_def_id = def_id
	entity.owner_player_id = owner
	entity.origin = origin
	entity.current_layer = "ground"
	entity.current_hp = 1000
	var footprint: Vector2i = Vector2i(1, 1)
	var registry: EntityRegistry = load("res://data/entity_registry.tres") as EntityRegistry
	var def: EntityDef = registry.get_by_id(def_id) if registry != null else null
	if def != null:
		footprint = def.footprint
		if def.health != null:
			entity.current_hp = def.health.max_hp
		if def.production != null:
			entity.production_state = ProductionState.new()
	if not state.tile_grid.place(entity.id, Rect2i(origin, footprint)):
		return -1
	state.entities.append(entity)
	return entity.id


func _command_card_ids(card: Control, method_name: String) -> Array[String]:
	var out: Array[String] = []
	var raw: Array = card.call(method_name)
	for item in raw:
		var id: String = item
		out.append(id)
	return out


func _free_mode(mode: Node) -> void:
	if mode == null:
		return
	if mode.is_inside_tree():
		remove_child(mode)
	mode.queue_free()
