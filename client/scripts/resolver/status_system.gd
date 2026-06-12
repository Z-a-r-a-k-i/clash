class_name StatusSystem
extends RefCounted

# Resolver-owned status application path (plan node 14). Ability effects,
# future attack procs, terrain triggers, and turn hooks all apply or clear
# statuses through here — never by mutating Entity.statuses directly.
# The resolver calls into this system at known phase boundaries; statuses
# never run callbacks from inside combat or movement.


# Applies a clone of `template` to the entity. Reapplying the same
# status_id replaces the existing instance (refreshes duration/values).
static func apply_status(
	entity: Entity, template: StatusEffect, events: Array[ResolverEvent]
) -> void:
	if entity == null or template == null or template.status_id == "":
		return
	clear_status(entity, template.status_id, events, false)
	entity.statuses.append(template.clone())
	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.STATUS_APPLIED
	ev.actor_id = entity.id
	ev.def_id = template.status_id
	events.append(ev)


static func clear_status(
	entity: Entity, status_id: String, events: Array[ResolverEvent], emit_event: bool = true
) -> void:
	if entity == null or status_id == "":
		return
	var kept: Array[StatusEffect] = []
	var removed := false
	for status in entity.statuses:
		if status != null and status.status_id == status_id:
			removed = true
			continue
		kept.append(status)
	if not removed:
		return
	entity.statuses = kept
	if emit_event:
		var ev := ResolverEvent.new()
		ev.type = ResolverEvent.Type.STATUS_CLEARED
		ev.actor_id = entity.id
		ev.def_id = status_id
		events.append(ev)


static func has_status(entity: Entity, status_id: String) -> bool:
	if entity == null:
		return false
	for status in entity.statuses:
		if status != null and status.status_id == status_id:
			return true
	return false


# End-of-turn hook: apply hp deltas (regen capped at max HP; damage can
# destroy through the canonical destroy path), then tick finite durations
# and expire statuses that reach zero. Runs in entity-id order.
static func run_end_of_turn(
	state: MatchState, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	if state == null:
		return
	for entity in state.entities_sorted_by_id():
		if entity == null or entity.current_hp <= 0 or entity.statuses.is_empty():
			continue
		_apply_end_of_turn_hp_delta(state, entity, registry, events)
		if entity.current_hp <= 0:
			continue
		_tick_durations(entity, events)


static func _apply_end_of_turn_hp_delta(
	state: MatchState, entity: Entity, registry: EntityRegistry, events: Array[ResolverEvent]
) -> void:
	var delta := 0
	for status in entity.statuses:
		if status != null:
			delta += status.end_of_turn_hp_delta
	if delta == 0:
		return
	if delta > 0:
		var max_hp := entity.current_hp
		var def: EntityDef = registry.get_by_id(entity.current_def_id) if registry != null else null
		if def != null and def.health != null:
			max_hp = def.health.max_hp
		entity.current_hp = mini(entity.current_hp + delta, max_hp)
		return
	entity.current_hp = maxi(0, entity.current_hp + delta)
	var damaged := ResolverEvent.new()
	damaged.type = ResolverEvent.Type.ENTITY_DAMAGED
	damaged.actor_id = -1
	damaged.target_id = entity.id
	damaged.damage = -delta
	damaged.hp_after = entity.current_hp
	events.append(damaged)
	if entity.current_hp <= 0:
		CombatSystem._destroy_entity(state, entity, -1, registry, events)


static func _tick_durations(entity: Entity, events: Array[ResolverEvent]) -> void:
	var kept: Array[StatusEffect] = []
	var expired_ids: Array[String] = []
	for status in entity.statuses:
		if status == null:
			continue
		if status.duration_turns == StatusEffect.INDEFINITE:
			kept.append(status)
			continue
		status.duration_turns -= 1
		if status.duration_turns > 0:
			kept.append(status)
		else:
			expired_ids.append(status.status_id)
	entity.statuses = kept
	for status_id in expired_ids:
		var ev := ResolverEvent.new()
		ev.type = ResolverEvent.Type.STATUS_CLEARED
		ev.actor_id = entity.id
		ev.def_id = status_id
		events.append(ev)
