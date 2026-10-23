extends "res://tests/harness/test_case.gd"

const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")


func test_dark_mode_persists_and_switches_the_shared_palette() -> void:
	var previous: bool = AppearanceSettings.dark_mode
	AppearanceSettings.set_dark_mode(true)
	var saved := ConfigFile.new()
	check_eq(saved.load(AppearanceSettings.SETTINGS_PATH), OK, "appearance preference is saved locally")
	check_eq(saved.get_value(AppearanceSettings.SECTION, AppearanceSettings.KEY_DARK_MODE), true, "dark mode survives a new launch")
	check_eq(Tabletop.canvas(), Color("#142224"), "dark mode uses the approved dark canvas")
	check_eq(Tabletop.ink(), Color("#F6F2E9"), "dark mode keeps text light against dark surfaces")
	check_eq(Tabletop.honey(), Color("#F4C86A"), "the primary action accent remains consistent")
	AppearanceSettings.set_dark_mode(previous)
