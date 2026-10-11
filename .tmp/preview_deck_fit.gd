extends SceneTree
## Render the real game screen and check header/board bounds after resizing.

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(540, 960)
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	root.add_child(screen)
	var controller := GameSessionController.new()
	controller.save_path = "user://header_logo_preview_only.json"
	screen.add_child(controller)
	screen.attach_controller(controller)
	controller.start_new_match(&"header-logo-preview", 4242)
	await create_timer(2.0).timeout
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(540, 960), Vector2i(1280, 720), Vector2i(844, 390), Vector2i(540, 960)]:
		root.size = dimensions
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var logo: TextureRect = screen.get_node("Root/Column/HeaderTools/Brand")
		var menu: Button = screen.get_node("%OpenMenuButton")
		var viewport_rect := screen.get_global_rect()
		var logo_rect := logo.get_global_rect()
		var art_size := logo.texture.get_size()
		var art_scale: float = minf(logo_rect.size.x / art_size.x, logo_rect.size.y / art_size.y)
		var drawn_size := art_size * art_scale
		var drawn_rect := Rect2(logo_rect.get_center() - drawn_size * 0.5, drawn_size)
		_check(logo.is_visible_in_tree(), "logo visible", dimensions)
		_check(absf(drawn_rect.get_center().x - viewport_rect.get_center().x) < 1.0, "logo centered on screen", dimensions)
		_check(viewport_rect.encloses(drawn_rect), "logo fits screen", dimensions)
		_check(not drawn_rect.intersects(menu.get_global_rect()), "logo clears settings", dimensions)
		_check(logo.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "logo keeps aspect ratio", dimensions)
		for node_path: String in ["Root/Column/Hud", "Root/Column/DeckBar", "BottomNavigation"]:
			var control := screen.get_node(node_path) as Control
			_check(viewport_rect.grow(1.0).encloses(control.get_global_rect()), node_path + " fits screen", dimensions)
		_check(viewport_rect.grow(1.0).encloses(menu.get_global_rect()), "settings fits screen", dimensions)
		var board_rect := screen.board_view.global_visible_rect()
		_check(viewport_rect.encloses(board_rect), "board fits screen", dimensions)
		_check(absf(board_rect.size.x - board_rect.size.y) < 1.0, "board stays square", dimensions)
		var deck_tile := DeckView.tile_rect(0, 6, screen.deck_view.size)
		_check(deck_tile.size.x >= 16.0, "rack tiles remain visible", dimensions)
		var filename: String = "res://deck-fit-%dx%d.png" % [dimensions.x, dimensions.y]
		var tray: Rect2 = screen.deck_panel.get_global_rect()
		var frame: Rect2 = board_rect.grow(BoardView.PADDING)
		_check(absf(tray.size.x - frame.size.x) < 1.0, "tray matches board frame width", dimensions)
		_check(absf(tray.get_center().x - frame.get_center().x) < 1.0, "tray and board are centered together", dimensions)
		var tray_art: Vector2 = screen.deck_panel.texture.get_size()
		_check(absf(tray.size.x / tray.size.y - tray_art.x / tray_art.y) < 0.05, "tray preserves artwork proportions", dimensions)
		var recess: Rect2 = screen.deck_panel.get_node("RackColumn").get_global_rect()
		_check(tray.encloses(recess), "tile recess fits within tray", dimensions)
		_check(recess.grow(1.0).encloses(screen.deck_view.get_global_rect()), "tile row fits within recess", dimensions)
		for count: int in range(1, 7):
			var first: Rect2 = DeckView.tile_rect(0, count, screen.deck_view.size)
			var last: Rect2 = DeckView.tile_rect(count - 1, count, screen.deck_view.size)
			_check(first.size.is_equal_approx(deck_tile.size), "tile size preserved with %d tiles" % count, dimensions)
			_check(is_equal_approx(first.size.x, first.size.y), "tiles remain square", dimensions)
			_check(is_equal_approx(first.position.x, screen.deck_view.size.x - last.end.x), "equal left/right padding", dimensions)
			_check(is_equal_approx(first.position.y, screen.deck_view.size.y - first.end.y), "equal top/bottom padding", dimensions)
			for index: int in range(count):
				var tile: Rect2 = DeckView.tile_rect(index, count, screen.deck_view.size)
				_check(DeckView._index_at(tile.get_center(), count, screen.deck_view.size) == index, "tile hit testing matches layout", dimensions)
				if index > 0:
					var previous: Rect2 = DeckView.tile_rect(index - 1, count, screen.deck_view.size)
					_check(is_equal_approx(tile.position.x - previous.end.x, first.position.x), "equal horizontal gaps including edges", dimensions)
		print("DECK FIT: tray=", tray, " recess=", recess, " row=", screen.deck_view.get_global_rect(), " tile=", deck_tile)
		var saved: Error = root.get_texture().get_image().save_png(filename)
		_check(saved == OK, "screenshot saved", dimensions)
		print(filename, " logo=", drawn_rect, " board=", board_rect)
	# The centered artwork must not intercept the settings control.
	screen.command_drawer.set_open(false, false)
	var menu: Button = screen.get_node("%OpenMenuButton")
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = menu.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = pressed
		root.push_input(event, true)
	await create_timer(0.3).timeout
	_check(screen.command_drawer.is_open, "settings click opens drawer", root.size)
	for failure: String in failures:
		push_error(failure)
	print("HEADER LOGO CHECK: ", failures.size(), " failures")
	screen.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check(passed: bool, description: String, dimensions: Vector2i) -> void:
	if not passed:
		failures.append("%s: %s" % [dimensions, description])

