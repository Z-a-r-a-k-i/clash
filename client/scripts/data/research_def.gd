class_name ResearchDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var mineral_cost: int = 0
@export var gas_cost: int = 0
@export var research_time_turns: int = 1
# Effect schema deferred (see plan/m0/00 open question).
# At M0 no concrete researches are authored; the class exists for ProductionDef refs.
