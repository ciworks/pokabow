extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var unit: TestCase = load("res://tests/unit/test_tile_source.gd").new()
	unit.call("test_public_remaining_faces_track_draws_without_exposing_order")
	var online: TestCase = load("res://tests/integration/test_online_play.gd").new()
	online.call("test_private_views_and_opposite_seats")
	for failure: String in unit.failures:
		push_error(failure)
	for failure: String in online.failures:
		push_error(failure)
	print("[Tile pot rules QA] %d assertions, %d failures" % [unit.assertions + online.assertions, unit.failures.size() + online.failures.size()])
	quit(0 if unit.failures.is_empty() and online.failures.is_empty() else 1)
