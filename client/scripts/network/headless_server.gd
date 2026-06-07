extends SceneTree

const SERVER_SCRIPT := preload("res://scripts/network/network_match_server.gd")


func _init() -> void:
	var server: NetworkMatchServer = SERVER_SCRIPT.new()
	_apply_args(server)
	root.add_child(server)
	var err: Error = server.start()
	if err != OK:
		quit(1)


func _apply_args(server: NetworkMatchServer) -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	for i in range(args.size()):
		var arg: String = args[i]
		if arg == "--port" and i + 1 < args.size():
			server.port = int(args[i + 1])
		elif arg.begins_with("--port="):
			server.port = int(arg.get_slice("=", 1))
		elif arg == "--bind" and i + 1 < args.size():
			server.bind_address = args[i + 1]
		elif arg.begins_with("--bind="):
			server.bind_address = arg.get_slice("=", 1)
		elif arg == "--scenario" and i + 1 < args.size():
			server.scenario_path = args[i + 1]
		elif arg.begins_with("--scenario="):
			server.scenario_path = arg.get_slice("=", 1)
		elif arg == "--replay-dir" and i + 1 < args.size():
			server.replay_dir = args[i + 1]
		elif arg.begins_with("--replay-dir="):
			server.replay_dir = arg.get_slice("=", 1)
