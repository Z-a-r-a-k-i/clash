@tool
extends Node

const DEV_TURN_INPUT_PATH: String = "res://scripts/game/dev_turn_input.gd"
const _INPUT_PERF_BUDGET_ENV_VAR := "DEV_INPUT_PERF_BUDGET_USEC"
const _INPUT_PERF_BUDGET_USEC_DEFAULT := 30000


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
		["dev_input_tracks_ordered_multi_selection", _test_tracks_ordered_multi_selection],
		["dev_input_snapshot_round_trips_selected_ids", _test_snapshot_selected_ids],
		["dev_input_queues_move_for_active_player", _test_queues_move_for_active_player],
		["dev_input_group_move_fans_out_to_movable_selection", _test_group_move_fan_out],
		["dev_input_group_move_spread_units_converge", _test_group_move_spread_units_converge],
		["dev_input_queues_attack_against_enemy", _test_queues_attack_against_enemy],
		[
			"dev_input_target_generates_firing_move_when_needed",
			_test_target_generates_firing_move_when_needed
		],
		["dev_input_group_target_and_gather_skip_ineligible", _test_group_target_and_gather_skips],
		["dev_input_replaces_duplicate_move_and_target", _test_replaces_duplicate_move_and_target],
		["dev_input_queues_gather_for_worker_resource_target", _test_queues_gather],
		[
			"dev_input_queues_move_and_applies_state_changes",
			_test_queues_move_and_applies_state_changes
		],
		["dev_input_move_allows_noncombat_movers", _test_move_allows_noncombat_movers],
		[
			"dev_input_target_preserves_existing_move_that_ends_in_range",
			_test_target_preserves_existing_move_that_ends_in_range
		],
		["dev_input_requeues_unfinished_move_assist", _test_requeues_unfinished_move_assist],
		[
			"dev_input_requeues_unfinished_target_move_assist",
			_test_requeues_unfinished_target_move_assist
		],
		[
			"dev_input_attack_move_requeues_until_enemy_in_range",
			_test_attack_move_requeues_until_enemy_in_range
		],
		[
			"dev_input_attack_move_prefers_queued_target_priority",
			_test_attack_move_prefers_queued_target_priority
		],
		[
			"dev_input_attack_move_uses_focus_target_priority",
			_test_attack_move_uses_focus_target_priority
		],
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
			"dev_input_queue_modifier_defers_target_with_generated_move",
			_test_queue_modifier_defers_target_with_generated_move
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
			"dev_input_rally_gather_idles_when_local_sources_full",
			_test_rally_gather_idles_when_local_sources_full
		],
		["dev_input_rejects_far_gather_rally", _test_rejects_far_gather_rally],
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
		["dev_input_group_ability_uses_union_and_skips_ineligible", _test_group_ability],
		["dev_input_group_cancel_removes_eligible_orders", _test_group_cancel],
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
		[
			"dev_input_records_last_resolve_income_per_player",
			_test_records_last_resolve_income_per_player
		],
		[
			"dev_input_committed_spend_sums_queued_production_orders",
			_test_committed_spend_sums_queued_production_orders
		],
		[
			"dev_input_large_group_move_stays_under_budget",
			_test_large_group_move_stays_under_budget
		],
		[
			"dev_input_large_group_target_stays_under_budget",
			_test_large_group_target_stays_under_budget
		],
	]


func _test_records_last_resolve_income_per_player() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	if input.last_income_for_player(0).get("known", true):
		push_error("income should be unknown before the first resolve")
		return false
	var events: Array[ResolverEvent] = [
		_gather_event(1, 3, 2),
		_gather_event(1, 3, 3),
		_gather_event(1, 10, 2),
		_gather_event(2, 3, 4),
		_gather_event(1, 999, 7),
	]
	input.apply_resolve_events(events)
	var income_p0: Dictionary = input.last_income_for_player(0)
	if not income_p0.get("known", false):
		push_error("income should be known after a resolve")
		return false
	if income_p0.get("minerals", -1) != 5 or income_p0.get("gas", -1) != 2:
		push_error("P0 income should split by resource kind, got %s" % [income_p0])
		return false
	var income_p1: Dictionary = input.last_income_for_player(1)
	if income_p1.get("minerals", -1) != 4 or income_p1.get("gas", -1) != 0:
		push_error("P1 income should only count P1 gatherers, got %s" % [income_p1])
		return false
	input.apply_resolve_events([] as Array[ResolverEvent])
	income_p0 = input.last_income_for_player(0)
	if income_p0.get("minerals", -1) != 0 or not income_p0.get("known", false):
		push_error("a resolve with no gathering should report known zero income")
		return false
	input.clear_submissions()
	if input.last_income_for_player(0).get("known", true):
		push_error("a full queue clear (fresh session) should reset income to unknown")
		return false
	return true


func _test_committed_spend_sums_queued_production_orders() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	var registry: EntityRegistry = setup.registry
	var marine_def: EntityDef = registry.get_by_id("marine")
	marine_def.construction.mineral_cost = 50
	marine_def.construction.gas_cost = 25
	marine_def.population = PopulationDef.new()
	marine_def.population.pop_cost = 2
	var barracks_def: EntityDef = registry.get_by_id("barracks")
	barracks_def.population = PopulationDef.new()
	barracks_def.population.pop_cost = 1
	input.bind_context(setup.state, registry)
	var spend_before: Dictionary = input.committed_spend_for_player(0)
	if spend_before.get("minerals", -1) != 0 or spend_before.get("pop", -1) != 0:
		push_error("an empty submit should commit nothing, got %s" % [spend_before])
		return false
	var submit: SubmitTurn = input.submit_for_player(0)
	submit.orders.append(_production_order(EntityOrder.Type.TRAIN, 6, "marine"))
	submit.orders.append(_production_order(EntityOrder.Type.TRAIN, 6, "marine"))
	submit.orders.append(_production_order(EntityOrder.Type.BUILD, 1, "barracks"))
	var resume_build: EntityOrder = _production_order(EntityOrder.Type.BUILD, 1, "barracks")
	resume_build.target_entity_id = 42
	submit.orders.append(resume_build)
	submit.orders.append(_production_order(EntityOrder.Type.RESEARCH, 6, "surge_research"))
	var spend: Dictionary = input.committed_spend_for_player(0)
	if spend.get("minerals", -1) != 350:
		push_error("committed minerals should sum train+build+research, got %s" % [spend])
		return false
	if spend.get("gas", -1) != 50:
		push_error("committed gas should sum both marine trains, got %s" % [spend])
		return false
	if spend.get("pop", -1) != 5:
		push_error(
			"committed pop should count trained units and non-resume builds, got %s" % [spend]
		)
		return false
	var enemy_spend: Dictionary = input.committed_spend_for_player(1)
	if enemy_spend.get("minerals", -1) != 0:
		push_error("the other player's committed spend should stay zero")
		return false
	return true


func _test_large_group_move_stays_under_budget() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_large_command_setup()
	var state: MatchState = setup["state"]
	var selected_ids: Array[int] = setup["selected_ids"]
	input.bind_context(state, setup["registry"])
	if not _select_entities_for_test(input, selected_ids):
		return false
	var target_tile := Vector2i(58, 42)
	var start_usec := Time.get_ticks_usec()
	var ok: bool = input.issue_move(target_tile)
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	if not ok:
		push_error("[large_group_move] issue_move rejected: %s" % input.status_message())
		return false
	if input.submit_for_player(0).orders.size() != selected_ids.size():
		push_error(
			"[large_group_move] expected %d orders, got %d"
			% [selected_ids.size(), input.submit_for_player(0).orders.size()]
		)
		return false
	var budget_usec := _input_perf_budget_usec()
	if elapsed_usec > budget_usec:
		push_error(
			"[large_group_move] issue_move took %.3fms; budget is %.3fms"
			% [float(elapsed_usec) / 1000.0, float(budget_usec) / 1000.0]
		)
		return false
	return true


func _test_large_group_target_stays_under_budget() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_large_command_setup()
	var state: MatchState = setup["state"]
	var selected_ids: Array[int] = setup["selected_ids"]
	var target_id: int = setup["target_id"]
	input.bind_context(state, setup["registry"])
	if not _select_entities_for_test(input, selected_ids):
		return false
	var start_usec := Time.get_ticks_usec()
	var ok: bool = input.issue_target(target_id)
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	if not ok:
		push_error("[large_group_target] issue_target rejected: %s" % input.status_message())
		return false
	if input.submit_for_player(0).orders.is_empty():
		push_error("[large_group_target] expected target orders")
		return false
	var budget_usec := _input_perf_budget_usec()
	if elapsed_usec > budget_usec:
		push_error(
			"[large_group_target] issue_target took %.3fms; budget is %.3fms"
			% [float(elapsed_usec) / 1000.0, float(budget_usec) / 1000.0]
		)
		return false
	return true


func _gather_event(actor_id: int, target_id: int, amount: int) -> ResolverEvent:
	var event: ResolverEvent = ResolverEvent.new()
	event.type = ResolverEvent.Type.WORKER_GATHERED
	event.actor_id = actor_id
	event.target_id = target_id
	event.amount = amount
	return event


func _production_order(order_type: EntityOrder.Type, entity_id: int, def_id: String) -> EntityOrder:
	var order: EntityOrder = EntityOrder.new()
	order.type = order_type
	order.entity_id = entity_id
	order.def_id = def_id
	return order


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
	if not input.select_entity(3):
		push_error("neutral resource #3 should be selectable for inspection")
		return false
	if input.can_issue_move() or input.can_issue_target() or input.can_issue_gather():
		push_error("a selected resource should expose no unit commands")
		return false
	if input.select_entity(4):
		push_error("dead owned entity #4 should not be selectable")
		return false
	return true


func _test_tracks_ordered_multi_selection() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	if not input.has_method("selected_entity_ids"):
		push_error("DevTurnInput should expose selected_entity_ids")
		return false
	if not input.has_method("select_entities"):
		push_error("DevTurnInput should expose select_entities")
		return false
	if not input.has_method("toggle_entity_selection"):
		push_error("DevTurnInput should expose toggle_entity_selection")
		return false
	if not input.has_method("has_multiple_selection"):
		push_error("DevTurnInput should expose has_multiple_selection")
		return false
	if not _select_entities_for_test(input, [5, 1, 2, 5, 4]):
		push_error("multi-select should accept live owned ids and ignore duplicates/invalid ids")
		return false
	var ids: Array[int] = _selected_ids_for_test(input)
	if ids != ([5, 1] as Array[int]):
		push_error("selected ids should preserve valid input order, got %s" % str(ids))
		return false
	if input.selected_entity_id() != 5:
		push_error("selected_entity_id should return primary selected id")
		return false
	if not input.call("has_multiple_selection"):
		push_error("two selected entities should count as multiple selection")
		return false
	if not input.call("toggle_entity_selection", 9):
		push_error("shift-toggle should add a live owned movable unit")
		return false
	ids = _selected_ids_for_test(input)
	if ids != ([5, 1, 9] as Array[int]):
		push_error("toggle add should append to ordered selection, got %s" % str(ids))
		return false
	if not input.call("toggle_entity_selection", 1):
		push_error("shift-toggle should remove an already selected unit")
		return false
	ids = _selected_ids_for_test(input)
	if ids != ([5, 9] as Array[int]):
		push_error("toggle remove should preserve remaining order, got %s" % str(ids))
		return false
	if input.call("toggle_entity_selection", 6):
		push_error("shift-toggle should reject non-movable owned buildings")
		return false
	setup.state.get_entity_by_id(5).current_hp = 0
	input.bind_context(setup.state, setup.registry)
	ids = _selected_ids_for_test(input)
	if ids != ([9] as Array[int]):
		push_error("bind_context should prune dead selected ids, got %s" % str(ids))
		return false
	input.set_active_player_id(1)
	if not _selected_ids_for_test(input).is_empty():
		push_error("active player switch should prune ids no longer owned by the active player")
		return false
	return true


func _test_snapshot_selected_ids() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	if not _select_entities_for_test(input, [5, 1, 9]):
		return false
	var snapshot: DevInputSnapshot = input.create_snapshot()
	if snapshot == null:
		push_error("expected snapshot")
		return false
	if not snapshot.has_method("clone"):
		push_error("snapshot should still be cloneable")
		return false
	var clone: DevInputSnapshot = snapshot.clone()
	var restored: DevTurnInput = _make_input()
	restored.restore_snapshot(clone, setup.state.clone(), setup.registry)
	var ids: Array[int] = _selected_ids_for_test(restored)
	if ids != ([5, 1, 9] as Array[int]):
		push_error("snapshot restore should preserve ordered selected ids, got %s" % str(ids))
		return false
	if restored.selected_entity_id() != 5:
		push_error("snapshot restore should keep primary selected id")
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
		push_error("expected Move to queue for selected worker")
		return false
	var submit_0: SubmitTurn = input.submit_for_player(0)
	var submit_1: SubmitTurn = input.submit_for_player(1)
	if submit_0.orders.size() != 1 or submit_1.orders.size() != 0:
		push_error("expected exactly one order for P0 and none for P1")
		return false
	var order: EntityOrder = submit_0.orders[0]
	return _expect_order(order, EntityOrder.Type.MOVE, 1, Vector2i(8, 8), -1, [])


# Regression: a spread-out selection must CONVERGE on the clicked tile,
# not preserve its full map-scale offsets (which sent every unit to a
# "formation" tile far from the click).
func _test_group_move_spread_units_converge() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	var state: MatchState = setup.state
	# Four marines at the map corners — maximum spread on the 12x12 grid.
	_add_entity(state, 31, "marine", 0, Vector2i(0, 0), Vector2i(1, 1), 45)
	_add_entity(state, 32, "marine", 0, Vector2i(11, 0), Vector2i(1, 1), 45)
	_add_entity(state, 33, "marine", 0, Vector2i(0, 11), Vector2i(1, 1), 45)
	_add_entity(state, 34, "marine", 0, Vector2i(11, 11), Vector2i(1, 1), 45)
	input.bind_context(state, setup.registry)
	input.set_active_player_id(0)
	if not _select_entities_for_test(input, [31, 32, 33, 34]):
		return false
	var click := Vector2i(6, 6)
	if not input.issue_move(click):
		push_error("group Move should queue for spread selected units")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 4:
		push_error("expected four MOVE orders, got %d" % orders.size())
		return false
	var seen: Dictionary = {}
	for order in orders:
		var distance: int = maxi(
			abs(order.target_tile.x - click.x), abs(order.target_tile.y - click.y)
		)
		if distance > 2:
			push_error(
				(
					"spread units should converge near the click; #%d targets %s (distance %d)"
					% [order.entity_id, str(order.target_tile), distance]
				)
			)
			return false
		if seen.has(order.target_tile):
			push_error("converged targets should stay distinct")
			return false
		seen[order.target_tile] = true
	return true


func _test_group_move_fan_out() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	if not _select_entities_for_test(input, [1, 5, 6, 9]):
		return false
	if not input.issue_move(Vector2i(11, 11)):
		push_error("group Move should queue for movable selected units")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 3:
		push_error("expected three MOVE orders and one skipped building, got %d" % orders.size())
		return false
	var expected_ids: Array[int] = [1, 5, 9]
	var target_tiles: Array[Vector2i] = []
	for i in orders.size():
		var order: EntityOrder = orders[i]
		if (
			order == null
			or order.type != EntityOrder.Type.MOVE
			or order.entity_id != expected_ids[i]
		):
			push_error("expected MOVE for selected unit #%d" % expected_ids[i])
			return false
		target_tiles.append(order.target_tile)
	if not target_tiles.has(Vector2i(11, 11)):
		push_error("group move formation should include clicked tile, got %s" % str(target_tiles))
		return false
	if _unique_tile_count(target_tiles) != expected_ids.size():
		push_error(
			"group move formation should assign distinct targets, got %s" % str(target_tiles)
		)
		return false
	if input.status_message().find("Skipped 1") == -1:
		push_error("group move status should include skipped count: %s" % input.status_message())
		return false
	input.set_queue_modifier_active(true)
	if not input.issue_move(Vector2i(10, 10)):
		push_error("shift group MOVE should append future orders for movable selected units")
		return false
	for entity_id in expected_ids:
		if input.future_order_count_for_entity(entity_id) != 1:
			push_error("expected one future order for #%d" % entity_id)
			return false
	if input.future_order_count_for_entity(6) != 0:
		push_error("non-movable building should not get a future move order")
		return false
	return true


func _test_queues_attack_against_enemy() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	if not _move_entity(setup.state, 2, Vector2i(6, 1)):
		return false
	input.select_entity(5)
	if not input.issue_target(2):
		push_error("expected ATTACK to queue against enemy marine")
		return false
	var order: EntityOrder = input.submit_for_player(0).orders[0]
	if not _expect_order(order, EntityOrder.Type.TARGET, 5, Vector2i(6, 1), 2, [2]):
		return false
	if input.issue_target(3):
		push_error("neutral mineral patch should not be a valid attack target")
		return false
	return true


func _test_group_target_and_gather_skips() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	if not _select_entities_for_test(input, [1, 5, 6, 9]):
		return false
	if not input.issue_target(2):
		push_error("group target should queue for combat-capable selected units")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	var target_actor_ids: Array[int] = []
	for order in orders:
		if order.type != EntityOrder.Type.TARGET:
			continue
		if order.target_entity_id != 2 or order.target_priority_chain != ([2] as Array[int]):
			push_error("group target order should focus enemy #2")
			return false
		target_actor_ids.append(order.entity_id)
	if target_actor_ids != ([1, 5] as Array[int]):
		push_error("worker and marine should receive TARGET, got %s" % str(target_actor_ids))
		return false
	if input.status_message().find("Skipped 2") == -1:
		push_error("target status should include skipped count: %s" % input.status_message())
		return false
	input.clear_submissions()
	if not _select_entities_for_test(input, [1, 5, 6]):
		return false
	if not input.issue_gather(3):
		push_error("group gather should queue for worker gatherers")
		return false
	orders = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("only the worker should gather, got %d orders" % orders.size())
		return false
	if not _expect_order(orders[0], EntityOrder.Type.GATHER, 1, Vector2i.ZERO, 3, []):
		return false
	if input.status_message().find("Skipped 2") == -1:
		push_error("gather status should include skipped count: %s" % input.status_message())
		return false
	return true


func _test_target_generates_firing_move_when_needed() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.has_method("issue_target"):
		push_error("DevTurnInput should expose persistent targeted attack intent")
		return false
	if not input.call("issue_target", 2):
		push_error("expected attack target to queue for selected marine")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 2:
		push_error("out-of-range target command should queue move + target, got %d" % orders.size())
		return false
	var actor: Entity = setup.state.get_entity_by_id(5)
	if actor == null or actor.focus_target_entity_id != -1:
		push_error("target command should not mutate focus before resolver distribution")
		return false
	if not _expect_generated_target_move(orders[0], setup.state, setup.registry, 5, 2):
		return false
	return _expect_order(orders[1], EntityOrder.Type.TARGET, 5, Vector2i(7, 1), 2, [2])


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
	if not input.issue_target(2):
		push_error("expected first target to queue")
		return false
	if not input.issue_target(8):
		push_error("expected second target to replace first")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 2:
		push_error("expected latest target to replace prior move + target, got %d" % orders.size())
		return false
	if not _expect_generated_target_move(orders[0], setup.state, setup.registry, 5, 8):
		return false
	return _expect_order(orders[1], EntityOrder.Type.TARGET, 5, Vector2i(9, 7), 8, [8])


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


func _test_queues_move_and_applies_state_changes() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_move(Vector2i(6, 6)):
		push_error("expected Move to queue for selected marine")
		return false
	if input.has_method("issue_move_only"):
		push_error("DevTurnInput should not expose legacy issue_move_only")
		return false
	if not input.issue_cancel():
		push_error("expected CANCEL to clear selected marine state")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 0:
		push_error("expected queued Move to be cancelled, got %d orders" % orders.size())
		return false
	if EntityOrder.Type.has("MOVE_ONLY"):
		push_error("EntityOrder.Type should not define MOVE_ONLY")
		return false
	var actor: Entity = setup.state.get_entity_by_id(5)
	if actor == null:
		push_error("expected selected marine to exist")
		return false
	if actor.focus_target_entity_id != -1:
		push_error("Move/CANCEL flow should not create target focus")
		return false
	return true


func _test_move_allows_noncombat_movers() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(9)
	if not input.can_issue_move():
		push_error("noncombat mover should be allowed to use Move")
		return false
	if not input.issue_move(Vector2i(11, 11)):
		push_error("expected noncombat mover Move to queue")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("expected one noncombat mover order, got %d" % orders.size())
		return false
	return _expect_order(orders[0], EntityOrder.Type.MOVE, 9, Vector2i(11, 11), -1, [])


func _test_target_preserves_existing_move_that_ends_in_range() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_move(Vector2i(4, 1)):
		push_error("expected Move ending in range to queue for selected marine")
		return false
	if not input.issue_target(2):
		push_error("expected target to queue for selected marine")
		return false
	var actor: Entity = setup.state.get_entity_by_id(5)
	if actor.focus_target_entity_id != -1:
		push_error("target command should not mutate focus before resolver distribution")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 2:
		push_error(
			(
				"target command should preserve the existing move and add TARGET, got %d"
				% orders.size()
			)
		)
		return false
	if not _expect_order(orders[0], EntityOrder.Type.MOVE, 5, Vector2i(4, 1), -1, []):
		return false
	return _expect_order(orders[1], EntityOrder.Type.TARGET, 5, Vector2i(7, 1), 2, [2])


func _test_requeues_unfinished_move_assist() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_move(Vector2i(9, 1)):
		push_error("expected Move to queue for selected marine")
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
	return _expect_order(orders[0], EntityOrder.Type.MOVE, 5, Vector2i(9, 1), -1, [])


func _test_requeues_unfinished_target_move_assist() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_target(2):
		push_error("expected TARGET to queue for selected marine")
		return false
	var first_orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if first_orders.size() != 2:
		push_error(
			"target assist should start as generated move + TARGET, got %d" % first_orders.size()
		)
		return false
	if not _expect_generated_target_move(first_orders[0], setup.state, setup.registry, 5, 2):
		return false
	if not _expect_order(first_orders[1], EntityOrder.Type.TARGET, 5, Vector2i(7, 1), 2, [2]):
		return false
	if not _move_entity(setup.state, 2, Vector2i(8, 1)):
		return false
	input.clear_submissions(false, false)
	input.queue_move_assists_for_next_turn()
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("unfinished target move assist should requeue one order, got %d" % orders.size())
		return false
	return _expect_generated_target_move(orders[0], setup.state, setup.registry, 5, 2)


func _test_attack_move_requeues_until_enemy_in_range() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	var state: MatchState = setup.state
	var registry: EntityRegistry = setup.registry
	var marine_def: EntityDef = registry.get_by_id("marine")
	if marine_def == null or marine_def.combat == null or marine_def.vision == null:
		push_error("attack-move continuation test needs marine combat and vision")
		return false
	marine_def.combat.attack_range = 3
	marine_def.vision.sight_radius = 4
	if not _move_entity(state, 7, Vector2i(0, 11)):
		return false
	if not _move_entity(state, 9, Vector2i(7, 11)):
		return false
	_add_entity(state, 12, "base", 1, Vector2i(8, 8), Vector2i(3, 3), 1500)
	if not _move_entity(state, 2, Vector2i(11, 1)):
		return false
	input.bind_context(state, registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_attack_move(Vector2i(11, 2)):
		push_error("expected Attack Move to queue for selected marine")
		return false

	var result: ResolveResult = Resolver.resolve(
		state, input.submit_for_player(0), SubmitTurn.new(), registry, null
	)
	state = result.new_state
	input.bind_context(state, registry)
	input.clear_submissions(false, false)
	input.apply_resolve_events(result.events)
	input.queue_move_assists_for_next_turn()
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("sight-only attack-move should requeue one order, got %d" % orders.size())
		return false
	if not _expect_order(orders[0], EntityOrder.Type.ATTACK_MOVE, 5, Vector2i(11, 2), -1, []):
		return false

	result = Resolver.resolve(state, input.submit_for_player(0), SubmitTurn.new(), registry, null)
	state = result.new_state
	var actor: Entity = state.get_entity_by_id(5)
	var enemy: Entity = state.get_entity_by_id(2)
	var actor_rect: Rect2i = state.tile_grid.entity_rect(actor.id) if actor != null else Rect2i()
	var enemy_rect: Rect2i = state.tile_grid.entity_rect(enemy.id) if enemy != null else Rect2i()
	var distance: int = TileGrid.distance_between_rects(actor_rect, enemy_rect)
	if actor == null or enemy == null or distance > marine_def.combat.attack_range:
		push_error(
			(
				"attack-move should advance to firing range, got distance %d at %s"
				% [distance, str(actor.origin if actor != null else Vector2i(-1, -1))]
			)
		)
		return false
	input.bind_context(state, registry)
	input.clear_submissions(false, false)
	input.apply_resolve_events(result.events)
	input.queue_move_assists_for_next_turn()
	if input.submit_for_player(0).orders.size() != 0:
		push_error("attack-move should stop requeueing once enemy is in weapon range")
		return false
	return true


func _test_attack_move_prefers_queued_target_priority() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	_add_entity(setup.state, 8, "marine", 1, Vector2i(8, 2), Vector2i(1, 1), 45)
	var actor: Entity = setup.state.get_entity_by_id(5)
	actor.focus_target_entity_id = 8
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_target(2):
		push_error("expected TARGET to queue for selected marine")
		return false
	if not input.issue_attack_move(Vector2i(11, 2)):
		push_error("expected Attack Move to queue for selected marine")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("attack-move should replace queued target orders, got %d" % orders.size())
		return false
	return _expect_order(orders[0], EntityOrder.Type.ATTACK_MOVE, 5, Vector2i(11, 2), -1, [2])


func _test_attack_move_uses_focus_target_priority() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	var actor: Entity = setup.state.get_entity_by_id(5)
	actor.focus_target_entity_id = 2
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_attack_move(Vector2i(11, 2)):
		push_error("expected Attack Move to queue for selected marine")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("attack-move should queue one order, got %d" % orders.size())
		return false
	return _expect_order(orders[0], EntityOrder.Type.ATTACK_MOVE, 5, Vector2i(11, 2), -1, [2])


func _test_drops_completed_move_assist() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_move(Vector2i(9, 1)):
		push_error("expected Move to queue for selected marine")
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
		push_error("expected Move to queue for selected marine")
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
		push_error("expected Move to queue for selected worker")
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
	if not input.issue_move(Vector2i(8, 8)):
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
		and _expect_order(future[0], EntityOrder.Type.MOVE, 5, Vector2i(8, 8), -1, [])
	)


func _test_queue_modifier_defers_target_with_generated_move() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if not input.issue_move(Vector2i(6, 6)):
		push_error("expected first move to queue for this turn")
		return false
	input.set_queue_modifier_active(true)
	if not input.issue_target(2):
		push_error("expected queue-modified target to append as future orders")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("queued target should keep one current order, got %d" % orders.size())
		return false
	var future: Array[EntityOrder] = input.future_orders_for_entity(5)
	if future.size() != 2:
		push_error("queued target should defer generated MOVE and TARGET, got %d" % future.size())
		return false
	if not _expect_generated_target_move(future[0], setup.state, setup.registry, 5, 2):
		return false
	if not _expect_order(future[1], EntityOrder.Type.TARGET, 5, Vector2i(7, 1), 2, [2]):
		return false
	input.clear_submissions(false, false)
	input.promote_future_orders_for_next_turn()
	orders = input.submit_for_player(0).orders
	if orders.size() != 2:
		push_error("future target pair should promote together, got %d orders" % orders.size())
		return false
	if input.future_order_count_for_entity(5) != 0:
		push_error("promoted target pair should clear the future queue")
		return false
	return (
		_expect_generated_target_move(orders[0], setup.state, setup.registry, 5, 2)
		and _expect_order(orders[1], EntityOrder.Type.TARGET, 5, Vector2i(7, 1), 2, [2])
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
	input.issue_move(Vector2i(8, 8))
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
	if not _expect_order(orders[0], EntityOrder.Type.MOVE, 12, Vector2i(9, 9), -1, []):
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


func _test_rally_gather_idles_when_local_sources_full() -> bool:
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
	var gather_event: ResolverEvent = ResolverEvent.new()
	gather_event.type = ResolverEvent.Type.TRAIN_COMPLETED
	gather_event.actor_id = 11
	gather_event.target_id = 13
	input.queue_rally_orders_for_train_completed([gather_event])
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if not orders.is_empty():
		push_error("full local rally sources should leave spawned worker idle")
		return false
	return true


func _test_rejects_far_gather_rally() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var base_setup: Dictionary = _make_input_setup()
	var registry: EntityRegistry = base_setup.registry
	var state: MatchState = MatchState.new()
	state.tile_grid = TileGrid.new(40, 20)
	state.next_entity_id = 1
	for player_id in [0, 1]:
		var player: PlayerState = PlayerState.new()
		player.player_id = player_id
		state.players.append(player)
	_add_entity(state, 11, "base", 0, Vector2i(1, 8), Vector2i(3, 3), 1500)
	state.get_entity_by_id(11).production_state = ProductionState.new()
	_add_entity(state, 3, "mineral_patch", -1, Vector2i(30, 8), Vector2i(1, 1), 0)
	state.get_entity_by_id(3).current_resource_amount = 500
	input.bind_context(state, registry)
	input.set_active_player_id(0)
	input.select_entity(11)
	if input.issue_rally_gather(3):
		push_error("far gather rally target should be rejected")
		return false
	if state.get_entity_by_id(11).production_state.rally_mode != ProductionState.RALLY_MODE_NONE:
		push_error("rejected far gather rally should not mutate producer rally state")
		return false
	return input.status_message().find("too far") >= 0


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
	input.issue_move(Vector2i(8, 8))
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
	if not input.issue_move(Vector2i(8, 8)):
		push_error("expected second move to queue as future order")
		return false
	input.clear_submissions(false, false)
	var standing_order: EntityOrder = EntityOrder.new()
	standing_order.type = EntityOrder.Type.TARGET
	standing_order.entity_id = 5
	standing_order.target_entity_id = 2
	standing_order.target_priority_chain = [2]
	input.submit_for_player(0).orders.append(standing_order)
	input.promote_future_orders_for_next_turn()
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	var saw_standing_order: bool = false
	var saw_promoted_action: bool = false
	for order in orders:
		if order == null:
			continue
		if order.type == EntityOrder.Type.TARGET and order.entity_id == 5:
			saw_standing_order = true
		if (
			order.type == EntityOrder.Type.MOVE
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
		push_error("expected Move to queue as future order behind GATHER")
		return false
	var worker: Entity = setup.state.get_entity_by_id(1)
	worker.gather_state.phase = GatherState.Phase.GATHERING
	input.clear_submissions(false, false)
	input.promote_future_orders_for_next_turn()
	if input.submit_for_player(0).orders.size() != 0:
		push_error("future Move should wait while worker is actively gathering")
		return false
	if input.future_order_count_for_entity(1) != 1:
		push_error("future Move should remain queued while worker is gathering")
		return false
	worker.gather_state.phase = GatherState.Phase.IDLE
	input.promote_future_orders_for_next_turn()
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("future Move should promote once worker is idle, got %d" % orders.size())
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
	if not input.issue_research("surge_research"):
		push_error("expected barracks to queue RESEARCH surge_research")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders[1].type != EntityOrder.Type.TRAIN or orders[1].def_id != "marine":
		push_error("second order should be TRAIN marine")
		return false
	if orders[2].type != EntityOrder.Type.RESEARCH or orders[2].def_id != "surge_research":
		push_error("third order should be RESEARCH surge_research")
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
	if not input.can_issue_move():
		push_error("non-combat mover should expose Move")
		return false
	input.select_entity(5)
	setup.state.get_entity_by_id(5).focus_target_entity_id = 2
	if not input.can_issue_move():
		push_error("movable unit should expose Move")
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
	if research_ids != ["surge_research"]:
		push_error("expected barracks research ids [surge_research], got %s" % str(research_ids))
		return false
	setup.state.get_player(0).unlocked_researches.append("surge_research")
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
		push_error("expected Move to queue for selected worker")
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
	setup.state.get_player(0).unlocked_researches.append("surge_research")
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	input.select_entity(5)
	if input.ability_option_ids() != ["surge"]:
		push_error(
			(
				"expected selected marine ability options [surge], got %s"
				% str(input.ability_option_ids())
			)
		)
		return false
	if not input.issue_ability("surge"):
		push_error("expected selected marine to queue USE_ABILITY surge")
		return false
	var order: EntityOrder = input.submit_for_player(0).orders[0]
	if order.type != EntityOrder.Type.USE_ABILITY or order.def_id != "surge":
		push_error("expected USE_ABILITY surge order")
		return false
	setup.state.get_entity_by_id(5).ability_cooldowns = {"surge": 2}
	if not input.ability_option_ids().is_empty():
		push_error("cooldown should hide surge ability option")
		return false
	return true


func _test_group_ability() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	setup.state.get_player(0).unlocked_researches.append("surge_research")
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	if not _select_entities_for_test(input, [1, 5, 9]):
		return false
	if input.ability_option_ids() != ["surge"]:
		push_error("group ability options should be the union of selected abilities")
		return false
	if not input.issue_ability("surge"):
		push_error("group ability should queue for eligible selected units")
		return false
	var orders: Array[EntityOrder] = input.submit_for_player(0).orders
	if orders.size() != 1:
		push_error("only the marine should receive surge, got %d orders" % orders.size())
		return false
	if (
		orders[0].type != EntityOrder.Type.USE_ABILITY
		or orders[0].entity_id != 5
		or orders[0].def_id != "surge"
	):
		push_error("expected USE_ABILITY surge for marine #5")
		return false
	if input.status_message().find("Skipped 2") == -1:
		push_error("group ability status should include skipped count: %s" % input.status_message())
		return false
	return true


func _test_group_cancel() -> bool:
	var input: DevTurnInput = _make_input()
	if input == null:
		return false
	var setup: Dictionary = _make_input_setup()
	input.bind_context(setup.state, setup.registry)
	input.set_active_player_id(0)
	if not _select_entities_for_test(input, [1, 5, 9]):
		return false
	if not input.issue_move(Vector2i(11, 11)):
		push_error("expected group Move before cancel")
		return false
	if input.submit_for_player(0).orders.size() != 3:
		push_error("expected three queued orders before group cancel")
		return false
	if not input.issue_cancel():
		push_error("group cancel should remove queued orders from eligible selected units")
		return false
	if input.submit_for_player(0).orders.size() != 0:
		push_error("group cancel should remove all selected queued orders")
		return false
	if input.status_message().find("Cancelled") == -1:
		push_error("group cancel should report cancelled orders: %s" % input.status_message())
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
	input.issue_move(Vector2i(9, 1))
	input.set_queue_modifier_active(true)
	input.issue_move(Vector2i(8, 1))
	input.set_active_player_id(1)
	input.select_entity(2)
	input.issue_move(Vector2i(6, 1))
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
	valid_future.type = EntityOrder.Type.MOVE
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


func _select_entities_for_test(input: DevTurnInput, ids: Array[int]) -> bool:
	if input == null:
		return false
	if not input.has_method("select_entities"):
		push_error("DevTurnInput should expose select_entities")
		return false
	return input.call("select_entities", ids)


func _selected_ids_for_test(input: DevTurnInput) -> Array[int]:
	var out: Array[int] = []
	if input == null:
		return out
	if not input.has_method("selected_entity_ids"):
		push_error("DevTurnInput should expose selected_entity_ids")
		return out
	var raw: Array = input.call("selected_entity_ids")
	for item in raw:
		out.append(int(item))
	return out


func _unique_tile_count(tiles: Array[Vector2i]) -> int:
	var seen: Dictionary = {}
	for tile in tiles:
		seen[tile] = true
	return seen.size()


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


func _make_large_command_setup() -> Dictionary:
	var state: MatchState = MatchState.new()
	state.tile_grid = TileGrid.new(72, 56)
	state.next_entity_id = 1
	for player_id in [0, 1]:
		var player: PlayerState = PlayerState.new()
		player.player_id = player_id
		state.players.append(player)
	var registry: EntityRegistry = EntityRegistry.new()
	registry.entities = [
		_make_def("marine", Vector2i(1, 1), true, false, false),
		_make_barracks_def(),
	]
	var selected_ids: Array[int] = []
	for y in range(5):
		for x in range(10):
			var entity_id: int = state.allocate_entity_id()
			_add_entity(state, entity_id, "marine", 0, Vector2i(5 + x, 8 + y), Vector2i.ONE, 45)
			selected_ids.append(entity_id)
	var target_id: int = state.allocate_entity_id()
	_add_entity(state, target_id, "marine", 1, Vector2i(62, 43), Vector2i.ONE, 45)
	for y in range(6):
		for x in range(6):
			if (x + y) % 3 != 0:
				continue
			var blocker_id: int = state.allocate_entity_id()
			_add_entity(
				state,
				blocker_id,
				"barracks",
				1,
				Vector2i(30 + x * 2, 20 + y * 2),
				Vector2i(3, 3),
				1000
			)
	return {
		"state": state,
		"registry": registry,
		"selected_ids": selected_ids,
		"target_id": target_id,
	}


func _input_perf_budget_usec() -> int:
	var override: String = OS.get_environment(_INPUT_PERF_BUDGET_ENV_VAR)
	if override.is_valid_int():
		var value: int = override.to_int()
		if value > 0:
			return value
	return _INPUT_PERF_BUDGET_USEC_DEFAULT


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
	var vision: VisionDef = VisionDef.new()
	vision.sight_radius = 99
	def.vision = vision
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
		def.abilities = _abilities_def([_surge_ability()])
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
	production.researches = ["surge_research"]
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
	research.id = "surge_research"
	research.display_name = "Surge Pack"
	research.mineral_cost = 100
	return research


func _abilities_def(abilities: Array[AbilityDef]) -> AbilitiesDef:
	var out: AbilitiesDef = AbilitiesDef.new()
	out.abilities = abilities
	return out


func _surge_ability() -> AbilityDef:
	var ability: AbilityDef = AbilityDef.new()
	ability.id = "surge"
	ability.display_name = "Surge"
	ability.target_type = "self"
	ability.cooldown_turns = 5
	ability.requires_research_id = "surge_research"
	var cost: AbilityCost = AbilityCost.new()
	cost.type = "hp"
	cost.amount = 10
	ability.costs = [cost]
	var status: StatusEffect = StatusEffect.new()
	status.status_id = "surge"
	status.duration_turns = 3
	status.damage_mult_pct = 150
	status.speed_mult_pct = 150
	var effect: StatusApplyEffect = StatusApplyEffect.new()
	effect.status = status
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
	e.current_layer = "ground"
	e.current_hp = hp
	if def_id == "worker":
		e.gather_state = GatherState.new()
	state.entities.append(e)
	state.next_entity_id = max(state.next_entity_id, id + 1)
	state.tile_grid.place(id, Rect2i(origin, footprint))


func _move_entity(state: MatchState, entity_id: int, origin: Vector2i) -> bool:
	var entity: Entity = state.get_entity_by_id(entity_id) if state != null else null
	if entity == null or state.tile_grid == null:
		push_error("test setup could not find entity #%d to move" % entity_id)
		return false
	if not state.tile_grid.move(entity_id, origin):
		push_error("test setup could not move entity #%d to %s" % [entity_id, str(origin)])
		return false
	entity.origin = origin
	return true


func _expect_generated_target_move(
	order: EntityOrder,
	state: MatchState,
	registry: EntityRegistry,
	expected_entity_id: int,
	expected_target_entity_id: int
) -> bool:
	if order == null:
		push_error("generated target move is null")
		return false
	if order.type != EntityOrder.Type.MOVE:
		push_error("generated target move should use MOVE, got %d" % order.type)
		return false
	if order.entity_id != expected_entity_id:
		push_error("generated target move entity_id should be %d" % expected_entity_id)
		return false
	if order.target_entity_id != expected_target_entity_id:
		push_error(
			(
				"generated target move should track target #%d, got #%d"
				% [expected_target_entity_id, order.target_entity_id]
			)
		)
		return false
	if not order.target_priority_chain.is_empty():
		push_error("generated target move should not carry a target chain")
		return false
	var actor: Entity = state.get_entity_by_id(expected_entity_id) if state != null else null
	var target: Entity = (
		state.get_entity_by_id(expected_target_entity_id) if state != null else null
	)
	var actor_def: EntityDef = registry.get_by_id(actor.current_def_id) if actor != null else null
	if actor == null or target == null or actor_def == null or actor_def.combat == null:
		push_error("generated target move test needs actor, target, and combat def")
		return false
	if not PathfindingSystem.can_occupy_origin(state, actor, order.target_tile, registry):
		push_error("generated target move tile %s is not occupiable" % str(order.target_tile))
		return false
	var footprint: Vector2i = PathfindingSystem.entity_footprint(state, actor, registry)
	var target_rect: Rect2i = state.tile_grid.entity_rect(expected_target_entity_id)
	var distance: int = TileGrid.distance_between_rects(
		Rect2i(order.target_tile, footprint), target_rect
	)
	if distance != actor_def.combat.attack_range:
		push_error(
			(
				"generated target move should choose farthest in-range distance %d, got %d"
				% [actor_def.combat.attack_range, distance]
			)
		)
		return false
	var path: Array[Vector2i] = PathfindingSystem.find_path(
		state, actor, order.target_tile, registry
	)
	if path.is_empty() or path[path.size() - 1] != order.target_tile:
		push_error("generated target move tile %s is not reachable" % str(order.target_tile))
		return false
	return true


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
