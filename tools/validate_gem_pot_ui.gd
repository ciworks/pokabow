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
	var title: Label = screen.gem_pot_view.get_node("Title") as Label
	var title_width: float = title.get_theme_font("font").get_string_size(title.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x
	if title_width > title.size.x:
		push_error("Gem pot heading does not fit horizontally")
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
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, previous_motion)
	print("[gem pot UI] %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
