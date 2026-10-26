extends "res://tests/harness/test_runner.gd"

## Fast, account-free contract checks: godot --headless --path . --script
## res://tools/validate_api_clients.gd
func _initialize() -> void:
	_run_when_ready.call_deferred()


func _run_when_ready() -> void:
	quit(_run_suites())


func _collect_test_scripts() -> PackedStringArray:
	return PackedStringArray([
		"res://tests/unit/test_game_api_client.gd",
		"res://tests/unit/test_gem_wallet_api_client.gd",
		"res://tests/integration/test_authentication_recovery.gd",
		"res://tests/integration/test_matchmaking.gd",
		"res://tests/unit/test_account_deletion.gd",
	])
