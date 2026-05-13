@tool
extends Node

const DEV_PLAY_MODE_PATH := "res://scripts/_dev/dev_play_mode.gd"
const COMBAT_SCENARIO_PATH := "res://data/scenarios/combat_marines_vs_tanks.tres"


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
	var ok := true
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


func _make_mode() -> Node:
	var script: Script = load(DEV_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % DEV_PLAY_MODE_PATH)
		return null
	return script.new()


func _free_mode(mode: Node) -> void:
	if mode == null:
		return
	if mode.is_inside_tree():
		remove_child(mode)
	mode.queue_free()
