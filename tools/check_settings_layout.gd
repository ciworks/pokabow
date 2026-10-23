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
	var requests: Array[int] = []
	hub.delete_account_requested.connect(func() -> void: requests.append(1))
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
		hub.get_node("%DeleteAccountButton").pressed.emit()
		await process_frame
		verify(requests.is_empty(), "Opening confirmation sends no API request")
		verify(hub.get_node("%DeleteWarning").text.contains("irrevocably"), "Confirmation warns of irreversible deletion")
		hub.get_node("%CancelDeleteButton").pressed.emit()
		verify(requests.is_empty(), "Cancel sends no API request")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("SETTINGS_QA_DIR").path_join("settings-%dx%d.png" % [dimensions.x, dimensions.y]))
	hub.get_node("%DeleteAccountButton").pressed.emit()
	hub.get_node("%ConfirmDeleteButton").pressed.emit()
	hub.get_node("%ConfirmDeleteButton").pressed.emit()
	verify(requests.size() == 1, "Confirm sends exactly one request")
	hub.close_settings()
	verify(hub.is_settings_open(), "Busy deletion cannot be dismissed")
	hub.show_deletion_result(false, "Server unavailable")
	verify(not hub.get_node("%ConfirmDeleteButton").disabled, "Failure allows retry")
	hub.show_deletion_result(false, "Retry cleanup", true)
	verify(not hub.get_node("%CancelDeleteButton").visible, "Remote success cannot return to a deleted account")
	hub.show_deletion_result(true, "Account deleted successfully", true)
	verify(hub.get_node("%ConfirmDeleteButton").text == "Continue", "Success is acknowledged explicitly")
	print("Settings layout and confirmation checks: ", "PASS" if failures.is_empty() else failures)
	hub.free()
	quit(0 if failures.is_empty() else 1)
