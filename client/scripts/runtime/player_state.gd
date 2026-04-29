class_name PlayerState
extends RefCounted

# Per-player runtime state. Two players per match at MVP.

var player_id: int = 0
var minerals: int = 0
var gas: int = 0
var pop_used: int = 0
var pop_cap: int = 0
var has_surrendered: bool = false
