class_name EntityView3D
extends Node3D

# 3D visual representation of a single Entity (3d-renderer branch):
# hosts a normalized Space Kit model, an emissive team ring, a billboard
# HP bar, and a selection ring. Zero game logic — MatchRenderer3D pushes
# state in via update_from_state(). Origin = footprint center on the
# ground plane; positions are in world units (1.0 = one tile).

const COLOR_PLAYER_0 := Color(0.2, 0.9, 1.0)
const COLOR_PLAYER_1 := Color(1.0, 0.25, 0.7)
const COLOR_NEUTRAL := Color(0.75, 0.8, 0.85)
const COLOR_SELECTION := Color(1.0, 1.0, 1.0)
const SILHOUETTE_COLOR := Color(0.32, 0.36, 0.42)
const CONSTRUCTION_TRANSPARENCY := 0.55
const HP_HIGH := Color(0.25, 1.0, 0.65)
const HP_LOW := Color(1.0, 0.2, 0.3)
const FLASH_SECONDS := 0.16

static var _silhouette_material: StandardMaterial3D = null

var _entity_id: int = -1
var _owner_player_id: int = -1
var _visual_key: String = ""
var _footprint: Vector2i = Vector2i.ONE
var _fog_silhouette: bool = false
var _is_constructing: bool = false
var _model: Node3D = null
var _team_ring: MeshInstance3D = null
var _selection_ring: MeshInstance3D = null
var _hp_back: MeshInstance3D = null
var _hp_fill: MeshInstance3D = null
var _hp_ratio: float = 1.0
var _hp_visible: bool = false
var _model_height: float = 1.0
var _flash_tween: Tween = null


func bind_entity_id(id: int) -> void:
	_entity_id = id


func get_entity_id() -> int:
	return _entity_id


func update_from_state(
	entity: Entity, def: EntityDef, visual_key: String, placement_rect: Rect2i
) -> void:
	var fp := Vector2i(maxi(placement_rect.size.x, 1), maxi(placement_rect.size.y, 1))
	_owner_player_id = entity.owner_player_id
	_is_constructing = entity.is_constructing
	_footprint = fp
	position = Vector3(
		placement_rect.position.x + fp.x * 0.5, 0.0, placement_rect.position.y + fp.y * 0.5
	)
	_ensure_model(visual_key, fp)
	_ensure_rings(fp)
	_update_hp(entity, def)
	_apply_presentation()


func visual_key() -> String:
	return _visual_key


func face_direction(direction: Vector2) -> void:
	if _model == null or direction == Vector2.ZERO:
		return
	# Kenney models face +Z; atan2 maps a tile-space direction onto a
	# yaw around Y (tile +y is world +z).
	_model.rotation.y = atan2(direction.x, direction.y)


func set_selected(selected: bool) -> void:
	if _selection_ring != null:
		_selection_ring.visible = selected and not _fog_silhouette


func set_fog_silhouette(enabled: bool) -> void:
	_fog_silhouette = enabled
	_apply_presentation()


func is_fog_silhouette() -> bool:
	return _fog_silhouette


func flash_hit() -> void:
	if _model == null or not is_inside_tree() or Engine.is_editor_hint():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_model.scale = Vector3.ONE * 1.18
	_flash_tween = _model.create_tween()
	_flash_tween.tween_property(_model, "scale", Vector3.ONE, FLASH_SECONDS)


func model_height() -> float:
	return _model_height


func fade_out_and_despawn(duration_seconds: float = 1.0) -> void:
	if not is_inside_tree() or Engine.is_editor_hint():
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, duration_seconds)
	tween.tween_callback(queue_free)


static func color_for_owner(owner_player_id: int) -> Color:
	match owner_player_id:
		0:
			return COLOR_PLAYER_0
		1:
			return COLOR_PLAYER_1
		_:
			return COLOR_NEUTRAL


func _ensure_model(visual_key: String, fp: Vector2i) -> void:
	if visual_key == _visual_key and _model != null:
		return
	if _model != null:
		_model.queue_free()
	_visual_key = visual_key
	_model = UnitModels3D.build(visual_key, maxf(float(maxi(fp.x, fp.y)) * 0.86, 0.5))
	add_child(_model)
	var box := UnitModels3D.merged_aabb(_model, Transform3D.IDENTITY)
	_model_height = maxf(box.size.y, 0.4)


func _ensure_rings(fp: Vector2i) -> void:
	# Neutral resources keep their natural look without rings.
	var wants_ring := _owner_player_id >= 0
	if _team_ring == null and wants_ring:
		_team_ring = _make_ring(color_for_owner(_owner_player_id), 0.06)
		add_child(_team_ring)
		_selection_ring = _make_ring(COLOR_SELECTION, 0.045)
		_selection_ring.position.y = 0.1
		_selection_ring.visible = false
		add_child(_selection_ring)
	if _team_ring != null:
		var radius := maxf(float(maxi(fp.x, fp.y)) * 0.5, 0.42)
		_team_ring.scale = Vector3(radius / 0.5, 1.0, radius / 0.5)
		_selection_ring.scale = Vector3(radius / 0.5 * 1.12, 1.0, radius / 0.5 * 1.12)


func _make_ring(color: Color, thickness: float) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5 - thickness
	torus.outer_radius = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torus.material = mat
	var node := MeshInstance3D.new()
	node.mesh = torus
	node.position.y = 0.04
	node.scale = Vector3(1.0, 0.22, 1.0)
	return node


func _update_hp(entity: Entity, def: EntityDef) -> void:
	var max_hp: int = def.health.max_hp if def != null and def.health != null else 0
	_hp_visible = max_hp > 0 and entity.current_hp > 0 and entity.current_hp < max_hp
	_hp_ratio = clampf(float(entity.current_hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	if not _hp_visible:
		if _hp_back != null:
			_hp_back.visible = false
			_hp_fill.visible = false
		return
	if _hp_back == null:
		_hp_back = _make_hp_quad(Color(0.02, 0.04, 0.07, 0.9), 0.001)
		add_child(_hp_back)
		_hp_fill = _make_hp_quad(HP_HIGH, 0.002)
		add_child(_hp_fill)
	var width := maxf(float(_footprint.x) * 0.8, 0.6)
	var height := _model_height + 0.35
	_hp_back.position = Vector3(0.0, height, 0.0)
	(_hp_back.mesh as QuadMesh).size = Vector2(width, 0.09)
	_hp_fill.position = Vector3(-width * (1.0 - _hp_ratio) * 0.5, height, 0.0)
	(_hp_fill.mesh as QuadMesh).size = Vector2(width * _hp_ratio, 0.06)
	var fill_mat := (_hp_fill.mesh as QuadMesh).material as StandardMaterial3D
	fill_mat.albedo_color = HP_LOW.lerp(HP_HIGH, _hp_ratio)
	_hp_back.visible = not _fog_silhouette
	_hp_fill.visible = not _fog_silhouette


func _make_hp_quad(color: Color, depth_offset: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 10 + int(depth_offset * 1000.0)
	quad.material = mat
	var node := MeshInstance3D.new()
	node.mesh = quad
	return node


func _apply_presentation() -> void:
	if _model != null:
		_apply_material_override(_model, _silhouette_mat() if _fog_silhouette else null)
		_set_transparency(
			_model, CONSTRUCTION_TRANSPARENCY if _is_constructing and not _fog_silhouette else 0.0
		)
	if _team_ring != null:
		_team_ring.visible = not _fog_silhouette
	if _selection_ring != null and _fog_silhouette:
		_selection_ring.visible = false
	if _hp_back != null:
		_hp_back.visible = _hp_visible and not _fog_silhouette
		_hp_fill.visible = _hp_visible and not _fog_silhouette


static func _silhouette_mat() -> StandardMaterial3D:
	if _silhouette_material == null:
		_silhouette_material = StandardMaterial3D.new()
		_silhouette_material.albedo_color = SILHOUETTE_COLOR
		_silhouette_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _silhouette_material


func _apply_material_override(node: Node, material: Material) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = material
	for child in node.get_children():
		_apply_material_override(child, material)


func _set_transparency(node: Node, amount: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).transparency = amount
	for child in node.get_children():
		_set_transparency(child, amount)
