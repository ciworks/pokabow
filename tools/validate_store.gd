extends Node

var failures: int = 0
var assertions: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)


func _settle() -> void:
	for frame: int in range(4):
		await get_tree().process_frame


func _run() -> void:
	var prior_dark: bool = AppearanceSettings.dark_mode
	if OS.get_environment("STORE_QA_DARK") == "1":
		AppearanceSettings.set_dark_mode(true)
	var window: Window = get_tree().root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = Vector2i.ZERO
	var store: StoreScreen = load("res://scenes/store/store_screen.tscn").instantiate()
	window.add_child(store)
	await _settle()
	_check(store._balance.text == "—", "Store does not show a fictitious balance")
	_check(store._pack_buttons.size() == 4, "Four paid packs appear")
	_check(store._pack_buttons.map(func(button: Button) -> String: return button.text) == ["£0.99", "£2.99", "£5.99", "£9.99"],
		"Placeholder prices match the approved concept")
	store.set_gem_wallet({"balance": 1240, "transactions": []})
	_check(store._balance.text == "1,240" and store._mini_balance.text == "1,240",
		"Both balances follow confirmed wallet data")
	store.set_rewarded_ad_status({"enabled": true, "available": true})
	_check(not store._ad_button.disabled, "Available daily ad can be watched")
	var ad_requests: Array[String] = []
	store.ad_requested.connect(func() -> void: ad_requests.append("requested"))
	store._ad_button.pressed.emit()
	_check(ad_requests.size() == 1 and store._ad_button.disabled and store._balance.text == "1,240",
		"Ad request waits for verified server credit")
	store.set_rewarded_ad_status({"enabled": true, "available": false,
		"nextAvailableAtUnix": int(Time.get_unix_time_from_system()) + 86400})
	_check(store._ad_button.disabled and store._ad_status.text.contains("Used today"),
		"Used daily reward is disabled and explained in its panel")
	store._pack_buttons[0].pressed.emit()
	_check(store.current_notice().contains("coming soon") and store._balance.text == "1,240",
		"Purchase placeholder cannot award Gems")
	var destinations: Array[String] = []
	store.home_requested.connect(func() -> void: destinations.append("home"))
	store.achievements_requested.connect(func() -> void: destinations.append("achievements"))
	(store._nav.get_node("HomeButton") as Button).pressed.emit()
	(store._nav.get_node("AchievementsButton") as Button).pressed.emit()
	_check(destinations == ["home", "achievements"], "Store navigation routes Home and Achievements")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(390, 844), Vector2i(540, 960), Vector2i(540, 1200)]:
		window.size = dimensions
		await _settle()
		var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check(viewport.encloses(store._nav.get_global_rect()), "Bottom navigation fits %s" % dimensions)
		_check(store._scroll.get_h_scroll_bar().max_value <= store._scroll.size.x + 1, "No horizontal scroll at %s" % dimensions)
		for button: Button in store._nav.get_children():
			_check(button.size.x >= 48 and button.size.y >= 64, "Navigation target fits %s" % dimensions)
		_check(store._ad_button.size.y >= 48, "Ad target is usable at %s" % dimensions)
		for button: Button in store._pack_buttons:
			_check(button.size.y >= 48, "Price target is usable at %s" % dimensions)
		var capture_path: String = OS.get_environment("STORE_QA_CAPTURE")
		if dimensions == Vector2i(390, 844) and not capture_path.is_empty() and DisplayServer.get_name() != "headless":
			store._notice.hide()
			store._scroll.scroll_vertical = 0
			await _settle()
			await RenderingServer.frame_post_draw
			_check(window.get_texture().get_image().save_png(capture_path) == OK, "Store capture saved")
	store.queue_free()
	await _settle()
	var app: AppRoot = load("res://scenes/app/app_root.tscn").instantiate()
	window.add_child(app)
	_check(app.show_hub(), "Hub opens")
	_check((app.hub_screen.get_node("%Brand") as Label).text == "POKABOW" and
		app.hub_screen.get_node_or_null("%Headline") == null,
		"Hub wordmark replaces the former headline")
	_check(app.hub_screen.get_node("%ShopButton").get_parent() == app.hub_screen.get_node("%Header"),
		"Shop lives in the hub header")
	_check((app.hub_screen.get_node("%GemBalanceButton") as Button).text == "—",
		"Hub does not invent a Gem balance")
	_check((app.hub_screen.get_node("%GemBalanceButton") as Button).icon.resource_path.contains("gem_balance"),
		"Hub chip uses the Shop Gem's faceted diamond outline")
	app.hub_screen.set_gem_wallet({"balance": 1240})
	_check((app.hub_screen.get_node("%GemBalanceButton") as Button).text == "1,240",
		"Hub chip displays the confirmed balance")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(390, 844)]:
		window.size = dimensions
		await _settle()
		var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
		for name: String in ["GemBalanceButton", "ShopButton", "ProfileButton", "SoundButton", "SettingsButton", "TournamentsButton"]:
			var button: Button = app.hub_screen.get_node("%" + name) as Button
			_check(viewport.encloses(button.get_global_rect()), "%s fits %s" % [name, dimensions])
			_check(button.size.x >= 48 and button.size.y >= 48, "%s remains touchable at %s" % [name, dimensions])
		var icon_left: float = (app.hub_screen.get_node("%GemBalanceButton") as Control).get_global_rect().position.x
		var icon_right: float = (app.hub_screen.get_node("%SettingsButton") as Control).get_global_rect().end.x
		_check(absf((icon_left + icon_right) * 0.5 - dimensions.x * 0.5) <= 1.5,
			"Hub header icons are centered at %s" % dimensions)
		var brand_left: float = (app.hub_screen.get_node("%Mark") as Control).get_global_rect().position.x
		var brand_right: float = (app.hub_screen.get_node("%Brand") as Control).get_global_rect().end.x
		_check(absf((brand_left + brand_right) * 0.5 - dimensions.x * 0.5) <= 1.5,
			"POKABOW logo is centered at %s" % dimensions)
		if dimensions == Vector2i(390, 844) and DisplayServer.get_name() != "headless":
			var hub_capture: String = OS.get_environment("HUB_QA_CAPTURE")
			if not hub_capture.is_empty():
				await RenderingServer.frame_post_draw
				_check(window.get_texture().get_image().save_png(hub_capture) == OK,
					"Hub preview saved")
	(app.hub_screen.get_node("%TournamentsButton") as Button).pressed.emit()
	await _settle()
	_check(app.hub_screen._notice_label.text.contains("coming soon"),
		"Hub Tournaments explains the placeholder")
	(app.hub_screen.get_node("%ShopButton") as Button).pressed.emit()
	_check(is_instance_valid(app.store_screen) and app.store_screen.visible, "Hub header Shop opens Store")
	(app.store_screen._nav.get_node("HomeButton") as Button).pressed.emit()
	await _settle()
	_check(app.store_screen == null and app.hub_screen.visible, "Store Home returns to Hub")
	app._on_hub_achievements_requested()
	_check(is_instance_valid(app.profile_screen), "Hub Achievements opens profile")
	if is_instance_valid(app.profile_screen):
		app.profile_screen.tournaments_requested.emit()
		await _settle()
		_check(is_instance_valid(app.hub_screen) and app.hub_screen.visible,
			"Achievements tournament placeholder returns to Hub")
		_check(app.hub_screen._notice_label.text.contains("coming soon"),
			"Tournament placeholder explains availability")
		(app.hub_screen.get_node("%GemBalanceButton") as Button).pressed.emit()
		_check(is_instance_valid(app.gem_history_screen) and app.gem_history_screen.visible,
			"Gem chip opens Gem history")
		if is_instance_valid(app.gem_history_screen):
			app.gem_history_screen.shop_requested.emit()
			await _settle()
			_check(is_instance_valid(app.store_screen) and app.store_screen.visible,
				"Gem history opens Store")
		if is_instance_valid(app.store_screen):
			(app.store_screen._nav.get_node("TournamentsButton") as Button).pressed.emit()
			await _settle()
			_check(app.store_screen == null and app.hub_screen._notice_label.text.contains("coming soon"),
				"Store Tournaments opens its placeholder")
			(app.hub_screen.get_node("%ShopButton") as Button).pressed.emit()
			(app.store_screen._nav.get_node("AchievementsButton") as Button).pressed.emit()
			await _settle()
			_check(app.store_screen == null and is_instance_valid(app.profile_screen),
				"Store Achievements returns to Achievements")
	app.queue_free()
	AppearanceSettings.set_dark_mode(prior_dark)
	print("[store] %d assertions, %d failures" % [assertions, failures])
	get_tree().quit(0 if failures == 0 else 1)
