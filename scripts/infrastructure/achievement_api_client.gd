class_name AchievementApiClient
extends Node
## Reports mechanic-derived unlocks and reads the authenticated user's catalog.

signal catalog_received(rows: Array)
signal newly_unlocked(ids: Array)
signal authentication_required

var access_token: String = ""
var _unlock_request_active: bool = false
var _retry_delay: float = 0.0
var _catalog_request_active: bool = false


func _process(delta: float) -> void:
	if _retry_delay > 0.0:
		_retry_delay = maxf(0.0, _retry_delay - delta)
		if _retry_delay == 0.0:
			_flush_pending_unlocks()


func set_access_token(token: String) -> void:
	access_token = token
	_flush_pending_unlocks()


func report_unlocks(ids: Array[String]) -> void:
	if ids.is_empty():
		return
	UsersStateStore.queue_achievement_ids(ids)
	_flush_pending_unlocks()


func _flush_pending_unlocks() -> void:
	if access_token.is_empty() or _unlock_request_active:
		return
	var ids: Array[String] = UsersStateStore.pending_achievement_ids()
	if ids.is_empty():
		return
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	request.request_completed.connect(_on_unlocks_completed.bind(request, access_token))
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % access_token,
	])
	var error := request.request(
		ApiConfiguration.api_base_url() + "/achievements/unlocks",
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify({"achievementIds": ids})
	)
	if error != OK:
		request.queue_free()
		_retry_delay = 15.0
		return
	_unlock_request_active = true


func fetch_catalog() -> void:
	if access_token.is_empty() or _catalog_request_active:
		return
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	request.request_completed.connect(_on_catalog_completed.bind(request, access_token))
	var error := request.request(
		ApiConfiguration.api_base_url() + "/achievements",
		PackedStringArray(["Authorization: Bearer %s" % access_token])
	)
	if error != OK:
		request.queue_free()
	else:
		_catalog_request_active = true


func _on_unlocks_completed(
	result: int, response_code: int, _headers: PackedStringArray,
	body: PackedByteArray, request: HTTPRequest, token: String
) -> void:
	request.queue_free()
	_unlock_request_active = false
	if token != access_token:
		_flush_pending_unlocks()
		return
	if response_code == 401:
		access_token = ""
		authentication_required.emit()
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if result != HTTPRequest.RESULT_SUCCESS or response_code >= 500 or response_code == 429:
			_retry_delay = 15.0
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) == TYPE_DICTIONARY:
		var response: Dictionary = parsed
		var unlocked: Variant = response.get("unlocked", [])
		var already: Variant = response.get("alreadyUnlocked", [])
		var completed: Array[String] = []
		if unlocked is Array:
			for id: Variant in unlocked:
				completed.append(String(id))
		if already is Array:
			for id: Variant in already:
				completed.append(String(id))
		UsersStateStore.clear_achievement_ids(completed)
		if unlocked is Array and not unlocked.is_empty():
			newly_unlocked.emit(unlocked)
		if not completed.is_empty():
			_flush_pending_unlocks()


func _on_catalog_completed(
	result: int, response_code: int, _headers: PackedStringArray,
	body: PackedByteArray, request: HTTPRequest, token: String
) -> void:
	request.queue_free()
	_catalog_request_active = false
	if token != access_token:
		fetch_catalog()
		return
	if response_code == 401:
		access_token = ""
		authentication_required.emit()
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Array:
		catalog_received.emit(parsed)
