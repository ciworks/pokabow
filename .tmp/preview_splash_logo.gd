extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var splash: Control = load("res://scenes/splash/splash_screen.tscn").instantiate()
	root.add_child(splash)
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(540, 960), Vector2i(1280, 720)]:
		root.size = dimensions
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var logo: TextureRect = splash.get_node("CenterContainer/TitleBlock/Logo")
		print("SPLASH ", dimensions, " viewport=", splash.get_global_rect(), " logo=", logo.get_global_rect())
		if not splash.get_global_rect().encloses(logo.get_global_rect()):
			push_error("Logo outside splash bounds")
			quit(1)
			return
		root.get_texture().get_image().save_png("res://.tmp/splash-logo-%dx%d.png" % [dimensions.x, dimensions.y])
	splash.queue_free()
	await process_frame
	quit()
