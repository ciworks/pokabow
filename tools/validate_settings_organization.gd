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
	var window := get_tree().root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = Vector2i.ZERO
	var hub: HubScreen = load("res://scenes/hub/hub_screen.tscn").instantiate()
	window.add_child(hub)
	await _settle()
	var settings: VBoxContainer = hub.get_node("%SettingsBox")
	_check(_child_names(settings) == ["SettingsTitle", "PlayAlertsCard", "DisplayCard", "HelpCard"],
		"Settings groups are ordered by task")
	_check(_child_names(settings.get_node("PlayAlertsCard/PlayAlertsBox")) ==
		["PlayAlertsHeading", "SoundToggle", "MusicVolumeLabel", "MusicVolumeRow", "HapticsToggle", "PushNotificationsToggle"],
		"Play and alert controls stay together")
	_check(_child_names(hub.get_node("%MusicVolumeSlider").get_parent()) ==
		["MusicVolumeSlider", "MusicVolumeValue"], "Music slider and value stay together")
	_check(_child_names(settings.get_node("DisplayCard/DisplayBox")) ==
		["DisplayHeading", "DarkModeToggle", "ReducedMotionToggle"],
		"Display and access controls stay together")
	_check(_child_names(settings.get_node("HelpCard/HelpBox")) ==
		["HelpHeading", "HowToPlayButton", "ReportProblemButton", "ClearGameCacheButton"],
		"Help and storage controls stay together")
	_check(hub.get_node_or_null("%DeleteAccountButton") == null,
		"Account deletion is absent from Settings")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(540, 960), Vector2i(800, 360)]:
		window.size = dimensions
		hub.open_settings()
		await _settle()
		var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check(viewport.encloses((hub.get_node("%SettingsPanel") as Control).get_global_rect()),
			"Panel fits %s" % dimensions)
		_check(viewport.encloses((hub.get_node("%SettingsCloseButton") as Control).get_global_rect()),
			"Close stays visible at %s" % dimensions)
		_check((hub.get_node("%SettingsScroll") as ScrollContainer).get_h_scroll_bar().max_value <=
			(hub.get_node("%SettingsScroll") as ScrollContainer).size.x + 1,
			"Settings do not scroll horizontally at %s" % dimensions)
		for name: String in ["SoundToggle", "HapticsToggle", "PushNotificationsToggle", "DarkModeToggle", "ReducedMotionToggle"]:
			_check((hub.get_node("%" + name) as Control).custom_minimum_size.y >= 48,
				"%s remains touchable at %s" % [name, dimensions])
		_check((hub.get_node("%MusicVolumeSlider") as Control).custom_minimum_size.y >= 48,
			"Music slider remains touchable at %s" % dimensions)
		if dimensions == Vector2i(360, 800):
			await _capture(window, "SETTINGS_QA_LIGHT")
			(hub.get_node("%SettingsScroll") as ScrollContainer).scroll_vertical = 9999
			await _settle()
			await _capture(window, "SETTINGS_QA_LIGHT_BOTTOM")
		hub.close_settings()
	_check(not hub.is_settings_open(), "Close behaviour is retained")
	hub.open_settings()
	_check((hub.get_node("%SettingsBox") as Control).visible,
		"Settings content opens directly")
	hub.close_settings()
	AppearanceSettings.set_dark_mode(true)
	hub._apply_tabletop_style()
	window.size = Vector2i(360, 800)
	hub.open_settings()
	await _settle()
	await _capture(window, "SETTINGS_QA_DARK")
	(hub.get_node("%SettingsScroll") as ScrollContainer).scroll_vertical = 9999
	await _settle()
	await _capture(window, "SETTINGS_QA_DARK_BOTTOM")
	hub.queue_free()
	AppearanceSettings.set_dark_mode(previous_dark)
	print("[settings organization] %d assertions, %d failures" % [assertions, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _child_names(node: Node) -> Array[String]:
	var names: Array[String] = []
	for child: Node in node.get_children():
		names.append(child.name)
	return names


func _capture(window: Window, environment_key: String) -> void:
	var path := OS.get_environment(environment_key)
	if path.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_check(window.get_texture().get_image().save_png(path) == OK,
		"Settings preview saved")
