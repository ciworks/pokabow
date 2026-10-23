extends Node
## Runs matchmaking integration checks with project autoloads initialized.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var suite: TestCase = load("res://tests/integration/test_matchmaking.gd").new()
	for method: Dictionary in suite.get_method_list():
		if String(method.name).begins_with("test_"):
			suite.call(method.name)
	for failure: String in suite.failures:
		push_error(failure)
	var layout_failures: int = 0
	var root := get_tree().root
	root.content_scale_size = Vector2i.ZERO
	var screen: OpponentSelectionScreen = load("res://scenes/hub/opponent_selection_screen.tscn").instantiate()
	root.add_child(screen)
	screen.select_online()
	screen._on_matchmaking_changed("matched", "Opponent found", {"id": "layout-lobby", "canReady": true, "opponent": {"displayName": "Opponent"}})
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(390, 844), Vector2i(540, 960)]:
		root.size = dimensions
		await get_tree().process_frame
		await get_tree().process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		for button: Button in [screen.start_button, screen.cancel_match_button]:
			if not bounds.encloses(button.get_global_rect()) or button.size.y < 48.0:
				layout_failures += 1
				push_error("Online action outside touch-safe bounds at %s: %s" % [dimensions, button.name])
	screen.free()
	print("[Matchmaking] %d assertions, %d failures" % [suite.assertions, suite.failures.size() + layout_failures])
	get_tree().quit(0 if suite.failures.is_empty() and layout_failures == 0 else 1)
