class_name ProgressionApiClient
extends Node
## Reads server-owned Table Level and Online Tier; no client-side award logic.

signal received(data: Dictionary)
signal failed(message: String)
signal authentication_required

var access_token: String = ""
var account_id: String = ""
var current: Dictionary = {}
var _request: HTTPRequest

func set_credentials(token: String, user_id: String) -> void:
	if token != access_token or user_id != account_id:
		if _request != null:
			_request.cancel_request()
			_request.queue_free()
			_request = null
		current.clear()
	access_token = token
	account_id = user_id
	if not access_token.is_empty():
		fetch()

func fetch() -> void:
	if access_token.is_empty() or account_id.is_empty() or _request != null:
		return
	_request = HTTPRequest.new()
	_request.timeout = 15.0
	add_child(_request)
	_request.request_completed.connect(_on_completed.bind(_request, access_token, account_id))
	var error: Error = _request.request(
		ApiConfiguration.api_base_url() + "/progression/me",
		PackedStringArray(["Authorization: Bearer %s" % access_token])
	)
	if error != OK:
		_request.queue_free()
		_request = null
		failed.emit("Level information is unavailable. Retry when connected.")

func _on_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray,
	request: HTTPRequest, token: String, user_id: String
) -> void:
	request.queue_free()
	if _request == request:
		_request = null
	if token != access_token or user_id != account_id:
		return
	if response_code == 401:
		authentication_required.emit()
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		failed.emit("Level information is unavailable. Retry when connected.")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		failed.emit("The server returned invalid level information.")
		return
	var data: Dictionary = parsed
	if int(data.get("level", 0)) < 1 or int(data.get("nextLevelExperience", 0)) <= int(data.get("experience", 0)):
		failed.emit("The server returned invalid level information.")
		return
	current = data.duplicate(true)
	received.emit(current)
