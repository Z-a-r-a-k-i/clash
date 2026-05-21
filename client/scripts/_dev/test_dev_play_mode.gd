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
		[
			"dev_play_mode_command_card_hides_when_not_actionable",
			_test_command_card_hides_when_not_actionable
		],
		["dev_play_mode_command_card_shows_costs", _test_command_card_shows_costs],
		[
			"dev_play_mode_worker_gather_command_targets_resource",
			_test_worker_gather_command_targets_resource
		],
		[
			"dev_play_mode_affordable_build_interrupts_auto_gather",
			_test_affordable_build_interrupts_auto_gather
		],
		["dev_play_mode_hud_resources_and_readable_queue", _test_hud_resources_and_readable_queue],
		[
			"dev_play_mode_selected_and_friendly_action_previews",
			_test_selected_and_friendly_action_previews
		],
		["dev_play_mode_routes_command_card_orders", _test_routes_command_card_orders],
		["dev_play_mode_pending_target_targets_enemy", _test_pending_target_targets_enemy],
		["dev_play_mode_left_drag_pans_camera", _test_left_drag_pans_camera],
		["dev_play_mode_hud_anchors_away_from_start_area", _test_hud_anchors_away_from_start_area],
		["dev_play_mode_focuses_active_player_on_switch", _test_focuses_active_player_on_switch],
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
	mode.set_active_player_id(0)
	mode.select_entity_id(1)
	mode.renderer().set_perspective_player_id(1)
	if not mode.issue_context_at_tile(Vector2i(13, 10)):
		push_error("right-clicking visible enemy-occupied tile should queue attack intent")
		_free_mode(mode)
		return false
	var attack_order: EntityOrder = mode.input_model().submit_for_player(0).orders[0]
	if (
		attack_order.type != EntityOrder.Type.ATTACK
		or attack_order.target_priority_chain != [4]
		or attack_order.target_tile != Vector2i.ZERO
	):
		push_error("context enemy action should set target focus on #4")
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


func _test_command_card_hides_when_not_actionable() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var card: Control = mode.command_card()
	if card == null:
		push_error("expected command card to exist")
		_free_mode(mode)
		return false
	var ok: bool = true
	if card.visible:
		push_error("command card should be hidden while nothing actionable is selected")
		ok = false
	mode.set_active_player_id(0)
	var mineral_id: int = _find_entity_id_any_hp(mode.current_state(), "mineral_patch", -1)
	if mineral_id < 0 or mode.select_entity_id(mineral_id):
		push_error("neutral mineral should not become an actionable selection")
		ok = false
	if card.visible:
		push_error("command card should stay hidden after selecting a non-owned target")
		ok = false
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a P0 worker")
		ok = false
	if not card.visible:
		push_error("command card should become visible for an actionable worker")
		ok = false
	if _find_label_with_substring(card, "#") != null:
		push_error("command card should not expose debug entity ids")
		ok = false
	_free_mode(mode)
	return ok


func _test_command_card_shows_costs() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var card: Control = mode.command_card()
	if card == null:
		push_error("expected command card")
		_free_mode(mode)
		return false

	var ok: bool = true
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a worker")
		ok = false
	else:
		var barracks_button: Button = _find_button_with_substring(card, "Barracks")
		if barracks_button == null:
			push_error("worker command card should show Barracks")
			ok = false
		elif not _button_text_has_all(barracks_button, _entity_cost_parts("barracks")):
			push_error(
				"Barracks button should show mineral cost and build time: %s" % barracks_button.text
			)
			ok = false
		elif not barracks_button.disabled:
			push_error("Barracks button should be disabled until P0 can pay 150M")
			ok = false
		mode.current_state().get_player(0).minerals = 150
		mode.select_entity_id(worker_id)
		barracks_button = _find_button_with_substring(card, "Barracks")
		if barracks_button == null or barracks_button.disabled:
			push_error("Barracks button should enable once P0 can pay 150M")
			ok = false

	var base_id: int = _find_entity_id(mode.current_state(), "base", 0)
	if base_id < 0 or not mode.select_entity_id(base_id):
		push_error("expected to select a base")
		ok = false
	else:
		var worker_button: Button = _find_button_with_substring(card, "Worker")
		if worker_button == null:
			push_error("base command card should show Worker")
			ok = false
		elif not _button_text_has_all(worker_button, _entity_cost_parts("worker")):
			push_error(
				"Worker button should show mineral, pop, and train time: %s" % worker_button.text
			)
			ok = false

	var barracks_id: int = _add_runtime_entity(mode.current_state(), "barracks", 0, Vector2i(16, 2))
	if barracks_id < 0 or not mode.select_entity_id(barracks_id):
		push_error("expected to select injected barracks")
		ok = false
	else:
		var marine_button: Button = _find_button_with_substring(card, "Marine")
		if marine_button == null:
			push_error("barracks command card should show Marine")
			ok = false
		elif not _button_text_has_all(marine_button, _entity_cost_parts("marine")):
			push_error(
				"Marine button should show mineral, pop, and train time: %s" % marine_button.text
			)
			ok = false
		var stim_button: Button = _find_button_with_substring(card, "Stim Pack")
		if stim_button == null:
			push_error("barracks command card should show Stim Pack")
			ok = false
		elif not _button_text_has_all(stim_button, _research_cost_parts("stim_research")):
			push_error(
				"Stim Pack button should show mineral cost and research time: %s" % stim_button.text
			)
			ok = false

	_free_mode(mode)
	return ok


func _test_worker_gather_command_targets_resource() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	var mineral_id: int = _find_entity_id_any_hp(mode.current_state(), "mineral_patch", -1)
	if worker_id < 0 or mineral_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected worker and mineral on MVP map")
		_free_mode(mode)
		return false
	var card: Control = mode.command_card()
	if card == null or not card.has_signal("gather_requested"):
		push_error("worker command card should expose gather_requested")
		_free_mode(mode)
		return false
	card.emit_signal("gather_requested")
	if mode.pending_command_kind() != "gather":
		push_error("Gather command should enter pending gather mode")
		_free_mode(mode)
		return false
	var mineral: Entity = mode.current_state().get_entity_by_id(mineral_id)
	if mineral == null or not mode.confirm_pending_at_tile(mineral.origin):
		push_error("pending gather should accept a mineral target tile")
		_free_mode(mode)
		return false
	var orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	var ok := true
	if orders.size() != 1:
		push_error("expected one GATHER order, got %d" % orders.size())
		ok = false
	elif orders[0].type != EntityOrder.Type.GATHER or orders[0].target_entity_id != mineral_id:
		push_error("expected GATHER targeting mineral #%d" % mineral_id)
		ok = false
	if mode.pending_command_kind() != "":
		push_error("successful gather target should clear pending mode")
		ok = false
	_free_mode(mode)
	return ok


func _test_affordable_build_interrupts_auto_gather() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	mode.current_state().get_player(0).minerals = 200
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select an auto-gathering P0 worker")
		_free_mode(mode)
		return false
	var worker_before: Entity = mode.current_state().get_entity_by_id(worker_id)
	if (
		worker_before.gather_state == null
		or worker_before.gather_state.phase == GatherState.Phase.IDLE
	):
		push_error("setup expected worker to start auto-gathering")
		_free_mode(mode)
		return false
	mode.begin_build("barracks")
	if mode.pending_command_kind() != "build":
		push_error("affordable barracks should enter pending build mode")
		_free_mode(mode)
		return false
	if not mode.confirm_pending_at_tile(Vector2i(16, 12)):
		push_error("affordable build on clear tile should queue BUILD")
		_free_mode(mode)
		return false
	if not mode.resolve_turn():
		push_error("resolve_turn should process queued BUILD")
		_free_mode(mode)
		return false
	var worker_after: Entity = mode.current_state().get_entity_by_id(worker_id)
	if worker_after == null or worker_after.locked_to_building_id < 0:
		push_error("BUILD should lock the worker to the new building")
		_free_mode(mode)
		return false
	if (
		worker_after.gather_state == null
		or worker_after.gather_state.phase != GatherState.Phase.IDLE
	):
		push_error("BUILD should interrupt auto-gathering")
		_free_mode(mode)
		return false
	if worker_after.gather_state.assigned_source_entity_id != -1:
		push_error("BUILD should clear the prior mineral assignment")
		_free_mode(mode)
		return false
	var building: Entity = mode.current_state().get_entity_by_id(worker_after.locked_to_building_id)
	if building == null or building.def_id != "barracks" or not building.is_constructing:
		push_error("BUILD should create a constructing barracks")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_hud_resources_and_readable_queue() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var p0: PlayerState = mode.current_state().get_player(0)
	var ok := true
	var resources_label := mode.get_node_or_null("DevHUD/Panel/Root/Resources") as Label
	if resources_label == null:
		push_error("HUD should expose a named Resources label")
		ok = false
	elif (
		resources_label.text.find("Minerals: %d" % p0.minerals) == -1
		or resources_label.text.find("Gas: %d" % p0.gas) == -1
		or resources_label.text.find("Pop: %d/%d" % [p0.pop_used, p0.pop_cap]) == -1
	):
		push_error("resources label missing current player economy: %s" % resources_label.text)
		ok = false
	var queue_label := mode.get_node_or_null("DevHUD/Panel/Root/QueuedOrders") as Label
	if queue_label == null:
		push_error("HUD should expose a named QueuedOrders label")
		ok = false
	elif queue_label.visible:
		push_error("queued-order label should be hidden while active player has no queued orders")
		ok = false
	var selected_label := mode.get_node_or_null("DevHUD/Panel/Root/Selected") as Label
	if selected_label != null and selected_label.visible:
		push_error("debug selected label should not be visible in the playtest HUD")
		ok = false
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select worker")
		ok = false
	elif not mode.issue_move_selected(Vector2i(13, 22)):
		push_error("expected worker move to queue")
		ok = false
	elif (
		queue_label != null
		and (
			not queue_label.visible
			or queue_label.text != "Queued this turn: 1 action"
			or queue_label.text.find("P0=") != -1
		)
	):
		push_error(
			"queued-order label should be active-player readable, got: %s" % queue_label.text
		)
		ok = false
	_free_mode(mode)
	return ok


func _test_selected_and_friendly_action_previews() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	if renderer == null:
		push_error("expected renderer")
		_free_mode(mode)
		return false
	for method in ["set_action_previews", "action_preview_count"]:
		if not renderer.has_method(method):
			push_error("renderer should expose %s" % method)
			_free_mode(mode)
			return false
	mode.set_active_player_id(0)
	var workers: Array[int] = _find_entity_ids(mode.current_state(), "worker", 0)
	if workers.size() < 2:
		push_error("expected multiple P0 workers on MVP map")
		_free_mode(mode)
		return false
	if not mode.select_entity_id(workers[0]) or not mode.issue_move_selected(Vector2i(13, 22)):
		push_error("expected first worker move preview")
		_free_mode(mode)
		return false
	if renderer.call("action_preview_count") != 1:
		push_error("selected queued action should always show one preview")
		_free_mode(mode)
		return false
	if not mode.select_entity_id(workers[1]) or not mode.issue_move_selected(Vector2i(13, 25)):
		push_error("expected second worker move preview")
		_free_mode(mode)
		return false
	if renderer.call("action_preview_count") != 1:
		push_error("all-friendly previews should be off by default")
		_free_mode(mode)
		return false
	if not mode.has_method("set_show_all_friendly_action_previews"):
		push_error("dev play mode should expose all-friendly preview toggle")
		_free_mode(mode)
		return false
	mode.call("set_show_all_friendly_action_previews", true)
	var expected_previews: int = workers.size()
	if renderer.call("action_preview_count") != expected_previews:
		push_error(
			(
				"all-friendly preview toggle should show one preview per active worker, got %d expected %d"
				% [renderer.call("action_preview_count"), expected_previews]
			)
		)
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
	card.emit_signal("move_requested")
	if mode.pending_command_kind() != "move":
		push_error("move signal should enter pending move mode")
		_free_mode(mode)
		return false
	if not mode.confirm_pending_at_tile(Vector2i(9, 22)):
		push_error("pending move click should queue MOVE")
		_free_mode(mode)
		return false
	var move_order: EntityOrder = mode.input_model().submit_for_player(0).orders[0]
	if move_order.type != EntityOrder.Type.MOVE:
		push_error("expected MOVE after pending click")
		_free_mode(mode)
		return false
	mode.input_model().clear_submissions()
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		push_error("expected combat scenario reload for target command")
		_free_mode(mode)
		return false
	card = mode.command_card()
	if card == null:
		push_error("expected command card after combat scenario reload")
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	if not mode.select_entity_id(1):
		push_error("expected P0 marine #1 to be selectable")
		_free_mode(mode)
		return false
	card.emit_signal("target_requested")
	if mode.pending_command_kind() != "target":
		push_error("target signal should enter pending target mode")
		_free_mode(mode)
		return false
	mode.renderer().set_perspective_player_id(1)
	if not mode.confirm_pending_at_tile(Vector2i(13, 10)):
		push_error("pending target click should queue ATTACK focus")
		_free_mode(mode)
		return false
	var target_order: EntityOrder = mode.input_model().submit_for_player(0).orders[0]
	if (
		target_order.type != EntityOrder.Type.ATTACK
		or target_order.target_priority_chain.is_empty()
	):
		push_error("expected ATTACK focus after pending target click")
		_free_mode(mode)
		return false
	card.emit_signal("move_only_requested")
	if mode.pending_command_kind() != "move_only":
		push_error("Move Only signal should enter pending move_only mode")
		_free_mode(mode)
		return false
	if not mode.confirm_pending_at_tile(Vector2i(8, 10)):
		push_error("pending Move Only click should queue MOVE_ONLY")
		_free_mode(mode)
		return false
	card.emit_signal("halt_on_sight_requested", true)
	card.emit_signal("cancel_requested", -1)
	var orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if orders.size() < 4:
		push_error(
			"expected ATTACK, MOVE_ONLY, HALT_ON_SIGHT_TOGGLE, CANCEL; got %d" % orders.size()
		)
		_free_mode(mode)
		return false
	if orders[1].type != EntityOrder.Type.MOVE_ONLY:
		push_error("Move Only signal should queue MOVE_ONLY")
		_free_mode(mode)
		return false
	if orders[2].type != EntityOrder.Type.HALT_ON_SIGHT_TOGGLE or not orders[2].halt_on_sight:
		push_error("halt-on-sight signal should queue HALT_ON_SIGHT_TOGGLE(true)")
		_free_mode(mode)
		return false
	if orders[3].type != EntityOrder.Type.CANCEL or orders[3].cancel_index != -1:
		push_error("cancel signal should queue CANCEL(-1)")
		_free_mode(mode)
		return false
	mode.input_model().clear_submissions()
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		push_error("expected mvp scenario reload for build commands")
		_free_mode(mode)
		return false
	card = mode.command_card()
	if card == null:
		push_error("expected command card after mvp scenario reload")
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	worker_id = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to reselect P0 worker on mvp_map")
		_free_mode(mode)
		return false
	mode.current_state().get_player(0).minerals = 150
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


func _test_pending_target_targets_enemy() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	if not mode.select_entity_id(1):
		push_error("expected to select P0 marine #1")
		_free_mode(mode)
		return false
	var card: Control = mode.command_card()
	card.emit_signal("target_requested")
	mode.renderer().set_perspective_player_id(1)
	if not mode.confirm_pending_at_tile(Vector2i(13, 10)):
		push_error("pending target click on enemy should queue targeted intent")
		_free_mode(mode)
		return false
	var order: EntityOrder = mode.input_model().submit_for_player(0).orders[0]
	if (
		order.type != EntityOrder.Type.ATTACK
		or order.target_priority_chain != [4]
		or order.target_tile != Vector2i.ZERO
	):
		push_error("pending enemy click should queue ATTACK focus with target chain [4]")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_left_drag_pans_camera() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	if renderer == null:
		push_error("expected renderer")
		_free_mode(mode)
		return false
	var camera := renderer.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		push_error("renderer has no Camera2D")
		_free_mode(mode)
		return false
	var original_position: Vector2 = camera.position
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, true, Vector2(8.0, 8.0)))
	mode.call("_unhandled_input", _mouse_motion(Vector2(96.0, 0.0), MOUSE_BUTTON_MASK_LEFT))
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, false, Vector2(104.0, 8.0)))
	var ok := true
	if camera.position == original_position:
		push_error("left-dragging empty map space should pan the camera")
		ok = false
	if mode.pending_command_kind() != "":
		push_error("camera drag should not leave a pending command")
		ok = false
	_free_mode(mode)
	return ok


func _test_hud_anchors_away_from_start_area() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var panel := mode.get_node_or_null("DevHUD/Panel") as Control
	if panel == null:
		push_error("expected dev HUD panel at DevHUD/Panel")
		_free_mode(mode)
		return false
	var ok := true
	if panel.anchor_left < 0.95 or panel.anchor_right < 0.95:
		push_error(
			(
				"dev HUD panel should be anchored to the right, got anchors %f..%f"
				% [panel.anchor_left, panel.anchor_right]
			)
		)
		ok = false
	if panel.offset_left >= 0.0 or panel.offset_right > -8.0:
		push_error(
			(
				"right-anchored HUD should use negative right-side offsets, got %s..%s"
				% [str(panel.offset_left), str(panel.offset_right)]
			)
		)
		ok = false
	_free_mode(mode)
	return ok


func _test_focuses_active_player_on_switch() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	if renderer == null:
		push_error("expected renderer")
		_free_mode(mode)
		return false
	if not renderer.has_method("focus_player_start"):
		push_error("renderer should expose focus_player_start for player switching")
		_free_mode(mode)
		return false
	var camera := renderer.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		push_error("renderer has no Camera2D")
		_free_mode(mode)
		return false
	var p0_position: Vector2 = camera.position
	mode.set_active_player_id(1)
	var p1_position: Vector2 = camera.position
	var ok := true
	if p0_position.distance_to(p1_position) < 128.0:
		push_error(
			(
				"switching player should refocus camera; positions were %s and %s"
				% [str(p0_position), str(p1_position)]
			)
		)
		ok = false
	if renderer.call("perspective_player_id") != 1:
		push_error("switching player should still update renderer perspective")
		ok = false
	_free_mode(mode)
	return ok


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


func _find_entity_id_any_hp(state: MatchState, def_id: String, owner: int) -> int:
	if state == null:
		return -1
	for entity in state.entities_sorted_by_id():
		if entity.def_id == def_id and entity.owner_player_id == owner:
			return entity.id
	return -1


func _find_entity_ids(state: MatchState, def_id: String, owner: int) -> Array[int]:
	var out: Array[int] = []
	if state == null:
		return out
	for entity in state.entities_sorted_by_id():
		if entity.def_id == def_id and entity.owner_player_id == owner and entity.current_hp > 0:
			out.append(entity.id)
	return out


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
	var registry: EntityRegistry = _load_registry()
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


func _find_label_with_substring(root: Node, needle: String) -> Label:
	if root == null:
		return null
	if root is Label:
		var label: Label = root as Label
		if label.text.find(needle) != -1:
			return label
	for child in root.get_children():
		var found: Label = _find_label_with_substring(child, needle)
		if found != null:
			return found
	return null


func _find_button_with_substring(root: Node, needle: String) -> Button:
	if root == null:
		return null
	if root is Button:
		var button: Button = root as Button
		if button.text.find(needle) != -1:
			return button
	for child in root.get_children():
		var found: Button = _find_button_with_substring(child, needle)
		if found != null:
			return found
	return null


func _button_text_has_all(button: Button, needles: Array[String]) -> bool:
	if button == null:
		return false
	for needle in needles:
		if button.text.find(needle) == -1:
			return false
	return true


func _entity_cost_parts(def_id: String) -> Array[String]:
	var parts: Array[String] = []
	var registry: EntityRegistry = _load_registry()
	var def: EntityDef = registry.get_by_id(def_id) if registry != null else null
	if def == null or def.construction == null:
		return parts
	parts.append("%dM" % def.construction.mineral_cost)
	if def.construction.gas_cost > 0:
		parts.append("%dG" % def.construction.gas_cost)
	if def.population != null and def.population.pop_cost > 0:
		parts.append("%dP" % def.population.pop_cost)
	parts.append("%dT" % def.construction.build_time_turns)
	return parts


func _research_cost_parts(research_id: String) -> Array[String]:
	var parts: Array[String] = []
	var registry: EntityRegistry = _load_registry()
	var research: ResearchDef = (
		registry.get_research_by_id(research_id) if registry != null else null
	)
	if research == null:
		return parts
	parts.append("%dM" % research.mineral_cost)
	if research.gas_cost > 0:
		parts.append("%dG" % research.gas_cost)
	parts.append("%dT" % research.research_time_turns)
	return parts


func _load_registry() -> EntityRegistry:
	return load("res://data/entity_registry.tres") as EntityRegistry


func _mouse_button(
	button_index: MouseButton, pressed: bool, position: Vector2
) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	event.position = position
	return event


func _mouse_motion(relative: Vector2, button_mask: MouseButtonMask) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.button_mask = button_mask
	return event


func _free_mode(mode: Node) -> void:
	if mode == null:
		return
	if mode.is_inside_tree():
		remove_child(mode)
	mode.queue_free()
