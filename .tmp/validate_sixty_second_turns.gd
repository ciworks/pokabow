extends "res://tests/harness/test_runner.gd"


func _collect_test_scripts() -> PackedStringArray:
	return PackedStringArray([
		"res://tests/unit/test_turn_timer.gd",
		"res://tests/unit/test_turn_manager.gd",
		"res://tests/unit/test_match_persistence.gd",
		"res://tests/integration/test_game_screen.gd",
	])
