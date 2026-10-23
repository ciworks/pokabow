extends SceneTree
## Render player-only framing without touching the real account or saved match.

var failures: int = 0
var assertions: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error(message)

func _capture(filename: String) -> void:
	for frame: int in range(6):
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp/avatar-frame-%s.png" % filename)

func _check_frame(view: TextureRect, message: String) -> void:
	_check(view is FramedPlayerAvatar, message + " uses shared frame")
	_check(view.has_node("DefaultAvatarFrame"), message + " displays frame")
	_check(view.mouse_filter == Control.MOUSE_FILTER_IGNORE, message + " preserves input")

func _run() -> void:
	root.content_scale_size = Vector2i(540, 960)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = Vector2i(540, 960)
	# Circular alignment must survive square, tall, and wide avatar slots.
	var probe := FramedPlayerAvatar.new()
	probe.visible = false
	root.add_child(probe)
	for dimensions: Vector2 in [Vector2(96, 96), Vector2(100, 144), Vector2(160, 90)]:
		probe.size = dimensions
		probe._fit_portrait()
		var frame: TextureRect = probe.get_node("DefaultAvatarFrame")
		var frame_scale: Vector2 = frame.size / FramedPlayerAvatar.FRAME.get_size()
		var opening: Vector2 = FramedPlayerAvatar.OPENING_SIZE * frame_scale
		var center: Vector2 = frame.position + FramedPlayerAvatar.OPENING_CENTER * frame_scale
		var portrait: Vector4 = (probe.material as ShaderMaterial).get_shader_parameter("portrait_rect")
		_check(is_equal_approx(opening.x, opening.y), "frame opening stays circular")
		_check(center.is_equal_approx(dimensions * 0.5), "frame opening stays centered")
		_check(is_equal_approx(portrait.z * dimensions.x, portrait.w * dimensions.y), "portrait stays circular")
		_check(is_equal_approx(portrait.z * dimensions.x, opening.x), "portrait perimeter matches frame opening")
		_check(Rect2(Vector2.ZERO, dimensions).grow(0.01).encloses(frame.get_rect()), "frame decorations remain within avatar slot")
	probe.free()
	var texture: Texture2D = load(PlayerAvatarStore.default_paths()[0])
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	root.add_child(screen)
	var controller := GameSessionController.new()
	controller.save_path = "user://avatar_frame_preview_%d.json" % OS.get_process_id()
	controller.process_mode = Node.PROCESS_MODE_DISABLED
	screen.add_child(controller)
	screen.attach_controller(controller)
	controller.start_new_match(&"avatar-frame-preview", 4242)
	screen.set_player_portrait(texture)
	var human: TextureRect = screen.human_score_panel.get_node("HumanScoreBox/Portrait")
	var rival: TextureRect = screen.ai_score_panel.get_node("AiScoreBox/Portrait")
	_check_frame(human, "HUD player")
	_check(not rival is FramedPlayerAvatar and not rival.has_node("DefaultAvatarFrame"), "HUD rival remains unframed")
	await create_timer(3.0).timeout
	await _capture("game-540x960")
	root.size = Vector2i(360, 800)
	await _capture("game-360x800")
	root.size = Vector2i(540, 960)
	var photo := Image.create(195, 195, false, Image.FORMAT_RGB8)
	photo.fill(Color("63aaca"))
	photo.fill_rect(Rect2i(55, 55, 85, 85), Color("f4c68c"))
	var photo_texture := ImageTexture.create_from_image(photo)
	screen.set_player_portrait(photo_texture)
	_check(human.texture == photo_texture and human.has_node("DefaultAvatarFrame"), "photo replacement preserves frame")
	await _capture("game-photo")
	var session: GameSessionState = controller.get_session()
	session.finish(TurnEnums.MatchOutcome.HUMAN_WIN, TurnEnums.EndReason.BOARD_FULL)
	screen._on_match_ended(MatchResult.build(session))
	screen.summary_overlay._stop_animation()
	screen.summary_overlay.seek(10.0)
	_check_frame(screen.summary_overlay.find_child("PlayerAvatar", true, false), "results player")
	_check(not screen.summary_overlay.find_child("RivalAvatar", true, false) is FramedPlayerAvatar, "results rival remains unframed")
	await _capture("results")
	controller.clear_saved_match()
	screen.free()
	var selection: OpponentSelectionScreen = load("res://scenes/hub/opponent_selection_screen.tscn").instantiate()
	root.add_child(selection)
	selection.set_player_portrait(texture)
	_check_frame(selection.get_node("%HumanPortrait"), "pre-match player")
	_check(not selection.rival_portrait is FramedPlayerAvatar, "pre-match rival remains unframed")
	await _capture("prematch")
	selection.free()
	var profile: ProfileScreen = load("res://scenes/profile/profile_screen.tscn").instantiate()
	profile.avatar_store_path = "user://avatar_frame_missing_account.json"
	root.add_child(profile)
	profile.set_user_state({"user": {"displayName": "Player", "username": "player", "email": "player@example.com"}})
	profile._avatar_choices[0].pressed.emit()
	_check(profile._avatar_index == 0, "framed thumbnail still selects avatar")
	_check_frame(profile._avatar_preview, "profile player")
	_check_frame(profile._photo_preview, "photo preview")
	for choice: Button in profile._avatar_choices:
		_check_frame(choice.get_node("AvatarPreview"), "avatar thumbnail")
	await _capture("profile-540x960")
	for choice: Button in profile._avatar_choices:
		var thumbnail: Control = choice.get_node("AvatarPreview")
		_check(choice.get_global_rect().encloses(thumbnail.get_global_rect()), "thumbnail fits its button")
	root.size = Vector2i(360, 800)
	await _capture("profile-360x800")
	profile.free()
	var suite = load("res://tests/unit/test_player_avatar.gd").new()
	suite.test_avatar_game_screen_receives_player_portrait()
	assertions += suite.assertions
	failures += suite.failures.size()
	for failure: String in suite.failures:
		push_error(failure)
	print("AVATAR FRAME: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
