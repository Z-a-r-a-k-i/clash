class_name EntityDef
extends Resource

# A single unified data shape for every entity in the game (units, buildings,
# neutrals, future entity kinds). Capability sub-resources are optional —
# null means the entity doesn't have that behaviour.

@export_group("Identity")
@export var id: String = ""
@export var display_name: String = ""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var tags: Array[String] = []
@export var default_hidden: bool = false

@export_group("Capabilities")
@export var health: HealthDef
@export var combat: CombatDef
@export var movement: MovementDef
@export var vision: VisionDef
@export var population: PopulationDef
@export var construction: ConstructionDef
@export var production: ProductionDef
@export var gather: GatherDef
@export var resource_source: ResourceSourceDef
@export var abilities: AbilitiesDef
