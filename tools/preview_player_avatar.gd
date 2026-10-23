extends SceneTree
## Render the selector without reading or changing the real account.


func _initialize() -> void:
	call_deferred("_preview")


func _preview() -> void:
	root.content_scale_size = Vector2i(540, 960)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = Vector2i(540, 960)
	var screen: ProfileScreen = load("res://scenes/profile/profile_screen.tscn").instantiate()
	screen.avatar_store_path = "user://avatar_preview_missing.json"
	root.add_child(screen)
	screen.set_user_state({"user": {"displayName": "Player", "username": "player", "email": "player@example.com"}})
	screen._cycle_avatar(1)
	for viewport_size: Vector2i in [Vector2i(540, 960), Vector2i(360, 800)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp/avatar-profile-%dx%d.png" % [viewport_size.x, viewport_size.y])
		print("Avatar render: %s; preview: %s" % [viewport_size, screen._avatar_preview.size])
	quit()
