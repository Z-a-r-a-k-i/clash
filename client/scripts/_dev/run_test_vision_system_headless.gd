extends SceneTree

const TEST_SCRIPT := "res://scripts/_dev/test_vision_system.gd"


func _init() -> void:
	var script: Script = load(TEST_SCRIPT) as Script
	if script == null:
		push_error("[test_vision_system_headless] could not load %s" % TEST_SCRIPT)
		quit(1)
		return
	var runner: Node = Node.new()
	runner.set_script(script)
	root.add_child(runner)
	var failed: int = int(runner.call("_run_all"))
	root.remove_child(runner)
	runner.queue_free()
	quit(0 if failed == 0 else 1)
