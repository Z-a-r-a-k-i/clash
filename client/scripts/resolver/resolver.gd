class_name Resolver
extends RefCounted

# Pure-function turn resolver. Per ADR 0013 (deterministic, no RNG).
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
#        Phase 1: self-target abilities.
#        Phase 2: every combat unit may fire once if it has a target in range.
#        Phase 3: every unit's move action (+ gather travel).
#        Phase 4: persistent move advance + gather state ticks (yield/deposit).
#   4. End-of-turn pass: cooldowns, buffs, production progress, is_hidden,
#      win check.
#
# The resolver is split across these files for chunked implementation:
# - resolver.gd          (this) — entry point + tick loop
# - combat_system.gd     — attack resolution + target chains
# - movement_system.gd   — move + persistent movement
# - gather_system.gd     — worker FSM (move-to-source, gather, deposit)
# - end_of_turn_system.gd — bookkeeping + win check
# - _state_helpers.gd    — deep-copy + queue distribution

const _STATE_HELPERS := preload("res://scripts/resolver/_state_helpers.gd")
const _ABILITY_SYSTEM := preload("res://scripts/resolver/ability_system.gd")


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
	#    a fresh MOVE gets stashed into Entity.persistent_order
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
	var per_entity := _STATE_HELPERS.distribute_orders(
		working, orders_a, orders_b, registry, events
	)

	# 3a. Idle producers that just received a TRAIN/RESEARCH this turn
	#     should start producing immediately (so build-time is N turns
	#     from order submission, not N+1). Plan node 05.
	ProductionSystem.try_fill_active_slots(working, registry, events)

	# 4. Tick loop. Move orders still consume movement budget in a stable
	#    phase, but attacks are no longer queued slots: each combat unit
	#    may fire at most once per resolve.
	var n_ticks := _STATE_HELPERS.max_queue_length(per_entity)
	# Ensure persistent moves, active gather cycles, and active production
	# slots still advance on turns with no submitted orders.
	if n_ticks == 0 and _has_standing_work(working, registry):
		n_ticks = 1
	var attacked_entity_ids: Dictionary = {}
	var fresh_move_entity_ids: Dictionary = _fresh_move_entity_ids(per_entity)
	for tick in n_ticks:
		# Sort once per tick and reuse across phases. Determinism still
		# requires fresh sorts each tick because attacks in the previous
		# tick can have killed entities, and dead entities are still in
		# the array (current_hp == 0) — the sort is stable and id-based,
		# so the order itself doesn't change, but recomputing is cheap and
		# defensive against future mutations of `entities`.
		var sorted_entities := working.entities_sorted_by_id()

		# Phase 1: self-target abilities. These consume the action slot
		# before attacks and movement; delayed casts block later slots.
		for entity in sorted_entities:
			var order := _STATE_HELPERS.action_at(per_entity, entity.id, tick)
			if order == null:
				continue
			if order.type == EntityOrder.Type.USE_ABILITY:
				_ABILITY_SYSTEM.resolve_use_ability(working, entity, order, registry, events)

		# Phase 2: attacks. Stable iteration by id for determinism. This
		# is independent from movement: a unit can shoot and still spend
		# its move budget later in the same resolve.
		for entity in sorted_entities:
			if _ABILITY_SYSTEM.is_casting(entity):
				continue
			if attacked_entity_ids.has(entity.id):
				continue
			var attack_order := _standing_attack_order(working, entity, registry)
			if attack_order == null:
				continue
			if CombatSystem.resolve_attack(
				working, entity, attack_order, registry, tunables, events
			):
				attacked_entity_ids[entity.id] = true

		# Phase 3: movement substeps. A MOVE action is one intent, but
		# speed_tiles_per_turn is a per-turn distance budget. Iterate
		# movement systems until every live mover has had a chance to spend
		# that budget. `moves_used_this_turn` still caps each entity, so
		# this upper bound is safe for mixed-speed rosters.
		for _substep in _max_live_movement_speed(working, registry):
			for entity in sorted_entities:
				if _ABILITY_SYSTEM.is_casting(entity):
					continue
				var order := _STATE_HELPERS.action_at(per_entity, entity.id, tick)
				if order == null:
					continue
				if order.type == EntityOrder.Type.MOVE:
					MovementSystem.resolve_move(working, entity, order, registry, tunables, events)

			# Gather workers that are walking to a source or a deposit sink
			# consume the same movement budget as explicit MOVE orders.
			GatherSystem.advance_move_phase(working, per_entity, tick, registry, tunables, events)

			# Workers locked to an in-progress build also consume the same
			# movement budget while walking toward the building's rect.
			ConstructionSystem.advance_move_phase(
				working, per_entity, tick, registry, tunables, events
			)

			# Persistent move advance for entities with no fresh order.
			MovementSystem.advance_persistent_moves(
				working, per_entity, tick, registry, tunables, events
			)

		# Phase 4 extension: gather workers at a source / sink tick yields
		# and deposits.
		GatherSystem.advance_state_phase(working, registry, tunables, events)

	_clear_attacked_persistent_moves(working, attacked_entity_ids, fresh_move_entity_ids)

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
static func _has_standing_work(state: MatchState, registry: EntityRegistry) -> bool:
	for e in state.entities:
		if e == null or e.current_hp <= 0:
			continue
		if e.persistent_order != null:
			return true
		if e.ability_cast != null:
			return true
		if e.gather_state != null and e.gather_state.phase != GatherState.Phase.IDLE:
			return true
		if e.locked_to_building_id >= 0:
			return true
		if e.is_constructing:
			return true
		if _standing_attack_order(state, e, registry) != null:
			return true
	return false


static func _standing_attack_order(
	state: MatchState, entity: Entity, registry: EntityRegistry
) -> EntityOrder:
	if entity == null or entity.current_hp <= 0:
		return null
	if entity.gather_state != null and entity.gather_state.phase != GatherState.Phase.IDLE:
		return null
	if entity.locked_to_building_id >= 0 or entity.is_constructing:
		return null
	var auto_attack := EntityOrder.new()
	auto_attack.type = EntityOrder.Type.ATTACK
	auto_attack.entity_id = entity.id
	if entity.focus_target_entity_id >= 0:
		var focus := state.get_entity_by_id(entity.focus_target_entity_id)
		if (
			focus == null
			or focus.current_hp <= 0
			or focus.owner_player_id < 0
			or focus.owner_player_id == entity.owner_player_id
		):
			entity.focus_target_entity_id = -1
		else:
			auto_attack.target_priority_chain = [entity.focus_target_entity_id]
	if CombatSystem.can_attack_now(state, entity, auto_attack, registry):
		return auto_attack
	return null


static func _max_live_movement_speed(state: MatchState, registry: EntityRegistry) -> int:
	if registry == null:
		return 0
	var max_speed := 0
	for e in state.entities_sorted_by_id():
		if e == null or e.current_hp <= 0:
			continue
		max_speed = max(max_speed, MovementSystem.movement_speed_for_entity(e, registry))
	return max_speed


static func _fresh_move_entity_ids(per_entity: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for entity_id in per_entity:
		var queue: Array = per_entity[entity_id]
		for order in queue:
			var entity_order: EntityOrder = order
			if entity_order != null and entity_order.type == EntityOrder.Type.MOVE:
				out[entity_order.entity_id] = true
				break
	return out


static func _clear_attacked_persistent_moves(
	state: MatchState, attacked_entity_ids: Dictionary, fresh_move_entity_ids: Dictionary
) -> void:
	for entity_id in attacked_entity_ids:
		if fresh_move_entity_ids.has(entity_id):
			continue
		var entity := state.get_entity_by_id(entity_id)
		if entity != null:
			entity.persistent_order = null
