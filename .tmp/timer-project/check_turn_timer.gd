extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	var assertions: int = 0
	var count: int = 0
	for path: String in [
		"res://tests/unit/test_turn_timer.gd",
		"res://tests/unit/test_turn_manager.gd",
		"res://tests/unit/test_match_persistence.gd",
		"res://tests/integration/test_game_screen.gd",
		"res://tests/integration/test_ai_turn.gd",
	]:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failures.append("Could not compile " + path)
			continue
		var suite = script.new()
		for method: Dictionary in script.get_script_method_list():
			var method_name: String = method.name
			if not method_name.begins_with("test_"):
				continue
			var before: int = suite.assertions
			var before_failures: int = suite.failures.size()
			suite.call(method_name)
			count += 1
			if suite.assertions == before:
				failures.append(path + "::" + method_name + " aborted without assertions")
			print("PASS " if suite.failures.size() == before_failures else "FAIL ", path, "::", method_name)
		assertions += suite.assertions
		for failure: String in suite.failures:
			failures.append(path + " " + failure)
	for failure: String in failures:
		push_error(failure)
	print("TIMER CHECK: ", count, " tests, ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
