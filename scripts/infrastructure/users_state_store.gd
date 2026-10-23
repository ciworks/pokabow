class_name UsersStateStore
extends RefCounted
## Local account record for the Terms of Use gate.
##
## This is not match state and must not live in an autoload (ADR-008 section 6).
## Callers own the store and pass a path, so tests can point it at a temporary
## file under user:// without touching the player's record.
##
## Registration saves the accepted account and credentials. A successful login
## adds user_state so a later launch can restore the API user directly.

const DEFAULT_PATH: String = "user://users_state.json"
const SCHEMA_VERSION: int = 1

const KEY_VERSION: String = "version"
const KEY_TERMS_AGREED: String = "terms_agreed"
const KEY_USERNAME: String = "username"
const KEY_PASSWORD: String = "password"
const KEY_EMAIL: String = "email"
const KEY_USER_STATE: String = "user_state"
const KEY_PENDING_ACHIEVEMENTS: String = "pending_achievements"
const KEY_PENDING_ACHIEVEMENT_PROGRESS: String = "pending_achievement_progress"
const KEY_ANNOUNCED_ACHIEVEMENTS: String = "announced_achievements"
const KEY_ACHIEVEMENT_CATALOG: String = "achievement_catalog"


static func load_record(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


static func has_accepted_account(path: String = DEFAULT_PATH) -> bool:
	var record: Dictionary = load_record(path)
	if int(record.get(KEY_VERSION, 0)) != SCHEMA_VERSION:
		return false
	if not bool(record.get(KEY_TERMS_AGREED, false)):
		return false
	return (
		not String(record.get(KEY_USERNAME, "")).is_empty()
		and not String(record.get(KEY_PASSWORD, "")).is_empty()
	)


## A login response is usable only when it supplies a token. Keep the complete
## response too, so later API fields remain available to the current user.
static func user_state_from_response(response: Dictionary) -> Dictionary:
	var token: String = String(response.get("token", response.get("access_token", "")))
	if token.is_empty():
		return {}
	var user: Variant = response.get("user", {})
	var user_details: Dictionary = {}
	if typeof(user) == TYPE_DICTIONARY:
		user_details = (user as Dictionary).duplicate(true)
	if user_details.is_empty():
		user_details = response.duplicate(true)
		user_details.erase("token")
		user_details.erase("access_token")
	return {
		"token": token,
		"user": user_details,
		"response": response.duplicate(true),
	}


static func load_user_state(path: String = DEFAULT_PATH) -> Dictionary:
	var state: Variant = load_record(path).get(KEY_USER_STATE, {})
	if typeof(state) != TYPE_DICTIONARY:
		return {}
	var user_state: Dictionary = state
	if String(user_state.get("token", "")).is_empty():
		return {}
	return user_state.duplicate(true)


static func has_user_state(path: String = DEFAULT_PATH) -> bool:
	return not load_user_state(path).is_empty()


static func save_user_state(response: Dictionary, path: String = DEFAULT_PATH) -> bool:
	if not has_accepted_account(path):
		return false
	var state: Dictionary = user_state_from_response(response)
	if state.is_empty():
		return false
	var record: Dictionary = load_record(path)
	record[KEY_USER_STATE] = state
	return save_record(record, path)


## Discard only the rejected session; keep credentials and queued unlocks.
static func clear_user_state(path: String = DEFAULT_PATH) -> bool:
	var record: Dictionary = load_record(path)
	if not record.has(KEY_USER_STATE):
		return true
	record.erase(KEY_USER_STATE)
	return save_record(record, path)


static func pending_achievement_ids(path: String = DEFAULT_PATH) -> Array[String]:
	var raw: Variant = load_record(path).get(KEY_PENDING_ACHIEVEMENTS, [])
	var ids: Array[String] = []
	if raw is Array:
		for value: Variant in raw:
			var id: String = str(value).strip_edges() if value is String or value is StringName else ""
			if not id.is_empty() and not ids.has(id):
				ids.append(id)
	return ids


static func queue_achievement_ids(ids: Array[String], path: String = DEFAULT_PATH) -> bool:
	var record: Dictionary = load_record(path)
	var pending: Array[String] = pending_achievement_ids(path)
	for id: String in ids:
		if not id.is_empty() and not pending.has(id):
			pending.append(id)
	record[KEY_PENDING_ACHIEVEMENTS] = pending
	return save_record(record, path)


static func clear_achievement_ids(ids: Array[String], path: String = DEFAULT_PATH) -> bool:
	var record: Dictionary = load_record(path)
	var pending: Array[String] = pending_achievement_ids(path)
	for id: String in ids:
		pending.erase(id)
	if pending.is_empty():
		record.erase(KEY_PENDING_ACHIEVEMENTS)
	else:
		record[KEY_PENDING_ACHIEVEMENTS] = pending
	return save_record(record, path)


static func pending_achievement_progress(path: String = DEFAULT_PATH) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	var raw: Variant = load_record(path).get(KEY_PENDING_ACHIEVEMENT_PROGRESS, [])
	if raw is Array:
		for value: Variant in raw:
			if value is Dictionary and not str(value.get("eventId", "")).is_empty():
				values.append((value as Dictionary).duplicate(true))
	return values


static func queue_achievement_progress(events: Array[Dictionary], path: String = DEFAULT_PATH) -> bool:
	var record: Dictionary = load_record(path)
	var pending: Array[Dictionary] = pending_achievement_progress(path)
	var ids: Dictionary = {}
	for event: Dictionary in pending:
		ids[str(event.get("eventId", ""))] = true
	for event: Dictionary in events:
		var id: String = str(event.get("eventId", ""))
		if id.is_empty() or ids.has(id):
			continue
		var queued: Dictionary = event.duplicate(true)
		queued["submitted"] = false
		pending.append(queued)
		ids[id] = true
	record[KEY_PENDING_ACHIEVEMENT_PROGRESS] = pending
	return save_record(record, path)


static func mark_achievement_progress_submitted(ids: Array[String], path: String = DEFAULT_PATH) -> bool:
	var record: Dictionary = load_record(path)
	var pending: Array[Dictionary] = pending_achievement_progress(path)
	for event: Dictionary in pending:
		if ids.has(str(event.get("eventId", ""))):
			event["submitted"] = true
	record[KEY_PENDING_ACHIEVEMENT_PROGRESS] = pending
	return save_record(record, path)


static func clear_achievement_progress(ids: Array[String], path: String = DEFAULT_PATH) -> bool:
	var record: Dictionary = load_record(path)
	var pending: Array[Dictionary] = pending_achievement_progress(path)
	pending = pending.filter(func(event: Dictionary) -> bool:
		return not ids.has(str(event.get("eventId", "")))
	)
	if pending.is_empty():
		record.erase(KEY_PENDING_ACHIEVEMENT_PROGRESS)
	else:
		record[KEY_PENDING_ACHIEVEMENT_PROGRESS] = pending
	return save_record(record, path)


static func achievement_catalog(path: String = DEFAULT_PATH) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	var raw: Variant = load_record(path).get(KEY_ACHIEVEMENT_CATALOG, [])
	if raw is Array:
		for value: Variant in raw:
			if value is Dictionary:
				values.append((value as Dictionary).duplicate(true))
	return values


static func save_achievement_catalog(rows: Array[Dictionary], path: String = DEFAULT_PATH) -> bool:
	var record: Dictionary = load_record(path)
	record[KEY_ACHIEVEMENT_CATALOG] = rows.duplicate(true)
	return save_record(record, path)


static func achievement_was_announced(id: String, path: String = DEFAULT_PATH) -> bool:
	var raw: Variant = load_record(path).get(KEY_ANNOUNCED_ACHIEVEMENTS, [])
	return raw is Array and raw.has(id)


static func mark_achievement_announced(id: String, path: String = DEFAULT_PATH) -> bool:
	var record: Dictionary = load_record(path)
	var raw: Variant = record.get(KEY_ANNOUNCED_ACHIEVEMENTS, [])
	var ids: Array = raw if raw is Array else []
	if not ids.has(id):
		ids.append(id)
	record[KEY_ANNOUNCED_ACHIEVEMENTS] = ids
	return save_record(record, path)


static func save_accepted_account(
	username: String,
	password: String,
	email: String,
	path: String = DEFAULT_PATH
) -> bool:
	var payload: Dictionary = {
		KEY_VERSION: SCHEMA_VERSION,
		KEY_TERMS_AGREED: true,
		KEY_USERNAME: username,
		KEY_PASSWORD: password,
		KEY_EMAIL: email,
	}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


## Writes an already-built record. Used when a later login response is stored
## beside the accepted account. Callers that only just accepted should use
## `save_accepted_account` so the terms flag cannot be dropped.
static func save_record(record: Dictionary, path: String = DEFAULT_PATH) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	return true


## Explicit allowlist: never remove unrelated files in the user's directory.
## Account credentials are removed last so a failed cleanup can be retried.
static func clear_local_state(
	directory: String = "user://", account_id: String = "", preserve_server_ip: bool = false
) -> bool:
	var settings_path: String = directory.path_join("settings.cfg")
	var server_ip: String = ""
	if preserve_server_ip:
		var settings := ConfigFile.new()
		if settings.load(settings_path) == OK:
			server_ip = String(settings.get_value("network", "server_ip", ""))
		if not server_ip.is_valid_ip_address():
			server_ip = ""
	var filenames: PackedStringArray = [
		"match_save.json", "match_fixture.json", "game_sync_state.json", "settings.cfg",
	]
	for filename: String in DirAccess.get_files_at(directory):
		if filename.begins_with("active_match_") and filename.ends_with(".json"):
			filenames.append(filename)
	if not account_id.is_empty():
		var account_hash: String = account_id.sha256_text()
		filenames.append("online_%s.txt" % account_hash)
		filenames.append("match_history_%s.json" % account_hash)
		for filename: String in DirAccess.get_files_at(directory):
			if filename.begins_with("history_avatar_%s_" % account_hash) and filename.ends_with(".png"):
				filenames.append(filename)
	else:
		# An earlier expired-session cleanup may already have removed the cached
		# account ID. Only recognize files created by OnlineGameApiClient.
		for filename: String in DirAccess.get_files_at(directory):
			if filename.begins_with("online_") and filename.ends_with(".txt"):
				var account_hash: String = filename.substr(7, filename.length() - 11)
				if account_hash.length() == 64 and account_hash.is_valid_hex_number(false):
					filenames.append(filename)
	filenames.append("users_state.json")
	for filename: String in filenames:
		var path: String = directory.path_join(filename)
		if DirAccess.dir_exists_absolute(path):
			return false
		if filename == "settings.cfg" and not server_ip.is_empty():
			var network_settings := ConfigFile.new()
			network_settings.set_value("network", "server_ip", server_ip)
			if network_settings.save(path) != OK:
				return false
			continue
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
			return false
	return true
