class_name TutorialProgressStore
extends RefCounted
## Per-account local onboarding choice. No match or gameplay state is stored here.

const DIRECTORY: String = "user://"
const PREFIX: String = "tutorial_"
const SUFFIX: String = ".cfg"
const SECTION: String = "tutorial"
const KEY_STATUS: String = "status"
const STATUS_PENDING: String = "pending"
const STATUS_COMPLETE: String = "complete"
const STATUS_NEVER: String = "never"


static func path_for(account_id: String, directory: String = DIRECTORY) -> String:
	if account_id.is_empty():
		return ""
	return directory.path_join(PREFIX + account_id.sha256_text() + SUFFIX)


static func status(account_id: String, directory: String = DIRECTORY) -> String:
	var path: String = path_for(account_id, directory)
	if path.is_empty():
		return ""
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return ""
	return String(config.get_value(SECTION, KEY_STATUS, ""))


static func should_show(account_id: String, directory: String = DIRECTORY) -> bool:
	return status(account_id, directory) == STATUS_PENDING


static func mark_eligible(account_id: String, directory: String = DIRECTORY) -> bool:
	if account_id.is_empty():
		return false
	if not status(account_id, directory).is_empty():
		return true
	return _save_status(account_id, STATUS_PENDING, directory)


static func finish(account_id: String, never_again: bool, directory: String = DIRECTORY) -> bool:
	return _save_status(account_id, STATUS_NEVER if never_again else STATUS_COMPLETE, directory)


static func _save_status(account_id: String, value: String, directory: String) -> bool:
	var path: String = path_for(account_id, directory)
	if path.is_empty():
		return false
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY_STATUS, value)
	return config.save(path) == OK
