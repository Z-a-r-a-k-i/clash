class_name GatherState
extends RefCounted

# Per-entity runtime state for entities with a GatherDef capability
# (workers). Tracks autonomous gathering: which resource source they're
# assigned to, how much they're carrying, and whether they're currently
# in the "deposit" phase of the gather loop.

var assigned_source_entity_id: int = -1  # -1 if unassigned
var carrying_resource_type: String = ""  # "minerals" | "gas" | "" if empty
var carrying_amount: int = 0
var phase: String = "idle"  # "idle" | "moving_to_source" | "gathering" | "moving_to_base" | "depositing"
