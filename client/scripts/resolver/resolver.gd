class_name Resolver
extends RefCounted

# Pure-function turn resolver. Per ADR 0004 (action-slot lockstep) and
# ADR 0013 (deterministic, no RNG).
#
# Contract:
#   Resolver.resolve(state, queue_a, queue_b, registry, tunables) -> ResolveResult
#
# - Does NOT mutate the input `state`. A deep copy is made internally and
#   the copy is returned in `ResolveResult.new_state`.
# - Output `events` is the ordered sequence of things that happened, in
#   the order clients animate them.
# - Same input always produces the same output (golden-test verifiable;
#   see client/scripts/_dev/test_resolver.gd "determinism_golden").
#
# Algorithm summary (full text in plan/m0/02-tick-based-resolver.md):
#   1. Apply player-level orders (SURRENDER) — short-circuits if present.
#   2. Distribute per-entity orders; HOLD_FIRE_TOGGLE / CANCEL apply now.
#   3. For tick in 1..N:
#        Phase 1: every unit's k-th action that is an attack.
#        Phase 2: every unit's k-th action that is a move.
#        Phase 3: persistent move advance for units with no fresh order.
#   4. End-of-turn pass: cooldowns, buffs, production progress, is_hidden,
#      win check.
#
# The resolver is split across these files for chunked implementation:
# - resolver.gd          (this) — entry point + tick loop
# - combat_system.gd     — attack resolution + target chains (chunk 3)
# - movement_system.gd   — move + attack-move + persistent (chunk 4)
# - end_of_turn_system.gd — bookkeeping + win check (chunk 5)
# - _state_helpers.gd    — deep-copy + queue distribution

const _STATE_HELPERS := preload("res://scripts/resolver/_state_helpers.gd")


static func resolve(
	state: MatchState,
	queue_a: Array[EntityOrder],
	queue_b: Array[EntityOrder],
	registry: EntityRegistry,
	tunables: Tunables
) -> ResolveResult:
	var result := ResolveResult.new()
	var events: Array[ResolverEvent] = []

	# 1. Working copy. Per the pure-function contract, the input `state` is
	#    never mutated — we operate on a deep clone and return it.
	var working: MatchState = state.clone()

	# 1a. If the match is already over, return a clone with no further
	#     processing. Prevents re-emitting MATCH_ENDED or mutating terminal
	#     state when the caller hands us a finished state.
	if working.match_over:
		result.new_state = working
		result.events = events
		return result

	# 2. Player-level surrender takes priority — if either side surrendered,
	#    the match ends and remaining tick work is moot.
	var surrender_a := _STATE_HELPERS.has_surrender(queue_a)
	var surrender_b := _STATE_HELPERS.has_surrender(queue_b)
	if surrender_a or surrender_b:
		# queue_a corresponds to working.players[0], queue_b to working.players[1].
		# Read the actual player_ids rather than hardcoding 0/1 so non-default
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
	var per_entity := _STATE_HELPERS.distribute_orders(working, queue_a, queue_b)

	# 4. Tick loop — action-slot lockstep per ADR 0004.
	var n_ticks := _STATE_HELPERS.max_queue_length(per_entity)
	# Ensure persistent moves still advance on turns with no submitted
	# orders: if any live entity has a persistent_order, force at least
	# one tick so Phase 3 runs.
	if n_ticks == 0 and _has_any_persistent_order(working):
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

		# Phase 3: persistent move advance for entities with no fresh order.
		MovementSystem.advance_persistent_moves(
			working, per_entity, tick, registry, tunables, events
		)

	# 5. End-of-turn pass.
	EndOfTurnSystem.run(working, registry, tunables, events)
	working.turn_index += 1

	result.new_state = working
	result.events = events
	return result


# Returns true if any live entity has a persistent_order set. Used by
# resolve() to force a tick on turns where no orders were submitted but
# persistent moves still need to advance.
static func _has_any_persistent_order(state: MatchState) -> bool:
	for e in state.entities:
		if e != null and e.current_hp > 0 and e.persistent_order != null:
			return true
	return false
