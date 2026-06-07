class_name NetworkV0Codec
extends RefCounted

const _MAGIC_BYTES := [67, 76, 83, 72, 86, 48]  # "CLSHV0"

# Same-version v0 wire codec. This deliberately allows Godot objects so
# MatchState, SubmitTurn, and ResolverEvent can cross the dev/playtest
# WebSocket without a schema copy. The boundary stays isolated here so a
# future protobuf/Go migration replaces this adapter, not game logic.


func encode(message: Dictionary) -> PackedByteArray:
	if message.is_empty():
		return PackedByteArray()
	var payload: PackedByteArray = var_to_bytes_with_objects(_normalize(message))
	var out: PackedByteArray = _magic()
	out.append_array(payload)
	return out


func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() <= _MAGIC_BYTES.size() or not _has_magic(bytes):
		return {}
	var payload: PackedByteArray = bytes.slice(_MAGIC_BYTES.size())
	var decoded: Variant = bytes_to_var_with_objects(payload)
	var denormalized: Variant = _denormalize(decoded)
	if not denormalized is Dictionary:
		return {}
	return denormalized


func _has_magic(bytes: PackedByteArray) -> bool:
	for i in _MAGIC_BYTES.size():
		if bytes[i] != _MAGIC_BYTES[i]:
			return false
	return true


func _magic() -> PackedByteArray:
	var out := PackedByteArray()
	for byte in _MAGIC_BYTES:
		out.append(byte)
	return out


func _normalize(value: Variant) -> Variant:
	if value is ResolverEvent:
		var event: ResolverEvent = value
		return {
			"__clash_type": "ResolverEvent",
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
	if value is Array:
		var out_array: Array = []
		for item in value:
			out_array.append(_normalize(item))
		return out_array
	if value is Dictionary:
		var out_dict: Dictionary = {}
		var source: Dictionary = value
		for key in source.keys():
			out_dict[key] = _normalize(source[key])
		return out_dict
	return value


func _denormalize(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value
		if source.get("__clash_type", "") == "ResolverEvent":
			var event := ResolverEvent.new()
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
		var out_dict: Dictionary = {}
		for key in source.keys():
			out_dict[key] = _denormalize(source[key])
		return out_dict
	if value is Array:
		var out_array: Array = []
		for item in value:
			out_array.append(_denormalize(item))
		return out_array
	return value
