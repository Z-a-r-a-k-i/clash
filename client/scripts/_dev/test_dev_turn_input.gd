@tool
extends Node

const DEV_TURN_INPUT_PATH: String = "res://scripts/game/dev_turn_input.gd"


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	_run_all()


func _run_all() -> int:
	var passed: int = 0
	var failed: int = 0
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
	print("[test_dev_turn_input] %d passed, %d failed" % [passed, failed])
	for test_name in fail_names:
		push_error("  failed: %s" % test_name)
	return failed


func _all_tests() -> Array:
	return [
		["dev_input_selects_only_active_live_owned_entities", _test_selects_owned_live_entity],
		["dev_input_queues_move_for_active_player", _test_queues_move_for_active_player],
		["dev_input_queues_attack_against_enemy", _test_queues_attack_against_enemy],
		[
			"dev_input_applies_persistent_attack_target_immediately",
			_test_applies_persistent_attack_target_immediately
		],
		["dev_input_replaces_duplicate_move_and_target", _test_replaces_duplicate_move_and_target],
		["dev_input_queues_gather_for_worker_resource_target", _test_queues_gather],
		[
			"dev_input_queues_move_only_and_applies_state_changes",
			_test_queues_move_only_and_applies_state_changes
		],
		["dev_input_move_only_allows_noncombat_movers", _test_move_only_allows_noncombat_movers],
		["dev_input_queues_target_chase_atomically", _test_queues_target_chase_atomically],
		["dev_input_requeues_unfinished_move_assist", _test_requeues_unfinished_move_assist],
		["dev_input_requeues_unfinished_attack_assist", _test_requeues_unfinished_attack_assist],
		["dev_input_drops_completed_move_assist", _test_drops_completed_move_assist],
		["dev_input_cancel_clears_move_assist", _test_cancel_clears_move_assist],
		[
			"dev_input_non_move_command_replaces_requeued_move_assist",
			_test_non_move_command_replaces_requeued_move_assist
		],
		[
			"dev_input_queue_modifier_appends_future_orders",
			_test_queue_modifier_appends_future_orders
		],
		[
			"dev_input_normal_order_replaces_current_and_future",
			_test_normal_order_replaces_current_and_future
		],
		["dev_input_sets_producer_rally", _test_sets_producer_rally],
		["dev_input_queues_spawned_unit_rally_orders", _test_queues_spawned_unit_rally_orders],
		[
			"dev_input_rally_gather_retargets_when_source_full",
			_test_rally_gather_retargets_when_source_full
		],
		[
			"dev_input_cancel_removes_future_before_current",
			_test_cancel_removes_future_before_current
		],
		["dev_input_promotes_future_order_when_ready", _test_promotes_future_order_when_ready],
		[
			"dev_input_standing_orders_do_not_block_future_promotion",
			_test_standing_orders_do_not_block_future_promotion
		],
		[
			"dev_input_waits_to_promote_future_order_while_gathering",
			_test_waits_to_promote_future_order_while_gathering
		],
		["dev_input_queues_build_train_and_research", _test_queues_build_train_research],
		[
			"dev_input_snaps_refinery_build_to_geyser_origin",
			_test_snaps_refinery_build_to_geyser_origin
		],
		["dev_input_reports_build_placement_preview", _test_build_placement_preview],
		[
			"dev_input_rejects_occupied_target_build_preview",
			_test_rejects_occupied_target_build_preview
		],
		[
			"dev_input_tagged_build_target_survives_overlapping_occupant",
			_test_tagged_build_target_survives_overlapping_occupant
		],
		[
			"dev_input_rejects_unaffordable_build_without_queue",
			_test_rejects_unaffordable_build_without_queue
		],
		[
			"dev_input_rejects_occupied_build_without_queue",
			_test_rejects_occupied_build_without_queue
		],
		["dev_input_derives_command_options_from_selection", _test_derives_command_options],
		[
			"dev_input_cancel_removes_selected_unit_queued_order",
			_test_cancel_removes_selected_unit_queued_order
		],
		["dev_input_queues_use_ability", _test_queues_use_ability],
		["dev_input_snapshot_restore_preserves_continuation", _test_snapshot_restore],
		[
			"dev_input_snapshot_restore_skips_malformed_order_entries",
			_test_snapshot_restore_skips_malformed_order_entries
		],
		[
			"dev_input_snapshot_restore_prunes_invalid_future_orders",
			_test_snapshot_restore_prunes_invalid_future_orders
		],
		["dev_input_clears_submissions_after_resolve", _test_clears_submissions],
		["dev_input_surrender_only_marks_active_player", _test_surrender_active_player],
	]


func _test_selects_owned_live_entity() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	if not input.select_entity(1):
		push_error("expected owner-0 worker #1 to be selectable")
		return false
	if input.selected_entity_id() != 1:
		push_error("selected entity id should be 1, got %d" % input.selected_entity_id())
		return false
	if input.select_entity(2):
		push_error("enemy entity #2 should not be selectable while active player is 0")
		return false
	if input.selected_entity_id() != -1:
		push_error("invalid selection should clear selected entity")
		return false
	if input.select_entity(3):
		push_error("neutral resource #3 should not be selectable")
		return false
	if input.select_entity(4):
		push_error("dead owned entity #4 should not be selectable")
		return false
	return true


func _test_queues_move_for_active_player() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(1)
	if not input.issue_move(Vector2i(8, 8)):
		push_error("expected MOVE to queue for selected worker")
		return false
	var submit_0: SubmitTurn = input.submit_for_player(0)
	var submit_1: SubmitTurn = input.submit_for_player(1)
	if submit_0.orders.size() != 1 or submit_1.orders.size() != 0:
		push_error("expected exactly one order for P0 and none for P1")
		return false
	var order: EntityOrder = submit_0.orders[0]
	return _expect_order(order, EntityOrder.Type.MOVE, 1, Vector2i(8, 8), -1, [])


func _test_queues_attack_against_enemy() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_attack(2):
		push_error("expected ATTACK to queue against enemy marine")
		return false
	var order: EntityOrder = input.submit_for_player(0).orders[0]
	if not _expect_order(order, EntityOrder.Type.ATTACK_TARGET, 5, Vector2i(7, 1), -1, [2]):
		return false
	if input.issue_attack(3):
		push_error("neutral mineral patch should not be a valid attack target")
		return false
	return true


func _test_applies_persistent_attack_target_immediately() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.has_method("issue_attack_target"):
		push_error("DevTurnInput should expose persistent targeted attack intent")
		return false
	if not input.call("issue_attack_target", 2):
		push_error("expected attack target to queue for selected marine")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("target command should queue one direct attack order, got %d" % orders.size())
		return false
	var actor: Entity = setup.state.get_entity_by_id(5)
	if actor == null or actor.focus_target_entity_id != -1:
		push_error("target command should not mutate focus before resolver distribution")
		return false
	return _expect_order(orders[0], EntityOrder.Type.ATTACK_TARGET, 5, Vector2i(7, 1), -1, [2])


func _test_replaces_duplicate_move_and_target() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	_add_entity(setup.state, 8, "marine", 1, Vector2i(9, 7), Vector2i(1, 1), 45)
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_move(Vector2i(6, 6)):
		push_error("expected first MOVE to queue")
		return false
	if not input.issue_move(Vector2i(8, 8)):
		push_error("expected second MOVE to replace first")
		return false
	if not input.issue_attack(2):
		push_error("expected first target to queue")
		return false
	if not input.issue_attack(8):
		push_error("expected second target to replace first")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("expected latest normal command to replace prior orders, got %d" % orders.size())
		return false
	return _expect_order(orders[0], EntityOrder.Type.ATTACK_TARGET, 5, Vector2i(9, 7), -1, [8])


func _test_queues_gather() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(1)
	if not input.issue_gather(3):
		push_error("expected worker to queue GATHER against mineral patch")
		return false
	var order: EntityOrder = input.submit_for_player(0).orders[0]
	if not _expect_order(order, EntityOrder.Type.GATHER, 1, Vector2i.ZERO, 3, []):
		return false
	if input.issue_gather(7):
		push_error("depleted mineral patch should not be a valid gather target")
		return false
	if input.submit_for_player(0).orders.size() != 1:
		push_error("rejected gather should not append an order")
		return false
	if input.issue_gather(10):
		push_error("raw gas without an owned refinery should not be a valid gather target")
		return false
	if input.submit_for_player(0).orders.size() != 1:
		push_error("rejected raw-gas gather should not append an order")
		return false
	var refinery: Entity = Entity.new()
	refinery.id = setup.state.allocate_entity_id()
	refinery.def_id = "refinery"
	refinery.current_def_id = "refinery"
	refinery.owner_player_id = 0
	refinery.origin = Vector2i(5, 8)
	refinery.current_hp = 750
	setup.state.entities.append(refinery)
	setup.state.tile_grid.place_overlapping(refinery.id, Rect2i(Vector2i(5, 8), Vector2i(2, 2)), 10)
	if not input.issue_gather(10):
		push_error("gas with an owned refinery should be a valid gather target")
		return false
	input.select_entity(5)
	if input.issue_gather(3):
		push_error("marine should not be allowed to gather")
		return false
	return true


func _test_queues_move_only_and_applies_state_changes() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_move(Vector2i(6, 6)):
		push_error("expected MOVE to queue for selected marine")
		return false
	if not input.has_method("issue_move_only"):
		push_error("DevTurnInput should expose MOVE_ONLY as the move-without-shooting command")
		return false
	if not input.call("issue_move_only", Vector2i(7, 7)):
		push_error("expected MOVE_ONLY to replace selected marine MOVE")
		return false
	if not input.issue_halt_on_sight_toggle(true):
		push_error("expected halt-on-sight to apply for selected marine")
		return false
	if not input.issue_cancel():
		push_error("expected CANCEL to clear selected marine state")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 0:
		push_error("expected queued MOVE_ONLY to be cancelled, got %d orders" % orders.size())
		return false
	if not EntityOrder.Type.has("MOVE_ONLY"):
		push_error("EntityOrder.Type should define MOVE_ONLY")
		return false
	var actor: Entity = setup.state.get_entity_by_id(5)
	if actor == null:
		push_error("expected selected marine to exist")
		return false
	if actor.focus_target_entity_id != -1:
		push_error("MOVE_ONLY/CANCEL flow should not create target focus")
		return false
	if not actor.halt_on_sight:
		push_error("halt-on-sight should remain immediately enabled")
		return false
	return true


func _test_move_only_allows_noncombat_movers() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(9)
	if not input.can_issue_move_only():
		push_error("noncombat mover should be allowed to use MOVE_ONLY")
		return false
	if not input.issue_move_only(Vector2i(11, 11)):
		push_error("expected noncombat mover MOVE_ONLY to queue")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("expected one noncombat mover order, got %d" % orders.size())
		return false
	return _expect_order(orders[0], EntityOrder.Type.MOVE_ONLY, 9, Vector2i(11, 11), -1, [])


func _test_queues_target_chase_atomically() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_target_chase(2):
		push_error("expected target chase to queue for selected marine")
		return false
	var actor: Entity = setup.state.get_entity_by_id(5)
	if actor.focus_target_entity_id != -1:
		push_error("target chase should not mutate focus before resolver distribution")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("target chase should be one atomic order, got %d" % orders.size())
		return false
	if not _expect_order(orders[0], EntityOrder.Type.ATTACK_TARGET, 5, Vector2i(7, 1), -1, [2]):
		return false
	input.set_queue_modifier_active(true)
	if not input.issue_target_chase(2):
		push_error("expected shift target chase to append as future order")
		return false
	if input.submit_for_player(0).orders.size() != 1 or input.future_order_count_for_entity(5) != 1:
		push_error("shift target chase should append one future atomic order")
		return false
	var future: Array[EntityOrder] = input.future_orders_for_entity(5)
	return _expect_order(future[0], EntityOrder.Type.ATTACK_TARGET, 5, Vector2i(7, 1), -1, [2])


func _test_requeues_unfinished_move_assist() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_move_only(Vector2i(9, 1)):
		push_error("expected MOVE_ONLY to queue for selected marine")
		return false
	if not input.has_method("queue_move_assists_for_next_turn"):
		push_error("DevTurnInput should expose move-assist requeue")
		return false
	setup.state.tile_grid.move(5, Vector2i(6, 1))
	var actor: Entity = setup.state.get_entity_by_id(5)
	actor.origin = Vector2i(6, 1)
	input.call("clear_submissions", false)
	input.call("queue_move_assists_for_next_turn")
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("unfinished move assist should requeue one order, got %d" % orders.size())
		return false
	return _expect_order(orders[0], EntityOrder.Type.MOVE_ONLY, 5, Vector2i(9, 1), -1, [])


func _test_requeues_unfinished_attack_assist() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_attack(2):
		push_error("expected ATTACK to queue for selected marine")
		return false
	var first_order: EntityOrder = input.submit_for_player(0).orders[0]
	if not _expect_order(first_order, EntityOrder.Type.ATTACK_TARGET, 5, Vector2i(7, 1), -1, [2]):
		return false
	setup.state.tile_grid.move(2, Vector2i(8, 1))
	var target: Entity = setup.state.get_entity_by_id(2)
	target.origin = Vector2i(8, 1)
	input.clear_submissions(false, false)
	input.queue_move_assists_for_next_turn()
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("unfinished attack assist should requeue one order, got %d" % orders.size())
		return false
	return _expect_order(orders[0], EntityOrder.Type.ATTACK_TARGET, 5, Vector2i(8, 1), -1, [2])


func _test_drops_completed_move_assist() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_move(Vector2i(9, 1)):
		push_error("expected MOVE to queue for selected marine")
		return false
	if not input.has_method("queue_move_assists_for_next_turn"):
		push_error("DevTurnInput should expose move-assist requeue")
		return false
	setup.state.tile_grid.move(5, Vector2i(9, 1))
	var actor: Entity = setup.state.get_entity_by_id(5)
	actor.origin = Vector2i(9, 1)
	input.call("clear_submissions", false)
	input.call("queue_move_assists_for_next_turn")
	if input.submit_for_player(0).orders.size() != 0:
		push_error("completed move assist should not requeue")
		return false
	return true


func _test_cancel_clears_move_assist() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_move(Vector2i(9, 1)):
		push_error("expected MOVE to queue for selected marine")
		return false
	if not input.issue_cancel():
		push_error("expected cancel to clear queued move")
		return false
	input.call("clear_submissions", false)
	input.call("queue_move_assists_for_next_turn")
	if input.submit_for_player(0).orders.size() != 0:
		push_error("cancelled move assist should not requeue")
		return false
	return true


func _test_non_move_command_replaces_requeued_move_assist() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(1)
	if not input.issue_move(Vector2i(10, 10)):
		push_error("expected MOVE to queue for selected worker")
		return false
	input.call("clear_submissions", false)
	input.call("queue_move_assists_for_next_turn")
	if input.submit_for_player(0).orders.size() != 1:
		push_error("expected requeued move assist before replacement")
		return false
	if not input.issue_gather(3):
		push_error("expected GATHER to replace assisted move")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("non-move command should remove assisted move, got %d orders" % orders.size())
		return false
	return _expect_order(orders[0], EntityOrder.Type.GATHER, 1, Vector2i.ZERO, 3, [])


func _test_queue_modifier_appends_future_orders() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_move(Vector2i(6, 6)):
		push_error("expected first command to queue for this turn")
		return false
	input.set_queue_modifier_active(true)
	if not input.issue_move_only(Vector2i(8, 8)):
		push_error("expected queue-modified command to append as future order")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("queue modifier should keep one current order, got %d" % orders.size())
		return false
	if input.future_order_count_for_entity(5) != 1:
		push_error("queue modifier should append one future order")
		return false
	var future: Array[EntityOrder] = input.future_orders_for_entity(5)
	return (
		_expect_order(orders[0], EntityOrder.Type.MOVE, 5, Vector2i(6, 6), -1, [])
		and _expect_order(future[0], EntityOrder.Type.MOVE_ONLY, 5, Vector2i(8, 8), -1, [])
	)


func _test_normal_order_replaces_current_and_future() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	input.issue_move(Vector2i(6, 6))
	input.set_queue_modifier_active(true)
	input.issue_move_only(Vector2i(8, 8))
	if not input.issue_move(Vector2i(9, 9)):
		push_error("expected normal command after future queue to queue")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("normal command should replace current order, got %d orders" % orders.size())
		return false
	if input.future_order_count_for_entity(5) != 0:
		push_error("normal command should clear future orders")
		return false
	return _expect_order(orders[0], EntityOrder.Type.MOVE, 5, Vector2i(9, 9), -1, [])


func _test_sets_producer_rally() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(11)
	if not input.issue_rally_move(Vector2i(9, 9)):
		push_error("base should set move rally")
		return false
	var base: Entity = setup.state.get_entity_by_id(11)
	if (
		base.production_state.rally_mode != ProductionState.RALLY_MODE_MOVE
		or base.production_state.rally_target_tile != Vector2i(9, 9)
		or base.production_state.rally_target_entity_id != -1
	):
		push_error("move rally state did not persist on producer")
		return false
	if not input.issue_rally_gather(3):
		push_error("base should set gather rally to mineral")
		return false
	if (
		base.production_state.rally_mode != ProductionState.RALLY_MODE_GATHER
		or base.production_state.rally_target_entity_id != 3
	):
		push_error("gather rally state did not persist on producer")
		return false
	var cloned: ProductionState = base.production_state.clone()
	cloned.rally_target_entity_id = 999
	return base.production_state.rally_target_entity_id == 3


func _test_queues_spawned_unit_rally_orders() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	var state: MatchState = setup.state
	input.bind_context(state, setup.registry)
	var base: Entity = state.get_entity_by_id(11)
	base.production_state.rally_mode = ProductionState.RALLY_MODE_MOVE
	base.production_state.rally_target_tile = Vector2i(9, 9)
	_add_entity(state, 12, "worker", 0, Vector2i(4, 8), Vector2i(1, 1), 40)
	var move_event: ResolverEvent = ResolverEvent.new()
	move_event.type = ResolverEvent.Type.TRAIN_COMPLETED
	move_event.actor_id = 11
	move_event.target_id = 12
	input.queue_rally_orders_for_train_completed([move_event])
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("move rally should queue one spawned-unit order, got %d" % orders.size())
		return false
	if not _expect_order(orders[0], EntityOrder.Type.MOVE_ONLY, 12, Vector2i(9, 9), -1, []):
		return false
	input.clear_submissions()
	base.production_state.rally_mode = ProductionState.RALLY_MODE_GATHER
	base.production_state.rally_target_entity_id = 3
	_add_entity(state, 13, "worker", 0, Vector2i(4, 9), Vector2i(1, 1), 40)
	var gather_event: ResolverEvent = ResolverEvent.new()
	gather_event.type = ResolverEvent.Type.TRAIN_COMPLETED
	gather_event.actor_id = 11
	gather_event.target_id = 13
	input.queue_rally_orders_for_train_completed([gather_event])
	orders = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("gather rally should queue one spawned-unit order, got %d" % orders.size())
		return false
	return _expect_order(orders[0], EntityOrder.Type.GATHER, 13, Vector2i.ZERO, 3, [])


func _test_rally_gather_retargets_when_source_full() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	var state: MatchState = setup.state
	var registry: EntityRegistry = setup.registry
	var mineral_def: EntityDef = registry.get_by_id("mineral_patch")
	if mineral_def == null or mineral_def.resource_source == null:
		push_error("expected mineral_patch resource_source definition in test registry")
		return false
	mineral_def.resource_source.max_gatherers = 1
	input.bind_context(state, registry)
	var base: Entity = state.get_entity_by_id(11)
	base.production_state.rally_mode = ProductionState.RALLY_MODE_GATHER
	base.production_state.rally_target_entity_id = 3
	var occupying_worker: Entity = state.get_entity_by_id(1)
	occupying_worker.gather_state.assigned_source_entity_id = 3
	occupying_worker.gather_state.phase = GatherState.Phase.GATHERING
	_add_entity(state, 13, "worker", 0, Vector2i(4, 9), Vector2i(1, 1), 40)
	_add_entity(state, 14, "mineral_patch", -1, Vector2i(6, 4), Vector2i(1, 1), 0)
	state.get_entity_by_id(14).current_resource_amount = 500
	var gather_event: ResolverEvent = ResolverEvent.new()
	gather_event.type = ResolverEvent.Type.TRAIN_COMPLETED
	gather_event.actor_id = 11
	gather_event.target_id = 13
	input.queue_rally_orders_for_train_completed([gather_event])
	var result: ResolveResult = Resolver.resolve(
		state, input.submit_for_player(0), SubmitTurn.new(), registry, null
	)
	var spawned: Entity = result.new_state.get_entity_by_id(13)
	return (
		spawned != null
		and spawned.gather_state != null
		and spawned.gather_state.assigned_source_entity_id == 14
	)


func _test_cancel_removes_future_before_current() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	input.issue_move(Vector2i(6, 6))
	input.set_queue_modifier_active(true)
	input.issue_move_only(Vector2i(8, 8))
	if not input.issue_cancel():
		push_error("first cancel should remove future order")
		return false
	if input.future_order_count_for_entity(5) != 0:
		push_error("first cancel should clear the future queue")
		return false
	if input.submit_for_player(0).orders.size() != 1:
		push_error("first cancel should leave current order intact")
		return false
	if not input.issue_cancel():
		push_error("second cancel should remove current order")
		return false
	return input.submit_for_player(0).orders.is_empty()


func _test_promotes_future_order_when_ready() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	setup.state.get_player(0).minerals = 200
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(1)
	if not input.issue_build("barracks", Vector2i(6, 6)):
		push_error("expected BUILD to queue as current order")
		return false
	input.set_queue_modifier_active(true)
	if not input.issue_gather(3):
		push_error("expected GATHER to queue as future order behind BUILD")
		return false
	var worker: Entity = setup.state.get_entity_by_id(1)
	worker.locked_to_building_id = 42
	input.clear_submissions(false, false)
	input.promote_future_orders_for_next_turn()
	if input.submit_for_player(0).orders.size() != 0:
		push_error("future GATHER should wait while worker is locked")
		return false
	worker.locked_to_building_id = -1
	worker.pending_build_def_id = "barracks"
	input.promote_future_orders_for_next_turn()
	if input.submit_for_player(0).orders.size() != 0:
		push_error("future GATHER should wait while worker has a pending build")
		return false
	worker.pending_build_def_id = ""
	input.promote_future_orders_for_next_turn()
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("future GATHER should promote when worker is free, got %d" % orders.size())
		return false
	if input.future_order_count_for_entity(1) != 0:
		push_error("promoted future order should be removed from future queue")
		return false
	return _expect_order(orders[0], EntityOrder.Type.GATHER, 1, Vector2i.ZERO, 3, [])


func _test_standing_orders_do_not_block_future_promotion() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_move(Vector2i(6, 6)):
		push_error("expected first move to queue")
		return false
	input.set_queue_modifier_active(true)
	if not input.issue_move_only(Vector2i(8, 8)):
		push_error("expected second move to queue as future order")
		return false
	input.clear_submissions(false, false)
	var standing_order: EntityOrder = EntityOrder.new()
	standing_order.type = EntityOrder.Type.HALT_ON_SIGHT_TOGGLE
	standing_order.entity_id = 5
	standing_order.halt_on_sight = true
	input.submit_for_player(0).orders.append(standing_order)
	input.promote_future_orders_for_next_turn()
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	var saw_standing_order: bool = false
	var saw_promoted_action: bool = false
	for order in orders:
		if order == null:
			continue
		if order.type == EntityOrder.Type.HALT_ON_SIGHT_TOGGLE and order.entity_id == 5:
			saw_standing_order = true
		if (
			order.type == EntityOrder.Type.MOVE_ONLY
			and order.entity_id == 5
			and order.target_tile == Vector2i(8, 8)
		):
			saw_promoted_action = true
	if not saw_standing_order or not saw_promoted_action:
		push_error("standing orders should coexist with promoted future actions: %s" % str(orders))
		return false
	if input.future_order_count_for_entity(5) != 0:
		push_error("promoted future action should be removed from the future queue")
		return false
	return true


func _test_waits_to_promote_future_order_while_gathering() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(1)
	if not input.issue_gather(3):
		push_error("expected GATHER to queue as current order")
		return false
	input.set_queue_modifier_active(true)
	if not input.issue_move(Vector2i(8, 8)):
		push_error("expected MOVE to queue as future order behind GATHER")
		return false
	var worker: Entity = setup.state.get_entity_by_id(1)
	worker.gather_state.phase = GatherState.Phase.GATHERING
	input.clear_submissions(false, false)
	input.promote_future_orders_for_next_turn()
	if input.submit_for_player(0).orders.size() != 0:
		push_error("future MOVE should wait while worker is actively gathering")
		return false
	if input.future_order_count_for_entity(1) != 1:
		push_error("future MOVE should remain queued while worker is gathering")
		return false
	worker.gather_state.phase = GatherState.Phase.IDLE
	input.promote_future_orders_for_next_turn()
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("future MOVE should promote once worker is idle, got %d" % orders.size())
		return false
	return _expect_order(orders[0], EntityOrder.Type.MOVE, 1, Vector2i(8, 8), -1, [])


func _test_queues_build_train_research() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	setup.state.get_player(0).minerals = 200
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(1)
	if not input.issue_build("barracks", Vector2i(6, 6)):
		push_error("expected worker to queue BUILD barracks")
		return false
	var build_order: EntityOrder = input.submit_for_player(0).orders[0]
	if build_order.type != EntityOrder.Type.BUILD:
		push_error("expected BUILD order")
		return false
	if build_order.entity_id != 1 or build_order.def_id != "barracks":
		push_error("BUILD should target worker #1 and barracks")
		return false
	if build_order.target_tile != Vector2i(5, 5) or build_order.target_entity_id != -1:
		push_error("BUILD should carry centered target tile and no resume target")
		return false
	input.select_entity(6)
	if not input.issue_train("marine"):
		push_error("expected barracks to queue TRAIN marine")
		return false
	if not input.issue_research("stim_research"):
		push_error("expected barracks to queue RESEARCH stim_research")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders[1].type != EntityOrder.Type.TRAIN or orders[1].def_id != "marine":
		push_error("second order should be TRAIN marine")
		return false
	if orders[2].type != EntityOrder.Type.RESEARCH or orders[2].def_id != "stim_research":
		push_error("third order should be RESEARCH stim_research")
		return false
	return true


func _test_snaps_refinery_build_to_geyser_origin() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	setup.state.get_player(0).minerals = 200
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(1)
	if not input.issue_build("refinery", Vector2i(6, 9)):
		push_error("expected refinery BUILD to accept a click inside the geyser footprint")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("expected exactly one refinery BUILD order, got %d" % orders.size())
		return false
	var build_order: EntityOrder = orders[0]
	if build_order.target_tile != Vector2i(5, 8):
		push_error(
			(
				"refinery BUILD should target geyser origin (5, 8), got %s"
				% str(build_order.target_tile)
			)
		)
		return false
	return true


func _test_build_placement_preview() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	if not input.has_method("build_placement_preview"):
		push_error("DevTurnInput should expose build_placement_preview")
		return false
	var setup: Dictionary = _make_input_setup()
	setup.state.get_player(0).minerals = 200
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(1)
	var clear_preview: Dictionary = input.build_placement_preview("barracks", Vector2i(6, 6))
	var ok: bool = true
	if not clear_preview.get("valid", false):
		push_error("clear barracks placement should preview as valid: %s" % clear_preview)
		ok = false
	if clear_preview.get("origin", Vector2i.ZERO) != Vector2i(5, 5):
		push_error("barracks preview should center the 3x3 footprint on the clicked tile")
		ok = false
	if clear_preview.get("footprint", Vector2i.ZERO) != Vector2i(3, 3):
		push_error("barracks preview should report a 3x3 footprint")
		ok = false
	var occupied_preview: Dictionary = input.build_placement_preview("barracks", Vector2i(8, 4))
	if occupied_preview.get("valid", true):
		push_error("occupied barracks placement should preview as invalid")
		ok = false
	var occupied_message: String = occupied_preview.get("message", "")
	if occupied_message.find("occupied") == -1:
		push_error("occupied preview should explain occupancy, got: %s" % occupied_message)
		ok = false
	var refinery_preview: Dictionary = input.build_placement_preview("refinery", Vector2i(6, 9))
	if not refinery_preview.get("valid", false):
		push_error(
			"refinery preview inside geyser footprint should be valid: %s" % refinery_preview
		)
		ok = false
	if refinery_preview.get("origin", Vector2i.ZERO) != Vector2i(5, 8):
		push_error(
			(
				"refinery preview should snap to geyser origin, got %s"
				% str(refinery_preview.get("origin", Vector2i.ZERO))
			)
		)
		ok = false
	if refinery_preview.get("footprint", Vector2i.ZERO) != Vector2i(2, 2):
		push_error("refinery preview should report the geyser/refinery 2x2 footprint")
		ok = false
	return ok


func _test_rejects_occupied_target_build_preview() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	setup.state.get_player(0).minerals = 200
	var existing_refinery: Entity = Entity.new()
	existing_refinery.id = setup.state.allocate_entity_id()
	existing_refinery.def_id = "refinery"
	existing_refinery.current_def_id = "refinery"
	existing_refinery.owner_player_id = 0
	existing_refinery.origin = Vector2i(5, 8)
	existing_refinery.current_hp = 750
	setup.state.entities.append(existing_refinery)
	if not setup.state.tile_grid.place_overlapping(
		existing_refinery.id, Rect2i(Vector2i(5, 8), Vector2i(2, 2)), 10
	):
		push_error("test setup should place an existing refinery over the geyser")
		return false
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(1)
	var preview: Dictionary = input.build_placement_preview("refinery", Vector2i(6, 9))
	var ok: bool = true
	if preview.get("valid", true):
		push_error("refinery preview should be invalid when the geyser already has a refinery")
		ok = false
	var message: String = preview.get("message", "")
	if message.find("occupied") == -1:
		push_error("occupied target preview should explain occupancy, got: %s" % message)
		ok = false
	if input.issue_build("refinery", Vector2i(6, 9), 10):
		push_error("targeted refinery BUILD should reject an already occupied geyser")
		ok = false
	if input.submit_for_player(0).orders.size() != 0:
		push_error("rejected refinery BUILD should not append an order")
		ok = false
	return ok


func _test_tagged_build_target_survives_overlapping_occupant() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	setup.state.get_player(0).minerals = 200
	var marine: Entity = setup.state.get_entity_by_id(5)
	marine.origin = Vector2i(6, 9)
	if not setup.state.tile_grid.move_batch({5: marine.origin}, true):
		push_error("test setup should move a marine onto the geyser tile")
		return false
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(1)
	var preview: Dictionary = input.build_placement_preview("refinery", Vector2i(6, 9))
	if preview.get("origin", Vector2i.ZERO) != Vector2i(5, 8):
		push_error("refinery target lookup should still snap to the overlapped geyser")
		return false
	var message: String = preview.get("message", "")
	if preview.get("valid", true) or message.find("occupied") == -1:
		push_error("overlapped geyser should be rejected as occupied, got: %s" % preview)
		return false
	return true


func _test_rejects_unaffordable_build_without_queue() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	setup.state.get_player(0).minerals = 50
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(1)
	if input.issue_build("barracks", Vector2i(6, 6)):
		push_error("unaffordable BUILD should be rejected before queueing")
		return false
	if input.submit_for_player(0).orders.size() != 0:
		push_error("rejected BUILD should not append an order")
		return false
	if input.status_message().find("Need") == -1 or input.status_message().find("150M") == -1:
		push_error("unaffordable BUILD should explain the cost gap: %s" % input.status_message())
		return false
	return true


func _test_rejects_occupied_build_without_queue() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	setup.state.get_player(0).minerals = 200
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(1)
	if input.issue_build("barracks", Vector2i(8, 4)):
		push_error("BUILD overlapping existing barracks should be rejected before queueing")
		return false
	if input.submit_for_player(0).orders.size() != 0:
		push_error("occupied BUILD should not append an order")
		return false
	if input.status_message().find("occupied") == -1:
		push_error("occupied BUILD should explain placement failure: %s" % input.status_message())
		return false
	return true


func _test_derives_command_options() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(1)
	var worker_builds: Array[String] = input.build_option_ids()
	if not worker_builds.has("barracks"):
		push_error("worker build options should include barracks")
		return false
	if worker_builds.has("worker"):
		push_error("build options should not include trainable units")
		return false
	if not input.train_option_ids().is_empty():
		push_error("worker should not expose train options")
		return false
	input.select_entity(9)
	if not input.can_issue_move():
		push_error("non-combat mover should expose Move")
		return false
	if not input.can_issue_move_only():
		push_error("non-combat mover should expose Move Only")
		return false
	input.select_entity(5)
	setup.state.get_entity_by_id(5).focus_target_entity_id = 2
	if not input.can_issue_move_only():
		push_error("movable unit should expose Move Only")
		return false
	if not input.can_issue_halt_on_sight_toggle():
		push_error("combat unit should expose halt-on-sight")
		return false
	if not input.can_issue_cancel():
		push_error("selected unit with focus target should expose cancel")
		return false
	input.select_entity(6)
	if input.build_option_ids().has("barracks"):
		push_error("barracks should not expose worker-built buildings")
		return false
	var train_ids: Array[String] = input.train_option_ids()
	var research_ids: Array[String] = input.research_option_ids()
	if train_ids != ["marine"]:
		push_error("expected barracks train ids [marine], got %s" % str(train_ids))
		return false
	if research_ids != ["stim_research"]:
		push_error("expected barracks research ids [stim_research], got %s" % str(research_ids))
		return false
	setup.state.get_player(0).unlocked_researches.append("stim_research")
	if not input.research_option_ids().is_empty():
		push_error("unlocked research should disappear from command options")
		return false
	return true


func _test_cancel_removes_selected_unit_queued_order() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(1)
	if not input.issue_move(Vector2i(6, 6)):
		push_error("expected MOVE to queue for selected worker")
		return false
	if not input.can_issue_cancel():
		push_error("selected worker with a queued order should expose cancel")
		return false
	if not input.issue_cancel():
		push_error("cancel should remove the selected worker's queued order")
		return false
	if input.submit_for_player(0).orders.size() != 0:
		push_error("selected worker cancel should remove queued order immediately")
		return false
	if input.status_message().find("queued order") == -1:
		push_error("cancel status should mention the queued order: %s" % input.status_message())
		return false
	return true


func _test_queues_use_ability() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	setup.state.get_player(0).unlocked_researches.append("stim_research")
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if input.ability_option_ids() != ["stim"]:
		push_error(
			(
				"expected selected marine ability options [stim], got %s"
				% str(input.ability_option_ids())
			)
		)
		return false
	if not input.issue_ability("stim"):
		push_error("expected selected marine to queue USE_ABILITY stim")
		return false
	var order: EntityOrder = input.submit_for_player(0).orders[0]
	if order.type != EntityOrder.Type.USE_ABILITY or order.def_id != "stim":
		push_error("expected USE_ABILITY stim order")
		return false
	setup.state.get_entity_by_id(5).ability_cooldowns = {"stim": 2}
	if not input.ability_option_ids().is_empty():
		push_error("cooldown should hide stim ability option")
		return false
	return true


func _test_snapshot_restore() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	input.issue_move_only(Vector2i(9, 1))
	input.set_queue_modifier_active(true)
	input.issue_move(Vector2i(8, 1))
	input.set_active_player_id(1)
	input.select_entity(2)
	input.issue_move_only(Vector2i(6, 1))
	input.set_queue_modifier_active(true)
	var snapshot: DevInputSnapshot = input.create_snapshot()
	var restored: DevTurnInput = _make_input()
	var restored_state: MatchState = setup.state.clone()
	restored.restore_snapshot(snapshot, restored_state, setup.registry)
	var ok: bool = true
	if restored.active_player_id() != 1:
		push_error("snapshot restore should preserve active player")
		ok = false
	if restored.selected_entity_id() != 2:
		push_error("snapshot restore should preserve selected entity")
		ok = false
	if not restored.queue_modifier_active():
		push_error("snapshot restore should preserve queue modifier")
		ok = false
	if restored.submit_for_player(0).orders.size() != 1:
		push_error("snapshot restore should preserve P0 submission")
		ok = false
	if restored.submit_for_player(1).orders.size() != 1:
		push_error("snapshot restore should preserve P1 submission")
		ok = false
	if restored.future_order_count_for_entity(5) != 1:
		push_error("snapshot restore should preserve future order queue")
		ok = false
	restored.clear_submissions(false, false)
	restored.queue_move_assists_for_next_turn()
	if restored.submit_for_player(0).orders.size() != 1:
		push_error("snapshot restore should preserve P0 move assist")
		ok = false
	if restored.submit_for_player(1).orders.size() != 1:
		push_error("snapshot restore should preserve P1 move assist")
		ok = false
	return ok


func _test_snapshot_restore_skips_malformed_order_entries() -> bool:
	var setup: Dictionary = _make_input_setup()
	var valid_assist: EntityOrder = EntityOrder.new()
	valid_assist.type = EntityOrder.Type.MOVE
	valid_assist.entity_id = 5
	valid_assist.target_tile = Vector2i(6, 1)
	var valid_future: EntityOrder = EntityOrder.new()
	valid_future.type = EntityOrder.Type.MOVE_ONLY
	valid_future.entity_id = 5
	valid_future.target_tile = Vector2i(8, 1)
	var snapshot: DevInputSnapshot = DevInputSnapshot.new()
	snapshot.submit_a = SubmitTurn.new()
	snapshot.submit_b = SubmitTurn.new()
	snapshot.move_assists = {5: valid_assist, 1: "not an order"}
	snapshot.future_orders = {5: ["not an order", valid_future], 1: "not a queue"}
	var restored: DevTurnInput = _make_input()
	if restored == null:
		return false
	restored.restore_snapshot(snapshot, setup.state.clone(), setup.registry)
	if restored.future_order_count_for_entity(5) != 1:
		push_error("snapshot restore should skip malformed future order entries")
		return false
	restored.queue_move_assists_for_next_turn()
	var orders: Array[EntityOrder] = restored.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("snapshot restore should keep valid move assist after malformed entries")
		return false
	return _expect_order(orders[0], EntityOrder.Type.MOVE, 5, Vector2i(6, 1), -1, [])


func _test_snapshot_restore_prunes_invalid_future_orders() -> bool:
	var setup: Dictionary = _make_input_setup()
	var invalid_gather: EntityOrder = EntityOrder.new()
	invalid_gather.type = EntityOrder.Type.GATHER
	invalid_gather.entity_id = 1
	invalid_gather.target_entity_id = 999
	var valid_move: EntityOrder = EntityOrder.new()
	valid_move.type = EntityOrder.Type.MOVE
	valid_move.entity_id = 1
	valid_move.target_tile = Vector2i(2, 2)
	var snapshot: DevInputSnapshot = DevInputSnapshot.new()
	snapshot.submit_a = SubmitTurn.new()
	snapshot.submit_b = SubmitTurn.new()
	snapshot.future_orders = {1: [invalid_gather, valid_move]}
	var restored: DevTurnInput = _make_input()
	if restored == null:
		return false
	restored.restore_snapshot(snapshot, setup.state.clone(), setup.registry)
	if restored.future_order_count_for_entity(1) != 1:
		push_error("snapshot restore should prune future orders with missing targets")
		return false
	restored.promote_future_orders_for_next_turn()
	var orders: Array[EntityOrder] = restored.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("snapshot restore should promote only the valid future order")
		return false
	if restored.future_order_count_for_entity(1) != 0:
		push_error("promoted future order should be removed after pruning invalid entries")
		return false
	return _expect_order(orders[0], EntityOrder.Type.MOVE, 1, Vector2i(2, 2), -1, [])


func _test_clears_submissions() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(1)
	input.issue_move(Vector2i(6, 6))
	input.set_active_player_id(1)
	input.select_entity(2)
	input.issue_move(Vector2i(7, 7))
	input.clear_submissions()
	if input.submit_for_player(0).orders.size() != 0:
		push_error("clear_submissions should empty P0 orders")
		return false
	if input.submit_for_player(1).orders.size() != 0:
		push_error("clear_submissions should empty P1 orders")
		return false
	return true


func _test_surrender_active_player() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(1)
	input.surrender_active_player()
	if input.submit_for_player(0).surrender:
		push_error("P0 surrender should remain false")
		return false
	if not input.submit_for_player(1).surrender:
		push_error("P1 surrender should be true")
		return false
	return true


func _make_input() -> DevTurnInput:
	var script: Script = load(DEV_TURN_INPUT_PATH) as Script
	if script == null:
		push_error("could not load %s" % DEV_TURN_INPUT_PATH)
		return null
	return script.new() as DevTurnInput


func _make_input_setup() -> Dictionary:
	var state: MatchState = MatchState.new()
	state.tile_grid = TileGrid.new(12, 12)
	state.next_entity_id = 1
	for player_id in [0, 1]:
		var p: PlayerState = PlayerState.new()
		p.player_id = player_id
		state.players.append(p)
	var registry: EntityRegistry = EntityRegistry.new()
	registry.entities = [
		_make_def("worker", Vector2i(1, 1), true, true, false),
		_make_def("marine", Vector2i(1, 1), true, false, false),
		_make_def("mineral_patch", Vector2i(1, 1), false, false, true),
		_make_base_def(),
		_make_barracks_def(),
		_make_gas_geyser_def(),
		_make_refinery_def(),
		_make_noncombat_mover_def(),
	]
	registry.researches = [_make_research_def()]
	_add_entity(state, 1, "worker", 0, Vector2i(1, 1), Vector2i(1, 1), 40)
	_add_entity(state, 2, "marine", 1, Vector2i(7, 1), Vector2i(1, 1), 45)
	_add_entity(state, 3, "mineral_patch", -1, Vector2i(4, 4), Vector2i(1, 1), 0)
	state.get_entity_by_id(3).current_resource_amount = 500
	_add_entity(state, 4, "worker", 0, Vector2i(2, 1), Vector2i(1, 1), 0)
	_add_entity(state, 5, "marine", 0, Vector2i(3, 1), Vector2i(1, 1), 45)
	_add_entity(state, 6, "barracks", 0, Vector2i(8, 4), Vector2i(3, 3), 1000)
	_add_entity(state, 7, "mineral_patch", -1, Vector2i(10, 1), Vector2i(1, 1), 0)
	state.get_entity_by_id(7).current_resource_amount = 0
	_add_entity(state, 9, "noncombat_mover", 0, Vector2i(10, 10), Vector2i(1, 1), 10)
	_add_entity(state, 10, "gas_geyser", -1, Vector2i(5, 8), Vector2i(2, 2), 1000)
	_add_entity(state, 11, "base", 0, Vector2i(1, 8), Vector2i(3, 3), 1500)
	state.get_entity_by_id(6).production_state = ProductionState.new()
	state.get_entity_by_id(11).production_state = ProductionState.new()
	return {"state": state, "registry": registry}


func _make_def(
	id: String, footprint: Vector2i, can_move: bool, can_gather: bool, resource_source: bool
) -> EntityDef:
	var def: EntityDef = EntityDef.new()
	def.id = id
	def.footprint = footprint
	if can_move:
		var movement: MovementDef = MovementDef.new()
		movement.speed_tiles_per_turn = 3
		def.movement = movement
	var combat: CombatDef = CombatDef.new()
	combat.damage = 5
	combat.attack_range = 3
	combat.target_layers = ["ground"]
	def.combat = combat
	if can_gather:
		var gather: GatherDef = GatherDef.new()
		gather.accepts_resource_types = ["minerals", "gas"]
		def.gather = gather
		def.tags.append("worker")
	if resource_source:
		var source: ResourceSourceDef = ResourceSourceDef.new()
		source.resource_type = "minerals"
		def.resource_source = source
		def.tags.append("resource_source")
	if id == "marine":
		def.tags.append("ground")
		var construction: ConstructionDef = ConstructionDef.new()
		construction.built_by_tag = "barracks"
		def.construction = construction
		def.abilities = _abilities_def([_stim_ability()])
	return def


func _make_barracks_def() -> EntityDef:
	var def: EntityDef = EntityDef.new()
	def.id = "barracks"
	def.footprint = Vector2i(3, 3)
	def.tags = ["building", "barracks", "structure", "ground"]
	var health: HealthDef = HealthDef.new()
	health.max_hp = 1000
	def.health = health
	var construction: ConstructionDef = ConstructionDef.new()
	construction.built_by_tag = "worker"
	construction.mineral_cost = 150
	def.construction = construction
	var production: ProductionDef = ProductionDef.new()
	production.produces = ["marine"]
	production.researches = ["stim_research"]
	def.production = production
	return def


func _make_base_def() -> EntityDef:
	var def: EntityDef = EntityDef.new()
	def.id = "base"
	def.footprint = Vector2i(3, 3)
	def.tags = ["building", "base", "structure", "ground"]
	var health: HealthDef = HealthDef.new()
	health.max_hp = 1500
	def.health = health
	var production: ProductionDef = ProductionDef.new()
	production.produces = ["worker"]
	def.production = production
	return def


func _make_gas_geyser_def() -> EntityDef:
	var def: EntityDef = EntityDef.new()
	def.id = "gas_geyser"
	def.footprint = Vector2i(2, 2)
	def.tags = ["neutral", "resource_source", "gas", "gas_geyser"]
	var source: ResourceSourceDef = ResourceSourceDef.new()
	source.resource_type = "gas"
	source.requires_extractor = true
	def.resource_source = source
	return def


func _make_refinery_def() -> EntityDef:
	var def: EntityDef = EntityDef.new()
	def.id = "refinery"
	def.footprint = Vector2i(2, 2)
	def.tags = ["building", "refinery", "structure", "ground", "extractor"]
	var construction: ConstructionDef = ConstructionDef.new()
	construction.built_by_tag = "worker"
	construction.mineral_cost = 75
	construction.requires_target_tag = "gas_geyser"
	def.construction = construction
	return def


func _make_noncombat_mover_def() -> EntityDef:
	var def: EntityDef = EntityDef.new()
	def.id = "noncombat_mover"
	def.footprint = Vector2i(1, 1)
	var movement: MovementDef = MovementDef.new()
	movement.speed_tiles_per_turn = 3
	def.movement = movement
	return def


func _make_research_def() -> ResearchDef:
	var research: ResearchDef = ResearchDef.new()
	research.id = "stim_research"
	research.display_name = "Stim Pack"
	research.mineral_cost = 100
	return research


func _abilities_def(abilities: Array[AbilityDef]) -> AbilitiesDef:
	var out: AbilitiesDef = AbilitiesDef.new()
	out.abilities = abilities
	return out


func _stim_ability() -> AbilityDef:
	var ability: AbilityDef = AbilityDef.new()
	ability.id = "stim"
	ability.display_name = "Stim"
	ability.target_type = "self"
	ability.cooldown_turns = 5
	ability.requires_research_id = "stim_research"
	var cost: AbilityCost = AbilityCost.new()
	cost.type = "hp"
	cost.amount = 10
	ability.costs = [cost]
	var effect: StatBuffEffect = StatBuffEffect.new()
	effect.duration_turns = 3
	effect.damage_mult = 1.5
	effect.speed_mult = 1.5
	ability.effect = effect
	return ability


func _add_entity(
	state: MatchState,
	id: int,
	def_id: String,
	owner: int,
	origin: Vector2i,
	footprint: Vector2i,
	hp: int
) -> void:
	var e: Entity = Entity.new()
	e.id = id
	e.def_id = def_id
	e.current_def_id = def_id
	e.owner_player_id = owner
	e.origin = origin
	e.current_hp = hp
	if def_id == "worker":
		e.gather_state = GatherState.new()
	state.entities.append(e)
	state.next_entity_id = max(state.next_entity_id, id + 1)
	state.tile_grid.place(id, Rect2i(origin, footprint))


func _expect_order(
	order: EntityOrder,
	expected_type: EntityOrder.Type,
	expected_entity_id: int,
	expected_tile: Vector2i,
	expected_target_entity_id: int,
	expected_chain: Array[int]
) -> bool:
	if order == null:
		push_error("order is null")
		return false
	if order.type != expected_type:
		push_error("expected order type %d, got %d" % [expected_type, order.type])
		return false
	if order.entity_id != expected_entity_id:
		push_error("expected entity_id %d, got %d" % [expected_entity_id, order.entity_id])
		return false
	if order.target_tile != expected_tile:
		push_error("expected target tile %s, got %s" % [str(expected_tile), str(order.target_tile)])
		return false
	if order.target_entity_id != expected_target_entity_id:
		push_error(
			(
				"expected target_entity_id %d, got %d"
				% [expected_target_entity_id, order.target_entity_id]
			)
		)
		return false
	if order.target_priority_chain != expected_chain:
		push_error(
			(
				"expected target chain %s, got %s"
				% [str(expected_chain), str(order.target_priority_chain)]
			)
		)
		return false
	return true
