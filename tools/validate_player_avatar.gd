extends SceneTree
## Focused avatar checks plus the existing read-only profile API regression.


func _initialize() -> void:
	var suite = load("res://tests/unit/test_player_avatar.gd").new()
	for method: Dictionary in suite.get_method_list():
		if String(method.name).begins_with("test_"):
			var before: int = suite.assertions
			suite.call(method.name)
			if suite.assertions == before:
				suite.failures.append("Test aborted: " + String(method.name))
	var api_suite = load("res://tests/unit/test_game_api_client.gd").new()
	api_suite.test_profile_refresh_is_available_and_account_fields_show_server_values()
	suite.failures.append_array(api_suite.failures)
	print("Avatar/profile assertions: %d; failures: %d" % [suite.assertions + api_suite.assertions, suite.failures.size()])
	for failure: String in suite.failures:
		push_error(failure)
	quit(0 if suite.failures.is_empty() else 1)
