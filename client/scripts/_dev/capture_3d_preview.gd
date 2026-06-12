extends SceneTree

# Throwaway 3D art-direction validation scene (plan/m1/04 reboot):
# Kenney Space Kit CC0 models under RTS lighting — one screenshot for
# user approval before converting the roster. Output lands in the
# gitignored docs/visual-references/.

const MODELS := "res://assets/space_kit/models"
const OUT := "res://../docs/visual-references/preview_3d_validation.png"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Render into a fixed-size offscreen viewport so the capture is
	# 1080p regardless of the OS window size.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.013, 0.028)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.6, 0.85)
	env.ambient_light_energy = 0.2
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.05
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-4.0, 4.0, 6.0)
	fill.light_color = Color(0.3, 0.7, 1.0)
	fill.light_energy = 0.6
	fill.omni_range = 18.0
	world.add_child(fill)

	world.add_child(_ground())

	# P0 (cyan) side: base + tank + marines + worker rover.
	_place(world, "hangar_roundGlass", Vector3(-4.6, 0.0, -2.4), 4.2, 25.0)
	_place(world, "satelliteDish", Vector3(-2.0, 0.0, -4.4), 1.5, -15.0)
	_ring(world, Vector3(-0.6, 0.0, 1.8), 1.05, Color(0.2, 0.9, 1.0))
	_place(world, "craft_speederD", Vector3(-0.6, 0.0, 1.8), 2.0, 100.0)
	_ring(world, Vector3(0.8, 0.0, 0.4), 0.38, Color(0.2, 0.9, 1.0))
	_place(world, "astronautA", Vector3(0.8, 0.0, 0.4), 0.55, 80.0)
	_ring(world, Vector3(1.2, 0.0, 2.6), 0.38, Color(0.2, 0.9, 1.0))
	_place(world, "astronautB", Vector3(1.2, 0.0, 2.6), 0.55, 95.0)
	_ring(world, Vector3(-2.4, 0.0, 3.4), 0.75, Color(0.2, 0.9, 1.0))
	_place(world, "rover", Vector3(-2.4, 0.0, 3.4), 1.4, 150.0)

	# P1 (magenta) raiders coming from the right.
	_ring(world, Vector3(5.2, 0.0, 0.2), 1.05, Color(1.0, 0.25, 0.7))
	_place(world, "craft_speederA", Vector3(5.2, 0.0, 0.2), 2.0, -95.0)
	_ring(world, Vector3(6.4, 0.0, 2.0), 1.05, Color(1.0, 0.25, 0.7))
	_place(world, "craft_miner", Vector3(6.4, 0.0, 2.0), 2.0, -80.0)

	# Neutral minerals field.
	_place(world, "rock_crystalsLargeA", Vector3(2.8, 0.0, -3.4), 1.8, 10.0)
	_place(world, "rock_crystals", Vector3(4.0, 0.0, -2.6), 1.3, 60.0)

	var cam := Camera3D.new()
	cam.position = Vector3(0.6, 7.6, 7.2)
	cam.fov = 40.0
	world.add_child(cam)
	cam.look_at(Vector3(0.8, 0.0, -0.2))
	cam.current = true

	await _frames(25)
	var image := viewport.get_texture().get_image()
	var err := image.save_png(OUT)
	print("[capture] preview_3d_validation.png -> %s" % error_string(err))
	quit(0)


func _ground() -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(60.0, 60.0)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode specular_disabled;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = abs(fract(wpos.xz) - 0.5);
	float line = 1.0 - smoothstep(0.0, 0.025, 0.5 - max(g.x, g.y));
	ALBEDO = vec3(0.007, 0.010, 0.022);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	EMISSION = vec3(0.05, 0.35, 0.55) * line * 0.10;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	ground.material_override = mat
	return ground


# Footprint-aware placement: scales the model so its ground footprint
# spans `footprint` world units, recenters its AABB on `at`, and snaps
# its base onto the ground plane (GLB pivots are arbitrary).
func _place(
	parent: Node3D, model: String, at: Vector3, footprint: float, yaw_degrees: float
) -> void:
	var packed: PackedScene = load("%s/%s.glb" % [MODELS, model])
	if packed == null:
		push_error("missing model %s" % model)
		return
	var node: Node3D = packed.instantiate() as Node3D
	var box := _merged_aabb(node, Transform3D.IDENTITY)
	var span := maxf(box.size.x, box.size.z)
	var factor := footprint / maxf(span, 0.001)
	node.scale = Vector3.ONE * factor
	node.rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	var center := box.get_center()
	# The recentering offset lives in model space; rotate it with the
	# model or the pivot swing reintroduces the misalignment.
	var offset := Vector3(-center.x, 0.0, -center.z).rotated(Vector3.UP, deg_to_rad(yaw_degrees))
	node.position = at + offset * factor + Vector3(0.0, -box.position.y * factor, 0.0)
	parent.add_child(node)


func _merged_aabb(node: Node, parent_transform: Transform3D) -> AABB:
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * (node as Node3D).transform
	var box := AABB()
	var has_box := false
	if node is MeshInstance3D:
		box = transform * (node as MeshInstance3D).get_aabb()
		has_box = true
	for child in node.get_children():
		var child_box := _merged_aabb(child, transform)
		if child_box.size != Vector3.ZERO:
			box = box.merge(child_box) if has_box else child_box
			has_box = true
	return box


func _ring(parent: Node3D, at: Vector3, radius: float, color: Color) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = radius
	torus.outer_radius = radius + 0.09
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color, 1.0)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.4
	torus.material = mat
	var node := MeshInstance3D.new()
	node.mesh = torus
	node.position = at + Vector3(0.0, 0.03, 0.0)
	node.scale = Vector3(1.0, 0.25, 1.0)
	parent.add_child(node)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame
