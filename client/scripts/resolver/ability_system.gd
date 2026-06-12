class_name AbilitySystem
extends RefCounted

# Resolves M0 self-target ability orders.

const _ABILITY_CAST_STATE := preload("res://scripts/runtime/ability_cast_state.gd")


static func resolve_use_ability(
	_state: MatchState,
	actor: Entity,
	order: EntityOrder,
	registry: EntityRegistry,
	events: Array[ResolverEvent]
) -> void:
	if actor == null or actor.current_hp <= 0:
		return
	if actor.ability_cast != null:
		_emit_order_rejected(actor.id, "already_casting", events)
		return
	var ability: AbilityDef = _ability_for_entity(actor, order.def_id, registry)
	if ability == null:
		_emit_order_rejected(actor.id, "bad_ability", events)
		return
	if ability.target_type != "self":
		_emit_order_rejected(actor.id, "not_self_target", events)
		return
	if not _research_unlocked(actor, ability, _state):
		_emit_order_rejected(actor.id, "research_required", events)
		return
	if actor.ability_cooldowns.get(ability.id, 0) > 0:
		_emit_order_rejected(actor.id, "cooldown", events)
		return
	var hp_cost: int = _hp_cost(ability)
	if hp_cost < 0:
		_emit_order_rejected(actor.id, "unsupported_cost", events)
		return
	if hp_cost > 0 and actor.current_hp <= hp_cost:
		_emit_order_rejected(actor.id, "insufficient_hp", events)
		return

	actor.current_hp -= hp_cost
	if ability.cooldown_turns > 0:
		# EndOfTurnSystem decrements existing cooldowns later this turn.
		# Store +1 so the post-turn state shows the configured cooldown.
		actor.ability_cooldowns[ability.id] = ability.cooldown_turns + 1
	_emit_ability_used(actor.id, ability.id, events)

	if ability.cast_time_turns > 0:
		var cast: AbilityCastState = _ABILITY_CAST_STATE.new()
		cast.ability_id = ability.id
		cast.turns_remaining = ability.cast_time_turns
		actor.ability_cast = cast
		return

	_apply_effect(actor, ability, registry, events)


static func advance_casts(
	state: MatchState, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	for actor in state.entities_sorted_by_id():
		if actor == null or actor.current_hp <= 0 or actor.ability_cast == null:
			continue
		var cast: AbilityCastState = actor.ability_cast
		var turns_remaining: int = cast.turns_remaining - 1
		cast.turns_remaining = turns_remaining
		if turns_remaining > 0:
			continue
		var ability_id: String = cast.ability_id
		actor.ability_cast = null
		var ability: AbilityDef = _ability_for_entity(actor, ability_id, registry)
		if ability == null:
			_emit_order_rejected(actor.id, "bad_ability", events)
			continue
		_apply_effect(actor, ability, registry, events)


static func is_casting(entity: Entity) -> bool:
	return entity != null and entity.ability_cast != null


static func available_self_abilities(
	state: MatchState, actor: Entity, registry: EntityRegistry
) -> Array[AbilityDef]:
	var out: Array[AbilityDef] = []
	if actor == null or actor.current_hp <= 0 or registry == null or actor.ability_cast != null:
		return out
	var def: EntityDef = registry.get_by_id(_def_id_for_entity(actor))
	if def == null or def.abilities == null:
		return out
	for item in def.abilities.abilities:
		var ability: AbilityDef = item
		if ability == null or ability.id == "" or ability.target_type != "self":
			continue
		if not _research_unlocked(actor, ability, state):
			continue
		if actor.ability_cooldowns.get(ability.id, 0) > 0:
			continue
		var hp_cost: int = _hp_cost(ability)
		if hp_cost < 0:
			continue
		if hp_cost > 0 and actor.current_hp <= hp_cost:
			continue
		if not _status_effect_applicable(actor, ability):
			continue
		out.append(ability)
	return out


# Status toggles only surface when they would change something: apply is
# hidden while the status is active (siege on a sieged tank) and clear is
# hidden while it isn't (unsiege on an unsieged tank).
static func _status_effect_applicable(actor: Entity, ability: AbilityDef) -> bool:
	if ability.effect is StatusApplyEffect:
		var apply_effect: StatusApplyEffect = ability.effect
		if apply_effect.status == null or apply_effect.status.status_id == "":
			return false
		return not StatusSystem.has_status(actor, apply_effect.status.status_id)
	if ability.effect is StatusClearEffect:
		var clear_effect: StatusClearEffect = ability.effect
		if clear_effect.status_id == "":
			return false
		return StatusSystem.has_status(actor, clear_effect.status_id)
	return true


static func _ability_for_entity(
	actor: Entity, ability_id: String, registry: EntityRegistry
) -> AbilityDef:
	if actor == null or registry == null or ability_id == "":
		return null
	var def: EntityDef = registry.get_by_id(_def_id_for_entity(actor))
	if def == null or def.abilities == null:
		return null
	for item in def.abilities.abilities:
		var ability: AbilityDef = item
		if ability != null and ability.id == ability_id:
			return ability
	return null


static func _research_unlocked(actor: Entity, ability: AbilityDef, state: MatchState) -> bool:
	if ability.requires_research_id == "":
		return true
	var player: PlayerState = state.get_player(actor.owner_player_id) if state != null else null
	return player != null and player.unlocked_researches.has(ability.requires_research_id)


static func _hp_cost(ability: AbilityDef) -> int:
	var total: int = 0
	for item in ability.costs:
		var cost: AbilityCost = item
		if cost == null or cost.amount <= 0:
			continue
		if cost.type != "hp":
			return -1
		total += cost.amount
	return total


static func _apply_effect(
	actor: Entity, ability: AbilityDef, _registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	if ability.effect is StatusApplyEffect:
		var apply_effect: StatusApplyEffect = ability.effect
		if apply_effect.status == null or apply_effect.status.status_id == "":
			_emit_order_rejected(actor.id, "bad_status", events)
			return
		var status: StatusEffect = apply_effect.status.clone()
		status.source_ability_id = ability.id
		StatusSystem.apply_status(actor, status, events)
		return
	if ability.effect is StatusClearEffect:
		var clear_effect: StatusClearEffect = ability.effect
		if clear_effect.status_id == "":
			_emit_order_rejected(actor.id, "bad_status", events)
			return
		StatusSystem.clear_status(actor, clear_effect.status_id, events)
		return
	_emit_order_rejected(actor.id, "bad_effect", events)


static func _emit_ability_used(
	actor_id: int, ability_id: String, events: Array[ResolverEvent]
) -> void:
	var ev: ResolverEvent = ResolverEvent.new()
	ev.type = ResolverEvent.Type.ABILITY_USED
	ev.actor_id = actor_id
	ev.def_id = ability_id
	events.append(ev)


static func _emit_order_rejected(
	actor_id: int, reason: String, events: Array[ResolverEvent]
) -> void:
	var ev: ResolverEvent = ResolverEvent.new()
	ev.type = ResolverEvent.Type.ORDER_REJECTED
	ev.actor_id = actor_id
	ev.def_id = reason
	events.append(ev)


static func _def_id_for_entity(entity: Entity) -> String:
	return entity.current_def_id if entity.current_def_id != "" else entity.def_id
