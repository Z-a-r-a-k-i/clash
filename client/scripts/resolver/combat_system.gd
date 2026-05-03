class_name CombatSystem
extends RefCounted

# Combat system — resolves ATTACK orders. Walks the target priority chain
# per plan/m0/02-tick-based-resolver.md "Target chain resolution":
# 1. For each id in priority list: if alive at this tick, fire at it.
# 2. If list exhausted and not on hold-fire: fire at closest enemy in
#    range (ties broken by id).
# 3. If on hold-fire and chain exhausted: do not fire.
#
# Damage is base damage × any matching AttackModifier multipliers from
# CombatDef.attack_modifiers, × any active buff damage multipliers on
# the attacker. Determinism: target enumeration uses
# entities_sorted_by_id; closest-enemy ties break by id.


static func resolve_attack(
	state: MatchState,
	attacker: Entity,
	order: EntityOrder,
	registry: EntityRegistry,
	_tunables: Tunables,
	events: Array[ResolverEvent]
) -> void:
	if attacker == null or attacker.current_hp <= 0:
		return
	if registry == null:
		return
	var def: EntityDef = registry.get_by_id(attacker.current_def_id)
	if def == null or def.combat == null:
		return  # Not combat-capable; silently skip.
	var combat: CombatDef = def.combat

	var target := _select_target(state, attacker, combat, order, registry)
	if target == null:
		return  # Chain exhausted + hold-fire OR no enemy in range.

	var damage := _compute_damage(combat, target, attacker, registry)
	if damage <= 0:
		# M0: suppress zero-damage attempts; revisit when miss/block
		# semantics arrive.
		return

	target.current_hp = max(0, target.current_hp - damage)

	var damaged := ResolverEvent.new()
	damaged.type = ResolverEvent.Type.ENTITY_DAMAGED
	damaged.actor_id = attacker.id
	damaged.target_id = target.id
	damaged.damage = damage
	damaged.hp_after = target.current_hp
	events.append(damaged)

	if target.current_hp <= 0:
		_destroy_entity(state, target, attacker.id, registry, events)


# ---------- Target selection ----------


# Returns the entity the attacker fires at this tick, or null if no fire.
# Order of resolution:
# 1. Walk the priority chain in order, return first live, in-range,
#    valid-layer enemy.
# 2. If chain exhausted and attacker is NOT on hold-fire: closest enemy
#    in range, ties broken by id.
# 3. If on hold-fire: return null.
static func _select_target(
	state: MatchState,
	attacker: Entity,
	combat: CombatDef,
	order: EntityOrder,
	registry: EntityRegistry
) -> Entity:
	# Priority chain.
	for target_id in order.target_priority_chain:
		var candidate := state.get_entity_by_id(target_id)
		if _is_valid_target(state, attacker, combat, candidate, registry):
			return candidate

	# Hold-fire blocks auto-acquire.
	if attacker.hold_fire:
		return null

	# Closest enemy in range, ties broken by id (entities_sorted_by_id
	# guarantees stable iteration).
	var closest: Entity = null
	var closest_dist := -1
	for candidate in state.entities_sorted_by_id():
		if not _is_valid_target(state, attacker, combat, candidate, registry):
			continue
		var d := _entity_distance(state, attacker, candidate, registry)
		if d < 0:
			continue
		if closest == null or d < closest_dist:
			closest = candidate
			closest_dist = d
	return closest


# Returns true if `candidate` is a fireable target for `attacker`:
# alive, enemy-owned, on a target-able layer, within attack_range.
static func _is_valid_target(
	state: MatchState,
	attacker: Entity,
	combat: CombatDef,
	candidate: Entity,
	registry: EntityRegistry
) -> bool:
	if candidate == null:
		return false
	if candidate.id == attacker.id:
		return false
	if candidate.current_hp <= 0:
		return false
	if candidate.owner_player_id == attacker.owner_player_id:
		return false
	# Layer check. If TargetLayers is empty, the unit can't hit anything
	# (which is a content bug; CombatDef without TargetLayers is useless).
	if combat.target_layers.size() == 0:
		return false
	if not combat.target_layers.has(candidate.current_layer):
		return false
	# Range check.
	var d := _entity_distance(state, attacker, candidate, registry)
	if d < 0:
		return false  # No tile grid or footprints couldn't be derived.
	return d <= combat.attack_range


# Chebyshev distance between two entities' footprints. Returns -1 if
# either entity has no resolvable rect (no def, no footprint, etc.).
# Falls back to def-derived rects when the TileGrid isn't available so
# tests that skip the grid still get correct range checks.
static func _entity_distance(
	state: MatchState, a: Entity, b: Entity, registry: EntityRegistry
) -> int:
	var ra := _resolve_rect(state, a, registry)
	var rb := _resolve_rect(state, b, registry)
	if ra.size == Vector2i.ZERO or rb.size == Vector2i.ZERO:
		return -1
	return TileGrid.distance_between_rects(ra, rb)


# Prefer the TileGrid's recorded rect (it tracks dynamic placement); fall
# back to def + origin when the grid is missing or the entity isn't placed.
static func _resolve_rect(state: MatchState, e: Entity, registry: EntityRegistry) -> Rect2i:
	if state.tile_grid != null:
		var r := state.tile_grid.entity_rect(e.id)
		if r.size != Vector2i.ZERO:
			return r
	if registry == null:
		return Rect2i()
	var def: EntityDef = registry.get_by_id(e.current_def_id)
	if def == null:
		return Rect2i()
	return Rect2i(e.origin, def.footprint)


# ---------- Damage computation ----------


static func _compute_damage(
	combat: CombatDef, target: Entity, attacker: Entity, registry: EntityRegistry
) -> int:
	var dmg := float(combat.damage)
	# Tag-matched attack modifiers. Tags live on EntityDef, not on the
	# runtime Entity, so we resolve through the registry.
	var target_tags: Array[String] = []
	if registry != null:
		var target_def: EntityDef = registry.get_by_id(target.current_def_id)
		if target_def != null:
			target_tags = target_def.tags
	for mod in combat.attack_modifiers:
		if mod == null:
			continue
		if target_tags.has(mod.target_tag):
			dmg *= mod.damage_mult
	# Attacker's active buffs (e.g. stim's damage_mult).
	for buff in attacker.active_buffs:
		if buff != null:
			dmg *= buff.damage_mult
	return int(round(dmg))


# ---------- Death handling ----------


static func _destroy_entity(
	state: MatchState,
	dead: Entity,
	killer_id: int,
	registry: EntityRegistry,
	events: Array[ResolverEvent]
) -> void:
	# Remove from tile grid; the entity's record stays in MatchState with
	# current_hp == 0 so referencing IDs continue to resolve (e.g. for
	# events that arrive in the same turn). The end-of-turn pass or the
	# next turn's distribution can prune dead entities; we don't do it
	# here to avoid invalidating iteration in the caller.
	if state.tile_grid != null:
		state.tile_grid.remove(dead.id)

	# Pop accounting (plan node 05). A dying unit returns its pop_cost.
	# A dying COMPLETED building returns its pop_provides (i.e. pop_cap
	# drops). Buildings still under construction never granted pop_provides
	# in the first place — they only had cost paid up front, which is NOT
	# refunded on death (death isn't cancel).
	var def: EntityDef = registry.get_by_id(dead.current_def_id) if registry != null else null
	if def != null:
		var player := state.get_player(dead.owner_player_id)
		if player != null and def.population != null:
			if def.tags.has("building"):
				if not dead.is_constructing:
					player.pop_cap = max(0, player.pop_cap - def.population.pop_provides)
			else:
				player.pop_used = max(0, player.pop_used - def.population.pop_cost)

	# If a constructing building dies, free its locked worker.
	if dead.is_constructing and dead.construction_worker_id >= 0:
		var worker := state.get_entity_by_id(dead.construction_worker_id)
		if worker != null and worker.locked_to_building_id == dead.id:
			worker.locked_to_building_id = -1
		dead.construction_worker_id = -1
		dead.is_constructing = false

	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.ENTITY_DESTROYED
	ev.actor_id = killer_id
	ev.target_id = dead.id
	events.append(ev)
