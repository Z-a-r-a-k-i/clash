class_name NetworkClient
extends Node

signal connected_to_server
signal connection_failed
signal disconnected
signal message_received(message: Dictionary)

const MESSAGE := preload("res://scripts/network/network_message.gd")
const WEBSOCKET_BUFFER_SIZE: int = 16 * 1024 * 1024
const WEBSOCKET_MAX_QUEUED_PACKETS: int = 128

var _peer: WebSocketPeer = null
var _codec: NetworkV0Codec = NetworkV0Codec.new()
var _url: String = ""
var _match_code: String = ""
var _open_emitted: bool = false


func connect_to_server(url: String) -> Error:
	disconnect_from_server()
	_url = url
	_match_code = ""
	_peer = WebSocketPeer.new()
	_configure_peer(_peer)
	_open_emitted = false
	var err: Error = _peer.connect_to_url(url)
	if err != OK:
		_peer = null
		_match_code = ""
		connection_failed.emit()
		return err
	set_process(true)
	return OK


func disconnect_from_server() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	_match_code = ""
	_open_emitted = false
	set_process(false)


func create_match() -> Error:
	return send_message(MESSAGE.make(MESSAGE.CREATE_MATCH))


func join_match(code: String) -> Error:
	_match_code = code.strip_edges().to_upper()
	return send_message(MESSAGE.make(MESSAGE.JOIN_MATCH, {"code": _match_code}))


func submit_turn(submit: SubmitTurn) -> Error:
	return send_message(
		(
			MESSAGE
			. make(
				MESSAGE.SUBMIT_TURN,
				{
					"code": _match_code,
					"submit": submit,
				}
			)
		)
	)


func cancel_submit_turn() -> Error:
	return send_message(
		(
			MESSAGE
			. make(
				MESSAGE.CANCEL_SUBMIT_TURN,
				{
					"code": _match_code,
				}
			)
		)
	)


func send_message(message: Dictionary) -> Error:
	if _peer == null:
		return ERR_UNCONFIGURED
	if _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	var bytes: PackedByteArray = _codec.encode(message)
	return _peer.send(bytes, WebSocketPeer.WRITE_MODE_BINARY)


func _configure_peer(peer: WebSocketPeer) -> void:
	peer.inbound_buffer_size = WEBSOCKET_BUFFER_SIZE
	peer.outbound_buffer_size = WEBSOCKET_BUFFER_SIZE
	peer.max_queued_packets = WEBSOCKET_MAX_QUEUED_PACKETS


func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	var state: int = _peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _open_emitted:
			_open_emitted = true
			connected_to_server.emit()
		while _peer.get_available_packet_count() > 0:
			var message: Dictionary = _codec.decode(_peer.get_packet())
			_handle_message(message)
	elif state == WebSocketPeer.STATE_CLOSED:
		_peer = null
		_match_code = ""
		_open_emitted = false
		set_process(false)
		disconnected.emit()


func _handle_message(message: Dictionary) -> void:
	var kind: String = MESSAGE.kind(message)
	if kind == MESSAGE.MATCH_JOINED:
		_match_code = MESSAGE.payload(message).get("code", _match_code)
	message_received.emit(message)
