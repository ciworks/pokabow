extends SceneTree
## Concept-only render. Overrides the painter cache in this process; no live assets change.
const OUTPUT: String = "res://docs/design/edge-bands-concept"
const VARIANTS: Array[String] = ["current", "clear", "strong"]
const BAND_PIXELS: Array[int] = [0, 18, 22]
var original_edges: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = Vector2i(360, 800)
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	var controller := GameSessionController.new()
	controller.save_path = "res://.tmp/edge_bands_preview.json"
	controller.process_mode = Node.PROCESS_MODE_DISABLED
	assert(controller.start_new_match(&"edge-bands-concept", 4242))
	var session: GameSessionState = controller.get_session()
	var rng := RandomNumberGenerator.new()
	rng.seed = 321
	var moves: int = 0
	for turn: int in range(16):
		var player: StringName = session.get_turn_state().active_player_id
		var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate_with_report(
			session.get_board(), session.deck_for(player), {}, 128)
		if candidates.is_empty():
			TurnManager.resolve_no_valid_move(session)
			continue
		var candidate: AiMoveCandidate = candidates[rng.randi_range(0, candidates.size() - 1)]
		var result: LineResult = MoveCommitter.commit_line(session, player, candidate.snapshots)
		assert(result.was_committed())
		TurnManager.resolve(session, result)
		moves += 1
	root.add_child(screen)
	screen.add_child(controller)
	screen.attach_controller(controller)
	await create_timer(3.0).timeout
	for color: String in ["blue", "red", "green", "yellow"]:
		for side: String in TilePainter.EDGE_SIDES:
			var path: String = TilePainter.EDGE_FILE_FORMAT % [TilePainter.TILE_EDGE_DIR, color, side]
			original_edges[path] = TilePainter._art_for(path)
	print("Legal preview: ", moves, " moves, ", session.get_board().occupied_count(), " tiles")
	print("Original blue top bounds: ", (original_edges[TilePainter.TILE_EDGE_DIR + "tile_blue_top.png"] as Texture2D).get_image().get_used_rect())
	for variant: int in range(VARIANTS.size()):
		_apply_edges(BAND_PIXELS[variant])
		for close: bool in [false, true]:
			screen.board_view.set_close_view(close)
			screen.board_view.set_board(session.get_board())
			screen.deck_view.queue_redraw()
			await create_timer(0.15).timeout
			await RenderingServer.frame_post_draw
			var capture: Image = root.get_texture().get_image()
			var zoom_name: String = "close" if close else "overview"
			capture.save_png(OUTPUT.path_join(VARIANTS[variant] + "-" + zoom_name + ".png"))
			print(VARIANTS[variant], " ", zoom_name, " board=", screen.board_view.global_board_rect())
	_apply_edges(0)
	screen.queue_free()
	await process_frame
	quit()

func _apply_edges(thickness: int) -> void:
	for path: String in original_edges:
		if thickness == 0:
			TilePainter._art[path] = original_edges[path]
			continue
		var side: String = path.get_file().get_basename().get_slice("_", 2)
		var mask: Image = Image.create(200, 200, false, Image.FORMAT_RGBA8)
		mask.fill(Color.TRANSPARENT)
		# Retain an ivory corner break and the base's lower lip. Bands grow inward
		# from the existing face perimeter; colours are applied only by TilePainter.
		var band: Rect2i
		match side:
			"top": band = Rect2i(23, 10, 154, thickness)
			"right": band = Rect2i(190 - thickness, 12 + thickness, thickness, 164 - thickness * 2)
			"bottom": band = Rect2i(23, 178 - thickness, 154, thickness)
			"left": band = Rect2i(10, 12 + thickness, thickness, 164 - thickness * 2)
		mask.fill_rect(band, Color.WHITE)
		mask.generate_mipmaps()
		TilePainter._art[path] = ImageTexture.create_from_image(mask)
