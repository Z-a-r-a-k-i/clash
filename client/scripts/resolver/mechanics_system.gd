class_name MechanicsSystem
extends RefCounted

const ATTACK_WINDOW_PRE_MOVEMENT := "pre_movement"
const ATTACK_WINDOW_POST_MOVEMENT := "post_movement"

const _PATHFINDING := preload("res://scripts/resolver/pathfinding_system.gd")

# ---------- Attack participation ----------
# All queries combine the def's CombatDef with the entity's active
# statuses; resolver systems must route through here instead of reading
# CombatDef or Entity.statuses directly (plan node 14).


static func can_attack(actor: Entity) -> bool:
	if actor == null:
		return false
	for status in actor.statuses:
		if status != null and status.blocks_attack:
			return false
	return true


static func can_move(actor: Entity) -> bool:
	if actor == null:
		return false
	for status in actor.statuses:
		if status != null and status.blocks_move:
			return false
	return true


static func has_attack_window(
	actor: Entity, registry: EntityRegistry, attack_window: String
) -> bool:
	var combat: CombatDef = combat_def_for_entity(actor, registry)
	if combat == null:
		return false
	if not can_attack(actor):
		return false
	if attack_window == ATTACK_WINDOW_PRE_MOVEMENT:
		return _apply_window_overrides(actor, combat.attacks_before_movement, true)
	if attack_window == ATTACK_WINDOW_POST_MOVEMENT:
		return _apply_window_overrides(actor, combat.attacks_after_movement, false)
	return false


static func has_any_attack_window(actor: Entity, registry: EntityRegistry) -> bool:
	return (
		has_attack_window(actor, registry, ATTACK_WINDOW_PRE_MOVEMENT)
		or has_attack_window(actor, registry, ATTACK_WINDOW_POST_MOVEMENT)
	)


static func has_initiative(actor: Entity, registry: EntityRegistry) -> bool:
	var combat: CombatDef = combat_def_for_entity(actor, registry)
	if combat == null:
		return false
	if combat.has_initiative:
		return true
	for status in actor.statuses:
		if status != null and status.grants_initiative:
			return true
	return false


# Statuses apply in array (application) order; the last non-inherit
# override wins.
static func _apply_window_overrides(actor: Entity, def_value: bool, pre_movement: bool) -> bool:
	var value := def_value
	for status in actor.statuses:
		if status == null:
			continue
		var override: int = (
			status.override_attacks_before_movement
			if pre_movement
			else status.override_attacks_after_movement
		)
		if override != StatusEffect.OVERRIDE_INHERIT:
			value = override == StatusEffect.OVERRIDE_ON
	return value


# ---------- Effective combat data ----------


static func effective_damage(actor: Entity, combat: CombatDef) -> int:
	if combat == null:
		return 0
	var damage := combat.damage
	for status in actor.statuses:
		if status != null and status.damage_override >= 0:
			damage = status.damage_override
	return damage


static func effective_attack_range(actor: Entity, combat: CombatDef) -> int:
	if combat == null:
		return 0
	var attack_range := combat.attack_range
	for status in actor.statuses:
		if status != null and status.attack_range_override >= 0:
			attack_range = status.attack_range_override
	return attack_range


# Integer percent scaling with round-half-up; keeps the resolver free of
# float math (ADR 0013).
static func scale_by_pct(value: int, pct: int) -> int:
	return maxi(0, (value * pct + 50) / 100)


static func damage_mult_pct(actor: Entity) -> int:
	var pct := 100
	for status in actor.statuses:
		if status != null and status.damage_mult_pct != 100:
			pct = pct * status.damage_mult_pct / 100
	return maxi(0, pct)


static func combat_def_for_entity(actor: Entity, registry: EntityRegistry) -> CombatDef:
	if actor == null or registry == null:
		return null
	var def: EntityDef = registry.get_by_id(actor.current_def_id)
	if def == null:
		return null
	return def.combat


# ---------- Movement ----------


static func movement_speed_for_entity(actor: Entity, registry: EntityRegistry) -> int:
	if actor == null or registry == null:
		return 0
	if not can_move(actor):
		return 0
	var def: EntityDef = registry.get_by_id(actor.current_def_id)
	if def == null or def.movement == null:
		return 0
	var speed: int = def.movement.speed_tiles_per_turn
	for status in actor.statuses:
		if status != null and status.speed_mult_pct != 100:
			speed = scale_by_pct(speed, status.speed_mult_pct)
	return maxi(0, speed)


static func movement_budget_for_entity(
	actor: Entity, registry: EntityRegistry, fired_before_movement: bool
) -> int:
	var speed: int = movement_speed_for_entity(actor, registry)
	if speed <= 0:
		return 0
	if fired_before_movement:
		var movement: MovementDef = _PATHFINDING.movement_def_for_entity(actor, registry)
		if movement == null:
			return 0
		return int(ceil(float(speed) * movement.post_shot_move_fraction))
	return speed


static func can_spend_movement(actor: Entity, movement_budget_tiles: int) -> bool:
	# Budgets are tile counts; moves_used_this_turn is octile cost units
	# (orthogonal 2 / diagonal 3).
	return (
		actor != null
		and movement_budget_tiles > 0
		and (
			actor.moves_used_this_turn + _PATHFINDING.STEP_COST_ORTHOGONAL
			<= movement_budget_tiles * _PATHFINDING.STEP_COST_ORTHOGONAL
		)
	)
