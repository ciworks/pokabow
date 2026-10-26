extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var suite = load("res://tests/integration/test_game_screen.gd").new()
	for method: String in [
		"test_game_screen_provides_the_adr_008_hierarchy",
		"test_table_level_chip_tracks_authoritative_player_level",
		"test_rival_tiles_fly_from_rack_then_refill_without_changing_state",
		"test_rival_refill_uses_only_remaining_pot_tiles",
		"test_rival_animation_clears_on_restart_and_respects_reduced_motion",
		"test_rival_final_move_finishes_before_results_cover_board",
		"test_player_panel_always_shows_you",
		"test_a_human_with_no_valid_move_sees_a_header_notice_and_loses_the_turn",
		"test_header_notices_replace_overlays_and_restore_latest_turn",
		"test_header_placement_warning_clears_when_the_line_is_fixed",
		"test_human_input_is_gated_to_the_human_action_phase",
		"test_command_drawer_opens_closes_and_returns_to_rack_for_swap",
		"test_command_preview_matches_commit_without_mutating_board",
		"test_bottom_navigation_menu_and_play_use_existing_commands",
		"test_bottom_navigation_swap_submits_and_cancels_from_the_rack",
		"test_hub_navigation_buttons_request_the_hub",
		"test_a_second_tap_on_the_selected_deck_tile_turns_it_in_the_row",
		"test_rotating_a_staged_tile_updates_the_line_without_writing_to_the_board",
		"test_turn_strip_stays_untimed_while_player_thinks",
		"test_turn_strip_uses_concept_style_without_a_countdown",
		"test_the_summary_panel_shows_the_final_breakdown_and_restarts",
		"test_deal_tracks_live_pot_and_rack_geometry_without_restarting",
		"test_deck_surrounding_space_can_drag_a_tile_onto_the_board",
		"test_pinch_zoom_keeps_anchor_and_mouse_wheel_steps",
		"test_pinch_cancels_staged_drag_and_waits_for_all_fingers",
		"test_pinch_ignores_outside_touches_and_recovers_from_cancel",
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
