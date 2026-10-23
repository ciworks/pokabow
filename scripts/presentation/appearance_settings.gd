extends Node
## Persists the app-wide appearance choice for the current device.

signal dark_mode_changed(enabled: bool)

const SETTINGS_PATH: String = "user://appearance.cfg"
const SECTION: String = "appearance"
const KEY_DARK_MODE: String = "dark_mode"

var dark_mode: bool = false


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		dark_mode = bool(config.get_value(SECTION, KEY_DARK_MODE, false))


func set_dark_mode(enabled: bool) -> void:
	if dark_mode == enabled:
		return
	dark_mode = enabled
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SECTION, KEY_DARK_MODE, enabled)
	var error: Error = config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save appearance preference: %s" % error_string(error))
	dark_mode_changed.emit(enabled)
