extends SceneTree

func _initialize() -> void:
	var suite: TestCase = load("res://tests/unit/test_ai_rival_catalog.gd").new()
	suite.test_bundled_roster_has_fifteen_stable_distinct_rivals()
	suite.test_api_catalogue_rejects_duplicate_or_unknown_identity()
	var api_suite: TestCase = load("res://tests/unit/test_ai_rival_api_client.gd").new()
	api_suite.test_named_rival_is_sent_and_rejected_create_stops_retrying()
	suite.assertions += api_suite.assertions
	suite.failures.append_array(api_suite.failures)
	for failure: String in suite.failures:
		push_error(failure)
	print("AI rival catalog: %d assertions, %d failures" % [suite.assertions, suite.failures.size()])
	quit(0 if suite.failures.is_empty() else 1)
