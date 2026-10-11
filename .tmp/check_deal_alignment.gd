extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(540, 960)
	ProjectSettings.set_setting("accessibility/reduced_motion", false)
	var suite = load("res://tests/integration/test_game_screen.gd").new()
	var screen: GameScreen = suite._host_screen()
	for frame: int in range(5):
		await process_frame
		await RenderingServer.frame_post_draw
		var layer: DealLayer = screen.deal_layer
		if not layer._to.is_empty():
			print("FRAME ", frame, " origin delta=", (layer.get_global_transform() * layer._from).distance_to(screen.tile_pile_view.stack_origin_global()),
				" target delta=", (layer.get_global_transform() * layer._to[0]).position.distance_to(screen.deck_view.tile_global_rect(0).position))
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.tmp/deal-alignment.png")
	suite._release(screen)
	quit()
