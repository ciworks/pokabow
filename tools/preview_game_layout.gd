extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(540, 960)
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	root.add_child(screen)
	var controller := GameSessionController.new()
	controller.save_path = "user://layout_preview_only.json"
	screen.add_child(controller)
	screen.attach_controller(controller)
	controller.start_new_match(&"layout-preview", 4242)
	screen.set_player_display_name("You")
	var deck: Array[TileDefinition] = controller.human_deck()
	var staged: bool = false
	for a: int in range(deck.size()):
		for b: int in range(a + 1, deck.size()):
			if deck[a].rank == deck[b].rank:
				controller.stage_tile(deck[a].tile_id, Vector2i(5, 5))
				controller.stage_tile(deck[b].tile_id, Vector2i(6, 5))
				staged = true
				break
		if staged:
			break
	await create_timer(5.0).timeout
	for dimensions: Vector2i in [Vector2i(540, 960), Vector2i(360, 800), Vector2i(1280, 720)]:
		root.size = dimensions
		for opened: bool in [false, true]:
			screen.command_drawer.set_open(opened)
			await create_timer(0.4).timeout
			await RenderingServer.frame_post_draw
			var filename: String = "res://layout-%dx%d-%s.png" % [dimensions.x, dimensions.y, "open" if opened else "closed"]
			root.get_texture().get_image().save_png(filename)
			print(filename, " screen=", screen.size, " board=", screen.board_view.global_board_rect(), " deck=", screen.deck_view.get_global_rect(), " drawer=", screen.command_drawer.panel.get_global_rect())
	root.size = Vector2i(360, 800)
	await create_timer(0.2).timeout
	screen.command_drawer.set_open(true, false)
	var board_presses: Array[int] = []
	screen.board_input.cell_tapped.connect(func(_cell: Vector2i) -> void: board_presses.append(1))
	_click(screen.get_node("%CloseMenuButton").get_global_rect().get_center())
	await create_timer(0.3).timeout
	var close_works: bool = not screen.command_drawer.is_open
	_click((screen.get_node("%HeaderSpacer") as Button).get_global_rect().get_center())
	await create_timer(0.3).timeout
	var settings_works: bool = screen.command_drawer.is_open
	_click(Vector2(45, 310))
	await create_timer(0.3).timeout
	var outside_works: bool = not screen.command_drawer.is_open and board_presses.is_empty()
	print("POINTER CHECK: close=", close_works, " settings=", settings_works, " outside_consumed=", outside_works)
	screen.queue_free()
	await process_frame
	quit(0 if close_works and settings_works and outside_works else 1)

func _click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		root.push_input(event, true)
