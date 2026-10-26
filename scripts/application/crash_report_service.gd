class_name CrashReportService
extends Node
## Keeps a small, local report when the previous foreground session ended unexpectedly.
## Godot writes the engine log; this service only reads its previous-session tail.

const SUPPORT_ADDRESS := "support@pokabow.game"
const MAX_LOG_BYTES := 5000
const MARKER_PATH := "user://crash-report-session.json"
const PENDING_PATH := "user://pending-crash-report.json"
const LOG_DIRECTORY := "user://logs"

var marker_path: String = MARKER_PATH
var pending_path: String = PENDING_PATH
var log_directory: String = LOG_DIRECTORY
var _started: bool = false
var _pending: Dictionary = {}


func begin_session() -> void:
	if _started:
		return
	_pending = _read_json(pending_path)
	var previous := _read_json(marker_path)
	if _pending.is_empty() and String(previous.get("state", "")) == "active":
		_pending = {
			"endedAt": String(previous.get("startedAt", "")),
			"log": _read_log_tail(true),
		}
		_write_json(pending_path, _pending)
	_started = true
	_write_state("active")


func has_pending_report() -> bool:
	return not _pending.is_empty()


func pending_report() -> Dictionary:
	return _pending.duplicate(true)


func current_log_excerpt() -> String:
	return _read_log_tail(false)


func dismiss_pending_report() -> void:
	_pending.clear()
	if FileAccess.file_exists(pending_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending_path))


func _notification(what: int) -> void:
	if not _started:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_write_state("background")
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_write_state("active")
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_write_state("closed")


func _exit_tree() -> void:
	if _started:
		_write_state("closed")


func _write_state(state: String) -> void:
	_write_json(marker_path, {
		"state": state,
		"startedAt": Time.get_datetime_string_from_system(true),
	})


func _read_log_tail(previous_session: bool) -> String:
	var path := log_directory.path_join("godot.log")
	if previous_session:
		path = ""
		var newest: int = -1
		for filename: String in DirAccess.get_files_at(log_directory):
			if not filename.ends_with(".log") or filename == "godot.log":
				continue
			var candidate := log_directory.path_join(filename)
			var modified := FileAccess.get_modified_time(candidate)
			if modified > newest:
				newest = modified
				path = candidate
	if path.is_empty() or not FileAccess.file_exists(path):
		return "No engine log was available for this session."
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "The engine log could not be read."
	var length := file.get_length()
	file.seek(maxi(0, length - MAX_LOG_BYTES))
	var excerpt := file.get_buffer(mini(length, MAX_LOG_BYTES)).get_string_from_utf8()
	file.close()
	return sanitize_log(excerpt.strip_edges()) if not excerpt.is_empty() else "The engine log is empty."


static func sanitize_log(raw: String) -> String:
	var result := raw
	for pattern: String in [
		"(?i)(Bearer\\s+)[A-Za-z0-9._~+/-]+",
		"(?i)(\\\"(?:password|token|access_token|refresh_token|authorization)\\\"\\s*:\\s*\\\")[^\\\"]*",
		"(?i)((?:password|token|access_token|refresh_token)=)[^\\s&]+",
	]:
		var expression := RegEx.new()
		if expression.compile(pattern) == OK:
			result = expression.sub(result, "$1[redacted]", true)
	return result


static func report_text(notes: String, log_excerpt: String) -> String:
	var description := notes.strip_edges()
	var details := [
		"Pokabow problem report",
		"App version: %s" % ProjectSettings.get_setting("application/config/version", "unknown"),
		"Godot version: %s" % Engine.get_version_info().get("string", "unknown"),
		"Platform: %s" % OS.get_name(),
		"Device OS: %s" % OS.get_version(),
		"Sent at: %s" % Time.get_datetime_string_from_system(true),
		"",
		"Player description:",
		description if not description.is_empty() else "No description supplied.",
		"",
		"Engine log excerpt (player reviewed):",
		log_excerpt.strip_edges(),
	]
	return "\n".join(details)


static func email_uri(report: String) -> String:
	return "mailto:%s?subject=%s&body=%s" % [
		SUPPORT_ADDRESS,
		"Pokabow crash report".uri_encode(),
		report.uri_encode(),
	]


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save crash report state: %s" % path)
		return
	file.store_string(JSON.stringify(data))
	file.close()
