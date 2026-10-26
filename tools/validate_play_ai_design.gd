extends SceneTree
## Render with Compatibility; PLAY_AI_QA_DIR optionally stores screenshots.
var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func verify(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)

func settle() -> void:
	for i: int in range(6):
		await process_frame

func capture(name: String) -> void:
	var path := OS.get_environment("PLAY_AI_QA_DIR")
	if path.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(path.path_join(name + ".png")) == OK, "Screenshot saved")

func _run() -> void:
	var suite: TestCase = load("res://tests/integration/test_matchmaking.gd").new()
	for method: Dictionary in suite.get_method_list():
		if String(method.name).begins_with("test_"):
			suite.call(method.name)
	assertions += suite.assertions
	failures += suite.failures.size()
	for message: String in suite.failures:
		push_error(message)
	var avatar_suite: TestCase = load("res://tests/unit/test_player_avatar.gd").new()
	avatar_suite.test_avatar_game_screen_receives_player_portrait()
	assertions += avatar_suite.assertions
	failures += avatar_suite.failures.size()
	for message: String in avatar_suite.failures:
		push_error(message)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i.ZERO
	var screen: OpponentSelectionScreen = load("res://scenes/hub/opponent_selection_screen.tscn").instantiate()
	root.add_child(screen)
	verify(screen._difficulty == AiEnums.DEFAULT_DIFFICULTY, "Existing difficulty default preserved")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(390, 844), Vector2i(540, 960), Vector2i(540, 1200)]:
		root.size = dimensions
		await settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		for key: String in ["Header", "Scroll", "StartButton", "FooterHint"]:
			verify(bounds.encloses((screen.get_node("%" + key) as Control).get_global_rect()), key + " fits " + str(dimensions))
		verify(screen.get_node("%Content").size.x <= screen.get_node("%Scroll").size.x + 1, "No horizontal overflow")
		for key: String in ["Heading", "Brand", "DifficultyLabel"]:
			var label := screen.get_node("%" + key) as Label
			verify(label.get_theme_font("font").get_font_name().contains("Fredoka"), "Actual Fredoka font")
			verify(label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x <= label.size.x + 1, key + " text fits")
		verify(screen.start_button.size.y >= 48, "Primary touch target")
		for key: String in ["HumanPortrait", "RivalPortrait"]:
			var portrait := screen.get_node("%" + key) as Control
			verify(portrait.size.x >= 72 and portrait.size.y >= 72, "Portrait has visible dimensions")
			verify(absf(portrait.size.x - portrait.size.y) < 1, "Portrait remains square")
		if dimensions.y / float(dimensions.x) < 1.95:
			verify((screen.get_node("%Scroll") as Control).get_global_rect().encloses((screen.get_node("%Difficulties") as Control).get_global_rect()), "Compact layout exposes difficulty controls")
		await capture("play-ai-%dx%d" % [dimensions.x, dimensions.y])
	root.size = Vector2i(360, 800)
	root.content_scale_size = Vector2i(540, 1200)
	await settle()
	var physical: float = root.get_screen_transform().get_scale().x
	for key: String in ["Modes", "Difficulties"]:
		for button: Button in screen.get_node("%" + key).get_children():
			verify(button.size.y * physical >= 47.9, "Physical 48px segment target")
	verify(screen.start_button.size.y * physical >= 48, "Physical primary target")
	for index: int in range(3):
		(screen.get_node("%Difficulties").get_child(index) as Button).pressed.emit()
		verify(screen._difficulty == index, "Visible difficulty segment selects its ID")
		verify((screen.get_node("%Difficulties").get_child(index) as Button).button_pressed, "Selected state shown")
	screen._select_difficulty(1)
	await settle()
	await capture("play-ai-phone-360x800")
	screen.select_online()
	await settle()
	verify(screen.start_button.disabled, "Unauthenticated online action disabled")
	verify(not screen.get_node("%DifficultyRow").visible, "Online hides AI controls")
	await capture("online-offline-phone")
	screen._on_matchmaking_changed("matched", "Your opponent is ready. Confirm when you are ready to play.", {"opponent": {"displayName": "A rival with a very long display name"}, "canReady": true, "ready": false})
	await settle()
	verify(screen.start_button.visible and not screen.start_button.disabled and screen.start_button.text == "Ready", "Matched lobby retains Ready action")
	verify(screen.back_button.text == "Leave lobby", "Matched lobby retains leave action")
	verify(screen.get_node("%Content").size.x <= screen.get_node("%Scroll").size.x + 1, "Long opponent name wraps without horizontal overflow")
	await capture("online-ready-phone")
	screen._on_matchmaking_changed("matched", "Waiting for your opponent.", {"opponent": {"displayName": "Rival"}, "canReady": true, "ready": true})
	verify(screen.start_button.disabled and screen.start_button.text == "Waiting for opponent", "Ready wait remains locked")
	screen._on_matchmaking_changed("failed", "Connection lost. Try again.", {})
	verify(not screen.start_button.disabled and not screen.mode_picker.disabled, "Failure permits retry or returning to AI")
	screen._select_mode(0)
	var received: Array[int] = []
	screen.opponent_selected.connect(func(rival: Dictionary, portrait: Texture2D) -> void:
		received.append(int(rival.get("difficulty", -1)))
		verify(portrait != null, "Selected real portrait supplied"))
	screen._begin_spin()
	for button: Button in screen.get_node("%Modes").get_children():
		verify(button.disabled, "Modes locked during selection")
	for button: Button in screen.get_node("%Difficulties").get_children():
		verify(button.disabled, "Difficulties locked during selection")
	screen._select_difficulty(2)
	verify(screen._difficulty == 1, "Locked selection cannot change difficulty")
	screen._process(100)
	screen._process(1)
	screen._process(1)
	verify(received == [1], "One automatic match handoff at selected difficulty")
	screen.free()
	var before: Variant = ProjectSettings.get_setting(AccessibilitySettings.REDUCED_MOTION_PATH, false)
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, true)
	screen = load("res://scenes/hub/opponent_selection_screen.tscn").instantiate()
	root.add_child(screen)
	screen._begin_spin()
	verify(not screen._spinning and screen._started, "Reduced motion chooses without cycling portraits")
	screen.free()
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, before)
	await settle()
	print("[Play AI QA] %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
