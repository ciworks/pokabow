class_name MusicPreferences
extends RefCounted
## Device-wide background music level, independent of the Sound mute switch.

const SETTINGS_PATH: String = "user://music.cfg"
const DEFAULT_VOLUME: float = 0.5


static func volume() -> float:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return DEFAULT_VOLUME
	return clampf(float(config.get_value("music", "volume", DEFAULT_VOLUME)), 0.0, 1.0)


static func set_volume(level: float) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("music", "volume", clampf(level, 0.0, 1.0))
	var error: Error = config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save music preference: %s" % error_string(error))
