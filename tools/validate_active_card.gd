extends SceneTree
## Focused hub card copy and resume routing check.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var suite = load("res://tests/integration/test_active_games.gd").new()
	suite.test_hub_prioritises_one_game_and_keeps_other_games_reachable()
	for failure: String in suite.failures:
		push_error(failure)
	print("[active card] %d assertions, %d failures" % [suite.assertions, suite.failures.size()])
	quit(0 if suite.failures.is_empty() else 1)
