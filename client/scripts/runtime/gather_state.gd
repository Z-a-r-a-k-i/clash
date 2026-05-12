@tool
class_name GatherState
extends Resource

# Per-entity runtime state for entities with a GatherDef capability
# (workers). Tracks autonomous gathering: which resource source they're
# assigned to, how much they're carrying, and whether they're currently
# in the "deposit" phase of the gather loop.
#
# Resource (not RefCounted) so MatchState save/load via ResourceSaver
# round-trips the gather phase cleanly. Fields are @export for that
# round-trip; clone() stays explicit for the resolver's pure-function
# contract (Resource.duplicate semantics differ from our needs).

enum Phase {
	IDLE,
	MOVING_TO_SOURCE,
	GATHERING,
	MOVING_TO_BASE,
	DEPOSITING,
}

@export var assigned_source_entity_id: int = -1  # -1 if unassigned
@export var carrying_resource_type: String = ""  # "minerals" | "gas" | "" if empty
@export var carrying_amount: int = 0
@export var phase: Phase = Phase.IDLE


func clone() -> GatherState:
	var c := GatherState.new()
	c.assigned_source_entity_id = assigned_source_entity_id
	c.carrying_resource_type = carrying_resource_type
	c.carrying_amount = carrying_amount
	c.phase = phase
	return c
