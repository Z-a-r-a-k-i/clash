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
#   2. Distribute per-entity orders; CANCEL applies now.
#   3. For tick in 1..N:
#        Phase 1: self-target abilities.
#        Phase 2: initiative pre-movement attack batch.
#        Phase 3: normal pre-movement attack batch.
#        Phase 4: every unit's move action (+ gather travel).
#        Phase 5: post-movement attack batch.
#        Phase 6: gather state ticks (direct resource credit).
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
const _MECHANICS_SYSTEM := preload("res://scripts/resolver/mechanics_system.gd")
const _RESOLVER_PROFILER := preload("res://scripts/resolver/resolver_profiler.gd")

const _ATTACK_FILTER_ALL := "all"
const _ATTACK_FILTER_INITIATIVE := "initiative"
const _ATTACK_FILTER_NON_INITIATIVE := "non_initiative"


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

	# 3. Distribute orders into per-entity queues. CANCEL and standing focus
	#    orders apply during distribution.
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
	#    may fire at most once per attack window per resolve.
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
	var fired_attack_windows: Dictionary = {}
	var fired_before_movement_entity_ids: Dictionary = {}
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

		# Phase 2: initiative pre-movement attacks. Batch collection
		# keeps initiative-vs-initiative lethal exchanges simultaneous.
		_apply_attack_opportunities(
			working,
			per_entity,
			tick,
			registry,
			tunables,
			events,
			fired_attack_windows,
			fired_before_movement_entity_ids,
			sorted_entities,
			_MECHANICS_SYSTEM.ATTACK_WINDOW_PRE_MOVEMENT,
			_ATTACK_FILTER_INITIATIVE,
			profile
		)

		# Phase 3: normal pre-movement attacks. Initiative units do not
		# get a second pre-movement opportunity in this later batch.
		_apply_attack_opportunities(
			working,
			per_entity,
			tick,
			registry,
			tunables,
			events,
			fired_attack_windows,
			fired_before_movement_entity_ids,
			sorted_entities,
			_MECHANICS_SYSTEM.ATTACK_WINDOW_PRE_MOVEMENT,
			_ATTACK_FILTER_NON_INITIATIVE,
			profile
		)

		# Phase 4: movement substeps. A MOVE action is one intent, but
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
			var halted_entity_ids: Dictionary = _attack_move_halted_entity_ids(
				working, registry, sorted_entities, per_entity, tick
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
				fired_before_movement_entity_ids,
				halted_entity_ids,
				sorted_entities,
				movement_path_cache,
				profile
			)
			if profile != null:
				profile.add("movement.resolve_substep", profile_step)
			if not moved:
				break

		# Phase 5: post-movement attacks. These do not retroactively
		# reduce movement budget because movement has already resolved.
		_apply_attack_opportunities(
			working,
			per_entity,
			tick,
			registry,
			tunables,
			events,
			fired_attack_windows,
			fired_before_movement_entity_ids,
			sorted_entities,
			_MECHANICS_SYSTEM.ATTACK_WINDOW_POST_MOVEMENT,
			_ATTACK_FILTER_ALL,
			profile
		)

		# Phase 6 extension: gather workers at a source tick yields and
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
	var visibility_by_player: Dictionary = {}
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
		if _standing_attack_order(state, e, registry, true, visibility_by_player) != null:
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
	state: MatchState,
	entity: Entity,
	registry: EntityRegistry,
	require_ready_target: bool,
	visibility_by_player: Dictionary
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
	if not _MECHANICS_SYSTEM.has_any_attack_window(entity, registry):
		return null
	var auto_attack := EntityOrder.new()
	auto_attack.type = EntityOrder.Type.TARGET
	auto_attack.entity_id = entity.id
	if entity.focus_target_entity_id >= 0:
		var focus := state.get_entity_by_id(entity.focus_target_entity_id)
		if (
			focus == null
			or focus.current_hp <= 0
			or focus.owner_player_id < 0
			or focus.owner_player_id == entity.owner_player_id
			or not _is_visible_to_player(
				state, registry, focus, entity.owner_player_id, visibility_by_player
			)
		):
			entity.focus_target_entity_id = -1
		else:
			auto_attack.target_priority_chain = [entity.focus_target_entity_id]
			auto_attack.target_entity_id = entity.focus_target_entity_id
	if (
		require_ready_target
		and not CombatSystem.can_attack_now(
			state, entity, auto_attack, registry, null, visibility_by_player
		)
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
	fired_attack_windows: Dictionary,
	fired_before_movement_entity_ids: Dictionary,
	sorted_entities: Array[Entity],
	attack_window: String,
	attack_filter: String,
	profile: Variant = null
) -> void:
	var attack_intents: Array[Dictionary] = []
	var visibility_by_player: Dictionary = {}
	var fired_entity_ids: Dictionary = _fired_entity_ids_for_window(
		fired_attack_windows, attack_window
	)
	for entity in sorted_entities:
		if entity == null or entity.current_hp <= 0:
			continue
		if _ABILITY_SYSTEM.is_casting(entity):
			continue
		if not _MECHANICS_SYSTEM.has_attack_window(entity, registry, attack_window):
			continue
		if not _matches_attack_filter(entity, registry, attack_filter):
			continue
		if fired_entity_ids.has(entity.id):
			continue
		var attack_lookup_start: int = profile.mark() if profile != null else 0
		var attack_order: EntityOrder = _attack_order_for_opportunity(
			state, per_entity, tick, entity, registry, visibility_by_player
		)
		if profile != null:
			profile.add("tick.attack_order_lookup", attack_lookup_start)
			profile.count("attack_order_lookups")
		if attack_order == null:
			continue
		var attack_intent_start: int = profile.mark() if profile != null else 0
		var intent: Dictionary = CombatSystem.build_attack_intent(
			state, entity, attack_order, registry, tunables, sorted_entities, visibility_by_player
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
		if attack_window == _MECHANICS_SYSTEM.ATTACK_WINDOW_PRE_MOVEMENT:
			fired_before_movement_entity_ids[entity_id] = true


static func _fired_entity_ids_for_window(
	fired_attack_windows: Dictionary, attack_window: String
) -> Dictionary:
	if not fired_attack_windows.has(attack_window):
		fired_attack_windows[attack_window] = {}
	return fired_attack_windows[attack_window]


static func _matches_attack_filter(
	entity: Entity, registry: EntityRegistry, attack_filter: String
) -> bool:
	if attack_filter == _ATTACK_FILTER_ALL:
		return true
	var has_initiative: bool = _MECHANICS_SYSTEM.has_initiative(entity, registry)
	if attack_filter == _ATTACK_FILTER_INITIATIVE:
		return has_initiative
	if attack_filter == _ATTACK_FILTER_NON_INITIATIVE:
		return not has_initiative
	return false


static func _attack_order_for_opportunity(
	state: MatchState,
	per_entity: Dictionary,
	tick: int,
	entity: Entity,
	registry: EntityRegistry,
	visibility_by_player: Dictionary
) -> EntityOrder:
	var queued_order: EntityOrder = _STATE_HELPERS.action_at(per_entity, entity.id, tick)
	if queued_order != null:
		if queued_order.type == EntityOrder.Type.TARGET:
			return queued_order
		if queued_order.type == EntityOrder.Type.ATTACK_MOVE:
			return _attack_order_for_queued_attack_move(
				state, entity, queued_order, registry, visibility_by_player
			)
		if queued_order.type == EntityOrder.Type.MOVE:
			return _standing_attack_order(state, entity, registry, false, visibility_by_player)
	return _standing_attack_order(state, entity, registry, false, visibility_by_player)


static func _attack_order_for_queued_attack_move(
	state: MatchState,
	entity: Entity,
	queued_order: EntityOrder,
	registry: EntityRegistry,
	visibility_by_player: Dictionary
) -> EntityOrder:
	var attack_order: EntityOrder = _standing_attack_order(
		state, entity, registry, false, visibility_by_player
	)
	if attack_order == null:
		return null
	if queued_order == null or queued_order.target_priority_chain.is_empty():
		return attack_order
	attack_order.target_priority_chain = queued_order.target_priority_chain.duplicate()
	attack_order.target_entity_id = attack_order.target_priority_chain[0]
	return attack_order


static func _max_live_movement_speed(state: MatchState, registry: EntityRegistry) -> int:
	if registry == null:
		return 0
	var max_speed := 0
	for e in state.entities_sorted_by_id():
		if e == null or e.current_hp <= 0:
			continue
		max_speed = max(max_speed, MovementSystem.movement_speed_for_entity(e, registry))
	return max_speed


static func _attack_move_halted_entity_ids(
	state: MatchState,
	registry: EntityRegistry,
	sorted_entities: Array[Entity],
	per_entity: Dictionary,
	tick: int
) -> Dictionary:
	var out: Dictionary = {}
	if state == null or registry == null:
		return out
	var visibility_by_player: Dictionary = {}
	for entity in sorted_entities:
		if entity == null or entity.current_hp <= 0:
			continue
		var order := _STATE_HELPERS.action_at(per_entity, entity.id, tick)
		if order == null or order.type != EntityOrder.Type.ATTACK_MOVE:
			continue
		var attack_order: EntityOrder = _attack_order_for_queued_attack_move(
			state, entity, order, registry, visibility_by_player
		)
		if (
			attack_order != null
			and CombatSystem.can_attack_now(
				state, entity, attack_order, registry, sorted_entities, visibility_by_player
			)
		):
			out[entity.id] = true
	return out


static func _is_visible_to_player(
	state: MatchState,
	registry: EntityRegistry,
	entity: Entity,
	player_id: int,
	visibility_by_player: Dictionary
) -> bool:
	if entity == null or player_id < 0:
		return false
	if state == null or state.tile_grid == null:
		return true
	var visibility: VisionSystem.Visibility = null
	if visibility_by_player.has(player_id):
		visibility = visibility_by_player[player_id] as VisionSystem.Visibility
	else:
		visibility = VisionSystem.compute_player_visibility(state, registry, player_id)
		visibility_by_player[player_id] = visibility
	return VisionSystem.is_entity_visible_to_player(entity, state, registry, player_id, visibility)


static func _clear_deprecated_persistent_orders(state: MatchState) -> void:
	if state == null:
		return
	for entity in state.entities_sorted_by_id():
		if entity != null:
			entity.persistent_order = null
