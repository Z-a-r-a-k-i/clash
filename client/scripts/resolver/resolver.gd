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
#   2. Distribute per-entity orders; HALT_ON_SIGHT_TOGGLE / CANCEL apply now.
#   3. For tick in 1..N:
#        Phase 1: self-target abilities.
#        Phase 2: every combat unit may fire once if it has a target in range.
#        Phase 3: every unit's move action (+ gather travel).
#        Phase 4: gather state ticks (direct resource credit).
#   4. End-of-turn pass: cooldowns, buffs, production progress, is_hidden,
#      win check.
#
# The resolver is split across these files for chunked implementation:
# - resolver.gd          (this) — entry point + tick loop
# - combat_system.gd     — attack resolution + target chains
# - movement_system.gd   — submitted movement
# - gather_system.gd     — worker FSM (move-to-source, gather at source)
# - end_of_turn_system.gd — bookkeeping + win check
# - _state_helpers.gd    — deep-copy + queue distribution

const _STATE_HELPERS := preload("res://scripts/resolver/_state_helpers.gd")
const _ABILITY_SYSTEM := preload("res://scripts/resolver/ability_system.gd")
const _RESOLVER_PROFILER := preload("res://scripts/resolver/resolver_profiler.gd")


static func resolve(
	state: MatchState,
	submit_a: SubmitTurn,
	submit_b: SubmitTurn,
	registry: EntityRegistry,
	tunables: Tunables
) -> ResolveResult:
	var profile: Variant = null
	if _RESOLVER_PROFILER.is_enabled():
		profile = _RESOLVER_PROFILER.new()
		profile.start()
	var profile_step: int = profile.mark() if profile != null else 0
	var result := ResolveResult.new()
	var events: Array[ResolverEvent] = []
	if profile != null:
		profile.count("input.entities", state.entities.size() if state != null else 0)
		profile.count("input.orders_a", submit_a.orders.size() if submit_a != null else 0)
		profile.count("input.orders_b", submit_b.orders.size() if submit_b != null else 0)

	# 1. Working copies. Per the pure-function contract, neither the input
	#    `state` nor the input submissions can be aliased into the result.
	var working: MatchState = state.clone()
	if profile != null:
		profile.add("clone_state", profile_step)
		profile_step = profile.mark()
	var safe_submit_a: SubmitTurn = submit_a.clone() if submit_a != null else null
	var safe_submit_b: SubmitTurn = submit_b.clone() if submit_b != null else null
	if profile != null:
		profile.add("clone_submissions", profile_step)
		profile_step = profile.mark()
	_clear_deprecated_persistent_orders(working)
	if profile != null:
		profile.add("clear_persistent_orders", profile_step)

	# 1a. If the match is already over, return a clone with no further
	#     processing. Prevents re-emitting MATCH_ENDED or mutating terminal
	#     state when the caller hands us a finished state.
	if working.match_over:
		result.new_state = working
		result.events = events
		if profile != null:
			profile.count("early_return.match_over")
			profile.finish()
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
		if profile != null:
			profile.count("early_return.surrender")
			profile.finish()
		return result

	# 3. Distribute orders into per-entity queues. HALT_ON_SIGHT_TOGGLE and
	#    CANCEL apply during distribution (they're mode changes, not
	#    actions).
	var orders_a: Array[EntityOrder] = (
		safe_submit_a.orders if safe_submit_a != null else [] as Array[EntityOrder]
	)
	var orders_b: Array[EntityOrder] = (
		safe_submit_b.orders if safe_submit_b != null else [] as Array[EntityOrder]
	)
	if profile != null:
		profile_step = profile.mark()
	var per_entity := _STATE_HELPERS.distribute_orders(
		working, orders_a, orders_b, registry, events
	)
	if profile != null:
		profile.add("distribute_orders", profile_step)

	# 3a. Idle producers that just received a TRAIN/RESEARCH this turn
	#     should start producing immediately (so build-time is N turns
	#     from order submission, not N+1). Plan node 05.
	if profile != null:
		profile_step = profile.mark()
	ProductionSystem.try_fill_active_slots(working, registry, events)
	if profile != null:
		profile.add("production.try_fill_active_slots", profile_step)

	# 4. Tick loop. Move orders still consume movement budget in a stable
	#    phase, but attacks are no longer queued slots: each combat unit
	#    may fire at most once per resolve.
	if profile != null:
		profile_step = profile.mark()
	var n_ticks := _STATE_HELPERS.max_queue_length(per_entity)
	if profile != null:
		profile.add("max_queue_length", profile_step)
	# Ensure active gather cycles and active production slots still advance
	# on turns with no submitted orders.
	if n_ticks == 0:
		if profile != null:
			profile_step = profile.mark()
		var has_standing_work: bool = _has_standing_work(working, registry, profile)
		if profile != null:
			profile.add("standing_work.total", profile_step)
		if has_standing_work:
			n_ticks = 1
	if profile != null:
		profile.count("ticks", n_ticks)
	var fired_entity_ids: Dictionary = {}
	for tick in n_ticks:
		# Sort once per tick and reuse across phases. Determinism still
		# requires fresh sorts each tick because attacks in the previous
		# tick can have killed entities, and dead entities are still in
		# the array (current_hp == 0) — the sort is stable and id-based,
		# so the order itself doesn't change, but recomputing is cheap and
		# defensive against future mutations of `entities`.
		if profile != null:
			profile_step = profile.mark()
		var sorted_entities := working.entities_sorted_by_id()
		if profile != null:
			profile.add("tick.sort_entities", profile_step)

		# Phase 1: self-target abilities. These consume the action slot
		# before attacks and movement; delayed casts block later slots.
		if profile != null:
			profile_step = profile.mark()
		for entity in sorted_entities:
			var order := _STATE_HELPERS.action_at(per_entity, entity.id, tick)
			if order == null:
				continue
			if order.type == EntityOrder.Type.USE_ABILITY:
				_ABILITY_SYSTEM.resolve_use_ability(working, entity, order, registry, events)
		if profile != null:
			profile.add("tick.abilities", profile_step)

		if profile != null:
			profile_step = profile.mark()
		var move_only_entity_ids: Dictionary = _move_only_entity_ids_at_tick(per_entity, tick)
		if profile != null:
			profile.add("tick.move_only_ids", profile_step)

		# Phase 2: attacks. Stable collection by id followed by one batch
		# application keeps lethal exchanges simultaneous. Attack-move also
		# gets another opportunity after each movement substep, so moving into
		# weapon range can fire this turn while still limiting each entity to
		# one shot per resolve.
		_apply_attack_opportunities(
			working,
			per_entity,
			tick,
			registry,
			tunables,
			events,
			fired_entity_ids,
			move_only_entity_ids,
			sorted_entities,
			profile,
			false
		)

		# Phase 3: movement substeps. A MOVE action is one intent, but
		# speed_tiles_per_turn is a per-turn distance budget. Iterate
		# movement systems until every live mover has had a chance to spend
		# that budget. `moves_used_this_turn` still caps each entity, so
		# this upper bound is safe for mixed-speed rosters.
		var movement_path_cache: Dictionary = {}
		if profile != null:
			profile_step = profile.mark()
		var max_movement_speed: int = _max_live_movement_speed(working, registry)
		if profile != null:
			profile.add("movement.max_live_speed", profile_step)
		for _substep in max_movement_speed:
			if profile != null:
				profile.count("movement.substep_attempts")
				profile_step = profile.mark()
			var halted_entity_ids: Dictionary = _halted_entity_ids(
				working, registry, sorted_entities
			)
			if profile != null:
				profile.add("movement.halted_entity_ids", profile_step)
				profile_step = profile.mark()
			var moved: bool = MovementSystem.resolve_movement_substep(
				working,
				per_entity,
				tick,
				registry,
				tunables,
				events,
				fired_entity_ids,
				halted_entity_ids,
				sorted_entities,
				movement_path_cache,
				profile
			)
			if profile != null:
				profile.add("movement.resolve_substep", profile_step)
			if not moved:
				break
			_apply_attack_opportunities(
				working,
				per_entity,
				tick,
				registry,
				tunables,
				events,
				fired_entity_ids,
				move_only_entity_ids,
				sorted_entities,
				profile,
				true
			)

		# Phase 4 extension: gather workers at a source tick yields and
		# direct resource credit.
		if profile != null:
			profile_step = profile.mark()
		GatherSystem.advance_state_phase(working, registry, tunables, events)
		if profile != null:
			profile.add("tick.gather", profile_step)

	# 5. End-of-turn pass.
	if profile != null:
		profile_step = profile.mark()
	EndOfTurnSystem.run(working, registry, tunables, events)
	if profile != null:
		profile.add("end_of_turn", profile_step)
	working.turn_index += 1

	result.new_state = working
	result.events = events
	if profile != null:
		profile.count("events", events.size())
		profile.finish()
	return result


# Returns true if any live entity has standing work that needs at least
# one tick to advance: a non-IDLE gather phase, active ability cast,
# construction, production, or an automatic attack.
# Used by resolve() to force n_ticks ≥ 1 on turns with no submitted
# orders.
static func _has_standing_work(
	state: MatchState, registry: EntityRegistry, profile: Variant = null
) -> bool:
	for e in state.entities:
		if e == null or e.current_hp <= 0:
			continue
		if e.ability_cast != null:
			if profile != null:
				profile.count("standing_work.ability_cast")
			return true
		if e.gather_state != null and e.gather_state.phase != GatherState.Phase.IDLE:
			if profile != null:
				profile.count("standing_work.gather")
			return true
		if ConstructionSystem.has_pending_build(e):
			if profile != null:
				profile.count("standing_work.pending_build")
			return true
		if e.locked_to_building_id >= 0:
			if profile != null:
				profile.count("standing_work.locked_worker")
			return true
		if e.is_constructing:
			if profile != null:
				profile.count("standing_work.constructing")
			return true
		var attack_lookup_start: int = profile.mark() if profile != null else 0
		if _standing_attack_order(state, e, registry) != null:
			if profile != null:
				profile.add("standing_work.attack_order_lookup", attack_lookup_start)
				profile.count("standing_work.attack_order_lookups")
				profile.count("standing_work.attack")
			return true
		if profile != null:
			profile.add("standing_work.attack_order_lookup", attack_lookup_start)
			profile.count("standing_work.attack_order_lookups")
	return false


static func _standing_attack_order(
	state: MatchState, entity: Entity, registry: EntityRegistry, require_ready_target: bool = true
) -> EntityOrder:
	if entity == null or entity.current_hp <= 0:
		return null
	if entity.gather_state != null and entity.gather_state.phase != GatherState.Phase.IDLE:
		return null
	if (
		ConstructionSystem.has_pending_build(entity)
		or entity.locked_to_building_id >= 0
		or entity.is_constructing
	):
		return null
	if registry == null:
		return null
	var def: EntityDef = registry.get_by_id(entity.current_def_id)
	if def == null or def.combat == null:
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
	if (
		require_ready_target
		and not CombatSystem.can_attack_now(state, entity, auto_attack, registry)
	):
		return null
	return auto_attack


static func _apply_attack_opportunities(
	state: MatchState,
	per_entity: Dictionary,
	tick: int,
	registry: EntityRegistry,
	tunables: Tunables,
	events: Array[ResolverEvent],
	fired_entity_ids: Dictionary,
	move_only_entity_ids: Dictionary,
	sorted_entities: Array[Entity],
	profile: Variant = null,
	post_movement: bool = false
) -> void:
	var attack_intents: Array[Dictionary] = []
	for entity in sorted_entities:
		if entity == null or entity.current_hp <= 0:
			continue
		if _ABILITY_SYSTEM.is_casting(entity):
			continue
		if fired_entity_ids.has(entity.id):
			continue
		if move_only_entity_ids.has(entity.id):
			continue
		var attack_lookup_start: int = profile.mark() if profile != null else 0
		var attack_order: EntityOrder = _attack_order_for_opportunity(
			state, per_entity, tick, entity, registry, post_movement
		)
		if profile != null:
			profile.add("tick.attack_order_lookup", attack_lookup_start)
			profile.count("attack_order_lookups")
		if attack_order == null:
			continue
		var attack_intent_start: int = profile.mark() if profile != null else 0
		var intent: Dictionary = CombatSystem.build_attack_intent(
			state, entity, attack_order, registry, tunables, sorted_entities
		)
		if profile != null:
			profile.add("tick.attack_intent_build", attack_intent_start)
			profile.count("attack_intent_builds")
		if not intent.is_empty():
			attack_intents.append(intent)
	if attack_intents.is_empty():
		return
	var apply_start: int = profile.mark() if profile != null else 0
	var tick_fired_ids: Dictionary = CombatSystem.apply_attack_intents(
		state, attack_intents, registry, events
	)
	if profile != null:
		profile.add("tick.attack_apply", apply_start)
		profile.count("attack_intents", attack_intents.size())
	for entity_id in tick_fired_ids:
		fired_entity_ids[entity_id] = true


static func _attack_order_for_opportunity(
	state: MatchState,
	per_entity: Dictionary,
	tick: int,
	entity: Entity,
	registry: EntityRegistry,
	post_movement: bool
) -> EntityOrder:
	var queued_order: EntityOrder = _STATE_HELPERS.action_at(per_entity, entity.id, tick)
	if queued_order != null:
		if queued_order.type == EntityOrder.Type.MOVE_ONLY:
			return null
		if queued_order.type == EntityOrder.Type.ATTACK_TARGET:
			return queued_order
		if queued_order.type == EntityOrder.Type.ATTACK:
			return queued_order
		if queued_order.type == EntityOrder.Type.MOVE:
			return _standing_attack_order(state, entity, registry, false)
	if post_movement:
		return null
	return _standing_attack_order(state, entity, registry, false)


static func _max_live_movement_speed(state: MatchState, registry: EntityRegistry) -> int:
	if registry == null:
		return 0
	var max_speed := 0
	for e in state.entities_sorted_by_id():
		if e == null or e.current_hp <= 0:
			continue
		max_speed = max(max_speed, MovementSystem.movement_speed_for_entity(e, registry))
	return max_speed


static func _move_only_entity_ids_at_tick(per_entity: Dictionary, tick: int) -> Dictionary:
	var out: Dictionary = {}
	for entity_id in per_entity:
		var order := _STATE_HELPERS.action_at(per_entity, entity_id, tick)
		if order != null and order.type == EntityOrder.Type.MOVE_ONLY:
			out[entity_id] = true
	return out


static func _halted_entity_ids(
	state: MatchState, registry: EntityRegistry, sorted_entities: Array[Entity]
) -> Dictionary:
	var out: Dictionary = {}
	if state == null or registry == null:
		return out
	var visibility_by_player: Dictionary = {}
	for entity in sorted_entities:
		if entity == null or entity.current_hp <= 0:
			continue
		if not entity.halt_on_sight:
			continue
		if _has_visible_enemy(state, registry, sorted_entities, entity, visibility_by_player):
			out[entity.id] = true
	return out


static func _has_visible_enemy(
	state: MatchState,
	registry: EntityRegistry,
	sorted_entities: Array[Entity],
	viewer: Entity,
	visibility_by_player: Dictionary
) -> bool:
	if viewer == null or viewer.owner_player_id < 0:
		return false
	var visibility: VisionSystem.Visibility = visibility_by_player.get(viewer.owner_player_id)
	if visibility == null:
		visibility = VisionSystem.compute_player_visibility(state, registry, viewer.owner_player_id)
		visibility_by_player[viewer.owner_player_id] = visibility
	for candidate in sorted_entities:
		if candidate == null or candidate.current_hp <= 0:
			continue
		if candidate.owner_player_id < 0 or candidate.owner_player_id == viewer.owner_player_id:
			continue
		if VisionSystem.is_entity_visible_to_player(
			candidate, state, registry, viewer.owner_player_id, visibility
		):
			return true
	return false


static func _clear_deprecated_persistent_orders(state: MatchState) -> void:
	if state == null:
		return
	for entity in state.entities_sorted_by_id():
		if entity != null:
			entity.persistent_order = null
