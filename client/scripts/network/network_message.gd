class_name NetworkMessage
extends RefCounted

const CLIENT_HELLO := "client_hello"
const CREATE_MATCH := "create_match"
const JOIN_MATCH := "join_match"
const MATCH_JOINED := "match_joined"
const TURN_STARTED := "turn_started"
const SUBMIT_TURN := "submit_turn"
const CANCEL_SUBMIT_TURN := "cancel_submit_turn"
const TURN_RESOLVED := "turn_resolved"
const MATCH_ERROR := "match_error"
const DISCONNECT_NOTICE := "disconnect_notice"

const KEY_KIND := "kind"
const KEY_PAYLOAD := "payload"
const KEY_REQUEST_ID := "request_id"


static func make(kind: String, payload: Dictionary = {}, request_id: String = "") -> Dictionary:
	var message: Dictionary = {
		KEY_KIND: kind,
		KEY_PAYLOAD: payload,
	}
	if request_id != "":
		message[KEY_REQUEST_ID] = request_id
	return message


static func error(code: String, message: String, fatal: bool = false) -> Dictionary:
	return make(
		MATCH_ERROR,
		{
			"code": code,
			"message": message,
			"fatal": fatal,
		}
	)


static func kind(message: Dictionary) -> String:
	return message.get(KEY_KIND, "")


static func payload(message: Dictionary) -> Dictionary:
	var raw: Variant = message.get(KEY_PAYLOAD, {})
	if raw is Dictionary:
		return raw
	return {}
