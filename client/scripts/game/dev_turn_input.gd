@tool
class_name DevTurnInput
extends RefCounted

# Dev-only turn input state for plan 07b2. Owns selection and pending
# SubmitTurn resources; it does not mutate MatchState or call the resolver.

const _ABILITY_SYSTEM := preload("res://scripts/resolver/ability_system.gd")

var _state: MatchState = null
var _registry: EntityRegistry = null
var _active_player_id: int = 0
var _selected_entity_id: int = -1
var _submissions: Dictionary[int, SubmitTurn] = {}
var _status_message: String = ""


func _init() -> void:
	clear_submissions()


func bind_context(state: MatchState, registry: EntityRegistry) -> void:
	_state = state
	_registry = registry
	_ensure_submit_turn(0)
	_ensure_submit_turn(1)
	if _selected_entity_id >= 0 and not _is_selectable(_selected_entity_id):
		_selected_entity_id = -1


func set_active_player_id(player_id: int) -> void:
	_active_player_id = player_id
	_ensure_submit_turn(player_id)
	if _selected_entity_id >= 0 and not _is_selectable(_selected_entity_id):
		_selected_entity_id = -1


func active_player_id() -> int:
	return _active_player_id


func selected_entity_id() -> int:
	return _selected_entity_id


func status_message() -> String:
	return _status_message


func select_entity(entity_id: int) -> bool:
	if not _is_selectable(entity_id):
		_selected_entity_id = -1
		_status_message = "Select an active P%d entity." % _active_player_id
		return false
	_selected_entity_id = entity_id
	var entity: Entity = _state.get_entity_by_id(entity_id)
	_status_message = "Selected %s #%d" % [_def_id_for_entity(entity), entity_id]
	return true


func clear_selection() -> void:
	_selected_entity_id = -1


func issue_move(target_tile: Vector2i) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select a unit before issuing MOVE."
		return false
	if _state == null or _state.tile_grid == null or not _state.tile_grid.is_in_bounds(target_tile):
		_status_message = "MOVE target is outside the map."
		return false
	var def: EntityDef = _def_for_entity(actor)
	if def == null or def.movement == null or def.movement.speed_tiles_per_turn <= 0:
		_status_message = "%s cannot move." % _def_id_for_entity(actor)
		return false
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.MOVE
	order.entity_id = actor.id
	order.target_tile = target_tile
	_append_order(order)
	_status_message = "Queued MOVE for #%d to %s." % [actor.id, str(target_tile)]
	return true


func issue_attack(target_entity_id: int) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select a unit before issuing ATTACK."
		return false
	var target: Entity = _live_enemy_entity(target_entity_id)
	if target == null:
		_status_message = "ATTACK needs a live enemy target."
		return false
	var def: EntityDef = _def_for_entity(actor)
	if def == null or def.combat == null or def.combat.damage <= 0:
		_status_message = "%s cannot attack." % _def_id_for_entity(actor)
		return false
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.ATTACK
	order.entity_id = actor.id
	order.target_priority_chain = [target_entity_id]
	_append_order(order)
	_status_message = "Queued ATTACK for #%d against #%d." % [actor.id, target_entity_id]
	return true


func issue_attack_target(target_entity_id: int) -> bool:
	var target: Entity = _live_enemy_entity(target_entity_id)
	if target == null:
		_status_message = "Attack target needs a live enemy target."
		return false
	return issue_attack(target_entity_id)


func issue_gather(target_entity_id: int) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select a worker before issuing GATHER."
		return false
	var actor_def: EntityDef = _def_for_entity(actor)
	if actor_def == null or actor_def.gather == null or actor.gather_state == null:
		_status_message = "%s cannot gather." % _def_id_for_entity(actor)
		return false
	var target: Entity = _gather_target_entity(target_entity_id)
	var target_def: EntityDef = _def_for_entity(target)
	if target == null or not _is_gather_target(target, target_def):
		_status_message = "GATHER needs a resource source or refinery target."
		return false
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.GATHER
	order.entity_id = actor.id
	order.target_entity_id = target_entity_id
	_append_order(order)
	_status_message = "Queued GATHER for #%d from #%d." % [actor.id, target_entity_id]
	return true


func issue_attack_move(target_tile: Vector2i, target_entity_id: int = -1) -> bool:
	var target_ok := true
	if target_entity_id >= 0:
		target_ok = issue_attack_target(target_entity_id)
	if not target_ok:
		return false
	return issue_move(target_tile)


func issue_hold_fire_toggle(enabled: bool) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select a combat entity before issuing HOLD_FIRE_TOGGLE."
		return false
	if not can_issue_hold_fire_toggle():
		_status_message = "%s cannot use hold fire." % _def_id_for_entity(actor)
		return false
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.HOLD_FIRE_TOGGLE
	order.entity_id = actor.id
	order.hold_fire = enabled
	_append_order(order)
	_status_message = "Queued HOLD_FIRE_TOGGLE for #%d." % actor.id
	return true


func issue_build(def_id: String, target_tile: Vector2i, target_entity_id: int = -1) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select a builder before issuing BUILD."
		return false
	if _state == null or _state.tile_grid == null:
		_status_message = "BUILD needs a loaded map."
		return false
	if not build_option_ids().has(def_id):
		_status_message = "%s cannot build '%s'." % [_def_id_for_entity(actor), def_id]
		return false
	var build_def: EntityDef = _registry.get_by_id(def_id) if _registry != null else null
	var footprint: Vector2i = build_def.footprint if build_def != null else Vector2i.ONE
	var rect: Rect2i = Rect2i(
		target_tile, footprint if footprint != Vector2i.ZERO else Vector2i.ONE
	)
	if not _state.tile_grid.is_rect_in_bounds(rect):
		_status_message = "BUILD target is outside the map."
		return false
	if target_entity_id < 0:
		var affordability_message := _build_affordability_message(def_id)
		if affordability_message != "":
			_status_message = affordability_message
			return false
		var placement_message := _build_placement_message(build_def, rect)
		if placement_message != "":
			_status_message = placement_message
			return false
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.BUILD
	order.entity_id = actor.id
	order.def_id = def_id
	order.target_tile = target_tile
	order.target_entity_id = target_entity_id
	_append_order(order)
	_status_message = "Queued BUILD %s for #%d at %s." % [def_id, actor.id, str(target_tile)]
	return true


func issue_train(def_id: String) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select a producer before issuing TRAIN."
		return false
	if not train_option_ids().has(def_id):
		_status_message = "%s cannot train '%s'." % [_def_id_for_entity(actor), def_id]
		return false
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.TRAIN
	order.entity_id = actor.id
	order.def_id = def_id
	_append_order(order)
	_status_message = "Queued TRAIN %s for #%d." % [def_id, actor.id]
	return true


func issue_research(def_id: String) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select a producer before issuing RESEARCH."
		return false
	if not research_option_ids().has(def_id):
		_status_message = "%s cannot research '%s'." % [_def_id_for_entity(actor), def_id]
		return false
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.RESEARCH
	order.entity_id = actor.id
	order.def_id = def_id
	_append_order(order)
	_status_message = "Queued RESEARCH %s for #%d." % [def_id, actor.id]
	return true


func issue_ability(ability_id: String) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select a unit before issuing USE_ABILITY."
		return false
	if not ability_option_ids().has(ability_id):
		_status_message = "%s cannot use '%s'." % [_def_id_for_entity(actor), ability_id]
		return false
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.USE_ABILITY
	order.entity_id = actor.id
	order.def_id = ability_id
	_append_order(order)
	_status_message = "Queued USE_ABILITY %s for #%d." % [ability_id, actor.id]
	return true


func issue_cancel(cancel_index: int = -1) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select an entity before issuing CANCEL."
		return false
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.CANCEL
	order.entity_id = actor.id
	order.cancel_index = cancel_index
	_append_order(order)
	_status_message = "Queued CANCEL(%d) for #%d." % [cancel_index, actor.id]
	return true


func surrender_active_player() -> void:
	_submission_for(_active_player_id).surrender = true
	_status_message = "P%d will surrender on resolve." % _active_player_id


func clear_submissions() -> void:
	_submissions.clear()
	_submissions[0] = SubmitTurn.new()
	_submissions[1] = SubmitTurn.new()
	_status_message = "Queues cleared."


func submit_for_player(player_id: int) -> SubmitTurn:
	return _submission_for(player_id)


func queued_order_count(player_id: int) -> int:
	return _submission_for(player_id).orders.size()


func selected_entity_label() -> String:
	var actor: Entity = _selected_entity()
	if actor == null:
		return "none"
	var def_id: String = _def_id_for_entity(actor)
	return label_for_entity_def_id(def_id)


func selected_hold_fire() -> bool:
	var actor: Entity = _selected_entity()
	return actor != null and actor.hold_fire


func can_issue_move() -> bool:
	var actor: Entity = _selected_entity()
	var def: EntityDef = _def_for_entity(actor)
	return def != null and def.movement != null and def.movement.speed_tiles_per_turn > 0


func can_issue_attack_target() -> bool:
	var actor: Entity = _selected_entity()
	var def: EntityDef = _def_for_entity(actor)
	return def != null and def.combat != null and def.combat.damage > 0


func can_issue_attack_move() -> bool:
	return can_issue_move() and can_issue_attack_target()


func can_issue_hold_fire_toggle() -> bool:
	var actor: Entity = _selected_entity()
	var def: EntityDef = _def_for_entity(actor)
	return def != null and def.combat != null and def.combat.damage > 0


func can_issue_gather() -> bool:
	var actor: Entity = _selected_entity()
	var def: EntityDef = _def_for_entity(actor)
	return def != null and def.gather != null and actor.gather_state != null


func can_issue_cancel() -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		return false
	if (
		actor.persistent_order != null
		or actor.focus_target_entity_id >= 0
		or actor.locked_to_building_id >= 0
	):
		return true
	if actor.production_state == null:
		return false
	return (
		not actor.production_state.active.is_empty() or not actor.production_state.queue.is_empty()
	)


func can_afford_build(def_id: String) -> bool:
	return _build_affordability_message(def_id) == ""


func build_option_ids() -> Array[String]:
	var out: Array[String] = []
	var actor: Entity = _selected_entity()
	var actor_def: EntityDef = _def_for_entity(actor)
	if actor == null or actor_def == null or _registry == null:
		return out
	for candidate in _registry.entities:
		var def: EntityDef = candidate
		if def == null or def.id == "" or def.construction == null:
			continue
		if not def.tags.has("building"):
			continue
		var built_by: String = def.construction.built_by_tag
		if built_by == "" or actor_def.tags.has(built_by):
			out.append(def.id)
	return out


func train_option_ids() -> Array[String]:
	var out: Array[String] = []
	var actor: Entity = _selected_entity()
	var producer_def: EntityDef = _def_for_entity(actor)
	if actor == null or producer_def == null or producer_def.production == null:
		return out
	if actor.production_state == null or actor.is_constructing:
		return out
	for id in producer_def.production.produces:
		var def_id: String = id
		if _registry == null or _registry.get_by_id(def_id) != null:
			out.append(def_id)
	return out


func research_option_ids() -> Array[String]:
	var out: Array[String] = []
	var actor: Entity = _selected_entity()
	var producer_def: EntityDef = _def_for_entity(actor)
	if actor == null or producer_def == null or producer_def.production == null:
		return out
	if actor.production_state == null or actor.is_constructing:
		return out
	var player: PlayerState = _state.get_player(actor.owner_player_id) if _state != null else null
	for id in producer_def.production.researches:
		var research_id: String = id
		if _registry != null and _registry.get_research_by_id(research_id) == null:
			continue
		if player != null and player.unlocked_researches.has(research_id):
			continue
		if _player_has_research_in_progress(actor.owner_player_id, research_id):
			continue
		out.append(research_id)
	return out


func ability_option_ids() -> Array[String]:
	var out: Array[String] = []
	var actor: Entity = _selected_entity()
	if actor == null:
		return out
	for ability in _ABILITY_SYSTEM.available_self_abilities(_state, actor, _registry):
		out.append(ability.id)
	return out


func label_for_entity_def_id(def_id: String) -> String:
	if _registry == null:
		return def_id
	var def: EntityDef = _registry.get_by_id(def_id)
	if def == null or def.display_name == "":
		return def_id
	return def.display_name


func label_for_entity_def_id_with_cost(def_id: String) -> String:
	if _registry == null:
		return def_id
	var def: EntityDef = _registry.get_by_id(def_id)
	if def == null:
		return def_id
	var label := def.display_name if def.display_name != "" else def_id
	var parts: Array[String] = []
	if def.construction != null:
		parts.append("%dM" % def.construction.mineral_cost)
		if def.construction.gas_cost > 0:
			parts.append("%dG" % def.construction.gas_cost)
		if def.population != null and def.population.pop_cost > 0:
			parts.append("%dP" % def.population.pop_cost)
		parts.append("%dT" % def.construction.build_time_turns)
	if parts.is_empty():
		return label
	return "%s (%s)" % [label, ", ".join(parts)]


func label_for_research_id(research_id: String) -> String:
	if _registry == null:
		return research_id
	var research: ResearchDef = _registry.get_research_by_id(research_id)
	if research == null or research.display_name == "":
		return research_id
	return research.display_name


func label_for_research_id_with_cost(research_id: String) -> String:
	if _registry == null:
		return research_id
	var research: ResearchDef = _registry.get_research_by_id(research_id)
	if research == null:
		return research_id
	var label := research.display_name if research.display_name != "" else research_id
	var parts: Array[String] = ["%dM" % research.mineral_cost]
	if research.gas_cost > 0:
		parts.append("%dG" % research.gas_cost)
	parts.append("%dT" % research.research_time_turns)
	return "%s (%s)" % [label, ", ".join(parts)]


func label_for_ability_id(ability_id: String) -> String:
	var actor: Entity = _selected_entity()
	var def: EntityDef = _def_for_entity(actor)
	if def == null or def.abilities == null:
		return ability_id
	for item in def.abilities.abilities:
		var ability: AbilityDef = item
		if ability != null and ability.id == ability_id:
			return ability.display_name if ability.display_name != "" else ability_id
	return ability_id


func _append_order(order: EntityOrder) -> void:
	var submit: SubmitTurn = _submission_for(_active_player_id)
	var replace_index := _replacement_index_for_order(submit.orders, order)
	if replace_index >= 0:
		submit.orders[replace_index] = order
	else:
		submit.orders.append(order)


func _replacement_index_for_order(orders: Array[EntityOrder], order: EntityOrder) -> int:
	if order == null:
		return -1
	for i in orders.size():
		var existing: EntityOrder = orders[i]
		if existing == null or existing.entity_id != order.entity_id:
			continue
		if order.type == EntityOrder.Type.MOVE and existing.type == EntityOrder.Type.MOVE:
			return i
		if order.type == EntityOrder.Type.ATTACK and existing.type == EntityOrder.Type.ATTACK:
			return i
	return -1


func _submission_for(player_id: int) -> SubmitTurn:
	_ensure_submit_turn(player_id)
	return _submissions[player_id]


func _ensure_submit_turn(player_id: int) -> void:
	if not _submissions.has(player_id) or _submissions[player_id] == null:
		_submissions[player_id] = SubmitTurn.new()


func _selected_entity() -> Entity:
	if _selected_entity_id < 0 or not _is_selectable(_selected_entity_id):
		return null
	return _state.get_entity_by_id(_selected_entity_id)


func _is_selectable(entity_id: int) -> bool:
	var entity: Entity = _live_entity(entity_id)
	return entity != null and entity.owner_player_id == _active_player_id


func _live_entity(entity_id: int) -> Entity:
	if _state == null:
		return null
	var entity: Entity = _state.get_entity_by_id(entity_id)
	if entity == null or entity.current_hp <= 0:
		return null
	return entity


func _live_enemy_entity(entity_id: int) -> Entity:
	var entity: Entity = _live_entity(entity_id)
	if entity == null:
		return null
	if entity.owner_player_id < 0 or entity.owner_player_id == _active_player_id:
		return null
	return entity


func _gather_target_entity(entity_id: int) -> Entity:
	if _state == null:
		return null
	var entity: Entity = _state.get_entity_by_id(entity_id)
	if entity == null:
		return null
	var def: EntityDef = _def_for_entity(entity)
	if def == null:
		return null
	if def.resource_source != null:
		# -1 is infinite capacity; only exactly zero is depleted.
		if entity.current_resource_amount == 0:
			return null
		return entity
	if entity.current_hp <= 0:
		return null
	if _is_gather_target(entity, def):
		return entity
	return null


func _def_for_entity(entity: Entity) -> EntityDef:
	if entity == null or _registry == null:
		return null
	return _registry.get_by_id(_def_id_for_entity(entity))


func _def_id_for_entity(entity: Entity) -> String:
	if entity == null:
		return ""
	return entity.current_def_id if entity.current_def_id != "" else entity.def_id


func _is_gather_target(target: Entity, target_def: EntityDef) -> bool:
	if target == null or target_def == null:
		return false
	if target_def.resource_source != null:
		return true
	return target_def.tags.has("refinery")


func _build_affordability_message(def_id: String) -> String:
	var actor: Entity = _selected_entity()
	if actor == null or _state == null or _registry == null:
		return "Select a builder before issuing BUILD."
	var def: EntityDef = _registry.get_by_id(def_id)
	if def == null or def.construction == null:
		return "Cannot build '%s'." % def_id
	var player: PlayerState = _state.get_player(actor.owner_player_id)
	if player == null:
		return "BUILD needs an active player economy."
	var missing: Array[String] = []
	if player.minerals < def.construction.mineral_cost:
		missing.append("%dM" % def.construction.mineral_cost)
	if player.gas < def.construction.gas_cost:
		missing.append("%dG" % def.construction.gas_cost)
	var pop_cost := 0
	if def.population != null:
		pop_cost = def.population.pop_cost
	if player.pop_used + pop_cost > player.pop_cap:
		missing.append("%dP" % pop_cost)
	if missing.is_empty():
		return ""
	return "Need %s for BUILD %s." % [", ".join(missing), label_for_entity_def_id(def_id)]


func _build_placement_message(def: EntityDef, rect: Rect2i) -> String:
	if def == null or def.construction == null or _state == null or _state.tile_grid == null:
		return "BUILD needs a valid placement."
	var require_tag: String = def.construction.requires_target_tag
	if require_tag != "":
		if _find_overlap_target(rect, require_tag) < 0:
			return "BUILD target needs %s." % require_tag
		return ""
	if not _state.tile_grid.is_rect_clear(rect):
		return "BUILD target is occupied."
	return ""


func _find_overlap_target(rect: Rect2i, tag: String) -> int:
	if _state == null or _state.tile_grid == null or _registry == null:
		return -1
	var occupants: Array[int] = []
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var occupant_id := _state.tile_grid.entity_at(Vector2i(x, y))
			if occupant_id != -1 and not occupants.has(occupant_id):
				occupants.append(occupant_id)
	if occupants.size() != 1:
		return -1
	var occupant: Entity = _state.get_entity_by_id(occupants[0])
	if occupant == null:
		return -1
	var occupant_def: EntityDef = _registry.get_by_id(_def_id_for_entity(occupant))
	if occupant_def == null or not occupant_def.tags.has(tag):
		return -1
	return occupant.id


func _player_has_research_in_progress(owner_player_id: int, research_id: String) -> bool:
	if _state == null or research_id == "":
		return false
	for e in _state.entities_sorted_by_id():
		if e == null or e.current_hp <= 0 or e.owner_player_id != owner_player_id:
			continue
		if e.production_state == null:
			continue
		var active: Dictionary = e.production_state.active
		if (
			not active.is_empty()
			and active.get(ProductionState.KEY_KIND, "") == ProductionState.KIND_RESEARCH
			and active.get(ProductionState.KEY_DEF_ID, "") == research_id
		):
			return true
		for item in e.production_state.queue:
			var queued: Dictionary = item
			if (
				queued.get(ProductionState.KEY_KIND, "") == ProductionState.KIND_RESEARCH
				and queued.get(ProductionState.KEY_DEF_ID, "") == research_id
			):
				return true
	return false
