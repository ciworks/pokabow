extends SceneTree
## Rendered catalogue/browser checks; fixtures never write unlocks or contact APIs.
var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame: int in range(5):
		await process_frame

func capture(name: String) -> void:
	var path: String = OS.get_environment("ACHIEVEMENT_QA_DIR")
	if path.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(path.path_join(name + ".png")) == OK, "Capture " + name)

func fixture() -> Array:
	return [
		{"id": "first_hand", "name": "First Hand", "description": "Score your first poker hand.", "unlocked": true},
		{"id": "straight", "name": "Straight", "description": "Score a straight.", "unlocked": false},
		{"id": "full_house", "name": "Full House", "description": "Score a full house.", "unlocked": true},
		{"id": "edge_cluster", "name": "Edge Cluster", "description": "Score an edge cluster.", "unlocked": false},
		{"id": "ai_victory", "name": "AI Victory", "description": "Win a match against the AI.", "unlocked": true},
	]

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(540, 960)
	var profile: ProfileScreen = load("res://scenes/profile/profile_screen.tscn").instantiate()
	profile.avatar_store_path = "user://achievements_qa_unused.json"
	root.add_child(profile)
	profile.show_achievements_only(true)
	var browser: AchievementBrowser = profile.get_node("%AchievementsPage")
	profile.set_achievement_rows(fixture())
	await settle()
	check(browser.rows.size() == 5, "Five real IDs remain visible")
	check(browser._unlocked(browser.rows) == 3, "Summary counts server unlocks")
	var route: Array[String] = []
	profile.back_requested.connect(func() -> void: route.append("home"))
	profile.achievement_refresh_requested.connect(func() -> void: route.append("retry"))
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(390, 844), Vector2i(540, 960), Vector2i(540, 1200)]:
		root.size = dimensions
		browser.show_overview()
		await settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		check(bounds.encloses(browser._nav.get_global_rect()), "Navigation fits " + str(dimensions))
		check(browser._scroll.get_h_scroll_bar().max_value <= browser._scroll.size.x + 1, "Overview has no horizontal overflow")
		for button: Button in browser._nav.get_children():
			check(button.size.y >= 48, "Navigation minimum touch height")
		await capture("overview-%dx%d" % [dimensions.x, dimensions.y])
		browser.select_category("Hands")
		await settle()
		check(browser._body.get_node("BadgeGrid").get_child_count() == 3, "Hands category includes all three known hands")
		check(browser._scroll.get_h_scroll_bar().max_value <= browser._scroll.size.x + 1, "Category has no horizontal overflow")
		browser.open_detail(browser.rows[1])
		await settle()
		check(bounds.encloses(browser._detail_panel.get_global_rect()), "Detail fits " + str(dimensions))
		check(browser._detail_status.text == "Locked", "Locked badge exposes requirement")
		check(browser._detail_copy.text == "Score a straight.", "Detail uses API description")
		await capture("detail-%dx%d" % [dimensions.x, dimensions.y])
		browser.go_back()
		check(not browser._detail.visible and browser.category == "Hands", "Detail back keeps category")
	var expanded: Array = fixture()
	for index: int in range(15):
		expanded.append({"id": "future_%d" % index, "name": "Future hand %02d" % index, "description": "An API-supplied requirement.", "category": "Hands", "unlocked": index % 2 == 0})
	expanded.append({"id": "unknown_new", "name": "New milestone", "description": "Future API achievement.", "unlocked": false})
	browser.set_rows(expanded)
	browser.select_category("Hands")
	await settle()
	check(browser.filtered_rows().size() == 18, "Future catalogue IDs included")
	var seen: Dictionary = {}
	for page_index: int in range(3):
		await settle()
		var grid: GridContainer = browser._body.get_node("BadgeGrid")
		check(grid.get_child_count() == 6, "Six badges per page")
		for card: Button in grid.get_children():
			seen[card.get_meta("achievement_id")] = true
		browser.change_page(1)
	check(seen.size() == 18, "Pagination reaches every badge once")
	check(browser.page == 2 and browser._next.disabled, "Last page is bounded")
	browser.select_filter("Locked")
	check(browser.page == 0, "Filter resets pagination")
	for row: Dictionary in browser.filtered_rows():
		check(not bool(row.unlocked), "Locked filter uses server state")
	browser.select_filter("All")
	browser._search_changed("future hand 14")
	check(browser.filtered_rows().size() == 1, "Case-insensitive name search")
	browser._search_changed("no such achievement")
	check(browser.filtered_rows().is_empty() and not browser._pages.visible, "No-results state")
	browser._search_changed("")
	browser.select_category("Milestones")
	check(browser.filtered_rows().size() == 1, "Unknown IDs have fallback category")
	browser.select_category("Hands")
	root.size = Vector2i(540, 960)
	await settle()
	await capture("expanded-hands-540x960")
	browser.set_rows(fixture())
	await settle()
	check(browser.page == 0 and browser.filtered_rows().size() == 3, "Catalogue shrink clamps page")
	browser.show_overview()
	browser.set_error("Offline. Retry when connected.")
	check(browser.rows.size() == 5, "Offline error retains loaded catalogue")
	await settle()
	await capture("offline-540x960")
	browser._retry()
	check(route.has("retry") and browser.loading, "Retry routes to catalogue refresh")
	browser.set_rows([])
	await settle()
	await capture("empty-540x960")
	check(browser.received and browser.rows.is_empty(), "Empty catalogue supported")
	browser.set_rows(fixture())
	browser._navigate("Profile")
	check(not browser.visible and profile.get_node("Title").visible, "Profile navigation restores profile")
	profile.show_achievements_only(true)
	browser._navigate("Home")
	check(route.has("home"), "Home routes through existing shell")
	root.size = Vector2i(360, 800)
	root.content_scale_size = Vector2i(540, 1200)
	await settle()
	await capture("overview-phone-360x800")
	browser.set_rows(expanded)
	browser.select_category("Hands")
	await settle()
	await capture("expanded-hands-phone-360x800")
	# Physical targets are checked after logical-to-device scaling, not just direct viewports.
	for button: Button in [browser._back, browser._search_button, browser._next, browser._previous]:
		check(button.size.x / browser._pixel_scale() >= 47.9 and button.size.y / browser._pixel_scale() >= 47.9, "48px physical touch target")
	var first: Button = browser._body.get_node("BadgeGrid").get_child(0)
	first.pressed.emit()
	check(browser._detail.visible, "Badge button opens the detail")
	var refreshed: Array = expanded.duplicate(true)
	refreshed[0]["unlocked"] = false
	browser.set_rows(refreshed)
	check(browser._detail_status.text == "Locked", "Open detail updates when server unlock state changes")
	browser.set_rows([])
	check(not browser._detail.visible, "Removed achievement closes its detail")
	var many_categories: Array = []
	for index: int in range(14):
		many_categories.append({"id": "category_test_%d" % index, "name": "Category badge", "category": "Collection %02d" % index, "unlocked": false})
	browser.set_rows(many_categories)
	browser.show_overview()
	await settle()
	check(browser._page_label.text == "1 of 3", "Overview paginates a large number of categories")
	browser.change_page(2)
	await settle()
	check(browser.page == 2, "Later category pages reachable")
	var dated: Array = fixture()
	dated[0]["unlockedAt"] = "2026-01-01T00:00:00Z"
	dated[2]["unlockedAt"] = "2026-03-01T00:00:00Z"
	dated[4]["unlockedAt"] = "2026-02-01T00:00:00Z"
	browser.set_rows(dated)
	await settle()
	var titles: Array[String] = []
	for child: Node in browser._body.get_children():
		if child is Label:
			titles.append(child.text)
	check(titles.has("Recently unlocked"), "Recent heading only when timestamps exist")
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(320, 568)
	var long_rows: Array = [{"id": "long", "name": "An achievement with a very long descriptive title that still needs to fit", "description": "A lengthy requirement. ".repeat(50), "unlocked": false}]
	browser.set_rows(long_rows)
	browser.select_category("Milestones")
	await settle()
	browser.open_detail(browser.rows[0])
	await settle()
	check(Rect2(Vector2.ZERO, Vector2(320, 568)).encloses(browser._detail_panel.get_global_rect()), "Long requirement remains inside small phone detail")
	await capture("long-detail-320x568")
	browser.go_back()
	# The catalogue transport surfaces unavailable/malformed responses to retry UI.
	var client := AchievementApiClient.new()
	root.add_child(client)
	var errors: Array[String] = []
	client.catalog_failed.connect(func(message: String) -> void: errors.append(message))
	client.fetch_catalog()
	check(errors.size() == 1, "Missing authentication reports an actionable state")
	client.access_token = "qa-only"
	var request := HTTPRequest.new()
	client.add_child(request)
	client._on_catalog_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "invalid".to_utf8_buffer(), request, "qa-only")
	check(errors.size() == 2, "Malformed catalogue reports error")
	await settle()
	client.queue_free()
	profile.queue_free()
	await settle()
	print("[achievements QA] %d assertions, %d failures" % [assertions, failures])
	quit.call_deferred(0 if failures == 0 else 1)

