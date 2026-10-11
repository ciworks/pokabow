extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i.ZERO
	var hub: HubScreen = load("res://scenes/hub/hub_screen.tscn").instantiate()
	root.add_child(hub)
	var failures: PackedStringArray = []
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(540, 960), Vector2i(844, 390), Vector2i(1280, 720)]:
		root.size = dimensions
		await create_timer(0.2).timeout
		var previous_end: float = 0.0
		for node_name: String in ["AchievementsButton", "ProfileButton", "ShopButton"]:
			var button: Button = hub.get_node("%" + node_name)
			var rect: Rect2 = button.get_global_rect()
			var font: Font = button.get_theme_font("font")
			var label_width: float = font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
			var style: StyleBox = button.get_theme_stylebox("normal")
			if rect.position.x < previous_end or rect.end.x > dimensions.x or rect.size.y < 44:
				failures.append("%s at %s does not fit: %s" % [node_name, dimensions, rect])
			if label_width + style.get_minimum_size().x > rect.size.x:
				failures.append("%s at %s clips its label" % [node_name, dimensions])
			previous_end = rect.end.x
			print(dimensions, " ", node_name, " ", rect, " font=", button.get_theme_font_size("font_size"))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp/hub-buttons-%dx%d.png" % [dimensions.x, dimensions.y])
	var profile_requests: Array[int] = []
	var achievement_requests: Array[int] = []
	hub.profile_requested.connect(func() -> void: profile_requests.append(1))
	hub.achievements_requested.connect(func() -> void: achievement_requests.append(1))
	(hub.get_node("%ProfileButton") as Button).pressed.emit()
	(hub.get_node("%AchievementsButton") as Button).pressed.emit()
	(hub.get_node("%ShopButton") as Button).pressed.emit()
	if profile_requests.size() != 1 or achievement_requests.size() != 1 or not hub._notice.visible:
		failures.append("destination actions were not preserved")
	print("HUB BUTTON CHECK: ", "PASS" if failures.is_empty() else failures)
	hub.free()
	quit(0 if failures.is_empty() else 1)
