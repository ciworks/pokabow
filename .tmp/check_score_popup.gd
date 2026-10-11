extends "res://tests/harness/test_runner.gd"

func _initialize() -> void:
	call_deferred("_run_ready")

func _run_ready() -> void:
	quit(_run_suites())

func _collect_test_scripts() -> PackedStringArray:
	return PackedStringArray(["res://tests/integration/test_game_screen.gd"])

func _test_method_names(_test_case: Object) -> PackedStringArray:
	return PackedStringArray([
		"test_committed_move_shows_one_total_popup",
		"test_empty_awards_show_no_total_popup",
		"test_command_drawer_opens_closes_and_returns_to_rack_for_swap",
	])
