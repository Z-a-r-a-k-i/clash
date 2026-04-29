class_name ScenarioDef
extends Resource

# A scenario is a fully-specified initial match state (placements, resources,
# optional registry override, optional per-entity stat overrides). Used by
# the dev play mode to load arbitrary game states without grinding through
# a real match. Save / load reuses the same shape.

@export var map_scene: PackedScene
@export var starting_resources_per_player: Dictionary = {}
@export var placements: Array[ScenarioPlacement] = []
@export var registry_override: EntityRegistry  # optional; null => standard registry
@export var stat_overrides: Array[ScenarioStatOverride] = []
