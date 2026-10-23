class_name AccountDeletionClient
extends Node
## Deletes only the authenticated account; refreshes an expired token once.
signal completed(success: bool, message: String)

var _request: HTTPRequest = null
var _credentials: Dictionary = {}
var _refreshed: bool = false
var _active: bool = false


func delete_account(token: String, credentials: Dictionary) -> void:
	if _active:
		return
	_active = true
	_refreshed = false
	_credentials = credentials.duplicate(true)
	if token.is_empty():
		_login()
	else:
		_delete(token)


func _delete(token: String) -> void:
	_send("/auth/me", HTTPClient.METHOD_DELETE, {"confirm": true}, token, false)


func _login() -> void:
	_refreshed = true
	_send("/auth/login", HTTPClient.METHOD_POST, {
		"email": String(_credentials.get("email", "")),
		"password": String(_credentials.get("password", "")),
	}, "", true)


func _send(path: String, method: int, payload: Dictionary, token: String, login: bool) -> void:
	_request = HTTPRequest.new()
	_request.timeout = 15.0
	add_child(_request)
	_request.request_completed.connect(_on_response.bind(login))
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)
	var error := _request.request(ApiConfiguration.api_base_url() + path, headers, method, JSON.stringify(payload))
	if error != OK:
		_finish(false, "Could not connect. Your local data has been kept. Please retry.")


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, login: bool) -> void:
	if _request != null:
		_request.queue_free()
		_request = null
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish(false, "Deletion could not be confirmed. Your local data has been kept. Please retry.")
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else null
	if login:
		if code == 200 and data is Dictionary and not String(data.get("token", "")).is_empty():
			_delete(String(data.token))
		else:
			_finish(false, "Could not authenticate the account. Your local data has been kept. Please retry.")
		return
	if code == 401 and not _refreshed:
		_login()
		return
	if code == 204 or (code == 200 and data is Dictionary and data.get("success") == true):
		_finish(true, "Account deleted.")
	else:
		_finish(false, "Deletion could not be confirmed (HTTP %d). Your local data has been kept. Please retry." % code)


func _finish(success: bool, message: String) -> void:
	if _request != null:
		_request.queue_free()
		_request = null
	_credentials.clear()
	_active = false
	completed.emit(success, message)
