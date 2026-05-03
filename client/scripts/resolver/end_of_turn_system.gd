class_name EndOfTurnSystem
extends RefCounted

# End-of-turn pass — fires after the last action tick. Per plan/m0/02:
# - Decrement ability cooldowns; remove entries at 0.
# - Decrement active buff durations; remove expired buffs.
# - Decrement production progress; emit BUILD_COMPLETED for items at 0
#   (M0: stub event only — actual unit-spawn / cost-deduction is plan
#   nodes 04 and 05).
# - Reset moves_used_this_turn (next turn gets a fresh budget).
# - Recompute is_hidden per entity (per ADR 0016).
# - Win check: any player with zero "building"-tagged entities loses.
#   Emit MATCH_ENDED with the surviving player as winner.

const _BUILDING_TAG := "building"


static func run(
	state: MatchState, registry: EntityRegistry, tunables: Tunables, events: Array[ResolverEvent]
) -> void:
	# Decrement / expire per-entity bookkeeping. Dead entities (current_hp
	# <= 0) are skipped: no point ticking cooldowns / buffs on a corpse,
	# and a freshly-destroyed barracks must not still finalize production.
	for entity in state.entities_sorted_by_id():
		if entity.current_hp <= 0:
			continue
		_tick_ability_cooldowns(entity)
		_tick_active_buffs(entity)
		entity.moves_used_this_turn = 0
		_recompute_is_hidden(entity, registry, tunables)

	# Production lifecycle (plan node 05). ProductionSystem ticks active
	# slots, finalizes completions (spawn unit / apply research), and
	# runs a final try-fill so a freshly-emptied slot can install the
	# next queued item the same turn.
	ProductionSystem.advance_queues(state, registry, events)

	# Win check. Resolver short-circuits on surrender before reaching this
	# point, so match_over is always false at entry.
	_check_win_condition(state, registry, events)


# ---------- Per-entity bookkeeping ----------


static func _tick_ability_cooldowns(entity: Entity) -> void:
	# Two pure passes: collect first, mutate after. Writing to a Dictionary
	# while iterating its keys is undefined behaviour in GDScript.
	var updates: Dictionary = {}
	var keys_to_remove: Array[String] = []
	for key in entity.ability_cooldowns:
		var remaining: int = entity.ability_cooldowns[key] - 1
		if remaining <= 0:
			keys_to_remove.append(key)
		else:
			updates[key] = remaining
	for key in updates:
		entity.ability_cooldowns[key] = updates[key]
	for key in keys_to_remove:
		entity.ability_cooldowns.erase(key)


static func _tick_active_buffs(entity: Entity) -> void:
	# Decrement each buff's turns_remaining; drop expired buffs.
	var kept: Array[ActiveBuff] = []
	for buff in entity.active_buffs:
		if buff == null:
			continue
		buff.turns_remaining -= 1
		if buff.turns_remaining > 0:
			kept.append(buff)
	entity.active_buffs = kept


static func _recompute_is_hidden(
	entity: Entity, registry: EntityRegistry, tunables: Tunables
) -> void:
	# Hidden = default_hidden OR layer is in layers_implying_hidden.
	# Detector-cancellation (an allied detector within detection_radius
	# reveals the entity to the OPPONENT) is per-viewer state, not
	# per-entity, and is computed by the per-player visibility mask
	# system that arrives with the rendering layer (plan node 07). The
	# `is_hidden` flag here is the canonical "would this be hidden in the
	# absence of detectors" baseline.
	var default_hidden := false
	if registry != null:
		var def: EntityDef = registry.get_by_id(entity.current_def_id)
		if def != null:
			default_hidden = def.default_hidden
	var layer_hidden := false
	if tunables != null:
		layer_hidden = tunables.layers_implying_hidden.has(entity.current_layer)
	entity.is_hidden = default_hidden or layer_hidden


# ---------- Win check ----------


static func _check_win_condition(
	state: MatchState, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	# Count surviving buildings per player. A "building" is any entity
	# whose def carries the "building" tag (per plan/m0/06 + the
	# generator's tags assignments).
	var buildings_per_player: Dictionary = {}
	for player in state.players:
		if player != null:
			buildings_per_player[player.player_id] = 0
	for entity in state.entities_sorted_by_id():
		if entity == null or entity.current_hp <= 0:
			continue
		var def: EntityDef = registry.get_by_id(entity.current_def_id) if registry != null else null
		if def == null:
			continue
		if not def.tags.has(_BUILDING_TAG):
			continue
		# Neutral / non-player owners (mineral patches, gas geysers, etc.)
		# must not count toward any player's surviving-building total —
		# otherwise a neutral building keeps the match going forever or
		# spuriously creates a survivor.
		if not buildings_per_player.has(entity.owner_player_id):
			continue
		buildings_per_player[entity.owner_player_id] += 1

	# Players with zero buildings have lost. If at least one player has
	# none, the match ends — surviving player wins (or -1 if both lost).
	var losers: Array[int] = []
	var survivors: Array[int] = []
	for player_id in buildings_per_player:
		if buildings_per_player[player_id] == 0:
			losers.append(player_id)
		else:
			survivors.append(player_id)
	if losers.is_empty():
		return  # Match continues.

	state.match_over = true
	if survivors.size() == 1:
		state.winner_player_id = survivors[0]
	else:
		# Both lost — M0 has no draw rule; emit -1.
		state.winner_player_id = -1

	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.MATCH_ENDED
	ev.winner_player_id = state.winner_player_id
	events.append(ev)
