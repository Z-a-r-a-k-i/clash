extends Node

# Dev launcher that loads a scenario into MatchRenderer for visual review.
# Run this scene to see the renderer with real entities on screen.
#
# Plan node: plan/m0/07-dev-play-mode/07b1-renderer-and-camera.md

const MATCH_SCENE_PATH := "res://scenes/match.tscn"
const REGISTRY_PATH := "res://data/entity_registry.tres"
const TUNABLES_PATH := "res://data/tunables.tres"

@export_file("*.tres") var scenario_path: String = "res://data/scenarios/mvp_map.tres"


func _ready() -> void:
	var scenario: ScenarioDef = load(scenario_path) as ScenarioDef
	var registry: EntityRegistry = load(REGISTRY_PATH) as EntityRegistry
	var tunables: Tunables = load(TUNABLES_PATH) as Tunables
	if scenario == null or registry == null or tunables == null:
		push_error("render_preview: missing scenario / registry / tunables")
		return

	var loaded: LoadedScenario = ScenarioLoader.load(scenario, registry, tunables)
	if loaded == null:
		push_error("render_preview: ScenarioLoader returned null")
		return
	var renderer: MatchRenderer = (load(MATCH_SCENE_PATH) as PackedScene).instantiate()
	add_child(renderer)
	renderer.bind_state(loaded.state, loaded.registry)
