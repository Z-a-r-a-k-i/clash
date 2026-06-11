class_name MechanicsSystem
extends RefCounted

const ATTACK_WINDOW_PRE_MOVEMENT := "pre_movement"
const ATTACK_WINDOW_POST_MOVEMENT := "post_movement"

const _PATHFINDING := preload("res://scripts/resolver/pathfinding_system.gd")


static func attack_windows_for_entity(actor: Entity, registry: EntityRegistry) -> Array[String]:
	var combat: CombatDef = combat_def_for_entity(actor, registry)
	var windows: Array[String] = []
	if combat == null:
		return windows
	if combat.attacks_before_movement:
		windows.append(ATTACK_WINDOW_PRE_MOVEMENT)
	if combat.attacks_after_movement:
		windows.append(ATTACK_WINDOW_POST_MOVEMENT)
	return windows


static func has_attack_window(
	actor: Entity, registry: EntityRegistry, attack_window: String
) -> bool:
	var combat: CombatDef = combat_def_for_entity(actor, registry)
	if combat == null:
		return false
	if attack_window == ATTACK_WINDOW_PRE_MOVEMENT:
		return combat.attacks_before_movement
	if attack_window == ATTACK_WINDOW_POST_MOVEMENT:
		return combat.attacks_after_movement
	return false


static func has_any_attack_window(actor: Entity, registry: EntityRegistry) -> bool:
	var combat: CombatDef = combat_def_for_entity(actor, registry)
	if combat == null:
		return false
	return combat.attacks_before_movement or combat.attacks_after_movement


static func has_initiative(actor: Entity, registry: EntityRegistry) -> bool:
	var combat: CombatDef = combat_def_for_entity(actor, registry)
	return combat != null and combat.has_initiative


static func combat_def_for_entity(actor: Entity, registry: EntityRegistry) -> CombatDef:
	if actor == null or registry == null:
		return null
	var def: EntityDef = registry.get_by_id(actor.current_def_id)
	if def == null:
		return null
	return def.combat


static func movement_speed_for_entity(actor: Entity, registry: EntityRegistry) -> int:
	if actor == null or registry == null:
		return 0
	var def: EntityDef = registry.get_by_id(actor.current_def_id)
	if def == null or def.movement == null:
		return 0
	var speed: float = float(def.movement.speed_tiles_per_turn)
	for buff in actor.active_buffs:
		if buff != null:
			speed *= buff.speed_mult
	return max(0, int(round(speed)))


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


static func can_spend_movement(actor: Entity, movement_budget: int) -> bool:
	return actor != null and movement_budget > 0 and actor.moves_used_this_turn < movement_budget
