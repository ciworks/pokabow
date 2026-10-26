extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func verify(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i.ZERO
	var hub: HubScreen = load("res://scenes/hub/hub_screen.tscn").instantiate()
	root.add_child(hub)
	await process_frame
	hub.open_settings()
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(540, 960), Vector2i(1280, 720), Vector2i(800, 360)]:
		root.size = dimensions
		await create_timer(0.15).timeout
		var panel: Control = hub.get_node("%SettingsPanel")
		var close: Control = hub.get_node("%SettingsCloseButton")
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(dimensions))
		verify(viewport_rect.encloses(panel.get_global_rect()), "Panel fits " + str(dimensions))
		verify(viewport_rect.encloses(close.get_global_rect()), "Close remains visible " + str(dimensions))
		verify(panel.size.x <= dimensions.x - 30, "Panel has horizontal margins " + str(dimensions))
		var toggle: Control = hub.get_node("%ReducedMotionToggle")
		verify(toggle.get_global_rect().end.x <= panel.get_global_rect().end.x - 10, "Toggle fits horizontally " + str(dimensions))
		verify(hub.get_node_or_null("%DeleteAccountButton") == null,
			"Settings has no account deletion action")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("SETTINGS_QA_DIR").path_join("settings-%dx%d.png" % [dimensions.x, dimensions.y]))
	hub.close_settings()
	verify(not hub.is_settings_open(), "Settings closes normally")
	print("Settings layout and confirmation checks: ", "PASS" if failures.is_empty() else failures)
	hub.free()
	quit(0 if failures.is_empty() else 1)
