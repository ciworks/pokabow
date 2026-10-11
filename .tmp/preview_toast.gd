extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	root.add_child(screen)
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(540, 960), Vector2i(1280, 720)]:
		root.size = dimensions
		screen._show_toast("Time up, play moves to other player")
		await create_timer(0.4).timeout
		var banner: Rect2 = screen._toast_panel.get_global_rect()
		var viewport: Rect2 = screen.get_global_rect()
		assert(is_equal_approx(banner.size.x, viewport.size.x), "Toast must fill viewport width")
		assert(banner.get_center().is_equal_approx(viewport.get_center()), "Toast must be centered")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp/toast-%dx%d.png" % [dimensions.x, dimensions.y])
		print("TOAST CHECK ", dimensions, " banner=", banner, " viewport=", viewport)
	# Exercise wrapping, replacement during display, and automatic dismissal.
	screen._show_toast("The opening hand needs at least two tiles. A line goes in one row or one column. The opening hand needs at least two tiles.")
	await create_timer(0.4).timeout
	assert(screen._toast_panel.get_global_rect().get_center().distance_to(screen.get_global_rect().get_center()) <= 1.0)
	assert(screen._toast_panel.size.y >= screen._toast_label.get_minimum_size().y + 36.0)
	screen._show_toast("A line goes in one row or one column")
	await create_timer(0.4).timeout
	assert(screen._toast_panel.visible)
	assert(is_equal_approx(screen._toast_panel.modulate.a, 1.0))
	await create_timer(4.3).timeout
	assert(not screen._toast_panel.visible)
	print("TOAST CHECK PASS: width, center, wrapping, replacement, dismissal")
	screen.queue_free()
	await process_frame
	quit()
