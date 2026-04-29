class_name ResearchDef
extends Resource

# Research definitions for the production / tech-tree system.
#
# At M0 no concrete researches are authored — the class exists only so
# ProductionDef.researches[] (an Array of research ids) has something to
# resolve against once we wire the registry. The effect-schema design
# (whether effects are a small DSL or hardcoded Effect subclasses) is
# deferred because we don't yet have concrete researches that exercise
# the full requirement space; picking a schema now would be guesswork.

@export var id: String = ""
@export var display_name: String = ""
@export var mineral_cost: int = 0:
	set(value):
		mineral_cost = max(0, value)
@export var gas_cost: int = 0:
	set(value):
		gas_cost = max(0, value)
@export var research_time_turns: int = 1:
	set(value):
		research_time_turns = max(1, value)
