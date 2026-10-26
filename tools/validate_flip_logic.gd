extends SceneTree
## Fast, headless check of the deal turn without requiring viewport rendering.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var suite: TestCase = load("res://tests/integration/test_game_screen.gd").new()
	suite.test_deal_signals_tile_flip_sound_at_half_turn()
	suite.test_tile_flip_uses_a_thin_edge_and_a_short_lift()
	for message: String in suite.failures:
		push_error(message)
	print("[deal flip] %d assertions, %d failures" % [suite.assertions, suite.failures.size()])
	quit(0 if suite.failures.is_empty() else 1)
