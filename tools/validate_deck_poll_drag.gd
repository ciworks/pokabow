extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var suite: TestCase = load("res://tests/unit/test_deck_touch_targets.gd").new()
	for method: Dictionary in suite.get_method_list():
		if String(method.name).begins_with("test_"):
			suite.call(String(method.name))
	var game_suite: TestCase = load("res://tests/integration/test_game_screen.gd").new()
	for method: String in [
		"test_a_fresh_deck_draws_no_tile_as_selected",
		"test_a_second_tap_on_the_selected_deck_tile_turns_it_in_the_row",
		"test_deck_drag_shrinks_preview_and_tracks_nearest_cell",
		"test_bottom_navigation_swap_submits_and_cancels_from_the_rack",
		"test_the_swap_returns_tiles_for_equal_replacements_and_consumes_the_turn",
	]:
		game_suite.call(method)
	suite.assertions += game_suite.assertions
	suite.failures.append_array(game_suite.failures)
	for failure: String in suite.failures:
		push_error(failure)
	print("[deck poll drag] %d assertions, %d failures" % [suite.assertions, suite.failures.size()])
	quit(0 if suite.failures.is_empty() else 1)
