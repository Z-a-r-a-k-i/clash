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
		["move_budget_respected", _test_move_budget_respected],
		["attack_move_halts_when_enemy_in_range", _test_attack_move_halts_when_enemy_in_range],
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
		["attack_move_no_enemy_in_range_advances", _test_attack_move_no_enemy_in_range_advances],
		["fresh_order_overrides_persistent_order", _test_fresh_order_overrides_persistent_order],
		["multi_buff_stacks_multiplicatively", _test_multi_buff_stacks_multiplicatively],
		["no_tile_grid_distance_fallback", _test_no_tile_grid_distance_fallback],
		["closest_enemy_skips_dead", _test_closest_enemy_skips_dead],
		["closest_enemy_ties_break_by_id", _test_closest_enemy_ties_break_by_id],
	]


# ---------- Chunk 1 — skeleton ----------


func _test_smoke_empty_input() -> bool:
	# Empty state, empty queues → empty events, no crash.
	var state := MatchState.new()
	var queue_a: Array[EntityOrder] = []
	var queue_b: Array[EntityOrder] = []
	var result := Resolver.resolve(state, queue_a, queue_b, null, null)
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
	var result := Resolver.resolve(state, queue_a, queue_b, registry, null)
	return result.events.size() == 0


func _test_surrender_ends_match() -> bool:
	# Player A surrenders → MATCH_ENDED event with winner = 1, match_over = true.
	var state := MatchState.new()
	state.players = [_player(0), _player(1)]

	var surrender := EntityOrder.new()
	surrender.type = EntityOrder.Type.SURRENDER
	# entity_id stays -1 (player-level order).
	var queue_a: Array[EntityOrder] = [surrender]
	var queue_b: Array[EntityOrder] = []

	var result := Resolver.resolve(state, queue_a, queue_b, null, null)
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
	var result := Resolver.resolve(state, queue_a, queue_b, null, null)

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

	var result := Resolver.resolve(state, queue_a, [], registry, null)
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
	var result := Resolver.resolve(state, queue_a, [], registry, null)

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
	state.tile_grid.place(attacker.id, Rect2i(5, 5, 1, 1))
	state.tile_grid.place(enemy.id, Rect2i(8, 5, 1, 1))

	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = attacker.id
	# Empty chain.
	var queue_a: Array[EntityOrder] = [attack]

	var result := Resolver.resolve(state, queue_a, [], registry, null)
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

	var result := Resolver.resolve(state, queue_a, [], registry, null)
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
	state.tile_grid.place(tank.id, Rect2i(5, 5, 2, 2))
	state.tile_grid.place(heli.id, Rect2i(8, 5, 1, 1))

	var attack := EntityOrder.new()
	attack.type = EntityOrder.Type.ATTACK
	attack.entity_id = tank.id
	attack.target_priority_chain = [heli.id]
	var queue_a: Array[EntityOrder] = [attack]

	var result := Resolver.resolve(state, queue_a, [], registry, null)
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

	var result := Resolver.resolve(state, queue_a, [], registry, null)
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

	var result := Resolver.resolve(state, queue_a, [], registry, null)
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

	var result := Resolver.resolve(state, queue_a, [], registry, null)
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

	var result := Resolver.resolve(state, [move] as Array[EntityOrder], [], registry, null)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == mover.id:
			return false
	return true


func _test_persistent_move_continuation() -> bool:
	# Entity has persistent_order set; no fresh order this tick. Expect
	# Phase 3 to advance one step toward the persistent target.
	var registry := _movable_registry(4)
	var state := _state_with_grid(20, 20)
	var actor := _make_entity(state, "marine", 0, Vector2i(5, 5), 50, "ground")
	state.tile_grid.place(actor.id, Rect2i(5, 5, 1, 1))

	var po := EntityOrder.new()
	po.type = EntityOrder.Type.MOVE
	po.entity_id = actor.id
	po.target_tile = Vector2i(15, 5)
	actor.persistent_order = po

	# No orders submitted this turn, but we need at least one tick. The
	# resolver currently sets N = max queue length; with no orders, N = 0
	# and Phase 3 doesn't run. Submit a no-op for a different entity to
	# force at least one tick.
	#
	# Workaround for M0: queue a HOLD_FIRE_TOGGLE on the same entity (it
	# applies at distribution time, not in the tick loop, so it doesn't
	# count toward queue length). Simpler: add a second entity owned by
	# the same player and queue an empty action... actually no, queue
	# length is per-entity.
	#
	# For this test, add a placeholder entity with one queued MOVE so
	# N=1, then check the actor's persistent move advanced.
	var dummy := _make_entity(state, "marine", 0, Vector2i(0, 0), 50, "ground")
	state.tile_grid.place(dummy.id, Rect2i(0, 0, 1, 1))
	var dummy_move := EntityOrder.new()
	dummy_move.type = EntityOrder.Type.MOVE
	dummy_move.entity_id = dummy.id
	dummy_move.target_tile = Vector2i(0, 0)  # already there, so step_toward returns false
	var queue_a: Array[EntityOrder] = [dummy_move]

	var result := Resolver.resolve(state, queue_a, [], registry, null)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == actor.id:
			# Persistent move should have advanced one tile toward (15, 5).
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

	var result := Resolver.resolve(state, [attack, move] as Array[EntityOrder], [], registry, null)
	var damaged_idx := -1
	var moved_idx := -1
	for i in result.events.size():
		var ev: ResolverEvent = result.events[i]
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED and damaged_idx == -1:
			damaged_idx = i
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and moved_idx == -1:
			moved_idx = i
	return damaged_idx != -1 and moved_idx != -1 and damaged_idx < moved_idx


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

	var result := Resolver.resolve(state, queue_a, [], registry, null)
	var move_count := 0
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == actor.id:
			move_count += 1
	return move_count == 2


func _test_attack_move_halts_when_enemy_in_range() -> bool:
	# ATTACK_MOVE with an enemy in range: should NOT emit ENTITY_MOVED
	# this tick (combat halts movement).
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

	var result := Resolver.resolve(state, queue_a, [], registry, null)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == actor.id:
			return false
	# We DO expect a damage event since the enemy is in range.
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED and ev.actor_id == actor.id:
			return true
	return false


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

	var result := Resolver.resolve(state, queue_a, [], registry, null)
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

	var result := Resolver.resolve(state, queue_a, [], registry, null)
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

	var result := Resolver.resolve(state, queue_a, [], registry, null)
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

	var result := Resolver.resolve(state, queue_a, [], registry, null)
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return new_actor.moves_used_this_turn == 0


func _test_production_progress_emits_completion() -> bool:
	# Building with one queued production item, turns_remaining=1 →
	# end-of-turn emits BUILD_COMPLETED, queue empties.
	var registry := EntityRegistry.new()
	var building_def := EntityDef.new()
	building_def.id = "barracks"
	building_def.tags = ["building", "ground"]
	building_def.footprint = Vector2i(3, 3)
	var hd := HealthDef.new()
	hd.max_hp = 1000
	building_def.health = hd
	registry.entities = [building_def]

	var state := _state_with_grid(20, 20)
	var building := _make_entity(state, "barracks", 0, Vector2i(2, 2), 1000, "ground")
	state.tile_grid.place(building.id, Rect2i(2, 2, 3, 3))
	var ps := ProductionState.new()
	ps.queue = [
		{
			ProductionState.KEY_DEF_ID: "marine",
			ProductionState.KEY_KIND: ProductionState.KIND_UNIT,
			ProductionState.KEY_TURNS_REMAINING: 1,
		}
	]
	building.production_state = ps

	# Force at least one tick (any noop order).
	var noop := EntityOrder.new()
	noop.type = EntityOrder.Type.MOVE
	noop.entity_id = building.id
	noop.target_tile = building.origin  # building has no Movement; resolve_move skips.
	var queue_a: Array[EntityOrder] = [noop]

	var result := Resolver.resolve(state, queue_a, [], registry, null)
	var saw_completed := false
	for ev in result.events:
		if ev.type == ResolverEvent.Type.BUILD_COMPLETED and ev.def_id == "marine":
			saw_completed = true
	if not saw_completed:
		return false
	var new_building := result.new_state.get_entity_by_id(building.id)
	return new_building.production_state.queue.is_empty()


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

	var result := Resolver.resolve(state, queue_a, [], registry, null)
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
		var result := Resolver.resolve(state, queue_a, [], registry, null)
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
		if pa.has_surrendered != pb.has_surrendered:
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
		if ea.is_hidden != eb.is_hidden:
			return false
		if ea.ability_cooldowns != eb.ability_cooldowns:
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
		var po_a := ea.persistent_order
		var po_b := eb.persistent_order
		if (po_a == null) != (po_b == null):
			return false
		if po_a != null and po_a.target_tile != po_b.target_tile:
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

	var result := Resolver.resolve(state, [hf, attack] as Array[EntityOrder], [], registry, null)
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
	var result := Resolver.resolve(state, queue_a, [], registry, null)

	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_MOVED and ev.actor_id == actor.id:
			return false
	var new_actor := result.new_state.get_entity_by_id(actor.id)
	return new_actor.persistent_order == null


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

	var result := Resolver.resolve(state, [am] as Array[EntityOrder], [], registry, null)
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

	var result := Resolver.resolve(state, [fresh] as Array[EntityOrder], [], registry, null)
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

	var result := Resolver.resolve(state, [attack] as Array[EntityOrder], [], registry, null)
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

	var result := Resolver.resolve(state, [attack] as Array[EntityOrder], [], registry, null)
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

	var result := Resolver.resolve(state, [attack] as Array[EntityOrder], [], registry, null)
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

	var result := Resolver.resolve(state, [attack] as Array[EntityOrder], [], registry, null)
	for ev in result.events:
		if ev.type == ResolverEvent.Type.ENTITY_DAMAGED:
			return ev.target_id == alive_far.id
	return false


# ---------- Helpers ----------


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


func _movement_def(speed: int, default_layer: String = "ground") -> MovementDef:
	var m := MovementDef.new()
	m.speed_tiles_per_turn = speed
	m.default_layer = default_layer
	return m


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


# Tank-shaped (2x2) registry with movement; used by multi-tile collision
# tests.
func _tank_registry(speed: int) -> EntityRegistry:
	var d := _def_with_movement("tank", Vector2i(2, 2), ["heavy", "ground"], 150, speed)
	var registry := EntityRegistry.new()
	registry.entities = [d]
	return registry
