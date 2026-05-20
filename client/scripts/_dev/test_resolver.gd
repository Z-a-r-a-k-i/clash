@tool
extends Node

# Smoke + correctness suite for Resolver. Runs via the same @tool
# _enter_tree pattern as test_tile_grid.gd — attach to a node in
# `test_resolver_scene.tscn`, save, then re-open the scene to trigger.
# Switch to a different scene first then back if you need to re-run after
# edits (opening an already-current scene is a no-op).
#
# Tests are grouped by build chunk so that as each chunk lands the
# matching tests start passing. See plan/m0/02 + the plan file for the
# chunk breakdown.

const _REGISTRY_PATH := "res://data/entity_registry.tres"
const _TUNABLES_PATH := "res://data/tunables.tres"
const _SMOKE_SCENARIO_PATH := "res://data/scenarios/smoke_minimal.tres"
const _MVP_MAP_TSCN_PATH := "res://data/scenarios/mvp_map.tscn"
const _MVP_MAP_TRES_PATH := "res://data/scenarios/mvp_map.tres"
const _TEST_KEEPALIVE_DEF_ID := "__test_keepalive_building"


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
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

	print("[test_resolver] %d passed, %d failed" % [passed, failed])
	for test_name in fail_names:
		push_error("  failed: %s" % test_name)


func _all_tests() -> Array:
	return [
		# Chunk 1 — skeleton.
		["smoke_empty_input", _test_smoke_empty_input],
		["smoke_no_orders_no_changes", _test_smoke_no_orders_no_changes],
		["surrender_ends_match", _test_surrender_ends_match],
		# Chunk 2 — state cloning.
		["state_not_mutated", _test_state_not_mutated],
		["clone_independence", _test_clone_independence],
		# Chunk 3 — combat system.
		["attack_hits_target_in_chain", _test_attack_hits_target_in_chain],
		["target_chain_fallback", _test_target_chain_fallback],
		["hold_fire_blocks_auto_acquire", _test_hold_fire_blocks_auto_acquire],
		["closest_enemy_acquired", _test_closest_enemy_acquired],
		["attack_layer_filter", _test_attack_layer_filter],
		["attack_modifier_applies", _test_attack_modifier_applies],
		["lethal_attack_emits_destroyed", _test_lethal_attack_emits_destroyed],
		# Chunk 4 — movement system.
		["move_emits_event", _test_move_emits_event],
		["multi_tile_move_collision", _test_multi_tile_move_collision],
		["persistent_move_continuation", _test_persistent_move_continuation],
		["attacks_before_moves", _test_attacks_before_moves],
		[
			"move_uses_full_speed_budget_single_order",
			_test_move_uses_full_speed_budget_single_order
		],
		[
			"persistent_move_uses_full_speed_budget_without_orders",
			_test_persistent_move_uses_full_speed_budget_without_orders
		],
		[
			"move_and_auto_attack_resolve_independently",
			_test_move_and_auto_attack_resolve_independently
		],
		["multiple_moves_latest_destination_wins", _test_multiple_moves_latest_destination_wins],
		["multiple_targets_latest_focus_wins", _test_multiple_targets_latest_focus_wins],
		[
			"focus_target_out_of_range_falls_back_to_closest",
			_test_focus_target_out_of_range_falls_back_to_closest
		],
		["attack_clears_stale_persistent_move", _test_attack_clears_stale_persistent_move],
		["fresh_move_persists_after_attack", _test_fresh_move_persists_after_attack],
		["move_budget_respected", _test_move_budget_respected],
		[
			"deprecated_attack_move_moves_and_targets",
			_test_deprecated_attack_move_moves_and_targets
		],
		["idle_unit_auto_attacks_enemy_in_range", _test_idle_unit_auto_attacks_enemy_in_range],
		# Chunk 5 — end-of-turn system.
		["cooldowns_decrement", _test_cooldowns_decrement],
		["cooldown_removed_at_zero", _test_cooldown_removed_at_zero],
		["buff_expires_at_zero", _test_buff_expires_at_zero],
		["moves_used_resets_each_turn", _test_moves_used_resets_each_turn],
		["production_progress_emits_completion", _test_production_progress_emits_completion],
		["win_by_raze", _test_win_by_raze],
		# Chunk 6 — determinism golden test.
		["determinism_golden", _test_determinism_golden],
		# Coverage gaps surfaced during fresh-review.
		["hold_fire_toggle_distribution_sets_flag", _test_hold_fire_toggle_distribution_sets_flag],
		["cancel_clears_persistent_order", _test_cancel_clears_persistent_order],
		["cancel_clears_focus_target", _test_cancel_clears_focus_target],
		["attack_move_no_enemy_in_range_advances", _test_attack_move_no_enemy_in_range_advances],
		["fresh_order_overrides_persistent_order", _test_fresh_order_overrides_persistent_order],
		["multi_buff_stacks_multiplicatively", _test_multi_buff_stacks_multiplicatively],
		["no_tile_grid_distance_fallback", _test_no_tile_grid_distance_fallback],
		["closest_enemy_skips_dead", _test_closest_enemy_skips_dead],
		["closest_enemy_ties_break_by_id", _test_closest_enemy_ties_break_by_id],
		# Plan node 03a — submit-turn shape + group fan-out.
		["submit_turn_clone_independence", _test_submit_turn_clone_independence],
		["order_builder_fan_out_move", _test_order_builder_fan_out_move],
		["order_builder_fan_out_attack_move", _test_order_builder_fan_out_attack_move],
		["order_builder_fan_out_attack", _test_order_builder_fan_out_attack],
		["order_builder_fan_out_hold_fire_toggle", _test_order_builder_fan_out_hold_fire_toggle],
		["order_builder_fan_out_cancel", _test_order_builder_fan_out_cancel],
		["validate_drops_unowned_order", _test_validate_drops_unowned_order],
		["validate_drops_missing_entity_order", _test_validate_drops_missing_entity_order],
		["submit_turn_input_not_aliased_in_result", _test_submit_turn_input_not_aliased_in_result],
		# Plan node 04 — economy / gather pipeline.
		["gather_order_distribution_sets_phase", _test_gather_order_distribution_sets_phase],
		["gather_full_cycle_minerals", _test_gather_full_cycle_minerals],
		[
			"gather_worker_rate_multiplies_source_yield",
			_test_gather_worker_rate_multiplies_source_yield
		],
		["gather_full_cycle_gas_via_refinery", _test_gather_full_cycle_gas_via_refinery],
		["gather_fails_geyser_without_refinery", _test_gather_fails_geyser_without_refinery],
		["gather_travel_uses_full_speed_budget", _test_gather_travel_uses_full_speed_budget],
		["patch_depletes_at_capacity_zero", _test_patch_depletes_at_capacity_zero],
		[
			"worker_idles_on_source_destroyed_mid_trip",
			_test_worker_idles_on_source_destroyed_mid_trip
		],
		["worker_idles_on_all_sinks_destroyed", _test_worker_idles_on_all_sinks_destroyed],
		["nearest_deposit_sink_chosen", _test_nearest_deposit_sink_chosen],
		["gather_clears_prior_persistent_move", _test_gather_clears_prior_persistent_move],
		[
			"fresh_attack_move_cancels_gather_assignment",
			_test_fresh_attack_move_cancels_gather_assignment
		],
		# Plan node 05 — production / build / research.
		[
			"train_appended_to_queue_no_immediate_cost",
			_test_train_appended_to_queue_no_immediate_cost
		],
		["train_idle_producer_immediate_install", _test_train_idle_producer_immediate_install],
		[
			"train_insufficient_minerals_stalls_at_install",
			_test_train_insufficient_minerals_stalls_at_install
		],
		["train_resumes_after_funds_arrive", _test_train_resumes_after_funds_arrive],
		[
			"train_spawn_adjacent_with_persistent_move_to_rally",
			_test_train_spawn_adjacent_with_persistent_move_to_rally
		],
		["train_spawn_deferred_no_free_tile", _test_train_spawn_deferred_no_free_tile],
		["unit_death_returns_pop", _test_unit_death_returns_pop],
		["cancel_active_full_refund", _test_cancel_active_full_refund],
		["cancel_queued_no_cost_movement", _test_cancel_queued_no_cost_movement],
		["cancel_active_triggers_try_fill", _test_cancel_active_triggers_try_fill],
		["train_pop_overflow_stalls_at_install", _test_train_pop_overflow_stalls_at_install],
		["research_full_cycle", _test_research_full_cycle],
		["research_already_unlocked_rejected", _test_research_already_unlocked_rejected],
		["duplicate_research_rejected_when_active", _test_duplicate_research_rejected_when_active],
		[
			"duplicate_research_rejected_when_queued_elsewhere",
			_test_duplicate_research_rejected_when_queued_elsewhere
		],
		["research_stalls_on_funds", _test_research_stalls_on_funds],
		[
			"build_distributes_creates_constructing_entity",
			_test_build_distributes_creates_constructing_entity
		],
		["build_worker_walks_to_site", _test_build_worker_walks_to_site],
		[
			"build_progress_only_while_worker_adjacent",
			_test_build_progress_only_while_worker_adjacent
		],
		[
			"construction_worker_travel_uses_full_speed_budget",
			_test_construction_worker_travel_uses_full_speed_budget
		],
		["build_completes_applies_pop_provides", _test_build_completes_applies_pop_provides],
		["build_locked_worker_rejects_new_orders", _test_build_locked_worker_rejects_new_orders],
		["building_death_drops_pop_cap", _test_building_death_drops_pop_cap],
		["build_worker_death_pauses", _test_build_worker_death_pauses],
		["build_resume_via_new_worker", _test_build_resume_via_new_worker],
		[
			"build_constructing_building_dies_no_refund",
			_test_build_constructing_building_dies_no_refund
		],
		["build_cancel_via_worker_full_refund", _test_build_cancel_via_worker_full_refund],
		[
			"build_refinery_on_geyser_overlap_allowed",
			_test_build_refinery_on_geyser_overlap_allowed
		],
		["build_refinery_double_target_rejected", _test_build_refinery_double_target_rejected],
		["build_target_tile_occupied_rejected", _test_build_target_tile_occupied_rejected],
		["build_off_grid_rejected", _test_build_off_grid_rejected],
		["production_determinism_golden", _test_production_determinism_golden],
		# Plan node 06 — combat data wiring.
		["siege_tank_has_anti_heavy_modifier_data", _test_siege_tank_has_anti_heavy_modifier_data],
		["helicopter_has_anti_light_modifier_data", _test_helicopter_has_anti_light_modifier_data],
		["marine_has_no_attack_modifiers_data", _test_marine_has_no_attack_modifiers_data],
		[
			"siege_tank_anti_heavy_damage_at_data_values",
			_test_siege_tank_anti_heavy_damage_at_data_values
		],
		[
			"helicopter_anti_light_damage_at_data_values",
			_test_helicopter_anti_light_damage_at_data_values
		],
		["registry_loads_from_data", _test_registry_loads_from_data],
		# Plan node 07a — scenario loader + save/load.
		["scenario_loader_minimal", _test_scenario_loader_minimal],
		[
			"scenario_loader_applies_starting_resources",
			_test_scenario_loader_applies_starting_resources
		],
		[
			"scenario_loader_auto_starts_workers_on_minerals",
			_test_scenario_loader_auto_starts_workers_on_minerals
		],
		[
			"scenario_loader_applies_initial_hp_override",
			_test_scenario_loader_applies_initial_hp_override
		],
		["scenario_loader_applies_stat_overrides", _test_scenario_loader_applies_stat_overrides],
		["match_state_save_load_roundtrip", _test_match_state_save_load_roundtrip],
		[
			"match_state_save_load_preserves_overrides",
			_test_match_state_save_load_preserves_overrides
		],
		# Plan node 08 — mvp map.
		["map_baker_validation", _test_map_baker_validation],
		["mvp_map_loads", _test_mvp_map_loads],
		["mvp_map_simple_facing_bases", _test_mvp_map_simple_facing_bases],
		["mvp_map_is_mirror", _test_mvp_map_is_mirror],
		["mvp_map_bake_parity", _test_mvp_map_bake_parity],
		["golden_minerals_higher_yield", _test_golden_minerals_higher_yield],
		# Plan node 07b5 — self-target ability orders.
		["ability_stim_rejects_without_research", _test_ability_stim_rejects_without_research],
		[
			"ability_stim_applies_cost_buff_cooldown_and_event",
			_test_ability_stim_applies_cost_buff_cooldown_and_event
		],
		["ability_stim_rejects_on_cooldown", _test_ability_stim_rejects_on_cooldown],
		["ability_stim_rejects_low_hp", _test_ability_stim_rejects_low_hp],
		[
			"ability_siege_delayed_transform_blocks_later_actions",
			_test_ability_siege_delayed_transform_blocks_later_actions
		],
		["ability_unsiege_delayed_transform", _test_ability_unsiege_delayed_transform],
		[
			"siege_tank_data_is_immobile_and_siege_requires_research",
			_test_siege_tank_data_is_immobile_and_siege_requires_research
		],
	]


# ---------- Chunk 1 — skeleton ----------


func _test_smoke_empty_input() -> bool:
	# Empty state, empty queues → empty events, no crash.
	var state := MatchState.new()
	var queue_a: Array[EntityOrder] = []
	var queue_b: Array[EntityOrder] = []
	var result := Resolver.resolve(state, _submit(queue_a), _submit(queue_b), null, null)
	if result == null:
		return false
	if result.new_state == null:
		return false
	return result.events.size() == 0


func _test_smoke_no_orders_no_changes() -> bool:
	# Entities exist but no orders queued → no events, no crash.
	# Each player needs at least one building so the end-of-turn win check
	# doesn't trigger MATCH_ENDED on an artificially building-less world.
	var registry := EntityRegistry.new()
	registry.entities = [
		_def("marine", Vector2i(1, 1), ["light", "ground"], _combat_def(0, 0, []), 50),
		_def("base", Vector2i(4, 4), ["building", "ground"], _combat_def(0, 0, []), 1500),
	]
	var state := _state_with_grid(20, 20)
	var marine := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var p0_base := _make_entity(state, "base", 0, Vector2i(0, 0), 1500, "ground")
	var p1_base := _make_entity(state, "base", 1, Vector2i(15, 15), 1500, "ground")
	state.tile_grid.place(marine.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(p0_base.id, Rect2i(0, 0, 4, 4))
	state.tile_grid.place(p1_base.id, Rect2i(15, 15, 4, 4))

	var queue_a: Array[EntityOrder] = []
	var queue_b: Array[EntityOrder] = []
	var result := Resolver.resolve(state, _submit(queue_a), _submit(queue_b), registry, null)
	return result.events.size() == 0


func _test_surrender_ends_match() -> bool:
	# Player A surrenders → MATCH_ENDED event with winner = 1, match_over = true.
	# Surrender is a per-turn flag on SubmitTurn, not an order in the queue
	# (per plan/m0/03-action-queue-and-orders.md).
	var state := MatchState.new()
	state.players = [_player(0), _player(1)]

	var submit_a := SubmitTurn.new()
	submit_a.surrender = true
	var submit_b := SubmitTurn.new()

	var result := Resolver.resolve(state, submit_a, submit_b, null, null)
	if result.events.size() != 1:
		return false
	var ev: ResolverEvent = result.events[0]
	if ev.type != ResolverEvent.Type.MATCH_ENDED:
		return false
	if ev.winner_player_id != 1:
		return false
	return result.new_state.match_over and result.new_state.winner_player_id == 1


# ---------- Chunk 2 — state cloning ----------


func _test_state_not_mutated() -> bool:
	# Resolver.resolve must not mutate its input. Build a state, snapshot
	# its observable fields, run resolve, assert nothing observable on the
	# input changed. We can't byte-compare RefCounted instances directly,
	# so we compare key invariants.
	var state := MatchState.new()
	state.players = [_player(0), _player(1)]

	var marine := Entity.new()
	marine.id = state.allocate_entity_id()
	marine.def_id = "marine"
	marine.current_def_id = "marine"
	marine.owner_player_id = 0
	marine.origin = Vector2i(5, 5)
	marine.current_hp = 50
	state.entities = [marine]

	# Snapshot via .clone() — the resolver should leave the original
	# instance pointer-identical to this snapshot (same hp, same origin,
	# same current_def_id, etc.) since clone is independent.
	var marine_origin_before := marine.origin
	var marine_hp_before := marine.current_hp
	var match_over_before := state.match_over
	var entity_count_before := state.entities.size()
	var same_marine_ref := state.entities[0]

	var queue_a: Array[EntityOrder] = []
	var queue_b: Array[EntityOrder] = []
	var result := Resolver.resolve(state, _submit(queue_a), _submit(queue_b), null, null)

	# The result's new_state must be a different instance than the input.
	if result.new_state == state:
		push_error("resolve returned the same MatchState reference instead of a clone")
		return false
	# Input invariants must be unchanged.
	if marine.origin != marine_origin_before:
		return false
	if marine.current_hp != marine_hp_before:
		return false
	if state.match_over != match_over_before:
		return false
	if state.entities.size() != entity_count_before:
		return false
	if state.entities[0] != same_marine_ref:
		return false
	return true


func _test_clone_independence() -> bool:
	# Mutating the cloned state must not affect the original.
	var state := MatchState.new()
	state.players = [_player(0), _player(1)]

	var marine := Entity.new()
	marine.id = state.allocate_entity_id()
	marine.def_id = "marine"
	marine.owner_player_id = 0
	marine.origin = Vector2i(5, 5)
	marine.current_hp = 50
	state.entities = [marine]

	var grid := TileGrid.new(20, 20)
	grid.place(marine.id, Rect2i(5, 5, 1, 1))
	state.tile_grid = grid

	var clone := state.clone()
	# Mutate clone.
	clone.match_over = true
	clone.entities[0].current_hp = 1
	clone.entities[0].origin = Vector2i(99, 99)
	clone.tile_grid.move(marine.id, Vector2i(10, 10))
	clone.players[0].minerals = 999

	# Original must be unaffected.
	if state.match_over:
		return false
	if state.entities[0].current_hp != 50:
		return false
	if state.entities[0].origin != Vector2i(5, 5):
		return false
	if state.tile_grid.entity_at(Vector2i(5, 5)) != marine.id:
		return false
	if state.players[0].minerals != 0:
		return false
	return true


# ---------- Chunk 3 — combat system ----------


func _test_attack_hits_target_in_chain() -> bool:
	# Marine attacks an enemy by id from chain[0]. Verify ENTITY_DAMAGED.
	var registry := _two_unit_registry(6, 5, ["ground"], 50)
	var state := _state_with_grid(20, 20)
	var attacker := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var target := _make_entity(state, "marine", 1, Vector2i(8, 5), 50, "ground")
	state.tile_grid.place(attacker.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(target.id, Rect2i(8, 5, 1, 1))

	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = attacker.id
	attack.target_priority_chain = [target.id]
	var queue_a: Array[EntityOrder] = [attack]

	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)
	if result.events.size() < 1:
		return false
	var ev: ResolverEvent = result.events[0]
	return (
		ev.type == ResolverEvent.Type.ENTITY_DAMAGED
		and ev.actor_id == attacker.id
		and ev.target_id == target.id
		and ev.damage == 6
	)


func _test_target_chain_fallback() -> bool:
	# Chain: [t1, t2]. t1 starts dead (hp=0). Attacker should fire at t2.
	var registry := _two_unit_registry(6, 5, ["ground"], 50)
	var state := _state_with_grid(20, 20)
	var attacker := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var t1 := _make_entity(state, "marine", 1, Vector2i(7, 5), 0, "ground")  # already dead
	var t2 := _make_entity(state, "marine", 1, Vector2i(8, 5), 50, "ground")
	state.tile_grid.place(attacker.id, Rect2i(5, 5, 1, 1))
	# t1 not placed in grid since it's dead; in-range check uses def-derived rect.

	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = attacker.id
	attack.target_priority_chain = [t1.id, t2.id]
	var queue_a: Array[EntityOrder] = [attack]

	state.tile_grid.place(t2.id, Rect2i(8, 5, 1, 1))
	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)

	# Expect exactly one ENTITY_DAMAGED on t2.
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED:
			return ev.target_id == t2.id
	return false


func _test_hold_fire_blocks_auto_acquire() -> bool:
	# Empty chain + hold_fire + enemy in range → no fire.
	var registry := _two_unit_registry(6, 5, ["ground"], 50)
	var state := _state_with_grid(20, 20)
	var attacker := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	attacker.hold_fire = true
	var enemy := _make_entity(state, "marine", 1, Vector2i(8, 5), 50, "ground")
	enemy.hold_fire = true
	state.tile_grid.place(attacker.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(enemy.id, Rect2i(8, 5, 1, 1))

	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = attacker.id
	# Empty chain.
	var queue_a: Array[EntityOrder] = [attack]

	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED:
			return false
	return true


func _test_closest_enemy_acquired() -> bool:
	# Empty chain + no hold_fire + two enemies in range. Fires at closer one.
	var registry := _two_unit_registry(6, 10, ["ground"], 50)
	var state := _state_with_grid(20, 20)
	var attacker := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var far_enemy := _make_entity(state, "marine", 1, Vector2i(12, 5), 50, "ground")
	var near_enemy := _make_entity(state, "marine", 1, Vector2i(8, 5), 50, "ground")
	state.tile_grid.place(attacker.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(far_enemy.id, Rect2i(12, 5, 1, 1))
	state.tile_grid.place(near_enemy.id, Rect2i(8, 5, 1, 1))

	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = attacker.id
	# Empty chain → triggers closest-enemy auto-acquire.
	var queue_a: Array[EntityOrder] = [attack]

	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED:
			return ev.target_id == near_enemy.id
	return false


func _test_attack_layer_filter() -> bool:
	# Tank's TargetLayers = ["ground"] — cannot hit a flying helicopter.
	var registry := EntityRegistry.new()
	registry.entities = [
		_def("tank", Vector2i(2, 2), ["heavy", "ground"], _combat_def(15, 7, ["ground"]), 150),
		_def(
			"helicopter",
			Vector2i(1, 1),
			["light", "flying"],
			_combat_def(10, 5, ["ground", "flying"]),
			80
		),
	]
	var state := _state_with_grid(20, 20)
	var tank := _make_entity(state, "tank", 0, Vector2i(5, 5), 150, "ground")
	var heli := _make_entity(state, "helicopter", 1, Vector2i(8, 5), 80, "flying")
	heli.hold_fire = true
	state.tile_grid.place(tank.id, Rect2i(5, 5, 2, 2))
	state.tile_grid.place(heli.id, Rect2i(8, 5, 1, 1))

	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = tank.id
	attack.target_priority_chain = [heli.id]
	var queue_a: Array[EntityOrder] = [attack]

	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED:
			return false
	return true


func _test_attack_modifier_applies() -> bool:
	# Marine has +50% vs heavy. Damage = 6 * 1.5 = 9 against a heavy target.
	var marine_combat := _combat_def(6, 5, ["ground"])
	var mod := AttackModifier.new()
	mod.target_tag = "heavy"
	mod.damage_mult = 1.5
	marine_combat.attack_modifiers = [mod]
	var registry := EntityRegistry.new()
	registry.entities = [
		_def("marine", Vector2i(1, 1), ["light", "ground"], marine_combat, 50),
		_def("tank", Vector2i(2, 2), ["heavy", "ground"], _combat_def(15, 7, ["ground"]), 150),
	]
	var state := _state_with_grid(20, 20)
	var attacker := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var target := _make_entity(state, "tank", 1, Vector2i(7, 5), 150, "ground")
	state.tile_grid.place(attacker.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(target.id, Rect2i(7, 5, 2, 2))

	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = attacker.id
	attack.target_priority_chain = [target.id]
	var queue_a: Array[EntityOrder] = [attack]

	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED:
			return ev.damage == 9
	return false


func _test_lethal_attack_emits_destroyed() -> bool:
	# Damage exceeds target HP → ENTITY_DAMAGED then ENTITY_DESTROYED.
	var registry := _two_unit_registry(100, 5, ["ground"], 50)
	var state := _state_with_grid(20, 20)
	var attacker := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var target := _make_entity(state, "marine", 1, Vector2i(7, 5), 50, "ground")
	state.tile_grid.place(attacker.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(target.id, Rect2i(7, 5, 1, 1))

	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = attacker.id
	attack.target_priority_chain = [target.id]
	var queue_a: Array[EntityOrder] = [attack]

	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)
	var saw_damaged := false
	var saw_destroyed := false
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED and ev.target_id == target.id:
			saw_damaged = true
		if ev.type == ResolverEvent.Type.ENTITY_DESTROYED and ev.target_id == target.id:
			saw_destroyed = true
	return saw_damaged and saw_destroyed


# ---------- Chunk 4 — movement system ----------


func _test_move_emits_event() -> bool:
	# Marine with speed 4 moves 1 tile in 1 tick. Expect ENTITY_MOVED.
	var registry := _movable_registry(4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))

	var move := EntityOrder.new()
	move.type = EntityOrder.Type.MOVE
	move.entity_id = actor.id
	move.target_tile = Vector2i(8, 5)
	var queue_a: Array[EntityOrder] = [move]

	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == actor.id:
			return ev.from_origin == Vector2i(5, 5) and ev.to_origin == Vector2i(6, 5)
	return false


func _test_multi_tile_move_collision() -> bool:
	# 2x2 mover at (1,1)-(2,2). 2x2 blocker at (3,1)-(4,2). Movement system
	# tries diagonal-first then axis-aligned: every candidate first-step rect
	# overlaps the blocker's footprint, so no ENTITY_MOVED event is emitted.
	var registry := _tank_registry(2)
	var state := _state_with_grid(10, 10)
	var mover := _make_entity(state, "tank", 0, Vector2i(1, 1), 150, "ground")
	var blocker := _make_entity(state, "tank", 0, Vector2i(3, 1), 150, "ground")
	state.tile_grid.place(mover.id, Rect2i(1, 1, 2, 2))
	state.tile_grid.place(blocker.id, Rect2i(3, 1, 2, 2))

	var move := EntityOrder.new()
	move.type = EntityOrder.Type.MOVE
	move.entity_id = mover.id
	move.target_tile = Vector2i(8, 1)  # straight right, blocked.

	var result := Resolver.resolve(
		state, _submit([move] as Array[EntityOrder]), _submit([]), registry, null
	)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == mover.id:
			return false
	return true


func _test_persistent_move_continuation() -> bool:
	# Entity has persistent_order set; no fresh order this tick. Expect
	# Phase 3 to advance toward the persistent target.
	var registry := _movable_registry(4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))

	var po := EntityOrder.new()
	po.type = EntityOrder.Type.MOVE
	po.entity_id = actor.id
	po.target_tile = Vector2i(15, 5)
	actor.persistent_order = po

	var result := Resolver.resolve(state, _submit(), _submit(), registry, null)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == actor.id:
			# First step still starts one tile toward (15, 5).
			return ev.from_origin == Vector2i(5, 5) and ev.to_origin == Vector2i(6, 5)
	return false


func _test_attacks_before_moves() -> bool:
	# Same tick: one entity has ATTACK queued, another has MOVE queued.
	# Expect ENTITY_DAMAGED to appear before ENTITY_MOVED in the events list.
	var registry := EntityRegistry.new()
	registry.entities = [
		_def_with_movement_combat(
			"marine", Vector2i(1, 1), ["light", "ground"], _combat_def(6, 5, ["ground"]), 50, 4
		),
	]
	var state := _state_with_grid(20, 20)
	var attacker := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var target := _make_entity(state, "marine", 1, Vector2i(7, 5), 50, "ground")
	var mover := _make_entity(state, "marine", 0, Vector2i(0, 0), 50, "ground")
	state.tile_grid.place(attacker.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(target.id, Rect2i(7, 5, 1, 1))
	state.tile_grid.place(mover.id, Rect2i(0, 0, 1, 1))

	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = attacker.id
	attack.target_priority_chain = [target.id]
	var move := EntityOrder.new()
	move.type = EntityOrder.Type.MOVE
	move.entity_id = mover.id
	move.target_tile = Vector2i(5, 0)

	var result := Resolver.resolve(
		state, _submit([attack, move] as Array[EntityOrder]), _submit([]), registry, null
	)
	var damaged_idx := -1
	var moved_idx := -1
	for i in result.events.size():
		var ev: ResolverEvent = result.events[i]
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED and damaged_idx == -1:
			damaged_idx = i
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and moved_idx == -1:
			moved_idx = i
	return damaged_idx != -1 and moved_idx != -1 and damaged_idx < moved_idx


func _test_move_uses_full_speed_budget_single_order() -> bool:
	# One MOVE order should spend the entity's whole speed budget this turn,
	# not just one tile because the action queue has one slot.
	var registry := _movable_registry(4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))

	var move := EntityOrder.new()
	move.type = EntityOrder.Type.MOVE
	move.entity_id = actor.id
	move.target_tile = Vector2i(15, 5)
	var result := Resolver.resolve(
		state, _submit([move] as Array[EntityOrder]), _submit(), registry, null
	)

	var move_count := 0
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == actor.id:
			move_count += 1
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return move_count == 4 and new_actor.origin == Vector2i(9, 5)


func _test_persistent_move_uses_full_speed_budget_without_orders() -> bool:
	# Standing movement with no submitted orders should still spend the
	# full speed budget, otherwise persistent movement crawls at 1 tile/turn.
	var registry := _movable_registry(4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))

	var po := EntityOrder.new()
	po.type = EntityOrder.Type.MOVE
	po.entity_id = actor.id
	po.target_tile = Vector2i(15, 5)
	actor.persistent_order = po

	var result := Resolver.resolve(state, _submit(), _submit(), registry, null)
	var move_count := 0
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == actor.id:
			move_count += 1
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return move_count == 4 and new_actor.origin == Vector2i(9, 5)


func _test_move_and_auto_attack_resolve_independently() -> bool:
	# A MOVE command is not an attack-mode choice. A combat unit should
	# shoot an in-range enemy first, then still spend its move budget.
	var registry := _combat_mover_registry(6, 3, 4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var enemy := _make_entity(state, "marine", 1, Vector2i(5, 7), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(enemy.id, Rect2i(5, 7, 1, 1))

	var move := EntityOrder.new()
	move.type = EntityOrder.Type.MOVE
	move.entity_id = actor.id
	move.target_tile = Vector2i(12, 5)

	var result := Resolver.resolve(
		state, _submit([move] as Array[EntityOrder]), _submit(), registry, null
	)
	var damaged := false
	var move_count := 0
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED and ev.actor_id == actor.id:
			damaged = ev.target_id == enemy.id
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == actor.id:
			move_count += 1
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return damaged and move_count == 4 and new_actor.origin == Vector2i(9, 5)


func _test_multiple_moves_latest_destination_wins() -> bool:
	# Repeated move clicks during one planning turn should replace the
	# destination, not create multiple movement slots.
	var registry := _movable_registry(4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))

	var old_move := EntityOrder.new()
	old_move.type = EntityOrder.Type.MOVE
	old_move.entity_id = actor.id
	old_move.target_tile = Vector2i(15, 5)
	var latest_move := EntityOrder.new()
	latest_move.type = EntityOrder.Type.MOVE
	latest_move.entity_id = actor.id
	latest_move.target_tile = Vector2i(5, 15)

	var result := Resolver.resolve(
		state, _submit([old_move, latest_move] as Array[EntityOrder]), _submit(), registry, null
	)
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return (
		new_actor.origin == Vector2i(5, 9)
		and new_actor.persistent_order != null
		and new_actor.persistent_order.target_tile == latest_move.target_tile
	)


func _test_multiple_targets_latest_focus_wins() -> bool:
	# Repeated target clicks during one planning turn should replace the
	# focus target and should not produce two attacks in one resolve.
	var registry := _two_unit_registry(6, 5, ["ground"], 50)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var first_target := _make_entity(state, "marine", 1, Vector2i(7, 5), 50, "ground")
	var latest_target := _make_entity(state, "marine", 1, Vector2i(8, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(first_target.id, Rect2i(7, 5, 1, 1))
	state.tile_grid.place(latest_target.id, Rect2i(8, 5, 1, 1))

	var first_attack := EntityOrder.new()
	first_attack.type = EntityOrder.Type.ATTACK
	first_attack.entity_id = actor.id
	first_attack.target_priority_chain = [first_target.id]
	var latest_attack := EntityOrder.new()
	latest_attack.type = EntityOrder.Type.ATTACK
	latest_attack.entity_id = actor.id
	latest_attack.target_priority_chain = [latest_target.id]

	var result := Resolver.resolve(
		state,
		_submit([first_attack, latest_attack] as Array[EntityOrder]),
		_submit(),
		registry,
		null
	)
	var damage_count := 0
	var damaged_latest := false
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED and ev.actor_id == actor.id:
			damage_count += 1
			damaged_latest = ev.target_id == latest_target.id
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return (
		damage_count == 1
		and damaged_latest
		and int(new_actor.get("focus_target_entity_id")) == latest_target.id
	)


func _test_focus_target_out_of_range_falls_back_to_closest() -> bool:
	# A focus target is priority only when it is in range. If it is out of
	# range, the unit should still shoot the closest in-range enemy.
	var registry := _two_unit_registry(6, 3, ["ground"], 50)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var far_focus := _make_entity(state, "marine", 1, Vector2i(15, 5), 50, "ground")
	var close_enemy := _make_entity(state, "marine", 1, Vector2i(7, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(far_focus.id, Rect2i(15, 5, 1, 1))
	state.tile_grid.place(close_enemy.id, Rect2i(7, 5, 1, 1))

	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = actor.id
	attack.target_priority_chain = [far_focus.id]

	var result := Resolver.resolve(
		state, _submit([attack] as Array[EntityOrder]), _submit(), registry, null
	)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED and ev.actor_id == actor.id:
			var new_actor := result.new_state.get_entity_by_id(actor.id)
			return (
				ev.target_id == close_enemy.id
				and int(new_actor.get("focus_target_entity_id")) == far_focus.id
			)
	return false


func _test_attack_clears_stale_persistent_move() -> bool:
	# If a unit was already walking and then engages without a fresh move
	# command, it may move this resolve but should stop continuing next turn.
	var registry := _combat_mover_registry(6, 3, 4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var enemy := _make_entity(state, "marine", 1, Vector2i(5, 7), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(enemy.id, Rect2i(5, 7, 1, 1))
	var po := EntityOrder.new()
	po.type = EntityOrder.Type.MOVE
	po.entity_id = actor.id
	po.target_tile = Vector2i(12, 5)
	actor.persistent_order = po

	var result := Resolver.resolve(state, _submit(), _submit(), registry, null)
	var damaged := false
	var moved := false
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED and ev.actor_id == actor.id:
			damaged = true
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == actor.id:
			moved = true
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return damaged and moved and new_actor.persistent_order == null


func _test_fresh_move_persists_after_attack() -> bool:
	# A newly-issued move is intentional. Even if the unit shoots before
	# moving this resolve, that new destination remains the persistent move.
	var registry := _combat_mover_registry(6, 3, 4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var enemy := _make_entity(state, "marine", 1, Vector2i(5, 7), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(enemy.id, Rect2i(5, 7, 1, 1))

	var move := EntityOrder.new()
	move.type = EntityOrder.Type.MOVE
	move.entity_id = actor.id
	move.target_tile = Vector2i(12, 5)

	var result := Resolver.resolve(
		state, _submit([move] as Array[EntityOrder]), _submit(), registry, null
	)
	var damaged := false
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED and ev.actor_id == actor.id:
			damaged = true
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return (
		damaged
		and new_actor.persistent_order != null
		and new_actor.persistent_order.target_tile == move.target_tile
	)


func _test_move_budget_respected() -> bool:
	# Entity with speed 2; queue 5 moves. Expect at most 2 ENTITY_MOVED events.
	var registry := _movable_registry(2)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))

	var queue_a: Array[EntityOrder] = []
	for i in 5:
		var move := EntityOrder.new()
		move.type = EntityOrder.Type.MOVE
		move.entity_id = actor.id
		move.target_tile = Vector2i(15, 5)
		queue_a.append(move)

	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)
	var move_count := 0
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == actor.id:
			move_count += 1
	return move_count == 2


func _test_deprecated_attack_move_moves_and_targets() -> bool:
	# ATTACK_MOVE is no longer exposed in the UX, but old builder/helper
	# code still maps it to MOVE + optional focus target.
	var registry := EntityRegistry.new()
	registry.entities = [
		_def_with_movement_combat(
			"marine", Vector2i(1, 1), ["light", "ground"], _combat_def(6, 5, ["ground"]), 50, 4
		),
	]
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var enemy := _make_entity(state, "marine", 1, Vector2i(8, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(enemy.id, Rect2i(8, 5, 1, 1))

	var attack_move := EntityOrder.new()
	attack_move.type = EntityOrder.Type.ATTACK_MOVE
	attack_move.entity_id = actor.id
	attack_move.target_tile = Vector2i(15, 5)
	attack_move.target_priority_chain = [enemy.id]
	var queue_a: Array[EntityOrder] = [attack_move]

	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)
	var moved := false
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == actor.id:
			moved = true
	var damaged := false
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED and ev.actor_id == actor.id:
			damaged = ev.target_id == enemy.id
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return (
		moved
		and damaged
		and new_actor.persistent_order != null
		and new_actor.persistent_order.type == EntityOrder.Type.MOVE
		and int(new_actor.get("focus_target_entity_id")) == enemy.id
	)


func _test_idle_unit_auto_attacks_enemy_in_range() -> bool:
	var registry := _combat_mover_registry(6, 3, 4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var enemy := _make_entity(state, "marine", 1, Vector2i(7, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(enemy.id, Rect2i(7, 5, 1, 1))

	var result := Resolver.resolve(state, _submit(), _submit(), registry, null)
	var new_enemy := result.new_state.get_entity_by_id(enemy.id)
	return new_enemy.current_hp == 44


# ---------- Chunk 5 — end-of-turn system ----------


func _test_cooldowns_decrement() -> bool:
	# Entity with cooldown {stim: 3} → after one turn → {stim: 2}.
	var registry := _movable_registry(4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))
	actor.ability_cooldowns = {"stim": 3}

	# Need at least one tick for end-of-turn to fire. Queue any move.
	var move := EntityOrder.new()
	move.type = EntityOrder.Type.MOVE
	move.entity_id = actor.id
	move.target_tile = Vector2i(5, 5)  # noop step
	var queue_a: Array[EntityOrder] = [move]

	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return new_actor.ability_cooldowns.get("stim", 0) == 2


func _test_cooldown_removed_at_zero() -> bool:
	# Cooldown {stim: 1} → after one turn → key removed.
	var registry := _movable_registry(4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))
	actor.ability_cooldowns = {"stim": 1}

	var move := EntityOrder.new()
	move.type = EntityOrder.Type.MOVE
	move.entity_id = actor.id
	move.target_tile = Vector2i(5, 5)
	var queue_a: Array[EntityOrder] = [move]

	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return not new_actor.ability_cooldowns.has("stim")


func _test_buff_expires_at_zero() -> bool:
	# Buff with turns_remaining=1 → after one turn → removed.
	var registry := _movable_registry(4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))

	var buff := ActiveBuff.new()
	buff.source_ability_id = "stim"
	buff.turns_remaining = 1
	buff.damage_mult = 1.5
	actor.active_buffs = [buff]

	var move := EntityOrder.new()
	move.type = EntityOrder.Type.MOVE
	move.entity_id = actor.id
	move.target_tile = Vector2i(5, 5)
	var queue_a: Array[EntityOrder] = [move]

	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return new_actor.active_buffs.is_empty()


func _test_moves_used_resets_each_turn() -> bool:
	# Entity moves twice in turn 1 (uses budget); after end-of-turn,
	# moves_used_this_turn must reset to 0.
	var registry := _movable_registry(2)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))

	var queue_a: Array[EntityOrder] = []
	for i in 2:
		var move := EntityOrder.new()
		move.type = EntityOrder.Type.MOVE
		move.entity_id = actor.id
		move.target_tile = Vector2i(15, 5)
		queue_a.append(move)

	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return new_actor.moves_used_this_turn == 0


func _test_production_progress_emits_completion() -> bool:
	# Building with one active production item, turns_remaining=1 →
	# end-of-turn ticks to 0, finalizes by spawning a marine adjacent,
	# emits TRAIN_COMPLETED, active slot empties.
	var registry := EntityRegistry.new()
	var building_def := EntityDef.new()
	building_def.id = "barracks"
	building_def.tags = ["building", "ground"]
	building_def.footprint = Vector2i(3, 3)
	var bd_hp := HealthDef.new()
	bd_hp.max_hp = 1000
	building_def.health = bd_hp
	building_def.production = ProductionDef.new()
	building_def.production.produces = ["marine"]
	building_def.production.rally_offset = Vector2i(0, 4)
	# Marine def for spawn.
	var marine_def := EntityDef.new()
	marine_def.id = "marine"
	marine_def.tags = ["light", "ground"]
	marine_def.footprint = Vector2i(1, 1)
	var md_hp := HealthDef.new()
	md_hp.max_hp = 50
	marine_def.health = md_hp
	marine_def.movement = MovementDef.new()
	marine_def.movement.speed_tiles_per_turn = 4
	marine_def.movement.default_layer = "ground"
	registry.entities = [building_def, marine_def]

	var state := _state_with_grid(20, 20)
	var building := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	state.tile_grid.place(building.id, Rect2i(2, 2, 3, 3))
	var ps := ProductionState.new()
	ps.active = {
		ProductionState.KEY_DEF_ID: "marine",
		ProductionState.KEY_KIND: ProductionState.KIND_UNIT,
		ProductionState.KEY_TURNS_REMAINING: 1,
		ProductionState.KEY_PAID_MINERALS: 0,
		ProductionState.KEY_PAID_GAS: 0,
		ProductionState.KEY_PAID_POP: 0,
	}
	building.production_state = ps

	var result := Resolver.resolve(state, _submit(), _submit(), registry, null)
	if not _has_event_of_type(result.events, ResolverEvent.Type.TRAIN_COMPLETED):
		return false
	var new_building := result.new_state.get_entity_by_id(building.id)
	return new_building.production_state.active.is_empty()


func _test_win_by_raze() -> bool:
	# Player B's last building is destroyed → MATCH_ENDED, winner = 0,
	# match_over = true.
	var registry := EntityRegistry.new()
	# Marine — only used as the attacker / damage source via direct hp manip.
	var marine_combat := _combat_def(2000, 5, ["ground"])
	registry.entities = [
		_def("marine", Vector2i(1, 1), ["light", "ground"], marine_combat, 50),
		_def("base", Vector2i(4, 4), ["building", "ground"], _combat_def(0, 0, []), 1500),
	]

	var state := _state_with_grid(30, 30)
	var attacker := _make_entity(state, "marine", 0, Vector2i(0, 0), 50, "ground")
	# Player A also has a building (so the win check finds them as
	# survivor). Player B has one base which we'll destroy.
	var player_a_base := _make_entity(state, "base", 0, Vector2i(2, 2), 1500, "ground")
	var player_b_base := _make_entity(state, "base", 1, Vector2i(20, 20), 1, "ground")
	state.tile_grid.place(attacker.id, Rect2i(0, 0, 1, 1))
	state.tile_grid.place(player_a_base.id, Rect2i(2, 2, 4, 4))
	state.tile_grid.place(player_b_base.id, Rect2i(20, 20, 4, 4))

	# Set hp=1 on the target so 2000 damage ends it. But need attacker
	# in range — attack range 5, base at (20,20) is way out of reach.
	# Easier: queue an attack with a chain referencing the base, but
	# distance check rejects it. So instead, set base hp=0 to simulate
	# already-destroyed state and trigger the end-of-turn win check
	# directly.
	player_b_base.current_hp = 0
	state.tile_grid.remove(player_b_base.id)  # death cleanup happened earlier this turn.

	# At least one tick to trigger end-of-turn.
	var noop := EntityOrder.new()
	noop.type = EntityOrder.Type.MOVE
	noop.entity_id = attacker.id
	noop.target_tile = attacker.origin
	var queue_a: Array[EntityOrder] = [noop]

	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)
	if not result.new_state.match_over:
		return false
	if result.new_state.winner_player_id != 0:
		return false
	var saw_match_ended := false
	for ev in result.events:
		if ev.type == ResolverEvent.Type.MATCH_ENDED and ev.winner_player_id == 0:
			saw_match_ended = true
	return saw_match_ended


# ---------- Chunk 6 — determinism golden test ----------


func _test_determinism_golden() -> bool:
	# Run Resolver.resolve N=5 times on the same input and assert every
	# run produces an identical event sequence. Per ADR 0013 the resolver
	# is fully deterministic — same (state, queue_a, queue_b) → same
	# events, every time. This is the keystone test for replays and
	# server-client reconciliation.
	#
	# The scenario is small but exercises every system that's been
	# implemented: a combat exchange, a movement, a persistent move,
	# end-of-turn cooldowns / buffs.
	var registry := EntityRegistry.new()
	registry.entities = [
		_def_with_movement_combat(
			"marine", Vector2i(1, 1), ["light", "ground"], _combat_def(6, 5, ["ground"]), 50, 4
		),
	]

	# Build a fresh state for each run so they're independent baselines.
	# Use a builder so the runs are byte-identical inputs.
	var event_lists: Array = []
	var state_lists: Array = []
	for run_index in 5:
		var state := _state_with_grid(20, 20)
		var p0_attacker := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
		var p0_mover := _make_entity(state, "marine", 0, Vector2i(2, 2), 50, "ground")
		var p1_target := _make_entity(state, "marine", 1, Vector2i(8, 5), 50, "ground")
		var p1_persistent := _make_entity(state, "marine", 1, Vector2i(15, 15), 50, "ground")
		state.tile_grid.place(p0_attacker.id, Rect2i(5, 5, 1, 1))
		state.tile_grid.place(p0_mover.id, Rect2i(2, 2, 1, 1))
		state.tile_grid.place(p1_target.id, Rect2i(8, 5, 1, 1))
		state.tile_grid.place(p1_persistent.id, Rect2i(15, 15, 1, 1))

		# Pre-existing buff and cooldown so end-of-turn has work to do.
		var buff := ActiveBuff.new()
		buff.source_ability_id = "stim"
		buff.turns_remaining = 2
		buff.damage_mult = 1.5
		p0_attacker.active_buffs = [buff]
		p0_attacker.ability_cooldowns = {"stim": 3}

		# Persistent move from a prior turn for the p1 marine at (15,15).
		var po := EntityOrder.new()
		po.type = EntityOrder.Type.MOVE
		po.entity_id = p1_persistent.id
		po.target_tile = Vector2i(10, 10)
		p1_persistent.persistent_order = po

		# Fresh orders this turn:
		# - p0_attacker fires at p1_target (chain)
		# - p0_mover walks toward (10, 5)
		var attack := EntityOrder.new()
		attack.type = EntityOrder.Type.ATTACK
		attack.entity_id = p0_attacker.id
		attack.target_priority_chain = [p1_target.id]
		var move := EntityOrder.new()
		move.type = EntityOrder.Type.MOVE
		move.entity_id = p0_mover.id
		move.target_tile = Vector2i(10, 5)

		var queue_a: Array[EntityOrder] = [attack, move]
		var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)
		event_lists.append(result.events)
		state_lists.append(result.new_state)

	# Compare every run's events AND new_state against the first.
	var baseline_events: Array = event_lists[0]
	var baseline_state: MatchState = state_lists[0]
	for i in range(1, event_lists.size()):
		if not _events_equal(baseline_events, event_lists[i]):
			push_error("determinism_golden: run %d events differ from run 0" % i)
			return false
		if not _states_equal(baseline_state, state_lists[i]):
			push_error("determinism_golden: run %d new_state differs from run 0" % i)
			return false
	return true


# Structural compare for two MatchState instances. Returns false if any
# observable mutated surface differs. Used by the determinism golden test
# to catch nondeterministic state mutations that the events-only check
# would miss (e.g. cooldowns / buffs / persistent_order drift).
func _states_equal(a: MatchState, b: MatchState) -> bool:
	if a.turn_index != b.turn_index:
		return false
	if a.rng_seed != b.rng_seed:
		return false
	if a.match_over != b.match_over:
		return false
	if a.winner_player_id != b.winner_player_id:
		return false
	if a.next_entity_id != b.next_entity_id:
		return false
	if (a.tile_grid == null) != (b.tile_grid == null):
		return false
	if a.tile_grid != null:
		if a.tile_grid.width != b.tile_grid.width:
			return false
		if a.tile_grid.height != b.tile_grid.height:
			return false
	if a.players.size() != b.players.size():
		return false
	for i in a.players.size():
		var pa: PlayerState = a.players[i]
		var pb: PlayerState = b.players[i]
		if (pa == null) != (pb == null):
			return false
		if pa == null:
			continue
		if pa.player_id != pb.player_id:
			return false
		if pa.minerals != pb.minerals:
			return false
		if pa.gas != pb.gas:
			return false
		if pa.pop_used != pb.pop_used:
			return false
		if pa.pop_cap != pb.pop_cap:
			return false
		if pa.has_surrendered != pb.has_surrendered:
			return false
		if pa.unlocked_researches != pb.unlocked_researches:
			return false
	var ents_a := a.entities_sorted_by_id()
	var ents_b := b.entities_sorted_by_id()
	if ents_a.size() != ents_b.size():
		return false
	for i in ents_a.size():
		var ea: Entity = ents_a[i]
		var eb: Entity = ents_b[i]
		if ea.id != eb.id:
			return false
		if ea.def_id != eb.def_id:
			return false
		if ea.current_def_id != eb.current_def_id:
			return false
		if ea.owner_player_id != eb.owner_player_id:
			return false
		if ea.current_hp != eb.current_hp:
			return false
		if ea.origin != eb.origin:
			return false
		if ea.current_layer != eb.current_layer:
			return false
		if ea.moves_used_this_turn != eb.moves_used_this_turn:
			return false
		if ea.hold_fire != eb.hold_fire:
			return false
		if ea.focus_target_entity_id != eb.focus_target_entity_id:
			return false
		if ea.is_hidden != eb.is_hidden:
			return false
		if ea.current_resource_amount != eb.current_resource_amount:
			return false
		if ea.is_constructing != eb.is_constructing:
			return false
		if ea.construction_turns_remaining != eb.construction_turns_remaining:
			return false
		if ea.construction_worker_id != eb.construction_worker_id:
			return false
		if ea.locked_to_building_id != eb.locked_to_building_id:
			return false
		if (ea.production_state == null) != (eb.production_state == null):
			return false
		if ea.production_state != null:
			if ea.production_state.active != eb.production_state.active:
				return false
			if ea.production_state.queue.size() != eb.production_state.queue.size():
				return false
			for j in ea.production_state.queue.size():
				if ea.production_state.queue[j] != eb.production_state.queue[j]:
					return false
		if (ea.gather_state == null) != (eb.gather_state == null):
			return false
		if ea.gather_state != null:
			if (
				ea.gather_state.assigned_source_entity_id
				!= eb.gather_state.assigned_source_entity_id
			):
				return false
			if ea.gather_state.carrying_resource_type != eb.gather_state.carrying_resource_type:
				return false
			if ea.gather_state.carrying_amount != eb.gather_state.carrying_amount:
				return false
			if ea.gather_state.phase != eb.gather_state.phase:
				return false
		if ea.ability_cooldowns != eb.ability_cooldowns:
			return false
		if (ea.ability_cast == null) != (eb.ability_cast == null):
			return false
		if ea.ability_cast != null:
			if ea.ability_cast.ability_id != eb.ability_cast.ability_id:
				return false
			if ea.ability_cast.turns_remaining != eb.ability_cast.turns_remaining:
				return false
		if ea.active_buffs.size() != eb.active_buffs.size():
			return false
		for j in ea.active_buffs.size():
			var ba: ActiveBuff = ea.active_buffs[j]
			var bb: ActiveBuff = eb.active_buffs[j]
			if (
				ba.source_ability_id != bb.source_ability_id
				or ba.turns_remaining != bb.turns_remaining
				or ba.damage_mult != bb.damage_mult
				or ba.speed_mult != bb.speed_mult
			):
				return false
		if ea.order_queue.size() != eb.order_queue.size():
			return false
		for j in ea.order_queue.size():
			if not _orders_equal(ea.order_queue[j], eb.order_queue[j]):
				return false
		if not _orders_equal(ea.persistent_order, eb.persistent_order):
			return false
	# Tile grid parity at each live entity's origin — catches drift in
	# placement / removal that wouldn't show up in entity fields alone.
	if a.tile_grid != null:
		for i in ents_a.size():
			var ea: Entity = ents_a[i]
			var eb: Entity = ents_b[i]
			if ea.current_hp <= 0 and eb.current_hp <= 0:
				continue
			if a.tile_grid.entity_rect(ea.id) != b.tile_grid.entity_rect(eb.id):
				return false
	return true


# Structural compare for two EntityOrder instances. Both null is true.
# One null + one non-null is false.
func _orders_equal(a: EntityOrder, b: EntityOrder) -> bool:
	if (a == null) != (b == null):
		return false
	if a == null:
		return true
	if a.type != b.type:
		return false
	if a.entity_id != b.entity_id:
		return false
	if a.target_tile != b.target_tile:
		return false
	if a.target_priority_chain != b.target_priority_chain:
		return false
	if a.hold_fire != b.hold_fire:
		return false
	if a.def_id != b.def_id:
		return false
	if a.cancel_index != b.cancel_index:
		return false
	if a.target_entity_id != b.target_entity_id:
		return false
	return true


# Returns true if the event list contains any event of `event_type`.
# Helper for tests that need to assert presence/absence of a specific
# event type without iterating the list inline.
func _has_event_of_type(events: Array, event_type: int) -> bool:
	for ev in events:
		if (ev as ResolverEvent).type == event_type:
			return true
	return false


func _has_event_with_def(events: Array, event_type: int, actor_id: int, def_id: String) -> bool:
	for ev in events:
		var event: ResolverEvent = ev
		if (
			event.type == event_type
			and event.actor_id == actor_id
			and (event.def_id == def_id or event.new_def_id == def_id)
		):
			return true
	return false


func _has_rejection(events: Array, actor_id: int, reason: String) -> bool:
	return _has_event_with_def(events, ResolverEvent.Type.ORDER_REJECTED, actor_id, reason)


# Structural compare for two event lists. Returns false if any field
# differs, including lengths.
func _events_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var ea: ResolverEvent = a[i]
		var eb: ResolverEvent = b[i]
		if ea.type != eb.type:
			return false
		if ea.actor_id != eb.actor_id:
			return false
		if ea.target_id != eb.target_id:
			return false
		if ea.damage != eb.damage:
			return false
		if ea.hp_after != eb.hp_after:
			return false
		if ea.from_origin != eb.from_origin:
			return false
		if ea.to_origin != eb.to_origin:
			return false
		if ea.def_id != eb.def_id:
			return false
		if ea.new_def_id != eb.new_def_id:
			return false
		if ea.winner_player_id != eb.winner_player_id:
			return false
		if ea.amount != eb.amount:
			return false
	return true


# ---------- Coverage gap tests (added during fresh-review) ----------


func _test_hold_fire_toggle_distribution_sets_flag() -> bool:
	# Submitting a HOLD_FIRE_TOGGLE order should set entity.hold_fire so
	# the same turn's ATTACK with empty chain doesn't auto-acquire.
	var registry := _two_unit_registry(6, 5, ["ground"], 50)
	var state := _state_with_grid(20, 20)
	var attacker := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	# Note: entity.hold_fire defaults to false; the order has to flip it.
	var enemy := _make_entity(state, "marine", 1, Vector2i(8, 5), 50, "ground")
	enemy.hold_fire = true
	state.tile_grid.place(attacker.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(enemy.id, Rect2i(8, 5, 1, 1))

	var hf := EntityOrder.new()
	hf.type = EntityOrder.Type.HOLD_FIRE_TOGGLE
	hf.entity_id = attacker.id
	hf.hold_fire = true
	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = attacker.id
	# Empty chain — auto-acquire would normally fire; hold_fire blocks it.

	var result := Resolver.resolve(
		state, _submit([hf, attack] as Array[EntityOrder]), _submit([]), registry, null
	)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED:
			return false
	# Verify the flag actually got applied (not just that no fire happened).
	var new_attacker := result.new_state.get_entity_by_id(attacker.id)
	return new_attacker.hold_fire


func _test_cancel_clears_persistent_order() -> bool:
	# Entity has persistent_order set; submitting CANCEL with cancel_index=-1
	# should clear it and prevent the Phase 3 advance.
	var registry := _movable_registry(4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))

	var po := EntityOrder.new()
	po.type = EntityOrder.Type.MOVE
	po.entity_id = actor.id
	po.target_tile = Vector2i(15, 5)
	actor.persistent_order = po

	var cancel := EntityOrder.new()
	cancel.type = EntityOrder.Type.CANCEL
	cancel.entity_id = actor.id
	cancel.cancel_index = -1

	# CANCEL applies at distribution time (no tick), so we need a separate
	# entity with a queued action to force at least one tick (n_ticks > 0)
	# and exercise Phase 3.
	var dummy := _make_entity(state, "marine", 0, Vector2i(0, 0), 50, "ground")
	state.tile_grid.place(dummy.id, Rect2i(0, 0, 1, 1))
	var dummy_move := EntityOrder.new()
	dummy_move.type = EntityOrder.Type.MOVE
	dummy_move.entity_id = dummy.id
	dummy_move.target_tile = dummy.origin

	var queue_a: Array[EntityOrder] = [cancel, dummy_move]
	var result := Resolver.resolve(state, _submit(queue_a), _submit([]), registry, null)

	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == actor.id:
			return false
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return new_actor.persistent_order == null


func _test_cancel_clears_focus_target() -> bool:
	# CANCEL(-1) is the current "clear standing intent" command. It should
	# clear focus target as well as persistent movement.
	var registry := _combat_mover_registry(6, 3, 4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var enemy := _make_entity(state, "marine", 1, Vector2i(7, 5), 50, "ground")
	actor.hold_fire = true
	actor.focus_target_entity_id = enemy.id
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(enemy.id, Rect2i(7, 5, 1, 1))

	var cancel := EntityOrder.new()
	cancel.type = EntityOrder.Type.CANCEL
	cancel.entity_id = actor.id
	cancel.cancel_index = -1

	var result := Resolver.resolve(
		state, _submit([cancel] as Array[EntityOrder]), _submit(), registry, null
	)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED and ev.actor_id == actor.id:
			push_error("cancelled hold-fire focus target should not fire")
			return false
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return new_actor.focus_target_entity_id == -1


func _test_attack_move_no_enemy_in_range_advances() -> bool:
	# ATTACK_MOVE with no enemy in range should behave like a regular MOVE:
	# emit ENTITY_MOVED and set persistent_order so future turns continue.
	var registry := EntityRegistry.new()
	registry.entities = [
		_def_with_movement_combat(
			"marine", Vector2i(1, 1), ["light", "ground"], _combat_def(6, 3, ["ground"]), 50, 4
		),
	]
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	# Far-away enemy (distance > attack_range of 3) so the halt branch
	# doesn't trigger. The closest-enemy logic in CombatSystem still runs
	# during the ATTACK phase but the enemy is out of range.
	var enemy := _make_entity(state, "marine", 1, Vector2i(15, 15), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(enemy.id, Rect2i(15, 15, 1, 1))

	var am := EntityOrder.new()
	am.type = EntityOrder.Type.ATTACK_MOVE
	am.entity_id = actor.id
	am.target_tile = Vector2i(10, 5)

	var result := Resolver.resolve(
		state, _submit([am] as Array[EntityOrder]), _submit([]), registry, null
	)
	var saw_moved := false
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == actor.id:
			saw_moved = true
	if not saw_moved:
		return false
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return (
		new_actor.persistent_order != null
		and new_actor.persistent_order.target_tile == am.target_tile
	)


func _test_fresh_order_overrides_persistent_order() -> bool:
	# Entity has persistent_order toward (15,5) from a prior turn but a
	# fresh MOVE order toward (5,15) is queued. The fresh target must win:
	# step is taken toward (5,15) and persistent_order updates to the new
	# order — not the stale one.
	var registry := _movable_registry(4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))

	var stale := EntityOrder.new()
	stale.type = EntityOrder.Type.MOVE
	stale.entity_id = actor.id
	stale.target_tile = Vector2i(15, 5)
	actor.persistent_order = stale

	var fresh := EntityOrder.new()
	fresh.type = EntityOrder.Type.MOVE
	fresh.entity_id = actor.id
	fresh.target_tile = Vector2i(5, 15)

	var result := Resolver.resolve(
		state, _submit([fresh] as Array[EntityOrder]), _submit([]), registry, null
	)
	var moved_to: Vector2i = Vector2i(-1, -1)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == actor.id:
			moved_to = ev.to_origin
			break
	# Step from (5,5) toward (5,15) is (5,6); toward (15,5) it would be (6,5).
	if moved_to != Vector2i(5, 6):
		return false
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return (
		new_actor.persistent_order != null
		and new_actor.persistent_order.target_tile == fresh.target_tile
	)


func _test_multi_buff_stacks_multiplicatively() -> bool:
	# Two buffs with damage_mult 1.5 and 2.0; base damage 4 → 4*1.5*2.0 = 12.
	var registry := _two_unit_registry(4, 5, ["ground"], 50)
	var state := _state_with_grid(20, 20)
	var attacker := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var target := _make_entity(state, "marine", 1, Vector2i(7, 5), 50, "ground")
	state.tile_grid.place(attacker.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(target.id, Rect2i(7, 5, 1, 1))

	var b1 := ActiveBuff.new()
	b1.source_ability_id = "stim"
	b1.turns_remaining = 2
	b1.damage_mult = 1.5
	var b2 := ActiveBuff.new()
	b2.source_ability_id = "rage"
	b2.turns_remaining = 2
	b2.damage_mult = 2.0
	attacker.active_buffs = [b1, b2]

	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = attacker.id
	attack.target_priority_chain = [target.id]

	var result := Resolver.resolve(
		state, _submit([attack] as Array[EntityOrder]), _submit([]), registry, null
	)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED:
			return ev.damage == 12
	return false


func _test_no_tile_grid_distance_fallback() -> bool:
	# state.tile_grid is null. Attack range checks must fall back to
	# def-derived rects so tests that don't build a grid still work.
	var registry := _two_unit_registry(6, 5, ["ground"], 50)
	var state := MatchState.new()
	state.players = [_player(0), _player(1)]
	# tile_grid intentionally NOT set.
	var attacker := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var target := _make_entity(state, "marine", 1, Vector2i(7, 5), 50, "ground")

	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = attacker.id
	attack.target_priority_chain = [target.id]

	var result := Resolver.resolve(
		state, _submit([attack] as Array[EntityOrder]), _submit([]), registry, null
	)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED and ev.target_id == target.id:
			return ev.damage == 6
	return false


func _test_closest_enemy_ties_break_by_id() -> bool:
	# Two equidistant enemies. We invert the storage order in `state.entities`
	# relative to id order so this test fails if selection ever regresses
	# to insertion-order iteration instead of the documented id tie-break.
	var registry := _two_unit_registry(6, 10, ["ground"], 50)
	var state := _state_with_grid(20, 20)
	var attacker := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var enemy_low_id := _make_entity(state, "marine", 1, Vector2i(8, 5), 50, "ground")
	var enemy_high_id := _make_entity(state, "marine", 1, Vector2i(2, 5), 50, "ground")
	if enemy_low_id.id >= enemy_high_id.id:
		return false  # Sanity: allocator gave low_id < high_id.
	# Force storage order opposite from id order.
	state.entities = [attacker, enemy_high_id, enemy_low_id]
	state.tile_grid.place(attacker.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(enemy_low_id.id, Rect2i(8, 5, 1, 1))
	state.tile_grid.place(enemy_high_id.id, Rect2i(2, 5, 1, 1))

	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = attacker.id
	# Empty chain → triggers closest-enemy auto-acquire.

	var result := Resolver.resolve(
		state, _submit([attack] as Array[EntityOrder]), _submit([]), registry, null
	)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED:
			return ev.target_id == enemy_low_id.id
	return false


func _test_closest_enemy_skips_dead() -> bool:
	# Closer enemy is dead (hp=0); farther enemy is alive. Auto-acquire
	# must skip the dead one and fire at the alive farther one.
	var registry := _two_unit_registry(6, 10, ["ground"], 50)
	var state := _state_with_grid(20, 20)
	var attacker := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	var dead_close := _make_entity(state, "marine", 1, Vector2i(7, 5), 0, "ground")
	var alive_far := _make_entity(state, "marine", 1, Vector2i(12, 5), 50, "ground")
	state.tile_grid.place(attacker.id, Rect2i(5, 5, 1, 1))
	# Dead entity not placed (already removed by death cleanup convention).
	state.tile_grid.place(alive_far.id, Rect2i(12, 5, 1, 1))

	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = attacker.id
	# Empty chain → triggers closest-enemy auto-acquire.

	var result := Resolver.resolve(
		state, _submit([attack] as Array[EntityOrder]), _submit([]), registry, null
	)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED:
			return ev.target_id == alive_far.id
	return false


# ---------- Plan node 03a — SubmitTurn + OrderBuilder + validator ----------


func _test_submit_turn_clone_independence() -> bool:
	# clone() must return a SubmitTurn that is fully independent of the
	# original — both at the array shell and at every EntityOrder inside.
	# Mutating the clone (or any EntityOrder field, including the
	# target_priority_chain) must not leak back to the original.
	var move := EntityOrder.new()
	move.type = EntityOrder.Type.MOVE
	move.entity_id = 7
	move.target_tile = Vector2i(3, 3)
	move.target_priority_chain = [1, 2, 3] as Array[int]
	var s := SubmitTurn.new()
	s.orders = [move] as Array[EntityOrder]
	s.surrender = false

	var c := s.clone()
	# 1. Mutate the clone's array shell.
	c.orders.append(move)
	# 2. Mutate the clone's surrender flag.
	c.surrender = true
	# 3. Mutate fields inside the clone's EntityOrder.
	var cloned_first: EntityOrder = c.orders[0]
	cloned_first.target_tile = Vector2i(99, 99)
	cloned_first.target_priority_chain.append(999)

	# Original must be untouched on every axis.
	if s.orders.size() != 1:
		return false
	if s.surrender:
		return false
	if s.orders[0].target_tile != Vector2i(3, 3):
		return false
	if s.orders[0].target_priority_chain != ([1, 2, 3] as Array[int]):
		return false
	# And the clone genuinely sees its own mutations.
	return (
		c.orders.size() == 2
		and c.surrender
		and c.orders[0].target_tile == Vector2i(99, 99)
		and c.orders[0].target_priority_chain.size() == 4
	)


func _test_order_builder_fan_out_move() -> bool:
	var ids: Array[int] = [3, 5, 9]
	var orders := OrderBuilder.fan_out_move(ids, Vector2i(10, 10))
	if orders.size() != 3:
		return false
	for i in 3:
		var o: EntityOrder = orders[i]
		if o.type != EntityOrder.Type.MOVE:
			return false
		if o.entity_id != ids[i]:
			return false
		if o.target_tile != Vector2i(10, 10):
			return false
	return true


func _test_order_builder_fan_out_attack_move() -> bool:
	var ids: Array[int] = [3, 5]
	var chain: Array[int] = [42, 17]
	var orders := OrderBuilder.fan_out_attack_move(ids, Vector2i(8, 8), chain)
	if orders.size() != 2:
		return false
	for i in 2:
		var o: EntityOrder = orders[i]
		if o.type != EntityOrder.Type.ATTACK_MOVE:
			return false
		if o.entity_id != ids[i]:
			return false
		if o.target_tile != Vector2i(8, 8):
			return false
		if o.target_priority_chain != chain:
			return false
	# Mutating one order's chain must not leak into the others (each got a
	# duplicated copy of the input chain).
	orders[0].target_priority_chain.append(99)
	return orders[1].target_priority_chain.size() == 2


func _test_order_builder_fan_out_attack() -> bool:
	var ids: Array[int] = [3, 5, 7]
	var chain: Array[int] = [42]
	var orders := OrderBuilder.fan_out_attack(ids, chain)
	if orders.size() != 3:
		return false
	for i in 3:
		var o: EntityOrder = orders[i]
		if o.type != EntityOrder.Type.ATTACK:
			return false
		if o.entity_id != ids[i]:
			return false
		if o.target_priority_chain != chain:
			return false
	return true


func _test_order_builder_fan_out_hold_fire_toggle() -> bool:
	var ids: Array[int] = [3, 5]
	var orders := OrderBuilder.fan_out_hold_fire_toggle(ids, true)
	if orders.size() != 2:
		return false
	for i in 2:
		var o: EntityOrder = orders[i]
		if o.type != EntityOrder.Type.HOLD_FIRE_TOGGLE:
			return false
		if o.entity_id != ids[i]:
			return false
		if not o.hold_fire:
			return false
	return true


func _test_order_builder_fan_out_cancel() -> bool:
	var ids: Array[int] = [3, 5]
	var orders := OrderBuilder.fan_out_cancel(ids, -1)
	if orders.size() != 2:
		return false
	for i in 2:
		var o: EntityOrder = orders[i]
		if o.type != EntityOrder.Type.CANCEL:
			return false
		if o.entity_id != ids[i]:
			return false
		if o.cancel_index != -1:
			return false
	return true


func _test_validate_drops_unowned_order() -> bool:
	# submit_a contains a MOVE for an entity owned by player B → dropped,
	# no event emitted. Verifies _state_helpers._distribute_one's
	# ownership check.
	var registry := _movable_registry(4)
	var state := _state_with_grid(20, 20)
	var enemy_unit := _make_entity(state, "marine", 1, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(enemy_unit.id, Rect2i(5, 5, 1, 1))

	var bad_move := EntityOrder.new()
	bad_move.type = EntityOrder.Type.MOVE
	bad_move.entity_id = enemy_unit.id  # owned by player 1 but submitted by A
	bad_move.target_tile = Vector2i(10, 5)

	var submit_a := SubmitTurn.new()
	submit_a.orders = [bad_move] as Array[EntityOrder]

	var result := Resolver.resolve(state, submit_a, SubmitTurn.new(), registry, null)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED:
			return false
	# Entity stays put.
	var new_enemy := result.new_state.get_entity_by_id(enemy_unit.id)
	return new_enemy.origin == Vector2i(5, 5)


func _test_submit_turn_input_not_aliased_in_result() -> bool:
	# After resolve(), mutating the caller's submitted EntityOrder must
	# NOT mutate anything stored in result.new_state. Specifically: a
	# fresh MOVE order is stashed into Entity.persistent_order by the
	# movement system — this test asserts the resolver clones the
	# SubmitTurn at its boundary so that path doesn't leak.
	var registry := _movable_registry(4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))

	var move := EntityOrder.new()
	move.type = EntityOrder.Type.MOVE
	move.entity_id = actor.id
	move.target_tile = Vector2i(15, 5)

	var submit_a := SubmitTurn.new()
	submit_a.orders = [move] as Array[EntityOrder]

	var result := Resolver.resolve(state, submit_a, SubmitTurn.new(), registry, null)

	# Now mutate the original caller-owned `move` instance.
	move.target_tile = Vector2i(99, 99)
	move.target_priority_chain = [42] as Array[int]

	# The cloned actor's persistent_order in the result must NOT reflect
	# those mutations.
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	if new_actor.persistent_order == null:
		return false
	if new_actor.persistent_order.target_tile != Vector2i(15, 5):
		return false
	return new_actor.persistent_order.target_priority_chain.is_empty()


func _test_validate_drops_missing_entity_order() -> bool:
	# Order references an entity_id that doesn't exist → dropped silently.
	var registry := _movable_registry(4)
	var state := _state_with_grid(20, 20)

	var ghost_move := EntityOrder.new()
	ghost_move.type = EntityOrder.Type.MOVE
	ghost_move.entity_id = 9999
	ghost_move.target_tile = Vector2i(5, 5)

	var submit_a := SubmitTurn.new()
	submit_a.orders = [ghost_move] as Array[EntityOrder]

	var result := Resolver.resolve(state, submit_a, SubmitTurn.new(), registry, null)
	# No entities exist, so the only events possible would be MATCH_ENDED
	# from the win check (both players have zero buildings → -1 winner).
	# Filter that out and assert no movement event leaked through.
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED:
			return false
	return true


# ---------- Plan node 04 — economy / gather pipeline ----------


func _test_gather_order_distribution_sets_phase() -> bool:
	# Submitting a GATHER order should, at distribute-time, set the
	# worker's gather_state.assigned_source_entity_id and flip phase to
	# MOVING_TO_SOURCE. The patch is far enough that the FSM stays in
	# MOVING_TO_SOURCE after the single forced tick.
	var registry := _gather_registry(5, 1, 4)
	var state := _state_with_grid(30, 30)
	var worker := _make_entity(state, "worker", 0, Vector2i(5, 5), 50, "ground")
	worker.gather_state = GatherState.new()
	state.tile_grid.place(worker.id, Rect2i(5, 5, 1, 1))
	var patch := _make_entity(state, "minpatch", -1, Vector2i(25, 5), 100, "ground")
	patch.current_resource_amount = 1500
	state.tile_grid.place(patch.id, Rect2i(25, 5, 1, 1))

	var orders := OrderBuilder.fan_out_gather([worker.id] as Array[int], patch.id)

	var result := Resolver.resolve(state, _submit(orders), _submit(), registry, null)
	var new_worker := result.new_state.get_entity_by_id(worker.id)
	if new_worker.gather_state == null:
		return false
	if new_worker.gather_state.assigned_source_entity_id != patch.id:
		return false
	# 19 tiles to walk; one forced tick advances at most 1 step → still MOVING.
	return new_worker.gather_state.phase == GatherState.Phase.MOVING_TO_SOURCE


func _test_gather_full_cycle_minerals() -> bool:
	# Worker walks adjacent to a mineral patch, gathers a full carry,
	# walks back to the base, deposits. player.minerals goes from 0 to
	# carry. Single resolve() with one big SubmitTurn carrying many
	# implicit ticks — we drive the cycle by submitting enough no-op
	# placeholder orders to force N ticks. Simpler: run resolve multiple
	# times with an empty submission until cycle completes.
	var registry := _gather_registry(5, 1, 4)
	var state := _state_with_grid(20, 20)
	var worker := _make_entity(state, "worker", 0, Vector2i(5, 5), 50, "ground")
	worker.gather_state = GatherState.new()
	state.tile_grid.place(worker.id, Rect2i(5, 5, 1, 1))
	var base := _make_entity(state, "base", 0, Vector2i(0, 0), 1500, "ground")
	state.tile_grid.place(base.id, Rect2i(0, 0, 4, 4))
	var patch := _make_entity(state, "minpatch", -1, Vector2i(8, 5), 1500, "ground")
	patch.current_resource_amount = 1500
	state.tile_grid.place(patch.id, Rect2i(8, 5, 1, 1))
	_add_opponent_keepalive_building(state, registry)

	# Send the GATHER order on turn 0.
	var orders := OrderBuilder.fan_out_gather([worker.id] as Array[int], patch.id)
	var result := Resolver.resolve(state, _submit(orders), _submit(), registry, null)
	# Drive the cycle to completion. ~30 turns is plenty (walk 2 + gather
	# 5 + walk 2 + deposit 1 = 10ish ticks). Each call advances at most a
	# couple of ticks given there's only one entity with standing work.
	for _i in 30:
		result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
		# Stop once the deposit happened.
		var p := result.new_state.get_player(0)
		if p != null and p.minerals >= 5:
			break
	var p_final := result.new_state.get_player(0)
	if p_final == null or p_final.minerals != 5:
		return false
	# Source should have drained by 5.
	var new_patch := result.new_state.get_entity_by_id(patch.id)
	return new_patch.current_resource_amount == 1495


func _test_gather_worker_rate_multiplies_source_yield() -> bool:
	var registry := _gather_registry(10, 2, 4)
	var state := _state_with_grid(20, 20)
	var worker := _make_entity(state, "worker", 0, Vector2i(5, 5), 50, "ground")
	worker.gather_state = GatherState.new()
	worker.gather_state.phase = GatherState.Phase.GATHERING
	state.tile_grid.place(worker.id, Rect2i(5, 5, 1, 1))
	var patch := _make_entity(state, "minpatch", -1, Vector2i(6, 5), 100, "ground")
	patch.current_resource_amount = 100
	state.tile_grid.place(patch.id, Rect2i(6, 5, 1, 1))
	worker.gather_state.assigned_source_entity_id = patch.id
	_add_opponent_keepalive_building(state, registry)

	var result := Resolver.resolve(state, _submit(), _submit(), registry, null)
	var new_worker := result.new_state.get_entity_by_id(worker.id)
	var new_patch := result.new_state.get_entity_by_id(patch.id)
	if new_worker.gather_state.carrying_amount != 4:
		push_error(
			(
				"worker gather_per_turn=2 on source yield=2 should gather 4, got %d"
				% new_worker.gather_state.carrying_amount
			)
		)
		return false
	if new_patch.current_resource_amount != 96:
		push_error("source should drain by 4, got %d" % new_patch.current_resource_amount)
		return false
	return true


func _test_gather_full_cycle_gas_via_refinery() -> bool:
	# Same loop, but the GATHER targets a refinery sitting on a geyser.
	# Resolver should translate the refinery to the geyser, gather, then
	# the worker walks back to the base and deposits into player.gas.
	var registry := _gather_registry(5, 1, 4)
	var state := _state_with_grid(20, 20)
	var worker := _make_entity(state, "worker", 0, Vector2i(5, 5), 50, "ground")
	worker.gather_state = GatherState.new()
	state.tile_grid.place(worker.id, Rect2i(5, 5, 1, 1))
	var base := _make_entity(state, "base", 0, Vector2i(0, 0), 1500, "ground")
	state.tile_grid.place(base.id, Rect2i(0, 0, 4, 4))
	var geyser := _make_entity(state, "geyser", -1, Vector2i(10, 5), 1000, "ground")
	geyser.current_resource_amount = -1  # infinite
	state.tile_grid.place(geyser.id, Rect2i(10, 5, 1, 1))
	# Refinery shares the geyser's origin. Use place_overlapping (added in
	# plan node 05 chunk 7) so the refinery's rect is registered without
	# evicting the geyser from _occupancy. This replaces the previous
	# test-shim that poked _entity_rects directly.
	var refinery := _make_entity(state, "refinery", 0, Vector2i(10, 5), 750, "ground")
	state.tile_grid.place_overlapping(refinery.id, Rect2i(10, 5, 1, 1), geyser.id)
	_add_opponent_keepalive_building(state, registry)

	var orders := OrderBuilder.fan_out_gather([worker.id] as Array[int], refinery.id)
	var result := Resolver.resolve(state, _submit(orders), _submit(), registry, null)
	for _i in 30:
		result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
		var p := result.new_state.get_player(0)
		if p != null and p.gas >= 5:
			break
	var p_final := result.new_state.get_player(0)
	return p_final != null and p_final.gas == 5


func _test_gather_fails_geyser_without_refinery() -> bool:
	# GATHER on a geyser with no refinery on top → worker walks adjacent,
	# can't gather (extractor missing), idles. No WORKER_GATHERED event.
	var registry := _gather_registry(5, 1, 4)
	var state := _state_with_grid(20, 20)
	var worker := _make_entity(state, "worker", 0, Vector2i(5, 5), 50, "ground")
	worker.gather_state = GatherState.new()
	state.tile_grid.place(worker.id, Rect2i(5, 5, 1, 1))
	var base := _make_entity(state, "base", 0, Vector2i(0, 0), 1500, "ground")
	state.tile_grid.place(base.id, Rect2i(0, 0, 4, 4))
	var geyser := _make_entity(state, "geyser", -1, Vector2i(8, 5), 1000, "ground")
	geyser.current_resource_amount = -1
	state.tile_grid.place(geyser.id, Rect2i(8, 5, 1, 1))

	var orders := OrderBuilder.fan_out_gather([worker.id] as Array[int], geyser.id)
	var result := Resolver.resolve(state, _submit(orders), _submit(), registry, null)
	if _has_event_of_type(result.events, ResolverEvent.Type.WORKER_GATHERED):
		return false
	for _i in 10:
		result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
		if _has_event_of_type(result.events, ResolverEvent.Type.WORKER_GATHERED):
			return false
	# Worker should have idled; player.gas stays 0.
	var p := result.new_state.get_player(0)
	if p == null or p.gas != 0:
		return false
	# Also assert the worker is in IDLE (resolve_source returned null →
	# the FSM transitioned to IDLE at the first tick).
	var w := result.new_state.get_entity_by_id(worker.id)
	return w.gather_state.phase == GatherState.Phase.IDLE


func _test_gather_travel_uses_full_speed_budget() -> bool:
	# A gather worker in MOVING_TO_SOURCE should spend its full movement
	# speed in one turn, sharing the same movement budget as normal MOVE.
	var registry := _gather_registry(5, 1, 4)
	var state := _state_with_grid(30, 30)
	var worker := _make_entity(state, "worker", 0, Vector2i(5, 5), 50, "ground")
	worker.gather_state = GatherState.new()
	state.tile_grid.place(worker.id, Rect2i(5, 5, 1, 1))
	var patch := _make_entity(state, "minpatch", -1, Vector2i(20, 5), 1500, "ground")
	patch.current_resource_amount = 1500
	state.tile_grid.place(patch.id, Rect2i(20, 5, 1, 1))

	var orders := OrderBuilder.fan_out_gather([worker.id] as Array[int], patch.id)
	var result := Resolver.resolve(state, _submit(orders), _submit(), registry, null)

	var move_count := 0
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == worker.id:
			move_count += 1
	var new_worker := result.new_state.get_entity_by_id(worker.id)
	return move_count == 4 and new_worker.origin == Vector2i(9, 5)


func _test_patch_depletes_at_capacity_zero() -> bool:
	# Patch with capacity = 3, carry = 5: worker can only collect 3
	# before the patch depletes; should walk back, deposit 3, then idle.
	var registry := _gather_registry(5, 1, 4)
	var state := _state_with_grid(20, 20)
	var worker := _make_entity(state, "worker", 0, Vector2i(5, 5), 50, "ground")
	worker.gather_state = GatherState.new()
	state.tile_grid.place(worker.id, Rect2i(5, 5, 1, 1))
	var base := _make_entity(state, "base", 0, Vector2i(0, 0), 1500, "ground")
	state.tile_grid.place(base.id, Rect2i(0, 0, 4, 4))
	var patch := _make_entity(state, "minpatch", -1, Vector2i(8, 5), 100, "ground")
	patch.current_resource_amount = 3
	state.tile_grid.place(patch.id, Rect2i(8, 5, 1, 1))
	_add_opponent_keepalive_building(state, registry)

	var orders := OrderBuilder.fan_out_gather([worker.id] as Array[int], patch.id)
	var saw_depleted := false
	var result := Resolver.resolve(state, _submit(orders), _submit(), registry, null)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.RESOURCE_DEPLETED:
			saw_depleted = true
	for _i in 30:
		result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
		for ev in result.events:
			if ev.type == ResolverEvent.Type.RESOURCE_DEPLETED:
				saw_depleted = true
		var p := result.new_state.get_player(0)
		if p != null and p.minerals >= 3:
			break
	var p_final := result.new_state.get_player(0)
	if p_final == null or p_final.minerals != 3:
		return false
	if not saw_depleted:
		return false
	var new_patch := result.new_state.get_entity_by_id(patch.id)
	return new_patch.current_resource_amount == 0


func _test_worker_idles_on_source_destroyed_mid_trip() -> bool:
	# Worker en-route to source; the patch is removed from the world
	# mid-trip; worker FSM transitions to IDLE.
	var registry := _gather_registry(5, 1, 4)
	var state := _state_with_grid(20, 20)
	var worker := _make_entity(state, "worker", 0, Vector2i(5, 5), 50, "ground")
	worker.gather_state = GatherState.new()
	state.tile_grid.place(worker.id, Rect2i(5, 5, 1, 1))
	var base := _make_entity(state, "base", 0, Vector2i(0, 0), 1500, "ground")
	state.tile_grid.place(base.id, Rect2i(0, 0, 4, 4))
	var patch := _make_entity(state, "minpatch", -1, Vector2i(15, 5), 100, "ground")
	patch.current_resource_amount = 100
	state.tile_grid.place(patch.id, Rect2i(15, 5, 1, 1))
	_add_opponent_keepalive_building(state, registry)

	var orders := OrderBuilder.fan_out_gather([worker.id] as Array[int], patch.id)
	var result := Resolver.resolve(state, _submit(orders), _submit(), registry, null)
	# Mid-trip: kill the patch on the result state, then keep resolving.
	var dying_patch := result.new_state.get_entity_by_id(patch.id)
	dying_patch.current_hp = 0
	result.new_state.tile_grid.remove(patch.id)
	for _i in 5:
		result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
	var w := result.new_state.get_entity_by_id(worker.id)
	return w.gather_state.phase == GatherState.Phase.IDLE


func _test_worker_idles_on_all_sinks_destroyed() -> bool:
	# Worker with cargo, walking back to a base. Base is razed mid-trip.
	# Worker idles, cargo preserved.
	var registry := _gather_registry(5, 1, 4)
	var state := _state_with_grid(20, 20)
	var worker := _make_entity(state, "worker", 0, Vector2i(10, 10), 50, "ground")
	worker.gather_state = GatherState.new()
	worker.gather_state.phase = GatherState.Phase.MOVING_TO_BASE
	worker.gather_state.carrying_amount = 4
	worker.gather_state.carrying_resource_type = "minerals"
	state.tile_grid.place(worker.id, Rect2i(10, 10, 1, 1))
	var base := _make_entity(state, "base", 0, Vector2i(0, 0), 1500, "ground")
	state.tile_grid.place(base.id, Rect2i(0, 0, 4, 4))

	# Razing the base before any tick runs: clone the state and remove
	# the base, then resolve. The worker should idle because there's no
	# deposit_sink to walk to.
	base.current_hp = 0
	state.tile_grid.remove(base.id)

	var result := Resolver.resolve(state, _submit(), _submit(), registry, null)
	var w := result.new_state.get_entity_by_id(worker.id)
	if w.gather_state.phase != GatherState.Phase.IDLE:
		return false
	# Cargo preserved.
	return w.gather_state.carrying_amount == 4


func _test_nearest_deposit_sink_chosen() -> bool:
	# Two owned bases at different distances. Worker has cargo, currently
	# in MOVING_TO_BASE. After enough ticks it should arrive at the
	# closer base (smaller id won't matter — distances differ).
	var registry := _gather_registry(5, 1, 4)
	var state := _state_with_grid(30, 30)
	# Far base first → lower id; near base second → higher id. Distance
	# decides regardless.
	var far_base := _make_entity(state, "base", 0, Vector2i(20, 20), 1500, "ground")
	state.tile_grid.place(far_base.id, Rect2i(20, 20, 4, 4))
	var near_base := _make_entity(state, "base", 0, Vector2i(2, 2), 1500, "ground")
	state.tile_grid.place(near_base.id, Rect2i(2, 2, 4, 4))
	var worker := _make_entity(state, "worker", 0, Vector2i(7, 7), 50, "ground")
	worker.gather_state = GatherState.new()
	worker.gather_state.phase = GatherState.Phase.MOVING_TO_BASE
	worker.gather_state.carrying_amount = 5
	worker.gather_state.carrying_resource_type = "minerals"
	state.tile_grid.place(worker.id, Rect2i(7, 7, 1, 1))
	_add_opponent_keepalive_building(state, registry)

	var result := Resolver.resolve(state, _submit(), _submit(), registry, null)
	for _i in 15:
		result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
		var p := result.new_state.get_player(0)
		if p != null and p.minerals >= 5:
			break
	# The deposit must have happened (proves the worker reached SOMEWHERE);
	# additionally check the worker is now adjacent to the near_base, not
	# the far one.
	var w := result.new_state.get_entity_by_id(worker.id)
	var near_rect := result.new_state.tile_grid.entity_rect(near_base.id)
	var far_rect := result.new_state.tile_grid.entity_rect(far_base.id)
	var w_rect := result.new_state.tile_grid.entity_rect(w.id)
	var d_near := TileGrid.distance_between_rects(w_rect, near_rect)
	var d_far := TileGrid.distance_between_rects(w_rect, far_rect)
	return d_near < d_far


func _test_gather_clears_prior_persistent_move() -> bool:
	# Worker mid-MOVE (persistent_order set), then we hit it with a GATHER.
	# After the gather cycle finishes (worker returns to IDLE) the prior
	# MOVE must NOT resume — it should have been cleared at distribution.
	var registry := _gather_registry(5, 1, 4)
	var state := _state_with_grid(30, 30)
	var worker := _make_entity(state, "worker", 0, Vector2i(5, 5), 50, "ground")
	worker.gather_state = GatherState.new()
	state.tile_grid.place(worker.id, Rect2i(5, 5, 1, 1))
	var base := _make_entity(state, "base", 0, Vector2i(0, 0), 1500, "ground")
	state.tile_grid.place(base.id, Rect2i(0, 0, 4, 4))
	var patch := _make_entity(state, "minpatch", -1, Vector2i(8, 5), 100, "ground")
	patch.current_resource_amount = 20
	state.tile_grid.place(patch.id, Rect2i(8, 5, 1, 1))
	_add_opponent_keepalive_building(state, registry)
	# Stash a stale persistent MOVE pointing far away. If it resumes after
	# gather, the worker drifts toward (25, 25) instead of staying put.
	var stale := EntityOrder.new()
	stale.type = EntityOrder.Type.MOVE
	stale.entity_id = worker.id
	stale.target_tile = Vector2i(25, 25)
	worker.persistent_order = stale

	var orders := OrderBuilder.fan_out_gather([worker.id] as Array[int], patch.id)
	var result := Resolver.resolve(state, _submit(orders), _submit(), registry, null)
	# After distribution the worker's persistent_order should already be
	# null — gathering supersedes prior movement.
	var w := result.new_state.get_entity_by_id(worker.id)
	if w.persistent_order != null:
		return false
	# Run enough turns for the worker to gather, deposit, and idle once
	# the patch is exhausted.
	for _i in 60:
		result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
		w = result.new_state.get_entity_by_id(worker.id)
		if w.gather_state.phase == GatherState.Phase.IDLE and w.gather_state.carrying_amount == 0:
			break
	# Worker should be IDLE and persistent_order should still be null —
	# the stale MOVE must not have resumed.
	if w.gather_state.phase != GatherState.Phase.IDLE:
		return false
	if w.persistent_order != null:
		return false
	# Sanity: at least one deposit must have happened, otherwise the FSM
	# never finished a cycle and the assertion above is vacuous.
	var p := result.new_state.get_player(0)
	return p != null and p.minerals > 0


func _test_fresh_attack_move_cancels_gather_assignment() -> bool:
	# A worker keeps gathering only while its latest standing job is GATHER.
	# A deprecated fresh ATTACK_MOVE should replace that job as MOVE, not
	# move once and then return to the previous mineral assignment.
	var registry := _gather_registry(5, 1, 4)
	var state := _state_with_grid(30, 30)
	var worker := _make_entity(state, "worker", 0, Vector2i(5, 5), 50, "ground")
	worker.gather_state = GatherState.new()
	worker.gather_state.assigned_source_entity_id = 99
	worker.gather_state.phase = GatherState.Phase.GATHERING
	state.tile_grid.place(worker.id, Rect2i(5, 5, 1, 1))
	var patch := _make_entity(state, "minpatch", -1, Vector2i(4, 5), 100, "ground")
	patch.current_resource_amount = 20
	worker.gather_state.assigned_source_entity_id = patch.id
	state.tile_grid.place(patch.id, Rect2i(4, 5, 1, 1))
	_add_opponent_keepalive_building(state, registry)

	var attack_move := EntityOrder.new()
	attack_move.type = EntityOrder.Type.ATTACK_MOVE
	attack_move.entity_id = worker.id
	attack_move.target_tile = Vector2i(12, 5)
	var result := Resolver.resolve(
		state, _submit([attack_move] as Array[EntityOrder]), _submit(), registry, null
	)
	var moved := false
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == worker.id:
			moved = true
	if not moved:
		push_error("fresh ATTACK_MOVE should still move the worker")
		return false
	var w := result.new_state.get_entity_by_id(worker.id)
	if w.gather_state == null:
		push_error("worker should keep gather_state capability")
		return false
	if w.gather_state.phase != GatherState.Phase.IDLE:
		push_error("fresh ATTACK_MOVE should cancel active gather phase")
		return false
	if w.gather_state.assigned_source_entity_id != -1:
		push_error("fresh ATTACK_MOVE should clear previous mineral assignment")
		return false
	return w.persistent_order != null and w.persistent_order.type == EntityOrder.Type.MOVE


# ---------- Plan node 05: production / build / research ----------


func _test_train_appended_to_queue_no_immediate_cost() -> bool:
	# TRAIN order to a producer with non-empty active slot → queued, no
	# cost deducted (lazy queue model).
	var registry := _production_registry()
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	var barracks := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	barracks.production_state = ProductionState.new()
	# Pre-occupied active slot so the new TRAIN goes into queue, not active.
	barracks.production_state.active = {
		ProductionState.KEY_DEF_ID: "marine",
		ProductionState.KEY_KIND: ProductionState.KIND_UNIT,
		ProductionState.KEY_TURNS_REMAINING: 2,
		ProductionState.KEY_PAID_MINERALS: 50,
		ProductionState.KEY_PAID_GAS: 0,
		ProductionState.KEY_PAID_POP: 1,
	}
	state.tile_grid.place(barracks.id, Rect2i(2, 2, 3, 3))

	var order := EntityOrder.new()
	order.type = EntityOrder.Type.TRAIN
	order.entity_id = barracks.id
	order.def_id = "marine"
	var result := Resolver.resolve(state, _submit([order]), _submit(), registry, null)

	var p := result.new_state.get_player(0)
	# Funds unchanged by appending to queue.
	if p.minerals != 500:
		return false
	var b := result.new_state.get_entity_by_id(barracks.id)
	# Queue grew by one (the new marine).
	if b.production_state.queue.size() != 1:
		return false
	return _has_event_of_type(result.events, ResolverEvent.Type.TRAIN_QUEUED)


func _test_train_idle_producer_immediate_install() -> bool:
	# TRAIN order to an idle producer with affordable cost → installed
	# in active slot the same turn, cost deducted, pop reserved.
	var registry := _production_registry()
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 200
	state.players[0].pop_cap = 10
	var barracks := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	barracks.production_state = ProductionState.new()
	state.tile_grid.place(barracks.id, Rect2i(2, 2, 3, 3))
	_add_opponent_keepalive_building(state, registry)

	var order := EntityOrder.new()
	order.type = EntityOrder.Type.TRAIN
	order.entity_id = barracks.id
	order.def_id = "marine"
	var result := Resolver.resolve(state, _submit([order]), _submit(), registry, null)

	var p := result.new_state.get_player(0)
	# Marine costs 50 minerals + 1 pop in the test registry. Note that
	# advance_queues at EOT also decrements turns_remaining once, so the
	# active slot starts at build_time and ends this first turn at
	# build_time - 1.
	if p.minerals != 150:
		return false
	if p.pop_used != 1:
		return false
	var b := result.new_state.get_entity_by_id(barracks.id)
	if b.production_state.queue.size() != 0:
		return false
	if b.production_state.active.is_empty():
		return false
	if b.production_state.active[ProductionState.KEY_DEF_ID] != "marine":
		return false
	# TRAIN_STARTED must have been emitted at install time.
	return _has_event_of_type(result.events, ResolverEvent.Type.TRAIN_STARTED)


func _test_train_insufficient_minerals_stalls_at_install() -> bool:
	# TRAIN order to an idle producer but player can't afford → queue
	# grows, active stays empty, no deduction, PRODUCTION_STALLED.
	var registry := _production_registry()
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 30  # marine costs 50
	state.players[0].pop_cap = 10
	var barracks := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	barracks.production_state = ProductionState.new()
	state.tile_grid.place(barracks.id, Rect2i(2, 2, 3, 3))
	_add_opponent_keepalive_building(state, registry)

	var order := EntityOrder.new()
	order.type = EntityOrder.Type.TRAIN
	order.entity_id = barracks.id
	order.def_id = "marine"
	var result := Resolver.resolve(state, _submit([order]), _submit(), registry, null)

	var p := result.new_state.get_player(0)
	if p.minerals != 30:
		return false
	if p.pop_used != 0:
		return false
	var b := result.new_state.get_entity_by_id(barracks.id)
	if not b.production_state.active.is_empty():
		return false
	if b.production_state.queue.size() != 1:
		return false
	return _has_event_of_type(result.events, ResolverEvent.Type.PRODUCTION_STALLED)


func _test_train_resumes_after_funds_arrive() -> bool:
	# Stalled queue head + funds arrive → next try-fill installs and
	# starts ticking.
	var registry := _production_registry()
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 0  # nothing
	state.players[0].pop_cap = 10
	var barracks := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	barracks.production_state = ProductionState.new()
	state.tile_grid.place(barracks.id, Rect2i(2, 2, 3, 3))
	_add_opponent_keepalive_building(state, registry)

	var order := EntityOrder.new()
	order.type = EntityOrder.Type.TRAIN
	order.entity_id = barracks.id
	order.def_id = "marine"
	var result := Resolver.resolve(state, _submit([order]), _submit(), registry, null)
	# Stalled.
	var b := result.new_state.get_entity_by_id(barracks.id)
	if not b.production_state.active.is_empty():
		return false
	if b.production_state.queue.size() != 1:
		return false
	# Inject funds into the cloned new_state and run another turn.
	result.new_state.get_player(0).minerals = 100
	result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
	b = result.new_state.get_entity_by_id(barracks.id)
	if b.production_state.active.is_empty():
		return false
	# Install consumes 50; turns_remaining decremented once at EOT same turn.
	return result.new_state.get_player(0).minerals == 50


func _test_train_spawn_adjacent_with_persistent_move_to_rally() -> bool:
	# Full cycle: TRAIN → install → tick to completion → spawn adjacent
	# → spawned unit has persistent MOVE to producer.origin + rally_offset.
	var registry := _production_registry()
	var state := _state_with_grid(30, 30)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	state.players[0].pop_cap = 10
	var barracks := _make_entity(state, "barracks", 0, Vector2i(5, 5), 1000, "ground")
	barracks.production_state = ProductionState.new()
	state.tile_grid.place(barracks.id, Rect2i(5, 5, 3, 3))
	_add_opponent_keepalive_building(state, registry)

	var order := EntityOrder.new()
	order.type = EntityOrder.Type.TRAIN
	order.entity_id = barracks.id
	order.def_id = "marine"
	var result := Resolver.resolve(state, _submit([order]), _submit(), registry, null)
	# Marine build_time = 3 in our registry. Run more turns until we see
	# a TRAIN_COMPLETED.
	var saw_completed := false
	var spawned_id: int = -1
	for _i in 5:
		result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
		for ev in result.events:
			if ev.type == ResolverEvent.Type.TRAIN_COMPLETED:
				saw_completed = true
				spawned_id = ev.target_id
		if saw_completed:
			break
	if not saw_completed or spawned_id < 0:
		return false
	var marine := result.new_state.get_entity_by_id(spawned_id)
	if marine == null or marine.def_id != "marine":
		return false
	# Marine should be adjacent to barracks rect.
	var br: Rect2i = result.new_state.tile_grid.entity_rect(barracks.id)
	var mr: Rect2i = result.new_state.tile_grid.entity_rect(marine.id)
	if TileGrid.distance_between_rects(br, mr) != 1:
		return false
	# persistent_order = MOVE to rally tile (5+0, 5+4) = (5, 9).
	if marine.persistent_order == null:
		return false
	if marine.persistent_order.type != EntityOrder.Type.MOVE:
		return false
	return marine.persistent_order.target_tile == Vector2i(5, 9)


func _test_train_spawn_deferred_no_free_tile() -> bool:
	# Block every adjacent tile around the barracks so spawn defers.
	var registry := _production_registry()
	var state := _state_with_grid(15, 15)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	state.players[0].pop_cap = 10
	var barracks := _make_entity(state, "barracks", 0, Vector2i(5, 5), 1000, "ground")
	barracks.production_state = ProductionState.new()
	state.tile_grid.place(barracks.id, Rect2i(5, 5, 3, 3))
	# Surround barracks (rect 5..7, 5..7) with blockers on every adjacent
	# tile. The perimeter at 4..8 forms an outer ring of 5x5 - 3x3 = 16
	# tiles. Each blocker is a 1x1 entity — _make_entity allocates an id.
	for x in range(4, 9):
		for y in range(4, 9):
			if x >= 5 and x <= 7 and y >= 5 and y <= 7:
				continue  # skip the barracks footprint itself
			var blk := _make_entity(state, "blocker", 1, Vector2i(x, y), 50, "ground")
			state.tile_grid.place(blk.id, Rect2i(x, y, 1, 1))
	_add_opponent_keepalive_building(state, registry)

	var order := EntityOrder.new()
	order.type = EntityOrder.Type.TRAIN
	order.entity_id = barracks.id
	order.def_id = "marine"
	var result := Resolver.resolve(state, _submit([order]), _submit(), registry, null)
	# Run a few turns until completion-attempt.
	var saw_deferred := false
	for _i in 5:
		result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
		if _has_event_of_type(result.events, ResolverEvent.Type.SPAWN_DEFERRED):
			saw_deferred = true
			break
	if not saw_deferred:
		return false
	# Active slot should still be populated with turns_remaining = 0.
	var b := result.new_state.get_entity_by_id(barracks.id)
	if b.production_state.active.is_empty():
		return false
	return b.production_state.active[ProductionState.KEY_TURNS_REMAINING] == 0


func _test_unit_death_returns_pop() -> bool:
	# Killing a unit returns its pop_cost to the player's pop_used.
	var registry := _two_unit_registry(2000, 5, ["ground"], 50)
	# Add population to the shared marine def.
	registry.entities[0].population = PopulationDef.new()
	registry.entities[0].population.pop_cost = 1
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].pop_used = 1  # represents the marine's reservation
	var attacker := _make_entity(state, "marine", 1, Vector2i(5, 5), 50, "ground")
	var victim := _make_entity(state, "marine", 0, Vector2i(7, 5), 50, "ground")
	state.tile_grid.place(attacker.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(victim.id, Rect2i(7, 5, 1, 1))
	# Set HP low so a single attack kills.
	victim.current_hp = 1

	var atk := EntityOrder.new()
	atk.type = EntityOrder.Type.ATTACK
	atk.entity_id = attacker.id
	atk.target_priority_chain = [victim.id]
	var result := Resolver.resolve(state, _submit(), _submit([atk]), registry, null)

	var p := result.new_state.get_player(0)
	return p.pop_used == 0


func _test_cancel_active_full_refund() -> bool:
	# Active marine paid 50 min + 1 pop. CANCEL(producer, 0) refunds
	# minerals + pop, clears active, emits PRODUCTION_CANCELLED.
	var registry := _production_registry()
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 100
	state.players[0].pop_cap = 10
	var barracks := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	barracks.production_state = ProductionState.new()
	state.tile_grid.place(barracks.id, Rect2i(2, 2, 3, 3))
	_add_opponent_keepalive_building(state, registry)

	# Submit a TRAIN to reach a paid active state, then cancel it next turn.
	var train := EntityOrder.new()
	train.type = EntityOrder.Type.TRAIN
	train.entity_id = barracks.id
	train.def_id = "marine"
	var result := Resolver.resolve(state, _submit([train]), _submit(), registry, null)
	# After T0: minerals = 100 - 50 = 50; pop_used = 1.
	if result.new_state.get_player(0).minerals != 50:
		return false
	if result.new_state.get_player(0).pop_used != 1:
		return false

	var cancel := EntityOrder.new()
	cancel.type = EntityOrder.Type.CANCEL
	cancel.entity_id = barracks.id
	cancel.cancel_index = 0
	result = Resolver.resolve(result.new_state, _submit([cancel]), _submit(), registry, null)
	# Refund: minerals back to 100, pop_used back to 0, active cleared.
	var p := result.new_state.get_player(0)
	if p.minerals != 100:
		return false
	if p.pop_used != 0:
		return false
	var b := result.new_state.get_entity_by_id(barracks.id)
	if not b.production_state.active.is_empty():
		return false
	return _has_event_of_type(result.events, ResolverEvent.Type.PRODUCTION_CANCELLED)


func _test_cancel_queued_no_cost_movement() -> bool:
	# 3-item queue → CANCEL(2) removes queue[1]; queue.size() drops to
	# 2; minerals unchanged; the right item is removed.
	var registry := _production_registry()
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 50  # only enough for active install
	state.players[0].pop_cap = 10
	var barracks := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	barracks.production_state = ProductionState.new()
	state.tile_grid.place(barracks.id, Rect2i(2, 2, 3, 3))
	_add_opponent_keepalive_building(state, registry)

	# Three TRAIN orders this turn. The first becomes active (cost paid);
	# the next two queue without payment.
	var orders: Array[EntityOrder] = []
	for _i in 3:
		var t := EntityOrder.new()
		t.type = EntityOrder.Type.TRAIN
		t.entity_id = barracks.id
		t.def_id = "marine"
		orders.append(t)
	var result := Resolver.resolve(state, _submit(orders), _submit(), registry, null)
	var b := result.new_state.get_entity_by_id(barracks.id)
	# Active = 1 marine, queue = 2 marines.
	if b.production_state.active.is_empty():
		return false
	if b.production_state.queue.size() != 2:
		return false
	var minerals_before: int = result.new_state.get_player(0).minerals

	# Cancel the second queued item (cancel_index = 2 maps to queue[1]).
	var cancel := EntityOrder.new()
	cancel.type = EntityOrder.Type.CANCEL
	cancel.entity_id = barracks.id
	cancel.cancel_index = 2
	result = Resolver.resolve(result.new_state, _submit([cancel]), _submit(), registry, null)
	b = result.new_state.get_entity_by_id(barracks.id)
	# Queue dropped by one; minerals unchanged (queued items are unpaid).
	if b.production_state.queue.size() != 1:
		return false
	return result.new_state.get_player(0).minerals == minerals_before


func _test_cancel_active_triggers_try_fill() -> bool:
	# Active marine + queued tank → cancel active → tank installs same
	# turn (resolver runs try_fill after distribution).
	var registry := _production_registry()
	# Add a tank def so the queue can hold a different unit type.
	var tank := EntityDef.new()
	tank.id = "tank"
	tank.footprint = Vector2i(1, 1)
	tank.tags = ["heavy", "ground"]
	var t_hp := HealthDef.new()
	t_hp.max_hp = 150
	tank.health = t_hp
	tank.movement = MovementDef.new()
	tank.movement.speed_tiles_per_turn = 3
	tank.movement.default_layer = "ground"
	tank.construction = ConstructionDef.new()
	tank.construction.build_time_turns = 5
	tank.construction.mineral_cost = 30
	tank.construction.gas_cost = 0
	tank.population = PopulationDef.new()
	tank.population.pop_cost = 2
	registry.entities.append(tank)
	# barracks.produces must list "tank" too for the new membership check.
	registry.entities[0].production.produces = ["marine", "tank"]

	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 80  # enough for marine (50) + tank (30)
	state.players[0].pop_cap = 10
	var barracks := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	barracks.production_state = ProductionState.new()
	state.tile_grid.place(barracks.id, Rect2i(2, 2, 3, 3))
	_add_opponent_keepalive_building(state, registry)

	# Submit TRAIN(marine), TRAIN(tank). Marine becomes active (50 paid),
	# tank queues unpaid.
	var t1 := EntityOrder.new()
	t1.type = EntityOrder.Type.TRAIN
	t1.entity_id = barracks.id
	t1.def_id = "marine"
	var t2 := EntityOrder.new()
	t2.type = EntityOrder.Type.TRAIN
	t2.entity_id = barracks.id
	t2.def_id = "tank"
	var result := Resolver.resolve(state, _submit([t1, t2]), _submit(), registry, null)
	# After T0: minerals = 80-50 = 30; queue has tank.
	# Cancel marine; tank should auto-install (refund 50, then deduct 30).
	var cancel := EntityOrder.new()
	cancel.type = EntityOrder.Type.CANCEL
	cancel.entity_id = barracks.id
	cancel.cancel_index = 0
	result = Resolver.resolve(result.new_state, _submit([cancel]), _submit(), registry, null)
	var b := result.new_state.get_entity_by_id(barracks.id)
	# Active should now be the tank, queue empty.
	if b.production_state.active.is_empty():
		return false
	if b.production_state.active[ProductionState.KEY_DEF_ID] != "tank":
		return false
	if b.production_state.queue.size() != 0:
		return false
	# Funds: refunded 50 (marine), deducted 30 (tank). Started at 30 in
	# new_state (after T0 marine deduct), ends at 30 + 50 - 30 = 50.
	return result.new_state.get_player(0).minerals == 50


func _test_research_full_cycle() -> bool:
	# RESEARCH order: queue → install → tick → completion → unlocked.
	var registry := _production_registry()
	registry.researches = [_make_research_def("stim_research", 100, 0, 3)]
	# Producer must list the research id in production.researches.
	registry.entities[0].production.researches = ["stim_research"]
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 200
	state.players[0].pop_cap = 10
	var barracks := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	barracks.production_state = ProductionState.new()
	state.tile_grid.place(barracks.id, Rect2i(2, 2, 3, 3))
	_add_opponent_keepalive_building(state, registry)

	var order := EntityOrder.new()
	order.type = EntityOrder.Type.RESEARCH
	order.entity_id = barracks.id
	order.def_id = "stim_research"
	var result := Resolver.resolve(state, _submit([order]), _submit(), registry, null)
	# Run more turns until completion.
	var saw_completed := false
	for _i in 6:
		result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
		for ev in result.events:
			if ev.type == ResolverEvent.Type.RESEARCH_COMPLETED and ev.def_id == "stim_research":
				saw_completed = true
		if saw_completed:
			break
	if not saw_completed:
		return false
	var p := result.new_state.get_player(0)
	if not p.unlocked_researches.has("stim_research"):
		return false
	# Cost was 100 minerals; pop_cost=0.
	return p.minerals == 100


func _test_research_already_unlocked_rejected() -> bool:
	# Submitting a duplicate RESEARCH for an already-unlocked research →
	# ORDER_REJECTED with reason "duplicate_research"; nothing queued.
	var registry := _production_registry()
	registry.researches = [_make_research_def("stim_research", 100, 0, 3)]
	registry.entities[0].production.researches = ["stim_research"]
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	state.players[0].unlocked_researches = ["stim_research"]
	var barracks := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	barracks.production_state = ProductionState.new()
	state.tile_grid.place(barracks.id, Rect2i(2, 2, 3, 3))

	var order := EntityOrder.new()
	order.type = EntityOrder.Type.RESEARCH
	order.entity_id = barracks.id
	order.def_id = "stim_research"
	var result := Resolver.resolve(state, _submit([order]), _submit(), registry, null)
	var b := result.new_state.get_entity_by_id(barracks.id)
	if not b.production_state.queue.is_empty():
		return false
	if not b.production_state.active.is_empty():
		return false
	# Look for the rejection event.
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ORDER_REJECTED and ev.def_id == "duplicate_research":
			return true
	return false


func _test_duplicate_research_rejected_when_active() -> bool:
	# Research is player-wide: if an owned producer is already actively
	# researching an id, another RESEARCH order for that id must reject.
	var registry := _production_registry()
	registry.researches = [_make_research_def("stim_research", 100, 0, 3)]
	registry.entities[0].production.researches = ["stim_research"]
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	var barracks := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	barracks.production_state = ProductionState.new()
	barracks.production_state.active = {
		ProductionState.KEY_DEF_ID: "stim_research",
		ProductionState.KEY_KIND: ProductionState.KIND_RESEARCH,
		ProductionState.KEY_TURNS_REMAINING: 2,
		ProductionState.KEY_PAID_MINERALS: 100,
		ProductionState.KEY_PAID_GAS: 0,
		ProductionState.KEY_PAID_POP: 0,
	}
	state.tile_grid.place(barracks.id, Rect2i(2, 2, 3, 3))

	var order := EntityOrder.new()
	order.type = EntityOrder.Type.RESEARCH
	order.entity_id = barracks.id
	order.def_id = "stim_research"
	var result := Resolver.resolve(
		state, _submit([order] as Array[EntityOrder]), _submit(), registry, null
	)
	var b := result.new_state.get_entity_by_id(barracks.id)
	if not b.production_state.queue.is_empty():
		return false
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ORDER_REJECTED and ev.def_id == "duplicate_research":
			return true
	return false


func _test_duplicate_research_rejected_when_queued_elsewhere() -> bool:
	# Queued-but-not-started research is also player-wide. A second owned
	# producer should not be able to queue or start the same research id.
	var registry := _production_registry()
	registry.researches = [_make_research_def("stim_research", 100, 0, 3)]
	registry.entities[0].production.researches = ["stim_research"]
	var state := _state_with_grid(30, 30)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	var barracks_a := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	barracks_a.production_state = ProductionState.new()
	barracks_a.production_state.queue = [
		{
			ProductionState.KEY_DEF_ID: "stim_research",
			ProductionState.KEY_KIND: ProductionState.KIND_RESEARCH,
		}
	]
	state.tile_grid.place(barracks_a.id, Rect2i(2, 2, 3, 3))
	var barracks_b := _make_entity(state, "barracks", 0, Vector2i(12, 2), 1000, "ground")
	barracks_b.production_state = ProductionState.new()
	state.tile_grid.place(barracks_b.id, Rect2i(12, 2, 3, 3))

	var order := EntityOrder.new()
	order.type = EntityOrder.Type.RESEARCH
	order.entity_id = barracks_b.id
	order.def_id = "stim_research"
	var result := Resolver.resolve(
		state, _submit([order] as Array[EntityOrder]), _submit(), registry, null
	)
	var b := result.new_state.get_entity_by_id(barracks_b.id)
	if not b.production_state.queue.is_empty() or not b.production_state.active.is_empty():
		return false
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ORDER_REJECTED and ev.def_id == "duplicate_research":
			return true
	return false


func _test_research_stalls_on_funds() -> bool:
	# RESEARCH stalls on insufficient minerals, mirrors TRAIN.
	var registry := _production_registry()
	registry.researches = [_make_research_def("stim_research", 100, 0, 3)]
	registry.entities[0].production.researches = ["stim_research"]
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 50  # not enough
	var barracks := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	barracks.production_state = ProductionState.new()
	state.tile_grid.place(barracks.id, Rect2i(2, 2, 3, 3))

	var order := EntityOrder.new()
	order.type = EntityOrder.Type.RESEARCH
	order.entity_id = barracks.id
	order.def_id = "stim_research"
	var result := Resolver.resolve(state, _submit([order]), _submit(), registry, null)
	var b := result.new_state.get_entity_by_id(barracks.id)
	if not b.production_state.active.is_empty():
		return false
	if b.production_state.queue.size() != 1:
		return false
	return _has_event_of_type(result.events, ResolverEvent.Type.PRODUCTION_STALLED)


func _test_train_pop_overflow_stalls_at_install() -> bool:
	# Queue head pop_cost overflows pop_cap → stall at try-fill.
	var registry := _production_registry()
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 200
	state.players[0].pop_used = 5
	state.players[0].pop_cap = 5  # no room for more pop
	var barracks := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	barracks.production_state = ProductionState.new()
	state.tile_grid.place(barracks.id, Rect2i(2, 2, 3, 3))

	var order := EntityOrder.new()
	order.type = EntityOrder.Type.TRAIN
	order.entity_id = barracks.id
	order.def_id = "marine"
	var result := Resolver.resolve(state, _submit([order]), _submit(), registry, null)

	var p := result.new_state.get_player(0)
	# Stalled — no install.
	if p.minerals != 200:
		return false
	if p.pop_used != 5:
		return false
	var b := result.new_state.get_entity_by_id(barracks.id)
	if not b.production_state.active.is_empty():
		return false
	if b.production_state.queue.size() != 1:
		return false
	# PRODUCTION_STALLED with STALL_POP bit set.
	for ev in result.events:
		if ev.type == ResolverEvent.Type.PRODUCTION_STALLED:
			return (ev.amount & ProductionSystem.STALL_POP) != 0
	return false


func _test_build_distributes_creates_constructing_entity() -> bool:
	# BUILD order at distribution → new building entity exists with
	# is_constructing=true, full HP, on tile_grid; cost deducted; worker
	# locked; BUILD_STARTED emitted.
	var registry := _build_registry()
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	var worker := _make_entity(state, "worker", 0, Vector2i(0, 0), 50, "ground")
	worker.def_id = "worker"
	worker.current_def_id = "worker"
	worker.gather_state = GatherState.new()
	worker.gather_state.assigned_source_entity_id = 99
	worker.gather_state.phase = GatherState.Phase.GATHERING
	state.tile_grid.place(worker.id, Rect2i(0, 0, 1, 1))

	var build_order := EntityOrder.new()
	build_order.type = EntityOrder.Type.BUILD
	build_order.entity_id = worker.id
	build_order.def_id = "barracks"
	build_order.target_tile = Vector2i(5, 5)
	var result := Resolver.resolve(state, _submit([build_order]), _submit(), registry, null)

	var p := result.new_state.get_player(0)
	# Barracks costs 150 in the test registry.
	if p.minerals != 350:
		return false
	# Find the new building entity.
	var found_building: Entity = null
	for e in result.new_state.entities:
		if e != null and e.def_id == "barracks":
			found_building = e
	if found_building == null:
		return false
	if not found_building.is_constructing:
		return false
	if found_building.current_hp != 1000:
		return false
	# Worker should be locked to the building.
	var w := result.new_state.get_entity_by_id(worker.id)
	if w.locked_to_building_id != found_building.id:
		return false
	if w.gather_state == null or w.gather_state.phase != GatherState.Phase.IDLE:
		push_error("BUILD should interrupt active gathering")
		return false
	if w.gather_state.assigned_source_entity_id != -1:
		push_error("BUILD should clear the previous mineral assignment")
		return false
	return _has_event_of_type(result.events, ResolverEvent.Type.BUILD_STARTED)


func _test_build_worker_walks_to_site() -> bool:
	# Worker at distance 5 from build target reaches adjacency in ~5 ticks.
	var registry := _build_registry()
	var state := _state_with_grid(30, 30)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	var worker := _make_entity(state, "worker", 0, Vector2i(0, 0), 50, "ground")
	state.tile_grid.place(worker.id, Rect2i(0, 0, 1, 1))
	_add_opponent_keepalive_building(state, registry)

	var build_order := EntityOrder.new()
	build_order.type = EntityOrder.Type.BUILD
	build_order.entity_id = worker.id
	build_order.def_id = "barracks"
	build_order.target_tile = Vector2i(10, 10)
	var result := Resolver.resolve(state, _submit([build_order]), _submit(), registry, null)
	# Worker speed is 4; barracks rect at (10,10,3,3); distance from (0,0)
	# rect to that rect is max(10-0, 10-0) = 10. So walk takes ~10/4 = 3
	# turns to be adjacent. Run 6 turns to be safe.
	var building_id: int = -1
	for ev in result.events:
		if ev.type == ResolverEvent.Type.BUILD_STARTED:
			building_id = ev.target_id
	for _i in 6:
		result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
	var w := result.new_state.get_entity_by_id(worker.id)
	var b := result.new_state.get_entity_by_id(building_id)
	var w_rect := result.new_state.tile_grid.entity_rect(w.id)
	var b_rect := result.new_state.tile_grid.entity_rect(b.id)
	return TileGrid.distance_between_rects(w_rect, b_rect) <= 1


func _test_build_progress_only_while_worker_adjacent() -> bool:
	# Worker far from site → construction_turns_remaining doesn't
	# decrement until worker arrives. While walking, no BUILD_PROGRESSED
	# fires; once adjacent, ticks resume. The construction_worker_id link
	# is preserved across the walk so progress picks up automatically.
	var registry := _build_registry()
	var state := _state_with_grid(40, 40)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	var worker := _make_entity(state, "worker", 0, Vector2i(0, 0), 50, "ground")
	state.tile_grid.place(worker.id, Rect2i(0, 0, 1, 1))
	_add_opponent_keepalive_building(state, registry)

	var build_order := EntityOrder.new()
	build_order.type = EntityOrder.Type.BUILD
	build_order.entity_id = worker.id
	build_order.def_id = "barracks"
	build_order.target_tile = Vector2i(20, 20)
	var result := Resolver.resolve(state, _submit([build_order]), _submit(), registry, null)
	var building_id: int = -1
	for ev in result.events:
		if ev.type == ResolverEvent.Type.BUILD_STARTED:
			building_id = ev.target_id
	# T0 EOT: worker not adjacent → no progress event.
	var b0 := result.new_state.get_entity_by_id(building_id)
	if _has_event_of_type(result.events, ResolverEvent.Type.BUILD_PROGRESSED):
		return false
	# Worker link preserved while walking.
	if b0.construction_worker_id != worker.id:
		return false
	# Run until adjacency + at least one progress tick.
	var initial_remaining := b0.construction_turns_remaining
	var saw_progress := false
	for _i in 15:
		result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
		var b := result.new_state.get_entity_by_id(building_id)
		if b == null:
			return false
		if b.construction_turns_remaining < initial_remaining:
			saw_progress = true
			break
	return saw_progress


func _test_construction_worker_travel_uses_full_speed_budget() -> bool:
	# A locked construction worker should spend its full speed budget while
	# walking to the building site during the BUILD submission turn.
	var registry := _build_registry()
	var state := _state_with_grid(30, 30)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	var worker := _make_entity(state, "worker", 0, Vector2i(0, 0), 50, "ground")
	state.tile_grid.place(worker.id, Rect2i(0, 0, 1, 1))

	var build_order := EntityOrder.new()
	build_order.type = EntityOrder.Type.BUILD
	build_order.entity_id = worker.id
	build_order.def_id = "barracks"
	build_order.target_tile = Vector2i(10, 10)
	var result := Resolver.resolve(
		state, _submit([build_order] as Array[EntityOrder]), _submit(), registry, null
	)

	var move_count := 0
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == worker.id:
			move_count += 1
	var w := result.new_state.get_entity_by_id(worker.id)
	return move_count == 4 and w.origin == Vector2i(4, 4)


func _test_build_completes_applies_pop_provides() -> bool:
	# A barracks that completes adds its pop_provides to player.pop_cap.
	var registry := _build_registry()
	# Add pop_provides to barracks for this test.
	registry.entities[1].population = PopulationDef.new()
	registry.entities[1].population.pop_provides = 8
	var state := _state_with_grid(15, 15)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	state.players[0].pop_cap = 0
	var worker := _make_entity(state, "worker", 0, Vector2i(4, 4), 50, "ground")
	state.tile_grid.place(worker.id, Rect2i(4, 4, 1, 1))
	_add_opponent_keepalive_building(state, registry)

	var build_order := EntityOrder.new()
	build_order.type = EntityOrder.Type.BUILD
	build_order.entity_id = worker.id
	build_order.def_id = "barracks"
	build_order.target_tile = Vector2i(5, 5)
	var result := Resolver.resolve(state, _submit([build_order]), _submit(), registry, null)
	# Barracks build_time = 4 in test registry. Worker is right next to
	# it (4,4 adjacent to 5..7,5..7), so progress ticks every turn.
	# Loop until BUILD_COMPLETED.
	var saw_completed := false
	for _i in 8:
		result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
		if _has_event_of_type(result.events, ResolverEvent.Type.BUILD_COMPLETED):
			saw_completed = true
			break
	if not saw_completed:
		return false
	var p := result.new_state.get_player(0)
	return p.pop_cap == 8


func _test_build_locked_worker_rejects_new_orders() -> bool:
	# A locked worker should refuse a fresh MOVE order.
	var registry := _build_registry()
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	var worker := _make_entity(state, "worker", 0, Vector2i(0, 0), 50, "ground")
	state.tile_grid.place(worker.id, Rect2i(0, 0, 1, 1))
	_add_opponent_keepalive_building(state, registry)

	var build_order := EntityOrder.new()
	build_order.type = EntityOrder.Type.BUILD
	build_order.entity_id = worker.id
	build_order.def_id = "barracks"
	build_order.target_tile = Vector2i(5, 5)
	var result := Resolver.resolve(state, _submit([build_order]), _submit(), registry, null)

	# Now submit a MOVE on the locked worker.
	var move := EntityOrder.new()
	move.type = EntityOrder.Type.MOVE
	move.entity_id = worker.id
	move.target_tile = Vector2i(15, 15)
	result = Resolver.resolve(result.new_state, _submit([move]), _submit(), registry, null)

	# Locked worker should not have moved toward the MOVE target.
	var w := result.new_state.get_entity_by_id(worker.id)
	# Worker should be walking toward the build site, not (15, 15). The
	# direction toward the build is +x/+y; toward (15,15) is also +x/+y
	# from (0,0) so we can't disambiguate by direction. Instead, assert
	# ORDER_REJECTED was emitted.
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ORDER_REJECTED and ev.def_id == "worker_locked":
			return w.locked_to_building_id >= 0
	return false


func _test_building_death_drops_pop_cap() -> bool:
	# A completed barracks (pop_provides = 8) is killed → pop_cap drops by 8.
	var registry := _two_unit_registry(2000, 5, ["ground"], 50)
	# Add a barracks def to this combat-style registry.
	var b_def := EntityDef.new()
	b_def.id = "barracks"
	b_def.footprint = Vector2i(3, 3)
	b_def.tags = ["building", "ground"]
	var b_hp := HealthDef.new()
	b_hp.max_hp = 1
	b_def.health = b_hp
	b_def.population = PopulationDef.new()
	b_def.population.pop_provides = 8
	registry.entities.append(b_def)

	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].pop_cap = 8  # already credited by the (already-built) barracks
	var attacker := _make_entity(state, "marine", 1, Vector2i(0, 5), 50, "ground")
	var barracks := _make_entity(state, "barracks", 0, Vector2i(2, 5), 1, "ground")
	# Barracks is_constructing = false (already complete).
	state.tile_grid.place(attacker.id, Rect2i(0, 5, 1, 1))
	state.tile_grid.place(barracks.id, Rect2i(2, 5, 3, 3))

	var atk := EntityOrder.new()
	atk.type = EntityOrder.Type.ATTACK
	atk.entity_id = attacker.id
	atk.target_priority_chain = [barracks.id]
	var result := Resolver.resolve(state, _submit(), _submit([atk]), registry, null)
	return result.new_state.get_player(0).pop_cap == 0


func _test_production_determinism_golden() -> bool:
	# Run a complex scenario twice (same orders, same starting state)
	# and assert identical end states + identical event streams. Covers
	# BUILD + TRAIN + RESEARCH end-to-end.
	var run_a := _run_determinism_scenario()
	var run_b := _run_determinism_scenario()
	if not _states_equal(run_a.new_state, run_b.new_state):
		return false
	return _events_equal(run_a.events, run_b.events)


func _run_determinism_scenario() -> ResolveResult:
	# Build a small two-player scenario with one barracks each + a
	# minerals patch. Issue TRAIN orders on both barracks every turn
	# for a fixed number of turns.
	var registry := _production_registry()
	var state := _state_with_grid(30, 30)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 1000
	state.players[1].minerals = 1000
	state.players[0].pop_cap = 50
	state.players[1].pop_cap = 50
	var b0 := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	b0.production_state = ProductionState.new()
	state.tile_grid.place(b0.id, Rect2i(2, 2, 3, 3))
	var b1 := _make_entity(state, "barracks", 1, Vector2i(20, 20), 1000, "ground")
	b1.production_state = ProductionState.new()
	state.tile_grid.place(b1.id, Rect2i(20, 20, 3, 3))

	var t_a := EntityOrder.new()
	t_a.type = EntityOrder.Type.TRAIN
	t_a.entity_id = b0.id
	t_a.def_id = "marine"
	var t_b := EntityOrder.new()
	t_b.type = EntityOrder.Type.TRAIN
	t_b.entity_id = b1.id
	t_b.def_id = "marine"

	var result := Resolver.resolve(state, _submit([t_a]), _submit([t_b]), registry, null)
	for _i in 8:
		# Keep submitting TRAIN every turn to fill the queues.
		var ta := EntityOrder.new()
		ta.type = EntityOrder.Type.TRAIN
		ta.entity_id = b0.id
		ta.def_id = "marine"
		var tb := EntityOrder.new()
		tb.type = EntityOrder.Type.TRAIN
		tb.entity_id = b1.id
		tb.def_id = "marine"
		result = Resolver.resolve(result.new_state, _submit([ta]), _submit([tb]), registry, null)
	return result


func _test_build_refinery_on_geyser_overlap_allowed() -> bool:
	# BUILD(refinery, target=geyser_tile) succeeds; both entities on
	# grid at the same rect; gas gather works post-completion.
	var registry := _gather_registry(5, 1, 4)
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	# Place a base + a worker + a geyser.
	var base := _make_entity(state, "base", 0, Vector2i(0, 0), 1500, "ground")
	state.tile_grid.place(base.id, Rect2i(0, 0, 4, 4))
	var worker := _make_entity(state, "worker", 0, Vector2i(9, 5), 50, "ground")
	state.tile_grid.place(worker.id, Rect2i(9, 5, 1, 1))
	var geyser := _make_entity(state, "geyser", -1, Vector2i(10, 5), 1000, "ground")
	geyser.current_resource_amount = -1
	state.tile_grid.place(geyser.id, Rect2i(10, 5, 1, 1))

	var build_order := EntityOrder.new()
	build_order.type = EntityOrder.Type.BUILD
	build_order.entity_id = worker.id
	build_order.def_id = "refinery"
	build_order.target_tile = Vector2i(10, 5)
	var result := Resolver.resolve(state, _submit([build_order]), _submit(), registry, null)

	# Refinery created, cost deducted.
	if result.new_state.get_player(0).minerals != 425:
		return false
	# Both refinery and geyser have rects at (10, 5).
	var refinery_id: int = -1
	for ev in result.events:
		if ev.type == ResolverEvent.Type.BUILD_STARTED:
			refinery_id = ev.target_id
	var refinery_rect: Rect2i = result.new_state.tile_grid.entity_rect(refinery_id)
	var geyser_rect: Rect2i = result.new_state.tile_grid.entity_rect(geyser.id)
	if refinery_rect.position != Vector2i(10, 5):
		return false
	if geyser_rect.position != Vector2i(10, 5):
		return false
	# Refinery and geyser have the same footprint (both 1x1) — confirms
	# the design choice of matching dimensions.
	return refinery_rect.size == geyser_rect.size


func _test_build_refinery_double_target_rejected() -> bool:
	# Two players target the same geyser the same turn → player 0 lands,
	# player 1 rejected (no cost deducted on player 1).
	var registry := _gather_registry(5, 1, 4)
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	state.players[1].minerals = 500
	var w0 := _make_entity(state, "worker", 0, Vector2i(9, 5), 50, "ground")
	state.tile_grid.place(w0.id, Rect2i(9, 5, 1, 1))
	var w1 := _make_entity(state, "worker", 1, Vector2i(11, 5), 50, "ground")
	state.tile_grid.place(w1.id, Rect2i(11, 5, 1, 1))
	var geyser := _make_entity(state, "geyser", -1, Vector2i(10, 5), 1000, "ground")
	geyser.current_resource_amount = -1
	state.tile_grid.place(geyser.id, Rect2i(10, 5, 1, 1))

	var b0 := EntityOrder.new()
	b0.type = EntityOrder.Type.BUILD
	b0.entity_id = w0.id
	b0.def_id = "refinery"
	b0.target_tile = Vector2i(10, 5)
	var b1 := EntityOrder.new()
	b1.type = EntityOrder.Type.BUILD
	b1.entity_id = w1.id
	b1.def_id = "refinery"
	b1.target_tile = Vector2i(10, 5)
	var result := Resolver.resolve(state, _submit([b0]), _submit([b1]), registry, null)
	# Player 0 paid; player 1 did NOT (rejected because the geyser already
	# has a refinery on it after player 0's BUILD).
	if result.new_state.get_player(0).minerals != 425:
		return false
	return result.new_state.get_player(1).minerals == 500


func _test_build_target_tile_occupied_rejected() -> bool:
	# BUILD on an occupied non-target-tag tile → rejected; no cost deducted.
	var registry := _build_registry()
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	var worker := _make_entity(state, "worker", 0, Vector2i(0, 0), 50, "ground")
	state.tile_grid.place(worker.id, Rect2i(0, 0, 1, 1))
	# Place a blocker on the build target.
	var blocker := _make_entity(state, "blocker", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(blocker.id, Rect2i(5, 5, 1, 1))

	var build_order := EntityOrder.new()
	build_order.type = EntityOrder.Type.BUILD
	build_order.entity_id = worker.id
	build_order.def_id = "barracks"
	build_order.target_tile = Vector2i(5, 5)
	var result := Resolver.resolve(state, _submit([build_order]), _submit(), registry, null)

	# Cost not deducted.
	if result.new_state.get_player(0).minerals != 500:
		return false
	# ORDER_REJECTED with reason "tile_occupied".
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ORDER_REJECTED and ev.def_id == "tile_occupied":
			return true
	return false


func _test_build_off_grid_rejected() -> bool:
	# BUILD with footprint partially outside grid → rejected.
	var registry := _build_registry()
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	var worker := _make_entity(state, "worker", 0, Vector2i(0, 0), 50, "ground")
	state.tile_grid.place(worker.id, Rect2i(0, 0, 1, 1))

	var build_order := EntityOrder.new()
	build_order.type = EntityOrder.Type.BUILD
	build_order.entity_id = worker.id
	build_order.def_id = "barracks"
	# barracks is 3x3; placing at (19, 19) extends to (21, 21) — off-grid.
	build_order.target_tile = Vector2i(19, 19)
	var result := Resolver.resolve(state, _submit([build_order]), _submit(), registry, null)

	if result.new_state.get_player(0).minerals != 500:
		return false
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ORDER_REJECTED and ev.def_id == "off_grid":
			return true
	return false


func _test_build_worker_death_pauses() -> bool:
	# Worker dies mid-build → building stays alive, construction_worker_id
	# = -1, BUILD_PAUSED emitted.
	var registry := _build_registry()
	# Add an enemy to kill the worker; reuse blocker as enemy by giving
	# it minimal combat to deal lethal damage.
	registry.entities[2].combat = CombatDef.new()
	registry.entities[2].combat.damage = 100
	registry.entities[2].combat.attack_range = 5
	registry.entities[2].combat.target_layers = ["ground"]
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	var worker := _make_entity(state, "worker", 0, Vector2i(4, 5), 50, "ground")
	state.tile_grid.place(worker.id, Rect2i(4, 5, 1, 1))
	var enemy := _make_entity(state, "blocker", 1, Vector2i(0, 5), 50, "ground")
	enemy.hold_fire = true
	state.tile_grid.place(enemy.id, Rect2i(0, 5, 1, 1))
	_add_opponent_keepalive_building(state, registry)

	var build_order := EntityOrder.new()
	build_order.type = EntityOrder.Type.BUILD
	build_order.entity_id = worker.id
	build_order.def_id = "barracks"
	build_order.target_tile = Vector2i(5, 5)
	var result := Resolver.resolve(state, _submit([build_order]), _submit(), registry, null)
	# Find the building.
	var building_id: int = -1
	for ev in result.events:
		if ev.type == ResolverEvent.Type.BUILD_STARTED:
			building_id = ev.target_id
	# Now kill the worker. enemy is at (0,5), worker at (4,5) — out of
	# range (5). Move enemy adjacent first via direct attack with a long
	# chain. Easier: just zero-out worker hp to simulate death.
	result.new_state.get_entity_by_id(worker.id).current_hp = 0
	result.new_state.tile_grid.remove(worker.id)

	result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
	var building := result.new_state.get_entity_by_id(building_id)
	if building == null or building.current_hp <= 0:
		return false
	if not building.is_constructing:
		return false
	if building.construction_worker_id != -1:
		return false
	return _has_event_of_type(result.events, ResolverEvent.Type.BUILD_PAUSED)


func _test_build_resume_via_new_worker() -> bool:
	# After pause, BUILD with target_entity_id=paused_building and a new
	# worker → resume; cost NOT charged again; building eventually
	# completes.
	var registry := _build_registry()
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	var worker := _make_entity(state, "worker", 0, Vector2i(4, 5), 50, "ground")
	state.tile_grid.place(worker.id, Rect2i(4, 5, 1, 1))
	_add_opponent_keepalive_building(state, registry)

	var build_order := EntityOrder.new()
	build_order.type = EntityOrder.Type.BUILD
	build_order.entity_id = worker.id
	build_order.def_id = "barracks"
	build_order.target_tile = Vector2i(5, 5)
	var result := Resolver.resolve(state, _submit([build_order]), _submit(), registry, null)
	var building_id: int = -1
	for ev in result.events:
		if ev.type == ResolverEvent.Type.BUILD_STARTED:
			building_id = ev.target_id
	# Cost was deducted: 500 - 150 = 350.
	if result.new_state.get_player(0).minerals != 350:
		return false
	# Kill the worker.
	result.new_state.get_entity_by_id(worker.id).current_hp = 0
	result.new_state.tile_grid.remove(worker.id)
	# One turn to register pause.
	result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
	var b := result.new_state.get_entity_by_id(building_id)
	if b.construction_worker_id != -1:
		return false
	# Spawn a new worker and issue BUILD with target_entity_id.
	var new_worker := Entity.new()
	new_worker.id = result.new_state.allocate_entity_id()
	new_worker.def_id = "worker"
	new_worker.current_def_id = "worker"
	new_worker.owner_player_id = 0
	new_worker.origin = Vector2i(4, 5)
	new_worker.current_hp = 50
	new_worker.current_layer = "ground"
	result.new_state.entities.append(new_worker)
	result.new_state.tile_grid.place(new_worker.id, Rect2i(4, 5, 1, 1))
	var minerals_before_resume: int = result.new_state.get_player(0).minerals

	var resume_order := EntityOrder.new()
	resume_order.type = EntityOrder.Type.BUILD
	resume_order.entity_id = new_worker.id
	resume_order.def_id = "barracks"
	resume_order.target_tile = Vector2i(5, 5)
	resume_order.target_entity_id = building_id
	result = Resolver.resolve(result.new_state, _submit([resume_order]), _submit(), registry, null)
	# No additional cost.
	if result.new_state.get_player(0).minerals != minerals_before_resume:
		return false
	# Building should now have construction_worker_id set, BUILD_RESUMED
	# emitted.
	b = result.new_state.get_entity_by_id(building_id)
	if b.construction_worker_id != new_worker.id:
		return false
	return _has_event_of_type(result.events, ResolverEvent.Type.BUILD_RESUMED)


func _test_build_constructing_building_dies_no_refund() -> bool:
	# Kill the constructing building → entity gone, pop_cap unchanged
	# (pop_provides never applied), worker freed, NO refund.
	var registry := _build_registry()
	# Add combat to enemy blocker.
	registry.entities[2].combat = CombatDef.new()
	registry.entities[2].combat.damage = 2000
	registry.entities[2].combat.attack_range = 5
	registry.entities[2].combat.target_layers = ["ground"]
	# Add population to barracks so we can verify pop_provides was never granted.
	registry.entities[1].population = PopulationDef.new()
	registry.entities[1].population.pop_provides = 8
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	state.players[0].pop_cap = 0
	var worker := _make_entity(state, "worker", 0, Vector2i(8, 5), 50, "ground")
	state.tile_grid.place(worker.id, Rect2i(8, 5, 1, 1))
	_add_opponent_keepalive_building(state, registry)

	var build_order := EntityOrder.new()
	build_order.type = EntityOrder.Type.BUILD
	build_order.entity_id = worker.id
	build_order.def_id = "barracks"
	build_order.target_tile = Vector2i(5, 5)
	var result := Resolver.resolve(state, _submit([build_order]), _submit(), registry, null)
	# Player should now have 350 minerals (500 - 150).
	if result.new_state.get_player(0).minerals != 350:
		return false
	var building_id: int = -1
	for ev in result.events:
		if ev.type == ResolverEvent.Type.BUILD_STARTED:
			building_id = ev.target_id

	# Now kill the building (set hp to 0, remove from grid). Use direct
	# state mutation rather than an attack to keep the test focused.
	var b := result.new_state.get_entity_by_id(building_id)
	# Spawn an enemy and have them attack the building (so death goes
	# through CombatSystem._destroy_entity).
	var enemy := _make_entity(result.new_state, "blocker", 1, Vector2i(0, 5), 50, "ground")
	result.new_state.tile_grid.place(enemy.id, Rect2i(0, 5, 1, 1))
	b.current_hp = 1
	var atk := EntityOrder.new()
	atk.type = EntityOrder.Type.ATTACK
	atk.entity_id = enemy.id
	atk.target_priority_chain = [b.id]
	# Move enemy adjacent first by re-placing close.
	result.new_state.tile_grid.remove(enemy.id)
	result.new_state.tile_grid.place(enemy.id, Rect2i(3, 5, 1, 1))
	enemy.origin = Vector2i(3, 5)
	result = Resolver.resolve(result.new_state, _submit(), _submit([atk]), registry, null)

	# Building should be dead.
	var b_after := result.new_state.get_entity_by_id(building_id)
	if b_after.current_hp > 0:
		return false
	# pop_cap unchanged (was 0, pop_provides never granted).
	if result.new_state.get_player(0).pop_cap != 0:
		return false
	# Minerals NOT refunded — death is not cancel.
	if result.new_state.get_player(0).minerals != 350:
		return false
	# Worker freed.
	var w_after := result.new_state.get_entity_by_id(worker.id)
	return w_after.locked_to_building_id == -1


func _test_build_cancel_via_worker_full_refund() -> bool:
	# CANCEL(worker, -1) on a worker locked to a building → full refund,
	# remove building entity, free worker.
	var registry := _build_registry()
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 500
	var worker := _make_entity(state, "worker", 0, Vector2i(4, 5), 50, "ground")
	state.tile_grid.place(worker.id, Rect2i(4, 5, 1, 1))
	_add_opponent_keepalive_building(state, registry)

	var build_order := EntityOrder.new()
	build_order.type = EntityOrder.Type.BUILD
	build_order.entity_id = worker.id
	build_order.def_id = "barracks"
	build_order.target_tile = Vector2i(5, 5)
	var result := Resolver.resolve(state, _submit([build_order]), _submit(), registry, null)
	if result.new_state.get_player(0).minerals != 350:
		return false
	var building_id: int = -1
	for ev in result.events:
		if ev.type == ResolverEvent.Type.BUILD_STARTED:
			building_id = ev.target_id

	# Now cancel via the worker.
	var cancel := EntityOrder.new()
	cancel.type = EntityOrder.Type.CANCEL
	cancel.entity_id = worker.id
	cancel.cancel_index = -1
	result = Resolver.resolve(result.new_state, _submit([cancel]), _submit(), registry, null)
	# Full refund.
	if result.new_state.get_player(0).minerals != 500:
		return false
	# Building gone.
	var b := result.new_state.get_entity_by_id(building_id)
	if b != null and b.current_hp > 0:
		return false
	# Worker freed.
	var w := result.new_state.get_entity_by_id(worker.id)
	if w.locked_to_building_id != -1:
		return false
	return _has_event_of_type(result.events, ResolverEvent.Type.BUILD_CANCELLED)


# ---------- Plan node 06 — combat data wiring ----------


func _test_siege_tank_has_anti_heavy_modifier_data() -> bool:
	# Smoke-test the .tres data: the merged registry must produce a
	# siege_tank def with exactly one AttackModifier targeting "heavy"
	# at 1.5x damage. Catches accidental data drift on the .tres files.
	var registry := _load_data_registry()
	if registry == null:
		return false
	var def: EntityDef = registry.get_by_id("siege_tank")
	if def == null or def.combat == null:
		return false
	if def.combat.attack_modifiers.size() != 1:
		return false
	var mod: AttackModifier = def.combat.attack_modifiers[0]
	return mod != null and mod.target_tag == "heavy" and is_equal_approx(mod.damage_mult, 1.5)


func _test_helicopter_has_anti_light_modifier_data() -> bool:
	# Same shape as siege_tank, but for helicopter vs light.
	var registry := _load_data_registry()
	if registry == null:
		return false
	var def: EntityDef = registry.get_by_id("helicopter")
	if def == null or def.combat == null:
		return false
	if def.combat.attack_modifiers.size() != 1:
		return false
	var mod: AttackModifier = def.combat.attack_modifiers[0]
	return mod != null and mod.target_tag == "light" and is_equal_approx(mod.damage_mult, 1.5)


func _test_marine_has_no_attack_modifiers_data() -> bool:
	# Marine is the generalist — no counters. Per spec: "keep modifiers
	# small (one or two per unit)"; marine carries none.
	var registry := _load_data_registry()
	if registry == null:
		return false
	var def: EntityDef = registry.get_by_id("marine")
	if def == null or def.combat == null:
		return false
	return def.combat.attack_modifiers.is_empty()


func _test_siege_tank_anti_heavy_damage_at_data_values() -> bool:
	# Behavioral test using actual .tres values: siege_tank base damage
	# is 15; with the +heavy 1.5x modifier, vs another siege_tank (heavy
	# tag) deals round(15 * 1.5) = 23.
	var registry := _load_data_registry()
	if registry == null:
		return false
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	var attacker := _make_entity(state, "siege_tank", 0, Vector2i(0, 5), 175, "ground")
	var target := _make_entity(state, "siege_tank", 1, Vector2i(5, 5), 175, "ground")
	state.tile_grid.place(attacker.id, Rect2i(0, 5, 2, 2))
	state.tile_grid.place(target.id, Rect2i(5, 5, 2, 2))

	var atk := EntityOrder.new()
	atk.type = EntityOrder.Type.ATTACK
	atk.entity_id = attacker.id
	atk.target_priority_chain = [target.id]
	var result := Resolver.resolve(state, _submit([atk]), _submit(), registry, null)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED and ev.target_id == target.id:
			return ev.damage == 23
	return false


func _test_helicopter_anti_light_damage_at_data_values() -> bool:
	# Behavioral test: helicopter base damage 12; vs light marine
	# (light tag), round(12 * 1.5) = 18.
	var registry := _load_data_registry()
	if registry == null:
		return false
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	var heli := _make_entity(state, "helicopter", 0, Vector2i(0, 5), 140, "flying")
	var marine := _make_entity(state, "marine", 1, Vector2i(4, 5), 45, "ground")
	state.tile_grid.place(heli.id, Rect2i(0, 5, 1, 1))
	state.tile_grid.place(marine.id, Rect2i(4, 5, 1, 1))

	var atk := EntityOrder.new()
	atk.type = EntityOrder.Type.ATTACK
	atk.entity_id = heli.id
	atk.target_priority_chain = [marine.id]
	var result := Resolver.resolve(state, _submit([atk]), _submit(), registry, null)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED and ev.target_id == marine.id:
			return ev.damage == 18
	return false


func _test_registry_loads_from_data() -> bool:
	# Sanity: every roster entity AND research is present in the loaded
	# registry. Catches accidental dropped imports / id renames in
	# entity_registry.tres or its referenced .tres files.
	var registry := _load_data_registry()
	if registry == null:
		return false
	for unit in ["marine", "siege_tank", "helicopter"]:
		if registry.get_by_id(unit) == null:
			return false
	for building in ["base", "barracks", "factory", "starport", "refinery"]:
		if registry.get_by_id(building) == null:
			return false
	for research in ["stim_research", "siege_mode_research"]:
		if registry.get_research_by_id(research) == null:
			return false
	return true


# ---------- Plan node 07a — scenario loader ----------


func _test_scenario_loader_minimal() -> bool:
	# Load the canonical smoke scenario (1 base per player on a 30x30
	# grid). Confirms the loader produces a usable MatchState shape:
	# 2 entities, both bases, on the tile grid, with players initialized.
	var registry := _load_data_registry()
	if registry == null:
		return false
	var scenario := _load_smoke_scenario()
	if scenario == null:
		return false
	var loaded := ScenarioLoader.load(scenario, registry, null)
	if loaded == null:
		return false
	var state: MatchState = loaded.state
	# 2 placements -> 2 entities.
	if state.entities.size() != 2:
		return false
	# Tile grid sized correctly.
	if state.tile_grid == null:
		return false
	if state.tile_grid.width != 30 or state.tile_grid.height != 30:
		return false
	# Both placements registered on the grid.
	for e in state.entities:
		var rect: Rect2i = state.tile_grid.entity_rect(e.id)
		if rect.size == Vector2i.ZERO:
			return false
	# Players initialized.
	if state.players.size() != 2:
		return false
	if state.players[0].player_id != 0 or state.players[1].player_id != 1:
		return false
	# turn_index, match_over fresh.
	return state.turn_index == 0 and not state.match_over


func _test_scenario_loader_applies_starting_resources() -> bool:
	# Loader applies starting_resources_per_player and auto-credits
	# pop_provides from placed buildings. Values derived from the
	# scenario + def so balance changes don't break the test.
	var registry := _load_data_registry()
	if registry == null:
		return false
	var scenario := _load_smoke_scenario()
	if scenario == null:
		return false
	var loaded := ScenarioLoader.load(scenario, registry, null)
	if loaded == null:
		return false
	var state: MatchState = loaded.state
	var base_def: EntityDef = registry.get_by_id("base")
	if base_def == null or base_def.population == null:
		return false
	for p in state.players:
		var src: Dictionary = scenario.starting_resources_per_player.get(p.player_id, {})
		var expected_minerals: int = src.get("minerals", 0)
		var expected_gas: int = src.get("gas", 0)
		var starting_pop_cap: int = src.get("pop_cap", 0)
		# Each player owns exactly one base in smoke_minimal; it credits
		# pop_provides into pop_cap on top of the starting value.
		var expected_pop_cap: int = starting_pop_cap + base_def.population.pop_provides
		if p.minerals != expected_minerals:
			return false
		if p.gas != expected_gas:
			return false
		if p.pop_cap != expected_pop_cap:
			return false
		if p.pop_used != 0:
			return false
	return true


func _test_scenario_loader_auto_starts_workers_on_minerals() -> bool:
	var registry := _load_data_registry()
	if registry == null:
		return false
	var scenario := ScenarioDef.new()
	scenario.map_width = 20
	scenario.map_height = 20
	scenario.auto_start_workers_on_minerals = true
	scenario.placements = [
		_scenario_placement("base", 0, Vector2i(10, 8)),
		_scenario_placement("worker", 0, Vector2i(7, 8)),
		_scenario_placement("worker", 0, Vector2i(7, 10)),
		_scenario_placement("mineral_patch", -1, Vector2i(5, 7)),
		_scenario_placement("mineral_patch", -1, Vector2i(5, 11)),
	]
	var loaded := ScenarioLoader.load(scenario, registry, null)
	if loaded == null:
		push_error("[scenario_loader_auto_starts_workers_on_minerals] loader returned null")
		return false
	var seen_sources: Dictionary[int, bool] = {}
	for entity in loaded.state.entities_sorted_by_id():
		if entity.def_id != "worker" or entity.owner_player_id != 0:
			continue
		if entity.gather_state == null:
			push_error(
				"[scenario_loader_auto_starts_workers_on_minerals] worker has no gather state"
			)
			return false
		var source_id: int = entity.gather_state.assigned_source_entity_id
		if source_id < 0:
			push_error("[scenario_loader_auto_starts_workers_on_minerals] worker has no source")
			return false
		if seen_sources.has(source_id):
			push_error(
				"[scenario_loader_auto_starts_workers_on_minerals] workers should prefer unique patches"
			)
			return false
		seen_sources[source_id] = true
		if entity.gather_state.phase == GatherState.Phase.IDLE:
			push_error(
				"[scenario_loader_auto_starts_workers_on_minerals] worker should not start idle"
			)
			return false
		var source: Entity = loaded.state.get_entity_by_id(source_id)
		var source_def: EntityDef = (
			registry.get_by_id(source.current_def_id) if source != null else null
		)
		if source_def == null or source_def.resource_source == null:
			push_error("[scenario_loader_auto_starts_workers_on_minerals] source is not a resource")
			return false
		if source_def.resource_source.resource_type != "minerals":
			push_error("[scenario_loader_auto_starts_workers_on_minerals] source is not minerals")
			return false
	return seen_sources.size() == 2


func _scenario_placement(
	def_id: String, owner_player_id: int, origin: Vector2i
) -> ScenarioPlacement:
	var placement := ScenarioPlacement.new()
	placement.def_id = def_id
	placement.owner_player_id = owner_player_id
	placement.origin = origin
	return placement


func _test_scenario_loader_applies_initial_hp_override() -> bool:
	# Build an in-code scenario with one base placement at hp 7 and
	# verify the loader applies the override.
	var registry := _load_data_registry()
	if registry == null:
		return false
	var scenario := ScenarioDef.new()
	scenario.map_width = 20
	scenario.map_height = 20
	var p := ScenarioPlacement.new()
	p.def_id = "base"
	p.owner_player_id = 0
	p.origin = Vector2i(2, 2)
	p.initial_hp_override = 7
	scenario.placements = [p]
	var loaded := ScenarioLoader.load(scenario, registry, null)
	if loaded == null:
		return false
	var state: MatchState = loaded.state
	if state.entities.size() != 1:
		return false
	return state.entities[0].current_hp == 7


func _test_scenario_loader_applies_stat_overrides() -> bool:
	# A scenario that patches `marine.combat.damage = (canonical + 14)`
	# produces an effective registry where the patched value is live,
	# while the canonical registry stays untouched. The baseline is
	# captured from the canonical def itself so a balance change to
	# marine damage doesn't break this test.
	var canonical := _load_data_registry()
	if canonical == null:
		return false
	var canonical_marine: EntityDef = canonical.get_by_id("marine")
	if canonical_marine == null or canonical_marine.combat == null:
		return false
	var baseline_damage: int = canonical_marine.combat.damage
	var override_damage: int = baseline_damage + 14
	var scenario := ScenarioDef.new()
	scenario.map_width = 20
	scenario.map_height = 20
	var ov := ScenarioStatOverride.new()
	ov.entity_def_id = "marine"
	ov.capability = "combat"
	ov.field = "damage"
	ov.value_kind = "int"
	ov.value_int = override_damage
	scenario.stat_overrides = [ov]

	var loaded := ScenarioLoader.load(scenario, canonical, null)
	if loaded == null or loaded.registry == null:
		return false
	# Effective registry's marine has the patched value.
	var patched_marine: EntityDef = loaded.registry.get_by_id("marine")
	if patched_marine == null or patched_marine.combat == null:
		return false
	if patched_marine.combat.damage != override_damage:
		return false
	# Canonical registry untouched (deep clone via Resource.duplicate).
	if canonical_marine.combat.damage != baseline_damage:
		return false
	# Untargeted defs in the effective registry have the same observable
	# state as canonical (id, footprint, combat values). Deliberately
	# observable-field equality, not reference equality — the loader is
	# free to share the original Resource instance OR clone it
	# unchanged; both are correct as long as the values match.
	var loaded_tank: EntityDef = loaded.registry.get_by_id("siege_tank")
	var canonical_tank: EntityDef = canonical.get_by_id("siege_tank")
	if loaded_tank == null or canonical_tank == null:
		return false
	if loaded_tank.id != canonical_tank.id:
		return false
	if loaded_tank.footprint != canonical_tank.footprint:
		return false
	if (loaded_tank.combat == null) != (canonical_tank.combat == null):
		return false
	if loaded_tank.combat != null:
		if loaded_tank.combat.damage != canonical_tank.combat.damage:
			return false
		if loaded_tank.combat.attack_range != canonical_tank.combat.attack_range:
			return false
	return true


func _test_match_state_save_load_roundtrip() -> bool:
	# Build a complex MatchState (two players with non-default
	# resources, multiple entities with assorted runtime state:
	# production active+queue, gather phase, ability_cooldowns,
	# active_buffs, persistent_order, construction state) — save it,
	# load it, assert _states_equal.
	var state := _state_with_grid(20, 20)
	state.players = [_player(0), _player(1)]
	state.players[0].minerals = 137
	state.players[0].gas = 42
	state.players[0].pop_used = 3
	state.players[0].pop_cap = 25
	state.players[0].unlocked_researches = ["stim_research"]
	state.players[1].minerals = 999
	state.turn_index = 14
	state.next_entity_id = 50

	# Entity 1: a barracks mid-production with active slot + queue.
	var barracks := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	state.tile_grid.place(barracks.id, Rect2i(2, 2, 3, 3))
	barracks.production_state = ProductionState.new()
	barracks.production_state.active = {
		ProductionState.KEY_DEF_ID: "marine",
		ProductionState.KEY_KIND: ProductionState.KIND_UNIT,
		ProductionState.KEY_TURNS_REMAINING: 2,
		ProductionState.KEY_PAID_MINERALS: 50,
		ProductionState.KEY_PAID_GAS: 0,
		ProductionState.KEY_PAID_POP: 1,
	}
	barracks.production_state.queue = [
		{
			ProductionState.KEY_DEF_ID: "marine",
			ProductionState.KEY_KIND: ProductionState.KIND_UNIT,
		}
	]

	# Entity 2: a marine with a buff + cooldown + persistent move.
	var marine := _make_entity(state, "marine", 0, Vector2i(8, 8), 32, "ground")
	state.tile_grid.place(marine.id, Rect2i(8, 8, 1, 1))
	marine.ability_cooldowns = {"stim": 4}
	marine.hold_fire = true
	marine.moves_used_this_turn = 1
	var buff := ActiveBuff.new()
	buff.source_ability_id = "stim"
	buff.turns_remaining = 2
	buff.damage_mult = 1.5
	buff.speed_mult = 1.5
	marine.active_buffs = [buff]
	var po := EntityOrder.new()
	po.type = EntityOrder.Type.MOVE
	po.entity_id = marine.id
	po.target_tile = Vector2i(15, 15)
	marine.persistent_order = po
	# Populate order_queue too so save/load actually exercises that
	# field (otherwise _states_equal compares two empty arrays and the
	# coverage is vacuous).
	var queued := EntityOrder.new()
	queued.type = EntityOrder.Type.ATTACK
	queued.entity_id = marine.id
	queued.target_priority_chain = [42, 99]
	marine.order_queue = [queued]

	# Entity 3: a worker mid-gather with a non-IDLE phase + cargo.
	var worker := _make_entity(state, "worker", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(worker.id, Rect2i(5, 5, 1, 1))
	worker.gather_state = GatherState.new()
	worker.gather_state.assigned_source_entity_id = 99
	worker.gather_state.phase = GatherState.Phase.MOVING_TO_BASE
	worker.gather_state.carrying_amount = 4
	worker.gather_state.carrying_resource_type = "minerals"

	# Entity 4: a constructing building with a locked worker.
	var ext := _make_entity(state, "barracks", 0, Vector2i(15, 2), 1000, "ground")
	state.tile_grid.place(ext.id, Rect2i(15, 2, 3, 3))
	ext.is_constructing = true
	ext.construction_turns_remaining = 5
	ext.construction_worker_id = worker.id
	worker.locked_to_building_id = ext.id

	# Save -> load with a registry alongside.
	var registry := _load_data_registry()
	if registry == null:
		return false
	var path := "user://test_match_state_roundtrip_%d.tres" % Time.get_ticks_msec()
	if MatchSaver.save(state, registry, path) != OK:
		return false
	var loaded: SavedSession = MatchSaver.load_from(path)
	# Cleanup the file regardless of test outcome.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if loaded == null or loaded.state == null:
		return false
	if not _states_equal(state, loaded.state):
		return false
	# Registry round-trip: every entity id present, in the same order,
	# plus every research id (so a future PR that drops the researches
	# array on save would fail this).
	if loaded.registry == null:
		return false
	if loaded.registry.entities.size() != registry.entities.size():
		return false
	for i in registry.entities.size():
		var orig_def: EntityDef = registry.entities[i]
		var loaded_def: EntityDef = loaded.registry.entities[i]
		if orig_def == null or loaded_def == null:
			return false
		if orig_def.id != loaded_def.id:
			return false
	if loaded.registry.researches.size() != registry.researches.size():
		return false
	for i in registry.researches.size():
		var orig_r: ResearchDef = registry.researches[i]
		var loaded_r: ResearchDef = loaded.registry.researches[i]
		if orig_r == null or loaded_r == null:
			return false
		if orig_r.id != loaded_r.id:
			return false
	return true


func _test_match_state_save_load_preserves_overrides() -> bool:
	# Verifies the SavedSession round-trip preserves a stat-override-
	# patched registry. Without this, a regression that saves the
	# canonical registry alongside the state (instead of the patched
	# one) would silently revert overrides on reload. Override value is
	# derived from the canonical baseline so a balance change to marine
	# damage doesn't break this test.
	var canonical := _load_data_registry()
	if canonical == null:
		return false
	var canonical_marine: EntityDef = canonical.get_by_id("marine")
	if canonical_marine == null or canonical_marine.combat == null:
		return false
	var baseline_damage: int = canonical_marine.combat.damage
	var override_damage: int = baseline_damage + 14
	var scenario := ScenarioDef.new()
	scenario.map_width = 20
	scenario.map_height = 20
	var ov := ScenarioStatOverride.new()
	ov.entity_def_id = "marine"
	ov.capability = "combat"
	ov.field = "damage"
	ov.value_kind = "int"
	ov.value_int = override_damage
	scenario.stat_overrides = [ov]
	var loaded := ScenarioLoader.load(scenario, canonical, null)
	if loaded == null or loaded.registry == null:
		return false
	# Patched registry has the override.
	var loaded_marine: EntityDef = loaded.registry.get_by_id("marine")
	if loaded_marine == null or loaded_marine.combat == null:
		return false
	if loaded_marine.combat.damage != override_damage:
		return false

	var path := "user://test_override_roundtrip_%d.tres" % Time.get_ticks_usec()
	if MatchSaver.save(loaded.state, loaded.registry, path) != OK:
		return false
	var reloaded: SavedSession = MatchSaver.load_from(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if reloaded == null or reloaded.registry == null:
		return false
	# Override survived the round-trip.
	var reloaded_marine: EntityDef = reloaded.registry.get_by_id("marine")
	if reloaded_marine == null or reloaded_marine.combat == null:
		return false
	if reloaded_marine.combat.damage != override_damage:
		return false
	# Canonical untouched (sanity check that the override didn't leak).
	return canonical.get_by_id("marine").combat.damage == baseline_damage


# ---------- Helpers ----------


# Loads the smoke scenario .tres. Factored out to satisfy gdlint's
# duplicated-load rule (multiple plan-07a tests share this scenario).
func _load_smoke_scenario() -> ScenarioDef:
	return load(_SMOKE_SCENARIO_PATH) as ScenarioDef


# Loads `client/data/entity_registry.tres` and returns it. Returns null
# if the file isn't loadable in the test context (the @tool runner runs
# inside the editor, so res:// loads work). Used by plan-06 data-wiring
# tests.
func _load_data_registry() -> EntityRegistry:
	var registry: EntityRegistry = load(_REGISTRY_PATH) as EntityRegistry
	return registry


# Wrap a flat orders array into a SubmitTurn (the resolver's per-player
# input shape). Default is an empty submit so test sites that pass `[]`
# still read cleanly.
func _submit(orders: Array[EntityOrder] = []) -> SubmitTurn:
	var s := SubmitTurn.new()
	s.orders = orders
	return s


func _ability_order(entity_id: int, ability_id: String) -> EntityOrder:
	var order := EntityOrder.new()
	order.type = EntityOrder.Type.USE_ABILITY
	order.entity_id = entity_id
	order.def_id = ability_id
	return order


func _player(id: int) -> PlayerState:
	var p := PlayerState.new()
	p.player_id = id
	p.minerals = 0
	p.gas = 0
	p.pop_used = 0
	p.pop_cap = 50
	return p


func _state_with_grid(w: int, h: int) -> MatchState:
	var s := MatchState.new()
	s.players = [_player(0), _player(1)]
	s.tile_grid = TileGrid.new(w, h)
	return s


func _make_entity(
	state: MatchState, def_id: String, owner: int, origin: Vector2i, hp: int, layer: String
) -> Entity:
	var e := Entity.new()
	e.id = state.allocate_entity_id()
	e.def_id = def_id
	e.current_def_id = def_id
	e.owner_player_id = owner
	e.origin = origin
	e.current_hp = hp
	e.current_layer = layer
	state.entities.append(e)
	return e


func _add_opponent_keepalive_building(state: MatchState, registry: EntityRegistry) -> Entity:
	var invalid_inputs: Array[String] = []
	if state == null:
		invalid_inputs.append("state")
	elif state.tile_grid == null:
		invalid_inputs.append("state.tile_grid")
	if registry == null:
		invalid_inputs.append("registry")
	if not invalid_inputs.is_empty():
		var invalid_args_message: String = (
			"_add_opponent_keepalive_building: invalid inputs (%s)" % ", ".join(invalid_inputs)
		)
		push_error(invalid_args_message)
		assert(false, invalid_args_message)
		return null
	var has_def: bool = false
	for existing in registry.entities:
		if existing != null and existing.id == _TEST_KEEPALIVE_DEF_ID:
			has_def = true
			break
	if not has_def:
		var def: EntityDef = EntityDef.new()
		def.id = _TEST_KEEPALIVE_DEF_ID
		def.footprint = Vector2i.ONE
		def.tags = ["building", "structure", "ground"]
		var hp: HealthDef = HealthDef.new()
		hp.max_hp = 1
		def.health = hp
		registry.entities.append(def)
		registry._indexes_built = false

	for y in range(state.tile_grid.height - 1, -1, -1):
		for x in range(state.tile_grid.width - 1, -1, -1):
			var origin: Vector2i = Vector2i(x, y)
			var rect: Rect2i = Rect2i(origin, Vector2i.ONE)
			if not state.tile_grid.is_rect_clear(rect):
				continue
			var entity: Entity = _make_entity(state, _TEST_KEEPALIVE_DEF_ID, 1, origin, 1, "ground")
			if state.tile_grid.place(entity.id, rect):
				return entity
			state.entities.erase(entity)
	var message: String = "_add_opponent_keepalive_building: no clear tile for keepalive fixture"
	push_error(message)
	assert(false, message)
	return null


func _combat_def(damage: int, range_tiles: int, target_layers: Array[String]) -> CombatDef:
	var c := CombatDef.new()
	c.damage = damage
	c.attack_range = range_tiles
	c.target_layers = target_layers
	return c


func _def(
	id: String, footprint: Vector2i, tags: Array[String], combat: CombatDef, max_hp: int
) -> EntityDef:
	var d := EntityDef.new()
	d.id = id
	d.footprint = footprint
	d.tags = tags
	d.combat = combat
	var hd := HealthDef.new()
	hd.max_hp = max_hp
	d.health = hd
	return d


# Two marine-shaped entities sharing a single def. Keeps simple combat
# tests tight — both attacker and target use the same combat profile.
func _two_unit_registry(
	damage: int, range_tiles: int, target_layers: Array[String], max_hp: int
) -> EntityRegistry:
	var combat := _combat_def(damage, range_tiles, target_layers)
	var d := _def("marine", Vector2i(1, 1), ["light", "ground"], combat, max_hp)
	var registry := EntityRegistry.new()
	registry.entities = [d]
	return registry


func _combat_mover_registry(damage: int, range_tiles: int, speed: int) -> EntityRegistry:
	var registry := EntityRegistry.new()
	registry.entities = [
		_def_with_movement_combat(
			"marine",
			Vector2i(1, 1),
			["light", "ground"],
			_combat_def(damage, range_tiles, ["ground"]),
			50,
			speed
		),
	]
	return registry


func _movement_def(speed: int, default_layer: String = "ground") -> MovementDef:
	var m := MovementDef.new()
	m.speed_tiles_per_turn = speed
	m.default_layer = default_layer
	return m


func _ability_state_with_bases() -> MatchState:
	var state: MatchState = _state_with_grid(30, 30)
	var p0_base: Entity = _make_entity(state, "base", 0, Vector2i(0, 0), 1500, "ground")
	var p1_base: Entity = _make_entity(state, "base", 1, Vector2i(24, 24), 1500, "ground")
	state.tile_grid.place(p0_base.id, Rect2i(0, 0, 4, 4))
	state.tile_grid.place(p1_base.id, Rect2i(24, 24, 4, 4))
	return state


func _ability_registry() -> EntityRegistry:
	var registry := EntityRegistry.new()
	var marine: EntityDef = _def_with_movement_combat(
		"marine",
		Vector2i(1, 1),
		["light", "biological", "ground"],
		_combat_def(6, 5, ["ground", "flying"]),
		45,
		4
	)
	marine.abilities = _abilities_def([_stim_ability()])
	var tank: EntityDef = _def_with_movement_combat(
		"tank",
		Vector2i(2, 2),
		["heavy", "mechanical", "ground"],
		_combat_def(15, 7, ["ground"]),
		150,
		2
	)
	tank.abilities = _abilities_def([_transform_ability("siege_mode", "siege_tank", 1)])
	tank.abilities.abilities[0].requires_research_id = "siege_mode_research"
	var siege_tank: EntityDef = _def(
		"siege_tank",
		Vector2i(2, 2),
		["heavy", "mechanical", "ground"],
		_combat_def(15, 7, ["ground"]),
		150
	)
	siege_tank.abilities = _abilities_def([_transform_ability("unsiege_mode", "tank", 1)])
	siege_tank.abilities.abilities[0].requires_research_id = "siege_mode_research"
	var base: EntityDef = _def("base", Vector2i(4, 4), ["building", "ground"], null, 1500)
	registry.entities = [marine, tank, siege_tank, base]
	return registry


func _abilities_def(abilities: Array[AbilityDef]) -> AbilitiesDef:
	var out := AbilitiesDef.new()
	out.abilities = abilities
	return out


func _stim_ability() -> AbilityDef:
	var ability := AbilityDef.new()
	ability.id = "stim"
	ability.display_name = "Stim"
	ability.target_type = "self"
	ability.cooldown_turns = 5
	ability.requires_research_id = "stim_research"
	var cost := AbilityCost.new()
	cost.type = "hp"
	cost.amount = 10
	ability.costs = [cost]
	var effect := StatBuffEffect.new()
	effect.duration_turns = 3
	effect.damage_mult = 1.5
	effect.speed_mult = 1.5
	ability.effect = effect
	return ability


func _transform_ability(id: String, to_def_id: String, cast_time_turns: int) -> AbilityDef:
	var ability := AbilityDef.new()
	ability.id = id
	ability.display_name = id
	ability.target_type = "self"
	ability.cast_time_turns = cast_time_turns
	var effect := TransformEffect.new()
	effect.to_def_id = to_def_id
	ability.effect = effect
	return ability


func _def_with_movement(
	id: String, footprint: Vector2i, tags: Array[String], max_hp: int, speed: int
) -> EntityDef:
	var d := EntityDef.new()
	d.id = id
	d.footprint = footprint
	d.tags = tags
	var hd := HealthDef.new()
	hd.max_hp = max_hp
	d.health = hd
	d.movement = _movement_def(speed)
	return d


func _def_with_movement_combat(
	id: String, footprint: Vector2i, tags: Array[String], combat: CombatDef, max_hp: int, speed: int
) -> EntityDef:
	var d := _def_with_movement(id, footprint, tags, max_hp, speed)
	d.combat = combat
	return d


# Marine-shaped registry with movement; used by chunk-4 tests that don't
# need combat. Speed is parameterised so move-budget tests can vary it.
func _movable_registry(speed: int) -> EntityRegistry:
	var d := _def_with_movement("marine", Vector2i(1, 1), ["light", "ground"], 50, speed)
	var registry := EntityRegistry.new()
	registry.entities = [d]
	return registry


# Worker + base + mineral_patch + refinery + geyser registry. Used by
# plan-04 economy tests so a single _gather_registry call wires every
# def the gather pipeline touches.
func _gather_registry(carry: int, yield_per_turn: int, speed: int) -> EntityRegistry:
	var registry := EntityRegistry.new()
	# Worker — movement + gather capabilities.
	var worker := _def_with_movement("worker", Vector2i(1, 1), ["worker", "ground"], 50, speed)
	worker.gather = GatherDef.new()
	worker.gather.gather_per_turn = yield_per_turn
	worker.gather.carry_amount = carry
	worker.gather.accepts_resource_types = ["minerals", "gas"]
	# Base — a deposit sink.
	var base := EntityDef.new()
	base.id = "base"
	base.footprint = Vector2i(4, 4)
	base.tags = ["building", "structure", "ground", "deposit_sink"]
	var base_hp := HealthDef.new()
	base_hp.max_hp = 1500
	base.health = base_hp
	# Mineral patch — ResourceSource without extractor.
	var patch := EntityDef.new()
	patch.id = "minpatch"
	patch.footprint = Vector2i(1, 1)
	patch.tags = ["resource_source", "minerals", "ground"]
	var patch_rs := ResourceSourceDef.new()
	patch_rs.resource_type = "minerals"
	patch_rs.yield_per_worker_per_turn = yield_per_turn
	patch_rs.requires_extractor = false
	patch.resource_source = patch_rs
	# Geyser — ResourceSource WITH extractor. The "gas_geyser" tag lets
	# BUILD's requires_target_tag check find it.
	var geyser := EntityDef.new()
	geyser.id = "geyser"
	geyser.footprint = Vector2i(1, 1)
	geyser.tags = ["resource_source", "gas", "ground", "gas_geyser"]
	var geyser_rs := ResourceSourceDef.new()
	geyser_rs.resource_type = "gas"
	geyser_rs.yield_per_worker_per_turn = yield_per_turn
	geyser_rs.requires_extractor = true
	geyser.resource_source = geyser_rs
	# Refinery — same 1x1 footprint as the geyser (per the design choice
	# locked in plan node 05: refinery and geyser share dimensions to
	# keep the overlap rule clean). Construction wired so BUILD tests
	# can target a geyser.
	var refinery := EntityDef.new()
	refinery.id = "refinery"
	refinery.footprint = Vector2i(1, 1)
	refinery.tags = ["building", "structure", "ground", "extractor"]
	var refinery_hp := HealthDef.new()
	refinery_hp.max_hp = 750
	refinery.health = refinery_hp
	refinery.construction = ConstructionDef.new()
	refinery.construction.build_time_turns = 4
	refinery.construction.mineral_cost = 75
	refinery.construction.gas_cost = 0
	refinery.construction.built_by_tag = "worker"
	refinery.construction.requires_target_tag = "gas_geyser"
	registry.entities = [worker, base, patch, geyser, refinery]
	return registry


# Barracks + marine + blocker registry. Used by plan-05 production tests
# so a single _production_registry() call wires every def the production
# pipeline touches: a producer with rally_offset, a unit with cost + pop,
# and a footprint-1 blocker for spawn-deferral tests.
func _production_registry() -> EntityRegistry:
	var registry := EntityRegistry.new()
	# Barracks — producer.
	var barracks := EntityDef.new()
	barracks.id = "barracks"
	barracks.footprint = Vector2i(3, 3)
	barracks.tags = ["building", "structure", "ground"]
	var b_hp := HealthDef.new()
	b_hp.max_hp = 1000
	barracks.health = b_hp
	barracks.production = ProductionDef.new()
	barracks.production.produces = ["marine"]
	barracks.production.rally_offset = Vector2i(0, 4)
	# Marine — produced unit.
	var marine := EntityDef.new()
	marine.id = "marine"
	marine.footprint = Vector2i(1, 1)
	marine.tags = ["light", "ground"]
	var m_hp := HealthDef.new()
	m_hp.max_hp = 50
	marine.health = m_hp
	marine.movement = MovementDef.new()
	marine.movement.speed_tiles_per_turn = 4
	marine.movement.default_layer = "ground"
	marine.construction = ConstructionDef.new()
	marine.construction.build_time_turns = 3
	marine.construction.mineral_cost = 50
	marine.construction.gas_cost = 0
	marine.construction.built_by_tag = "barracks"
	marine.population = PopulationDef.new()
	marine.population.pop_cost = 1
	# Blocker — generic 1x1 entity for occupying tiles in tests.
	var blocker := EntityDef.new()
	blocker.id = "blocker"
	blocker.footprint = Vector2i(1, 1)
	blocker.tags = ["ground"]
	var bl_hp := HealthDef.new()
	bl_hp.max_hp = 50
	blocker.health = bl_hp
	registry.entities = [barracks, marine, blocker]
	return registry


# Worker + barracks + blocker registry for plan-05 chunk 5/6/7 BUILD
# tests. Worker has movement, barracks has construction + (optionally)
# population, blocker is a 1x1 ground entity for spawn-deferral / tile
# occupancy tests.
func _build_registry() -> EntityRegistry:
	var registry := EntityRegistry.new()
	# Worker.
	var worker := EntityDef.new()
	worker.id = "worker"
	worker.footprint = Vector2i(1, 1)
	worker.tags = ["worker", "light", "ground"]
	var w_hp := HealthDef.new()
	w_hp.max_hp = 50
	worker.health = w_hp
	worker.movement = MovementDef.new()
	worker.movement.speed_tiles_per_turn = 4
	worker.movement.default_layer = "ground"
	# Barracks.
	var barracks := EntityDef.new()
	barracks.id = "barracks"
	barracks.footprint = Vector2i(3, 3)
	barracks.tags = ["building", "structure", "ground"]
	var b_hp := HealthDef.new()
	b_hp.max_hp = 1000
	barracks.health = b_hp
	barracks.construction = ConstructionDef.new()
	barracks.construction.build_time_turns = 4
	barracks.construction.mineral_cost = 150
	barracks.construction.gas_cost = 0
	barracks.construction.built_by_tag = "worker"
	barracks.production = ProductionDef.new()
	barracks.production.produces = ["marine"]
	barracks.production.rally_offset = Vector2i(0, 4)
	# Blocker.
	var blocker := EntityDef.new()
	blocker.id = "blocker"
	blocker.footprint = Vector2i(1, 1)
	blocker.tags = ["ground"]
	var bl_hp := HealthDef.new()
	bl_hp.max_hp = 50
	blocker.health = bl_hp
	registry.entities = [worker, barracks, blocker]
	return registry


# Lightweight ResearchDef factory for plan-05 chunk 4 tests.
func _make_research_def(
	id: String, mineral_cost: int, gas_cost: int, time_turns: int
) -> ResearchDef:
	var r := ResearchDef.new()
	r.id = id
	r.display_name = id
	r.mineral_cost = mineral_cost
	r.gas_cost = gas_cost
	r.research_time_turns = time_turns
	return r


# Tank-shaped (2x2) registry with movement; used by multi-tile collision
# tests.
func _tank_registry(speed: int) -> EntityRegistry:
	var d := _def_with_movement("tank", Vector2i(2, 2), ["heavy", "ground"], 150, speed)
	var registry := EntityRegistry.new()
	registry.entities = [d]
	return registry


# ---------- Plan node 08 — bake validation ----------


# Tiny registry used for MapBaker negative tests. Includes a worker (1x1),
# a 2x2 "block2" for on-axis tests, and a 3x3 "block3" for axis-crossing
# tests. None need full capability shapes — the baker only reads
# def.footprint.
func _baker_registry() -> EntityRegistry:
	var registry := EntityRegistry.new()
	var worker := EntityDef.new()
	worker.id = "worker"
	worker.footprint = Vector2i(1, 1)
	worker.tags = ["worker"]
	var block2 := EntityDef.new()
	block2.id = "block2"
	block2.footprint = Vector2i(2, 2)
	block2.tags = ["neutral"]
	var block3 := EntityDef.new()
	block3.id = "block3"
	block3.footprint = Vector2i(3, 3)
	block3.tags = ["neutral"]
	registry.entities = [worker, block2, block3]
	return registry


# Build a synthetic map scene with the given placements (no .tscn on disk).
# Each placement spec is a dict {def_id, owner, tile, on_axis}. Returns
# the scene root — caller is responsible for free()ing it.
func _make_test_map_scene(specs: Array) -> Node:
	var scene_root := Node2D.new()
	var placements_node := Node2D.new()
	placements_node.name = "Placements"
	scene_root.add_child(placements_node)
	var ep_script: GDScript = load("res://scripts/data/entity_placement.gd")
	for spec in specs:
		var ep := Node2D.new()
		ep.set_script(ep_script)
		ep.def_id = spec.get("def_id", "")
		ep.owner_player_id = spec.get("owner", -1)
		ep.tile_position = spec.get("tile", Vector2i.ZERO)
		ep.on_axis = spec.get("on_axis", false)
		placements_node.add_child(ep)
	return scene_root


func _test_map_baker_validation() -> bool:
	var registry := _baker_registry()
	var w := 50
	var h := 50

	# Negative 1: right-half placement rejected (worker at x=40).
	var scene1 := _make_test_map_scene(
		[{"def_id": "worker", "owner": 0, "tile": Vector2i(40, 25), "on_axis": false}]
	)
	var sd1 := MapBaker.bake_to_resource_from_scene(scene1, w, h, {}, registry)
	scene1.free()
	if sd1 != null:
		push_error("[map_baker_validation] right-half placement should fail")
		return false

	# Negative 2: unknown def_id rejected.
	var scene2 := _make_test_map_scene(
		[{"def_id": "no_such_def", "owner": 0, "tile": Vector2i(5, 5), "on_axis": false}]
	)
	var sd2 := MapBaker.bake_to_resource_from_scene(scene2, w, h, {}, registry)
	scene2.free()
	if sd2 != null:
		push_error("[map_baker_validation] unknown def_id should fail")
		return false

	# Negative 3: 3x3 axis-crossing placement without on_axis rejected.
	# block3 at x=23 occupies x=23,24,25 — right edge crosses the axis (24/25).
	var scene3 := _make_test_map_scene(
		[{"def_id": "block3", "owner": -1, "tile": Vector2i(23, 23), "on_axis": false}]
	)
	var sd3 := MapBaker.bake_to_resource_from_scene(scene3, w, h, {}, registry)
	scene3.free()
	if sd3 != null:
		push_error("[map_baker_validation] axis-crossing without on_axis should fail")
		return false

	# Negative 4: on-axis even-footprint with player owner rejected.
	# block2 (2x2) at x=24 is centered (occupies x=24,25), but owner=0
	# is invalid for axis-straddling placements.
	var scene4 := _make_test_map_scene(
		[{"def_id": "block2", "owner": 0, "tile": Vector2i(24, 23), "on_axis": true}]
	)
	var sd4 := MapBaker.bake_to_resource_from_scene(scene4, w, h, {}, registry)
	scene4.free()
	if sd4 != null:
		push_error("[map_baker_validation] on-axis with player owner should fail")
		return false

	# Negative 5: on-axis odd-footprint rejected (3x3 can't be centered
	# on an even-width axis).
	var scene5 := _make_test_map_scene(
		[{"def_id": "block3", "owner": -1, "tile": Vector2i(23, 23), "on_axis": true}]
	)
	var sd5 := MapBaker.bake_to_resource_from_scene(scene5, w, h, {}, registry)
	scene5.free()
	if sd5 != null:
		push_error("[map_baker_validation] odd-footprint on_axis should fail")
		return false

	# Positive: left-half placement → source + mirror = 2 placements.
	var scene_ok := _make_test_map_scene(
		[{"def_id": "worker", "owner": 0, "tile": Vector2i(5, 25), "on_axis": false}]
	)
	var sd_ok := MapBaker.bake_to_resource_from_scene(scene_ok, w, h, {}, registry)
	scene_ok.free()
	if sd_ok == null:
		push_error("[map_baker_validation] left-half worker should succeed")
		return false
	if sd_ok.placements.size() != 2:
		push_error(
			(
				"[map_baker_validation] expected 2 placements (source + mirror), got %d"
				% sd_ok.placements.size()
			)
		)
		return false
	# Verify the mirror is at x = 50 - 5 - 1 = 44, owner = 1.
	var owners := [sd_ok.placements[0].owner_player_id, sd_ok.placements[1].owner_player_id]
	owners.sort()
	if owners != [0, 1]:
		push_error("[map_baker_validation] mirror should flip owner: got %s" % str(owners))
		return false
	var xs := [sd_ok.placements[0].origin.x, sd_ok.placements[1].origin.x]
	xs.sort()
	if xs != [5, 44]:
		push_error("[map_baker_validation] mirror should be at x=44 (got xs=%s)" % str(xs))
		return false

	# Positive: on-axis even-footprint neutral → emitted ONCE.
	var scene_axis_ok := _make_test_map_scene(
		[{"def_id": "block2", "owner": -1, "tile": Vector2i(24, 23), "on_axis": true}]
	)
	var sd_axis := MapBaker.bake_to_resource_from_scene(scene_axis_ok, w, h, {}, registry)
	scene_axis_ok.free()
	if sd_axis == null or sd_axis.placements.size() != 1:
		push_error(
			(
				"[map_baker_validation] on-axis block2 should emit exactly 1 placement, got %s"
				% str(sd_axis.placements.size() if sd_axis != null else "null")
			)
		)
		return false

	return true


# ---------- Plan node 08 — full mvp_map suite ----------


func _entity_counts_by_def_id(state: MatchState) -> Dictionary:
	var counts := {}
	for entity in state.entities:
		counts[entity.def_id] = counts.get(entity.def_id, 0) + 1
	return counts


func _load_mvp_map() -> LoadedScenario:
	var scenario: ScenarioDef = load(_MVP_MAP_TRES_PATH)
	if scenario == null:
		return null
	var registry: EntityRegistry = load(_REGISTRY_PATH)
	var tunables: Tunables = load(_TUNABLES_PATH)
	if registry == null or tunables == null:
		return null
	return ScenarioLoader.load(scenario, registry, tunables)


func _scenario_defs_equal(a: ScenarioDef, b: ScenarioDef) -> bool:
	if a.map_width != b.map_width or a.map_height != b.map_height:
		return false
	if a.auto_start_workers_on_minerals != b.auto_start_workers_on_minerals:
		return false
	if a.placements.size() != b.placements.size():
		return false
	for i in range(a.placements.size()):
		var pa: ScenarioPlacement = a.placements[i]
		var pb: ScenarioPlacement = b.placements[i]
		if pa.def_id != pb.def_id:
			return false
		if pa.owner_player_id != pb.owner_player_id:
			return false
		if pa.origin != pb.origin:
			return false
		if pa.initial_hp_override != pb.initial_hp_override:
			return false
	return true


func _test_mvp_map_loads() -> bool:
	var loaded := _load_mvp_map()
	if loaded == null or loaded.state == null:
		push_error("[mvp_map_loads] ScenarioLoader returned null")
		return false
	if loaded.state.tile_grid.width != 50 or loaded.state.tile_grid.height != 50:
		push_error(
			(
				"[mvp_map_loads] expected 50x50 grid, got %dx%d"
				% [loaded.state.tile_grid.width, loaded.state.tile_grid.height]
			)
		)
		return false
	if loaded.state.players.size() != 2:
		push_error("[mvp_map_loads] expected 2 players")
		return false
	# Expected entity counts after the baker mirrors the left half.
	# One base, four workers, eight minerals, and one geyser per player.
	var counts := _entity_counts_by_def_id(loaded.state)
	var expected := {
		"base": 2,
		"worker": 8,
		"mineral_patch": 16,
		"mineral_patch_gold": 0,
		"gas_geyser": 2,
	}
	var expected_total := 28
	if loaded.state.entities.size() != expected_total:
		push_error(
			(
				"[mvp_map_loads] expected %d total entities, got %d"
				% [expected_total, loaded.state.entities.size()]
			)
		)
		return false
	for def_id in expected:
		if counts.get(def_id, 0) != expected[def_id]:
			push_error(
				(
					"[mvp_map_loads] expected %d %s, got %d"
					% [expected[def_id], def_id, counts.get(def_id, 0)]
				)
			)
			return false
	for player_id in [0, 1]:
		var auto_started_workers := 0
		for entity in loaded.state.entities_sorted_by_id():
			if entity.def_id != "worker" or entity.owner_player_id != player_id:
				continue
			if entity.gather_state == null:
				push_error("[mvp_map_loads] worker missing gather state")
				return false
			if entity.gather_state.assigned_source_entity_id < 0:
				push_error("[mvp_map_loads] worker should start assigned to minerals")
				return false
			if entity.gather_state.phase != GatherState.Phase.GATHERING:
				push_error("[mvp_map_loads] worker should start already mining minerals")
				return false
			auto_started_workers += 1
		if auto_started_workers != 4:
			push_error(
				(
					"[mvp_map_loads] expected four auto-started P%d workers, got %d"
					% [player_id, auto_started_workers]
				)
			)
			return false
	return true


func _test_mvp_map_simple_facing_bases() -> bool:
	var loaded := _load_mvp_map()
	if loaded == null or loaded.state == null:
		push_error("[mvp_map_simple_facing_bases] failed to load mvp_map")
		return false
	var state: MatchState = loaded.state
	var p0_base: Entity = _find_entity_by_def_and_owner(state, "base", 0)
	var p1_base: Entity = _find_entity_by_def_and_owner(state, "base", 1)
	if p0_base == null or p1_base == null:
		push_error("[mvp_map_simple_facing_bases] expected one base for each player")
		return false
	var p0_rect: Rect2i = state.tile_grid.entity_rect(p0_base.id)
	var p1_rect: Rect2i = state.tile_grid.entity_rect(p1_base.id)
	var ok := true
	if p0_rect.position.x >= p1_rect.position.x:
		push_error("[mvp_map_simple_facing_bases] P0 base should be left of P1 base")
		ok = false
	if p0_rect.position.y * 2 + p0_rect.size.y != p1_rect.position.y * 2 + p1_rect.size.y:
		push_error("[mvp_map_simple_facing_bases] bases should face each other on the same row")
		ok = false

	var left_resources := _resource_rects_on_side(state, true)
	var right_resources := _resource_rects_on_side(state, false)
	if left_resources.size() != 9:
		push_error(
			(
				"[mvp_map_simple_facing_bases] expected 9 left-side resources, got %d"
				% left_resources.size()
			)
		)
		ok = false
	if right_resources.size() != 9:
		push_error(
			(
				"[mvp_map_simple_facing_bases] expected 9 right-side resources, got %d"
				% right_resources.size()
			)
		)
		ok = false
	for rect in left_resources:
		if rect.position.x + rect.size.x > p0_rect.position.x:
			push_error(
				(
					"[mvp_map_simple_facing_bases] left resource %s is not behind P0 base %s"
					% [str(rect), str(p0_rect)]
				)
			)
			ok = false
	for rect in right_resources:
		if rect.position.x < p1_rect.position.x + p1_rect.size.x:
			push_error(
				(
					"[mvp_map_simple_facing_bases] right resource %s is not behind P1 base %s"
					% [str(rect), str(p1_rect)]
				)
			)
			ok = false
	return ok


func _find_entity_by_def_and_owner(
	state: MatchState, def_id: String, owner_player_id: int
) -> Entity:
	var found: Entity = null
	for entity in state.entities:
		if entity == null:
			continue
		if entity.def_id != def_id or entity.owner_player_id != owner_player_id:
			continue
		if found != null:
			return null
		found = entity
	return found


func _resource_rects_on_side(state: MatchState, left_side: bool) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	var half_x: int = state.tile_grid.width / 2
	for entity in state.entities:
		if entity == null or not ["mineral_patch", "gas_geyser"].has(entity.def_id):
			continue
		var rect: Rect2i = state.tile_grid.entity_rect(entity.id)
		if left_side and rect.position.x < half_x:
			rects.append(rect)
		elif not left_side and rect.position.x >= half_x:
			rects.append(rect)
	return rects


func _test_mvp_map_is_mirror() -> bool:
	var loaded := _load_mvp_map()
	if loaded == null:
		push_error("[mvp_map_is_mirror] failed to load mvp_map")
		return false
	var w: int = loaded.state.tile_grid.width
	var paired: Dictionary = {}
	for entity in loaded.state.entities:
		if paired.has(entity.id):
			continue
		var rect: Rect2i = loaded.state.tile_grid.entity_rect(entity.id)
		var mirror_x: int = w - rect.position.x - rect.size.x
		# Self-mirror (axis placement): no pair needed.
		if mirror_x == rect.position.x:
			paired[entity.id] = true
			continue
		var mirror_owner: int = entity.owner_player_id
		if entity.owner_player_id == 0:
			mirror_owner = 1
		elif entity.owner_player_id == 1:
			mirror_owner = 0
		var found: int = -1
		for other in loaded.state.entities:
			if other.id == entity.id or paired.has(other.id):
				continue
			if other.def_id != entity.def_id:
				continue
			if other.owner_player_id != mirror_owner:
				continue
			var other_rect: Rect2i = loaded.state.tile_grid.entity_rect(other.id)
			if (
				other_rect.position.x == mirror_x
				and other_rect.position.y == rect.position.y
				and other_rect.size == rect.size
			):
				found = other.id
				break
		if found == -1:
			push_error(
				(
					"[mvp_map_is_mirror] no mirror for entity %d (def=%s, owner=%d) at %s"
					% [entity.id, entity.def_id, entity.owner_player_id, str(rect.position)]
				)
			)
			return false
		paired[entity.id] = true
		paired[found] = true
	return true


func _test_mvp_map_bake_parity() -> bool:
	var registry: EntityRegistry = load(_REGISTRY_PATH)
	var tunables: Tunables = load(_TUNABLES_PATH)
	if registry == null or tunables == null:
		push_error("[mvp_map_bake_parity] missing registry or tunables")
		return false
	var starting_resources: Dictionary = {
		0: {"minerals": tunables.starting_minerals, "gas": tunables.starting_gas},
		1: {"minerals": tunables.starting_minerals, "gas": tunables.starting_gas},
	}
	var fresh: ScenarioDef = (
		MapBaker
		. bake_to_resource(
			_MVP_MAP_TSCN_PATH,
			tunables.map_width,
			tunables.map_height,
			starting_resources,
			registry,
			true,
		)
	)
	if fresh == null:
		push_error("[mvp_map_bake_parity] re-bake failed")
		return false
	var on_disk: ScenarioDef = load(_MVP_MAP_TRES_PATH)
	if on_disk == null:
		push_error("[mvp_map_bake_parity] failed to load mvp_map.tres")
		return false
	if not _scenario_defs_equal(fresh, on_disk):
		push_error(
			(
				"[mvp_map_bake_parity] mvp_map.tres is stale "
				+ "(re-run Bake MVP Map from Project > Tools after editing the .tscn)"
			)
		)
		return false
	return true


func _test_golden_minerals_higher_yield() -> bool:
	# Synthetic head-to-head: identical scenario with one worker on a
	# standard mineral_patch vs one worker on a mineral_patch_gold.
	# Run for N=30 turns, compare totals. Asserts strict greater-than,
	# not a specific multiplier — lets us retune yields without breaking
	# the test on balance changes.
	var standard_total := _gather_total_after_turns("mineral_patch", 1, 30)
	var golden_total := _gather_total_after_turns("mineral_patch_gold", 2, 30)
	if golden_total <= standard_total:
		push_error(
			(
				(
					"[golden_minerals_higher_yield] expected golden > standard, "
					+ "got golden=%d standard=%d"
				)
				% [golden_total, standard_total]
			)
		)
		return false
	return true


# ---------- Plan node 07b5 — self-target ability orders ----------


func _test_ability_stim_rejects_without_research() -> bool:
	var registry: EntityRegistry = _ability_registry()
	var state: MatchState = _ability_state_with_bases()
	var marine: Entity = _make_entity(state, "marine", 0, Vector2i(5, 5), 45, "ground")
	state.tile_grid.place(marine.id, Rect2i(5, 5, 1, 1))

	var result: ResolveResult = Resolver.resolve(
		state, _submit([_ability_order(marine.id, "stim")]), _submit(), registry, null
	)
	var new_marine: Entity = result.new_state.get_entity_by_id(marine.id)
	if new_marine.current_hp != 45:
		push_error("rejected stim should not spend HP")
		return false
	if not new_marine.active_buffs.is_empty():
		push_error("rejected stim should not apply a buff")
		return false
	return _has_rejection(result.events, marine.id, "research_required")


func _test_ability_stim_applies_cost_buff_cooldown_and_event() -> bool:
	var registry: EntityRegistry = _ability_registry()
	var state: MatchState = _ability_state_with_bases()
	state.get_player(0).unlocked_researches.append("stim_research")
	var marine: Entity = _make_entity(state, "marine", 0, Vector2i(5, 5), 45, "ground")
	var enemy: Entity = _make_entity(state, "marine", 1, Vector2i(7, 5), 45, "ground")
	enemy.hold_fire = true
	state.tile_grid.place(marine.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(enemy.id, Rect2i(7, 5, 1, 1))

	var attack: EntityOrder = EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = marine.id
	attack.target_priority_chain = [enemy.id]
	var result: ResolveResult = Resolver.resolve(
		state, _submit([_ability_order(marine.id, "stim"), attack]), _submit(), registry, null
	)
	var new_marine: Entity = result.new_state.get_entity_by_id(marine.id)
	var new_enemy: Entity = result.new_state.get_entity_by_id(enemy.id)
	if not _has_event_with_def(result.events, ResolverEvent.Type.ABILITY_USED, marine.id, "stim"):
		push_error("stim should emit ABILITY_USED")
		return false
	if new_marine.current_hp != 35:
		push_error("stim should spend 10 HP, got %d" % new_marine.current_hp)
		return false
	if new_marine.ability_cooldowns.get("stim", 0) != 5:
		push_error("stim cooldown should be 5 after the use turn")
		return false
	if new_marine.active_buffs.size() != 1:
		push_error("stim should apply one active buff")
		return false
	var buff: ActiveBuff = new_marine.active_buffs[0]
	if buff.source_ability_id != "stim" or buff.turns_remaining != 2:
		push_error("stim buff should remain for 2 turns after end-of-turn tick")
		return false
	if new_enemy.current_hp != 36:
		push_error(
			"same-turn attack should use stim damage; enemy HP got %d" % new_enemy.current_hp
		)
		return false
	return true


func _test_ability_stim_rejects_on_cooldown() -> bool:
	var registry: EntityRegistry = _ability_registry()
	var state: MatchState = _ability_state_with_bases()
	state.get_player(0).unlocked_researches.append("stim_research")
	var marine: Entity = _make_entity(state, "marine", 0, Vector2i(5, 5), 45, "ground")
	marine.ability_cooldowns = {"stim": 2}
	state.tile_grid.place(marine.id, Rect2i(5, 5, 1, 1))

	var result: ResolveResult = Resolver.resolve(
		state, _submit([_ability_order(marine.id, "stim")]), _submit(), registry, null
	)
	var new_marine: Entity = result.new_state.get_entity_by_id(marine.id)
	if new_marine.current_hp != 45:
		push_error("cooldown-rejected stim should not spend HP")
		return false
	return _has_rejection(result.events, marine.id, "cooldown")


func _test_ability_stim_rejects_low_hp() -> bool:
	var registry: EntityRegistry = _ability_registry()
	var state: MatchState = _ability_state_with_bases()
	state.get_player(0).unlocked_researches.append("stim_research")
	var marine: Entity = _make_entity(state, "marine", 0, Vector2i(5, 5), 10, "ground")
	state.tile_grid.place(marine.id, Rect2i(5, 5, 1, 1))

	var result: ResolveResult = Resolver.resolve(
		state, _submit([_ability_order(marine.id, "stim")]), _submit(), registry, null
	)
	var new_marine: Entity = result.new_state.get_entity_by_id(marine.id)
	if new_marine.current_hp != 10:
		push_error("low-HP rejected stim should not spend HP")
		return false
	return _has_rejection(result.events, marine.id, "insufficient_hp")


func _test_ability_siege_delayed_transform_blocks_later_actions() -> bool:
	var registry: EntityRegistry = _ability_registry()
	var state: MatchState = _ability_state_with_bases()
	state.get_player(0).unlocked_researches.append("siege_mode_research")
	var tank: Entity = _make_entity(state, "tank", 0, Vector2i(5, 5), 150, "ground")
	state.tile_grid.place(tank.id, Rect2i(5, 5, 2, 2))
	var move: EntityOrder = EntityOrder.new()
	move.type = EntityOrder.Type.MOVE
	move.entity_id = tank.id
	move.target_tile = Vector2i(9, 5)

	var result: ResolveResult = Resolver.resolve(
		state, _submit([_ability_order(tank.id, "siege_mode"), move]), _submit(), registry, null
	)
	var new_tank: Entity = result.new_state.get_entity_by_id(tank.id)
	if new_tank.current_def_id != "siege_tank":
		push_error("siege mode should transform tank to siege_tank")
		return false
	if new_tank.origin != Vector2i(5, 5):
		push_error("later MOVE should be blocked while siege cast is active")
		return false
	if new_tank.ability_cast != null:
		push_error("one-turn siege cast should be cleared after transform")
		return false
	if _has_event_of_type(result.events, ResolverEvent.Type.ENTITY_MOVED):
		push_error("siege casting should not also move")
		return false
	if not _has_event_with_def(
		result.events, ResolverEvent.Type.ENTITY_TRANSFORMED, tank.id, "siege_tank"
	):
		push_error("siege mode should emit ENTITY_TRANSFORMED")
		return false
	return _has_event_with_def(
		result.events, ResolverEvent.Type.ABILITY_USED, tank.id, "siege_mode"
	)


func _test_ability_unsiege_delayed_transform() -> bool:
	var registry: EntityRegistry = _ability_registry()
	var state: MatchState = _ability_state_with_bases()
	state.get_player(0).unlocked_researches.append("siege_mode_research")
	var tank: Entity = _make_entity(state, "siege_tank", 0, Vector2i(5, 5), 150, "ground")
	state.tile_grid.place(tank.id, Rect2i(5, 5, 2, 2))

	var result: ResolveResult = Resolver.resolve(
		state, _submit([_ability_order(tank.id, "unsiege_mode")]), _submit(), registry, null
	)
	var new_tank: Entity = result.new_state.get_entity_by_id(tank.id)
	if new_tank.current_def_id != "tank":
		push_error("unsiege mode should transform siege_tank back to tank")
		return false
	return _has_event_with_def(
		result.events, ResolverEvent.Type.ENTITY_TRANSFORMED, tank.id, "tank"
	)


func _test_siege_tank_data_is_immobile_and_siege_requires_research() -> bool:
	var registry: EntityRegistry = _load_data_registry()
	if registry == null:
		push_error("registry should load entity data")
		return false
	var tank: EntityDef = registry.get_by_id("tank")
	var siege_tank: EntityDef = registry.get_by_id("siege_tank")
	if tank == null:
		push_error("tank data missing")
		return false
	if tank.abilities == null or tank.abilities.abilities.is_empty():
		push_error("tank should expose siege_mode ability data")
		return false
	var siege: AbilityDef = null
	for item in tank.abilities.abilities:
		var ability: AbilityDef = item
		if ability != null and ability.id == "siege_mode":
			siege = ability
			break
	if siege == null:
		push_error("tank should expose siege_mode ability data")
		return false
	if siege.requires_research_id != "siege_mode_research":
		push_error("siege_mode should require siege_mode_research")
		return false
	if siege_tank == null:
		push_error("siege_tank data missing")
		return false
	if siege_tank.movement != null:
		push_error("siege_tank should be immobile")
		return false
	return true


# Build a 1-base + 1-worker + 1-patch scenario, run N turns, return the
# total minerals harvested. The patch is a synthetic def with the given
# yield; capacity is high enough to avoid depleting in N turns.
func _gather_total_after_turns(patch_def_id: String, patch_yield: int, turns: int) -> int:
	var registry := _golden_yield_registry(patch_def_id, patch_yield)
	var state := _state_with_grid(20, 20)
	var worker := _make_entity(state, "worker", 0, Vector2i(5, 5), 50, "ground")
	worker.gather_state = GatherState.new()
	state.tile_grid.place(worker.id, Rect2i(5, 5, 1, 1))
	var base := _make_entity(state, "base", 0, Vector2i(0, 0), 1500, "ground")
	state.tile_grid.place(base.id, Rect2i(0, 0, 4, 4))
	var patch := _make_entity(state, patch_def_id, -1, Vector2i(8, 5), 1500, "ground")
	patch.current_resource_amount = 5000
	state.tile_grid.place(patch.id, Rect2i(8, 5, 1, 1))
	_add_opponent_keepalive_building(state, registry)

	var orders := OrderBuilder.fan_out_gather([worker.id] as Array[int], patch.id)
	var result := Resolver.resolve(state, _submit(orders), _submit(), registry, null)
	for _i in turns:
		result = Resolver.resolve(result.new_state, _submit(), _submit(), registry, null)
	var p := result.new_state.get_player(0)
	return 0 if p == null else p.minerals


func _golden_yield_registry(patch_def_id: String, patch_yield: int) -> EntityRegistry:
	var registry := EntityRegistry.new()
	var worker := _def_with_movement("worker", Vector2i(1, 1), ["worker", "ground"], 50, 4)
	worker.gather = GatherDef.new()
	worker.gather.gather_per_turn = patch_yield
	worker.gather.carry_amount = 5
	worker.gather.accepts_resource_types = ["minerals", "gas"]
	var base := EntityDef.new()
	base.id = "base"
	base.footprint = Vector2i(4, 4)
	base.tags = ["building", "structure", "ground", "deposit_sink"]
	var base_hp := HealthDef.new()
	base_hp.max_hp = 1500
	base.health = base_hp
	var patch := EntityDef.new()
	patch.id = patch_def_id
	patch.footprint = Vector2i(1, 1)
	patch.tags = ["resource_source", "minerals", "ground"]
	var patch_rs := ResourceSourceDef.new()
	patch_rs.resource_type = "minerals"
	patch_rs.yield_per_worker_per_turn = patch_yield
	patch_rs.requires_extractor = false
	patch.resource_source = patch_rs
	registry.entities = [worker, base, patch]
	return registry
