extends Node

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: int = 0
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	get_tree().root.add_child(screen)
	var online: OnlineGameController = OnlineGameController.new()
	get_tree().root.add_child(online)
	var response: Dictionary = OnlineRules.execute({"action": "create", "matchId": "gem-ui", "seed": 42}).views.human
	response.merge({"matchId": "gem-ui", "version": 1, "deadline": 1060.0, "serverTime": 1000.0,
		"opponent": {"displayName": "Rival", "connected": true}})
	online._session = OnlineSessionView.from_response(response)
	var prior_hand: ScoreEvent = ScoreEvent.create(&"gem-ui-prior", &"gem-ui-prior-move", &"ai",
		ScoringEnums.ScoreCategory.POKER_HAND, 2, [Vector2i(1, 1)] as Array[Vector2i],
		{"category": "PAIR"})
	online._session.get_ledger().add(prior_hand)
	screen.attach_controller(online)
	await get_tree().process_frame
	if screen.gem_pot_view == null or screen.tile_pile_view.visible:
		push_error("Online HUD did not replace centered tile stack with Gem pot")
		failures += 1
	if screen.gem_pot_view.total() != 2 or screen.gem_travel_layer.active_flights() != 0:
		push_error("Reconnected match did not restore pot without replaying old awards")
		failures += 1
	if screen.gem_pot_view.get_child_count() != 0 or screen.gem_pot_view.progress_fraction() != 0.0:
		push_error("Uncapped online pot should have no numeric labels or honey progress")
		failures += 1
	if screen.gem_pot_view.accessibility_name != "Online Gem pot: 2 Gems, no limit":
		push_error("Online pot total is unavailable to accessibility")
		failures += 1
	var event: ScoreEvent = ScoreEvent.create(&"gem-ui-hand", &"gem-ui-move", &"human",
		ScoringEnums.ScoreCategory.POKER_HAND, 6, [Vector2i(2, 2)] as Array[Vector2i],
		{"category": "THREE_OF_A_KIND"})
	screen._show_gem_awards([event], Vector2i(2, 2))
	if screen.gem_travel_layer.active_flights() != 1:
		push_error("Committed hand did not launch Gem flight")
		failures += 1
	if screen.gem_travel_layer.get_child_count() != 1:
		push_error("Gem gain label was not shown")
		failures += 1
	else:
		var gain: Label = screen.gem_travel_layer.get_child(0).get_child(0) as Label
		if gain.text != "+8 GEMS":
			push_error("Gem gain label did not show the awarded amount")
			failures += 1
	await get_tree().create_timer(1.1).timeout
	if screen.gem_pot_view.total() != 10:
		push_error("Gem pot did not increment by the hand value on arrival")
		failures += 1
	screen._show_gem_awards([event], Vector2i(2, 2))
	if screen.gem_pot_view.total() != 10 or screen.gem_travel_layer.active_flights() != 0:
		push_error("Duplicate score event animated or counted twice")
		failures += 1
	var previous_motion: bool = AccessibilitySettings.reduced_motion()
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, true)
	var quiet_event: ScoreEvent = ScoreEvent.create(&"gem-ui-quiet", &"gem-ui-move-2", &"human",
		ScoringEnums.ScoreCategory.POKER_HAND, 2, [Vector2i(3, 2)] as Array[Vector2i],
		{"category": "PAIR"})
	screen._show_gem_awards([quiet_event], Vector2i(3, 2))
	if screen.gem_pot_view.total() != 12 or screen.gem_travel_layer.active_flights() != 0:
		push_error("Reduced motion did not update the count without travel")
		failures += 1
	screen.free()
	online.free()
	var ai_screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	get_tree().root.add_child(ai_screen)
	var ai := GameSessionController.new()
	ai.save_path = "user://ai_gem_ui_test.json"
	ai_screen.add_child(ai)
	ai_screen.attach_controller(ai)
	ai.start_new_match(&"ai-gem-ui", 4242, AiEnums.Difficulty.HARD)
	await get_tree().process_frame
	if ai_screen.gem_pot_view == null or ai_screen.tile_pile_view.visible:
		push_error("AI HUD did not show the Gem pot")
		failures += 1
	elif ai_screen.gem_pot_view.total() != 0 or ai_screen.gem_pot_view.cap() != 80:
		push_error("Hard AI pot did not start at 0/80")
		failures += 1
	if ai_screen.gem_pot_view.progress_fraction() != 0.0:
		push_error("Empty AI pot ring is not empty")
		failures += 1
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, false)
	ai_screen.gem_pot_view.set_total(20, true)
	if not is_equal_approx(ai_screen.gem_pot_view.progress_fraction(), 0.25):
		push_error("AI pot ring does not represent the current share of its cap")
		failures += 1
	await get_tree().create_timer(0.14).timeout
	if not (ai_screen.gem_pot_view._display_fraction > 0.0 and ai_screen.gem_pot_view._display_fraction < 0.25):
		push_error("AI pot honey ring did not fill progressively")
		failures += 1
	await get_tree().create_timer(0.5).timeout
	if not is_equal_approx(ai_screen.gem_pot_view._display_fraction, 0.25):
		push_error("AI pot honey ring did not reach the current Gem share")
		failures += 1
	ai_screen.gem_pot_view.set_total(0)
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, true)
	var ai_events: Array[ScoreEvent] = []
	for index: int in range(6):
		ai_events.append(ScoreEvent.create(StringName("ai-ui-hand-%d" % index), &"ai-ui-move",
			&"human" if index % 2 == 0 else &"ai", ScoringEnums.ScoreCategory.POKER_HAND,
			12, [Vector2i(3, 3)] as Array[Vector2i], {"category": "FOUR_OF_A_KIND"}))
	ai_screen._show_gem_awards(ai_events, Vector2i(3, 3))
	if ai_screen.gem_pot_view.total() != 80 or not is_equal_approx(ai_screen.gem_pot_view.progress_fraction(), 1.0) \
			or not is_equal_approx(ai_screen.gem_pot_view._display_fraction, 1.0):
		push_error("AI pot did not stop at its cap")
		failures += 1
	if ai_screen.gem_pot_view.get_child_count() != 0 or ai_screen.gem_pot_view.accessibility_name != "AI Gem pot full: 80 of 80 Gems":
		push_error("Full AI pot should show only the ring and expose its total to accessibility")
		failures += 1
	if not OS.get_environment("AI_GEM_CAPTURE").is_empty() and DisplayServer.get_name() != "headless":
		get_tree().root.size = Vector2i(360, 800)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png(OS.get_environment("AI_GEM_CAPTURE")) != OK:
			push_error("AI Gem pot capture failed")
			failures += 1
	ai.set_ai_difficulty(AiEnums.Difficulty.EASY)
	ai_screen._refresh_all()
	if ai_screen.gem_pot_view.cap() != 20 or ai_screen.gem_pot_view.total() != 0:
		push_error("Difficulty downgrade did not recompute the AI pot from committed events")
		failures += 1
	ai.set_ai_difficulty(AiEnums.Difficulty.HARD)
	ai_screen._refresh_all()
	if ai_screen.gem_pot_view.cap() != 20:
		push_error("Raising rival difficulty increased the reward ceiling")
		failures += 1
	ai.clear_saved_match()
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, previous_motion)
	print("[gem pot UI] %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
