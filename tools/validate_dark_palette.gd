extends Node
## Focused dark-mode checks for hub and game action navigation.

const T = preload("res://scripts/presentation/modern_tabletop_theme.gd")

var failures: Array[String] = []
var assertions: int = 0
var root: Window


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _luminance(color: Color) -> float:
	var linear: Color = color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b


func _contrast(first: Color, second: Color) -> float:
	var a: float = _luminance(first)
	var b: float = _luminance(second)
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


func _capture(name: String) -> void:
	var directory: String = OS.get_environment("DARK_PALETTE_QA_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(directory.path_join(name + ".png")) == OK, name + " preview saved")


func _run() -> void:
	root = get_tree().root
	var original_mode: bool = AppearanceSettings.dark_mode
	AppearanceSettings.dark_mode = true
	root.size = Vector2i(360, 800)
	_check(_contrast(T.ink(), T.canvas()) >= 7.0, "main text clears 7:1 on canvas")
	_check(_contrast(T.muted(), T.canvas()) >= 4.5, "supporting text clears 4.5:1 on canvas")
	_check(_contrast(T.icon_ink(), T.canvas_alt()) >= 4.5, "icons clear 4.5:1 on raised surfaces")
	_check(_contrast(T.ink(), T.sage()) >= 4.5, "selected navigation text clears 4.5:1")
	_check(_contrast(T.on_primary(), T.honey()) >= 4.5, "primary button text clears 4.5:1")
	var hub: HubScreen = load("res://scenes/hub/hub_screen.tscn").instantiate()
	root.add_child(hub)
	for frame: int in range(3):
		await get_tree().process_frame
	for name: String in ["ShopButton", "ProfileButton", "SettingsButton", "SoundButton"]:
		var button: Button = hub.get_node("%" + name)
		_check(button.icon.resource_path.ends_with("_dark.svg"), name + " loads the light-stroke icon")
	_check((hub.get_node("%GemBalanceButton") as Button).icon.resource_path.ends_with("gem_balance_dark.svg"),
		"Gem balance uses the matching light-stroke diamond in dark mode")
	for name: String in ["HomeButton", "AchievementsButton", "TournamentsButton"]:
		var button: Button = hub.get_node("%" + name)
		var contents: VBoxContainer = button.get_node("Contents")
		_check(contents.get_child_count() == 2, name + " has one icon and caption")
		_check((contents.get_node("Icon") as TextureRect).texture.resource_path.ends_with("_dark.svg"), name + " icon uses dark asset")
		hub._make_nav(button, name.trim_suffix("Button"), name.trim_suffix("Button").to_lower(), name == "HomeButton")
		_check(contents.get_child_count() == 2, name + " does not duplicate content when restyled")
	AppearanceSettings.dark_mode = false
	hub._apply_tabletop_style()
	_check(not (hub.get_node("%HomeButton/Contents/Icon") as TextureRect).texture.resource_path.ends_with("_dark.svg"), "switching to light mode restores the light icon set")
	AppearanceSettings.dark_mode = true
	hub._apply_tabletop_style()
	_check((hub.get_node("%HomeButton/Contents/Icon") as TextureRect).texture.resource_path.ends_with("_dark.svg"), "switching back restores dark icons")
	_check((hub.get_node("%HomeButton/Contents") as VBoxContainer).get_child_count() == 2, "switching themes keeps one hub navigation icon")
	var play: Button = hub.get_node("%PlayButton")
	_check(play.get_theme_color("font_color") == T.on_primary(), "hub primary label uses deep teal")
	await _capture("dark-hub-360x800")
	hub.open_settings()
	await get_tree().process_frame
	await _capture("dark-settings-360x800")
	hub.free()
	var opponent: OpponentSelectionScreen = load("res://scenes/hub/opponent_selection_screen.tscn").instantiate()
	root.add_child(opponent)
	await get_tree().process_frame
	_check((opponent.get_node("Background") as ColorRect).color == T.canvas(), "opponent screen uses dark canvas")
	_check(((opponent.get_node("%Hero") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat).bg_color == T.sage(), "opponent matchup uses selected dark surface")
	_check((opponent.get_node("%BackButton") as Button).icon.resource_path.ends_with("_dark.svg"), "opponent back icon uses light stroke")
	_check(((opponent.get_node("%Modes/Online") as Button).get_theme_stylebox("normal") as StyleBoxFlat).bg_color == T.canvas_alt(), "unselected opponent mode uses a raised dark surface")
	await _capture("dark-opponent-360x800")
	opponent.free()
	AppearanceSettings.dark_mode = false
	var light_opponent: OpponentSelectionScreen = load("res://scenes/hub/opponent_selection_screen.tscn").instantiate()
	root.add_child(light_opponent)
	await get_tree().process_frame
	_check((light_opponent.get_node("Background") as ColorRect).color == T.canvas(), "opponent screen retains the light canvas")
	light_opponent.free()
	AppearanceSettings.dark_mode = true
	var background := ColorRect.new()
	background.color = T.canvas()
	root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bar := GameBottomNavigation.new()
	root.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	await get_tree().process_frame
	for action: StringName in [&"Undo", &"Swap", &"Resign", &"Pot"]:
		var button: Button = bar.buttons[action]
		var icon: TextureRect = button.get_node("Content/IconSurface/IconCenter/Icon")
		_check(icon.texture.resource_path.ends_with("_dark.svg"), String(action) + " uses a light-stroke icon")
		_check((button.get_node("Content") as Control).modulate.r >= 0.99, String(action) + " disabled state does not darken its icon")
	_check((bar.buttons[&"Play"].get_node("Content/Label") as Label).get_theme_color("font_color") == T.on_primary(), "game primary label uses deep teal")
	await _capture("dark-actions-360x800")
	bar.free()
	background.free()
	AppearanceSettings.dark_mode = original_mode
	var preference_suite = load("res://tests/unit/test_appearance_settings.gd").new()
	preference_suite.test_dark_mode_persists_and_switches_the_shared_palette()
	assertions += preference_suite.assertions
	failures.append_array(preference_suite.failures)
	print("DARK PALETTE: %d assertions, %d failures" % [assertions, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
