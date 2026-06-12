extends SceneTree

# Throwaway: run dev play mode (3D renderer path) and screenshot it for
# visual iteration. Output in gitignored docs/visual-references/.

const OUT_DIR := "res://../docs/visual-references"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/_dev/dev_play_mode.tscn")
	var mode: Node = scene.instantiate()
	root.add_child(mode)
	await _frames(25)
	_capture("play3d_arena.png")
	# Send the four workers somewhere so the playback glide shows.
	var state: MatchState = mode.current_state()
	for entity in state.entities_sorted_by_id():
		if entity.def_id == "worker" and entity.owner_player_id == 0:
			mode.select_entity_id(entity.id)
			mode.issue_move_selected(entity.origin + Vector2i(6, 3))
	mode.resolve_turn()
	await _frames(8)
	_capture("play3d_glide.png")
	await _frames(80)
	_capture("play3d_after.png")
	quit(0)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _capture(file_name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + "/" + file_name)
	print("[capture] %s -> %s" % [file_name, error_string(err)])
