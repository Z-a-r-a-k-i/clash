class_name NetworkV0Codec
extends RefCounted

const _MAGIC_BYTES: Array[int] = [67, 76, 83, 72, 86, 48]  # "CLSHV0"
const _TYPE_KEY: String = "__clash_type"
const _TYPE_RESOLVER_EVENT: String = "ResolverEvent"
const _TYPE_SUBMIT_TURN: String = "SubmitTurn"
const _TYPE_ENTITY_ORDER: String = "EntityOrder"
const _TYPE_MATCH_STATE: String = "MatchState"
const _TYPE_PLAYER_STATE: String = "PlayerState"
const _TYPE_ENTITY: String = "Entity"
const _TYPE_TILE_GRID: String = "TileGrid"
const _TYPE_ACTIVE_BUFF: String = "ActiveBuff"
const _TYPE_ABILITY_CAST_STATE: String = "AbilityCastState"
const _TYPE_PRODUCTION_STATE: String = "ProductionState"
const _TYPE_GATHER_STATE: String = "GatherState"
const _TYPE_ENTITY_REGISTRY: String = "EntityRegistry"

# Same-version v0 wire codec. The payload is Godot Variant bytes, but the
# network boundary only decodes primitive Variant containers and then rebuilds
# the small whitelist of Clash runtime objects used by this playtest slice.


func encode(message: Dictionary) -> PackedByteArray:
	if message.is_empty():
		return PackedByteArray()
	var payload: PackedByteArray = var_to_bytes(_normalize(message))
	var out: PackedByteArray = _magic()
	out.append_array(payload)
	return out


func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() <= _MAGIC_BYTES.size() or not _has_magic(bytes):
		return {}
	var payload: PackedByteArray = bytes.slice(_MAGIC_BYTES.size())
	var decoded: Variant = bytes_to_var(payload)
	var denormalized: Variant = _denormalize(decoded)
	if not denormalized is Dictionary:
		return {}
	return denormalized


func _has_magic(bytes: PackedByteArray) -> bool:
	for i: int in range(_MAGIC_BYTES.size()):
		if bytes[i] != _MAGIC_BYTES[i]:
			return false
	return true


func _magic() -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	for byte: int in _MAGIC_BYTES:
		out.append(byte)
	return out


func _normalize(value: Variant) -> Variant:
	if value is ResolverEvent:
		return _normalize_resolver_event(value as ResolverEvent)
	if value is SubmitTurn:
		return _normalize_submit_turn(value as SubmitTurn)
	if value is EntityOrder:
		return _normalize_entity_order(value as EntityOrder)
	if value is MatchState:
		return _normalize_match_state(value as MatchState)
	if value is PlayerState:
		return _normalize_player_state(value as PlayerState)
	if value is Entity:
		return _normalize_entity(value as Entity)
	if value is TileGrid:
		return _normalize_tile_grid(value as TileGrid)
	if value is ActiveBuff:
		return _normalize_active_buff(value as ActiveBuff)
	if value is AbilityCastState:
		return _normalize_ability_cast_state(value as AbilityCastState)
	if value is ProductionState:
		return _normalize_production_state(value as ProductionState)
	if value is GatherState:
		return _normalize_gather_state(value as GatherState)
	if value is EntityRegistry:
		return _normalize_entity_registry(value as EntityRegistry)
	if value is Array:
		var out_array: Array = []
		for item: Variant in value:
			out_array.append(_normalize(item))
		return out_array
	if value is Dictionary:
		var out_dict: Dictionary = {}
		var source: Dictionary = value
		for key: Variant in source.keys():
			out_dict[key] = _normalize(source[key])
		return out_dict
	return value


func _denormalize(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value
		var clash_type: String = source.get(_TYPE_KEY, "")
		match clash_type:
			_TYPE_RESOLVER_EVENT:
				return _resolver_event_from_dict(source)
			_TYPE_SUBMIT_TURN:
				return _submit_turn_from_dict(source)
			_TYPE_ENTITY_ORDER:
				return _entity_order_from_dict(source)
			_TYPE_MATCH_STATE:
				return _match_state_from_dict(source)
			_TYPE_PLAYER_STATE:
				return _player_state_from_dict(source)
			_TYPE_ENTITY:
				return _entity_from_dict(source)
			_TYPE_TILE_GRID:
				return _tile_grid_from_dict(source)
			_TYPE_ACTIVE_BUFF:
				return _active_buff_from_dict(source)
			_TYPE_ABILITY_CAST_STATE:
				return _ability_cast_state_from_dict(source)
			_TYPE_PRODUCTION_STATE:
				return _production_state_from_dict(source)
			_TYPE_GATHER_STATE:
				return _gather_state_from_dict(source)
			_TYPE_ENTITY_REGISTRY:
				return _entity_registry_from_dict(source)
		var out_dict: Dictionary = {}
		for key: Variant in source.keys():
			out_dict[key] = _denormalize(source[key])
		return out_dict
	if value is Array:
		var out_array: Array = []
		for item: Variant in value:
			out_array.append(_denormalize(item))
		return out_array
	return value


func _normalize_resolver_event(event: ResolverEvent) -> Dictionary:
	return {
		_TYPE_KEY: _TYPE_RESOLVER_EVENT,
		"type": event.type,
		"actor_id": event.actor_id,
		"target_id": event.target_id,
		"from_origin": event.from_origin,
		"to_origin": event.to_origin,
		"damage": event.damage,
		"hp_after": event.hp_after,
		"new_def_id": event.new_def_id,
		"def_id": event.def_id,
		"winner_player_id": event.winner_player_id,
		"amount": event.amount,
	}


func _normalize_submit_turn(submit: SubmitTurn) -> Dictionary:
	return {
		_TYPE_KEY: _TYPE_SUBMIT_TURN,
		"orders": _normalize(submit.orders),
		"surrender": submit.surrender,
	}


func _normalize_entity_order(order: EntityOrder) -> Dictionary:
	return {
		_TYPE_KEY: _TYPE_ENTITY_ORDER,
		"type": order.type,
		"entity_id": order.entity_id,
		"target_tile": order.target_tile,
		"target_priority_chain": order.target_priority_chain.duplicate(),
		"def_id": order.def_id,
		"cancel_index": order.cancel_index,
		"target_entity_id": order.target_entity_id,
		"mode": order.mode,
		"enabled": order.enabled,
	}


func _normalize_match_state(state: MatchState) -> Dictionary:
	return {
		_TYPE_KEY: _TYPE_MATCH_STATE,
		"turn_index": state.turn_index,
		"rng_seed": state.rng_seed,
		"players": _normalize(state.players),
		"entities": _normalize(state.entities),
		"next_entity_id": state.next_entity_id,
		"tile_grid": _normalize(state.tile_grid),
		"winner_player_id": state.winner_player_id,
		"match_over": state.match_over,
	}


func _normalize_player_state(player: PlayerState) -> Dictionary:
	return {
		_TYPE_KEY: _TYPE_PLAYER_STATE,
		"player_id": player.player_id,
		"minerals": player.minerals,
		"gas": player.gas,
		"pop_used": player.pop_used,
		"pop_cap": player.pop_cap,
		"has_surrendered": player.has_surrendered,
		"unlocked_researches": player.unlocked_researches.duplicate(),
	}


func _normalize_entity(entity: Entity) -> Dictionary:
	return {
		_TYPE_KEY: _TYPE_ENTITY,
		"id": entity.id,
		"def_id": entity.def_id,
		"current_def_id": entity.current_def_id,
		"owner_player_id": entity.owner_player_id,
		"origin": entity.origin,
		"current_layer": entity.current_layer,
		"current_hp": entity.current_hp,
		"order_queue": _normalize(entity.order_queue),
		"persistent_order": _normalize(entity.persistent_order),
		"focus_target_entity_id": entity.focus_target_entity_id,
		"ability_cooldowns": _normalize(entity.ability_cooldowns),
		"active_buffs": _normalize(entity.active_buffs),
		"ability_cast": _normalize(entity.ability_cast),
		"is_hidden": entity.is_hidden,
		"moves_used_this_turn": entity.moves_used_this_turn,
		"current_resource_amount": entity.current_resource_amount,
		"is_constructing": entity.is_constructing,
		"construction_turns_remaining": entity.construction_turns_remaining,
		"construction_worker_id": entity.construction_worker_id,
		"locked_to_building_id": entity.locked_to_building_id,
		"pending_build_def_id": entity.pending_build_def_id,
		"pending_build_target_tile": entity.pending_build_target_tile,
		"pending_build_target_entity_id": entity.pending_build_target_entity_id,
		"production_state": _normalize(entity.production_state),
		"gather_state": _normalize(entity.gather_state),
	}


func _normalize_tile_grid(grid: TileGrid) -> Dictionary:
	return {
		_TYPE_KEY: _TYPE_TILE_GRID,
		"width": grid.width,
		"height": grid.height,
		"occupancy": _normalize(grid.get("_occupancy")),
		"terrain_tags": _normalize(grid.get("_terrain_tags")),
		"entity_rects": _normalize(grid.get("_entity_rects")),
	}


func _normalize_active_buff(buff: ActiveBuff) -> Dictionary:
	return {
		_TYPE_KEY: _TYPE_ACTIVE_BUFF,
		"source_ability_id": buff.source_ability_id,
		"turns_remaining": buff.turns_remaining,
		"damage_mult": buff.damage_mult,
		"speed_mult": buff.speed_mult,
	}


func _normalize_ability_cast_state(cast_state: AbilityCastState) -> Dictionary:
	return {
		_TYPE_KEY: _TYPE_ABILITY_CAST_STATE,
		"ability_id": cast_state.ability_id,
		"turns_remaining": cast_state.turns_remaining,
	}


func _normalize_production_state(production: ProductionState) -> Dictionary:
	return {
		_TYPE_KEY: _TYPE_PRODUCTION_STATE,
		"active": _normalize(production.active),
		"queue": _normalize(production.queue),
		"repeat_train_enabled": production.repeat_train_enabled,
		"repeat_train_def_id": production.repeat_train_def_id,
		"rally_mode": production.rally_mode,
		"rally_target_tile": production.rally_target_tile,
		"rally_target_entity_id": production.rally_target_entity_id,
	}


func _normalize_gather_state(gather: GatherState) -> Dictionary:
	return {
		_TYPE_KEY: _TYPE_GATHER_STATE,
		"assigned_source_entity_id": gather.assigned_source_entity_id,
		"carrying_resource_type": gather.carrying_resource_type,
		"carrying_amount": gather.carrying_amount,
		"phase": gather.phase,
	}


func _normalize_entity_registry(registry: EntityRegistry) -> Dictionary:
	return {
		_TYPE_KEY: _TYPE_ENTITY_REGISTRY,
		"path": registry.resource_path,
	}


func _resolver_event_from_dict(source: Dictionary) -> ResolverEvent:
	var event: ResolverEvent = ResolverEvent.new()
	event.type = source.get("type", ResolverEvent.Type.INVALID)
	event.actor_id = source.get("actor_id", -1)
	event.target_id = source.get("target_id", -1)
	event.from_origin = source.get("from_origin", Vector2i.ZERO)
	event.to_origin = source.get("to_origin", Vector2i.ZERO)
	event.damage = source.get("damage", 0)
	event.hp_after = source.get("hp_after", 0)
	event.new_def_id = source.get("new_def_id", "")
	event.def_id = source.get("def_id", "")
	event.winner_player_id = source.get("winner_player_id", -1)
	event.amount = source.get("amount", 0)
	return event


func _submit_turn_from_dict(source: Dictionary) -> SubmitTurn:
	var submit: SubmitTurn = SubmitTurn.new()
	submit.orders = _entity_order_array(source.get("orders", []))
	submit.surrender = source.get("surrender", false)
	return submit


func _entity_order_from_dict(source: Dictionary) -> EntityOrder:
	var order: EntityOrder = EntityOrder.new()
	order.type = source.get("type", EntityOrder.Type.INVALID)
	order.entity_id = source.get("entity_id", -1)
	order.target_tile = source.get("target_tile", Vector2i.ZERO)
	order.target_priority_chain = _int_array(source.get("target_priority_chain", []))
	order.def_id = source.get("def_id", "")
	order.cancel_index = source.get("cancel_index", -1)
	order.target_entity_id = source.get("target_entity_id", -1)
	order.mode = source.get("mode", "")
	order.enabled = source.get("enabled", false)
	return order


func _match_state_from_dict(source: Dictionary) -> MatchState:
	var state: MatchState = MatchState.new()
	state.turn_index = source.get("turn_index", 0)
	state.rng_seed = source.get("rng_seed", 0)
	state.players = _player_state_array(source.get("players", []))
	state.entities = _entity_array(source.get("entities", []))
	state.next_entity_id = source.get("next_entity_id", 1)
	state.tile_grid = _denormalize(source.get("tile_grid", null)) as TileGrid
	state.winner_player_id = source.get("winner_player_id", -1)
	state.match_over = source.get("match_over", false)
	return state


func _player_state_from_dict(source: Dictionary) -> PlayerState:
	var player: PlayerState = PlayerState.new()
	player.player_id = source.get("player_id", 0)
	player.minerals = source.get("minerals", 0)
	player.gas = source.get("gas", 0)
	player.pop_used = source.get("pop_used", 0)
	player.pop_cap = source.get("pop_cap", 0)
	player.has_surrendered = source.get("has_surrendered", false)
	player.unlocked_researches = _string_array(source.get("unlocked_researches", []))
	return player


func _entity_from_dict(source: Dictionary) -> Entity:
	var entity: Entity = Entity.new()
	entity.id = source.get("id", -1)
	entity.def_id = source.get("def_id", "")
	entity.current_def_id = source.get("current_def_id", "")
	entity.owner_player_id = source.get("owner_player_id", 0)
	entity.origin = source.get("origin", Vector2i.ZERO)
	entity.current_layer = source.get("current_layer", "")
	entity.current_hp = source.get("current_hp", 0)
	entity.order_queue = _entity_order_array(source.get("order_queue", []))
	entity.persistent_order = _denormalize(source.get("persistent_order", null)) as EntityOrder
	entity.focus_target_entity_id = source.get("focus_target_entity_id", -1)
	var ability_cooldowns: Variant = _denormalize(source.get("ability_cooldowns", {}))
	entity.ability_cooldowns = ability_cooldowns if ability_cooldowns is Dictionary else {}
	entity.active_buffs = _active_buff_array(source.get("active_buffs", []))
	entity.ability_cast = (_denormalize(source.get("ability_cast", null)) as AbilityCastState)
	entity.is_hidden = source.get("is_hidden", false)
	entity.moves_used_this_turn = source.get("moves_used_this_turn", 0)
	entity.current_resource_amount = source.get("current_resource_amount", -1)
	entity.is_constructing = source.get("is_constructing", false)
	entity.construction_turns_remaining = source.get("construction_turns_remaining", -1)
	entity.construction_worker_id = source.get("construction_worker_id", -1)
	entity.locked_to_building_id = source.get("locked_to_building_id", -1)
	entity.pending_build_def_id = source.get("pending_build_def_id", "")
	entity.pending_build_target_tile = source.get("pending_build_target_tile", Vector2i.ZERO)
	entity.pending_build_target_entity_id = source.get("pending_build_target_entity_id", -1)
	entity.production_state = _denormalize(source.get("production_state", null)) as ProductionState
	entity.gather_state = _denormalize(source.get("gather_state", null)) as GatherState
	return entity


func _tile_grid_from_dict(source: Dictionary) -> TileGrid:
	var grid: TileGrid = TileGrid.new(source.get("width", 0), source.get("height", 0))
	var occupancy: Variant = _denormalize(source.get("occupancy", {}))
	var terrain_tags: Variant = _denormalize(source.get("terrain_tags", {}))
	var entity_rects: Variant = _denormalize(source.get("entity_rects", {}))
	grid.set("_occupancy", occupancy if occupancy is Dictionary else {})
	grid.set("_terrain_tags", terrain_tags if terrain_tags is Dictionary else {})
	grid.set("_entity_rects", entity_rects if entity_rects is Dictionary else {})
	return grid


func _active_buff_from_dict(source: Dictionary) -> ActiveBuff:
	var buff: ActiveBuff = ActiveBuff.new()
	buff.source_ability_id = source.get("source_ability_id", "")
	buff.turns_remaining = source.get("turns_remaining", 0)
	buff.damage_mult = source.get("damage_mult", 1.0)
	buff.speed_mult = source.get("speed_mult", 1.0)
	return buff


func _ability_cast_state_from_dict(source: Dictionary) -> AbilityCastState:
	var cast_state: AbilityCastState = AbilityCastState.new()
	cast_state.ability_id = source.get("ability_id", "")
	cast_state.turns_remaining = source.get("turns_remaining", 0)
	return cast_state


func _production_state_from_dict(source: Dictionary) -> ProductionState:
	var production: ProductionState = ProductionState.new()
	var active: Variant = _denormalize(source.get("active", {}))
	production.active = active if active is Dictionary else {}
	production.queue = _dictionary_array(source.get("queue", []))
	production.repeat_train_enabled = source.get("repeat_train_enabled", false)
	production.repeat_train_def_id = source.get("repeat_train_def_id", "")
	production.rally_mode = source.get("rally_mode", ProductionState.RALLY_MODE_NONE)
	production.rally_target_tile = source.get("rally_target_tile", Vector2i.ZERO)
	production.rally_target_entity_id = source.get("rally_target_entity_id", -1)
	return production


func _gather_state_from_dict(source: Dictionary) -> GatherState:
	var gather: GatherState = GatherState.new()
	gather.assigned_source_entity_id = source.get("assigned_source_entity_id", -1)
	gather.carrying_resource_type = source.get("carrying_resource_type", "")
	gather.carrying_amount = source.get("carrying_amount", 0)
	gather.phase = source.get("phase", GatherState.Phase.IDLE)
	return gather


func _entity_registry_from_dict(source: Dictionary) -> EntityRegistry:
	var path: String = source.get("path", "")
	if path == "":
		return null
	return load(path) as EntityRegistry


func _entity_order_array(value: Variant) -> Array[EntityOrder]:
	var out: Array[EntityOrder] = []
	if not value is Array:
		return out
	for item: Variant in value:
		out.append(_denormalize(item) as EntityOrder)
	return out


func _player_state_array(value: Variant) -> Array[PlayerState]:
	var out: Array[PlayerState] = []
	if not value is Array:
		return out
	for item: Variant in value:
		out.append(_denormalize(item) as PlayerState)
	return out


func _entity_array(value: Variant) -> Array[Entity]:
	var out: Array[Entity] = []
	if not value is Array:
		return out
	for item: Variant in value:
		out.append(_denormalize(item) as Entity)
	return out


func _active_buff_array(value: Variant) -> Array[ActiveBuff]:
	var out: Array[ActiveBuff] = []
	if not value is Array:
		return out
	for item: Variant in value:
		out.append(_denormalize(item) as ActiveBuff)
	return out


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not value is Array:
		return out
	for item: Variant in value:
		var denormalized: Variant = _denormalize(item)
		out.append(denormalized if denormalized is Dictionary else {})
	return out


func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if not value is Array:
		return out
	for item: Variant in value:
		out.append(str(item))
	return out


func _int_array(value: Variant) -> Array[int]:
	var out: Array[int] = []
	if not value is Array:
		return out
	for item: Variant in value:
		out.append(int(item))
	return out
