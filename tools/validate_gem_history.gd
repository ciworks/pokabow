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
	for frame: int in range(3):
		await get_tree().process_frame


func _run() -> void:
	var prior_dark: bool = AppearanceSettings.dark_mode
	if OS.get_environment("GEM_HISTORY_QA_DARK") == "1":
		AppearanceSettings.set_dark_mode(true)
	var window := get_tree().root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = Vector2i.ZERO
	var screen: GemHistoryScreen = load("res://scenes/hub/gem_history_screen.tscn").instantiate()
	window.add_child(screen)
	await _settle()
	_check(screen._balance.text == "—", "No invented Gem balance before loading")
	screen.set_gem_wallet({"balance": 0, "transactions": []})
	_check(screen._balance.text == "0", "Confirmed zero balance appears")
	_check(screen._status.text.contains("No confirmed"), "Empty history is explained")
	var entries: Array = [
		{"kind": "online_pot", "amount": 24, "createdAt": "2026-10-24T12:00:00Z"},
		{"kind": "verified_ai_pot", "amount": 12, "createdAt": "2026-10-23T12:00:00Z"},
		{"kind": "rewarded_ad", "amount": 20, "createdAt": "2026-10-22T12:00:00Z"},
		{"kind": "purchase", "amount": 100, "createdAt": "2026-10-21T12:00:00Z"},
	]
	screen.set_gem_wallet({"balance": 1156, "transactions": entries})
	_check(screen._balance.text == "1,156", "Balance follows server data")
	_check(screen._history.get_child_count() == 4, "Every supplied transaction has a row")
	_check(_row_source(screen, 0) == "Online game pot",
		"Game source is named")
	_check(_row_source(screen, 2) == "Advert reward",
		"Advert source is named")
	_check(_row_source(screen, 3) == "Gem purchase",
		"Purchase source is named")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(390, 844), Vector2i(540, 960)]:
		window.size = dimensions
		await _settle()
		var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check(viewport.encloses(screen._scroll.get_global_rect()), "History viewport fits %s" % dimensions)
		_check(screen._scroll.get_h_scroll_bar().max_value <= screen._scroll.size.x + 1,
			"No horizontal history scrolling at %s" % dimensions)
		var capture_path := OS.get_environment("GEM_HISTORY_QA_CAPTURE")
		if dimensions == Vector2i(390, 844) and not capture_path.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			_check(window.get_texture().get_image().save_png(capture_path) == OK,
				"Gem history preview saved")
	screen.queue_free()
	await _settle()
	var app: AppRoot = load("res://scenes/app/app_root.tscn").instantiate()
	window.add_child(app)
	_check(app.show_hub(), "Hub opens")
	(app.hub_screen.get_node("%GemBalanceButton") as Button).pressed.emit()
	_check(is_instance_valid(app.gem_history_screen), "Gem chip opens history")
	_check(app.store_screen == null, "Gem chip does not open the shop")
	app._on_gem_wallet_received({"balance": 7, "transactions": []})
	_check(app.gem_history_screen._balance.text == "7", "Wallet updates reach history")
	app.gem_history_screen.back_requested.emit()
	await _settle()
	_check(app.gem_history_screen == null and app.hub_screen.visible, "Back returns to hub")
	_check(app.show_profile(), "Profile opens")
	_check(app.profile_screen.find_child("ConfirmedGems", true, false) == null,
		"Gem information is absent from My Profile")
	app.queue_free()
	AppearanceSettings.set_dark_mode(prior_dark)
	print("[gem history] %d assertions, %d failures" % [assertions, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _row_source(screen: GemHistoryScreen, index: int) -> String:
	var card := screen._history.get_child(index) as PanelContainer
	var row := card.get_child(0) as HBoxContainer
	var description := row.get_child(0) as VBoxContainer
	return (description.get_child(0) as Label).text
