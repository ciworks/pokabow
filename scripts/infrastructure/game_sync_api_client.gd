class_name GameSyncApiClient
extends Node
## Mirrors local match creation and committed moves to the authenticated Games API.

signal sync_notice(message: String)
signal authentication_required
signal score_preview_received(score: Dictionary)

const SYNC_PATH: String = "user://game_sync_state.json"

var access_token: String = ""
var _controller: GameSessionController = null
var _local_match_id: String = ""
var _records: Dictionary = {}
var _active_request: HTTPRequest = null
var _request_kind: String = ""
var _active_match_key: String = ""
var _pending_deletes: Array[String] = []
var sync_path: String = SYNC_PATH
var _retry_delay: float = 0.0
var _retry_backoff: float = 2.0
var _preview_delay: float = 0.0
var _preview_generation: int = 0
var _sent_preview_generation: int = -1
var _preview_pending: bool = false
var _preview_supported: bool = true
var _conflict_retry: bool = false


func _ready() -> void:
	_load_records()


func set_access_token(token: String) -> void:
	if token != access_token and _active_request != null:
		_active_request.cancel_request()
		_finish_request(_active_request)
	access_token = token
	_retry_delay = 0.0
	_start_next_delete()
	if not access_token.is_empty() and is_instance_valid(_controller):
		_begin_match(_controller)
	retry_pending()


func _process(delta: float) -> void:
	_preview_delay = maxf(0.0, _preview_delay - delta)
	if _retry_delay > 0.0:
		_retry_delay = maxf(0.0, _retry_delay - delta)
		if _retry_delay == 0.0:
			retry_pending()
	if _preview_pending and _preview_delay == 0.0 and _retry_delay == 0.0:
		_send_preview()


## Retries queued actions after reconnect/login without changing their turn IDs.
func retry_pending() -> void:
	if _active_request != null or access_token.is_empty():
		return
	_start_next_delete()
	if _active_request != null:
		return
	for key: String in _records:
		var record: Dictionary = _match_record(key)
		var pending: Array = record.get("pending", [])
		if pending.is_empty() and key != _local_match_id:
			continue
		if String(record.get("game_id", "")).is_empty():
			# Freed Nodes are not null and cannot cross a typed argument boundary.
			# Persisted initial_state lets retries continue without a live match.
			_find_or_create_game(_controller if is_instance_valid(_controller) else null, record, key)
		else:
			_flush_turns(record, key)
		if _active_request != null:
			return


func _schedule_retry() -> void:
	_retry_delay = _retry_backoff
	_retry_backoff = minf(60.0, _retry_backoff * 2.0)


## Returns the local match key currently associated with this client.
func current_match_id() -> String:
	return _local_match_id


func has_cached_matches() -> bool:
	return not _records.is_empty()


## Clears every locally tracked match record and queues remote deletions.
func clear_all_match_caches() -> void:
	var match_keys: Array[String] = []
	for key: Variant in _records.keys():
		match_keys.append(String(key))
	for match_key: String in match_keys:
		clear_match_cache(match_key)


## Clears one match's persisted API mapping and requests deletion of its remote
## game when a game ID and authenticated token are available.
func clear_match_cache(match_key: String) -> void:
	if match_key.is_empty():
		return
	var record: Dictionary = _match_record(match_key)
	var game_id: String = String(record.get("game_id", ""))
	_records.erase(match_key)
	if _local_match_id == match_key:
		_local_match_id = ""
		_on_preview_changed()
	if _active_request != null and _active_match_key == match_key:
		_active_request.cancel_request()
		_finish_request(_active_request)
	if not game_id.is_empty():
		if not _pending_deletes.has(game_id):
			_pending_deletes.append(game_id)
		_save_records()
		_start_next_delete()
	else:
		_save_records()


func attach_controller(controller: GameSessionController) -> void:
	if _controller != null and is_instance_valid(_controller):
		if _controller.session_started.is_connected(_on_session_started):
			_controller.session_started.disconnect(_on_session_started)
		if _controller.line_committed.is_connected(_on_line_committed):
			_controller.line_committed.disconnect(_on_line_committed)
		if _controller.swap_committed.is_connected(_on_swap_committed):
			_controller.swap_committed.disconnect(_on_swap_committed)
		if _controller.match_ended.is_connected(_on_match_ended):
			_controller.match_ended.disconnect(_on_match_ended)
		_controller.turn_passed.disconnect(_on_turn_passed)
		_controller.preview_changed.disconnect(_on_preview_changed)
		_controller.state_changed.disconnect(_on_preview_changed)
	_controller = controller
	if _controller == null:
		return
	_controller.session_started.connect(_on_session_started)
	_controller.line_committed.connect(_on_line_committed)
	_controller.swap_committed.connect(_on_swap_committed)
	_controller.match_ended.connect(_on_match_ended)
	_controller.turn_passed.connect(_on_turn_passed)
	_controller.preview_changed.connect(_on_preview_changed)
	_controller.state_changed.connect(_on_preview_changed)
	if _controller.has_session():
		_begin_match(_controller)


func _on_session_started() -> void:
	_begin_match(_controller)


func _begin_match(controller: GameSessionController) -> void:
	if controller == null or not is_instance_valid(controller):
		return
	var match_key: String = String(controller.get_match_id())
	if _local_match_id != match_key:
		_preview_supported = true
	_local_match_id = match_key
	if _local_match_id.is_empty():
		return
	var record: Dictionary = _match_record(_local_match_id)
	if not record.has("initial_state"):
		record["initial_state"] = controller.match_snapshot_dictionary()
		_save_records()
	_on_preview_changed()
	if access_token.is_empty():
		return
	if String(record.get("game_id", "")).is_empty():
		if _active_request == null:
			_find_or_create_game(controller, record)
	else:
		# Resume verifies the stored API version before sending pending commands.
		if _active_request == null:
			_lookup_game(_local_match_id, "resume_lookup")


func _on_line_committed(result: LineResult, _turn_phase: int) -> void:
	if result == null or not result.was_committed() or _controller == null:
		return
	if _local_match_id.is_empty():
		_local_match_id = String(_controller.get_match_id())
	if _local_match_id.is_empty():
		return
	var record: Dictionary = _match_record(_local_match_id)
	var history: Array[ScoringMove] = _controller.get_session().get_history()
	if not history.is_empty() and history.back().player_id != TurnEnums.HUMAN_PLAYER_ID:
		# The API infers player identity from the bearer token. Never impersonate
		# the AI as the human; its move and score are preserved in localState.
		_queue_state_update(record, "completed" if _controller.final_result() != null else "active")
		_flush_turns(record, _local_match_id)
		return
	var placements: Array[Dictionary] = []
	for snapshot: TileSnapshot in result.staged_tiles:
		if snapshot == null or not snapshot.is_valid():
			continue
		var cell: Vector2i = snapshot.get_cell()
		placements.append({
			"tileId": String(snapshot.get_tile_id()),
			"x": cell.x,
			"y": cell.y,
		})
	if placements.is_empty():
		return
	var pending: Array = record.get("pending", [])
	var snapshot: Dictionary = _controller.match_snapshot_dictionary()
	var revision: int = maxi(int(record.get("sync_revision", 0)), pending.size()) + 1
	record["sync_revision"] = revision
	var final_result: MatchResult = _controller.final_result()
	pending.append({
		"turnId": _new_uuid(),
		"placements": placements,
		"stateAfter": snapshot,
		"statusAfter": "completed" if final_result != null else "active",
		"revision": revision,
		"turnAccepted": false,
	})
	record["pending"] = pending
	_save_records()
	if String(record.get("game_id", "")).is_empty():
		_begin_match(_controller)
	else:
		_flush_turns(record, _local_match_id)


func _on_match_ended(_result: MatchResult) -> void:
	if _controller == null or _local_match_id.is_empty():
		return
	var record: Dictionary = _match_record(_local_match_id)
	var pending: Array = record.get("pending", [])
	if not pending.is_empty() and pending[pending.size() - 1] is Dictionary:
		var last_update: Dictionary = pending[pending.size() - 1]
		if String(last_update.get("statusAfter", "active")) != "completed":
			if pending.size() == 1 and _active_request != null and _request_kind == "update":
				_queue_state_update(record, "completed")
			else:
				last_update["statusAfter"] = "completed"
				last_update["stateAfter"] = _controller.match_snapshot_dictionary()
				record["pending"] = pending
				_save_records()
	else:
		_queue_state_update(record, "completed")
	_flush_turns(record, _local_match_id)


func _on_swap_committed(_returned_count: int, _turn_phase: int) -> void:
	if _controller == null or _local_match_id.is_empty():
		return
	var record: Dictionary = _match_record(_local_match_id)
	var status: String = "completed" if _controller.final_result() != null else "active"
	_queue_state_update(record, status)
	_flush_turns(record, _local_match_id)


func _on_turn_passed(player_id: StringName) -> void:
	if _controller == null or _local_match_id.is_empty():
		return
	var record: Dictionary = _match_record(_local_match_id)
	_queue_state_update(record, "completed" if _controller.final_result() != null else "active")
	var pending: Array = record.get("pending", [])
	if player_id == TurnEnums.HUMAN_PLAYER_ID and not pending.is_empty():
		pending.back()["pass"] = true
		pending.back()["turnAccepted"] = false
	_save_records()
	_flush_turns(record, _local_match_id)


func _find_or_create_game(controller: GameSessionController, record: Dictionary, match_key: String = "") -> void:
	if _active_request != null:
		return
	if match_key.is_empty():
		match_key = _local_match_id
	if not record.has("initial_state"):
		if controller == null or String(controller.get_match_id()) != match_key:
			return
		record["initial_state"] = controller.match_snapshot_dictionary()
		_save_records()
	var request := _new_request("list", match_key)
	var err: int = _send_http(request,
		ApiConfiguration.api_base_url() + "/games",
		_request_headers(false)
	)
	if err != OK:
		_finish_request(request)
		_schedule_retry()
		push_warning("GameSyncApiClient: game lookup request could not start (%s)." % error_string(err))


func _create_game(match_key: String, record: Dictionary) -> void:
	if _active_request != null:
		return
	var request := _new_request("create", match_key)
	var state: Dictionary = {"clientMatchId": match_key}
	var local_state: Variant = record.get("initial_state", {})
	if local_state is Dictionary and not local_state.is_empty():
		state["localState"] = local_state
	var err: int = _send_http(request,
		ApiConfiguration.api_base_url() + "/games",
		_request_headers(true),
		HTTPClient.METHOD_POST,
		JSON.stringify({"state": state})
	)
	if err != OK:
		_finish_request(request)
		_schedule_retry()
		push_warning("GameSyncApiClient: game creation request could not start (%s)." % error_string(err))


func _flush_turns(record: Dictionary, match_key: String) -> void:
	if _active_request != null or access_token.is_empty():
		return
	var game_id: String = String(record.get("game_id", ""))
	var pending: Array = record.get("pending", [])
	if game_id.is_empty() or pending.is_empty():
		return
	var turn: Variant = pending[0]
	if not turn is Dictionary:
		pending.pop_front()
		record["pending"] = pending
		_save_records()
		_flush_turns(record, match_key)
		return
	if bool(turn.get("turnAccepted", false)):
		_patch_game_state(record, match_key, turn)
		return
	var passing: bool = bool(turn.get("pass", false))
	var request := _new_request("pass" if passing else "turn", match_key)
	var payload: Dictionary = {
		"turnId": String(turn.get("turnId", "")),
		"expectedVersion": maxi(1, int(record.get("version", 1))),
		"placements": turn.get("placements", []),
	}
	if passing:
		payload.erase("placements")
	var err: int = _send_http(request,
		ApiConfiguration.api_base_url() + "/games/%s/%s" % [game_id.uri_encode(), "pass" if passing else "turns"],
		_request_headers(true),
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if err != OK:
		_finish_request(request)
		_schedule_retry()
		push_warning("GameSyncApiClient: turn request could not start (%s)." % error_string(err))


func _patch_game_state(record: Dictionary, match_key: String, update: Dictionary) -> void:
	if _active_request != null or access_token.is_empty():
		return
	var game_id: String = String(record.get("game_id", ""))
	if game_id.is_empty():
		return
	var local_state: Variant = update.get("stateAfter", {})
	if not local_state is Dictionary or (local_state as Dictionary).is_empty():
		if _controller == null or not _controller.has_session():
			return
		local_state = _controller.match_snapshot_dictionary()
	var game_state: Dictionary = {
		"clientMatchId": match_key,
		"syncRevision": maxi(1, int(update.get("revision", record.get("sync_revision", 0)))),
		"localState": local_state,
	}
	var final_result: MatchResult = (
		_controller.final_result() if _controller != null else null
	)
	if final_result != null:
		# Keep the replayable snapshot and the compact result together in the API
		# game state. In particular, resignation's winner may differ from the
		# score comparison, so consumers should use this explicit result record.
		game_state["result"] = final_result.to_dictionary()
	record["sync_revision"] = maxi(
		int(record.get("sync_revision", 0)), int(game_state["syncRevision"])
	)
	_save_records()
	var request := _new_request("update", match_key)
	var payload: Dictionary = {
		"expectedVersion": maxi(1, int(record.get("version", 1))),
		"state": game_state,
		"status": String(update.get("statusAfter", "active")),
	}
	var err: int = _send_http(request,
		ApiConfiguration.api_base_url() + "/games/%s" % game_id.uri_encode(),
		_request_headers(true),
		HTTPClient.METHOD_PATCH,
		JSON.stringify(payload)
	)
	if err != OK:
		_finish_request(request)
		_schedule_retry()
		push_warning("GameSyncApiClient: game update request could not start (%s)." % error_string(err))


func _queue_state_update(record: Dictionary, status: String) -> void:
	if _controller == null:
		return
	var pending: Array = record.get("pending", [])
	var snapshot: Dictionary = _controller.match_snapshot_dictionary()
	var revision: int = int(record.get("sync_revision", 0)) + 1
	record["sync_revision"] = revision
	pending.append({
		"turnId": _new_uuid(),
		"placements": [],
		"stateAfter": snapshot,
		"statusAfter": status,
		"revision": revision,
		"turnAccepted": true,
	})
	record["pending"] = pending
	_save_records()


func _new_request(kind: String, match_key: String) -> HTTPRequest:
	var request := HTTPRequest.new()
	request.timeout = 15.0
	request.request_completed.connect(_on_request_completed.bind(request, kind, match_key))
	add_child(request)
	_active_request = request
	_request_kind = kind
	_active_match_key = match_key
	return request


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	request: HTTPRequest,
	kind: String,
	match_key: String
) -> void:
	if request != _active_request:
		return
	var successful_transport: bool = result == HTTPRequest.RESULT_SUCCESS
	# Authentication depends on the status, even for an empty/non-JSON body.
	if successful_transport and response_code == 401:
		access_token = ""
		_finish_request(request)
		authentication_required.emit()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if successful_transport else null
	var data: Dictionary = parsed if parsed is Dictionary else {}
	if kind == "preview":
		_handle_preview_response(result, response_code, data)
		_finish_request(request)
		if _records.has(match_key):
			_flush_turns(_match_record(match_key), match_key)
		return
	if kind == "delete":
		if successful_transport and response_code in [204, 404]:
			_pending_deletes.pop_front()
			_save_records()
			_finish_request(request)
			retry_pending()
			return
		push_warning(
			"GameSyncApiClient: remote game deletion failed (transport %s, HTTP %d): %s" % [
				str(result), response_code, body.get_string_from_utf8()
			]
		)
		sync_notice.emit("The local game was cleared, but the server game could not be deleted")
		_finish_request(request)
		if not successful_transport or response_code >= 500 or response_code == 429:
			_schedule_retry()
		return
	if kind == "list" and successful_transport and response_code == 200 and parsed is Array:
		var record: Dictionary = _match_record(match_key)
		for game_variant: Variant in parsed:
			if not game_variant is Dictionary:
				continue
			var game: Dictionary = game_variant
			var state_variant: Variant = game.get("state", {})
			if not state_variant is Dictionary:
				continue
			if String(state_variant.get("clientMatchId", "")) != match_key:
				continue
			record["game_id"] = String(game.get("id", ""))
			record["version"] = maxi(1, int(game.get("version", 1)))
			record["sync_revision"] = maxi(
				int(record.get("sync_revision", 0)), int(state_variant.get("syncRevision", 0))
			)
			break
		_save_records()
		_finish_request(request)
		if String(record.get("game_id", "")).is_empty():
			_create_game(match_key, record)
		else:
			_flush_turns(record, match_key)
		if _active_request == null:
			retry_pending()
		return
	if kind == "create" and successful_transport and response_code == 201:
		var record: Dictionary = _match_record(match_key)
		record["game_id"] = String(data.get("id", ""))
		record["version"] = maxi(1, int(data.get("version", 1)))
		_save_records()
		_finish_request(request)
		if not String(record.get("game_id", "")).is_empty():
			_flush_turns(record, match_key)
			if _active_request == null:
				retry_pending()
		return
	if kind in ["turn", "pass"] and successful_transport and response_code == 200 and data.get("accepted") == true:
		var record: Dictionary = _match_record(match_key)
		var pending: Array = record.get("pending", [])
		if not pending.is_empty() and pending[0] is Dictionary:
			var accepted_turn: Dictionary = pending[0]
			accepted_turn["turnAccepted"] = true
			pending[0] = accepted_turn
		record["pending"] = pending
		record["version"] = maxi(int(record.get("version", 1)), int(data.get("gameVersion", 1)))
		_save_records()
		_finish_request(request)
		_flush_turns(record, match_key)
		return
	if kind == "pass" and successful_transport and response_code == 400 and data.get("error") == "INVALID_TURN":
		# The deployed pass endpoint requires two account members; local AI has
		# no account. Preserve the pass snapshot through the documented PATCH.
		var record: Dictionary = _match_record(match_key)
		var pending: Array = record.get("pending", [])
		if not pending.is_empty():
			pending[0]["turnAccepted"] = true
		_save_records()
		_finish_request(request)
		_flush_turns(record, match_key)
		return
	if kind == "update" and successful_transport and response_code == 200:
		var record: Dictionary = _match_record(match_key)
		var pending: Array = record.get("pending", [])
		if not pending.is_empty():
			pending.pop_front()
		record["pending"] = pending
		record["version"] = maxi(int(record.get("version", 1)), int(data.get("version", 1)))
		_save_records()
		_retry_backoff = 2.0
		_conflict_retry = false
		_finish_request(request)
		_flush_turns(record, match_key)
		if _active_request == null:
			retry_pending()
		return
	if kind in ["update", "turn", "pass"] and successful_transport and response_code == 409 and not _conflict_retry:
		_conflict_retry = true
		_finish_request(request)
		_lookup_game(match_key, "update_lookup" if kind == "update" else "turn_lookup")
		return
	if kind in ["update_lookup", "turn_lookup", "resume_lookup"] and successful_transport and response_code == 200:
		var record: Dictionary = _match_record(match_key)
		var pending: Array = record.get("pending", [])
		record["version"] = maxi(1, int(data.get("version", 1)))
		if not pending.is_empty() and pending[0] is Dictionary:
			var queued_update: Dictionary = pending[0]
			var server_state: Variant = data.get("state", {})
			var server_revision: int = 0
			if server_state is Dictionary:
				server_revision = int((server_state as Dictionary).get("syncRevision", 0))
			if bool(queued_update.get("turnAccepted", false)) and server_revision >= maxi(1, int(queued_update.get("revision", 0))):
				pending.pop_front()
		record["pending"] = pending
		_save_records()
		_finish_request(request)
		_flush_turns(record, match_key)
		return
	push_warning(
		"GameSyncApiClient: %s failed (transport %s, HTTP %d): %s" % [
			kind,
			str(result),
			response_code,
			body.get_string_from_utf8(),
		]
	)
	sync_notice.emit("Match sync is waiting for the server")
	_finish_request(request)
	if not successful_transport or response_code >= 500 or response_code == 429:
		_schedule_retry()


func _lookup_game(match_key: String, kind: String) -> void:
	var lookup := _new_request(kind, match_key)
	var err: int = _send_http(lookup,
		ApiConfiguration.api_base_url() + "/games/%s" % String(_match_record(match_key).get("game_id", "")).uri_encode(),
		_request_headers(false)
	)
	if err != OK:
		_finish_request(lookup)
		_schedule_retry()


func _finish_request(request: HTTPRequest) -> void:
	if is_instance_valid(request):
		request.queue_free()
	if _active_request == request:
		_active_request = null
		_request_kind = ""
		_active_match_key = ""


## Starts the next queued server deletion when the sync transport is idle.
func _start_next_delete() -> void:
	if _active_request != null or _pending_deletes.is_empty() or access_token.is_empty():
		return
	var game_id: String = _pending_deletes[0]
	var request := _new_request("delete", "")
	var err: int = _send_http(request,
		ApiConfiguration.api_base_url() + "/games/%s" % game_id.uri_encode(),
		_request_headers(false),
		HTTPClient.METHOD_DELETE
	)
	if err != OK:
		_finish_request(request)
		_schedule_retry()
		push_warning("GameSyncApiClient: game deletion request could not start (%s)." % error_string(err))


func _request_headers(json_body: bool) -> PackedStringArray:
	var headers := PackedStringArray(["Authorization: Bearer %s" % access_token])
	if json_body:
		headers.append("Content-Type: application/json")
	return headers


func _on_preview_changed() -> void:
	_preview_generation += 1
	_preview_delay = 0.3
	_preview_pending = true
	score_preview_received.emit({})


## Debounce drag/rotation changes and wait until queued state reaches the server.
func _send_preview() -> void:
	if _active_request != null or access_token.is_empty() or not _preview_supported:
		return
	if _local_match_id.is_empty() or _controller == null or not is_instance_valid(_controller):
		_preview_pending = false
		return
	if not _controller.is_human_turn() or not _controller.is_line_valid():
		_preview_pending = false
		return
	var record: Dictionary = _match_record(_local_match_id)
	var pending: Array = record.get("pending", [])
	var game_id: String = String(record.get("game_id", ""))
	if not pending.is_empty() or game_id.is_empty():
		return
	var placements: Array[Dictionary] = []
	for tile: TileSnapshot in _controller.staged_snapshots():
		placements.append({"tileId": String(tile.get_tile_id()), "x": tile.get_cell().x,
			"y": tile.get_cell().y, "rotation": tile.get_rotation()})
	var request := _new_request("preview", _local_match_id)
	_sent_preview_generation = _preview_generation
	_preview_pending = false
	var err: int = _send_http(request,
		ApiConfiguration.api_base_url() + "/games/%s/turns/preview" % game_id.uri_encode(),
		_request_headers(true), HTTPClient.METHOD_POST,
		JSON.stringify({"expectedVersion": int(record.get("version", 1)), "placements": placements})
	)
	if err != OK:
		_finish_request(request)


func _handle_preview_response(result: int, code: int, data: Dictionary) -> void:
	if _sent_preview_generation != _preview_generation or _active_match_key != _local_match_id:
		return
	if code in [404, 501]:
		# The route is explicitly proposed in OpenAPI. Avoid repeatedly probing
		# a server that has not implemented it; local preview remains usable.
		_preview_supported = false
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var record: Dictionary = _match_record(_local_match_id)
	if data.get("gameVersion", -1) != int(record.get("version", 1)):
		return
	if _controller == null or not _controller.is_human_turn() or not _controller.is_line_valid():
		return
	if data.get("rulesVersion") != _controller.get_session().get_rules().version_key():
		return
	if not is_valid_preview_response(data):
		return
	score_preview_received.emit((data["score"] as Dictionary).duplicate(true))


static func is_valid_preview_response(data: Dictionary) -> bool:
	if data.get("valid") != true or not data.get("score") is Dictionary:
		return false
	var score: Dictionary = data["score"]
	for key: String in ["poker", "edge", "cluster", "total"]:
		var value: Variant = score.get(key)
		if not (value is int or value is float):
			return false
		if not is_finite(float(value)) or float(value) < 0 or float(value) != floorf(float(value)):
			return false
	return score["total"] == score["poker"] + score["edge"] + score["cluster"]


## Transport seam lets contract tests exercise the queue without live accounts.
func _send_http(request: HTTPRequest, url: String, headers: PackedStringArray,
	method: int = HTTPClient.METHOD_GET, body: String = "") -> int:
	return request.request(url, headers, method, body)


func _match_record(match_id: String) -> Dictionary:
	if _records.has(match_id) and _records[match_id] is Dictionary:
		return _records[match_id]
	var record: Dictionary = {"game_id": "", "version": 1, "pending": []}
	_records[match_id] = record
	return record


func _load_records() -> void:
	if not FileAccess.file_exists(sync_path):
		return
	var file := FileAccess.open(sync_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_records = parsed
		var deletes: Variant = _records.get("_pending_deletes", [])
		if deletes is Array:
			for game_id: Variant in deletes:
				if game_id is String:
					_pending_deletes.append(game_id)
		_records.erase("_pending_deletes")


func _save_records() -> void:
	var file := FileAccess.open(sync_path, FileAccess.WRITE)
	if file == null:
		push_warning("GameSyncApiClient: pending match sync could not be saved locally.")
		return
	var stored: Dictionary = _records.duplicate(true)
	stored["_pending_deletes"] = _pending_deletes
	file.store_string(JSON.stringify(stored, "\t"))
	file.close()


func _new_uuid() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12),
	]
