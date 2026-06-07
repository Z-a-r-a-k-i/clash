extends SceneTree

const TEST_SCRIPT := "res://scripts/_dev/test_network_multiplayer.gd"


func _init() -> void:
	var script: Script = load(TEST_SCRIPT) as Script
	if script == null:
		push_error("[test_network_multiplayer_headless] could not load %s" % TEST_SCRIPT)
		quit(1)
		return
	var runner: Node = Node.new()
	runner.set_script(script)
	if not runner.has_method("_run_all"):
		push_error("[test_network_multiplayer_headless] test runner did not expose _run_all")
		quit(1)
		return
	root.add_child(runner)
	var failed: int = runner._run_all()
	root.remove_child(runner)
	runner.queue_free()
	quit(0 if failed == 0 else 1)
