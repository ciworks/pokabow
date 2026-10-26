class_name VerifiedAiMatchListClient
extends Node
## Fetches all resumable server AI matches independently of the open match.

signal received(matches: Array[Dictionary])

var matches: Array[Dictionary] = []
var _token: String = ""
var _account_id: String = ""
var _request: HTTPRequest = null
var _refresh_again: bool = false


func set_credentials(token: String, account_id: String) -> void:
	if account_id != _account_id:
		if _request != null:
			_request.cancel_request()
			_request.queue_free()
			_request = null
		matches.clear()
		_refresh_again = false
	_account_id = account_id
	_token = token


func refresh() -> void:
	if _token.is_empty() or _account_id.is_empty():
		return
	if _request != null:
		_refresh_again = true
		return
	_request = HTTPRequest.new()
	_request.timeout = 8.0
	add_child(_request)
	_request.request_completed.connect(_on_completed.bind(_request))
	var error: Error = _request.request(ApiConfiguration.api_base_url() + "/ai-games/active",
		PackedStringArray(["Authorization: Bearer %s" % _token]))
	if error != OK:
		_request.queue_free()
		_request = null


func _on_completed(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, request: HTTPRequest) -> void:
	if request != _request:
		return
	_request = null
	request.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
		if payload is Dictionary and payload.get("matches") is Array:
			matches.clear()
			for candidate: Variant in payload["matches"]:
				if candidate is Dictionary and String(candidate.get("status", "")) == "active":
					matches.append(candidate)
			received.emit(matches)
	if _refresh_again:
		_refresh_again = false
		refresh()
