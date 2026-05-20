@tool
class_name ScenarioDef
extends Resource

# A scenario is a fully-specified initial match state (placements, resources,
# optional registry override, optional per-entity stat overrides). Used by
# the dev play mode to load arbitrary game states without grinding through
# a real match. Save / load reuses the same shape.

@export var map_scene: PackedScene
# Tile grid dimensions for the loaded match. Required to be > 0 — the
# setters clamp to 1 so a scenario .tres can never declare a degenerate
# map. Defaults are a sensible smoke size (50x50); plan-08's mvp_map.tres
# overrides them to the actual map size. Visual map_scene handles
# rendering; these give the headless resolver the grid it needs without
# instantiating the scene.
@export var map_width: int = 50:
	set(value):
		map_width = max(1, value)
@export var map_height: int = 50:
	set(value):
		map_height = max(1, value)
@export var starting_resources_per_player: Dictionary = {}
@export var auto_start_workers_on_minerals: bool = false
@export var placements: Array[ScenarioPlacement] = []
@export var registry_override: EntityRegistry  # optional; null => standard registry
@export var stat_overrides: Array[ScenarioStatOverride] = []
