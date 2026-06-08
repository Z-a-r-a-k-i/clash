@tool
extends Node

const DEV_PLAY_MODE_PATH := "res://scripts/_dev/dev_play_mode.gd"
const COMMAND_CARD_PATH := "res://scripts/game/command_card.gd"
const COMBAT_SCENARIO_PATH := "res://data/scenarios/combat_marines_vs_tanks.tres"
const MVP_SCENARIO_PATH := "res://data/scenarios/mvp_map.tres"
const TUNABLES_PATH := "res://data/tunables.tres"


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
		["dev_play_mode_context_cursor_classifier", _test_context_cursor_classifier],
		[
			"dev_play_mode_switches_input_and_render_perspective",
			_test_switches_input_and_render_perspective
		],
		["dev_play_mode_command_card_tracks_selection", _test_command_card_tracks_selection],
		[
			"dev_play_mode_command_card_hides_when_not_actionable",
			_test_command_card_hides_when_not_actionable
		],
		[
			"command_card_actions_and_state_changes_are_separate_rows",
			_test_command_card_actions_and_state_changes_are_separate_rows
		],
		[
			"command_card_primary_visibility_tracks_each_command",
			_test_command_card_primary_visibility_tracks_each_command
		],
		["dev_play_mode_command_card_shows_costs", _test_command_card_shows_costs],
		[
			"dev_play_mode_worker_gather_command_targets_resource",
			_test_worker_gather_command_targets_resource
		],
		[
			"dev_play_mode_right_click_gather_rejects_raw_gas",
			_test_right_click_gather_rejects_raw_gas
		],
		["dev_play_mode_producer_right_click_sets_rally", _test_producer_right_click_sets_rally],
		[
			"dev_play_mode_affordable_build_interrupts_auto_gather",
			_test_affordable_build_interrupts_auto_gather
		],
		["dev_play_mode_mvp_worker_builds_refinery", _test_mvp_worker_builds_refinery],
		["dev_play_mode_hud_resources_and_readable_queue", _test_hud_resources_and_readable_queue],
		[
			"dev_play_mode_selected_and_friendly_action_previews",
			_test_selected_and_friendly_action_previews
		],
		[
			"dev_play_mode_gather_and_build_previews_route_around_blockers",
			_test_gather_and_build_previews_route_around_blockers
		],
		["dev_play_mode_shift_click_routes_future_orders", _test_shift_click_routes_future_orders],
		[
			"dev_play_mode_shift_click_routes_future_gather_and_build_orders",
			_test_shift_click_routes_future_gather_and_build_orders
		],
		[
			"dev_play_mode_halt_on_sight_move_preview_does_not_route",
			_test_halt_on_sight_move_preview_does_not_route
		],
		[
			"dev_play_mode_target_chase_preview_tracks_live_target",
			_test_target_chase_preview_tracks_live_target
		],
		[
			"dev_play_mode_pending_build_updates_placement_preview",
			_test_pending_build_updates_placement_preview
		],
		[
			"dev_play_mode_requeues_unfinished_move_after_resolve",
			_test_requeues_unfinished_move_after_resolve
		],
		[
			"dev_play_mode_tied_same_target_move_completes_for_future_queue",
			_test_tied_same_target_move_completes_for_future_queue
		],
		["dev_play_mode_routes_command_card_orders", _test_routes_command_card_orders],
		["dev_play_mode_pending_target_targets_enemy", _test_pending_target_targets_enemy],
		["dev_play_mode_a_key_attack_move_mode", _test_a_key_attack_move_mode],
		["dev_play_mode_left_drag_pans_camera", _test_left_drag_pans_camera],
		["dev_play_mode_hud_anchors_away_from_start_area", _test_hud_anchors_away_from_start_area],
		[
			"dev_play_mode_switching_player_keeps_camera_bounded",
			_test_switching_player_keeps_camera_bounded
		],
		["dev_play_mode_hud_omits_resolution_button", _test_hud_omits_resolution_button],
		["dev_play_mode_hud_separates_replay_controls", _test_hud_separates_replay_controls],
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
	var queued_after_resolve: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if (
		queued_after_resolve.size() != 1
		or queued_after_resolve[0].type != EntityOrder.Type.ATTACK
		or queued_after_resolve[0].target_priority_chain != ([4] as Array[int])
		or mode.pending_order_count(1) != 0
	):
		push_error("resolve_turn should requeue the unfinished targeted ATTACK for P0 only")
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
		push_error("right-clicking visible enemy-occupied tile should queue target chase")
		_free_mode(mode)
		return false
	var marine: Entity = mode.current_state().get_entity_by_id(1)
	if marine == null or marine.focus_target_entity_id != -1:
		push_error("context enemy action should not mutate focus before resolve")
		_free_mode(mode)
		return false
	var target_chase_orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if target_chase_orders.size() != 1:
		push_error("context enemy target should queue one atomic order")
		_free_mode(mode)
		return false
	var target_chase: EntityOrder = target_chase_orders[0]
	if (
		target_chase.type != EntityOrder.Type.MOVE
		or target_chase.target_priority_chain != ([4] as Array[int])
		or target_chase.target_tile != Vector2i(13, 10)
	):
		push_error("context enemy action should queue MOVE with target chain for #4")
		_free_mode(mode)
		return false
	mode.input_model().clear_submissions()
	mode.set_active_player_id(0)
	mode.select_entity_id(1)
	if not mode.issue_context_at_tile(Vector2i(9, 10)):
		push_error("right-clicking empty tile should queue MOVE_ONLY")
		_free_mode(mode)
		return false
	var move_order: EntityOrder = mode.input_model().submit_for_player(0).orders[0]
	if move_order.type != EntityOrder.Type.MOVE_ONLY or move_order.target_tile != Vector2i(9, 10):
		push_error("context empty-tile action should be MOVE_ONLY to (9, 10)")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_context_cursor_classifier() -> bool:
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
	var enemy_context: Dictionary = mode.context_action_at_tile(Vector2i(13, 10))
	var ok := true
	if (
		enemy_context.get("action", "") != "target_chase"
		or enemy_context.get("cursor_shape", -1) != Input.CURSOR_CROSS
	):
		push_error("enemy hover should classify as target chase with cross cursor")
		ok = false
	var empty_context: Dictionary = mode.context_action_at_tile(Vector2i(9, 10))
	if (
		empty_context.get("action", "") != "move_only"
		or empty_context.get("cursor_shape", -1) != Input.CURSOR_MOVE
	):
		push_error("empty hover should classify as move-only with move cursor")
		ok = false
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	var mineral_id: int = _find_entity_id_any_hp(mode.current_state(), "mineral_patch", -1)
	if worker_id < 0 or mineral_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected worker and mineral for gather cursor classifier")
		_free_mode(mode)
		return false
	var mineral: Entity = mode.current_state().get_entity_by_id(mineral_id)
	var gather_context: Dictionary = mode.context_action_at_tile(mineral.origin)
	if (
		gather_context.get("action", "") != "gather"
		or gather_context.get("cursor_shape", -1) != Input.CURSOR_POINTING_HAND
	):
		push_error("resource hover should classify as gather with pointing-hand cursor")
		ok = false
	_free_mode(mode)
	return ok


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


func _test_command_card_actions_and_state_changes_are_separate_rows() -> bool:
	var card: Control = _make_command_card()
	if card == null:
		return false
	add_child(card)
	_set_command_card_state(card, true, true, true, true, true, true)
	var move_button: Button = _find_exact_button(card, "Attack and Move")
	var move_only_button: Button = _find_exact_button(card, "Move Only")
	var gather_button: Button = _find_exact_button(card, "Gather")
	var target_button: Button = _find_exact_button(card, "Target")
	var halt_button: Button = _find_exact_button(card, "Halt on Sight: Off")
	var cancel_button: Button = _find_exact_button(card, "Cancel")
	var ok: bool = true
	if (
		move_button == null
		or move_only_button == null
		or gather_button == null
		or target_button == null
		or halt_button == null
		or cancel_button == null
	):
		push_error("command card should expose action and state buttons")
		ok = false
	else:
		var action_parent: Node = move_button.get_parent()
		var state_parent: Node = target_button.get_parent()
		if (
			action_parent != move_only_button.get_parent()
			or action_parent != gather_button.get_parent()
		):
			push_error("Attack and Move, Move Only, and Gather should share the action row")
			ok = false
		if (
			action_parent.get_child(0) != move_only_button
			or action_parent.get_child(1) != move_button
			or action_parent.get_child(2) != gather_button
		):
			push_error("action row should order Move Only before Attack and Move")
			ok = false
		if state_parent != halt_button.get_parent() or state_parent != cancel_button.get_parent():
			push_error("Target, Halt on Sight, and Cancel should share the state row")
			ok = false
		if action_parent == state_parent:
			push_error("actions and state changes should be on separate rows")
			ok = false
		if not action_parent is HBoxContainer or not state_parent is HBoxContainer:
			push_error("action and state rows should be horizontal rows")
			ok = false
		if move_button.size_flags_horizontal != Control.SIZE_EXPAND_FILL:
			push_error("Move button should expand within the action row")
			ok = false
		if move_only_button.size_flags_horizontal != Control.SIZE_EXPAND_FILL:
			push_error("Move Only button should expand within the action row")
			ok = false
	_free_mode(card)
	return ok


func _test_command_card_primary_visibility_tracks_each_command() -> bool:
	var card: Control = _make_command_card()
	if card == null:
		return false
	add_child(card)
	var ok: bool = true
	_set_command_card_state(card, false, false, false, false, false, false)
	if card.visible:
		push_error("command card should hide when no command section has visible actions")
		ok = false

	_set_command_card_state(card, true, true, false, false, false, false)
	if not _expect_button_visibility(card, "Attack and Move", true):
		ok = false
	if not _expect_button_visibility(card, "Move Only", true):
		ok = false
	if not _expect_button_visibility(card, "Gather", false):
		ok = false

	_set_command_card_state(card, true, false, false, false, false, false)
	if not _expect_button_visibility(card, "Attack and Move", true):
		ok = false
	if not _expect_button_visibility(card, "Move Only", false):
		ok = false

	_set_command_card_state(card, false, true, false, false, false, false)
	if not _expect_button_visibility(card, "Attack and Move", false):
		ok = false
	if not _expect_button_visibility(card, "Move Only", true):
		ok = false

	_set_command_card_state(card, false, false, true, true, true, true)
	for label in ["Target", "Halt on Sight: Off", "Gather", "Cancel"]:
		if not _expect_button_visibility(card, label, true):
			ok = false
	if not _expect_button_visibility(card, "Attack and Move", false):
		ok = false
	if not _expect_button_visibility(card, "Move Only", false):
		ok = false
	if not card.visible:
		push_error("command card should show when non-move commands are visible")
		ok = false

	_free_mode(card)
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
		mode.current_state().get_player(0).minerals = 149
		mode.select_entity_id(worker_id)
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
		var repeat_toggle: CheckBox = _find_check_box_with_substring(card, "Repeat Train")
		if repeat_toggle == null or not repeat_toggle.visible:
			push_error("training producer command card should show Repeat Train")
			ok = false
		else:
			repeat_toggle.emit_signal("toggled", true)
			var barracks: Entity = mode.current_state().get_entity_by_id(barracks_id)
			if barracks == null or not barracks.production_state.repeat_train_enabled:
				push_error("Repeat Train toggle should update selected producer state")
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


func _test_right_click_gather_rejects_raw_gas() -> bool:
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
		push_error("expected worker for raw-gas context test")
		_free_mode(mode)
		return false
	var worker: Entity = mode.current_state().get_entity_by_id(worker_id)
	var gas_origin: Vector2i = _find_clear_rect_origin_near(
		mode.current_state(), worker.origin, Vector2i(2, 2)
	)
	var gas_id: int = _add_runtime_entity(mode.current_state(), "gas_geyser", -1, gas_origin)
	if gas_id < 0:
		push_error("expected to add raw gas geyser to MVP map")
		_free_mode(mode)
		return false
	mode.current_state().get_entity_by_id(gas_id).current_resource_amount = 1000
	mode.renderer().bind_state(mode.current_state(), _load_registry())
	mode.renderer().set_perspective_player_id(0)
	var context: Dictionary = mode.context_action_at_tile(gas_origin)
	var ok := true
	if (
		context.get("action", "") != "invalid"
		or context.get("cursor_shape", -1) != Input.CURSOR_FORBIDDEN
	):
		push_error("raw gas without owned refinery should classify as invalid")
		ok = false
	if mode.issue_context_at_tile(gas_origin):
		push_error("right-click raw gas without owned refinery should be rejected")
		ok = false
	if mode.input_model().submit_for_player(0).orders.size() != 0:
		push_error("rejected raw-gas context action should not fall back to movement")
		ok = false
	_free_mode(mode)
	return ok


func _test_producer_right_click_sets_rally() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var base_id: int = _find_entity_id(mode.current_state(), "base", 0)
	var mineral_id: int = _find_entity_id_any_hp(mode.current_state(), "mineral_patch", -1)
	if base_id < 0 or mineral_id < 0 or not mode.select_entity_id(base_id):
		push_error("expected base producer and mineral target")
		_free_mode(mode)
		return false
	var rally_tile: Vector2i = _find_clear_rect_origin_near(
		mode.current_state(), mode.current_state().get_entity_by_id(base_id).origin, Vector2i.ONE
	)
	var ok := true
	if not mode.issue_context_at_tile(rally_tile):
		push_error("producer right-click empty tile should set move rally")
		ok = false
	var base: Entity = mode.current_state().get_entity_by_id(base_id)
	if (
		base == null
		or base.production_state == null
		or base.production_state.rally_mode != ProductionState.RALLY_MODE_MOVE
		or base.production_state.rally_target_tile != rally_tile
	):
		push_error("producer move rally state was not stored")
		ok = false
	var renderer: MatchRenderer = mode.renderer()
	if renderer != null and renderer.action_preview_count() < 1:
		push_error("selected producer rally should render an action preview")
		ok = false
	var mineral: Entity = mode.current_state().get_entity_by_id(mineral_id)
	if not mode.issue_context_at_tile(mineral.origin):
		push_error("producer right-click resource should set gather rally")
		ok = false
	if (
		base.production_state.rally_mode != ProductionState.RALLY_MODE_GATHER
		or base.production_state.rally_target_entity_id != mineral_id
	):
		push_error("producer gather rally state was not stored")
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
	if (
		worker_after == null
		or (
			worker_after.locked_to_building_id < 0
			and not ConstructionSystem.has_pending_build(worker_after)
		)
	):
		push_error("BUILD should commit the worker to construction")
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
	if worker_after.locked_to_building_id >= 0:
		var building: Entity = mode.current_state().get_entity_by_id(
			worker_after.locked_to_building_id
		)
		if building == null or building.def_id != "barracks" or not building.is_constructing:
			push_error("adjacent BUILD should create a constructing barracks")
			_free_mode(mode)
			return false
	elif worker_after.pending_build_def_id != "barracks":
		push_error("far BUILD should remain pending until the worker reaches the site")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_mvp_worker_builds_refinery() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var player: PlayerState = mode.current_state().get_player(0)
	player.minerals = 10000
	player.gas = 10000
	player.pop_cap = 200
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a P0 worker on mvp_map")
		_free_mode(mode)
		return false
	mode.begin_build("refinery")
	if mode.pending_command_kind() != "build":
		push_error("refinery should enter pending BUILD mode for the selected worker")
		_free_mode(mode)
		return false
	if not mode.confirm_pending_at_tile(Vector2i(6, 23)):
		push_error("expected refinery BUILD to queue on the P0 geyser")
		_free_mode(mode)
		return false
	var queued_orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if queued_orders.size() != 1:
		push_error("expected one queued refinery BUILD order, got %d" % queued_orders.size())
		_free_mode(mode)
		return false
	var queued_order: EntityOrder = queued_orders[0]
	if (
		queued_order.type != EntityOrder.Type.BUILD
		or queued_order.def_id != "refinery"
		or queued_order.target_tile != Vector2i(6, 23)
		or queued_order.target_entity_id != -1
	):
		push_error("unexpected queued refinery BUILD order: %s" % str(queued_order))
		_free_mode(mode)
		return false
	if not mode.resolve_turn():
		push_error("expected resolve_turn to succeed after refinery BUILD")
		_free_mode(mode)
		return false
	var refinery_id: int = _find_entity_id(mode.current_state(), "refinery", 0)
	var refinery: Entity = mode.current_state().get_entity_by_id(refinery_id)
	var worker: Entity = mode.current_state().get_entity_by_id(worker_id)
	var geyser_id: int = _find_entity_id(mode.current_state(), "gas_geyser", -1)
	if geyser_id < 0:
		geyser_id = _find_entity_id_any_hp(mode.current_state(), "gas_geyser", -1)
	var geyser: Entity = mode.current_state().get_entity_by_id(geyser_id)
	if refinery == null:
		var worker_summary := "missing worker"
		if worker != null:
			worker_summary = (
				"origin=%s pending=%s pending_tile=%s locked=%d"
				% [
					str(worker.origin),
					worker.pending_build_def_id,
					str(worker.pending_build_target_tile),
					worker.locked_to_building_id,
				]
			)
		push_error(
			(
				"refinery BUILD should create a constructing refinery on the geyser; worker %s"
				% worker_summary
			)
		)
		_free_mode(mode)
		return false
	if worker == null or geyser == null:
		_free_mode(mode)
		return false
	var refinery_rect: Rect2i = mode.current_state().tile_grid.entity_rect(refinery.id)
	var geyser_rect: Rect2i = mode.current_state().tile_grid.entity_rect(geyser.id)
	var worker_rect: Rect2i = mode.current_state().tile_grid.entity_rect(worker.id)
	var ok: bool = true
	if not refinery.is_constructing:
		push_error("refinery should be under construction immediately after the worker arrives")
		ok = false
	if refinery.construction_worker_id != worker.id or worker.locked_to_building_id != refinery.id:
		push_error("worker should be locked to the started refinery")
		ok = false
	if refinery_rect != geyser_rect:
		push_error("refinery rect should overlap the geyser rect")
		ok = false
	if TileGrid.distance_between_rects(worker_rect, refinery_rect) > 1:
		push_error("worker should be adjacent to the refinery after starting construction")
		ok = false
	_free_mode(mode)
	return ok


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
	elif queue_label != null and queue_label.visible:
		push_error("queued-order count label should stay hidden; previews are the primary queue UX")
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


func _test_gather_and_build_previews_route_around_blockers() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	var gather_target_id: int = _add_runtime_entity(
		mode.current_state(), "mineral_patch", -1, Vector2i(17, 23)
	)
	var renderer: MatchRenderer = mode.renderer()
	if worker_id < 0 or gather_target_id < 0 or renderer == null:
		push_error("expected worker, injected mineral patch, and renderer for preview test")
		_free_mode(mode)
		return false
	renderer.bind_state(mode.current_state(), _load_registry())
	if not mode.select_entity_id(worker_id) or not mode.issue_gather_selected(gather_target_id):
		push_error("expected cross-base GATHER preview to queue")
		_free_mode(mode)
		return false
	var ok := true
	if renderer.action_preview_line_point_count(0) <= 2:
		push_error("GATHER preview should draw a routed path, not a straight fallback line")
		ok = false

	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		push_error("expected scenario reload before BUILD preview")
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	mode.current_state().get_player(0).minerals = 10000
	mode.current_state().get_player(0).gas = 10000
	worker_id = _find_entity_id(mode.current_state(), "worker", 0)
	renderer = mode.renderer()
	if worker_id < 0 or renderer == null:
		push_error("expected worker and renderer after scenario reload")
		_free_mode(mode)
		return false
	if (
		not mode.select_entity_id(worker_id)
		or not mode.issue_build_selected("barracks", Vector2i(18, 23))
	):
		push_error("expected cross-base BUILD preview to queue")
		_free_mode(mode)
		return false
	if renderer.action_preview_line_point_count(0) <= 2:
		push_error("BUILD preview should draw a routed path, not a straight fallback line")
		ok = false
	_free_mode(mode)
	return ok


func _test_shift_click_routes_future_orders() -> bool:
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
		push_error("expected to select a P0 worker")
		_free_mode(mode)
		return false
	var card: Control = mode.command_card()
	if card == null:
		push_error("expected command card")
		_free_mode(mode)
		return false
	if _find_check_box_with_substring(card, "Queue") != null:
		push_error("command card should not expose a Queue toggle; use Shift-click instead")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(13, 22)):
		push_error("expected first queued move")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(13, 25), true):
		push_error("expected Shift-click move to become future order")
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	var ok: bool = true
	if mode.input_model().submit_for_player(0).orders.size() != 1:
		push_error("Shift-click queueing should keep one current order")
		ok = false
	if mode.input_model().future_order_count_for_entity(worker_id) != 1:
		push_error("Shift-click should append a future order")
		ok = false
	if mode.input_model().queue_modifier_active():
		push_error("Shift-click queue modifier should be one-shot")
		ok = false
	if renderer != null and renderer.action_preview_count() != 2:
		push_error("selected previews should include current and future orders")
		ok = false
	elif renderer != null:
		var preview_root: Node2D = renderer.get_node_or_null("Overlays/ActionPreviews") as Node2D
		var future_preview: Node = (
			preview_root.get_child(1)
			if preview_root != null and preview_root.get_child_count() > 1
			else null
		)
		var future_line: Line2D = (
			future_preview.get_child(0) as Line2D if future_preview != null else null
		)
		var expected_future_start: Vector2 = Vector2(13.5, 22.5) * 32.0
		if (
			future_line == null
			or future_line.points.size() < 2
			or future_line.points[0].distance_to(expected_future_start) > 0.5
		):
			push_error(
				(
					"future queued move preview should start at previous move destination, got %s"
					% str(future_line)
				)
			)
			ok = false
	mode.set_active_player_id(1)
	if mode.input_model().queue_modifier_active():
		push_error("queue modifier should stay inactive when switching active player")
		ok = false
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		push_error("scenario reload should succeed")
		ok = false
	elif mode.input_model().queue_modifier_active():
		push_error("queue modifier should stay inactive on scenario reload")
		ok = false
	_free_mode(mode)
	return ok


func _test_shift_click_routes_future_gather_and_build_orders() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	var ok: bool = true
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	var gather_target_id: int = _add_runtime_entity(
		mode.current_state(), "mineral_patch", -1, Vector2i(17, 23)
	)
	if worker_id < 0 or gather_target_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected worker and mineral patch for future gather preview")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(13, 22)):
		push_error("expected first queued move before future gather")
		ok = false
	if not mode.issue_gather_selected(gather_target_id, true):
		push_error("expected Shift-click gather to become future order")
		ok = false
	var renderer: MatchRenderer = mode.renderer()
	var expected_start: Vector2 = Vector2(13.5, 22.5) * 32.0
	if ok and not _action_preview_starts_near(renderer, 1, expected_start):
		push_error("future gather preview should start at previous move destination")
		ok = false

	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		push_error("expected scenario reload before future build preview")
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	mode.current_state().get_player(0).minerals = 10000
	mode.current_state().get_player(0).gas = 10000
	worker_id = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected worker for future build preview")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(13, 22)):
		push_error("expected first queued move before future build")
		ok = false
	if not mode.issue_build_selected("barracks", Vector2i(18, 23), true):
		push_error("expected Shift-click build to become future order")
		ok = false
	renderer = mode.renderer()
	if ok and not _action_preview_starts_near(renderer, 1, expected_start):
		push_error("future build preview should start at previous move destination")
		ok = false
	_free_mode(mode)
	return ok


func _test_halt_on_sight_move_preview_does_not_route() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var state: MatchState = mode.current_state()
	var marine_id: int = _find_entity_id(state, "marine", 0)
	var actor: Entity = state.get_entity_by_id(marine_id) if state != null else null
	var renderer: MatchRenderer = mode.renderer()
	if actor == null or state.tile_grid == null or renderer == null:
		push_error("expected marine actor and renderer for halt preview test")
		_free_mode(mode)
		return false
	var enemy_id: int = -1
	for delta in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		var enemy_origin: Vector2i = actor.origin + delta
		enemy_id = _add_runtime_entity(state, "marine", 1, enemy_origin)
		if enemy_id >= 0:
			break
	if enemy_id < 0:
		push_error("expected to place enemy beside actor for halt preview test")
		_free_mode(mode)
		return false
	actor.halt_on_sight = true
	renderer.bind_state(state, _load_registry())
	if (
		not mode.select_entity_id(actor.id)
		or not mode.issue_move_selected(actor.origin + Vector2i(6, 0))
	):
		push_error("expected halted marine MOVE preview to queue")
		_free_mode(mode)
		return false
	var point_count: int = renderer.call("action_preview_line_point_count", 0)
	_free_mode(mode)
	if point_count > 2:
		push_error("halt-on-sight MOVE preview should not draw a routed movement path")
		return false
	return true


func _test_target_chase_preview_tracks_live_target() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var state: MatchState = mode.current_state()
	var actor_id: int = _find_entity_id(state, "marine", 0)
	var target_id: int = _find_entity_id(state, "siege_tank", 1)
	var actor: Entity = state.get_entity_by_id(actor_id) if state != null else null
	var target: Entity = state.get_entity_by_id(target_id) if state != null else null
	var renderer: MatchRenderer = mode.renderer()
	if actor == null or target == null or state.tile_grid == null or renderer == null:
		push_error("expected opposing marines and renderer for target-chase preview test")
		_free_mode(mode)
		return false
	actor.halt_on_sight = true
	if not mode.select_entity_id(actor.id) or not mode.issue_target_chase_selected(target.id):
		push_error("expected target chase order to queue")
		_free_mode(mode)
		return false
	var stale_target_tile: Vector2i = target.origin
	var live_target_tile: Vector2i = stale_target_tile + Vector2i(0, 4)
	if not state.tile_grid.is_rect_clear(Rect2i(live_target_tile, Vector2i.ONE)):
		live_target_tile = _find_clear_rect_origin_near(state, live_target_tile, Vector2i.ONE)
	if not state.tile_grid.move(target.id, live_target_tile):
		push_error("expected target move setup to succeed")
		_free_mode(mode)
		return false
	target.origin = live_target_tile
	renderer.bind_state(state, _load_registry())
	mode.call("_update_hud")
	var stale_target_center: Vector2 = _tile_center_px(stale_target_tile)
	var live_target_center: Vector2 = _tile_center_px(live_target_tile)
	var preview_root: Node2D = renderer.get_node_or_null("Overlays/ActionPreviews") as Node2D
	var preview_group: Node = preview_root.get_child(0) if preview_root != null else null
	var preview_line: Line2D = (
		preview_group.get_child(0) as Line2D
		if preview_group != null and preview_group.get_child_count() > 0
		else null
	)
	if preview_line == null or preview_line.points.size() < 2:
		push_error("target chase preview should draw a routed path")
		_free_mode(mode)
		return false
	var end_point: Vector2 = preview_line.points[preview_line.points.size() - 1]
	var ok: bool = true
	if end_point.distance_to(stale_target_center) <= 0.5:
		push_error("target chase preview should not end at the stale fallback target tile")
		ok = false
	if end_point.distance_to(live_target_center) >= end_point.distance_to(stale_target_center):
		push_error("target chase preview should route toward the live target tile")
		ok = false
	_free_mode(mode)
	return ok


func _test_pending_build_updates_placement_preview() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var player: PlayerState = mode.current_state().get_player(0)
	player.minerals = 10000
	player.gas = 10000
	player.pop_cap = 200
	var worker_id: int = _find_entity_id(mode.current_state(), "worker", 0)
	if worker_id < 0 or not mode.select_entity_id(worker_id):
		push_error("expected to select a P0 worker on mvp_map")
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	if renderer == null or not renderer.has_method("build_placement_preview_count"):
		push_error("renderer should expose build placement preview count")
		_free_mode(mode)
		return false
	mode.begin_build("barracks")
	if mode.pending_command_kind() != "build":
		push_error("begin_build should enter pending build mode")
		_free_mode(mode)
		return false
	mode.call("_set_hover_tile", Vector2i(12, 2))
	var ok: bool = true
	if renderer.call("build_placement_preview_count") != 1:
		push_error("pending BUILD hover should create a placement preview")
		ok = false
	mode.cancel_pending_command()
	if renderer.call("build_placement_preview_count") != 0:
		push_error("cancel_pending_command should clear placement preview")
		ok = false
	mode.begin_build("barracks")
	mode.call("_set_hover_tile", Vector2i(12, 2))
	if renderer.call("build_placement_preview_count") != 1:
		push_error("second pending BUILD hover should recreate placement preview")
		ok = false
	if not mode.confirm_pending_at_tile(Vector2i(12, 2)):
		push_error("confirming valid pending BUILD should queue the order")
		ok = false
	var orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if orders.is_empty() or orders[0].target_tile != Vector2i(11, 1):
		push_error("pending BUILD should queue the centered origin shown by the preview")
		ok = false
	if renderer.call("build_placement_preview_count") != 0:
		push_error("successful pending BUILD confirm should clear placement preview")
		ok = false
	_free_mode(mode)
	return ok


func _test_requeues_unfinished_move_after_resolve() -> bool:
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
		push_error("expected to select a P0 worker")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(20, 22)):
		push_error("expected long-range move to queue")
		_free_mode(mode)
		return false
	var renderer: MatchRenderer = mode.renderer()
	if renderer == null or not renderer.has_method("action_preview_line_point_count"):
		push_error("renderer should expose path preview point counts")
		_free_mode(mode)
		return false
	var preview_points_before: int = renderer.call("action_preview_line_point_count", 0)
	if preview_points_before <= 2:
		push_error("long-range move preview should draw a path polyline before resolve")
		_free_mode(mode)
		return false
	if not mode.resolve_turn():
		push_error("expected resolve to succeed")
		_free_mode(mode)
		return false
	var orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if orders.size() != 1:
		push_error("unfinished long-range move should requeue, got %d orders" % orders.size())
		_free_mode(mode)
		return false
	var order: EntityOrder = orders[0]
	var ok := (
		order.type == EntityOrder.Type.MOVE
		and order.entity_id == worker_id
		and order.target_tile == Vector2i(20, 22)
	)
	if not ok:
		push_error("requeued move should preserve type, actor, and target")
	if renderer != null and renderer.action_preview_count() != 1:
		push_error("requeued move should remain visible as an action preview")
		ok = false
	var preview_points_after: int = renderer.call("action_preview_line_point_count", 0)
	if preview_points_after <= 2:
		push_error("requeued move preview should still draw a path polyline")
		ok = false
	elif preview_points_after >= preview_points_before:
		push_error("requeued move preview should recompute from the post-resolve origin")
		ok = false
	_free_mode(mode)
	return ok


func _test_tied_same_target_move_completes_for_future_queue() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(COMBAT_SCENARIO_PATH):
		_free_mode(mode)
		return false
	mode.set_active_player_id(0)
	var marines: Array[int] = _find_entity_ids(mode.current_state(), "marine", 0)
	if marines.size() < 2:
		push_error("expected at least two P0 marines")
		_free_mode(mode)
		return false
	var left_id: int = marines[0]
	var right_id: int = marines[2] if marines.size() > 2 else marines[1]
	if not mode.select_entity_id(left_id):
		push_error("expected to select first marine")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(6, 11)):
		push_error("expected first contested move to queue")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(8, 10), true):
		push_error("expected first future move to queue")
		_free_mode(mode)
		return false
	if not mode.select_entity_id(right_id):
		push_error("expected to select second marine")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(6, 11)):
		push_error("expected second contested move to queue")
		_free_mode(mode)
		return false
	if not mode.issue_move_selected(Vector2i(8, 12), true):
		push_error("expected second future move to queue")
		_free_mode(mode)
		return false
	if not mode.resolve_turn():
		push_error("expected resolve to succeed")
		_free_mode(mode)
		return false
	var left_after: Entity = mode.current_state().get_entity_by_id(left_id)
	var right_after: Entity = mode.current_state().get_entity_by_id(right_id)
	var ok := true
	if left_after.origin != Vector2i(5, 10) or right_after.origin != Vector2i(5, 12):
		push_error(
			(
				"tied movers should stop before the contested target, got %s and %s"
				% [str(left_after.origin), str(right_after.origin)]
			)
		)
		ok = false
	var orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if orders.size() != 2:
		push_error(
			"future orders should promote after tied move completion, got %d" % orders.size()
		)
		ok = false
	else:
		if not _expect_order(orders[0], EntityOrder.Type.MOVE, left_id, Vector2i(8, 10)):
			ok = false
		if not _expect_order(orders[1], EntityOrder.Type.MOVE, right_id, Vector2i(8, 12)):
			ok = false
	_free_mode(mode)
	return ok


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
	if not _expect_button_visibility(card, "Cancel", true):
		push_error("selected worker with a queued order should expose Cancel")
		_free_mode(mode)
		return false
	card.emit_signal("cancel_requested", -1)
	if mode.pending_order_count(0) != 0:
		push_error("Cancel should remove the selected worker's queued MOVE")
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
		push_error("pending target click should apply target focus")
		_free_mode(mode)
		return false
	var marine: Entity = mode.current_state().get_entity_by_id(1)
	if marine == null or marine.focus_target_entity_id != 4:
		push_error("expected immediate target focus after pending target click")
		_free_mode(mode)
		return false
	if mode.pending_order_count(0) != 0:
		push_error("target focus should not queue a turn order")
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
	if orders.size() != 0:
		push_error(
			"Cancel should remove the selected marine's queued MOVE_ONLY, got %d" % orders.size()
		)
		_free_mode(mode)
		return false
	if marine == null or marine.focus_target_entity_id != 4:
		push_error("first cancel signal should keep target focus while cancelling MOVE_ONLY")
		_free_mode(mode)
		return false
	card.emit_signal("cancel_requested", -1)
	if marine == null or marine.focus_target_entity_id != -1:
		push_error("second cancel signal should immediately clear target focus")
		_free_mode(mode)
		return false
	if not marine.halt_on_sight:
		push_error("halt-on-sight signal should immediately enable halt-on-sight")
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
		push_error("pending target click on enemy should apply targeted intent")
		_free_mode(mode)
		return false
	var marine: Entity = mode.current_state().get_entity_by_id(1)
	if marine == null or marine.focus_target_entity_id != 4:
		push_error("pending enemy click should immediately set target focus to #4")
		_free_mode(mode)
		return false
	if mode.pending_order_count(0) != 0:
		push_error("pending enemy click should not queue ATTACK focus")
		_free_mode(mode)
		return false
	_free_mode(mode)
	return true


func _test_a_key_attack_move_mode() -> bool:
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
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	mode.call("_unhandled_input", _key_press(KEY_A))
	if mode.pending_command_kind() != "move":
		push_error("A key should enter pending attack-move mode")
		_free_mode(mode)
		return false
	if mode.pending_cursor_shape() != Input.CURSOR_CROSS:
		push_error("pending attack-move should use the crosshair cursor")
		_free_mode(mode)
		return false
	if not mode.confirm_pending_at_tile(Vector2i(8, 10)):
		push_error("A-key ground click should queue attack-move")
		_free_mode(mode)
		return false
	var orders: Array[EntityOrder] = mode.input_model().submit_for_player(0).orders
	if orders.size() != 1 or orders[0].type != EntityOrder.Type.MOVE:
		push_error("A-key ground click should queue one MOVE order")
		_free_mode(mode)
		return false
	mode.input_model().clear_submissions()
	mode.call("_unhandled_input", _key_press(KEY_A))
	mode.renderer().set_perspective_player_id(1)
	if not mode.confirm_pending_at_tile(Vector2i(13, 10)):
		push_error("A-key enemy click should queue targeted ATTACK")
		_free_mode(mode)
		return false
	orders = mode.input_model().submit_for_player(0).orders
	if (
		orders.size() != 1
		or orders[0].type != EntityOrder.Type.ATTACK
		or orders[0].target_priority_chain != ([4] as Array[int])
		or orders[0].target_tile != Vector2i(13, 10)
	):
		push_error("A-key enemy click should queue ATTACK against #4")
		_free_mode(mode)
		return false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
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
	mode.call("_unhandled_input", _mouse_motion(Vector2(0.0, 96.0), MOUSE_BUTTON_MASK_LEFT))
	mode.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_LEFT, false, Vector2(8.0, 104.0)))
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


func _test_switching_player_keeps_camera_bounded() -> bool:
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
	var ok: bool = _camera_visible_rect_inside_state(
		camera, mode.current_state(), "P0 player focus"
	)
	mode.set_active_player_id(1)
	ok = _camera_visible_rect_inside_state(camera, mode.current_state(), "P1 player focus") and ok
	if renderer.call("perspective_player_id") != 1:
		push_error("switching player should still update renderer perspective")
		ok = false
	_free_mode(mode)
	return ok


func _test_tile_size() -> float:
	var tunables: Tunables = load(TUNABLES_PATH) as Tunables
	if tunables == null:
		return 32.0
	return float(tunables.tile_pixel_size)


func _camera_visible_rect_inside_state(
	camera: Camera2D, state: MatchState, context: String
) -> bool:
	if state == null or state.tile_grid == null:
		push_error("camera bounds check requires a loaded tile grid")
		return false
	var viewport: Viewport = camera.get_viewport()
	var viewport_size: Vector2 = (
		viewport.get_visible_rect().size if viewport != null else Vector2.ZERO
	)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = Vector2(
			float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920.0)),
			float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080.0))
		)
	var safe_zoom_x: float = maxf(camera.zoom.x, 0.01)
	var safe_zoom_y: float = maxf(camera.zoom.y, 0.01)
	var visible_size: Vector2 = Vector2(
		viewport_size.x / safe_zoom_x, viewport_size.y / safe_zoom_y
	)
	var visible: Rect2 = Rect2(camera.position - visible_size * 0.5, visible_size)
	var tile_size: float = _test_tile_size()
	var map_bounds: Rect2 = Rect2(
		Vector2.ZERO, Vector2(state.tile_grid.width * tile_size, state.tile_grid.height * tile_size)
	)
	var epsilon: float = 0.01
	var ok: bool = (
		visible.position.x >= map_bounds.position.x - epsilon
		and visible.position.y >= map_bounds.position.y - epsilon
		and visible.end.x <= map_bounds.end.x + epsilon
		and visible.end.y <= map_bounds.end.y + epsilon
	)
	if not ok:
		push_error(
			(
				"camera visible rect escaped map after %s: visible=%s map=%s zoom=%s"
				% [context, str(visible), str(map_bounds), str(camera.zoom)]
			)
		)
	return ok


func _test_hud_omits_resolution_button() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var ok: bool = true
	var button: Button = mode.get_node_or_null("DevHUD/Panel/Root/Buttons/Resolution") as Button
	if button != null:
		push_error("dev HUD should not expose a Resolution/2K button")
		ok = false
	_free_mode(mode)
	return ok


func _test_hud_separates_replay_controls() -> bool:
	var mode: Node = _make_mode()
	if mode == null:
		return false
	add_child(mode)
	if not mode.load_scenario_path(MVP_SCENARIO_PATH):
		_free_mode(mode)
		return false
	var play_root: Node = mode.get_node_or_null("DevHUD/Panel/Root")
	var play_panel: PanelContainer = mode.get_node_or_null("DevHUD/Panel") as PanelContainer
	var replay_panel: PanelContainer = mode.get_node_or_null("DevHUD/ReplayPanel") as PanelContainer
	var escape_menu: PanelContainer = mode.get_node_or_null("DevHUD/EscapeMenu") as PanelContainer
	var load_kind: OptionButton = (
		mode.get_node_or_null("DevHUD/EscapeMenu/Root/LoadRow/LoadKind") as OptionButton
	)
	var snapshot_dialog: FileDialog = (
		mode.get_node_or_null("DevHUD/SnapshotLoadDialog") as FileDialog
	)
	var replay_dialog: FileDialog = mode.get_node_or_null("DevHUD/ReplayLoadDialog") as FileDialog
	var ok: bool = true
	if play_root == null:
		push_error("play HUD root should exist")
		ok = false
	else:
		if play_root.get_node_or_null("SnapshotButtons") != null:
			push_error("snapshot/replay save controls should not live in the play HUD")
			ok = false
		if play_root.get_node_or_null("ReplayButtons") != null:
			push_error("replay transport controls should not live in the play HUD")
			ok = false
		var replay_button: Button = _find_exact_button(play_root, "Replay")
		if replay_button != null:
			push_error("play HUD should not expose replay controls")
			ok = false
	if play_panel == null:
		push_error("play HUD panel should exist")
		ok = false
	elif not play_panel.visible:
		push_error("play HUD should be visible during live play")
		ok = false
	if replay_panel == null:
		push_error("replay HUD panel should exist separately from the play HUD")
		ok = false
	else:
		if replay_panel.offset_left < 384.0 or replay_panel.offset_top > 12.0:
			push_error("replay panel should sit to the right of the top-left zoom debug readout")
			ok = false
		if replay_panel.get_node_or_null("Root/SnapshotButtons") != null:
			push_error("snapshot controls should not live in the replay panel")
			ok = false
		if replay_panel.get_node_or_null("Root/ReplayFileButtons") != null:
			push_error("replay save/load file controls should not live in the replay panel")
			ok = false
		if replay_panel.get_node_or_null("Root/ReplayButtons") == null:
			push_error("replay transport controls should live in the replay panel")
			ok = false
		if replay_panel.get_node_or_null("Root/ReplayTimelineRow/ReplayTimeline") == null:
			push_error("replay panel should expose a timeline scrubber")
			ok = false
		if _find_exact_button(replay_panel, "Play From Here") == null:
			push_error("replay panel should expose a play-from-here branch button")
			ok = false
		if replay_panel.visible:
			push_error("replay panel should be hidden during live play")
			ok = false
	if escape_menu == null:
		push_error("escape menu should exist")
		ok = false
	else:
		if escape_menu.visible:
			push_error("escape menu should start hidden")
			ok = false
		mode.call("_unhandled_input", _escape_key())
		if not escape_menu.visible:
			push_error("Escape should open the menu")
			ok = false
		if _find_exact_button(escape_menu, "New Game") == null:
			push_error("escape menu should expose New Game")
			ok = false
		if _find_exact_button(escape_menu, "Save Snapshot") == null:
			push_error("escape menu should expose snapshot saving")
			ok = false
		if _find_exact_button(escape_menu, "Load...") == null:
			push_error("escape menu should expose shared load")
			ok = false
		if load_kind == null:
			push_error("escape menu should expose snapshot/replay load filter")
			ok = false
		elif load_kind.item_count != 2:
			push_error("load filter should include snapshot and replay")
			ok = false
		mode.call("_unhandled_input", _escape_key())
		if escape_menu.visible:
			push_error("Escape should close the menu")
			ok = false
	if snapshot_dialog == null:
		push_error("snapshot load dialog should exist")
		ok = false
	else:
		if snapshot_dialog.access != FileDialog.ACCESS_USERDATA:
			push_error("snapshot load dialog should browse user:// data")
			ok = false
		if snapshot_dialog.current_dir != "user://tmp/snapshots":
			push_error("snapshot load dialog should start in the snapshot folder")
			ok = false
	if replay_dialog == null:
		push_error("replay load dialog should exist")
		ok = false
	else:
		if replay_dialog.access != FileDialog.ACCESS_USERDATA:
			push_error("replay load dialog should browse user:// data")
			ok = false
		if replay_dialog.current_dir != "user://tmp/replays":
			push_error("replay load dialog should start in the replay folder")
			ok = false
	if ok and not mode.resolve_turn():
		push_error("resolve should succeed before checking replay-only interface")
		ok = false
	if ok and not mode.replay_jump_to_turn(1):
		push_error("replay jump should enter replay mode")
		ok = false
	if ok:
		if play_panel.visible:
			push_error("play HUD should be hidden during replay")
			ok = false
		if not replay_panel.visible:
			push_error("replay panel should be visible during replay")
			ok = false
		mode.call("_set_escape_menu_visible", true)
		var save_snapshot_button: Button = _find_exact_button(escape_menu, "Save Snapshot")
		if save_snapshot_button == null or save_snapshot_button.visible:
			push_error("snapshot saving should be hidden while viewing a replay")
			ok = false
		mode.call("_set_escape_menu_visible", false)
		var play_from_here: Button = _find_exact_button(replay_panel, "Play From Here")
		if play_from_here == null:
			push_error("replay panel should keep Play From Here available in replay mode")
			ok = false
		else:
			play_from_here.pressed.emit()
			if not play_panel.visible or replay_panel.visible:
				push_error("Play From Here should return to the playable interface")
				ok = false
	_free_mode(mode)
	return ok


func _make_mode() -> Node:
	var script: Script = load(DEV_PLAY_MODE_PATH) as Script
	if script == null:
		push_error("could not load %s" % DEV_PLAY_MODE_PATH)
		return null
	var mode: Node = script.new()
	mode.set_auto_save_replays_enabled(false)
	return mode


func _make_command_card() -> Control:
	var script: Script = load(COMMAND_CARD_PATH) as Script
	if script == null:
		push_error("could not load %s" % COMMAND_CARD_PATH)
		return null
	return script.new() as Control


func _set_command_card_state(
	card: Control,
	can_move: bool,
	can_move_only: bool,
	can_target: bool,
	can_halt_on_sight: bool,
	can_gather: bool,
	can_cancel: bool
) -> void:
	var build_options: Array[Dictionary] = []
	var train_options: Array[Dictionary] = []
	var research_options: Array[Dictionary] = []
	var ability_options: Array[Dictionary] = []
	card.call(
		"set_command_state",
		"Selection",
		can_move,
		can_move_only,
		can_target,
		can_halt_on_sight,
		can_gather,
		false,
		build_options,
		train_options,
		research_options,
		ability_options,
		can_cancel
	)


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


func _find_clear_rect_origin_near(
	state: MatchState, near_tile: Vector2i, footprint: Vector2i
) -> Vector2i:
	if state == null or state.tile_grid == null:
		return Vector2i.ZERO
	for radius in range(1, 20):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				var origin := near_tile + Vector2i(dx, dy)
				var rect := Rect2i(origin, footprint)
				if state.tile_grid.is_rect_in_bounds(rect) and state.tile_grid.is_rect_clear(rect):
					return origin
	return Vector2i.ZERO


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
		if def.gather != null:
			entity.gather_state = GatherState.new()
		if def.resource_source != null:
			entity.current_resource_amount = def.resource_source.capacity
	if not state.tile_grid.place(entity.id, Rect2i(origin, footprint)):
		return -1
	state.entities.append(entity)
	return entity.id


func _action_preview_starts_near(
	renderer: MatchRenderer, preview_index: int, expected_start: Vector2
) -> bool:
	if renderer == null:
		return false
	var preview_root: Node2D = renderer.get_node_or_null("Overlays/ActionPreviews") as Node2D
	if preview_root == null or preview_index < 0 or preview_index >= preview_root.get_child_count():
		return false
	var preview_group: Node = preview_root.get_child(preview_index)
	var preview_line: Line2D = (
		preview_group.get_child(0) as Line2D
		if preview_group != null and preview_group.get_child_count() > 0
		else null
	)
	return (
		preview_line != null
		and preview_line.points.size() >= 2
		and preview_line.points[0].distance_to(expected_start) <= 0.5
	)


func _tile_center_px(tile: Vector2i) -> Vector2:
	return Vector2(tile.x + 0.5, tile.y + 0.5) * _test_tile_size()


func _command_card_ids(card: Control, method_name: String) -> Array[String]:
	var out: Array[String] = []
	var raw: Array = card.call(method_name)
	for item in raw:
		var id: String = item
		out.append(id)
	return out


func _expect_order(
	order: EntityOrder, expected_type: EntityOrder.Type, entity_id: int, target_tile: Vector2i
) -> bool:
	return (
		order != null
		and order.type == expected_type
		and order.entity_id == entity_id
		and order.target_tile == target_tile
	)


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


func _find_check_box_with_substring(root: Node, needle: String) -> CheckBox:
	if root == null:
		return null
	if root is CheckBox:
		var check_box: CheckBox = root as CheckBox
		if check_box.text.find(needle) != -1:
			return check_box
	for child in root.get_children():
		var found: CheckBox = _find_check_box_with_substring(child, needle)
		if found != null:
			return found
	return null


func _find_exact_button(root: Node, text: String) -> Button:
	if root == null:
		return null
	if root is Button:
		var button: Button = root as Button
		if button.text == text:
			return button
	for child in root.get_children():
		var found: Button = _find_exact_button(child, text)
		if found != null:
			return found
	return null


func _expect_button_visibility(root: Node, text: String, expected_visible: bool) -> bool:
	var button: Button = _find_exact_button(root, text)
	if button == null:
		push_error("expected button '%s' to exist" % text)
		return false
	if button.visible != expected_visible:
		push_error(
			(
				"button '%s' visibility should be %s, got %s"
				% [text, str(expected_visible), str(button.visible)]
			)
		)
		return false
	return true


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


func _escape_key() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	return event


func _key_press(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _free_mode(mode: Node) -> void:
	if mode == null:
		return
	if mode.is_inside_tree():
		remove_child(mode)
	mode.queue_free()
