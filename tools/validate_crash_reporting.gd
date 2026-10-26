extends Node

var assertions: int = 0
var failures: int = 0


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
	var previous_dark: bool = AppearanceSettings.dark_mode
	var fixture := "user://crash-report-qa"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	var marker := fixture.path_join("marker.json")
	var pending := fixture.path_join("pending.json")
	var old_log := fixture.path_join("godot2026-10-24.log")
	var current_log := fixture.path_join("godot.log")
	_write(marker, '{"state":"active","startedAt":"2026-10-24T10:00:00Z"}')
	_write(old_log, "Previous session\nSCRIPT ERROR: example crash context\n")
	_write(current_log, "Current session only")
	var service := CrashReportService.new()
	service.marker_path = marker
	service.pending_path = pending
	service.log_directory = fixture
	add_child(service)
	service.begin_session()
	_check(service.has_pending_report(), "Unexpected foreground exit leaves a report")
	_check(String(service.pending_report().get("log", "")).contains("example crash context"),
		"Report uses the previous log, not the new session")
	_check(CrashReportService._read_json(marker).get("state") == "active",
		"New session is marked active")
	var report := CrashReportService.report_text("The board froze", "SCRIPT ERROR: example")
	_check(report.contains("The board froze") and report.contains("SCRIPT ERROR: example") and
		report.contains("App version:"), "Report includes player notes, log and app details")
	var uri := CrashReportService.email_uri(report)
	_check(uri.begins_with("mailto:support@pokabow.game?"), "Email is addressed to support")
	_check(uri.contains("body=") and uri.contains("The%20board%20froze"), "Email body is URL encoded")
	_check(not CrashReportService.sanitize_log("Bearer secret-token token=abc").contains("secret-token") and
		not CrashReportService.sanitize_log("Bearer secret-token token=abc").contains("token=abc"),
		"Common credential forms are removed from the log")
	_check(not CrashReportService.sanitize_log('{"password":"secret","access_token":"private"}').contains("secret") and
		not CrashReportService.sanitize_log('{"password":"secret","access_token":"private"}').contains("private"),
		"JSON credentials are removed from the log")
	service.dismiss_pending_report()
	_check(not service.has_pending_report() and not FileAccess.file_exists(pending),
		"Player can discard the saved report")
	service.queue_free()
	await _settle()
	_write(marker, '{"state":"background","startedAt":"2026-10-24T11:00:00Z"}')
	var background_service := CrashReportService.new()
	background_service.marker_path = marker
	background_service.pending_path = pending
	background_service.log_directory = fixture
	add_child(background_service)
	background_service.begin_session()
	_check(not background_service.has_pending_report(),
		"Normal mobile background termination does not claim a crash")
	background_service.queue_free()
	await _settle()
	var window := get_tree().root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = Vector2i.ZERO
	var screen: CrashReportScreen = load("res://scenes/hub/crash_report_screen.tscn").instantiate()
	window.add_child(screen)
	await _settle()
	screen.set_report({"log": "SCRIPT ERROR: test"}, true)
	_check(screen._log.text.contains("SCRIPT ERROR: test") and screen._discard.visible,
		"Screen shows the reviewable crash log")
	var drafts: Array[String] = []
	screen.email_requested.connect(func(value: String) -> void: drafts.append(value))
	screen._on_email_pressed()
	_check(drafts.size() == 1 and drafts[0].contains("No description supplied."),
		"Crash log can be reported without extra notes")
	screen._notes.text = "I tapped Play, then the app closed."
	screen._on_email_pressed()
	_check(drafts.size() == 2 and drafts[1].contains("I tapped Play"),
		"Description and log are prepared only after player action")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(540, 960)]:
		window.size = dimensions
		await _settle()
		var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check(viewport.encloses(screen._margin.get_global_rect()), "Report fits %s" % dimensions)
		_check(viewport.encloses((screen.find_child("EmailSupportButton", true, false) as Control).get_global_rect()),
			"Report action fits %s" % dimensions)
		if dimensions == Vector2i(360, 800):
			await _capture(window, "CRASH_QA_LIGHT")
			(screen.find_child("ReportScroll", true, false) as ScrollContainer).scroll_vertical = 9999
			await _settle()
			await _capture(window, "CRASH_QA_LIGHT_BOTTOM")
	screen.queue_free()
	await _settle()
	AppearanceSettings.set_dark_mode(true)
	var dark_screen: CrashReportScreen = load("res://scenes/hub/crash_report_screen.tscn").instantiate()
	window.add_child(dark_screen)
	dark_screen.set_report({"log": "SCRIPT ERROR: test"}, true)
	window.size = Vector2i(360, 800)
	await _settle()
	await _capture(window, "CRASH_QA_DARK")
	(dark_screen.find_child("ReportScroll", true, false) as ScrollContainer).scroll_vertical = 9999
	await _settle()
	await _capture(window, "CRASH_QA_DARK_BOTTOM")
	dark_screen.queue_free()
	await _settle()
	AppearanceSettings.set_dark_mode(previous_dark)
	var app: AppRoot = load("res://scenes/app/app_root.tscn").instantiate()
	window.add_child(app)
	_check(app.show_hub(), "Hub opens")
	app.hub_screen.open_settings()
	(app.hub_screen.get_node("%ReportProblemButton") as Button).pressed.emit()
	_check(is_instance_valid(app.crash_report_screen) and app.crash_report_screen.visible,
		"Settings opens the report screen")
	app.crash_report_screen.back_requested.emit()
	await _settle()
	_check(app.crash_report_screen == null and app.hub_screen.visible,
		"Report back action returns to the hub")
	app.queue_free()
	print("[crash reporting] %d assertions, %d failures" % [assertions, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


func _capture(window: Window, environment_key: String) -> void:
	var path := OS.get_environment(environment_key)
	if path.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_check(window.get_texture().get_image().save_png(path) == OK, "Report preview saved")
