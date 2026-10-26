extends Node

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite: TestCase = load("res://tests/integration/test_game_screen.gd").new()
	suite.test_turn_strip_stays_untimed_while_player_thinks()
	suite.test_turn_strip_uses_concept_style_without_a_countdown()
	suite.test_notices_use_board_caption_and_restore_the_current_turn()
	suite.test_placement_warning_in_board_caption_clears_when_the_line_is_fixed()
	suite.test_rival_score_notice_uses_the_match_opponent_name()
	for failure: String in suite.failures:
		push_error(failure)
	print("Board caption: %d assertions, %d failures" % [suite.assertions, suite.failures.size()])
	get_tree().quit(0 if suite.failures.is_empty() else 1)
