extends Node

# Dev launcher that loads a scenario into MatchRenderer for visual review.
# Run this scene to see the renderer with real entities on screen.
#
# Plan node: plan/m0/07-dev-play-mode/07b1-renderer-and-camera.md

const MATCH_SCENE_PATH := "res://scenes/match.tscn"
const REGISTRY_PATH := "res://data/entity_registry.tres"
const TUNABLES_PATH := "res://data/tunables.tres"

@export_file("*.tres")
var scenario_path: String = "res://data/scenarios/combat_marines_vs_tanks.tres"

# When true, repeatedly fires synthetic ENTITY_DAMAGED events on a timer
# so the attack overlay + damage label + combat log are visible in
# screenshots regardless of when the capture lands.
@export var fire_demo_attack: bool = true
@export var demo_attack_interval_seconds: float = 1.5

var _renderer: MatchRenderer = null
var _loaded: LoadedScenario = null
var _attacker_id: int = -1
var _target_id: int = -1


func _ready() -> void:
	var scenario: ScenarioDef = load(scenario_path) as ScenarioDef
	var registry: EntityRegistry = load(REGISTRY_PATH) as EntityRegistry
	var tunables: Tunables = load(TUNABLES_PATH) as Tunables
	if scenario == null or registry == null or tunables == null:
		push_error("render_preview: missing scenario / registry / tunables")
		return

	_loaded = ScenarioLoader.load(scenario, registry, tunables)
	if _loaded == null:
		push_error("render_preview: ScenarioLoader returned null")
		return
	var match_packed: PackedScene = load(MATCH_SCENE_PATH) as PackedScene
	if match_packed == null:
		push_error("render_preview: failed to load %s" % MATCH_SCENE_PATH)
		return
	_renderer = match_packed.instantiate() as MatchRenderer
	if _renderer == null:
		push_error("render_preview: match scene root is not a MatchRenderer")
		return
	add_child(_renderer)
	_renderer.bind_state(_loaded.state, _loaded.registry)

	if fire_demo_attack and _loaded.state.entities.size() >= 2:
		_attacker_id = _loaded.state.entities[0].id
		for entity in _loaded.state.entities:
			if (
				entity.owner_player_id != _loaded.state.entities[0].owner_player_id
				and entity.owner_player_id >= 0
			):
				_target_id = entity.id
				break
		if _target_id < 0:
			push_warning("render_preview: no opposing target found; demo attack disabled")
			return
		_fire_demo_attack()
		var timer: Timer = Timer.new()
		timer.wait_time = demo_attack_interval_seconds
		timer.autostart = true
		timer.timeout.connect(_fire_demo_attack)
		add_child(timer)


func _fire_demo_attack() -> void:
	if _renderer == null or _attacker_id < 0 or _target_id < 0:
		return
	var event: ResolverEvent = ResolverEvent.new()
	event.type = ResolverEvent.Type.ENTITY_DAMAGED
	event.actor_id = _attacker_id
	event.target_id = _target_id
	event.damage = 12
	event.hp_after = 100  # cosmetic; the demo never destroys the target
	_renderer.render_step(_loaded.state, [event])
