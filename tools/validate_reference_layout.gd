extends SceneTree

var failures: int = 0
var assertions: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = Vector2i(540, 960)
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	root.add_child(screen)
	var controller := GameSessionController.new()
	controller.save_path = "user://reference_layout_%d.json" % OS.get_process_id()
	controller.process_mode = Node.PROCESS_MODE_DISABLED
	screen.add_child(controller)
	screen.attach_controller(controller)
	controller.start_new_match(&"reference-layout", 4242)
	await create_timer(3.0).timeout
	for dimensions: Vector2i in [Vector2i(540, 960), Vector2i(360, 800), Vector2i(320, 568), Vector2i(1080, 2400), Vector2i(1280, 720)]:
		root.size = dimensions
		for frame: int in range(12):
			await process_frame
		var hud: Control = screen.get_node("Root/Column/Hud")
		var pot: Control = screen.get_node("%PotPanel")
		var rival_rack: Control = screen.get_node("%OpponentRack")
		var board: Rect2 = screen.board_view.global_visible_rect().grow(BoardView.PADDING)
		var rack: Rect2 = screen.deck_panel.get_global_rect()
		var navigation: Rect2 = screen.bottom_navigation.get_global_rect()
		var player_avatar: TextureRect = screen.human_score_panel.get_node("HumanScoreBox/Portrait")
		var rival_avatar: TextureRect = screen.ai_score_panel.get_node("AiScoreBox/Portrait")
		_check(player_avatar.scale.is_equal_approx(Vector2.ONE * 1.25), "player avatar and frame are 25 percent larger")
		_check(absf(player_avatar.get_global_rect().get_center().y - rival_avatar.get_global_rect().get_center().y) < 1.0, "player and rival avatars share a vertical center")
		_check(not player_avatar.get_global_rect().intersects(pot.get_global_rect()), "enlarged player avatar clears the pot")
		var tile: Rect2 = screen.deck_view.tile_rect_at(0)
		_check(not screen.deck_panel is TextureRect, "human tiles have no textured tray")
		_check(absf(screen.deck_panel.size.y - tile.size.y - DeckView.PADDING * 2.0) <= 1.0, "hand reserves only tile height and touch padding")
		_check(absf(pot.get_global_rect().get_center().x - hud.get_global_rect().get_center().x) < 1.0, "pot stays centered")
		_check(pot.size.x >= 170.0, "pot is prominently sized")
		_check(not screen.tile_pile_view.caption.is_visible_in_tree(), "pot has no caption")
		_check(rival_rack._tile_count == controller.get_session().deck_count(TurnEnums.AI_PLAYER_ID), "rival rack uses authoritative count")
		_check(rival_rack.get_global_rect().position.y >= hud.get_global_rect().end.y, "rival tiles below header")
		_check(board.position.y >= rival_rack.get_global_rect().end.y, "board below rival tiles")
		_check(board.end.y <= rack.position.y + 1.0, "board above human rack")
		_check(rack.end.y <= navigation.position.y, "rack clear of actions")
		_check(absf(board.size.x - rack.size.x) <= 1.0, "board and rack fill width at close zoom")
		_check(screen.get_node("%HeaderTurnStatus").text == "Your turn", "turn visible in header")
		for action: StringName in screen.bottom_navigation.ACTIONS:
			var button: Button = screen.bottom_navigation.buttons[action]
			var icon: Control = button.get_node("Content").get_child(0)
			_check(icon.size.x >= 80.0 and icon.size.y >= 80.0, "large action icon")
			_check(navigation.encloses(button.get_global_rect()), "action remains inside bar")
		for panel: PanelContainer in [screen.human_score_panel, screen.ai_score_panel]:
			var art: Control = panel.get_child(0)
			_check(not art.title.get_global_rect().intersects(pot.get_global_rect()), "pot clears player name")
			_check(not art.value.get_global_rect().intersects(pot.get_global_rect()), "pot clears player score")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.tmp/reference-layout-%dx%d.png" % [dimensions.x, dimensions.y])
		screen.board_view.set_close_view(false)
		await process_frame
		var overview: Rect2 = screen.board_view.global_visible_rect()
		_check(is_equal_approx(overview.size.x, overview.size.y), "overview shows full square board")
		screen.board_view.set_close_view(true)
		await process_frame
	# Inspect the countdown band at full, half, warning, and empty states.
	root.size = Vector2i(540, 960)
	for frame: int in range(12):
		await process_frame
	for seconds: int in [60, 30, 10, 0]:
		screen.tile_pile_view.set_seconds_left(seconds)
		await process_frame
		await process_frame
		_check(is_equal_approx(screen.tile_pile_view.remaining_timer_angle(), TAU * float(seconds) / TurnManager.TURN_SECONDS), "pot ring tracks remaining time")
		_check(not screen.human_score_panel.get_node("HumanScoreBox/TurnOutline").visible, "human border timer is hidden")
		_check(not screen.ai_score_panel.get_node("AiScoreBox/TurnOutline").visible, "rival border timer is hidden")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.tmp/pot-ring-%d-seconds.png" % seconds)
	# Check an actual notification at phone width, including timer expiry.
	root.size = Vector2i(360, 800)
	for frame: int in range(12):
		await process_frame
	screen._on_notice(GameSessionController.NO_VALID_MOVE_NOTICE)
	await process_frame
	await process_frame
	var header: Label = screen.get_node("%HeaderTurnStatus")
	_check(header.text == GameSessionController.NO_VALID_MOVE_NOTICE, "notification appears in top label")
	_check(screen.feedback_layer.find_child("ToastLayout", true, false) == null, "notifications create no overlay")
	_check(screen.get_global_rect().encloses(header.get_global_rect()), "notification fits phone viewport")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp/header-notice-360x800.png")
	await create_timer(GameScreen.HEADER_NOTICE_SECONDS + 0.1).timeout
	_check(header.text == "Your turn", "notification expiry restores turn status")
	controller.clear_saved_match()
	screen.free()
	print("REFERENCE LAYOUT: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
