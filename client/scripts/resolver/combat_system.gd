class_name CombatSystem
extends RefCounted

const _MECHANICS_SYSTEM := preload("res://scripts/resolver/mechanics_system.gd")

# Combat system — resolves TARGET focus. Walks the target priority chain
# per plan/m0/02-tick-based-resolver.md "Target chain resolution":
# 1. For each id in priority list: if alive, visible, in-range, and targetable, fire at it.
# 2. If list exhausted: fire at closest visible enemy in range (ties broken by id).
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
) -> bool:
	var intent := build_attack_intent(state, attacker, order, registry, _tunables)
	if intent.is_empty():
		return false
	var fired := apply_attack_intents(state, [intent], registry, events)
	return fired.has(attacker.id)


static func build_attack_intent(
	state: MatchState,
	attacker: Entity,
	order: EntityOrder,
	registry: EntityRegistry,
	_tunables: Tunables,
	sorted_entities: Variant = null,
	visibility_by_player: Variant = null
) -> Dictionary:
	if attacker == null or attacker.current_hp <= 0:
		return {}
	if registry == null:
		return {}
	var def: EntityDef = registry.get_by_id(attacker.current_def_id)
	if def == null or def.combat == null:
		return {}  # Not combat-capable; silently skip.
	var combat: CombatDef = def.combat
	var target := _select_target(
		state, attacker, combat, order, registry, sorted_entities, visibility_by_player
	)
	if target == null:
		return {}
	var damage := _compute_damage(combat, target, attacker, registry)
	if damage <= 0:
		# M0: suppress zero-damage attempts; revisit when miss/block
		# semantics arrive.
		return {}
	return {"actor_id": attacker.id, "target_id": target.id, "damage": damage}


static func apply_attack_intents(
	state: MatchState,
	intents: Array,
	registry: EntityRegistry,
	events: Array[ResolverEvent],
	context: Variant = null
) -> Dictionary:
	var fired_entity_ids: Dictionary = {}
	var live_intents: Array[Dictionary] = []
	for item in intents:
		var intent: Dictionary = item
		var actor_id: int = intent.get("actor_id", -1)
		var target_id: int = intent.get("target_id", -1)
		var damage: int = intent.get("damage", 0)
		if actor_id < 0 or target_id < 0 or damage <= 0:
			continue
		var actor := state.get_entity_by_id(actor_id)
		var target := state.get_entity_by_id(target_id)
		if actor == null or target == null:
			continue
		live_intents.append(intent)
	live_intents.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["actor_id"]) < int(b["actor_id"])
	)

	var killer_by_target: Dictionary = {}
	var destroyed_targets: Dictionary = {}
	for intent in live_intents:
		var actor_id: int = intent["actor_id"]
		var target_id: int = intent["target_id"]
		var damage: int = intent["damage"]
		var target := state.get_entity_by_id(target_id)
		if target == null:
			continue
		target.current_hp = max(0, target.current_hp - damage)
		fired_entity_ids[actor_id] = true

		var damaged := ResolverEvent.new()
		damaged.type = ResolverEvent.Type.ENTITY_DAMAGED
		damaged.actor_id = actor_id
		damaged.target_id = target_id
		damaged.damage = damage
		damaged.hp_after = target.current_hp
		events.append(damaged)

		if target.current_hp <= 0:
			destroyed_targets[target_id] = true
			if not killer_by_target.has(target_id):
				killer_by_target[target_id] = actor_id

		# Splash (plan m1/06 wave 3): sieged attackers damage everything
		# around the target — friendly fire included — at a falloff.
		var splash: Dictionary = _MECHANICS_SYSTEM.splash_for(state.get_entity_by_id(actor_id))
		if not splash.is_empty() and state.tile_grid != null:
			var target_rect: Rect2i = state.tile_grid.entity_rect(target_id)
			var splash_damage: int = _MECHANICS_SYSTEM.scale_by_pct(
				damage, int(splash["falloff_pct"])
			)
			if target_rect.size != Vector2i.ZERO and splash_damage > 0:
				for other in state.entities_sorted_by_id():
					if other.id == target_id or other.id == actor_id:
						continue
					if other.current_hp <= 0:
						continue
					var other_def: EntityDef = registry.get_by_id(other.current_def_id)
					if other_def == null or other_def.resource_source != null:
						continue
					var other_rect: Rect2i = state.tile_grid.entity_rect(other.id)
					if other_rect.size == Vector2i.ZERO:
						continue
					if (
						TileGrid.distance_between_rects(target_rect, other_rect)
						> int(splash["radius"])
					):
						continue
					other.current_hp = max(0, other.current_hp - splash_damage)
					var splashed := ResolverEvent.new()
					splashed.type = ResolverEvent.Type.ENTITY_DAMAGED
					splashed.actor_id = actor_id
					splashed.target_id = other.id
					splashed.damage = splash_damage
					splashed.hp_after = other.current_hp
					events.append(splashed)
					if other.current_hp <= 0:
						destroyed_targets[other.id] = true
						if not killer_by_target.has(other.id):
							killer_by_target[other.id] = actor_id

	var destroyed_ids: Array[int] = []
	for target_id in destroyed_targets.keys():
		destroyed_ids.append(target_id)
	destroyed_ids.sort()
	for target_id in destroyed_ids:
		var dead := state.get_entity_by_id(target_id)
		if dead != null and dead.current_hp <= 0:
			_destroy_entity(
				state, dead, killer_by_target.get(target_id, -1), registry, events, context
			)
	return fired_entity_ids


static func can_attack_now(
	state: MatchState,
	attacker: Entity,
	order: EntityOrder,
	registry: EntityRegistry,
	sorted_entities: Variant = null,
	visibility_by_player: Variant = null
) -> bool:
	if attacker == null or attacker.current_hp <= 0:
		return false
	if registry == null:
		return false
	var def: EntityDef = registry.get_by_id(attacker.current_def_id)
	if def == null or def.combat == null:
		return false
	return (
		_select_target(
			state, attacker, def.combat, order, registry, sorted_entities, visibility_by_player
		)
		!= null
	)


# ---------- Target selection ----------


# Returns the entity the attacker fires at this tick, or null if no fire.
# Order of resolution:
# 1. Walk the priority chain in order, return first live, visible, in-range,
#    valid-layer enemy.
# 2. If chain exhausted: closest visible enemy in range, ties broken by id.
static func _select_target(
	state: MatchState,
	attacker: Entity,
	combat: CombatDef,
	order: EntityOrder,
	registry: EntityRegistry,
	sorted_entities: Variant = null,
	visibility_by_player: Variant = null
) -> Entity:
	var attacker_rect := _resolve_rect(state, attacker, registry)
	if attacker_rect.size == Vector2i.ZERO:
		return null
	var visibility: VisionSystem.Visibility = null
	if attacker.owner_player_id >= 0:
		if visibility_by_player is ResolveContext:
			visibility = visibility_by_player.visibility_for(attacker.owner_player_id)
		else:
			var cache: Dictionary = (
				visibility_by_player if visibility_by_player is Dictionary else {}
			)
			if cache.has(attacker.owner_player_id):
				visibility = cache[attacker.owner_player_id] as VisionSystem.Visibility
			else:
				visibility = VisionSystem.compute_player_visibility(
					state, registry, attacker.owner_player_id
				)
				if visibility_by_player is Dictionary:
					cache[attacker.owner_player_id] = visibility

	var attack_range: int = _MECHANICS_SYSTEM.effective_attack_range(attacker, combat)

	# Priority chain.
	if order != null:
		for target_id in order.target_priority_chain:
			var candidate := state.get_entity_by_id(target_id)
			if not _is_targetable(attacker, combat, candidate):
				continue
			var d := _entity_distance_from_rect(state, attacker_rect, candidate, registry)
			if d >= 0 and d <= attack_range:
				if _is_visible_to_attacker(state, attacker, candidate, registry, visibility):
					return candidate

	# Closest enemy in range, ties broken by id (entities_sorted_by_id
	# guarantees stable iteration).
	var closest: Entity = null
	var closest_dist := -1
	var candidates: Array = (
		sorted_entities if sorted_entities is Array else state.entities_sorted_by_id()
	)
	for item in candidates:
		var candidate: Entity = item as Entity
		if not _is_targetable(attacker, combat, candidate):
			continue
		var d := _entity_distance_from_rect(state, attacker_rect, candidate, registry)
		if d < 0 or d > attack_range:
			continue
		if not _is_visible_to_attacker(state, attacker, candidate, registry, visibility):
			continue
		if closest == null or d < closest_dist or (d == closest_dist and candidate.id < closest.id):
			closest = candidate
			closest_dist = d
	return closest


static func _is_visible_to_attacker(
	state: MatchState,
	attacker: Entity,
	candidate: Entity,
	registry: EntityRegistry,
	visibility: VisionSystem.Visibility
) -> bool:
	if attacker == null or candidate == null or attacker.owner_player_id < 0:
		return false
	if state == null or state.tile_grid == null:
		return true
	return VisionSystem.is_entity_visible_to_player(
		candidate, state, registry, attacker.owner_player_id, visibility
	)


static func _is_targetable(attacker: Entity, combat: CombatDef, candidate: Entity) -> bool:
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
	return combat.target_layers.has(candidate.current_layer)


# Returns true if `candidate` is a fireable target for `attacker`:
# alive, enemy-owned, on a target-able layer, within attack_range.
static func _is_valid_target(
	state: MatchState,
	attacker: Entity,
	combat: CombatDef,
	candidate: Entity,
	registry: EntityRegistry
) -> bool:
	if not _is_targetable(attacker, combat, candidate):
		return false
	# Range check.
	var d := _entity_distance(state, attacker, candidate, registry)
	if d < 0:
		return false  # No tile grid or footprints couldn't be derived.
	return d <= _MECHANICS_SYSTEM.effective_attack_range(attacker, combat)


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


static func _entity_distance_from_rect(
	state: MatchState, a_rect: Rect2i, b: Entity, registry: EntityRegistry
) -> int:
	var rb := _resolve_rect(state, b, registry)
	if rb.size == Vector2i.ZERO:
		return -1
	return TileGrid.distance_between_rects(a_rect, rb)


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


# UI-only entry point: what one attack from `attacker` would deal to
# `target` right now (def damage + status overrides + tag modifiers +
# status multipliers). Pure query; never mutates state.
static func preview_damage(attacker: Entity, target: Entity, registry: EntityRegistry) -> int:
	if attacker == null or target == null:
		return 0
	var combat: CombatDef = _MECHANICS_SYSTEM.combat_def_for_entity(attacker, registry)
	if combat == null:
		return 0
	return _compute_damage(combat, target, attacker, registry)


static func _compute_damage(
	combat: CombatDef, target: Entity, attacker: Entity, registry: EntityRegistry
) -> int:
	# Integer percent math throughout (ADR 0013 — no float in the resolver).
	var dmg: int = _MECHANICS_SYSTEM.effective_damage(attacker, combat)
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
			dmg = _MECHANICS_SYSTEM.scale_by_pct(dmg, mod.damage_mult_pct)
	# Attacker's status damage multipliers.
	var status_pct: int = _MECHANICS_SYSTEM.damage_mult_pct(attacker)
	if status_pct != 100:
		dmg = _MECHANICS_SYSTEM.scale_by_pct(dmg, status_pct)
	return dmg


# ---------- Death handling ----------


static func _destroy_entity(
	state: MatchState,
	dead: Entity,
	killer_id: int,
	registry: EntityRegistry,
	events: Array[ResolverEvent],
	context: Variant = null
) -> void:
	# Remove from tile grid; the entity's record stays in MatchState with
	# current_hp == 0 so referencing IDs continue to resolve (e.g. for
	# events that arrive in the same turn). The end-of-turn pass or the
	# next turn's distribution can prune dead entities; we don't do it
	# here to avoid invalidating iteration in the caller.
	if state.tile_grid != null:
		var dead_rect: Rect2i = state.tile_grid.entity_rect(dead.id)
		state.tile_grid.remove(dead.id)
		if context is ResolveContext:
			context.on_entity_removed(
				dead.id,
				PathfindingSystem.layer_for_entity(dead, registry),
				dead_rect,
				dead.owner_player_id
			)

	# Pop accounting (plan node 05). A dying unit returns its pop_cost.
	# Pop cap is a fixed match rule (Tunables.pop_cap); buildings never
	# grant or remove supply, so building death leaves pop_cap untouched.
	var def: EntityDef = registry.get_by_id(dead.current_def_id) if registry != null else null
	if def != null:
		var player := state.get_player(dead.owner_player_id)
		if player != null and def.population != null:
			if not def.tags.has("building"):
				player.pop_used = max(0, player.pop_used - def.population.pop_cost)

	# If a worker dies before its build site exists, cancel the reserved
	# build and refund the reservation because there is no constructed
	# entity to destroy.
	if ConstructionSystem.has_pending_build(dead):
		ConstructionSystem.cancel_pending_build(state, dead, registry, events)

	# If a constructing building dies, free its locked worker.
	if dead.is_constructing and dead.construction_worker_id >= 0:
		var worker := state.get_entity_by_id(dead.construction_worker_id)
		if worker != null and worker.locked_to_building_id == dead.id:
			worker.locked_to_building_id = -1
		dead.construction_worker_id = -1
		dead.is_constructing = false

	# A producer dying with an active production slot leaks pop_used
	# unless we refund the reservation. Minerals/gas paid into the slot
	# are NOT refunded (death isn't cancel), but pop is structural — the
	# unit will never spawn, so the reservation has to come back or
	# pop_cap erodes monotonically across the match.
	if dead.production_state != null and not dead.production_state.active.is_empty():
		var paid_pop: int = dead.production_state.active.get(ProductionState.KEY_PAID_POP, 0)
		if paid_pop > 0:
			var owner := state.get_player(dead.owner_player_id)
			if owner != null:
				owner.pop_used = max(0, owner.pop_used - paid_pop)

	for entity in state.entities:
		if entity != null and entity.focus_target_entity_id == dead.id:
			entity.focus_target_entity_id = -1

	var ev := ResolverEvent.new()
	ev.type = ResolverEvent.Type.ENTITY_DESTROYED
	ev.actor_id = killer_id
	ev.target_id = dead.id
	events.append(ev)
