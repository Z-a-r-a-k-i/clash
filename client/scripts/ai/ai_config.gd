@tool
class_name AiConfig
extends Resource

# Strategy configuration for AiPlayer (plan m1/01). Difficulty and
# personality are DATA, not code: the three shipped strategies under
# client/data/ai/ are hand-authored canon.

# Opening sequence, consumed left to right. Entries are def ids: units
# are trained at a matching idle producer, buildings are built by a
# worker near the main. After the list is exhausted the steady-state
# unit mix takes over.
@export var build_order: Array[String] = []

# Steady-state army composition weights (def id -> relative weight).
# The planner trains whichever mixed unit is furthest below its target
# share, producer and resources permitting.
@export var unit_mix: Dictionary = {"marine": 1}

# Launch an attack when the army's mineral+gas value reaches this.
@export var attack_army_value: int = 800

# While attacking, retreat to staging when own army value drops below
# this percentage of the last-seen enemy army value.
@export var retreat_below_enemy_pct: int = 60

# Tiles to advance the staging point from the main toward map center.
@export var staging_advance_tiles: int = 8

# Send a scout (lowest-id army unit) once this turn is reached and the
# enemy hasn't been seen for `scout_stale_turns`.
@export var scout_turn: int = 6
@export var scout_stale_turns: int = 10

# Plan only every Nth turn (1 = every turn). Coarser cadence = weaker AI.
@export var decision_cadence: int = 1

# Extra workers beyond total gather slots near owned bases.
@export var worker_margin: int = 1

# Expand when banked minerals exceed base cost plus this buffer and the
# current bases' sources are saturated (or mined out).
@export var expand_mineral_buffer: int = 150

# Omniscient baseline for the simulator; fog-honest when false.
@export var cheats_vision: bool = false

# Reserved for future randomized behavior; determinism requires that
# any randomness derive from this seed.
@export var seed: int = 0
