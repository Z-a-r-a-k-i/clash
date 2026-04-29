class_name ActiveBuff
extends RefCounted

# A stat modifier currently applied to an entity. Created by an ability
# that has a StatBuffEffect. The resolver decrements turns_remaining each
# turn end and removes buffs at zero.

var source_ability_id: String = ""  # which AbilityDef created this buff
var turns_remaining: int = 0
var damage_mult: float = 1.0
var speed_mult: float = 1.0
