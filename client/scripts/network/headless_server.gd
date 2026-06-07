extends SceneTree

const SERVER_SCRIPT := preload("res://scripts/network/network_match_server.gd")


func _init() -> void:
	var server: NetworkMatchServer = SERVER_SCRIPT.new()
	if not _apply_args(server):
		quit(1)
		return
	root.add_child(server)
	var err: Error = server.start()
	if err != OK:
		quit(1)


func _apply_args(server: NetworkMatchServer) -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	for i in range(args.size()):
		var arg: String = args[i]
		if arg == "--port" and i + 1 < args.size():
			if not _apply_port(server, args[i + 1]):
				return false
		elif arg.begins_with("--port="):
			if not _apply_port(server, arg.get_slice("=", 1)):
				return false
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
	return true


func _apply_port(server: NetworkMatchServer, raw_port: String) -> bool:
	if not raw_port.is_valid_int():
		push_error("Network headless server: invalid --port value '%s'" % raw_port)
		return false
	var parsed_port: int = int(raw_port)
	if parsed_port < 1 or parsed_port > 65535:
		push_error("Network headless server: --port must be in range 1-65535, got %d" % parsed_port)
		return false
	server.port = parsed_port
	return true
