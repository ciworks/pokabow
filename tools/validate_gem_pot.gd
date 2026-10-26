extends SceneTree

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var assertions: int = 0
	var failures: Array[String] = []
	for path: String in ["res://tests/unit/test_gem_pot.gd", "res://tests/unit/test_ai_gem_pot.gd"]:
		var suite: TestCase = load(path).new()
		for method: Dictionary in suite.get_method_list():
			var name: String = String(method.name)
			if name.begins_with("test_"):
				suite.call(name)
		assertions += suite.assertions
		failures.append_array(suite.failures)
	for failure: String in failures:
		push_error(failure)
	print("[gem pot] %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
