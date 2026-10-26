class_name AvatarLevelBadge
extends PanelContainer

## A compact Table Level chip for the in-game avatar. The caller supplies the
## server-owned level; this control does not calculate progression.
const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")

var _level: int = 0
var _text: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 4
	var background: StyleBoxFlat = Tabletop.panel(Tabletop.sage(), 14, 0.0)
	background.content_margin_left = 8.0
	background.content_margin_right = 8.0
	background.content_margin_top = 2.0
	background.content_margin_bottom = 2.0
	background.set_border_width_all(1)
	background.border_color = Tabletop.ink()
	add_theme_stylebox_override("panel", background)
	_text = Label.new()
	_text.name = "LevelText"
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.add_theme_font_override("font", Tabletop.SEMIBOLD)
	_text.add_theme_font_size_override("font_size", 19)
	_text.add_theme_color_override("font_color", Tabletop.ink())
	add_child(_text)
	_refresh()


func set_level(level: int) -> void:
	_level = level if level >= 1 else 0
	if is_node_ready():
		_refresh()


func _refresh() -> void:
	visible = _level > 0
	if _level == 0:
		tooltip_text = ""
		accessibility_name = ""
		return
	_text.text = "Lv %d" % _level
	tooltip_text = "Table Level %d" % _level
	accessibility_name = tooltip_text
	update_minimum_size()
