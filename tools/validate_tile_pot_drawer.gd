extends Node

var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var previous_dark: bool = AppearanceSettings.dark_mode
	if OS.get_environment("POT_QA_DARK") == "1":
		AppearanceSettings.dark_mode = true
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	add_child(screen)
	var controller := GameSessionController.new()
	controller.save_path = "user://tile_pot_drawer_qa.json"
	screen.add_child(controller)
	screen.attach_controller(controller)
	controller.start_new_match("tile-pot-drawer-qa", 42)
	var nav: GameBottomNavigation = screen.bottom_navigation
	var drawer: TilePotDrawer = screen.tile_pot_drawer
	_check(not nav.buttons.has(&"Menu") and nav.buttons.has(&"Pot"), "Pot replaces bottom Menu")
	_check(nav.get_node("Actions").get_child(4) == nav.buttons[&"Pot"], "Pot is the rightmost action")
	_check(controller.remaining_tiles() == 40, "twelve opening tiles leave 40 in the pot")
	_check(nav.get_node("Actions/PotButton/Content/IconSurface/IconCenter/Icon/PotCount").text == "40", "sack shows the live count")
	var faces: Array[Dictionary] = controller.remaining_tile_faces()
	_check(faces.size() == controller.remaining_tiles(), "inventory matches pot count")
	for face: Dictionary in faces:
		_check(not face.has("tile_id"), "inventory has no draw-order tile ID")
	nav.buttons[&"Pot"].pressed.emit()
	_check(drawer.is_open and drawer.visible, "Pot opens the bottom sheet")
	_check(drawer.displayed_count() == 40, "drawer renders every remaining face")
	var first_tile := drawer.get_node("PotSheet/PotContent/PotScroll/PotGrid/PotTile0") as TilePotTileView
	_check(first_tile != null and first_tile._tile != null and first_tile._tile.get_base_edges().size() == 4, "tile painter receives the actual face and four edges")
	var capture_path: String = OS.get_environment("POT_QA_CAPTURE")
	if not capture_path.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(get_viewport().get_texture().get_image().save_png(capture_path) == OK, "open drawer captured")
	var source: TileSource = controller.get_session().get_tile_source()
	var removed: TileDefinition = source.draw()
	controller.state_changed.emit()
	_check(removed != null and controller.remaining_tiles() == 39, "draw consumes one pot tile")
	_check(drawer.displayed_count() == 39, "open drawer refreshes after a draw")
	_check(nav.get_node("Actions/PotButton/Content/IconSurface/IconCenter/Icon/PotCount").text == "39", "sack count refreshes after a draw")
	_check(source.return_to_pot(removed), "drawn tile can return during a swap")
	controller.state_changed.emit()
	_check(drawer.displayed_count() == 40, "return restores the visible inventory")
	(drawer.get_node("PotSheet/PotContent/PotHeader/ClosePotButton") as Button).pressed.emit()
	_check(not drawer.is_open, "close action dismisses drawer")
	var closed_capture: String = OS.get_environment("POT_QA_CLOSED_CAPTURE")
	if not closed_capture.is_empty() and DisplayServer.get_name() != "headless":
		var settle: Tween = create_tween()
		settle.tween_interval(TilePotDrawer.SLIDE_SECONDS + 0.05)
		await settle.finished
		await RenderingServer.frame_post_draw
		_check(get_viewport().get_texture().get_image().save_png(closed_capture) == OK, "closed bar captured")
	(screen.get_node("%HeaderSpacer") as Button).pressed.emit()
	_check(screen.command_drawer.is_open, "top-right menu remains available")
	screen.command_drawer.set_open(false, false)
	_check((screen.get_node("%HeaderSpacer") as Button).has_focus(), "menu close returns focus to the header")
	var turn: TurnState = controller.get_session().get_turn_state()
	turn.active_player_id = TurnEnums.AI_PLAYER_ID
	controller.state_changed.emit()
	_check(not nav.buttons[&"Pot"].disabled, "Pot stays available off-turn")
	turn.active_player_id = TurnEnums.HUMAN_PLAYER_ID
	controller.state_changed.emit()
	drawer.set_inventory([], 0)
	_check(drawer.displayed_count() == 0 and drawer.get_node("PotSheet/PotContent/PotEmptyMessage").visible, "empty pot has a clear state")
	var online: Dictionary = OnlineRules.execute({"action": "create", "matchId": "tile-pot-online-qa", "seed": 42})
	_check(online.has("views"), "online server creates public views")
	if online.has("views"):
		var a: Dictionary = online.views.human
		var b: Dictionary = online.views.ai
		_check(a.potTiles.size() == a.remainingTiles and b.potTiles == a.potTiles, "both online seats see the same inventory")
		_check(not JSON.stringify(a.potTiles).contains("tile_id"), "online inventory omits actual tile IDs")
		a["matchId"] = "tile-pot-online-qa"
		var view: OnlineSessionView = OnlineSessionView.from_response(a)
		_check(view != null and view.remaining_tile_faces().size() == view.remaining_tile_count(), "online client parses the public inventory")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(540, 960)]:
		get_window().size = dimensions
		await get_tree().process_frame
		drawer.set_open(true, false)
		var sheet: Control = drawer.get_node("PotSheet") as Control
		_check(Rect2(Vector2.ZERO, drawer.size).encloses(Rect2(sheet.position, sheet.size)), "bottom sheet fits %s" % dimensions)
		_check(sheet.size.y >= 300.0, "bottom sheet leaves usable scroll area at %s" % dimensions)
		drawer.set_open(false, false)
	_check(controller.resign(), "active match can end normally")
	_check(nav.buttons[&"Pot"].disabled and not drawer.is_open, "Pot closes and disables after game over")
	screen.queue_free()
	AppearanceSettings.dark_mode = previous_dark
	print("[Tile pot drawer QA] %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
