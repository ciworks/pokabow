extends SceneTree
## Focused profile UI checks without the Windows-incompatible image fixtures.

func _initialize() -> void:
	var suite = load("res://tests/unit/test_player_avatar.gd").new()
	suite.test_avatar_selector_saves_username_and_avatar_as_one_profile_change()
	suite.test_photo_editor_previews_cancels_and_saves_without_losing_the_current_avatar()
	var api_suite = load("res://tests/unit/test_game_api_client.gd").new()
	api_suite.test_profile_updates_username_inline_and_keeps_email_read_only()
	var profile_scene: PackedScene = load("res://scenes/profile/profile_screen.tscn")
	var profile: Variant = profile_scene.instantiate()
	root.add_child(profile)
	var achievement_browser: Variant = profile.get_node("%AchievementsPage")
	var achievement_back: Button = achievement_browser._back
	var profile_back: Button = profile.get_node("%BackButton")
	var achievement_title: Label = achievement_browser._heading
	var profile_title: Label = profile.get_node("Title")
	api_suite.check(achievement_back.icon.resource_path == profile_back.icon.resource_path, "Achievements uses the same chevron asset as Profile")
	api_suite.check(not achievement_back.expand_icon and not profile_back.expand_icon, "Both back chevrons use the same intrinsic scale")
	api_suite.check_eq(achievement_title.get_theme_font_size("font_size"), profile_title.get_theme_font_size("font_size"), "Achievement and profile titles match in size")
	var profile_focus: StyleBox = profile_back.get_theme_stylebox("focus")
	api_suite.check(profile_focus is StyleBoxEmpty, "Profile back button has no visible focus border")
	achievement_browser.free()
	profile.free()
	suite.failures.append_array(api_suite.failures)
	print("Profile design: %d assertions; %d failures" % [suite.assertions + api_suite.assertions, suite.failures.size()])
	for failure: String in suite.failures:
		push_error(failure)
	quit(0 if suite.failures.is_empty() else 1)
