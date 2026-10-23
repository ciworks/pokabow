extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures: int = 0
	var assertions: int = 0
	for path: String in ["res://tests/integration/test_online_play.gd", "res://tests/integration/test_matchmaking.gd", "res://tests/unit/test_tile_source.gd"]:
		var suite: RefCounted = load(path).new()
		for method: Dictionary in suite.get_method_list():
			var name: String = String(method.name)
			if name.begins_with("test_"):
				suite.call(name)
		for failure: String in suite.failures:
			push_error(failure)
		failures += suite.failures.size()
		assertions += suite.assertions
	print("[online] %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
