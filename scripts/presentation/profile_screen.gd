class_name ProfileScreen
extends Control
## Read-only account details; OpenAPI provides GET /auth/me but no profile update.

signal back_requested
signal refresh_requested

const PROFILE_FIELD_KEYS: Dictionary = {
	"Display name": ["displayName", "display_name", "name", "username"],
	"Username": ["username", "userName", "handle"],
	"Email": ["email", "emailAddress", "email_address"],
}

var _fields: Dictionary = {}
var _achievement_rows: Array = []
var _catalog_received: bool = false
var _category: String = "All"

# Presentation grouping only. Catalog copy and unlocks always come from the API.
const ACHIEVEMENT_GROUPS: Dictionary = {
	"first_hand": "Hands", "straight": "Hands", "full_house": "Hands",
	"edge_cluster": "Edges", "ai_victory": "Victories",
}
const ACHIEVEMENT_ICONS: Dictionary = {
	"first_hand": preload("res://assets/tiles/suits/tile_ace_spades.png"),
	"straight": preload("res://assets/tiles/suits/tile_jack_hearts.png"),
	"full_house": preload("res://assets/tiles/suits/tile_queen_hearts.png"),
	"edge_cluster": preload("res://assets/tiles/suits/tile_ace_clubs.png"),
	"ai_victory": preload("res://assets/tiles/suits/tile_king_spades.png"),
}
const TILE_BASE: Texture2D = preload("res://assets/tiles/tile_base.png")
const INK: Color = Color("f4f3f8")
const MUTED: Color = Color("bac2d0")
const GOLD: Color = Color("ffca36")


func _ready() -> void:
	for button_path: NodePath in [^"%BackButton", ^"%UpdateButton"]:
		var button: Button = get_node_or_null(button_path) as Button
		if button == null:
			push_error("ProfileScreen: required button '%s' is missing." % button_path)
			continue
		if button_path == ^"%BackButton":
			button.pressed.connect(_on_back_pressed)
		else:
			button.text = "Refresh"
			button.pressed.connect(_on_update_pressed)
	_fields["Display name"] = get_node_or_null("%DisplayNameField") as LineEdit
	_fields["Username"] = get_node_or_null("%UsernameField") as LineEdit
	_fields["Email"] = get_node_or_null("%EmailField") as LineEdit
	for field: LineEdit in _fields.values():
		if field != null:
			field.editable = false
	_setup_achievements()
	resized.connect(_fit_achievements)
	_fit_achievements()
	_render_achievements()


## Populates account fields from AppRoot's authenticated state.
func set_user_state(state: Dictionary) -> void:
	var user: Variant = state.get("user", {})
	var details: Dictionary = user as Dictionary if typeof(user) == TYPE_DICTIONARY else {}
	for field_name: String in PROFILE_FIELD_KEYS:
		var field: LineEdit = _fields.get(field_name) as LineEdit
		if field == null:
			continue
		field.text = _value_for(details, PROFILE_FIELD_KEYS[field_name])


func set_achievement_rows(rows: Array) -> void:
	_achievement_rows = rows.duplicate(true)
	_catalog_received = true
	if is_node_ready():
		_render_achievements()
	var form: VBoxContainer = get_node_or_null("%Form") as VBoxContainer
	if form == null:
		form = get_node_or_null("ScrollContainer/Form") as VBoxContainer
	if form == null:
		return
	for child: Node in form.get_children():
		if child.name.begins_with("Achievement_"):
			child.queue_free()
	var heading := Label.new()
	heading.name = "Achievement_Heading"
	heading.text = "Achievements"
	heading.add_theme_color_override("font_color", Color(0.97, 0.94, 0.86, 1))
	heading.add_theme_font_size_override("font_size", 26)
	form.add_child(heading)
	for row_variant: Variant in _achievement_rows:
		if not row_variant is Dictionary:
			continue
		var row: Dictionary = row_variant
		var label := Label.new()
		label.name = "Achievement_%s" % String(row.get("id", "unknown"))
		var unlocked: bool = bool(row.get("unlocked", false))
		label.text = "%s %s — %s" % ["✓" if unlocked else "○", row.get("name", "Achievement"), row.get("description", "")]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", Color(0.97, 0.94, 0.86, 1))
		label.add_theme_font_size_override("font_size", 20)
		form.add_child(label)


func show_achievements_only(enabled: bool) -> void:
	%AchievementsPage.visible = enabled
	for node_path: String in ["Title", "BackButton", "ScrollContainer"]:
		(get_node(node_path) as Control).visible = not enabled
	($Background as ColorRect).color = Color("100f1c") if enabled else Color(0.12, 0.08, 0.19, 1)
	if enabled:
		_fit_achievements()
		%AchievementBack.grab_focus()
	else:
		%BackButton.grab_focus()


func _setup_achievements() -> void:
	var page_theme := Theme.new()
	page_theme.default_font_size = 28
	page_theme.set_color("font_color", "Label", INK)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		page_theme.set_color(state, "Button", INK)
	page_theme.set_stylebox("normal", "Button", _box(Color("101923"), 14, Color.TRANSPARENT, 6))
	page_theme.set_stylebox("hover", "Button", _box(Color("203349"), 14, Color("3695d0"), 6))
	page_theme.set_stylebox("pressed", "Button", _box(Color("075799"), 14, Color("288fe5"), 6))
	page_theme.set_stylebox("hover_pressed", "Button", _box(Color("075799"), 14, Color("64b9ff"), 6))
	var focus := _box(Color.TRANSPARENT, 14, Color("d5c3ea"), 0)
	focus.set_border_width_all(2)
	page_theme.set_stylebox("focus", "Button", focus)
	%AchievementsPage.theme = page_theme
	# Full-viewport surface; retain only comfortable inner content padding.
	var frame := _box(Color("080e16"), 0, Color.TRANSPARENT, 14)
	frame.set_border_width_all(0)
	frame.shadow_size = 0
	%AchievementFrame.add_theme_stylebox_override("panel", frame)
	%CategoryPanel.add_theme_stylebox_override("panel", _box(Color("101923"), 16, Color.TRANSPARENT, 2))
	%AchievementSummary.add_theme_color_override("font_color", MUTED)
	var group := ButtonGroup.new()
	for child: Node in %Categories.get_children():
		var button := child as Button
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = button.text == _category
		button.pressed.connect(_on_category_selected.bind(button.text))


func _fit_achievements() -> void:
	# Use the entire viewport in both orientations without an outer gutter.
	for side: String in ["left", "top", "right", "bottom"]:
		%AchievementsPage.add_theme_constant_override("margin_" + side, 0)


func _on_category_selected(category: String) -> void:
	_category = category
	%AchievementScroll.scroll_vertical = 0
	_render_achievements()


func _render_achievements() -> void:
	var cards: VBoxContainer = %AchievementCards
	for child: Node in cards.get_children():
		cards.remove_child(child)
		child.queue_free()
	var total: int = 0
	var unlocked_count: int = 0
	for value: Variant in _achievement_rows:
		if not value is Dictionary:
			continue
		var row: Dictionary = value
		var id: String = String(row.get("id", ""))
		if not ACHIEVEMENT_GROUPS.has(id):
			continue
		total += 1
		if bool(row.get("unlocked", false)):
			unlocked_count += 1
		if _category == "All" or ACHIEVEMENT_GROUPS[id] == _category:
			cards.add_child(_achievement_card(row))
	%AchievementSummary.text = "%d / %d unlocked - Account achievements" % [unlocked_count, total] if _catalog_received else "Account achievements"
	if cards.get_child_count() == 0:
		var message: String = "No achievements in this category."
		if not _catalog_received:
			message = "Waiting for your account catalog. If it is unavailable, return to the hub and reopen this page to retry."
		elif total == 0:
			message = "No achievements returned by your account."
		cards.add_child(_label(message, 32, MUTED))


func _achievement_card(row: Dictionary) -> PanelContainer:
	var id: String = String(row.get("id", ""))
	var unlocked: bool = bool(row.get("unlocked", false))
	var accent: Color = Color("32d9f0")
	if id == "full_house" or id == "straight":
		accent = Color("df58ed")
	elif id == "ai_victory":
		accent = GOLD
	var card := PanelContainer.new()
	card.name = "Achievement_" + id
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _box(Color("18232e"), 16, Color("2c3948"), 10))
	var row_box := HBoxContainer.new()
	row_box.add_theme_constant_override("separation", 10)
	card.add_child(row_box)
	var icon_frame := PanelContainer.new()
	icon_frame.custom_minimum_size = Vector2(116, 128)
	icon_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_style := _box(Color("0e1620"), 10, accent, 5)
	icon_style.set_border_width_all(4)
	icon_style.shadow_color = Color("b956d9") if accent != Color("df58ed") else Color("32d9f0")
	icon_style.shadow_offset = Vector2(1, 1)
	icon_style.shadow_size = 3
	icon_frame.add_theme_stylebox_override("panel", icon_style)
	row_box.add_child(icon_frame)
	var tile := TextureRect.new()
	tile.texture = TILE_BASE
	tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_frame.add_child(tile)
	var suit := TextureRect.new()
	suit.texture = ACHIEVEMENT_ICONS[id] as Texture2D
	suit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	suit.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	suit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(suit)
	suit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 6)
	row_box.add_child(copy)
	var title := _label(String(row.get("name", "Achievement")), 24, INK)
	title.add_theme_constant_override("outline_size", 1)
	title.add_theme_color_override("font_outline_color", INK)
	copy.add_child(title)
	copy.add_child(_label(String(row.get("description", "")), 28, MUTED))
	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 8)
	copy.add_child(progress_row)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = 1.0
	bar.value = 1.0 if unlocked else 0.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _box(Color("273441"), 4, Color.TRANSPARENT, 0))
	bar.add_theme_stylebox_override("fill", _box(GOLD, 4, Color("ffe785"), 0))
	progress_row.add_child(bar)
	var fraction := _label("1 / 1" if unlocked else "0 / 1", 25, MUTED)
	fraction.autowrap_mode = TextServer.AUTOWRAP_OFF
	progress_row.add_child(fraction)
	var divider := VSeparator.new()
	row_box.add_child(divider)
	var status := _label("Unlocked" if unlocked else "Locked", 25, GOLD if unlocked else MUTED)
	status.custom_minimum_size.x = 66
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row_box.add_child(status)
	return card


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _box(color: Color, radius: int, border: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = border
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func _value_for(details: Dictionary, keys: Array) -> String:
	for key: String in keys:
		if details.has(key) and details[key] != null and not String(details[key]).is_empty():
			return String(details[key])
	return ""


func _on_back_pressed() -> void:
	back_requested.emit()


## Reload from the documented account endpoint.
func _on_update_pressed() -> void:
	refresh_requested.emit()
