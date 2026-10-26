extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var assertions: int = 0
	var failures: int = 0
	for path: String in [
		"res://tests/unit/test_turn_timer.gd",
		"res://tests/integration/test_online_play.gd",
	]:
		var suite: RefCounted = load(path).new()
		for method: Dictionary in suite.get_method_list():
			var name: String = String(method.name)
			if name.begins_with("test_"):
				suite.call(name)
		for failure: String in suite.failures:
			push_error(failure)
		assertions += suite.assertions
		failures += suite.failures.size()
	var screen_suite: RefCounted = load("res://tests/integration/test_game_screen.gd").new()
	for name: String in [
		"test_turn_strip_stays_untimed_while_player_thinks",
		"test_turn_strip_uses_concept_style_without_a_countdown",
		"test_the_summary_panel_shows_the_final_breakdown_and_restarts",
	]:
		screen_suite.call(name)
	for failure: String in screen_suite.failures:
		push_error(failure)
	assertions += screen_suite.assertions
	failures += screen_suite.failures.size()
	print("[untimed turns] %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
