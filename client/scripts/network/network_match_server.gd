class_name NetworkMatchServer
extends Node

const MESSAGE := preload("res://scripts/network/network_message.gd")
const MAX_PACKET_SIZE: int = 65536

@export var bind_address: String = "127.0.0.1"
@export var port: int = 9087
@export_file("*.tres") var scenario_path: String = "res://data/scenarios/mvp_map.tres"
@export_dir var replay_dir: String = "user://tmp/network_replays"

var _tcp_server: TCPServer = TCPServer.new()
var _peers: Dictionary[int, WebSocketPeer] = {}
var _next_peer_id: int = 1
var _codec: NetworkV0Codec = NetworkV0Codec.new()
var _hub: NetworkMatchHub = NetworkMatchHub.new()


func start() -> Error:
	_hub.configure(
		scenario_path, "res://data/entity_registry.tres", "res://data/tunables.tres", replay_dir
	)
	var err: Error = _tcp_server.listen(port, bind_address)
	if err != OK:
		push_error("NetworkMatchServer: listen failed on %s:%d: %d" % [bind_address, port, err])
		return err
	set_process(true)
	print("NetworkMatchServer listening on ws://%s:%d" % [bind_address, port])
	return OK


func stop() -> void:
	for peer_id in _peers.keys():
		var peer: WebSocketPeer = _peers[peer_id]
		if peer != null:
			peer.close()
	_peers.clear()
	_tcp_server.stop()
	set_process(false)


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	_accept_new_peers()
	_poll_peers()


func _accept_new_peers() -> void:
	while _tcp_server.is_connection_available():
		var stream: StreamPeerTCP = _tcp_server.take_connection()
		var peer: WebSocketPeer = WebSocketPeer.new()
		var err: Error = peer.accept_stream(stream)
		if err != OK:
			push_warning("NetworkMatchServer: WebSocket accept failed: %d" % err)
			continue
		var peer_id: int = _next_peer_id
		_next_peer_id += 1
		_peers[peer_id] = peer


func _poll_peers() -> void:
	var closed: Array[int] = []
	for peer_id in _peers.keys():
		var peer: WebSocketPeer = _peers[peer_id]
		if peer == null:
			closed.append(peer_id)
			continue
		peer.poll()
		var state: int = peer.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while peer.get_available_packet_count() > 0:
				var packet: PackedByteArray = peer.get_packet()
				if packet.size() > MAX_PACKET_SIZE:
					push_warning(
						(
							"NetworkMatchServer: dropping oversized packet from peer %d (%d bytes)"
							% [peer_id, packet.size()]
						)
					)
					continue
				var message: Dictionary = _codec.decode(packet)
				_handle_message(int(peer_id), message)
		elif state == WebSocketPeer.STATE_CLOSED:
			closed.append(int(peer_id))
	for peer_id in closed:
		_peers.erase(peer_id)
		_broadcast_by_peer(_hub.disconnect_peer(peer_id).get("messages_by_peer", {}))


func _handle_message(peer_id: int, message: Dictionary) -> void:
	var kind: String = MESSAGE.kind(message)
	var payload: Dictionary = MESSAGE.payload(message)
	match kind:
		MESSAGE.CLIENT_HELLO:
			_send(peer_id, MESSAGE.make(MESSAGE.CLIENT_HELLO, {"server": "clash-godot-v0"}))
		MESSAGE.CREATE_MATCH:
			var created: Dictionary = _hub.create_match(peer_id)
			_send_result_to_peer(peer_id, created)
		MESSAGE.JOIN_MATCH:
			var joined: Dictionary = _hub.join_match(peer_id, payload.get("code", ""))
			if joined.get("ok", false):
				_broadcast_by_peer(joined.get("messages_by_peer", {}))
			else:
				_send_result_to_peer(peer_id, joined)
		MESSAGE.SUBMIT_TURN:
			var submit: SubmitTurn = payload.get("submit") as SubmitTurn
			var submitted: Dictionary = _hub.submit_turn(peer_id, payload.get("code", ""), submit)
			if submitted.get("ok", false) and submitted.get("resolved", false):
				_broadcast_by_peer(submitted.get("messages_by_peer", {}))
			elif submitted.get("ok", false):
				_send(peer_id, MESSAGE.make(MESSAGE.SUBMIT_TURN, {"accepted": true}))
			else:
				_send_result_to_peer(peer_id, submitted)
		_:
			_send(peer_id, MESSAGE.error("unknown_message", "unknown_message"))


func _send_result_to_peer(peer_id: int, result: Dictionary) -> void:
	for message in result.get("messages", []):
		_send(peer_id, message)


func _broadcast_by_peer(messages_by_peer: Dictionary) -> void:
	for peer_id in messages_by_peer.keys():
		for message in messages_by_peer[peer_id]:
			_send(int(peer_id), message)


func _send(peer_id: int, message: Dictionary) -> void:
	var peer: WebSocketPeer = _peers.get(peer_id)
	if peer == null or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var err: Error = peer.send(_codec.encode(message), WebSocketPeer.WRITE_MODE_BINARY)
	if err != OK:
		push_warning("NetworkMatchServer: send failed to peer %d: %d" % [peer_id, err])
