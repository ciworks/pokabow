extends Node
## Checks the project version binding and bottom placement on phone layouts.

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)


func _run() -> void:
	var root := get_tree().root
	root.content_scale_size = Vector2i.ZERO
	var splash: Control = load("res://scenes/splash/splash_screen.tscn").instantiate()
	root.add_child(splash)
	var version_label := splash.get_node("%VersionLabel") as Label
	var caption := splash.get_node("CenterContainer/TitleBlock/LoadingCaption") as Label
	var version: String = String(ProjectSettings.get_setting("application/config/version", ""))
	_check(version == "1.0.0", "Project version has the initial semantic value")
	_check(version_label.text == "v" + version, "Splash reads the project version")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(390, 844), Vector2i(540, 960), Vector2i(540, 1200)]:
		root.size = dimensions
		await get_tree().process_frame
		await get_tree().process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check(bounds.encloses(version_label.get_global_rect()), "Version fits %s" % dimensions)
		_check(version_label.global_position.y >= caption.get_global_rect().end.y, "Version follows loading caption %s" % dimensions)
		_check(version_label.size.y > 0 and version_label.get_theme_font_size("font_size") >= 14, "Version stays readable %s" % dimensions)
	splash.free()
	ProjectSettings.set_setting("application/config/version", "1.2.3")
	var updated: Control = load("res://scenes/splash/splash_screen.tscn").instantiate()
	root.add_child(updated)
	_check((updated.get_node("%VersionLabel") as Label).text == "v1.2.3", "Changing Project Settings updates the splash without editing the scene")
	updated.free()
	ProjectSettings.set_setting("application/config/version", version)
	print("[Splash version] %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
