class_name Resolver
extends RefCounted

# Pure-function turn resolver. Per ADR 0004 (action-slot lockstep) and
# ADR 0013 (deterministic, no RNG).
#
# Contract:
#   Resolver.resolve(state, submit_a, submit_b, registry, tunables) -> ResolveResult
#
# - Does NOT mutate the input `state`. A deep copy is made internally and
#   the copy is returned in `ResolveResult.new_state`.
# - Output `events` is the ordered sequence of things that happened, in
#   the order clients animate them.
# - Same input always produces the same output (golden-test verifiable;
#   see client/scripts/_dev/test_resolver.gd "determinism_golden").
#
# Algorithm summary (full text in plan/m0/02-tick-based-resolver.md):
#   1. Apply player-level orders (surrender flag) — short-circuits if set.
#   2. Distribute per-entity orders; HOLD_FIRE_TOGGLE / CANCEL apply now.
#   3. For tick in 1..N:
#        Phase 1: every unit's k-th action that is an attack.
#        Phase 2: every unit's k-th action that is a move (+ gather travel).
#        Phase 3: persistent move advance + gather state ticks (yield/deposit).
#   4. End-of-turn pass: cooldowns, buffs, production progress, is_hidden,
#      win check.
#
# The resolver is split across these files for chunked implementation:
# - resolver.gd          (this) — entry point + tick loop
# - combat_system.gd     — attack resolution + target chains
# - movement_system.gd   — move + attack-move + persistent
# - gather_system.gd     — worker FSM (move-to-source, gather, deposit)
# - end_of_turn_system.gd — bookkeeping + win check
# - _state_helpers.gd    — deep-copy + queue distribution

const _STATE_HELPERS := preload("res://scripts/resolver/_state_helpers.gd")


static func resolve(
	state: MatchState,
	submit_a: SubmitTurn,
	submit_b: SubmitTurn,
	registry: EntityRegistry,
	tunables: Tunables
) -> ResolveResult:
	var result := ResolveResult.new()
	var events: Array[ResolverEvent] = []

	# 1. Working copies. Per the pure-function contract, neither the input
	#    `state` nor the input submissions can be aliased into the result.
	#    Cloning state is obvious; cloning the SubmitTurns matters because
	#    a fresh MOVE / ATTACK_MOVE gets stashed into Entity.persistent_order
	#    by the movement system — without the clone, `result.new_state`
	#    would alias the caller's EntityOrder instances.
	var working: MatchState = state.clone()
	var safe_submit_a: SubmitTurn = submit_a.clone() if submit_a != null else null
	var safe_submit_b: SubmitTurn = submit_b.clone() if submit_b != null else null

	# 1a. If the match is already over, return a clone with no further
	#     processing. Prevents re-emitting MATCH_ENDED or mutating terminal
	#     state when the caller hands us a finished state.
	if working.match_over:
		result.new_state = working
		result.events = events
		return result

	# 2. Player-level surrender takes priority — if either side surrendered,
	#    the match ends and remaining tick work is moot.
	var surrender_a := safe_submit_a != null and safe_submit_a.surrender
	var surrender_b := safe_submit_b != null and safe_submit_b.surrender
	if surrender_a or surrender_b:
		# Read the actual player_ids from working.players so non-default
		# id assignments still produce correct winners. Both surrendered → -1
		# (M0 has no draw rule; legitimate UI shouldn't produce this).
		# Null slots are tolerated (clone preserves them) and fall back to
		# the conventional 0/1 mapping.
		var p_a: PlayerState = working.players[0] if working.players.size() >= 1 else null
		var p_b: PlayerState = working.players[1] if working.players.size() >= 2 else null
		var pid_a := p_a.player_id if p_a != null else 0
		var pid_b := p_b.player_id if p_b != null else 1
		var ev := ResolverEvent.new()
		ev.type = ResolverEvent.Type.MATCH_ENDED
		if surrender_a and not surrender_b:
			ev.winner_player_id = pid_b
		elif surrender_b and not surrender_a:
			ev.winner_player_id = pid_a
		else:
			ev.winner_player_id = -1
		working.match_over = true
		working.winner_player_id = ev.winner_player_id
		events.append(ev)
		result.new_state = working
		result.events = events
		return result

	# 3. Distribute orders into per-entity queues. HOLD_FIRE_TOGGLE and
	#    CANCEL apply during distribution (they're mode changes, not
	#    actions).
	var orders_a: Array[EntityOrder] = (
		safe_submit_a.orders if safe_submit_a != null else [] as Array[EntityOrder]
	)
	var orders_b: Array[EntityOrder] = (
		safe_submit_b.orders if safe_submit_b != null else [] as Array[EntityOrder]
	)
	var per_entity := _STATE_HELPERS.distribute_orders(working, orders_a, orders_b)

	# 4. Tick loop — action-slot lockstep per ADR 0004.
	var n_ticks := _STATE_HELPERS.max_queue_length(per_entity)
	# Ensure persistent moves and active gather cycles still advance on
	# turns with no submitted orders.
	if n_ticks == 0 and _has_standing_work(working):
		n_ticks = 1
	for tick in n_ticks:
		# Sort once per tick and reuse across phases. Determinism still
		# requires fresh sorts each tick because attacks in the previous
		# tick can have killed entities, and dead entities are still in
		# the array (current_hp == 0) — the sort is stable and id-based,
		# so the order itself doesn't change, but recomputing is cheap and
		# defensive against future mutations of `entities`.
		var sorted_entities := working.entities_sorted_by_id()

		# Phase 1: attacks. Stable iteration by id for determinism.
		for entity in sorted_entities:
			var order := _STATE_HELPERS.action_at(per_entity, entity.id, tick)
			if order == null:
				continue
			if order.type == EntityOrder.Type.ATTACK or order.type == EntityOrder.Type.ATTACK_MOVE:
				CombatSystem.resolve_attack(working, entity, order, registry, tunables, events)

		# Phase 2: moves. Same stable iteration.
		for entity in sorted_entities:
			var order := _STATE_HELPERS.action_at(per_entity, entity.id, tick)
			if order == null:
				continue
			if order.type == EntityOrder.Type.MOVE or order.type == EntityOrder.Type.ATTACK_MOVE:
				MovementSystem.resolve_move(working, entity, order, registry, tunables, events)

		# Phase 2 extension: gather workers that are walking to a source or
		# a deposit sink step here too — same lockstep as MOVE.
		GatherSystem.advance_move_phase(working, per_entity, tick, registry, tunables, events)

		# Phase 3: persistent move advance for entities with no fresh order.
		MovementSystem.advance_persistent_moves(
			working, per_entity, tick, registry, tunables, events
		)

		# Phase 3 extension: gather workers at a source / sink tick yields
		# and deposits.
		GatherSystem.advance_state_phase(working, registry, tunables, events)

	# 5. End-of-turn pass.
	EndOfTurnSystem.run(working, registry, tunables, events)
	working.turn_index += 1

	result.new_state = working
	result.events = events
	return result


# Returns true if any live entity has standing work that needs at least
# one tick to advance: a `persistent_order`, or a non-IDLE gather phase.
# Used by resolve() to force n_ticks ≥ 1 on turns with no submitted
# orders.
static func _has_standing_work(state: MatchState) -> bool:
	for e in state.entities:
		if e == null or e.current_hp <= 0:
			continue
		if e.persistent_order != null:
			return true
		if e.gather_state != null and e.gather_state.phase != GatherState.Phase.IDLE:
			return true
	return false
