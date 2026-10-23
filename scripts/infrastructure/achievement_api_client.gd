class_name AchievementApiClient
extends Node
## Reports gameplay unlocks, checks in account activity, and reads the catalog.

signal catalog_received(rows: Array)
signal catalog_loading
signal catalog_failed(message: String)
signal newly_unlocked(ids: Array)
signal authentication_required

var access_token: String = ""
var _unlock_request_active: bool = false
var _retry_delay: float = 0.0
var _catalog_request_active: bool = false
var _catalog_refresh_pending: bool = false
var _progress_request_active: bool = false
var _check_in_request_active: bool = false
var _last_check_in_day: String = ""


## Achievement IDs and metrics cross JSON, StringName and saved-state boundaries.
## `str()` handles both text variants without invoking the String constructor.
static func _text(value: Variant) -> String:
	return str(value).strip_edges() if value is String or value is StringName else ""


static func _achievement_id(value: Variant) -> String:
	return _text(value.get("id", "")) if value is Dictionary else _text(value)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		check_in.call_deferred()


func _process(delta: float) -> void:
	if _retry_delay > 0.0:
		_retry_delay = maxf(0.0, _retry_delay - delta)
		if _retry_delay == 0.0:
			_flush_pending_unlocks()
			_flush_pending_progress()
			check_in()


func set_access_token(token: String) -> void:
	if token != access_token:
		for child: Node in get_children():
			if child is HTTPRequest:
				child.cancel_request()
				child.queue_free()
		_unlock_request_active = false
		_catalog_request_active = false
		_catalog_refresh_pending = false
		_progress_request_active = false
		_check_in_request_active = false
		_last_check_in_day = ""
		_retry_delay = 0.0
	access_token = token
	_flush_pending_unlocks()
	_flush_pending_progress()
	check_in()


## A visit counts once per UTC day. The API clock and database enforce the day.
func check_in() -> void:
	if access_token.is_empty() or _check_in_request_active:
		return
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	request.request_completed.connect(_on_check_in_completed.bind(request, access_token))
	var error: Error = request.request(
		ApiConfiguration.api_base_url() + "/achievements/check-in",
		PackedStringArray(["Authorization: Bearer %s" % access_token]),
		HTTPClient.METHOD_POST
	)
	if error != OK:
		request.queue_free()
		_retry_delay = 15.0
		return
	_check_in_request_active = true


func _on_check_in_completed(
	result: int, response_code: int, _headers: PackedStringArray,
	body: PackedByteArray, request: HTTPRequest, token: String
) -> void:
	request.queue_free()
	_check_in_request_active = false
	if token != access_token:
		check_in()
		return
	if response_code == 401:
		access_token = ""
		authentication_required.emit()
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if result != HTTPRequest.RESULT_SUCCESS or response_code >= 500 or response_code == 429:
			_retry_delay = 15.0
		return
	var response: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not response is Dictionary:
		_retry_delay = 15.0
		return
	var day: String = _text((response as Dictionary).get("day", ""))
	var details: Variant = (response as Dictionary).get("unlockedDetails", [])
	if details is Array and not details.is_empty():
		newly_unlocked.emit(details)
	if day != _last_check_in_day or (details is Array and not details.is_empty()):
		fetch_catalog()
	_last_check_in_day = day


func report_unlocks(ids: Array[String]) -> void:
	if ids.is_empty():
		return
	UsersStateStore.queue_achievement_ids(ids)
	_flush_pending_unlocks()


func report_progress(events: Array[Dictionary]) -> void:
	if events.is_empty():
		return
	if not UsersStateStore.queue_achievement_progress(events):
		return
	_announce_locally_reached_achievements()
	_flush_pending_progress()


func _announce_locally_reached_achievements() -> void:
	var counts: Dictionary = {}
	for event: Dictionary in UsersStateStore.pending_achievement_progress():
		if bool(event.get("submitted", false)):
			continue
		var metric: String = _text(event.get("metric", ""))
		counts[metric] = int(counts.get(metric, 0)) + 1
	var reached: Array[String] = []
	for row: Dictionary in UsersStateStore.achievement_catalog():
		var id: String = _achievement_id(row)
		var metric: String = _text(row.get("metric", ""))
		if id.is_empty() or metric.is_empty() or bool(row.get("unlocked", false)) or UsersStateStore.achievement_was_announced(id):
			continue
		if int(row.get("progress", 0)) + int(counts.get(metric, 0)) >= int(row.get("target", 1)):
			UsersStateStore.mark_achievement_announced(id)
			reached.append(id)
	if not reached.is_empty():
		newly_unlocked.emit(reached)


func _flush_pending_progress() -> void:
	if access_token.is_empty() or _progress_request_active:
		return
	var pending: Array[Dictionary] = UsersStateStore.pending_achievement_progress()
	if pending.is_empty():
		return
	var batch: Array[Dictionary] = []
	var batch_ids: Array[String] = []
	for event: Dictionary in pending.slice(0, 50):
		var event_id: String = _text(event.get("eventId", ""))
		batch.append({"eventId": event_id, "metric": _text(event.get("metric", ""))})
		batch_ids.append(event_id)
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	request.request_completed.connect(_on_progress_completed.bind(request, access_token, batch))
	var error: Error = request.request(
		ApiConfiguration.api_base_url() + "/achievements/progress",
		PackedStringArray([
			"Content-Type: application/json",
			"Authorization: Bearer %s" % access_token,
		]),
		HTTPClient.METHOD_POST,
		JSON.stringify({"events": batch})
	)
	if error != OK:
		request.queue_free()
		_retry_delay = 15.0
		return
	_progress_request_active = true
	UsersStateStore.mark_achievement_progress_submitted(batch_ids)


func _on_progress_completed(
	result: int, response_code: int, _headers: PackedStringArray,
	body: PackedByteArray, request: HTTPRequest, token: String,
	batch: Array[Dictionary]
) -> void:
	request.queue_free()
	_progress_request_active = false
	if token != access_token:
		_flush_pending_progress()
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
	if not parsed is Dictionary:
		_retry_delay = 15.0
		return
	var ids: Array[String] = []
	for event: Dictionary in batch:
		ids.append(_text(event.get("eventId", "")))
	UsersStateStore.clear_achievement_progress(ids)
	var unlocked: Variant = (parsed as Dictionary).get("unlocked", [])
	var details: Dictionary = {}
	var raw_details: Variant = (parsed as Dictionary).get("unlockedDetails", [])
	if raw_details is Array:
		for value: Variant in raw_details:
			if value is Dictionary:
				var detail_id: String = _achievement_id(value)
				if not detail_id.is_empty():
					details[detail_id] = value
	var unseen: Array = []
	if unlocked is Array:
		for value: Variant in unlocked:
			var id: String = _achievement_id(value)
			if id.is_empty():
				continue
			if not UsersStateStore.achievement_was_announced(id):
				UsersStateStore.mark_achievement_announced(id)
				unseen.append(details.get(id, id))
	if not unseen.is_empty():
		newly_unlocked.emit(unseen)
	# Refresh durable progress and unlock state for the collection screen.
	fetch_catalog()
	_flush_pending_progress()


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
	if access_token.is_empty():
		catalog_failed.emit("Sign in to load your achievements. You can retry after your account reconnects.")
		return
	if _catalog_request_active:
		_catalog_refresh_pending = true
		return
	catalog_loading.emit()
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
		catalog_failed.emit("Could not load achievements. Check your connection and retry.")
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
				var normalized_id: String = _achievement_id(id)
				if not normalized_id.is_empty():
					completed.append(normalized_id)
		if already is Array:
			for id: Variant in already:
				var normalized_id: String = _achievement_id(id)
				if not normalized_id.is_empty():
					completed.append(normalized_id)
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
	var refresh_after: bool = _catalog_refresh_pending
	_catalog_refresh_pending = false
	if token != access_token:
		fetch_catalog()
		return
	if response_code == 401:
		access_token = ""
		catalog_failed.emit("Your account session expired. Retry after signing in.")
		authentication_required.emit()
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		catalog_failed.emit("Could not load achievements. Check your connection and retry.")
		if refresh_after:
			fetch_catalog()
		return
	var parser := JSON.new()
	var parse_error: Error = parser.parse(body.get_string_from_utf8())
	var parsed: Variant = parser.data if parse_error == OK else null
	if parsed is Array:
		var rows: Array[Dictionary] = []
		for value: Variant in parsed:
			if value is Dictionary:
				rows.append(value)
				if bool(value.get("unlocked", false)):
					var id: String = _achievement_id(value)
					if not id.is_empty():
						UsersStateStore.mark_achievement_announced(id)
		UsersStateStore.save_achievement_catalog(rows)
		catalog_received.emit(parsed)
	else:
		catalog_failed.emit("The achievement catalogue could not be read. Please retry.")
	if refresh_after:
		fetch_catalog()
