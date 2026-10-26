extends SceneTree


func _initialize() -> void:
	var test: TestCase = load("res://tests/integration/test_online_play.gd").new()
	test.test_new_verified_ai_game_ignores_the_previous_match_poll()
	test.test_all_active_verified_ai_games_remain_resumable()
	for failure: String in test.failures:
		push_error(failure)
	print("[new AI game] %d assertions, %d failures" % [test.assertions, test.failures.size()])
	quit(0 if test.failures.is_empty() else 1)
