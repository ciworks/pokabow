extends "res://tests/harness/test_case.gd"

class FakeClient extends GameSyncApiClient:
	var sent: Array[Dictionary] = []
	func _send_http(_request: HTTPRequest, url: String, headers: PackedStringArray,
		method: int = HTTPClient.METHOD_GET, body: String = "") -> int:
		sent.append({"url": url, "method": method, "headers": headers,
			"body": JSON.parse_string(body) if not body.is_empty() else {}})
		return OK
	func _save_records() -> void:
		pass
	func complete(code: int, data: Variant) -> void:
		_on_request_completed(HTTPRequest.RESULT_SUCCESS, code, PackedStringArray(),
			JSON.stringify(data).to_utf8_buffer(), _active_request, _request_kind, _active_match_key)

class FakeSession extends GameSessionState:
	var moves: Array[ScoringMove] = []
	func get_history() -> Array[ScoringMove]:
		return moves
	func get_rules() -> ScoringRules:
		return ScoringRules.create_default()

class FakeController extends GameSessionController:
	var tiles: Array[TileSnapshot] = []
	var fixture_session := FakeSession.new()
	func get_session() -> GameSessionState:
		return fixture_session
	func has_session() -> bool:
		return true
	func get_match_id() -> StringName:
		return &"api-test"
	func match_snapshot_dictionary() -> Dictionary:
		return {"fixture": "snapshot"}
	func is_human_turn() -> bool:
		return true
	func is_line_valid() -> bool:
		return not tiles.is_empty()
	func staged_snapshots() -> Array[TileSnapshot]:
		return tiles
	func final_result() -> MatchResult:
		return null


func test_offline_match_and_swap_are_queued_then_created_and_patched() -> void:
	var client := FakeClient.new()
	var controller := FakeController.new()
	client.attach_controller(controller)
	check_eq(client.current_match_id(), "api-test", "offline start retains the match identity")
	controller.swap_committed.emit(2, TurnEnums.MatchPhase.TURN_END)
	check_eq(client.sent.size(), 0, "offline actions must not send unauthenticated requests")
	client.set_access_token("test-token")
	check(client.sent.back().url.ends_with("/games"), "reconnect looks for an existing game")
	client.complete(200, [])
	check_eq(client.sent.back().method, HTTPClient.METHOD_POST, "missing game is created")
	check_eq(client.sent.back().body.state.localState, {"fixture": "snapshot"}, "creation carries initial state")
	client.complete(201, {"id": "remote-game", "version": 1})
	check_eq(client.sent.back().method, HTTPClient.METHOD_PATCH, "swap sync uses the implemented state endpoint")
	check_eq(client.sent.back().body.expectedVersion, 1, "patch uses returned API version")
	client.complete(200, {"version": 2})
	check_eq(client._records["api-test"].pending.size(), 0, "only successful patch removes the action")
	client.free()
	controller.free()


func test_retry_after_controller_is_freed_uses_saved_initial_state() -> void:
	var client := FakeClient.new()
	var controller := FakeController.new()
	client.attach_controller(controller)
	controller.free()
	client.access_token = "test-token"
	client.retry_pending()
	check_eq(client.sent.size(), 1, "retry must work without the freed controller")
	client.complete(200, [])
	check_eq(client.sent.back().body.state.localState, {"fixture": "snapshot"},
		"retry creates the game from the persisted snapshot")
	client.free()


func test_detaching_controller_preserves_sync_record_and_disconnects_signals() -> void:
	var client := FakeClient.new()
	var controller := FakeController.new()
	client.attach_controller(controller)
	client.attach_controller(null)
	check(client._controller == null, "hub transition must release the controller reference")
	check(not controller.session_started.is_connected(client._on_session_started),
		"detaching must disconnect the old session")
	check(not controller.preview_changed.is_connected(client._on_preview_changed),
		"detaching must disconnect preview changes")
	controller.free()
	client.set_access_token("test-token")
	check_eq(client.sent.size(), 1, "login in the hub must retry the saved match")
	check_eq(client.current_match_id(), "api-test", "detaching must retain the queued match identity")
	client.free()


func test_pass_uses_contract_and_falls_back_for_local_ai() -> void:
	var client := FakeClient.new()
	var controller := FakeController.new()
	client.attach_controller(controller)
	client._records["api-test"]["game_id"] = "remote-game"
	client.access_token = "test-token"
	controller.turn_passed.emit(TurnEnums.HUMAN_PLAYER_ID)
	var command: Dictionary = client.sent.back()
	check(command.url.ends_with("/games/remote-game/pass"), "human pass reaches the pass endpoint")
	check_eq(command.body.keys().size(), 2, "pass sends only turnId and expectedVersion")
	check(command.body.has("turnId"), "pass has a retry-safe action ID")
	client.complete(400, {"error": "INVALID_TURN"})
	check_eq(client.sent.back().method, HTTPClient.METHOD_PATCH, "single-account AI match preserves the local pass snapshot")
	client.complete(200, {"version": 2})
	controller.turn_passed.emit(TurnEnums.AI_PLAYER_ID)
	check_eq(client.sent.back().method, HTTPClient.METHOD_PATCH, "AI pass is not submitted as the human")
	client.free()
	controller.free()


func test_turn_conflict_refreshes_version_without_changing_id() -> void:
	var client := FakeClient.new()
	client.access_token = "test-token"
	var record: Dictionary = client._match_record("api-test")
	record["game_id"] = "remote-game"
	record["pending"] = [{"turnId": "stable-id", "placements": [{"tileId": "t", "x": 5, "y": 5}],
		"stateAfter": {"fixture": true}, "revision": 1, "turnAccepted": false}]
	client._flush_turns(record, "api-test")
	client.complete(409, {"error": "STALE_GAME_STATE"})
	check_eq(client.sent.back().method, HTTPClient.METHOD_GET, "conflict refreshes the current game")
	client.complete(200, {"version": 7, "state": {}})
	check_eq(client.sent.back().body.turnId, "stable-id", "retry preserves idempotency ID")
	check_eq(client.sent.back().body.expectedVersion, 7, "retry uses refreshed version")
	client.complete(200, {"accepted": true, "duplicate": true, "score": 5, "gameVersion": 8})
	check_eq(client.sent.back().method, HTTPClient.METHOD_PATCH, "accepted turn is followed by real local score/state sync")
	check_eq(client.sent.back().body.expectedVersion, 8, "state update follows the accepted turn version")
	check_eq(record.pending.size(), 1, "action remains durable until state update succeeds")
	client.complete(200, {"version": 9})
	check_eq(record.pending.size(), 0, "completed update drains the queue")
	client.free()


func test_preview_serializes_rotations_and_ignores_stale_or_unavailable_result() -> void:
	var client := FakeClient.new()
	var controller := FakeController.new()
	var edges: Array[TileEnums.EdgeColor] = [0, 1, 2, 3]
	var tile := TileDefinition.create(&"tile-1", TileEnums.TileRank.JACK, TileEnums.FaceColor.RED, edges)
	controller.tiles.append(TileSnapshot.create(tile, Vector2i(5, 5), 3))
	client.attach_controller(controller)
	client._records["api-test"]["game_id"] = "remote-game"
	client._records["api-test"]["version"] = 4
	client.access_token = "test-token"
	client._process(0.1)
	check_eq(client.sent.size(), 0, "rapid staging changes are debounced")
	client._process(0.3)
	check(client.sent.back().url.ends_with("/turns/preview"), "preview reaches the proposed endpoint")
	check_eq(client.sent.back().body.placements[0].rotation, 3, "rotation uses quarter turns")
	check_eq(client.sent.back().body.expectedVersion, 4, "preview uses API version")
	controller.preview_changed.emit()
	client.complete(200, {"valid": true, "gameVersion": 4, "rulesVersion": "scoring:7",
		"score": {"poker": 4, "edge": 0, "cluster": 0, "total": 4}})
	check(client._preview_pending, "stale response leaves the new preview pending")
	client._process(0.4)
	client.complete(404, {})
	var sent_count: int = client.sent.size()
	controller.preview_changed.emit()
	client._process(1.0)
	check_eq(client.sent.size(), sent_count, "unimplemented preview is not hammered repeatedly")
	client.free()
	controller.free()


func test_preview_response_requires_integer_nonnegative_consistent_scores() -> void:
	check(GameSyncApiClient.is_valid_preview_response({"valid": true,
		"score": {"poker": 4.0, "edge": 1.0, "cluster": 0.0, "total": 5.0}}), "JSON integer-valued numbers are accepted")
	check(not GameSyncApiClient.is_valid_preview_response({"valid": true,
		"score": {"poker": 4, "edge": 1, "cluster": 0, "total": 99}}), "inconsistent totals are rejected")
	check(not GameSyncApiClient.is_valid_preview_response({"valid": true,
		"score": {"poker": -1, "edge": 1, "cluster": 0, "total": 0}}), "negative points are rejected")
	check(not GameSyncApiClient.is_valid_preview_response({"valid": true,
		"score": {"poker": 0.5, "edge": 0, "cluster": 0, "total": 0.5}}), "fractional points are rejected")


func test_delete_waits_for_auth_and_retries_after_server_failure() -> void:
	var client := FakeClient.new()
	client._match_record("api-test")["game_id"] = "remote-game"
	client.clear_match_cache("api-test")
	check_eq(client._pending_deletes, ["remote-game"], "offline deletion is retained")
	client.set_access_token("test-token")
	check_eq(client.sent.back().method, HTTPClient.METHOD_DELETE, "login flushes queued delete")
	client.complete(503, {})
	check_eq(client._pending_deletes.size(), 1, "failed deletion is not discarded")
	client._process(3.0)
	check_eq(client.sent.size(), 2, "retry sends the delete again")
	client.complete(204, {})
	check(client._pending_deletes.is_empty(), "successful delete clears the queue")
	client.free()


func test_ai_line_only_patches_state_and_never_credits_the_human() -> void:
	var client := FakeClient.new()
	var controller := FakeController.new()
	client.attach_controller(controller)
	client._records["api-test"]["game_id"] = "remote-game"
	client.access_token = "test-token"
	var move := ScoringMove.new()
	move.player_id = TurnEnums.AI_PLAYER_ID
	controller.fixture_session.moves.append(move)
	var result := LineResult.new()
	result.accepted = true
	result.move_id = &"ai-move"
	controller.line_committed.emit(result, TurnEnums.MatchPhase.TURN_END)
	check_eq(client.sent.size(), 1, "AI line sends one state update")
	check_eq(client.sent[0].method, HTTPClient.METHOD_PATCH, "AI action never goes to the human turn route")
	check(not client.sent[0].body.has("placements"), "AI placements are stored in localState, not attributed to the bearer")
	client.free()
	controller.free()


func test_unauthorized_turn_keeps_queue_and_requests_login_once() -> void:
	var client := FakeClient.new()
	client.access_token = "expired-token"
	var signals: Array[int] = [0]
	client.authentication_required.connect(func() -> void: signals[0] += 1)
	var record: Dictionary = client._match_record("api-test")
	record["game_id"] = "remote-game"
	record["pending"] = [{"turnId": "same-turn", "placements": [{"tileId": "t", "x": 5, "y": 5}]}]
	client._flush_turns(record, "api-test")
	client.complete(401, {"error": "UNAUTHORIZED"})
	check_eq(signals[0], 1, "authentication failure asks the shell for a fresh login")
	check_eq(record.pending[0].turnId, "same-turn", "expired authentication does not lose the action")
	client.retry_pending()
	check_eq(client.sent.size(), 1, "expired token is not retried")
	client.free()


func test_current_valid_preview_is_delivered_without_mutating_sync_version() -> void:
	var client := FakeClient.new()
	var controller := FakeController.new()
	var edges: Array[TileEnums.EdgeColor] = [0, 1, 2, 3]
	controller.tiles.append(TileSnapshot.create(TileDefinition.create(&"tile", TileEnums.TileRank.JACK,
		TileEnums.FaceColor.RED, edges), Vector2i(5, 5)))
	client.attach_controller(controller)
	client._records["api-test"]["game_id"] = "remote-game"
	client.access_token = "test-token"
	var delivered: Array[Dictionary] = []
	client.score_preview_received.connect(func(score: Dictionary) -> void: delivered.append(score))
	client._process(1.0)
	client.complete(200, {"valid": true, "gameVersion": 1, "rulesVersion": "scoring:7",
		"score": {"poker": 4, "edge": 0, "cluster": 0, "total": 4}})
	check_eq(delivered.size(), 1, "only the matching response is delivered")
	check_eq(delivered[0].total, 4, "the displayed preview receives server totals")
	check_eq(client._records["api-test"].version, 1, "preview leaves the API version unchanged")
	check(client._records["api-test"].pending.is_empty(), "preview creates no mutation or achievement action")
	client.free()
	controller.free()


func test_profile_updates_username_inline_and_keeps_email_read_only() -> void:
	var packed: PackedScene = load("res://scenes/profile/profile_screen.tscn")
	var screen: Variant = packed.instantiate()
	screen._ready()
	screen.set_user_state({"user": {"id": "user-1", "displayName": "API Player", "email": null}})
	var email: LineEdit = screen.get_node("%EmailField")
	check_eq((screen.find_child("ProfileDisplayName", true, false) as Label).text, "API Player", "profile summary uses the current account name")
	var account_details: Control = screen.find_child("AccountDetails", true, false) as Control
	check(account_details != null and account_details.get_parent().name == "ProfileSummary", "account details occupy the subtitle position in the profile summary")
	check_eq(screen._profile_name.autowrap_mode, TextServer.AUTOWRAP_OFF, "the profile username stays on one horizontal line")
	check_eq(screen._profile_name.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "long usernames truncate cleanly beside the edit icon")
	check(screen._username_edit_row is VBoxContainer, "the inline editor gives the text field the full profile width")
	check(screen._username_editor.size_flags_horizontal & Control.SIZE_EXPAND_FILL != 0, "the username field expands above its actions")
	check_eq(email.text, "", "nullable email is handled without an invalid String conversion")
	check(screen.get_node_or_null("%UsernameField") == null, "account details no longer duplicate the profile username")
	check(not email.editable, "email remains read-only")
	var emitted: Array[Dictionary] = []
	screen.profile_save_requested.connect(func(username: String, avatar_data: String) -> void:
		emitted.append({"username": username, "avatar": avatar_data})
	)
	screen._begin_username_edit()
	check(screen._username_edit_row.visible and not screen._username_display_row.visible, "pencil opens the inline editor")
	screen._username_editor.text = "New Player"
	screen._submit_current_username()
	check_eq(screen._profile_name.text, "New Player", "inline Done stages the edited username")
	(screen.find_child("SaveProfile", true, false) as Button).pressed.emit()
	check_eq(emitted.size(), 1, "profile save submits the edited username")
	check_eq(emitted[0].username, "New Player", "combined save contains the staged username")
	var avatar_image := Image.new()
	check_eq(avatar_image.load_png_from_buffer(Marshalls.base64_to_raw(emitted[0].avatar)), OK, "combined save contains a valid normalized PNG")
	check_eq(avatar_image.get_size(), Vector2i(195, 195), "combined save uses the avatar contract dimensions")
	screen.set_profile_save_pending(true)
	screen.set_profile_save_pending(false)
	screen.set_profile_avatar_persisted(emitted[0].avatar)
	screen.set_profile_save_result(true)
	check_eq(screen._profile_name.text, "New Player", "successful update returns to the profile label")
	check(not screen._username_edit_row.visible and screen._username_display_row.visible, "successful update closes the inline editor")
	check_eq((screen.get_node("%UpdateButton") as Button).text, "Refresh", "refresh remains separate from profile saving")
	var refreshed: Array[bool] = [false]
	screen.refresh_requested.connect(func() -> void: refreshed[0] = true)
	screen._on_update_pressed()
	check(refreshed[0], "Refresh asks the shell to reload the API profile")
	screen.free()
