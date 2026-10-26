extends SceneTree
## Focused check for the committed-move score popup.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var suite: TestCase = load("res://tests/integration/test_game_screen.gd").new()
	suite.test_committed_move_shows_one_total_popup()
	for message: String in suite.failures:
		push_error(message)
	print("[score popup] %d assertions, %d failures" % [suite.assertions, suite.failures.size()])
	quit(0 if suite.failures.is_empty() else 1)
