extends SceneTree

const TEST_SCRIPT := "res://scripts/_dev/test_arena_map.gd"


func _init() -> void:
	var script: Script = load(TEST_SCRIPT) as Script
	if script == null:
		push_error("[test_arena_map_headless] could not load %s" % TEST_SCRIPT)
		quit(1)
		return
	var runner: Node = Node.new()
	runner.set_script(script)
	root.add_child(runner)
	var result: Dictionary = runner.run_all()
	root.remove_child(runner)
	runner.queue_free()
	var passed: int = result.get("passed", 0)
	var failed: int = result.get("failed", 0)
	if failed == 0:
		print("[test_arena_map] %d passed, 0 failed" % passed)
	else:
		push_error("[test_arena_map] %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
