extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var screen: Control = load("res://scenes/hub/hub_screen.tscn").instantiate()
	root.add_child(screen)
	var button: Button = screen.get_node("%SoundButton")
	var bus: int = AudioServer.get_bus_index("Master")
	var was_enabled: bool = not AudioServer.is_bus_mute(bus)
	button.pressed.emit()
	if AudioServer.is_bus_mute(bus) != was_enabled:
		push_error("Sound button did not toggle the audio bus")
		quit(1)
		return
	button.pressed.emit()
	if AudioServer.is_bus_mute(bus) == was_enabled:
		push_error("Sound button did not restore the audio bus")
		quit(1)
		return
	print("SOUND TOGGLE: passed")
	await create_timer(3.0).timeout
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(540, 960)]:
		root.size = dimensions
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp/hub-sound-%dx%d.png" % [dimensions.x, dimensions.y])
		print("HUB SOUND ", dimensions, " button=", button.get_global_rect(), " texture=", button.icon.get_size())
	screen.queue_free()
	await process_frame
	quit()
