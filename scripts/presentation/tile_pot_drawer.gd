class_name TilePotDrawer
extends Control

## Read-only bottom sheet. GameScreen supplies the public pot inventory.
const T = preload("res://scripts/presentation/modern_tabletop_theme.gd")
const SLIDE_SECONDS: float = 0.24
const GRID_COLUMNS: int = 5
const GRID_GAP: int = 8

var is_open: bool = false
var _panel: PanelContainer
var _scrim: Button
var _count_label: Label
var _grid: GridContainer
var _empty_label: Label
var _close_button: Button
var _motion: Tween
var _inventory_key: String = ""
var _displayed_count: int = 0
var _handle_drag: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 20
	_build()
	resized.connect(_layout)
	_layout()
	hide()


func _build() -> void:
	_scrim = Button.new()
	_scrim.name = "PotScrim"
	_scrim.focus_mode = Control.FOCUS_NONE
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim_style: StyleBoxFlat = T.panel(Color("#142224", 0.58), 0, 0)
	for state: String in ["normal", "hover", "pressed"]:
		_scrim.add_theme_stylebox_override(state, scrim_style)
	_scrim.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_child(_scrim)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.pressed.connect(func() -> void: set_open(false))

	_panel = PanelContainer.new()
	_panel.name = "PotSheet"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", T.panel(T.canvas(), 26, 20))
	add_child(_panel)
	var column := VBoxContainer.new()
	column.name = "PotContent"
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	var handle_row := CenterContainer.new()
	handle_row.custom_minimum_size.y = 10
	handle_row.mouse_filter = Control.MOUSE_FILTER_STOP
	handle_row.gui_input.connect(_on_handle_input)
	column.add_child(handle_row)
	var handle := ColorRect.new()
	handle.name = "DragHandle"
	handle.color = T.muted()
	handle.custom_minimum_size = Vector2(48, 5)
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	handle_row.add_child(handle)
	var header := HBoxContainer.new()
	header.name = "PotHeader"
	column.add_child(header)
	var title := Label.new()
	title.name = "PotTitle"
	title.text = "Tile pot"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", T.BOLD)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", T.ink())
	header.add_child(title)
	_close_button = Button.new()
	_close_button.name = "ClosePotButton"
	_close_button.text = "×"
	_close_button.tooltip_text = "Close tile pot"
	_close_button.accessibility_name = "Close tile pot"
	_close_button.custom_minimum_size = Vector2(82, 82)
	T.style_button(_close_button, "quiet")
	_close_button.add_theme_font_size_override("font_size", 30)
	header.add_child(_close_button)
	_close_button.pressed.connect(func() -> void: set_open(false))
	_count_label = Label.new()
	_count_label.name = "PotAvailableCount"
	_count_label.text = "0 available"
	_count_label.add_theme_font_override("font", T.REGULAR)
	_count_label.add_theme_font_size_override("font_size", 22)
	_count_label.add_theme_color_override("font_color", T.muted())
	column.add_child(_count_label)
	var scroll := ScrollContainer.new()
	scroll.name = "PotScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.name = "PotGrid"
	_grid.columns = GRID_COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", GRID_GAP)
	_grid.add_theme_constant_override("v_separation", GRID_GAP)
	scroll.add_child(_grid)
	_empty_label = Label.new()
	_empty_label.name = "PotEmptyMessage"
	_empty_label.visible = false
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_override("font", T.REGULAR)
	_empty_label.add_theme_font_size_override("font_size", 20)
	_empty_label.add_theme_color_override("font_color", T.muted())
	column.add_child(_empty_label)


func set_inventory(faces: Array[Dictionary], count: int) -> void:
	var key: String = JSON.stringify(faces) + ":" + str(count)
	if key == _inventory_key:
		return
	_inventory_key = key
	_count_label.text = "%d available" % count
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_displayed_count = 0
	for face: Dictionary in faces:
		var tile := TilePotTileView.new()
		if not tile.set_face(face, _displayed_count):
			tile.queue_free()
			continue
		tile.name = "PotTile%d" % _displayed_count
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(tile)
		_displayed_count += 1
	_grid.visible = _displayed_count > 0
	_empty_label.visible = _displayed_count == 0
	if count == 0:
		_empty_label.text = "The tile pot is empty"
	else:
		_empty_label.text = "Tile details are not available yet"
	_layout()


func displayed_count() -> int:
	return _displayed_count


func set_open(value: bool, animate: bool = true) -> void:
	if is_open == value and (value or not visible):
		return
	is_open = value
	if _motion != null:
		_motion.kill()
	if value:
		show()
		_layout()
		_panel.position.y = size.y
	else:
		_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	var destination: float = size.y - _panel.size.y if value else size.y
	if animate and not AccessibilitySettings.reduced_motion() and is_inside_tree():
		_motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_motion.tween_property(_panel, "position:y", destination, SLIDE_SECONDS)
		if not value:
			_motion.tween_callback(hide)
	else:
		_panel.position.y = destination
		if not value:
			hide()
	if value:
		_close_button.grab_focus()
	else:
		var nav := get_parent().get_node_or_null("BottomNavigation") as GameBottomNavigation
		if nav != null and nav.buttons.has(&"Pot") and nav.buttons[&"Pot"].is_visible_in_tree():
			nav.buttons[&"Pot"].grab_focus()


func _layout() -> void:
	if _panel == null:
		return
	_panel.size = Vector2(size.x, minf(size.y * 0.65, 640.0))
	_panel.position.x = 0.0
	_panel.position.y = size.y - _panel.size.y if is_open else size.y
	var tile_side: float = maxf(44.0, floorf((size.x - 40.0 - GRID_GAP * (GRID_COLUMNS - 1)) / GRID_COLUMNS))
	for child: Node in _grid.get_children():
		(child as Control).custom_minimum_size = Vector2.ONE * tile_side


func _on_handle_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_drag = 0.0
		else:
			_handle_drag = 0.0
	elif event is InputEventScreenDrag:
		_handle_drag += event.relative.y
		if _handle_drag > 64.0:
			set_open(false)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_drag = 0.0
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_handle_drag += event.relative.y
		if _handle_drag > 64.0:
			set_open(false)


func _unhandled_key_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
