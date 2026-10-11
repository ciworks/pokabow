extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failed: bool = false
	for path: String in ["res://tests/integration/test_game_screen.gd", "res://tests/unit/test_board_metrics.gd"]:
		var suite = load(path).new()
		for method: Dictionary in suite.get_script().get_script_method_list():
			var method_name: String = method.name
			if not method_name.begins_with("test_"):
				continue
			var before: int = suite.assertions
			suite.call(method_name)
			if suite.assertions == before:
				suite.failures.append(method_name + " aborted without assertions")
		for failure: String in suite.failures:
			push_error(failure)
		print(path, ": ", suite.assertions, " assertions, ", suite.failures.size(), " failures")
		failed = failed or not suite.failures.is_empty()
		suite = null
	quit(1 if failed else 0)
