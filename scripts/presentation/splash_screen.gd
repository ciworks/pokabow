extends Control
## Modern Tabletop splash. Startup and account routing remain owned by AppRoot.
const TABLETOP = preload("res://scripts/presentation/modern_tabletop_theme.gd")

@onready var _margin: MarginContainer = $CenterContainer
@onready var _column: VBoxContainer = $CenterContainer/TitleBlock
@onready var _version_label: Label = %VersionLabel

func _ready() -> void:
	theme = TABLETOP.create()
	$Background.color = TABLETOP.canvas()
	_column.get_node("Brand").add_theme_font_override("font", TABLETOP.BOLD)
	_column.get_node("Tagline").add_theme_font_override("font", TABLETOP.MEDIUM)
	_column.get_node("Tagline").add_theme_color_override("font_color", TABLETOP.muted())
	_column.get_node("LoadingCaption").add_theme_color_override("font_color", TABLETOP.muted())
	_version_label.add_theme_font_override("font", TABLETOP.REGULAR)
	_version_label.add_theme_color_override("font_color", TABLETOP.muted())
	var version: String = String(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	_version_label.text = "v%s" % version if not version.is_empty() else ""
	resized.connect(_fit_layout)
	_fit_layout()

func _fit_layout() -> void:
	var factor: float = minf(size.x / 540.0, size.y / 960.0)
	var side: int = maxi(12, roundi(20.0 * factor))
	var top: int = maxi(16, roundi(24.0 * factor))
	var bottom: int = top
	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var window: Vector2i = DisplayServer.window_get_size()
		if window.x > 0 and window.y > 0 and safe.has_area():
			var ratio := size / Vector2(window)
			side = maxi(side, ceili(maxi(safe.position.x, window.x - safe.end.x) * ratio.x))
			top = maxi(top, ceili(safe.position.y * ratio.y))
			bottom = maxi(bottom, ceili((window.y - safe.end.y) * ratio.y))
	_margin.add_theme_constant_override("margin_left", side)
	_margin.add_theme_constant_override("margin_right", side)
	_margin.add_theme_constant_override("margin_top", top)
	_margin.add_theme_constant_override("margin_bottom", bottom)
	_column.add_theme_constant_override("separation", maxi(4, roundi(10.0 * factor)))
	_column.get_node("Logo").custom_minimum_size = Vector2.ONE * 80.0 * factor
	_column.get_node("Brand").add_theme_font_size_override("font_size", maxi(24, roundi(88.0 * factor)))
	_column.get_node("Tagline").add_theme_font_size_override("font_size", maxi(14, roundi(30.0 * factor)))
	_column.get_node("Hero").custom_minimum_size.y = 350.0 * factor
	_column.get_node("LoadingProgress").custom_minimum_size = Vector2(116, 24) * factor
	_column.get_node("LoadingCaption").add_theme_font_size_override("font_size", maxi(14, roundi(24.0 * factor)))
	_version_label.add_theme_font_size_override("font_size", maxi(14, roundi(16.0 * factor)))

