@tool
class_name DevTurnInput
extends RefCounted

# Dev-only turn input state for plan 07b2. Owns selection and pending
# SubmitTurn resources; dev HUD state controls mutate standing MatchState state
# immediately, while turn actions still queue for resolver submission.

const _ABILITY_SYSTEM := preload("res://scripts/resolver/ability_system.gd")

var _state: MatchState = null
var _registry: EntityRegistry = null
var _active_player_id: int = 0
var _selected_entity_id: int = -1
var _submissions: Dictionary[int, SubmitTurn] = {}
var _move_assists: Dictionary[int, EntityOrder] = {}
var _future_orders: Dictionary[int, Array] = {}
var _queue_modifier_active: bool = false
var _status_message: String = ""


func _init() -> void:
	clear_submissions()


func bind_context(state: MatchState, registry: EntityRegistry) -> void:
	_state = state
	_registry = registry
	_ensure_submit_turn(0)
	_ensure_submit_turn(1)
	_prune_move_assists()
	_prune_future_orders()
	if _selected_entity_id >= 0 and not _is_selectable(_selected_entity_id):
		_selected_entity_id = -1


func set_active_player_id(player_id: int) -> void:
	_active_player_id = player_id
	_queue_modifier_active = false
	_ensure_submit_turn(player_id)
	if _selected_entity_id >= 0 and not _is_selectable(_selected_entity_id):
		_selected_entity_id = -1


func active_player_id() -> int:
	return _active_player_id


func selected_entity_id() -> int:
	return _selected_entity_id


func status_message() -> String:
	return _status_message


func set_queue_modifier_active(enabled: bool) -> void:
	_queue_modifier_active = enabled


func queue_modifier_active() -> bool:
	return _queue_modifier_active


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
		_status_message = "Select a unit before issuing Attack and Move."
		return false
	if _state == null or _state.tile_grid == null or not _state.tile_grid.is_in_bounds(target_tile):
		_status_message = "Attack and Move target is outside the map."
		return false
	if not _can_entity_move(actor):
		_status_message = "%s cannot move." % _def_id_for_entity(actor)
		return false
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.MOVE
	order.entity_id = actor.id
	order.target_tile = target_tile
	_append_order(order)
	_status_message = "Queued Attack and Move for #%d to %s." % [actor.id, str(target_tile)]
	return true


func issue_move_only(target_tile: Vector2i) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select a unit before issuing MOVE ONLY."
		return false
	if _state == null or _state.tile_grid == null or not _state.tile_grid.is_in_bounds(target_tile):
		_status_message = "MOVE ONLY target is outside the map."
		return false
	if not _can_entity_move(actor):
		_status_message = "%s cannot move." % _def_id_for_entity(actor)
		return false
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.MOVE_ONLY
	order.entity_id = actor.id
	order.target_tile = target_tile
	_append_order(order)
	_status_message = (
		"Queued MOVE ONLY for #%d to %s. Unit will not shoot this turn."
		% [actor.id, str(target_tile)]
	)
	return true


func issue_attack(target_entity_id: int) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select a unit before issuing ATTACK."
		return false
	if (
		ConstructionSystem.has_pending_build(actor)
		or actor.locked_to_building_id >= 0
		or actor.is_constructing
	):
		_status_message = "%s cannot attack." % _def_id_for_entity(actor)
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
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select a combat unit before setting TARGET."
		return false
	if not can_issue_attack_target():
		_status_message = "%s cannot target enemies." % _def_id_for_entity(actor)
		return false
	var target: Entity = _live_enemy_entity(target_entity_id)
	if target == null:
		_status_message = "Attack target needs a live enemy target."
		return false
	var def: EntityDef = _def_for_entity(actor)
	if def == null or def.combat == null or def.combat.damage <= 0:
		_status_message = "%s cannot target enemies." % _def_id_for_entity(actor)
		return false
	GatherSystem.clear_assignment(actor)
	actor.focus_target_entity_id = target.id
	_status_message = "Set TARGET for #%d to #%d." % [actor.id, target.id]
	return true


func issue_target_chase(target_entity_id: int) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select a combat unit before issuing target chase."
		return false
	if not can_issue_target_chase():
		_status_message = "%s cannot chase targets." % _def_id_for_entity(actor)
		return false
	var target: Entity = _live_enemy_entity(target_entity_id)
	if target == null:
		_status_message = "Target chase needs a live enemy target."
		return false
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.MOVE
	order.entity_id = actor.id
	order.target_tile = target.origin
	order.target_priority_chain = [target_entity_id]
	_append_order(order)
	_status_message = "Queued target chase for #%d against #%d." % [actor.id, target_entity_id]
	return true


func issue_halt_on_sight_toggle(enabled: bool) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select a combat entity before issuing HALT_ON_SIGHT_TOGGLE."
		return false
	if not can_issue_halt_on_sight_toggle():
		_status_message = "%s cannot use halt on sight." % _def_id_for_entity(actor)
		return false
	actor.halt_on_sight = enabled
	_status_message = (
		("Halt on Sight enabled for #%d." if enabled else "Halt on Sight disabled for #%d.")
		% actor.id
	)
	return true


func issue_gather(target_entity_id: int) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select a worker before issuing GATHER."
		return false
	if not _can_entity_gather(actor):
		_status_message = "%s cannot gather." % _def_id_for_entity(actor)
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
	var source: Entity = GatherSystem.resolve_source_for_worker(
		_state, _registry, target_entity_id, actor.owner_player_id
	)
	if source == null:
		_status_message = "GATHER needs an owned refinery for that gas source."
		return false
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.GATHER
	order.entity_id = actor.id
	order.target_entity_id = target_entity_id
	_append_order(order)
	_status_message = "Queued GATHER for #%d from #%d." % [actor.id, target_entity_id]
	return true


func issue_build(def_id: String, target_tile: Vector2i, target_entity_id: int = -1) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		_status_message = "Select a builder before issuing BUILD."
		return false
	if actor.locked_to_building_id >= 0 or ConstructionSystem.has_pending_build(actor):
		_status_message = "Builder is already committed to construction."
		return false
	if _state == null or _state.tile_grid == null:
		_status_message = "BUILD needs a loaded map."
		return false
	if not build_option_ids().has(def_id):
		_status_message = "%s cannot build '%s'." % [_def_id_for_entity(actor), def_id]
		return false
	var build_def: EntityDef = _registry.get_by_id(def_id) if _registry != null else null
	var footprint: Vector2i = build_def.footprint if build_def != null else Vector2i.ONE
	var build_tile: Vector2i = _normalized_build_tile(build_def, target_tile)
	var rect: Rect2i = Rect2i(build_tile, footprint if footprint != Vector2i.ZERO else Vector2i.ONE)
	if not _state.tile_grid.is_rect_in_bounds(rect):
		_status_message = "BUILD target is outside the map."
		return false
	var preview: Dictionary = build_placement_preview(def_id, target_tile)
	var preview_valid: bool = preview.get("valid", false)
	if not preview_valid:
		var preview_message: String = preview.get("message", "BUILD needs a valid placement.")
		_status_message = preview_message
		return false
	var preview_origin: Vector2i = preview.get("origin", build_tile)
	build_tile = preview_origin
	var order: EntityOrder = EntityOrder.new()
	order.type = EntityOrder.Type.BUILD
	order.entity_id = actor.id
	order.def_id = def_id
	order.target_tile = build_tile
	order.target_entity_id = target_entity_id
	_append_order(order)
	_status_message = "Queued BUILD %s for #%d at %s." % [def_id, actor.id, str(build_tile)]
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
	if cancel_index < 0 and _remove_future_order_for_entity(actor.id):
		_status_message = "Cancelled future queued order for #%d." % actor.id
		return true
	if cancel_index < 0 and _remove_queued_order_for_entity(actor.id):
		_clear_move_assist(actor.id)
		_status_message = "Cancelled queued order for #%d." % actor.id
		return true
	if (
		cancel_index < 0
		and actor.locked_to_building_id < 0
		and not ConstructionSystem.has_pending_build(actor)
		and (_move_assists.has(actor.id) or actor.focus_target_entity_id >= 0)
	):
		_clear_move_assist(actor.id)
		actor.focus_target_entity_id = -1
		_status_message = "Cancelled standing intent for #%d." % actor.id
		return true
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


func clear_submissions(clear_move_assists: bool = true, clear_future_orders: bool = true) -> void:
	_submissions.clear()
	_submissions[0] = SubmitTurn.new()
	_submissions[1] = SubmitTurn.new()
	_queue_modifier_active = false
	if clear_move_assists:
		_move_assists.clear()
	if clear_future_orders:
		_future_orders.clear()
	_status_message = "Queues cleared."


func create_snapshot() -> DevInputSnapshot:
	var snapshot: DevInputSnapshot = DevInputSnapshot.new()
	snapshot.active_player_id = _active_player_id
	snapshot.selected_entity_id = _selected_entity_id
	snapshot.submit_a = _submission_for(0).clone()
	snapshot.submit_b = _submission_for(1).clone()
	snapshot.move_assists = _clone_order_dictionary(_move_assists)
	snapshot.future_orders = _clone_future_order_dictionary(_future_orders)
	snapshot.queue_modifier_active = _queue_modifier_active
	snapshot.status_message = _status_message
	return snapshot


func restore_snapshot(
	snapshot: DevInputSnapshot, state: MatchState, registry: EntityRegistry
) -> void:
	_state = state
	_registry = registry
	_submissions.clear()
	if snapshot == null:
		_active_player_id = 0
		_selected_entity_id = -1
		_move_assists.clear()
		_future_orders.clear()
		_queue_modifier_active = false
		_status_message = ""
		clear_submissions()
		bind_context(state, registry)
		return
	_active_player_id = snapshot.active_player_id
	_selected_entity_id = snapshot.selected_entity_id
	_submissions[0] = (snapshot.submit_a.clone() if snapshot.submit_a != null else SubmitTurn.new())
	_submissions[1] = (snapshot.submit_b.clone() if snapshot.submit_b != null else SubmitTurn.new())
	_move_assists = _clone_order_dictionary(snapshot.move_assists)
	_future_orders = _clone_future_order_dictionary(snapshot.future_orders)
	_queue_modifier_active = snapshot.queue_modifier_active
	_status_message = snapshot.status_message
	_ensure_submit_turn(0)
	_ensure_submit_turn(1)
	_prune_submissions()
	_prune_move_assists()
	_prune_future_orders()
	if _selected_entity_id >= 0 and not _is_selectable(_selected_entity_id):
		_selected_entity_id = -1


func queue_move_assists_for_next_turn() -> void:
	_prune_move_assists()
	var ids: Array[int] = []
	for entity_id in _move_assists.keys():
		ids.append(entity_id)
	ids.sort()
	for entity_id in ids:
		var entity: Entity = _state.get_entity_by_id(entity_id) if _state != null else null
		if entity == null:
			continue
		var assisted_order: EntityOrder = _move_assists[entity_id]
		var order: EntityOrder = assisted_order.clone()
		order.entity_id = entity.id
		var submit: SubmitTurn = _submission_for(entity.owner_player_id)
		_append_order_to_submit(submit, order)


func apply_resolve_events(events: Array[ResolverEvent]) -> void:
	for event in events:
		if event == null:
			continue
		if event.type == ResolverEvent.Type.MOVE_COMPLETED:
			_clear_move_assist(event.actor_id)


func queue_rally_orders_for_train_completed(events: Array[ResolverEvent]) -> void:
	if _state == null or _registry == null:
		return
	for ev in events:
		if ev == null or ev.type != ResolverEvent.Type.TRAIN_COMPLETED:
			continue
		var producer: Entity = _state.get_entity_by_id(ev.actor_id)
		var spawned: Entity = _state.get_entity_by_id(ev.target_id)
		if producer == null or spawned == null:
			continue
		if producer.production_state == null:
			continue
		_queue_rally_order_for_spawn(producer, spawned)


func promote_future_orders_for_next_turn() -> void:
	_prune_future_orders()
	var ids: Array[int] = []
	for entity_id in _future_orders.keys():
		ids.append(entity_id)
	ids.sort()
	for entity_id in ids:
		var entity: Entity = _state.get_entity_by_id(entity_id) if _state != null else null
		if not _can_promote_future_order_for_entity(entity):
			continue
		if _has_queued_order_for_entity_and_player(entity.id, entity.owner_player_id):
			continue
		var queue: Array = _future_orders.get(entity_id, [])
		if queue.is_empty():
			_future_orders.erase(entity_id)
			continue
		var order: EntityOrder = queue.pop_front()
		if queue.is_empty():
			_future_orders.erase(entity_id)
		else:
			_future_orders[entity_id] = queue
		var promoted: EntityOrder = order.clone()
		promoted.entity_id = entity.id
		_append_order_to_submit(_submission_for(entity.owner_player_id), promoted)
		if _is_move_like(promoted.type):
			_remember_move_assist(promoted)
		else:
			_clear_move_assist(entity.id)


func submit_for_player(player_id: int) -> SubmitTurn:
	return _submission_for(player_id)


func queued_order_count(player_id: int) -> int:
	return _submission_for(player_id).orders.size()


func future_orders_for_entity(entity_id: int) -> Array[EntityOrder]:
	var out: Array[EntityOrder] = []
	var queue: Array = _future_orders.get(entity_id, [])
	for item in queue:
		var order: EntityOrder = item
		if order != null:
			out.append(order.clone())
	return out


func future_order_count_for_entity(entity_id: int) -> int:
	var queue: Array = _future_orders.get(entity_id, [])
	return queue.size()


func selected_entity_label() -> String:
	var actor: Entity = _selected_entity()
	if actor == null:
		return "none"
	var def_id: String = _def_id_for_entity(actor)
	return label_for_entity_def_id(def_id)


func selected_halt_on_sight() -> bool:
	var actor: Entity = _selected_entity()
	return actor != null and actor.halt_on_sight


func can_issue_move() -> bool:
	var actor: Entity = _selected_entity()
	return _can_entity_move(actor)


func can_issue_move_only() -> bool:
	var actor: Entity = _selected_entity()
	return _can_entity_move(actor)


func can_issue_attack_target() -> bool:
	var actor: Entity = _selected_entity()
	if (
		actor == null
		or ConstructionSystem.has_pending_build(actor)
		or actor.locked_to_building_id >= 0
		or actor.is_constructing
	):
		return false
	var def: EntityDef = _def_for_entity(actor)
	return def != null and def.combat != null and def.combat.damage > 0


func can_issue_target_chase() -> bool:
	var actor: Entity = _selected_entity()
	if (
		actor == null
		or ConstructionSystem.has_pending_build(actor)
		or actor.locked_to_building_id >= 0
		or actor.is_constructing
	):
		return false
	var def: EntityDef = _def_for_entity(actor)
	return (
		def != null
		and def.combat != null
		and def.combat.damage > 0
		and def.movement != null
		and def.movement.speed_tiles_per_turn > 0
	)


func can_issue_halt_on_sight_toggle() -> bool:
	var actor: Entity = _selected_entity()
	if (
		actor == null
		or ConstructionSystem.has_pending_build(actor)
		or actor.locked_to_building_id >= 0
	):
		return false
	var def: EntityDef = _def_for_entity(actor)
	return def != null and def.combat != null and def.combat.damage > 0


func can_issue_gather() -> bool:
	var actor: Entity = _selected_entity()
	return _can_entity_gather(actor)


func can_issue_cancel() -> bool:
	var actor: Entity = _selected_entity()
	if actor == null:
		return false
	if (
		_move_assists.has(actor.id)
		or actor.focus_target_entity_id >= 0
		or actor.locked_to_building_id >= 0
		or ConstructionSystem.has_pending_build(actor)
		or _has_queued_order_for_entity(actor.id)
		or future_order_count_for_entity(actor.id) > 0
	):
		return true
	if actor.production_state == null:
		return false
	return (
		not actor.production_state.active.is_empty() or not actor.production_state.queue.is_empty()
	)


func can_issue_repeat_train_toggle() -> bool:
	var actor: Entity = _selected_entity()
	return actor != null and actor.production_state != null and not train_option_ids().is_empty()


func can_issue_rally_move() -> bool:
	var actor: Entity = _selected_entity()
	return _producer_can_train(actor)


func can_issue_rally_gather() -> bool:
	var actor: Entity = _selected_entity()
	return _producer_can_train_gatherer(actor)


func selected_repeat_train_enabled() -> bool:
	var actor: Entity = _selected_entity()
	return (
		actor != null
		and actor.production_state != null
		and actor.production_state.repeat_train_enabled
	)


func issue_repeat_train_toggle(enabled: bool) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null or actor.production_state == null:
		_status_message = "Select a producer before toggling repeat training."
		return false
	if train_option_ids().is_empty():
		_status_message = "%s cannot repeat train." % _def_id_for_entity(actor)
		return false
	actor.production_state.repeat_train_enabled = enabled
	_status_message = (
		("Repeat training enabled for #%d." if enabled else "Repeat training disabled for #%d.")
		% actor.id
	)
	return true


func issue_rally_move(target_tile: Vector2i) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null or actor.production_state == null:
		_status_message = "Select a producer before setting a rally point."
		return false
	if not can_issue_rally_move():
		_status_message = "%s cannot set a train rally." % _def_id_for_entity(actor)
		return false
	if _state == null or _state.tile_grid == null or not _state.tile_grid.is_in_bounds(target_tile):
		_status_message = "Rally target is outside the map."
		return false
	actor.production_state.rally_mode = ProductionState.RALLY_MODE_MOVE
	actor.production_state.rally_target_tile = target_tile
	actor.production_state.rally_target_entity_id = -1
	_status_message = "Set rally for #%d to %s." % [actor.id, str(target_tile)]
	return true


func issue_rally_gather(target_entity_id: int) -> bool:
	var actor: Entity = _selected_entity()
	if actor == null or actor.production_state == null:
		_status_message = "Select a producer before setting a gather rally."
		return false
	if not can_issue_rally_gather():
		_status_message = "%s cannot rally gatherers." % _def_id_for_entity(actor)
		return false
	var target: Entity = _gather_target_entity(target_entity_id)
	var target_def: EntityDef = _def_for_entity(target)
	if target == null or not _is_gather_target(target, target_def):
		_status_message = "Gather rally needs a resource source or refinery target."
		return false
	var source: Entity = GatherSystem.resolve_source_for_worker(
		_state, _registry, target_entity_id, actor.owner_player_id
	)
	if source == null:
		_status_message = "Gather rally needs an owned refinery for that gas source."
		return false
	actor.production_state.rally_mode = ProductionState.RALLY_MODE_GATHER
	actor.production_state.rally_target_tile = Vector2i.ZERO
	actor.production_state.rally_target_entity_id = target_entity_id
	_status_message = "Set gather rally for #%d to #%d." % [actor.id, target_entity_id]
	return true


func can_afford_build(def_id: String) -> bool:
	return _build_affordability_message(def_id) == ""


func build_placement_preview(def_id: String, clicked_tile: Vector2i) -> Dictionary:
	var out: Dictionary = {
		"def_id": def_id,
		"origin": clicked_tile,
		"footprint": Vector2i.ONE,
		"rect": Rect2i(clicked_tile, Vector2i.ONE),
		"valid": false,
		"message": "",
	}
	var actor: Entity = _selected_entity()
	if actor == null:
		out["message"] = "Select a builder before issuing BUILD."
		return out
	if actor.locked_to_building_id >= 0 or ConstructionSystem.has_pending_build(actor):
		out["message"] = "Builder is already committed to construction."
		return out
	if _state == null or _state.tile_grid == null:
		out["message"] = "BUILD needs a loaded map."
		return out
	var build_def: EntityDef = _registry.get_by_id(def_id) if _registry != null else null
	var footprint: Vector2i = build_def.footprint if build_def != null else Vector2i.ONE
	if footprint == Vector2i.ZERO:
		footprint = Vector2i.ONE
	var build_tile: Vector2i = _normalized_build_tile(build_def, clicked_tile)
	var rect: Rect2i = Rect2i(build_tile, footprint)
	out["origin"] = build_tile
	out["footprint"] = footprint
	out["rect"] = rect
	if not build_option_ids().has(def_id):
		out["message"] = "%s cannot build '%s'." % [_def_id_for_entity(actor), def_id]
		return out
	if not _state.tile_grid.is_rect_in_bounds(rect):
		out["message"] = "BUILD target is outside the map."
		return out
	var affordability_message := _build_affordability_message(def_id)
	if affordability_message != "":
		out["message"] = affordability_message
		return out
	var placement_message := _build_placement_message(build_def, rect)
	if placement_message != "":
		out["message"] = placement_message
		return out
	out["valid"] = true
	return out


func build_option_ids() -> Array[String]:
	var out: Array[String] = []
	var actor: Entity = _selected_entity()
	var actor_def: EntityDef = _def_for_entity(actor)
	if actor == null or actor_def == null or _registry == null:
		return out
	if actor.locked_to_building_id >= 0 or ConstructionSystem.has_pending_build(actor):
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


func _append_order(order: EntityOrder) -> bool:
	if order == null:
		return false
	var queue_requested: bool = _consume_queue_modifier()
	if not _uses_future_order_queue(order):
		var submit: SubmitTurn = _submission_for(_active_player_id)
		_append_order_to_submit(submit, order)
		return true
	if (
		queue_requested
		and (_has_queued_order_for_entity(order.entity_id) or _future_orders.has(order.entity_id))
	):
		_append_future_order(order)
		return false
	if not queue_requested:
		_clear_current_and_future_orders_for_entity(order.entity_id)
	var current_submit: SubmitTurn = _submission_for(_active_player_id)
	_append_order_to_submit(current_submit, order)
	if _is_move_like(order.type):
		_remember_move_assist(order)
	else:
		_clear_move_assist(order.entity_id)
	return true


func _append_order_to_submit(submit: SubmitTurn, order: EntityOrder) -> void:
	var replace_index := _replacement_index_for_order(submit.orders, order)
	if replace_index >= 0:
		submit.orders[replace_index] = order
	else:
		submit.orders.append(order)


func _uses_future_order_queue(order: EntityOrder) -> bool:
	if order == null:
		return false
	return not (
		order.type == EntityOrder.Type.TRAIN
		or order.type == EntityOrder.Type.RESEARCH
		or order.type == EntityOrder.Type.CANCEL
		or order.type == EntityOrder.Type.HALT_ON_SIGHT_TOGGLE
	)


func _consume_queue_modifier() -> bool:
	var queue_requested: bool = _queue_modifier_active
	_queue_modifier_active = false
	return queue_requested


func _append_future_order(order: EntityOrder) -> void:
	if order == null:
		return
	var queue: Array = _future_orders.get(order.entity_id, [])
	queue.append(order.clone())
	_future_orders[order.entity_id] = queue


func _clone_order_dictionary(source: Variant) -> Dictionary[int, EntityOrder]:
	var out: Dictionary[int, EntityOrder] = {}
	if not source is Dictionary:
		return out
	var source_dict: Dictionary = source
	for key in source_dict.keys():
		var raw_order: Variant = source_dict[key]
		if not raw_order is EntityOrder:
			continue
		var order: EntityOrder = raw_order
		out[int(key)] = order.clone()
	return out


func _clone_future_order_dictionary(source: Variant) -> Dictionary[int, Array]:
	var out: Dictionary[int, Array] = {}
	if not source is Dictionary:
		return out
	var source_dict: Dictionary = source
	for key in source_dict.keys():
		var raw_queue: Variant = source_dict[key]
		if not raw_queue is Array:
			continue
		var cloned_queue: Array[EntityOrder] = []
		for item in raw_queue:
			if not item is EntityOrder:
				continue
			var order: EntityOrder = item
			cloned_queue.append(order.clone())
		if not cloned_queue.is_empty():
			out[int(key)] = cloned_queue
	return out


func _queue_rally_order_for_spawn(producer: Entity, spawned: Entity) -> void:
	if producer == null or spawned == null or producer.production_state == null:
		return
	if spawned.current_hp <= 0 or spawned.owner_player_id != producer.owner_player_id:
		return
	var mode: String = producer.production_state.rally_mode
	if mode == ProductionState.RALLY_MODE_MOVE:
		if not _can_entity_move(spawned):
			return
		var target_tile: Vector2i = producer.production_state.rally_target_tile
		if _state.tile_grid == null or not _state.tile_grid.is_in_bounds(target_tile):
			return
		var move_order := EntityOrder.new()
		move_order.type = EntityOrder.Type.MOVE_ONLY
		move_order.entity_id = spawned.id
		move_order.target_tile = target_tile
		_append_order_to_submit(_submission_for(spawned.owner_player_id), move_order)
		_remember_move_assist(move_order)
	elif mode == ProductionState.RALLY_MODE_GATHER:
		if not _can_entity_gather(spawned):
			return
		var target_entity_id: int = producer.production_state.rally_target_entity_id
		var source: Entity = GatherSystem.resolve_source_for_worker(
			_state, _registry, target_entity_id, spawned.owner_player_id
		)
		if source == null:
			return
		var gather_order := EntityOrder.new()
		gather_order.type = EntityOrder.Type.GATHER
		gather_order.entity_id = spawned.id
		gather_order.target_entity_id = target_entity_id
		_append_order_to_submit(_submission_for(spawned.owner_player_id), gather_order)
		_clear_move_assist(spawned.id)


func _clear_current_and_future_orders_for_entity(entity_id: int) -> void:
	_remove_all_queued_orders_for_entity(entity_id)
	_future_orders.erase(entity_id)
	_clear_move_assist(entity_id)


func _remember_move_assist(order: EntityOrder) -> void:
	if order == null or not _is_move_like(order.type):
		return
	var actor: Entity = _state.get_entity_by_id(order.entity_id) if _state != null else null
	if actor == null or actor.origin == order.target_tile:
		_move_assists.erase(order.entity_id)
		return
	_move_assists[order.entity_id] = order.clone()


func _clear_move_assist(entity_id: int, remove_queued_move: bool = false) -> void:
	_move_assists.erase(entity_id)
	if remove_queued_move:
		_remove_queued_move_for_entity(entity_id)


func _prune_move_assists() -> void:
	for entity_id in _move_assists.keys():
		var order: EntityOrder = _move_assists[entity_id]
		var entity: Entity = _state.get_entity_by_id(entity_id) if _state != null else null
		if not _can_continue_move_assist(entity, order):
			_move_assists.erase(entity_id)


func _can_continue_move_assist(entity: Entity, order: EntityOrder) -> bool:
	if entity == null or order == null or not _is_move_like(order.type):
		return false
	if entity.current_hp <= 0 or entity.owner_player_id < 0:
		return false
	if (
		_state == null
		or _state.tile_grid == null
		or not _state.tile_grid.is_in_bounds(order.target_tile)
	):
		return false
	var effective_target_tile: Vector2i = _effective_move_assist_target_tile(entity, order)
	if entity.origin == effective_target_tile:
		return false
	var def: EntityDef = _def_for_entity(entity)
	if def == null or def.movement == null or def.movement.speed_tiles_per_turn <= 0:
		return false
	if entity.gather_state != null and entity.gather_state.phase != GatherState.Phase.IDLE:
		return false
	if (
		ConstructionSystem.has_pending_build(entity)
		or entity.locked_to_building_id >= 0
		or entity.is_constructing
	):
		return false
	if entity.ability_cast != null:
		return false
	return true


func _effective_move_assist_target_tile(entity: Entity, order: EntityOrder) -> Vector2i:
	if entity == null or order == null:
		return Vector2i.ZERO
	if order.type == EntityOrder.Type.MOVE and not order.target_priority_chain.is_empty():
		var target: Entity = _live_enemy_from_chain(entity, order.target_priority_chain)
		if target != null:
			var target_rect: Rect2i = _state.tile_grid.entity_rect(target.id)
			if target_rect.size != Vector2i.ZERO:
				return target_rect.position
			return target.origin
	return order.target_tile


func _has_queued_order_for_entity(entity_id: int) -> bool:
	var submit: SubmitTurn = _submission_for(_active_player_id)
	for order in submit.orders:
		if order != null and order.entity_id == entity_id:
			return true
	return false


func _has_queued_order_for_entity_and_player(entity_id: int, player_id: int) -> bool:
	var submit: SubmitTurn = _submission_for(player_id)
	for order in submit.orders:
		if order != null and order.entity_id == entity_id:
			return true
	return false


func _remove_queued_order_for_entity(entity_id: int) -> bool:
	var submit: SubmitTurn = _submission_for(_active_player_id)
	for i in range(submit.orders.size() - 1, -1, -1):
		var order: EntityOrder = submit.orders[i]
		if order != null and order.entity_id == entity_id:
			submit.orders.remove_at(i)
			return true
	return false


func _remove_all_queued_orders_for_entity(entity_id: int) -> bool:
	var removed := false
	var submit: SubmitTurn = _submission_for(_active_player_id)
	for i in range(submit.orders.size() - 1, -1, -1):
		var order: EntityOrder = submit.orders[i]
		if order != null and order.entity_id == entity_id:
			submit.orders.remove_at(i)
			removed = true
	return removed


func _remove_future_order_for_entity(entity_id: int) -> bool:
	var queue: Array = _future_orders.get(entity_id, [])
	if queue.is_empty():
		return false
	queue.remove_at(queue.size() - 1)
	if queue.is_empty():
		_future_orders.erase(entity_id)
	else:
		_future_orders[entity_id] = queue
	return true


func _remove_queued_move_for_entity(entity_id: int) -> void:
	for submit in _submissions.values():
		var submit_turn: SubmitTurn = submit
		for i in range(submit_turn.orders.size() - 1, -1, -1):
			var order: EntityOrder = submit_turn.orders[i]
			if order != null and order.entity_id == entity_id and _is_move_like(order.type):
				submit_turn.orders.remove_at(i)


func _prune_future_orders() -> void:
	for entity_id in _future_orders.keys():
		var entity: Entity = _state.get_entity_by_id(entity_id) if _state != null else null
		if entity == null or entity.current_hp <= 0 or entity.owner_player_id < 0:
			_future_orders.erase(entity_id)
			continue
		var queue: Array = _future_orders.get(entity_id, [])
		for i in range(queue.size() - 1, -1, -1):
			var raw_order: Variant = queue[i]
			if not raw_order is EntityOrder:
				queue.remove_at(i)
				continue
			var order: EntityOrder = raw_order
			_prune_missing_order_targets(order)
			if (
				order.entity_id != entity_id
				or not _is_restorable_order(order, entity.owner_player_id)
			):
				queue.remove_at(i)
		if queue.is_empty():
			_future_orders.erase(entity_id)
		else:
			_future_orders[entity_id] = queue


func _prune_submissions() -> void:
	for player_id in _submissions.keys():
		var submit: SubmitTurn = _submissions[player_id]
		if submit == null:
			_submissions[player_id] = SubmitTurn.new()
			continue
		for i in range(submit.orders.size() - 1, -1, -1):
			var order: EntityOrder = submit.orders[i]
			_prune_missing_order_targets(order)
			if not _is_restorable_order(order, player_id):
				submit.orders.remove_at(i)


func _is_restorable_order(order: EntityOrder, player_id: int) -> bool:
	if order == null or order.type == EntityOrder.Type.INVALID:
		return false
	if _state == null:
		return false
	var actor: Entity = _state.get_entity_by_id(order.entity_id)
	if actor == null or actor.current_hp <= 0 or actor.owner_player_id != player_id:
		return false
	if order.target_entity_id >= 0 and _state.get_entity_by_id(order.target_entity_id) == null:
		return false
	return true


func _prune_missing_order_targets(order: EntityOrder) -> void:
	if order == null or _state == null:
		return
	for i in range(order.target_priority_chain.size() - 1, -1, -1):
		var target_id: int = order.target_priority_chain[i]
		if _state.get_entity_by_id(target_id) == null:
			order.target_priority_chain.remove_at(i)


func _can_promote_future_order_for_entity(entity: Entity) -> bool:
	if entity == null or entity.current_hp <= 0 or entity.owner_player_id < 0:
		return false
	if (
		ConstructionSystem.has_pending_build(entity)
		or entity.locked_to_building_id >= 0
		or entity.is_constructing
	):
		return false
	if entity.ability_cast != null:
		return false
	if entity.gather_state != null and entity.gather_state.phase != GatherState.Phase.IDLE:
		return false
	return true


func _replacement_index_for_order(orders: Array[EntityOrder], order: EntityOrder) -> int:
	if order == null:
		return -1
	for i in orders.size():
		var existing: EntityOrder = orders[i]
		if existing == null or existing.entity_id != order.entity_id:
			continue
		if _is_move_like(order.type) and _is_move_like(existing.type):
			return i
		if order.type == EntityOrder.Type.ATTACK and existing.type == EntityOrder.Type.ATTACK:
			return i
	return -1


func _is_move_like(type: EntityOrder.Type) -> bool:
	return type == EntityOrder.Type.MOVE or type == EntityOrder.Type.MOVE_ONLY


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


func _live_enemy_from_chain(actor: Entity, target_priority_chain: Array[int]) -> Entity:
	if actor == null or _state == null:
		return null
	for target_id in target_priority_chain:
		var target: Entity = _state.get_entity_by_id(target_id)
		if target == null or target.current_hp <= 0:
			continue
		if target.owner_player_id < 0 or target.owner_player_id == actor.owner_player_id:
			continue
		return target
	return null


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


func _can_entity_move(entity: Entity) -> bool:
	if (
		entity == null
		or ConstructionSystem.has_pending_build(entity)
		or entity.locked_to_building_id >= 0
		or entity.is_constructing
	):
		return false
	var def: EntityDef = _def_for_entity(entity)
	return def != null and def.movement != null and def.movement.speed_tiles_per_turn > 0


func _can_entity_gather(entity: Entity) -> bool:
	if (
		entity == null
		or ConstructionSystem.has_pending_build(entity)
		or entity.locked_to_building_id >= 0
		or entity.is_constructing
	):
		return false
	var def: EntityDef = _def_for_entity(entity)
	return def != null and def.gather != null and entity.gather_state != null


func _producer_can_train(entity: Entity) -> bool:
	var def: EntityDef = _def_for_entity(entity)
	if entity == null or entity.production_state == null or def == null or def.production == null:
		return false
	if entity.is_constructing:
		return false
	for def_id in def.production.produces:
		if _registry == null or _registry.get_by_id(def_id) != null:
			return true
	return false


func _producer_can_train_gatherer(entity: Entity) -> bool:
	var def: EntityDef = _def_for_entity(entity)
	if entity == null or entity.production_state == null or def == null or def.production == null:
		return false
	if entity.is_constructing:
		return false
	for def_id in def.production.produces:
		var unit_def: EntityDef = _registry.get_by_id(def_id) if _registry != null else null
		if unit_def != null and unit_def.gather != null:
			return true
	return false


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
		var target_id: int = _find_overlap_target(rect, require_tag)
		if target_id < 0:
			return "BUILD target needs %s." % require_tag
		var target_rect: Rect2i = _state.tile_grid.entity_rect(target_id)
		if target_rect.position != rect.position or target_rect.size != rect.size:
			return "BUILD target must match the %s footprint." % require_tag
		var overlap_message: String = _target_overlap_message(rect, target_id)
		if overlap_message != "":
			return overlap_message
		return ""
	if not _state.tile_grid.is_rect_clear(rect):
		return "BUILD target is occupied."
	return ""


func _target_overlap_message(rect: Rect2i, allow_overlap_id: int) -> String:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for occupant_id in _state.tile_grid.entities_at(Vector2i(x, y)):
				if occupant_id != allow_overlap_id:
					return "BUILD target is occupied."
	for existing_id: int in _state.tile_grid.all_placed_entity_ids():
		if existing_id == allow_overlap_id:
			continue
		var existing_rect: Rect2i = _state.tile_grid.entity_rect(existing_id)
		if existing_rect.intersects(rect):
			return "BUILD target is occupied."
	return ""


func _normalized_build_tile(def: EntityDef, clicked_tile: Vector2i) -> Vector2i:
	if def == null or def.construction == null or _state == null or _state.tile_grid == null:
		return clicked_tile
	var require_tag: String = def.construction.requires_target_tag
	if require_tag == "":
		var footprint: Vector2i = def.footprint
		if footprint == Vector2i.ZERO:
			footprint = Vector2i.ONE
		return (
			clicked_tile
			- Vector2i(floori(float(footprint.x) * 0.5), floori(float(footprint.y) * 0.5))
		)
	var target_id: int = _find_target_at_tile(clicked_tile, require_tag)
	if target_id < 0:
		return clicked_tile
	var target_rect: Rect2i = _state.tile_grid.entity_rect(target_id)
	if target_rect.size.x <= 0 or target_rect.size.y <= 0:
		return clicked_tile
	return target_rect.position


func _find_target_at_tile(tile: Vector2i, tag: String) -> int:
	if _state == null or _state.tile_grid == null or _registry == null:
		return -1
	if not _state.tile_grid.is_in_bounds(tile):
		return -1
	var matching_ids: Array[int] = []
	for occupant_id in _state.tile_grid.entities_at(tile):
		if _entity_has_tag(occupant_id, tag):
			matching_ids.append(occupant_id)
	if matching_ids.size() != 1:
		return -1
	return matching_ids[0]


func _find_overlap_target(rect: Rect2i, tag: String) -> int:
	if _state == null or _state.tile_grid == null or _registry == null:
		return -1
	var matching_ids: Array[int] = []
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for occupant_id in _state.tile_grid.entities_at(Vector2i(x, y)):
				if _entity_has_tag(occupant_id, tag) and not matching_ids.has(occupant_id):
					matching_ids.append(occupant_id)
	if matching_ids.size() != 1:
		return -1
	return matching_ids[0]


func _entity_has_tag(entity_id: int, tag: String) -> bool:
	var occupant: Entity = _state.get_entity_by_id(entity_id)
	if occupant == null:
		return false
	var occupant_def: EntityDef = _registry.get_by_id(_def_id_for_entity(occupant))
	return occupant_def != null and occupant_def.tags.has(tag)


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
