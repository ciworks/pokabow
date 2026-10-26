extends SceneTree
## Focused in-game Table Level chip check at phone widths.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var suite = load("res://tests/integration/test_game_screen.gd").new()
	suite.test_table_level_chip_tracks_authoritative_player_level()
	var screen: Control = load("res://scenes/game/game_screen.tscn").instantiate()
	root.add_child(screen)
	screen.call("set_player_level", 12)
	var badge: PanelContainer = screen.get_node("Root/Column/Hud/HumanScorePanel/HumanScoreBox/LevelBadge") as PanelContainer
	var app = load("res://scripts/presentation/app_root.gd").new()
	app.game_screen = screen
	app._on_progression_received({"level": 13})
	suite.check_eq((badge.get_node("LevelText") as Label).text, "Lv 13",
		"a fresh progression response updates an open match")
	app.free()
	for dimensions: Vector2i in [Vector2i(320, 640), Vector2i(390, 844), Vector2i(540, 960)]:
		root.size = dimensions
		await process_frame
		var art: Control = badge.get_parent() as Control
		var rect: Rect2 = badge.get_global_rect()
		var portrait: TextureRect = art.get_node("Portrait") as TextureRect
		suite.check(rect.position.x >= 0.0 and rect.end.x <= dimensions.x,
			"level chip stays in the viewport at %s" % dimensions)
		suite.check(rect.position.y >= art.get_global_rect().position.y and rect.end.y <= art.get_global_rect().end.y,
			"level chip stays in the score header at %s" % dimensions)
		suite.check(rect.intersects(portrait.get_global_rect()), "level chip overlays the avatar at %s" % dimensions)
	screen.queue_free()
	for message: String in suite.failures:
		push_error(message)
	print("[avatar level] %d assertions, %d failures" % [suite.assertions, suite.failures.size()])
	quit(0 if suite.failures.is_empty() else 1)
