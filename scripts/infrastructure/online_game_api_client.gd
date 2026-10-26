class_name OnlineGameApiClient
extends Node
signal received(state: Dictionary)
signal connection_changed(connected: bool, message: String)
signal authentication_required

var account_id: String = ""
var access_token: String = ""
var match_id: String = ""
var state: Dictionary = {}
var connected: bool = false
var _wanted: bool = false
var _paused: bool = false
var _request: HTTPRequest
var _delay: float = 0.0
var _pending: Dictionary = {}
var _request_kind: String = ""
var _authentication_pending: bool = false
var base_path: String = "/online-games"
var _create_payload: Dictionary = {}

func set_credentials(token: String, user_id: String) -> void:
	if token != access_token and _request != null:
		_request.cancel_request()
		_request.queue_free()
		_request = null
	if account_id != user_id:
		stop()
		state = {}
		match_id = ""
		_pending = {}
		_create_payload = {}
	account_id = user_id
	access_token = token
	_authentication_pending = false
	_delay = 0.0

func recover() -> void:
	_authentication_pending = false
	match_id = ""
	var path: String = _resume_path()
	if FileAccess.file_exists(path):
		match_id = FileAccess.get_file_as_string(path).strip_edges()
	_wanted = true
	_delay = 0.0

func start(id: String) -> void:
	if match_id != id:
		_pending = {}
		state = {}
	match_id = id
	_wanted = true
	_delay = 0.0
	var file: FileAccess = FileAccess.open(_resume_path(), FileAccess.WRITE)
	if file != null:
		file.store_string(id)

func start_verified_ai(difficulty: int, rival_id: String = "") -> void:
	base_path = "/ai-games"
	# A poll for the previous match may still be in flight when New Game is
	# selected. Its response must not replace the new create request.
	if _request != null:
		_request.cancel_request()
		_request.queue_free()
		_request = null
	match_id = ""
	state = {}
	_pending = {}
	_create_payload = {"requestId": MatchmakingApiClient._uuid(), "difficulty": difficulty}
	if not rival_id.is_empty():
		_create_payload["rivalId"] = rival_id
	_wanted = true
	_delay = 0.0

func stop() -> void:
	_wanted = false
	if _request != null:
		_request.cancel_request()
		_request.queue_free()
		_request = null
	_set_connection(false, "")

func has_pending_command() -> bool:
	return not _pending.is_empty()

func submit(command: Dictionary) -> bool:
	if not connected or not _pending.is_empty() or match_id.is_empty() or state.is_empty():
		return false
	_pending = command.duplicate(true)
	_pending["commandId"] = MatchmakingApiClient._uuid()
	_pending["expectedVersion"] = int(state.version)
	_delay = 0.0
	return true

func _process(delta: float) -> void:
	_delay = maxf(0.0, _delay - delta)
	if not _wanted or _paused or _request != null or _delay > 0.0 or _authentication_pending:
		return
	if access_token.is_empty():
		_authentication_pending = true
		if connected:
			_set_connection(false, "Reconnecting your account...")
		authentication_required.emit()
		_delay = 8.0
		return
	var path: String = "/current" if match_id.is_empty() else "/%s" % match_id
	_request_kind = "create" if not _create_payload.is_empty() else ("poll" if _pending.is_empty() else "command")
	if _request_kind == "command":
		path += "/commands"
	_request = HTTPRequest.new()
	_request.timeout = 8.0
	add_child(_request)
	_request.request_completed.connect(_completed.bind(_request, _request_kind))
	var error: int = _send_http(_request, ApiConfiguration.api_base_url() + base_path + ("/" if _request_kind == "create" else path),
		PackedStringArray(["Content-Type: application/json", "Authorization: Bearer %s" % access_token]),
		HTTPClient.METHOD_GET if _request_kind == "poll" else HTTPClient.METHOD_POST,
		JSON.stringify(_create_payload) if _request_kind == "create" else ("" if _request_kind == "poll" else JSON.stringify(_pending)))
	if error != OK:
		_request.queue_free()
		_request = null
		_retry()

func _send_http(request: HTTPRequest, url: String, headers: PackedStringArray, method: int, body: String) -> int:
	return request.request(url, headers, method, body)

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
	request: HTTPRequest, kind: String) -> void:
	if request != _request:
		return
	_request = null
	request.queue_free()
	if code == 401:
		access_token = ""
		_authentication_pending = true
		_set_connection(false, "Reconnecting your account...")
		authentication_required.emit()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code >= 500 or code == 429:
		_retry()
		return
	if code == 404:
		_clear_resume()
		_pending = {}
		_create_payload = {}
		stop()
		_set_connection(false, "This verified AI match is no longer available." if base_path == "/ai-games" else "This online match is no longer available.")
		return
	if code == 400 and kind == "create" and base_path == "/ai-games":
		_create_payload = {}
		stop()
		_set_connection(false, "The AI rival service rejected this match request.")
		return
	var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not payload is Dictionary or code not in [200, 409]:
		_pending = {}
		_retry()
		return
	if match_id.is_empty() and kind != "create":
		payload = payload.get("match")
		if payload == null:
			stop()
			return
	if not payload is Dictionary or not payload.has("matchId") or not payload.has("version"):
		_retry()
		return
	if kind == "command":
		_pending = {}
	if kind == "create":
		_create_payload = {}
	if match_id.is_empty():
		start(String(payload.matchId))
	state = payload
	_set_connection(true, String(payload.get("error", "")).replace("_", " ").capitalize())
	received.emit(state)
	_delay = 1.0
	if String(state.get("status")) == "completed":
		if String(state.get("gemSettlementStatus", "ineligible")) == "pending":
			_delay = 2.0
		else:
			_clear_resume()
			_wanted = false

func authentication_failed(message: String) -> void:
	access_token = ""
	_authentication_pending = true
	if _request != null:
		_request.cancel_request()
		_request.queue_free()
		_request = null
	_set_connection(false, message)


func _retry() -> void:
	_delay = 2.0
	_set_connection(false, "Connection lost. Reconnecting to your match.")

func _set_connection(value: bool, message: String) -> void:
	connected = value
	connection_changed.emit(value, message)

func _resume_path() -> String:
	return "user://%s_%s.txt" % ["verified_ai" if base_path == "/ai-games" else "online", account_id.sha256_text()]

func _clear_resume() -> void:
	if FileAccess.file_exists(_resume_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_resume_path()))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_paused = true
		_set_connection(false, "Reconnecting...")
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_paused = false
		_delay = 0.0

func _exit_tree() -> void:
	if _request != null:
		_request.cancel_request()
