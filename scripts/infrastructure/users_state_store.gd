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


static func pending_achievement_ids(path: String = DEFAULT_PATH) -> Array[String]:
	var raw: Variant = load_record(path).get(KEY_PENDING_ACHIEVEMENTS, [])
	var ids: Array[String] = []
	if raw is Array:
		for value: Variant in raw:
			var id: String = String(value)
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
