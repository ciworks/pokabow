class_name BackgroundMusic
extends AudioStreamPlayer
## App-shell player: starts at the hub and continues across screen changes.

const THEME: AudioStreamMP3 = preload("res://assets/audio/pokabow_theme.mp3")


func _ready() -> void:
	var theme: AudioStreamMP3 = THEME.duplicate() as AudioStreamMP3
	theme.loop = true
	stream = theme
	set_level(MusicPreferences.volume())


func start_music() -> void:
	if not playing:
		play()


func set_level(level: float) -> void:
	volume_db = linear_to_db(clampf(level, 0.0, 1.0)) if level > 0.0 else -80.0
