class_name UsersStateStore
extends RefCounted
## Local account record for the Terms of Use gate.
##
## This is not match state and must not live in an autoload (ADR-008 section 6).
## Callers own the store and pass a path, so tests can point it at a temporary
## file under user:// without touching the player's record.
##
## The file is written only after a successful register response. A later launch
## treats "terms agreed" plus a username and password as enough to log in again.

const DEFAULT_PATH: String = "user://users_state.json"
const SCHEMA_VERSION: int = 1

const KEY_VERSION: String = "version"
const KEY_TERMS_AGREED: String = "terms_agreed"
const KEY_USERNAME: String = "username"
const KEY_PASSWORD: String = "password"
const KEY_EMAIL: String = "email"


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
