@tool
class_name EntityVisuals
extends Resource

# Maps entity def_id → sprite texture path. Decoupled from EntityRegistry
# so we can swap art without touching gameplay defs.
#
# The renderer queries this resource at EntityView spawn time to pick a
# sprite for each entity. Missing entries fall back to a placeholder
# texture (chunk 3 wires this up); chunk 2 just defines the shape.

@export var sprite_paths: Dictionary[String, String] = {}
# Example: { "marine": "res://data/art/sprites/marine.png", ... }
