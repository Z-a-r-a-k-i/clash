@tool
class_name ScenarioTerrainPatch
extends Resource

# A rectangle of terrain-tagged tiles in a baked scenario (plan/m1/03).
# ScenarioLoader applies `tags` to every tile in `rect` via
# TileGrid.set_tile_terrain_tags; movement defs decide what the tags mean
# (e.g. ground units carry impassable_terrain_tags = ["cliff"]).

@export var rect: Rect2i = Rect2i()
@export var tags: Array[String] = []
