extends "res://tests/harness/test_runner.gd"


func _initialize() -> void:
	call_deferred("_run_focused_suites")


func _run_focused_suites() -> void:
	quit(_run_suites())


func _collect_test_scripts() -> PackedStringArray:
	return PackedStringArray([
		"res://tests/unit/test_deck_touch_targets.gd",
		"res://tests/unit/test_turn_timer.gd",
		"res://tests/integration/test_game_screen.gd",
	])


func _test_method_names(test_case: Object) -> PackedStringArray:
	var names: PackedStringArray = super._test_method_names(test_case)
	if test_case.get_script().resource_path.ends_with("test_deck_touch_targets.gd"):
		return names
	var focused: PackedStringArray = []
	for method: String in names:
		if method in [
			"test_deal_tracks_live_pot_and_rack_geometry_without_restarting",
			"test_deck_drag_moves_smoothly_within_cells_and_outside_board",
			"test_deck_drag_shrinks_preview_and_tracks_nearest_cell",
			"test_a_drag_highlights_the_cell_under_the_pointer_as_legal_or_illegal",
			"test_a_drop_on_an_illegal_cell_or_off_the_board_changes_nothing",
			"test_each_player_has_sixty_seconds_before_timeout",
			"test_timer_border_loses_equal_lengths_and_disappears_at_zero",
			"test_deck_surrounding_space_can_drag_a_tile_onto_the_board",
			"test_a_dragged_tile_is_staged_at_the_cell_it_is_dropped_on",
			"test_a_second_tap_on_the_selected_deck_tile_turns_it_in_the_row",
			"test_the_deck_row_is_not_selectable_off_turn",
			"test_a_drag_off_turn_is_refused",
		]:
			focused.append(method)
	return focused
