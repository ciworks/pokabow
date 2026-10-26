extends SceneTree
## Rendered splash QA: responsive typography and the real startup warm-up/hold.
## Set SPLASH_QA_DIR to save screenshots. Run with the Compatibility renderer.
class ObservedRoot extends AppRoot:
	var handed_over: bool = false
	func _after_splash() -> void:
		# Observe the real callback without reading accounts or making API requests.
		handed_over = true

var failures: int = 0
var assertions: int = 0

func _initialize() -> void:
	_run.call_deferred()

func verify(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame: int in range(5):
		await process_frame

func capture(name: String) -> void:
	var destination: String = OS.get_environment("SPLASH_QA_DIR")
	if destination.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(destination.path_join(name + ".png")) == OK, "Capture " + name)

func _run() -> void:
	var suite: TestCase = load("res://tests/unit/test_project_bootstrap.gd").new()
	for method: Dictionary in suite.get_method_list():
		if String(method.name).begins_with("test_") and method.name != "test_app_root_scene_has_required_layers":
			suite.call(method.name)
	assertions += suite.assertions
	failures += suite.failures.size()
	for failure: String in suite.failures:
		push_error(failure)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i.ZERO
	var splash: Control = load("res://scenes/splash/splash_screen.tscn").instantiate()
	root.add_child(splash)
	var column: VBoxContainer = splash.get_node("CenterContainer/TitleBlock")
	var progress: ProgressBar = column.get_node("LoadingProgress")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(390, 844), Vector2i(540, 960), Vector2i(540, 1200)]:
		root.size = dimensions
		await settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		for name: String in ["Logo", "Brand", "Tagline", "Hero", "LoadingProgress", "LoadingCaption"]:
			var node: Control = column.get_node(name)
			verify(bounds.encloses(node.get_global_rect()), name + " fits " + str(dimensions))
			if node is Label:
				var label := node as Label
				var font: Font = label.get_theme_font("font")
				verify(font.get_font_name().contains("Fredoka"), name + " uses real Fredoka")
				verify(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x <= label.size.x + 1, name + " has no clipped text")
		verify(column.get_node("Hero").get_global_rect().end.y <= progress.global_position.y, "Hero does not overlap progress")
		progress.value = 100
		await capture("splash-%dx%d" % [dimensions.x, dimensions.y])
	root.size = Vector2i(360, 800)
	root.content_scale_size = Vector2i(540, 1200)
	await settle()
	await capture("splash-phone-360x800")
	splash.free()
	root.content_scale_size = Vector2i.ZERO
	var chibi: Control = load("res://scenes/splash/chibi_splash_screen.tscn").instantiate()
	root.add_child(chibi)
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(390, 844), Vector2i(540, 960)]:
		root.size = dimensions
		await settle()
		var logo: TextureRect = chibi.get_node("Logo") as TextureRect
		var viewport_bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		verify(viewport_bounds.encloses(logo.get_global_rect()), "CHIBI logo fits " + str(dimensions))
		verify(logo.get_global_rect().get_center().distance_to(viewport_bounds.get_center()) < 1.0, "CHIBI logo is centered " + str(dimensions))
		await capture("chibi-%dx%d" % [dimensions.x, dimensions.y])
	chibi.free()
	var app: Node = load("res://scenes/app/app_root.tscn").instantiate()
	app.set_script(ObservedRoot)
	var startup_progress: ProgressBar = app.get_node("SceneHost/SplashScreen/CenterContainer/TitleBlock/LoadingProgress")
	var samples: Array[float] = []
	startup_progress.value_changed.connect(func(value: float) -> void: samples.append(value))
	var start: int = Time.get_ticks_msec()
	root.add_child(app)
	verify(app.get_node_or_null("SceneHost/ChibiSplashScreen") != null, "CHIBI splash starts before the welcome splash")
	verify(not (app.get_node("SceneHost/SplashScreen") as Control).visible, "Welcome splash starts hidden")
	# Check layers on the complete startup fixture: the synchronous bootstrap test
	# tears down audio preloading mid-frame.
	for path: String in ["SceneHost", "SceneHost/SplashScreen", "OverlayLayer", "AccessibilityLayer"]:
		verify(app.get_node_or_null(path) != null, "Bootstrap layer: " + path)
	while not app.handed_over and Time.get_ticks_msec() - start < 15000:
		await process_frame
	verify(app.handed_over, "Real startup warm-up and splash hold reach the handoff")
	verify(app.get_node_or_null("SceneHost/ChibiSplashScreen") == null, "CHIBI splash clears before handoff")
	verify((app.get_node("SceneHost/SplashScreen") as Control).visible, "Welcome splash appears after CHIBI")
	verify(startup_progress.value == 100, "Audio, tile art and shader warm-up reach completion")
	verify(samples.size() > 4, "Indicator receives actual startup progress")
	verify(Time.get_ticks_msec() - start >= 1200, "Existing branding hold preserved")
	verify(app.get_node_or_null("SplashHold") != null, "Existing startup timer retained")
	await capture("splash-startup-complete")
	app.queue_free()
	await settle()
	print("[splash QA] %d assertions, %d failures" % [assertions, failures])
	quit.call_deferred(0 if failures == 0 else 1)

