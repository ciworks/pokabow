extends "res://tests/harness/test_runner.gd"

## Fast, account-free contract checks: godot --headless --path . --script
## res://tools/validate_api_clients.gd
func _collect_test_scripts() -> PackedStringArray:
	return PackedStringArray(["res://tests/unit/test_game_api_client.gd"])
