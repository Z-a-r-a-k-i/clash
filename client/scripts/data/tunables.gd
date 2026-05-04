class_name Tunables
extends Resource

# Map / spatial
@export var map_width: int = 50
@export var map_height: int = 50
@export var tile_pixel_size: int = 32

# Population
@export var pop_cap: int = 50

# Match start defaults
@export var starting_workers: int = 4
@export var starting_minerals: int = 50
@export var starting_gas: int = 0
@export var default_turn_timer_ms: int = 30000

# Resources
@export var mineral_patch_yield_per_worker_per_turn: int = 1
@export var mineral_patch_capacity: int = 1500
@export var gas_geyser_yield_per_worker_per_turn: int = 1
@export var gas_geyser_capacity: int = -1  # -1 = infinite (M0 default)
@export var worker_carry_amount: int = 5

# Visibility
@export var layers_implying_hidden: Array[String] = ["burrowed"]
