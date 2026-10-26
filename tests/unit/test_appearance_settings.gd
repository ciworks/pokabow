extends "res://tests/harness/test_case.gd"

const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")


func test_dark_mode_persists_and_switches_the_shared_palette() -> void:
	var previous: bool = AppearanceSettings.dark_mode
	AppearanceSettings.set_dark_mode(true)
	var saved := ConfigFile.new()
	check_eq(saved.load(AppearanceSettings.SETTINGS_PATH), OK, "appearance preference is saved locally")
	check_eq(saved.get_value(AppearanceSettings.SECTION, AppearanceSettings.KEY_DARK_MODE), true, "dark mode survives a new launch")
	check_eq(Tabletop.canvas(), Color("#101F26"), "dark mode uses the revised canvas")
	check_eq(Tabletop.canvas_alt(), Color("#203841"), "dark mode uses the revised raised surface")
	check_eq(Tabletop.ink(), Color("#F2F5EF"), "dark mode keeps text light against dark surfaces")
	check_eq(Tabletop.icon_ink(), Color("#E8F2EC"), "dark icons use a distinct light stroke")
	check(Tabletop.icon_texture("home").resource_path.ends_with("home_dark.svg"), "dark navigation icon uses a light-stroke asset")
	check_eq(Tabletop.honey(), Color("#F4C86A"), "the primary action accent remains consistent")
	var primary := Button.new()
	Tabletop.style_button(primary, "primary")
	check_eq(primary.get_theme_color("font_color"), Color("#173D42"), "honey primary button keeps a legible deep-teal label")
	primary.free()
	AppearanceSettings.set_dark_mode(previous)
