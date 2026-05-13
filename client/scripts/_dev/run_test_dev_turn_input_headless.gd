extends SceneTree

const TEST_SCRIPT := "res://scripts/_dev/test_dev_turn_input.gd"


func _init() -> void:
	var script: Script = load(TEST_SCRIPT) as Script
	if script == null:
		push_error("[test_dev_turn_input_headless] could not load %s" % TEST_SCRIPT)
		quit(1)
		return
	var runner: Node = Node.new()
	runner.set_script(script)
	var failed: int = runner._run_all()
	quit(0 if failed == 0 else 1)
