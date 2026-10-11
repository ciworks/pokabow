extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(540, 960)
	var suite = load("res://tests/integration/test_game_screen.gd").new()
	var screen: GameScreen = suite._host_screen()
	await create_timer(2.0).timeout
	var row: DeckView = screen.deck_view
	row.set_concealed([])
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = row.tile_rect_at(0).get_center()
	row._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	var target: Vector2 = BoardMetrics.cell_center(screen.board_view.global_board_rect(), Vector2i(5, 5)) + Vector2(25, -18)
	motion.position = row.get_global_transform().affine_inverse() * target
	row._gui_input(motion)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.tmp/smooth-drag-preview.png")
	print("Drag preview captured: ", screen.board_view.get_drop_cell())
	suite._release(screen)
	quit()
