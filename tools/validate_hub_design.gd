extends SceneTree
## Hub layout and existing command routing; no account/network/save mutations.
## HUB_QA_DIR enables PNG capture when running with a rendering display.
var failures: Array[String] = []
var assertions: int = 0

func _initialize() -> void:
	call_deferred("_run")

func verify(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for i: int in range(5):
		await process_frame

func capture(label: String) -> void:
	var destination: String = OS.get_environment("HUB_QA_DIR")
	if DisplayServer.get_name() == "headless" or destination.is_empty():
		return
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(destination.path_join(label + ".png"))
	verify(error == OK, "Capture saved: " + label)

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(540, 960)
	var text_server: TextServer = TextServerManager.get_primary_interface()
	var expected_weights: Dictionary = {"Regular": 400, "Medium": 500, "Semibold": 600, "Bold": 700}
	for style: String in expected_weights:
		var font: Font = load("res://assets/fonts/fredoka/Fredoka-%s.tres" % style)
		for rid: RID in font.get_rids():
			var actual: Dictionary = text_server.font_get_variation_coordinates(rid)
			verify(actual.get(text_server.name_to_tag("wght"), 0) == expected_weights[style], style + " resolves the requested weight in the renderer")
	var hub: HubScreen = load("res://scenes/hub/hub_screen.tscn").instantiate()
	root.add_child(hub)
	await settle()
	for name: String in ["ProfileButton", "SettingsButton", "SoundButton"]:
		var icon_button: Button = hub.get_node("%" + name)
		verify(not icon_button.expand_icon, name + " keeps its icon centered within the touch target")
		verify(icon_button.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER, name + " centers its icon alignment")
		verify(icon_button.get_theme_color("icon_hover_color") == Color("#173D42"), name + " hover tint follows the centered ink icon")
	var games: Array[Dictionary] = [
		{"kind": "ai", "id": "qa-ai", "path": "user://qa-only.json", "opponent": "AI Rival", "score": "You 128  |  Rival 96"},
		{"kind": "online", "id": "qa-online", "path": "", "opponent": "A player with a very long display name", "score": "You 99999  |  A player with a very long display name 88888"},
		{"kind": "ai", "id": "qa-third", "path": "user://qa-third.json", "opponent": "Another rival", "score": "You 8  |  Rival 12"},
	]
	var requests: Array[String] = []
	hub.play_requested.connect(func() -> void: requests.append("play"))
	hub.profile_requested.connect(func() -> void: requests.append("profile"))
	hub.achievements_requested.connect(func() -> void: requests.append("achievements"))
	hub.shop_requested.connect(func() -> void: requests.append("shop"))
	hub.tournaments_requested.connect(func() -> void: requests.append("tournaments"))
	hub.resume_game_requested.connect(func(kind: String, id: String, path: String) -> void: requests.append(kind + "|" + id + "|" + path))
	verify(hub.get_node_or_null("%OnlineButton") == null, "Hub has one play action")
	verify((hub.get_node("%PlayButton") as Button).text == "Play Now", "Primary action is Play Now")
	for name: String in ["PlayButton", "ProfileButton", "AchievementsButton"]:
		hub.get_node("%" + name).pressed.emit()
	verify(requests == ["play", "profile", "achievements"], "Navigation signals route once")
	hub.get_node("%ShopButton").pressed.emit()
	verify(requests.back() == "shop", "Shop opens its own destination")
	hub.get_node("%TournamentsButton").pressed.emit()
	verify(requests.back() == "tournaments", "Tournaments opens its placeholder destination")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(390, 844), Vector2i(540, 960), Vector2i(540, 1200)]:
		root.size = dimensions
		await settle()
		var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
		for count: int in [0, 1, 3]:
			hub.set_active_games(games.slice(0, count))
			hub.get_node("%PageScroll").scroll_vertical = 0
			await settle()
			verify(hub.get_node("%ActiveGameList").get_child_count() == mini(count, 1), "Compact hub shows at most one saved game")
			verify(hub.get_node("%ActiveGamesPanel").visible == (count > 0), "No fictitious resume card")
			var fill: StyleBoxFlat = hub.get_node("%PlayButton").get_theme_stylebox("normal")
			verify(fill.bg_color == Color("#F4C86A"), "Play Now stays honey with or without saved games")
			for name: String in ["GemBalanceButton", "ShopButton", "ProfileButton", "SettingsButton", "SoundButton", "HomeButton", "AchievementsButton", "TournamentsButton"]:
				var button: Control = hub.get_node("%" + name)
				verify(viewport.encloses(button.get_global_rect()), name + " stays visible at " + str(dimensions))
				verify(button.size.x >= 48 and button.size.y >= 48, name + " touch target")
			for name: String in ["Hero", "Brand", "PlayButton", "ActiveGamesPanel"]:
				var control: Control = hub.get_node("%" + name)
				if control.is_visible_in_tree():
					verify(control.get_global_rect().end.x <= dimensions.x, name + " fits width")
			for name: String in ["Brand"]:
				var label: Label = hub.get_node("%" + name)
				var font: Font = label.get_theme_font("font")
				verify(font.get_font_name().contains("Fredoka"), name + " resolves Fredoka")
				for line: String in label.text.split("\n"):
					verify(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x <= label.size.x + 1, name + " text fits")
			for name: String in ["HomeButton", "AchievementsButton", "TournamentsButton"]:
				var button: Button = hub.get_node("%" + name)
				var caption: Label = button.get_node("Contents/Caption")
				verify(caption.get_minimum_size().x <= button.size.x + 1, name + " caption fits")
			var play_button: Button = hub.get_node("%PlayButton") as Button
			var play_width: float = play_button.get_theme_font("font").get_string_size(play_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, play_button.get_theme_font_size("font_size")).x
			verify(play_width + play_button.get_theme_stylebox("normal").get_minimum_size().x <= play_button.size.x + 1, "Play Now text fits")
			var page_scroll: ScrollContainer = hub.get_node("%PageScroll")
			verify(page_scroll.get_h_scroll_bar().max_value <= page_scroll.size.x + 1, "No horizontal scroll")
			if count == 1:
				var resume: Button = hub.get_node("%ActiveGameList").get_child(0).find_child("Resume", true, false)
				verify(resume.size.y >= 48, "Resume touch target")
				if dimensions.y >= 800:
					verify(page_scroll.get_global_rect().encloses(resume.get_global_rect()), "Resume above fold")
				resume.pressed.emit()
				verify(requests.back() == "ai|qa-ai|user://qa-only.json", "Resume retains selected match identity")
			if dimensions == Vector2i(540, 960) or dimensions == Vector2i(360, 800):
				await capture("hub-%dx%d-%d-games" % [dimensions.x, dimensions.y, count])
		hub.get_node("%PageScroll").scroll_vertical = 9999
		await settle()
		hub.get_node("%HomeButton").pressed.emit()
		verify(hub.get_node("%PageScroll").scroll_vertical == 0, "Home returns to top")
		hub.open_settings()
		await settle()
		verify(hub.get_node("%SettingsScroll").scroll_vertical == 0, "Settings reopens at the top")
		verify(viewport.encloses(hub.get_node("%SettingsPanel").get_global_rect()), "Settings fits viewport")
		verify(viewport.encloses(hub.get_node("%SettingsCloseButton").get_global_rect()), "Settings close stays visible")
		if dimensions == Vector2i(360, 800):
			await capture("hub-settings-360x800")
		hub.close_settings()
		verify(not hub.is_settings_open(), "Settings closes")
	# Actual game stretch: 540 logical pixels on a 360px-wide, tall phone.
	root.size = Vector2i(360, 800)
	root.content_scale_size = Vector2i(540, 1200)
	hub.set_active_games(games.slice(0, 1))
	await settle()
	for name: String in ["ProfileButton", "SettingsButton", "SoundButton", "PlayButton"]:
		var control: Control = hub.get_node("%" + name)
		verify(control.size.y * 360.0 / 540.0 >= 48, name + " physical phone touch target")
	var phone_resume: Button = hub.get_node("%ActiveGameList").get_child(0).find_child("Resume", true, false)
	verify(phone_resume.size.y * 360.0 / 540.0 >= 48, "Physical phone resume target")
	await capture("hub-phone-360x800")
	var suite = load("res://tests/integration/test_active_games.gd").new()
	suite.test_hub_prioritises_one_game_and_keeps_other_games_reachable()
	assertions += suite.assertions
	failures.append_array(suite.failures)
	hub.free()
	print("HUB DESIGN: ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

