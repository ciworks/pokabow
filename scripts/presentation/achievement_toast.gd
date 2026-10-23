class_name AchievementToast
extends Control

## App-level, non-blocking achievement notification. AppRoot hosts this on
## OverlayLayer so the toast survives screen changes.
const T = preload("res://scripts/presentation/modern_tabletop_theme.gd")
const ART_ROOT: String = "res://assets/achievements/"
const DISPLAY_SECONDS: float = 4.0

var _queue: Array[Dictionary] = []
var _card: PanelContainer
var _icon: TextureRect
var _heading: Label
var _name: Label
var _description: Label
var _timer: Timer
var _active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card = PanelContainer.new()
	_card.name = "AchievementToastCard"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel: StyleBoxFlat = T.panel(T.canvas(), 12, 8.0)
	panel.set_border_width_all(1)
	panel.border_color = T.honey()
	panel.shadow_color = Color(0.05, 0.15, 0.16, 0.18)
	panel.shadow_size = 4
	_card.add_theme_stylebox_override("panel", panel)
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.size = Vector2(460, 72)
	add_child(_card)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	_card.add_child(row)
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.custom_minimum_size = Vector2(42, 42)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_icon)
	var copy := VBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 0)
	row.add_child(copy)
	_heading = Label.new()
	_heading.name = "Heading"
	_heading.text = "Achievement Unlocked"
	_heading.add_theme_font_override("font", T.SEMIBOLD)
	_heading.add_theme_font_size_override("font_size", 17)
	_heading.add_theme_color_override("font_color", T.muted())
	copy.add_child(_heading)
	_name = Label.new()
	_name.name = "AchievementName"
	_name.add_theme_font_override("font", T.SEMIBOLD)
	_name.add_theme_font_size_override("font_size", 22)
	_name.add_theme_color_override("font_color", T.ink())
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(_name)
	_description = Label.new()
	_description.name = "AchievementDescription"
	_description.add_theme_font_override("font", T.REGULAR)
	_description.add_theme_font_size_override("font_size", 18)
	_description.add_theme_color_override("font_color", T.muted())
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.max_lines_visible = 2
	_description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(_description)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_hide_current)
	add_child(_timer)
	_card.hide()
	resized.connect(_position_card)
	_position_card()


func show_achievement(id: String, title: String, description: String, badge_key: String = "") -> void:
	_queue.append({"id": id, "title": title, "description": description, "badgeKey": badge_key})
	if not _active:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_active = false
		return
	_active = true
	var item: Dictionary = _queue.pop_front()
	_name.text = str(item.get("title", ""))
	_description.text = str(item.get("description", "")).strip_edges()
	if _description.text.is_empty():
		_description.text = "Added to your achievements."
	var key: String = str(item.get("badgeKey", ""))
	if key.is_empty():
		key = str(item.get("id", ""))
	if not key in ["first_hand", "straight", "full_house", "edge_cluster", "ai_victory", "two_pair_10", "perfect_match"]:
		key = "milestone"
	var art: Texture2D = load(ART_ROOT + key + ".svg") as Texture2D
	_icon.texture = art if art != null else load(ART_ROOT + "milestone.svg") as Texture2D
	_position_card()
	_card.modulate.a = 0.0
	_card.show()
	create_tween().tween_property(_card, "modulate:a", 1.0, 0.22)
	_timer.start(DISPLAY_SECONDS)


func _hide_current() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_card, "modulate:a", 0.0, 0.2)
	tween.finished.connect(func() -> void:
		_card.hide()
		_show_next()
	)


func _position_card() -> void:
	if _card == null:
		return
	var top: float = 12.0
	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		top = maxf(top, float(safe.position.y) + 8.0)
	_card.size.x = minf(460.0, maxf(0.0, size.x - 24.0))
	_card.position = Vector2((size.x - _card.size.x) * 0.5, top)
