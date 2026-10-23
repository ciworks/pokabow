extends SceneTree
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
	var path := OS.get_environment("RESULTS_QA_DIR")
	if path.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(path.path_join(name + ".png")) == OK, "Capture saved")
func result(outcome: int) -> MatchResult:
	var value := MatchResult.new()
	value.outcome = outcome
	value.end_reason = TurnEnums.EndReason.TILE_SOURCE_EXHAUSTED
	value.human_score = 128
	value.ai_score = 128 if outcome == TurnEnums.MatchOutcome.DRAW else 96
	value.move_count = 42
	value.terms = {String(TurnEnums.HUMAN_PLAYER_ID): {"poker": 90, "edge": 26, "cluster": 12}, String(TurnEnums.AI_PLAYER_ID): {"poker": 102 if outcome == TurnEnums.MatchOutcome.DRAW else 70, "edge": 18, "cluster": 8}}
	return value
func present_result(screen: GameScreen, value: MatchResult) -> void:
	screen._on_match_ended(value)
	if screen._pending_match_result != null:
		screen._on_final_board_pause_finished()
func _run() -> void:
	var suite: TestCase = load("res://tests/integration/test_game_screen.gd").new()
	for method: String in ["test_results_mark_the_winner_without_sweeping_panels", "test_the_summary_panel_shows_the_final_breakdown_and_restarts", "test_rival_final_move_finishes_before_results_cover_board"]:
		suite.call(method)
	assertions += suite.assertions
	failures += suite.failures.size()
	for message: String in suite.failures:
		push_error(message)
	var avatars: TestCase = load("res://tests/unit/test_player_avatar.gd").new()
	avatars.test_avatar_game_screen_receives_player_portrait()
	assertions += avatars.assertions
	failures += avatars.failures.size()
	for message: String in avatars.failures:
		push_error(message)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i.ZERO
	# Use the actual scene and its native result nodes, without creating a match.
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	root.add_child(screen)
	root.size_changed.disconnect(screen._fit_canvas)
	root.content_scale_size = Vector2i.ZERO
	screen.set_rival_portrait(load("res://assets/ui/modern_tabletop/avatars/rivals/rival_02.tres"))
	var view := screen.summary_overlay as MatchEndPresentation
	var win := result(TurnEnums.MatchOutcome.HUMAN_WIN)
	present_result(screen, win)
	view._stop_animation()
	view.seek(view.DURATION)
	for dimensions: Vector2i in [Vector2i(320,568), Vector2i(360,800), Vector2i(390,844), Vector2i(540,960), Vector2i(540,1200)]:
		root.size = dimensions
		await settle()
		view._fit_layout()
		await settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		verify(bounds.encloses(view._button.get_global_rect()), "Exit stays on screen " + str(dimensions))
		verify(view.can_share_win() and view._share_button.visible, "Win share is available " + str(dimensions))
		verify(bounds.encloses(view._share_button.get_global_rect()), "Win share stays on screen " + str(dimensions))
		verify(view._share_button.icon != null and view._share_button.size.y >= 48, "Win share has icon and touch height")
		verify(view._button.size.y >= 48, "Exit touch height")
		verify(view._content.size.x <= view._scroll.size.x + 1, "No horizontal overflow")
		verify(view._card_slot.size.y >= view._card.get_combined_minimum_size().y, "Score card fits content")
		verify(view._card.get_global_rect().end.y <= view._breakdown_title.global_position.y + 1, "Score card clears breakdown")
		for portrait: TextureRect in view._portraits:
			verify(portrait.size.x > 40 and absf(portrait.size.x-portrait.size.y)<1, "Portrait visible and square")
		verify(view._title.get_theme_font("font").get_font_name().contains("Fredoka"), "Real Fredoka")
		await capture("results-%dx%d" % [dimensions.x,dimensions.y])
	root.size = Vector2i(360,800)
	root.content_scale_size = Vector2i(540,1200)
	await settle()
	view._fit_layout()
	await settle()
	verify(view._button.size.y * root.get_screen_transform().get_scale().x >= 48, "Physical 48px exit")
	for key: String in ["poker","edge","cluster"]:
		verify(view._terms[key][1].text == str(win.terms_for(TurnEnums.HUMAN_PLAYER_ID)[key]), "Real player " + key)
		verify(view._terms[key][2].text == str(win.terms_for(TurnEnums.AI_PLAYER_ID)[key]), "Real rival " + key)
	for moment: float in [0.0,0.15,0.5,0.8]:
		view.seek(moment)
		verify(view._button.visible and not view._button.disabled, "Exit available throughout animation")
		verify(view._scores[0].text == "128" and view._scores[1].text == "96", "Scores final throughout entrance")
		await capture("win-%03dms" % roundi(moment*1000))
	for outcome: int in [TurnEnums.MatchOutcome.AI_WIN, TurnEnums.MatchOutcome.DRAW, TurnEnums.MatchOutcome.INCOMPLETE]:
		var value := result(outcome)
		if outcome == TurnEnums.MatchOutcome.AI_WIN:
			value.end_reason = TurnEnums.EndReason.RESIGNATION
		if outcome == TurnEnums.MatchOutcome.INCOMPLETE:
			value.end_reason = TurnEnums.EndReason.RULES_FAILURE
		present_result(screen, value)
		view._stop_animation()
		view.seek(0.5)
		verify(not view.can_share_win() and not view._share_button.visible, "Share hidden for loss, draw, or incomplete result")
		verify(view._accents[0].sparkle_alpha == 0 and view._accents[1].sparkle_alpha == 0, "No celebration for loss/draw/incomplete")
		verify(view._accents[1].winner == (outcome == TurnEnums.MatchOutcome.AI_WIN), "Outcome determines winner even when resignation winner has fewer points")
		view.seek(0.8)
		await settle()
		await capture("outcome-%d" % outcome)
	var large := result(TurnEnums.MatchOutcome.HUMAN_WIN)
	large.human_score = 123456
	large.ai_score = 120000
	large.terms = {String(TurnEnums.HUMAN_PLAYER_ID): {"poker": 120000, "edge": 3000, "cluster": 456}, String(TurnEnums.AI_PLAYER_ID): {"poker": 119000, "edge": 800, "cluster": 200}}
	present_result(screen, large)
	view._stop_animation()
	view.seek(0.8)
	await settle()
	verify(view._content.size.x <= view._scroll.size.x + 1, "Large scores fit without horizontal scrolling")
	for label: Label in view._scores:
		verify(label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x <= label.size.x + 1, "Six-digit score fits")
	view.clear()
	present_result(screen, win)
	await create_timer(0.95).timeout
	verify(is_equal_approx(view._elapsed, view.DURATION), "Live tween finishes within one second")
	verify(view._animation == null, "Entrance finishes within one second")
	verify(view._accent_animation != null and view._accent_animation.is_running(), "Winner accent keeps animating")
	await create_timer(view.ACCENT_CYCLE_SECONDS * 0.5).timeout
	verify(view._accents[0].pulse > 0.5 and view._accents[0].sparkle_alpha > 0.0, "Winner ring and sparkles repeat")
	present_result(screen, result(TurnEnums.MatchOutcome.HUMAN_WIN))
	verify(is_equal_approx(view._elapsed, view.DURATION), "Repeated result does not replay the entrance")
	verify(view._accent_animation != null and view._accent_animation.is_running(), "Repeated result retains the accent loop")
	view.clear()
	verify(view._accent_animation == null, "Clear cancels winner accent")
	present_result(screen, win)
	view.hide()
	verify(view._animation == null and view._accent_animation == null, "Leaving cancels animations")
	var previous: Variant = ProjectSettings.get_setting(AccessibilitySettings.REDUCED_MOTION_PATH, false)
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, true)
	present_result(screen, result(TurnEnums.MatchOutcome.HUMAN_WIN))
	verify(view._animation == null and view._accent_animation == null and view._elapsed == view.DURATION, "Reduced motion settles immediately")
	verify(view._accents[0].sparkle_alpha < 0.001, "Reduced motion has no sparkles")
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, previous)
	var exits: Array[int] = []
	var shares: Array[int] = []
	screen.hub_requested.connect(func() -> void: exits.append(1))
	view.share_requested.connect(func() -> void: shares.append(1))
	view._share_button.pressed.emit()
	verify(shares.size() == 1, "Share action emits the win request")
	view._button.pressed.emit()
	verify(exits.size() == 1, "Existing hub exit signal preserved")
	screen.free()
	await settle()
	print("[Results QA] %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)
