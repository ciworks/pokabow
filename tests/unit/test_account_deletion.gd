extends "res://tests/harness/test_case.gd"

class FakeDeletionClient extends AccountDeletionClient:
	var sent: Array[Dictionary] = []
	func _send(path: String, method: int, payload: Dictionary, token: String, login: bool) -> void:
		sent.append({"path": path, "method": method, "payload": payload, "token": token, "login": login})
	func respond(code: int, payload: Variant, login: bool = false, result: int = HTTPRequest.RESULT_SUCCESS) -> void:
		_on_response(result, code, PackedStringArray(), JSON.stringify(payload).to_utf8_buffer(), login)


func test_delete_sends_confirmed_authenticated_request_and_blocks_duplicates() -> void:
	var client := FakeDeletionClient.new()
	var results: Array[bool] = []
	client.completed.connect(func(ok: bool, _message: String) -> void: results.append(ok))
	client.delete_account("token", {"password": "secret"})
	client.delete_account("token", {})
	check_eq(client.sent.size(), 1, "double tapping cannot send two deletions")
	check_eq(client.sent[0].path, "/auth/me", "only the current account is targeted")
	check_eq(client.sent[0].method, HTTPClient.METHOD_DELETE, "deletion uses DELETE")
	check_eq(client.sent[0].token, "token", "request carries authentication")
	check_eq(client.sent[0].payload, {"confirm": true}, "confirmation is sent to the API")
	client.respond(200, {"success": true})
	check_eq(results, [true], "server success is reported")
	check(client._credentials.is_empty(), "credentials are released after completion")
	client.free()


func test_failure_and_ambiguous_success_never_report_deletion() -> void:
	for code: int in [200, 400, 403, 404, 500]:
		var client := FakeDeletionClient.new()
		var results: Array[bool] = []
		client.completed.connect(func(ok: bool, _message: String) -> void: results.append(ok))
		client.delete_account("token", {})
		client.respond(code, {})
		check_eq(results, [false], "HTTP %d without confirmed success preserves local state" % code)
		client.free()
	var offline := FakeDeletionClient.new()
	var results: Array[bool] = []
	offline.completed.connect(func(ok: bool, _message: String) -> void: results.append(ok))
	offline.delete_account("token", {})
	offline.respond(0, null, false, HTTPRequest.RESULT_TIMEOUT)
	check_eq(results, [false], "timeout is not success")
	offline.free()


func test_expired_token_refreshes_once_then_retries_delete() -> void:
	var client := FakeDeletionClient.new()
	var results: Array[bool] = []
	client.completed.connect(func(ok: bool, _message: String) -> void: results.append(ok))
	client.delete_account("expired", {"email": "test@example.com", "password": "secret"})
	client.respond(401, {})
	check_eq(client.sent.back().path, "/auth/login", "401 refreshes credentials")
	client.respond(200, {"token": "fresh"}, true)
	check_eq(client.sent.back().token, "fresh", "retry uses the refreshed token")
	client.respond(401, {})
	check_eq(results, [false], "a second 401 fails without an infinite loop")
	check_eq(client.sent.size(), 3, "only one login retry is allowed")
	client.free()


func test_local_cleanup_removes_account_match_and_settings_but_preserves_unrelated_files() -> void:
	var directory := "user://account_deletion_fixture"
	DirAccess.make_dir_recursive_absolute(directory)
	var names: PackedStringArray = ["users_state.json", "match_save.json", "active_match_fixture.json", "match_fixture.json", "game_sync_state.json", "settings.cfg", "unrelated.txt"]
	for filename: String in names:
		var file := FileAccess.open(directory.path_join(filename), FileAccess.WRITE)
		file.store_string("fixture")
		file.close()
	check(UsersStateStore.clear_local_state(directory), "cleanup succeeds")
	for filename: String in names:
		check_eq(FileAccess.file_exists(directory.path_join(filename)), filename == "unrelated.txt", "cleanup scope: " + filename)
	check(UsersStateStore.clear_local_state(directory), "cleanup is idempotent")
	DirAccess.remove_absolute(directory.path_join("unrelated.txt"))
	DirAccess.remove_absolute(directory)


func test_cleanup_removes_orphaned_resume_when_cached_account_id_is_missing() -> void:
	var directory := "user://account_resume_cleanup_fixture"
	DirAccess.make_dir_recursive_absolute(directory)
	var resume_name: String = "online_%s.txt" % "old-account".sha256_text()
	for filename: String in [resume_name, "online_notes.txt"]:
		var file := FileAccess.open(directory.path_join(filename), FileAccess.WRITE)
		file.store_string("fixture")
		file.close()
	check(UsersStateStore.clear_local_state(directory), "cleanup succeeds without a cached account ID")
	check(not FileAccess.file_exists(directory.path_join(resume_name)), "the old match cannot return under a new account")
	check(FileAccess.file_exists(directory.path_join("online_notes.txt")), "unrelated files are retained")
	DirAccess.remove_absolute(directory.path_join("online_notes.txt"))
	DirAccess.remove_absolute(directory)
