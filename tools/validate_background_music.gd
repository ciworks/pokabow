extends Node


func _ready() -> void:
	var original_level: float = MusicPreferences.volume()
	var player := BackgroundMusic.new()
	add_child(player)
	assert(player.stream is AudioStreamMP3)
	assert((player.stream as AudioStreamMP3).loop)
	assert(not player.playing)
	player.start_music()
	assert(player.playing)
	var playback_position: float = player.get_playback_position()
	player.start_music()
	assert(player.playing and player.get_playback_position() >= playback_position)

	var hub: HubScreen = load("res://scenes/hub/hub_screen.tscn").instantiate()
	add_child(hub)
	hub.music_volume_changed.connect(player.set_level)
	var slider: HSlider = hub.get_node("%MusicVolumeSlider") as HSlider
	slider.value = 25.0
	assert(is_equal_approx(MusicPreferences.volume(), 0.25))
	assert((hub.get_node("%MusicVolumeValue") as Label).text == "25%")
	assert(is_equal_approx(player.volume_db, linear_to_db(0.25)))
	MusicPreferences.set_volume(original_level)
	print("[background music] looping playback, volume control and persistence passed")
	get_tree().quit()
