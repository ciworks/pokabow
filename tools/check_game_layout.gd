extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var suite = load("res://tests/integration/test_game_screen.gd").new()
	for method: String in [
		"test_game_screen_provides_the_adr_008_hierarchy",
		"test_player_panel_always_shows_you",
		"test_human_input_is_gated_to_the_human_action_phase",
		"test_command_drawer_opens_closes_and_returns_to_rack_for_swap",
		"test_command_preview_matches_commit_without_mutating_board",
		"test_bottom_navigation_play_and_undo_use_staged_line_commands",
		"test_bottom_navigation_swap_uses_existing_selection_and_confirmation",
		"test_bottom_navigation_quit_requests_the_hub",
		"test_a_second_tap_on_the_selected_deck_tile_turns_it_in_the_row",
		"test_rotating_a_staged_tile_updates_the_line_without_writing_to_the_board",
		"test_avatar_timer_updates_without_rebuilding_board_and_clears_swap_on_expiry",
		"test_avatar_timer_repeated_warning_respects_reduced_motion",
	]:
		var before: int = suite.assertions
		suite.call(method)
		if suite.assertions == before:
			suite.failures.append(method + " aborted without assertions")
		print(method, ": assertions=", suite.assertions - before)
	for failure: String in suite.failures:
		push_error(failure)
	print("LAYOUT CHECK: ", suite.assertions, " assertions, ", suite.failures.size(), " failures")
	var failed: bool = not suite.failures.is_empty()
	suite = null
	var bootstrap = load("res://tests/unit/test_project_bootstrap.gd").new()
	bootstrap.test_viewport_is_locked_portrait_540x960()
	bootstrap.test_portrait_canvas_preserves_aspect_ratio()
	for failure: String in bootstrap.failures:
		push_error(failure)
	print("PORTRAIT CHECK: ", bootstrap.assertions, " assertions, ", bootstrap.failures.size(), " failures")
	failed = failed or not bootstrap.failures.is_empty()
	bootstrap = null
	quit(1 if failed else 0)
