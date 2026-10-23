extends "res://tests/harness/test_case.gd"

const ACCOUNT_DIRECTORY: String = "user://test_authentication_recovery"
const ACCOUNT_PATH: String = ACCOUNT_DIRECTORY + "/users_state.json"

class FakeApp extends AppRoot:
	var login_requests: int = 0
	var login_request: HTTPRequest
	var start_error: int = OK
	var error_shown: bool = false
	var restarts: int = 0
	func _restart_for_new_account() -> void:
		restarts += 1
	func _ready() -> void:
		pass
	func _send_login_request(client: HTTPRequest, _headers: PackedStringArray, _body: String) -> int:
		login_requests += 1
		login_request = client
		return start_error
	func complete(code: int, data: Dictionary, result: int = HTTPRequest.RESULT_SUCCESS) -> void:
		_on_returning_login_completed(result, code, PackedStringArray(), JSON.stringify(data).to_utf8_buffer(), login_request)
	func _show_authentication_error(message: String = "") -> void:
		error_shown = true
		# The general runner also calls suites before entering the scene tree.
		# The focused runner exercises the actual dialog after tree startup.
		if is_inside_tree():
			super._show_authentication_error(message)


func _app() -> FakeApp:
	DirAccess.make_dir_recursive_absolute(ACCOUNT_DIRECTORY)
	UsersStateStore.save_accepted_account("test-user", "test-password", "test@example.invalid", ACCOUNT_PATH)
	UsersStateStore.save_user_state({"token": "expired-token", "user": {"id": "account-one"}}, ACCOUNT_PATH)
	UsersStateStore.queue_achievement_ids(["first_hand"], ACCOUNT_PATH)
	var app := FakeApp.new()
	app.users_path = ACCOUNT_PATH
	app.user_state = UsersStateStore.load_user_state(ACCOUNT_PATH)
	var host := Node.new()
	host.name = "SceneHost"
	app.add_child(host)
	var overlay := CanvasLayer.new()
	overlay.name = "OverlayLayer"
	app.add_child(overlay)
	app.game_sync_client = GameSyncApiClient.new()
	app.game_sync_client.sync_path = "user://test_authentication_sync_unused.json"
	app.add_child(app.game_sync_client)
	app.matchmaking_client = MatchmakingApiClient.new()
	app.add_child(app.matchmaking_client)
	app.online_client = OnlineGameApiClient.new()
	app.add_child(app.online_client)
	app.game_sync_client.access_token = "expired-token"
	app.matchmaking_client.set_credentials("expired-token", "account-one")
	app.online_client.set_credentials("expired-token", "account-one")
	app.matchmaking_client.authentication_required.connect(app._refresh_api_login)
	app.online_client.authentication_required.connect(app._refresh_api_login)
	(Engine.get_main_loop() as SceneTree).root.add_child(app)
	return app


func _dispose(app: FakeApp) -> void:
	app.free()
	UsersStateStore.clear_local_state(ACCOUNT_DIRECTORY, "account-one")
	DirAccess.remove_absolute(ACCOUNT_DIRECTORY)


func test_401_coalesces_login_and_success_restores_all_transports() -> void:
	var app := _app()
	app._refresh_api_login()
	app._refresh_api_login()
	check_eq(app.login_requests, 1, "concurrent unauthorized clients share one login")
	check(not UsersStateStore.has_user_state(ACCOUNT_PATH), "rejected token is removed from disk")
	check_eq(app.game_sync_client.access_token, "", "sync cannot reuse the rejected token")
	check(UsersStateStore.has_accepted_account(ACCOUNT_PATH), "account credentials and acceptance survive")
	check_eq(UsersStateStore.pending_achievement_ids(ACCOUNT_PATH), ["first_hand"], "queued unlocks survive")
	app.complete(200, {"token": "fresh-token", "user": {"id": "account-one"}})
	check(not app._login_active, "successful login releases the busy flag")
	check_eq(app.game_sync_client.access_token, "fresh-token", "sync resumes with fresh credentials")
	check_eq(app.online_client.access_token, "fresh-token", "online play receives the new token")
	check_eq(app.matchmaking_client.access_token, "fresh-token", "matchmaking receives the new token")
	check_eq(UsersStateStore.load_user_state(ACCOUNT_PATH).get("token"), "fresh-token", "new session persists")
	_dispose(app)


func test_temporary_login_failure_exits_waiting_and_allows_explicit_retry() -> void:
	var app := _app()
	app.matchmaking_client._wanted = true
	app.online_client._wanted = true
	app.online_client._pending = {"commandId": "stable-command"}
	app._refresh_api_login()
	app.complete(503, {})
	check(not app._login_active, "failed login releases the busy flag")
	check_eq(app.matchmaking_client.state, "failed", "matchmaking enables Back and Find opponent")
	check(app.error_shown, "authentication error is presented")
	check(app._authentication_error.contains("Could not sign in"), "error explains connection failure")
	if app.is_inside_tree():
		check(app._authentication_dialog.visible, "authentication error is visible")
	app.online_client._process(120.0)
	check_eq(app.login_requests, 1, "online polling cannot restart failed login forever")
	check_eq(app.online_client._pending.get("commandId"), "stable-command", "pending online command is preserved")
	app.matchmaking_client.start_search()
	check_eq(app.matchmaking_client.state, "failed", "another search with rejected credentials cannot get stuck waiting")
	check_eq(app.login_requests, 1, "another search offers explicit retry instead of silently logging in")
	if app.is_inside_tree():
		app._authentication_dialog.confirmed.emit()
	else:
		app._retry_api_login()
	check_eq(app.login_requests, 2, "Retry starts exactly one new login")
	app.complete(200, {"token": "retry-token", "user": {"id": "account-one"}})
	check(not app.online_client._authentication_pending, "successful retry permits polling again")
	_dispose(app)


func test_rejected_fresh_token_stops_automatic_login_loop() -> void:
	var app := _app()
	app._refresh_api_login()
	app.complete(200, {"token": "still-rejected", "user": {"id": "account-one"}})
	app._refresh_api_login()
	check_eq(app.login_requests, 1, "immediate repeat 401 does not start another automatic login")
	check(app._authentication_blocked, "user can choose when to retry")
	check(not UsersStateStore.has_user_state(ACCOUNT_PATH), "fresh but rejected token is also discarded")
	_dispose(app)


func test_rejected_saved_login_clears_old_account_and_restarts_setup() -> void:
	var app := _app()
	for filename: String in ["match_save.json", "match_fixture.json", "game_sync_state.json", "online_%s.txt" % "account-one".sha256_text()]:
		var file := FileAccess.open(ACCOUNT_DIRECTORY.path_join(filename), FileAccess.WRITE)
		file.store_string("old-account-data")
		file.close()
	var settings := ConfigFile.new()
	settings.set_value("network", "server_ip", "192.0.2.25")
	settings.set_value("profile", "display_name", "Old player")
	settings.save(ACCOUNT_DIRECTORY.path_join("settings.cfg"))
	app._refresh_api_login()
	app.complete(401, {})
	check(app._account_reset_pending, "rejected saved credentials request new-account setup")
	app._refresh_api_login()
	check_eq(app.login_requests, 1, "reset cannot trigger further old-account logins")
	app._finish_unavailable_account_reset()
	check_eq(app.restarts, 1, "successful cleanup restarts the game")
	check(app.user_state.is_empty(), "old in-memory profile is removed")
	check(app.game_sync_client == null and app.online_client == null and app.matchmaking_client == null, "old transports are stopped before registration")
	check(not UsersStateStore.has_accepted_account(ACCOUNT_PATH), "restart enters the Terms/new-account gate")
	check(UsersStateStore.pending_achievement_ids(ACCOUNT_PATH).is_empty(), "old unlocks cannot be submitted as the new account")
	for filename: String in ["match_save.json", "match_fixture.json", "game_sync_state.json", "online_%s.txt" % "account-one".sha256_text()]:
		check(not FileAccess.file_exists(ACCOUNT_DIRECTORY.path_join(filename)), "old account data removed: " + filename)
	settings.clear()
	settings.load(ACCOUNT_DIRECTORY.path_join("settings.cfg"))
	check_eq(settings.get_value("network", "server_ip"), "192.0.2.25", "new registration uses the configured server")
	check(not settings.has_section("profile"), "profile settings are removed")
	# Simulate a late successful profile response after teardown.
	var request := HTTPRequest.new()
	app.add_child(request)
	app._on_current_user_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"id":"old","displayName":"Old"}'.to_utf8_buffer(), request, "expired-token")
	check(not FileAccess.file_exists(ACCOUNT_PATH), "late profile responses cannot recreate the old account")
	_dispose(app)


func test_cleanup_failure_keeps_credentials_until_cleanup_can_be_retried() -> void:
	var app := _app()
	var blocked_path: String = ACCOUNT_DIRECTORY.path_join("online_%s.txt" % "account-one".sha256_text())
	# A directory occupying a known file path is a cleanup error, not permission
	# to recursively erase arbitrary contents.
	DirAccess.make_dir_recursive_absolute(blocked_path)
	var child := FileAccess.open(blocked_path.path_join("blocker"), FileAccess.WRITE)
	child.store_string("fixture")
	child.close()
	app._refresh_api_login()
	app.complete(401, {})
	app._finish_unavailable_account_reset()
	check_eq(app.restarts, 0, "failed cleanup cannot restart with stale data")
	check(app.error_shown, "cleanup failure offers a retry")
	check(UsersStateStore.has_accepted_account(ACCOUNT_PATH), "credentials are removed only after other data is cleaned")
	DirAccess.remove_absolute(blocked_path.path_join("blocker"))
	DirAccess.remove_absolute(blocked_path)
	app._retry_api_login()
	check_eq(app.restarts, 1, "retry finishes cleanup and restarts setup")
	check_eq(app.login_requests, 1, "cleanup retry never logs into the unavailable account")
	_dispose(app)


func test_network_and_unusable_login_responses_have_recoverable_errors() -> void:
	for code: int in [0, 403, 404, 429, 500, 200]:
		var app := _app()
		app._refresh_api_login()
		app.complete(code, {}, HTTPRequest.RESULT_CANT_CONNECT if code == 0 else HTTPRequest.RESULT_SUCCESS)
		check(not app._login_active, "failed response releases waiting state")
		check(app.error_shown, "network, server and missing-token failures offer retry")
		check(not app._account_reset_pending, "an ambiguous failure is not evidence of a deleted account")
		check(UsersStateStore.has_accepted_account(ACCOUNT_PATH), "transient/unusable responses retain saved credentials")
		_dispose(app)
	var app := _app()
	app.start_error = ERR_CANT_CONNECT
	app._refresh_api_login()
	check(not app._login_active, "request startup failure releases waiting state")
	check(app.error_shown, "request startup failure offers retry")
	_dispose(app)


func test_online_401_requests_authentication_once_and_preserves_command() -> void:
	var client := OnlineGameApiClient.new()
	client.set_credentials("expired-token", "test-account")
	client._wanted = true
	client._pending = {"commandId": "same-command"}
	var request := HTTPRequest.new()
	client.add_child(request)
	client._request = request
	var refreshes: Array[int] = []
	client.authentication_required.connect(func() -> void: refreshes.append(1))
	client._completed(HTTPRequest.RESULT_SUCCESS, 401, PackedStringArray(), PackedByteArray(), request, "command")
	client._process(120.0)
	check_eq(refreshes.size(), 1, "401 waits for the shell to resolve authentication")
	check(not client.connected, "unauthorized online play cannot submit moves")
	check_eq(client._pending.get("commandId"), "same-command", "retry retains the command identity")
	client.set_credentials("new-token", "test-account")
	check(not client._authentication_pending, "fresh credentials release authentication wait")
	client.free()


func test_sync_and_preview_401_accept_non_json_error_bodies() -> void:
	for kind: String in ["turn", "preview", "delete"]:
		var client := GameSyncApiClient.new()
		client.access_token = "expired-token"
		var request := HTTPRequest.new()
		client.add_child(request)
		client._active_request = request
		var refreshes: Array[int] = []
		client.authentication_required.connect(func() -> void: refreshes.append(1))
		client._on_request_completed(HTTPRequest.RESULT_SUCCESS, 401, PackedStringArray(), "Unauthorized".to_utf8_buffer(), request, kind, "test-match")
		check_eq(refreshes.size(), 1, "status alone triggers authentication for " + kind)
		check(client._active_request == null, "401 releases the active request for " + kind)
		check_eq(client.access_token, "", "401 discards rejected token for " + kind)
		client.free()
