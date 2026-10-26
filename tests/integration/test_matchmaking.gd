extends "res://tests/harness/test_case.gd"

class FakeClient extends MatchmakingApiClient:
	var sent: Array[Dictionary] = []
	func _send_http(_http: HTTPRequest, url: String, _headers: PackedStringArray, method: int, body: String) -> int:
		sent.append({"url": url, "method": method, "headers": _headers, "body": JSON.parse_string(body) if not body.is_empty() else {}})
		return OK
	func complete(code: int, data: Variant, result: int = HTTPRequest.RESULT_SUCCESS) -> void:
		_completed(result, code, PackedStringArray(), JSON.stringify(data).to_utf8_buffer(), _request, _kind)


func _ticket(status: String = "searching") -> Dictionary:
	return {"ticketId": "ticket-one", "status": status, "lobby": {
		"id": "lobby-one", "playable": false, "opponent": {"id": "other", "displayName": "Real Rival"}
	} if status == "matched" else null}


func _client() -> FakeClient:
	var client := FakeClient.new()
	client.set_credentials("test-token", "test-user")
	return client

func test_ready_handshake_hands_off_without_cancelling_the_match() -> void:
	var client: FakeClient = _client()
	client.start_search()
	var matched: Dictionary = _ticket("matched")
	matched.lobby["canReady"] = true
	matched.lobby["ready"] = false
	client.complete(200, {"ticket": matched})
	client.ready_up()
	check_eq(client._kind, "ready", "Ready sends the authenticated readiness command")
	matched.lobby.ready = true
	client.complete(200, matched)
	client._process(2.0)
	check_eq(client._kind, "heartbeat", "waiting after readiness still renews lobby presence")
	matched.status = "playing"
	matched.lobby["matchId"] = "shared-match"
	matched.lobby.playable = true
	client.complete(200, matched)
	check_eq(client.state, "playing", "both-ready response hands off the shared match")
	var sent_count: int = client.sent.size()
	client.leave()
	client._process(10.0)
	check_eq(client.sent.size(), sent_count, "removing the lobby UI never cancels a started game")
	client.free()


func test_search_pairs_and_keeps_the_lobby_alive() -> void:
	var client := _client()
	client.start_search()
	check(client.sent.back().url.ends_with("/tickets/current"), "search recovers an existing ticket before joining")
	client.complete(200, {"ticket": null})
	check_eq(client.sent.back().body.rulesVersion, "pokabow-v3", "queue identifies the compatible game rules")
	check_eq(String(client.sent.back().body.requestId).length(), 36, "join carries an idempotency UUID")
	client.complete(200, _ticket())
	check_eq(client.state, "searching", "a queued account remains searching")
	client._process(2.0)
	check(client.sent.back().url.ends_with("/tickets/ticket-one/heartbeat"), "poll renews presence")
	var matched: Dictionary = _ticket("matched")
	matched.lobby["canReady"] = true
	matched.lobby.opponent["onlineTier"] = "Contender"
	client.complete(200, matched)
	check_eq(client.state, "matched", "server pairing enters the lobby")
	check_eq(client.lobby.opponent.displayName, "Real Rival", "lobby uses the real public opponent name")
	check(client.message.contains("Contender online tier"), "lobby shows the server-owned opponent tier")
	check_eq(client.lobby.playable, false, "lobby does not claim to be playable PvP")
	client._process(2.0)
	check_eq(client._kind, "heartbeat", "matched lobbies continue presence heartbeats")
	client.free()


func test_cancel_during_join_never_shows_the_late_matched_lobby() -> void:
	var client := _client()
	var states: Array[String] = []
	client.changed.connect(func(next: String, _message: String, _lobby: Dictionary) -> void: states.append(next))
	client.start_search()
	client.complete(200, {"ticket": null})
	client.leave()
	client.complete(200, _ticket("matched"))
	check(not states.has("matched"), "a late match response cannot reopen a cancelled screen")
	check_eq(client.sent.back().method, HTTPClient.METHOD_DELETE, "late join success is cancelled on the server")
	check(not client.sent.back().headers.has("Content-Type: application/json"), "bodyless cancellation must not advertise JSON to Fastify")
	client.complete(200, _ticket("cancelled"))
	check_eq(client.state, "idle", "server acknowledgement finishes cancellation")
	client.free()


func test_lost_join_response_uses_request_tombstone_when_cancelled() -> void:
	var client := _client()
	client.start_search()
	client.complete(200, {"ticket": null})
	var key: String = client.sent.back().body.requestId
	client.complete(0, {}, HTTPRequest.RESULT_CANT_CONNECT)
	client.leave()
	check(client.sent.back().url.ends_with("/requests/" + key), "unknown ticket cancellation uses the original join ID")
	client.complete(200, _ticket("cancelled"))
	check_eq(client.state, "idle", "lost join reply does not strand cancellation")
	client.free()


func test_network_retry_recovers_without_duplicate_join_and_auth_refresh_keeps_ticket() -> void:
	var client := _client()
	client.start_search()
	client.complete(200, {"ticket": null})
	client.complete(0, {}, HTTPRequest.RESULT_CANT_CONNECT)
	client._process(2.0)
	check_eq(client._kind, "current", "lost join response is recovered before retrying")
	client.complete(200, {"ticket": _ticket()})
	client._process(2.0)
	var refreshes: Array[int] = []
	client.authentication_required.connect(func() -> void: refreshes.append(1))
	client.complete(401, {})
	check_eq(refreshes.size(), 1, "expired token requests one authentication refresh")
	client.set_credentials("new-token", "test-user")
	check_eq(client._kind, "heartbeat", "same account token refresh preserves the active ticket")
	client.complete(200, _ticket("opponent_left"))
	check_eq(client.state, "failed", "opponent departure enables a new search")
	client.free()


func test_account_change_and_background_resume_do_not_reuse_stale_presence() -> void:
	var client := _client()
	client.start_search()
	client.complete(200, {"ticket": _ticket()})
	client._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	var before: int = client.sent.size()
	client._process(60.0)
	check_eq(client.sent.size(), before, "backgrounded clients do not hold matchmaking presence")
	client._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check_eq(client._kind, "heartbeat", "resume checks the server before claiming presence")
	client.complete(200, _ticket("expired"))
	check_eq(client.state, "failed", "expired search is not silently revived")
	client.start_search()
	client.set_credentials("other-token", "other-user")
	check_eq(client.state, "idle", "account switch clears the old account's queue UI")
	check_eq(client._ticket_id, "", "account switch cannot reuse another user's ticket")
	check(client._request == null, "account switch cancels old account requests")
	client.free()


func test_screen_shows_real_lobby_without_starting_an_ai_match() -> void:
	var screen: OpponentSelectionScreen = load("res://scenes/hub/opponent_selection_screen.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	var client := _client()
	var started: Array[int] = []
	screen.opponent_selected.connect(func(_rival: Dictionary, _portrait: Texture2D) -> void: started.append(1))
	screen.attach_matchmaking(client)
	screen.mode_picker.select(1)
	screen._on_mode_selected(1)
	screen._begin_spin()
	client.complete(200, {"ticket": _ticket("matched")})
	screen._process(5.0)
	check_eq(screen.rival_name_label.text, "Real Rival", "screen shows the API opponent")
	check(screen.start_button.visible and screen.start_button.disabled, "lobby shows progress without a manual ready action")
	check(screen.cancel_match_button.visible, "matched player can cancel beside the progress action")
	check_eq(started.size(), 0, "online lobby must never start a local AI match")
	screen._on_back_pressed()
	client.complete(200, _ticket("cancelled"))
	screen.free()
	client.free()


func test_online_reveal_waits_three_to_five_seconds_then_joins_without_a_tap() -> void:
	var screen: OpponentSelectionScreen = load("res://scenes/hub/opponent_selection_screen.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	var client := _client()
	screen.attach_matchmaking(client)
	screen.select_online()
	screen._begin_spin()
	check(screen._online_reveal_duration >= 3.0 and screen._online_reveal_duration <= 5.0, "online reveal duration is randomized within 3–5 seconds")
	var custom_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	custom_image.fill(Color.RED)
	var custom_portrait := ImageTexture.create_from_image(custom_image)
	screen.set_online_opponent_portrait(custom_portrait)
	client.complete(200, {"ticket": null})
	var matched: Dictionary = _ticket("matched")
	matched.lobby.canReady = true
	client.complete(200, matched)
	check(not screen._online_revealed, "immediate match still runs the avatar reveal")
	check(screen.rival_portrait.texture != custom_portrait, "real opponent photo waits until the reveal completes")
	screen._online_reveal_duration = 4.0
	screen._process(3.5)
	check(not screen._online_revealed and client._kind != "ready", "match cannot auto-ready before the reveal minimum")
	screen._process(0.5)
	check(screen._online_revealed and screen.rival_portrait.texture == custom_portrait, "real opponent photo appears at reveal end")
	check_eq(screen.start_button.text, "Joining in 3...", "countdown starts at three")
	screen._process(1.0)
	check_eq(screen.start_button.text, "Joining in 2...", "countdown advances to two")
	screen._process(1.0)
	check_eq(screen.start_button.text, "Joining in 1...", "countdown advances to one")
	screen._process(1.0)
	check_eq(client._kind, "ready", "countdown sends readiness without a tap")
	screen._process(1.0)
	check_eq(client.sent.filter(func(item: Dictionary) -> bool: return item.url.ends_with("/ready")).size(), 1, "countdown submits readiness once")
	screen.free()
	client.free()


func test_online_search_keeps_cycling_until_match_and_cancel_prevents_join() -> void:
	var screen: OpponentSelectionScreen = load("res://scenes/hub/opponent_selection_screen.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	var client := _client()
	screen.attach_matchmaking(client)
	screen.select_online()
	screen._begin_spin()
	check_eq(screen._online_portraits.size(), 16, "the complete rival roster is available to exported builds")
	client.complete(200, {"ticket": null})
	client.complete(200, _ticket())
	screen._process(6.0)
	check(not screen._online_revealed and screen._online_search_active, "search keeps cycling after five seconds when unmatched")
	var matched: Dictionary = _ticket("matched")
	matched.lobby.canReady = true
	client._process(2.0)
	client.complete(200, matched)
	check(screen._online_revealed, "late match reveals as soon as it is found")
	screen.cancel_match_button.pressed.emit()
	check_eq(client.state, "leaving", "adjacent Cancel leaves the lobby")
	check(not screen._online_search_active, "cancellation stops the avatar cycle and countdown")
	screen._process(4.0)
	check(client._kind != "ready", "cancelled match never sends readiness")
	screen.free()
	client.free()


func test_online_reduced_motion_keeps_reveal_timing_without_avatar_cycling() -> void:
	var previous: Variant = ProjectSettings.get_setting(AccessibilitySettings.REDUCED_MOTION_PATH, false)
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, true)
	var screen: OpponentSelectionScreen = load("res://scenes/hub/opponent_selection_screen.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	var client := _client()
	screen.attach_matchmaking(client)
	screen.select_online()
	screen._begin_spin()
	var first: Texture2D = screen.rival_portrait.texture
	client.complete(200, {"ticket": null})
	var matched: Dictionary = _ticket("matched")
	matched.lobby.canReady = true
	client.complete(200, matched)
	screen._online_reveal_duration = 3.0
	screen._process(2.9)
	check(screen.rival_portrait.texture == first and not screen._online_revealed, "reduced motion holds one portrait through the reveal")
	screen._process(0.1)
	check(screen._online_revealed, "reduced motion keeps the minimum reveal time")
	screen.free()
	client.free()
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, previous)


class QuietApp extends AppRoot:
	var matches_started: int = 0
	func _ready() -> void:
		pass
	func _boot_match(_difficulty: int = -1, _portrait: Texture2D = null) -> bool:
		matches_started += 1
		return true


class LocalFallbackApp extends AppRoot:
	func _ready() -> void:
		pass


func test_verified_ai_fallback_keeps_hub_out_of_live_match() -> void:
	var app := LocalFallbackApp.new()
	var host := Node.new()
	host.name = "SceneHost"
	app.add_child(host)
	(Engine.get_main_loop() as SceneTree).root.add_child(app)
	check(app.show_hub(), "the hub opens before an AI match")
	app._pending_verified_ai_difficulty = AiEnums.Difficulty.MEDIUM
	app._open_verified_ai_when_received = true
	app._on_verified_ai_connection_changed(false, "This verified AI match is no longer available.")
	check_not_null(app.game_screen, "the fallback opens a local Medium match")
	check(not app.hub_screen.visible, "the live match hides the hub behind it")
	app._on_hub_play_requested()
	check(app.opponent_selection_screen == null,
		"a hub Play event cannot replace an active match with the difficulty chooser")
	var save_path: String = app.session_controller.save_path if app.session_controller != null else ""
	app.free()
	if not save_path.is_empty() and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func test_hub_play_now_defaults_to_ai_and_keeps_online_available() -> void:
	var app := QuietApp.new()
	var host := Node.new()
	host.name = "SceneHost"
	app.add_child(host)
	(Engine.get_main_loop() as SceneTree).root.add_child(app)
	app.user_state = {"token": "test-token", "user": {"id": "test-user"}}
	app.matchmaking_client = _client()
	app.add_child(app.matchmaking_client)
	check(app.show_hub(), "hub opens with matchmaking services")
	check_eq((app.hub_screen.get_node("%PlayButton") as Button).text, "Play Now", "the hub has one Play Now action")
	check(app.hub_screen.get_node_or_null("%OnlineButton") == null, "the hub has no separate online action")
	app.hub_screen.get_node("%PlayButton").pressed.emit()
	check(app.opponent_selection_screen != null, "Play Now opens the opponent chooser")
	check_eq(app.opponent_selection_screen.mode_picker.selected, 0, "Play Now defaults to AI rival")
	app.opponent_selection_screen._select_mode(1)
	check_eq(app.opponent_selection_screen.mode_picker.selected, 1, "online play remains available in the chooser")
	check_eq(app.matches_started, 0, "opening a lobby does not replace the saved local game")
	app.opponent_selection_screen._on_back_pressed()
	check(app.hub_screen.visible, "Back returns to the existing hub")
	check(app.opponent_selection_screen == null, "Back releases the selection screen")
	app.hub_screen.get_node("%PlayButton").pressed.emit()
	check(app.opponent_selection_screen != null, "Play Now reopens the chooser")
	check_eq(app.opponent_selection_screen.mode_picker.selected, 0, "reopened chooser defaults to AI rival")
	app.opponent_selection_screen._begin_spin()
	app.opponent_selection_screen._process(100.0)
	app.opponent_selection_screen._process(1.0)
	check_eq(app.matches_started, 1, "AI reveal still boots the original local match route")
	app.free()
