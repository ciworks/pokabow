extends SceneTree
## Focused hub entry-point check; the chooser keeps AI and Online available.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var suite = load("res://tests/integration/test_matchmaking.gd").new()
	suite.test_hub_play_now_defaults_to_ai_and_keeps_online_available()
	root.content_scale_size = Vector2i.ZERO
	var hub: Control = load("res://scenes/hub/hub_screen.tscn").instantiate()
	root.add_child(hub)
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(390, 844), Vector2i(540, 960)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var play_button: Button = hub.get_node("%PlayButton") as Button
		var rect: Rect2 = play_button.get_global_rect()
		suite.check(rect.position.x >= 0.0 and rect.end.x <= dimensions.x,
			"Play Now fits the viewport at %s" % dimensions)
		suite.check(play_button.size.y >= 48.0, "Play Now keeps a usable target at %s" % dimensions)
	hub.free()
	for failure: String in suite.failures:
		push_error(failure)
	print("[hub play now] %d assertions, %d failures" % [suite.assertions, suite.failures.size()])
	quit(0 if suite.failures.is_empty() else 1)
