class_name UnitModels3D
extends RefCounted

# Def-id → Kenney Space Kit model mapping for the 3D presentation layer
# (3d-renderer branch). Models are CC0 (client/assets/space_kit). Each
# build is AABB-normalized: scaled so its ground footprint spans the
# entity's footprint in world units, recentered, and base-snapped onto
# the ground plane — GLB pivots in the pack are arbitrary.

const MODELS_DIR := "res://assets/space_kit/models"

# Visual keys (def ids + status sprite_keys) → model file stem. Unknown
# keys fall back to the meteor so a missing mapping is obvious in-game
# without crashing.
const MODEL_BY_KEY := {
	"base": "hangar_roundGlass",
	"barracks": "hangar_smallA",
	"factory": "hangar_largeA",
	"starport": "platform_large",
	"refinery": "machine_generatorLarge",
	"worker": "rover",
	"marine": "astronautA",
	"tank": "craft_speederD",
	"siege_tank": "turret_single",
	"helicopter": "craft_racer",
	"mineral_patch": "rock_crystals",
	"mineral_patch_gold": "rock_crystalsLargeA",
	"gas_geyser": "crater",
}
const FALLBACK_MODEL := "meteor"

# Flying units hover above the ground plane.
const HOVER_HEIGHT_BY_KEY := {
	"helicopter": 0.9,
}

static var _scene_cache: Dictionary = {}


# Returns a Node3D wrapper whose origin sits at the footprint center on
# the ground: the model child inside is normalized to `footprint_units`.
static func build(visual_key: String, footprint_units: float) -> Node3D:
	var wrapper := Node3D.new()
	wrapper.name = "Model"
	wrapper.set_meta("visual_key", visual_key)
	var packed := _packed_scene(visual_key)
	if packed == null:
		return wrapper
	var model: Node3D = packed.instantiate() as Node3D
	if model == null:
		return wrapper
	var box := merged_aabb(model, Transform3D.IDENTITY)
	var span := maxf(box.size.x, box.size.z)
	var factor := footprint_units / maxf(span, 0.001)
	model.scale = Vector3.ONE * factor
	var center := box.get_center()
	model.position = Vector3(
		-center.x * factor,
		-box.position.y * factor + float(HOVER_HEIGHT_BY_KEY.get(visual_key, 0.0)),
		-center.z * factor
	)
	wrapper.add_child(model)
	return wrapper


static func merged_aabb(node: Node, parent_transform: Transform3D) -> AABB:
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * (node as Node3D).transform
	var box := AABB()
	var has_box := false
	if node is MeshInstance3D:
		box = transform * (node as MeshInstance3D).get_aabb()
		has_box = true
	for child in node.get_children():
		var child_box := merged_aabb(child, transform)
		if child_box.size != Vector3.ZERO:
			box = box.merge(child_box) if has_box else child_box
			has_box = true
	return box


static func _packed_scene(visual_key: String) -> PackedScene:
	var stem: String = MODEL_BY_KEY.get(visual_key, FALLBACK_MODEL)
	if _scene_cache.has(stem):
		return _scene_cache[stem]
	var packed: PackedScene = load("%s/%s.glb" % [MODELS_DIR, stem]) as PackedScene
	_scene_cache[stem] = packed
	return packed
