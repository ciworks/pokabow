extends Node

const T = preload("res://scripts/presentation/modern_tabletop_theme.gd")

var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var window: Window = get_tree().root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = Vector2i.ZERO
	window.size = Vector2i(360, 800)
	var profile: ProfileScreen = load("res://scenes/profile/profile_screen.tscn").instantiate()
	profile.avatar_store_path = "user://achievement_nav_unused.json"
	window.add_child(profile)
	profile.show_achievements_only(true)
	var browser: AchievementBrowser = profile.get_node("%AchievementsPage")
	for frame: int in range(5):
		await get_tree().process_frame

	var destinations: Array[String] = ["Home", "Achievements", "Tournaments"]
	_check(browser._nav.get_child_count() == destinations.size(), "Achievements navigation has the hub's three buttons")
	for index: int in range(destinations.size()):
		var destination: String = destinations[index]
		var button: Button = browser._nav.get_child(index) as Button
		var caption: Label = button.get_node("Contents/Caption") as Label
		var icon: TextureRect = button.get_node("Contents/Icon") as TextureRect
		_check(button.name == destination + "Button" and caption.text == destination,
			"Navigation order and captions match the hub")
		_check(icon.texture == T.icon_texture(destination.to_lower()), "Navigation uses the shared hub icon")
		_check(button.size.x >= 48.0 and button.size.y >= 64.0, "Navigation keeps hub-sized touch targets")
		_check(caption.get_theme_font("font") == (T.SEMIBOLD if destination == "Achievements" else T.MEDIUM),
			"Navigation caption weight matches selected state")
	_check(Rect2(Vector2.ZERO, Vector2(window.size)).encloses(browser._nav.get_global_rect()),
		"Navigation fits the phone viewport")
	_check(browser._nav.get_theme_constant("separation") == 8, "Navigation uses hub spacing")
	_check((browser._nav.get_node("AchievementsButton") as Button).tooltip_text.ends_with("current page"),
		"Achievements is identified as the current page")
	var hub: HubScreen = load("res://scenes/hub/hub_screen.tscn").instantiate()
	window.add_child(hub)
	hub.hide()
	for destination: String in destinations:
		var browser_button: Button = browser._nav.get_node(destination + "Button") as Button
		var hub_button: Button = hub.get_node("%" + destination + "Button") as Button
		var browser_caption: Label = browser_button.get_node("Contents/Caption") as Label
		var style_reference: String = "Home" if destination == "Achievements" else \
			"Achievements"
		var reference_button: Button = hub.get_node("%" + style_reference + "Button") as Button
		var hub_caption: Label = reference_button.get_node("Contents/Caption") as Label
		_check(browser_button.custom_minimum_size.y == hub_button.custom_minimum_size.y,
			"Navigation target height mirrors the hub")
		_check(browser_caption.get_theme_font("font") == hub_caption.get_theme_font("font") and
			browser_caption.get_theme_color("font_color") == hub_caption.get_theme_color("font_color"),
			"Navigation caption style mirrors the hub")
		_check((browser_button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color ==
			(reference_button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color,
			"Navigation selected surface mirrors the hub")
	hub.queue_free()

	var capture_path: String = OS.get_environment("ACHIEVEMENT_NAV_CAPTURE")
	if not capture_path.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(window.get_texture().get_image().save_png(capture_path) == OK, "Phone capture saved")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(390, 844), Vector2i(540, 960)]:
		window.size = dimensions
		for frame: int in range(3):
			await get_tree().process_frame
		_check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(browser._nav.get_global_rect()),
			"Navigation fits %s" % dimensions)
		for button: Button in browser._nav.get_children():
			_check(button.size.x >= 48.0 and button.size.y >= 64.0,
				"Navigation keeps touch targets at %s" % dimensions)

	var tournament_routes: Array[String] = []
	profile.tournaments_requested.connect(func() -> void: tournament_routes.append("tournaments"))
	(browser._nav.get_node("TournamentsButton") as Button).pressed.emit()
	_check(tournament_routes == ["tournaments"], "Tournaments follows the placeholder route")
	(browser._nav.get_node("AchievementsButton") as Button).pressed.emit()
	_check(browser.category.is_empty(), "Selected Achievements button returns to overview")
	var routes: Array[String] = []
	profile.back_requested.connect(func() -> void: routes.append("home"))
	(browser._nav.get_node("HomeButton") as Button).pressed.emit()
	_check(routes.has("home"), "Home follows the existing route")

	profile.queue_free()
	print("[achievement navigation] %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
