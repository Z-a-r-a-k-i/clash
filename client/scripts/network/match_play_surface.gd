class_name MatchPlaySurface
extends Node

const MATCH_SCENE_PATH := "res://scenes/match.tscn"
const MATCH_3D_SCENE_PATH := "res://scenes/match_3d.tscn"

var _renderer: Variant = null
var _state: MatchState = null
var _registry: EntityRegistry = null
var _player_slot: int = -1


func _ready() -> void:
	_ensure_renderer()


func bind_authoritative_state(
	state: MatchState, registry: EntityRegistry, player_slot: int
) -> void:
	_ensure_renderer()
	_state = state
	_registry = registry
	_player_slot = player_slot
	if _renderer != null:
		_renderer.bind_state(_state, _registry)
		_renderer.set_perspective_player_id(_player_slot)
		_renderer.focus_player_start(_player_slot)


func render_authoritative_result(new_state: MatchState, events: Array) -> void:
	_ensure_renderer()
	_state = new_state
	if _renderer != null:
		_renderer.render_step(new_state, _typed_events(events))
		_renderer.set_perspective_player_id(_player_slot)


func renderer() -> Variant:
	_ensure_renderer()
	return _renderer


func current_state() -> MatchState:
	return _state


func registry() -> EntityRegistry:
	return _registry


func player_slot() -> int:
	return _player_slot


func _ensure_renderer() -> void:
	if _renderer != null:
		return
	var scene_path: String = (
		MATCH_3D_SCENE_PATH if DisplayServer.get_name() != "headless" else MATCH_SCENE_PATH
	)
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("MatchPlaySurface: failed to load %s" % scene_path)
		return
	_renderer = packed.instantiate()
	if _renderer == null:
		push_error("MatchPlaySurface: match scene failed to instantiate.")
		return
	add_child(_renderer)


func _typed_events(events: Array) -> Array[ResolverEvent]:
	var out: Array[ResolverEvent] = []
	for item in events:
		var event: ResolverEvent = item as ResolverEvent
		if event != null:
			out.append(event)
	return out
