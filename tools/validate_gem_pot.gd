extends SceneTree

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var suite: TestCase = load("res://tests/unit/test_gem_pot.gd").new()
	for method: Dictionary in suite.get_method_list():
		var name: String = String(method.name)
		if name.begins_with("test_"):
			suite.call(name)
	for failure: String in suite.failures:
		push_error(failure)
	print("[gem pot] %d assertions, %d failures" % [suite.assertions, suite.failures.size()])
	quit(0 if suite.failures.is_empty() else 1)
