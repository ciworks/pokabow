class_name GemWalletApiClient
extends Node
## Reads confirmed, server-owned Gems. Never converts match projections into balance.

signal received(data: Dictionary)
signal failed(message: String)
signal authentication_required

var access_token: String = ""
var account_id: String = ""
var current: Dictionary = {}
var _request: HTTPRequest = null
var _refresh_queued: bool = false

func set_credentials(token: String, user_id: String) -> void:
	if token != access_token or user_id != account_id:
		if _request != null:
			_request.cancel_request()
			_request.queue_free()
			_request = null
		current.clear()
		_refresh_queued = false
	access_token = token
	account_id = user_id
	if not access_token.is_empty() and not account_id.is_empty():
		fetch()

func fetch() -> void:
	if access_token.is_empty() or account_id.is_empty():
		return
	if _request != null:
		# A match may settle while an earlier balance read is still in flight.
		_refresh_queued = true
		return
	_request = HTTPRequest.new()
	_request.timeout = 15.0
	add_child(_request)
	_request.request_completed.connect(_on_completed.bind(_request, access_token, account_id))
	var error: Error = _send_http(_request,
		ApiConfiguration.api_base_url() + "/gems/me",
		PackedStringArray(["Authorization: Bearer %s" % access_token])
	)
	if error != OK:
		_request.queue_free()
		_request = null
		failed.emit("Gem balance is unavailable. Retry when connected.")

func _send_http(request: HTTPRequest, url: String, headers: PackedStringArray) -> Error:
	return request.request(url, headers)

func _on_completed(result: int, code: int, _headers: PackedStringArray,
	body: PackedByteArray, request: HTTPRequest, token: String, user_id: String) -> void:
	request.queue_free()
	if _request == request:
		_request = null
	if token != access_token or user_id != account_id:
		return
	if _refresh_queued:
		_refresh_queued = false
		if code != 401:
			fetch()
	if code == 401:
		authentication_required.emit()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit("Gem balance is unavailable. Retry when connected.")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		failed.emit("The server returned invalid Gem balance data.")
		return
	var balance: Variant = parsed.get("balance")
	if (not balance is float and not balance is int) or not parsed.get("transactions") is Array \
		or int(balance) < 0:
		failed.emit("The server returned invalid Gem balance data.")
		return
	current = (parsed as Dictionary).duplicate(true)
	received.emit(current)
