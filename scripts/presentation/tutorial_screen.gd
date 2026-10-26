class_name TutorialScreen
extends Control
## Read-only first-run guide, hosted over the hub by AppRoot.

signal finished(choice: String)

const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")
const GUIDE_PORTRAIT: Texture2D = preload("res://assets/ui/modern_tabletop/avatars/players/player_03.tres")
const LESSONS: Array[Dictionary] = [
	{"title": "Welcome to Pokabow!", "body": "Hi! I'm your guide. Let's get comfortable at the table together. You can leave whenever you're ready.", "example": "welcome", "focus": ""},
	{"title": "Your table", "body": "Your score is on the left and your rival's is on the right. Your tiles sit below the board, ready for your turn.", "example": "welcome", "focus": ""},
	{"title": "Choose and place", "body": "Drag a tile from your rack to an empty board cell. Tap a rack tile twice to turn it a quarter-turn before placing it.", "example": "place", "focus": ""},
	{"title": "Make a hand", "body": "Place tiles in a straight line to make a recognised hand. Two Kings make a Pair; J–Q–K in order makes a 3-straight.", "example": "hands", "focus": ""},
	{"title": "Seven ways to score", "body": "Look for Pair, Two Pair, Three-of-a-Kind, Four-of-a-Kind, 3-straight, 4-straight and Full House. A hand uses two to five tiles.", "example": "catalogue", "focus": ""},
	{"title": "Match the edges", "body": "Touching edges of the same colour score +1. Rotate a tile to line up more matches. Different colours can still touch.", "example": "edges", "focus": ""},
	{"title": "Grow colour clusters", "body": "Connect four tiles through matching edges of one colour to earn a cluster bonus. Clusters add points separately from your hand.", "example": "clusters", "focus": ""},
	{"title": "Preview, Play, Undo", "body": "Check your score preview, then press Play hand to commit. Undo returns staged tiles to your rack before you play.", "example": "play", "focus": "Play"},
	{"title": "Your other tools", "body": "Swap exchanges selected rack tiles. Pot shows the remaining tiles. Resign ends the match after you confirm it.", "example": "actions", "focus": "Swap"},
	{"title": "Explore the board", "body": "Your turn has no time limit. Drag empty board space to look around and pinch to zoom. Play, swap or resign when you're ready.", "example": "navigate", "focus": ""},
	{"title": "Choose a rival", "body": "Play an Easy, Medium or Hard AI rival, or choose Online. Your rival's face and difficulty are shown before the match.", "example": "rivals", "focus": ""},
	{"title": "Level and Gem pot", "body": "Verified online matches grow your Table Level; AI matches do not. Poker hands grow the Gem pot. Server-controlled AI matches can credit Gems after completion; local AI matches show a pot but do not credit your wallet.", "example": "hands", "focus": ""},
]

var _index: int = 0
var _page_margin: MarginContainer
var _example_scroll: ScrollContainer
var _demo: VBoxContainer
var _step_label: Label
var _guide_title: Label
var _guide_body: Label
var _example_caption: Label
var _board: TutorialExampleBoard
var _back_button: Button
var _next_button: Button
var _exit_layer: Control
var _keep_learning: Button
var _progress: Array[ColorRect] = []
var _action_chips: Dictionary[String, PanelContainer] = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Tabletop.create()
	_build()
	resized.connect(_fit_layout)
	_fit_layout()
	_show_step()


func step_index() -> int:
	return _index


func lesson_count() -> int:
	return LESSONS.size()


func next_step() -> void:
	if _index >= LESSONS.size() - 1:
		finished.emit("complete")
		return
	_index += 1
	_show_step()


func previous_step() -> void:
	if _index <= 0:
		return
	_index -= 1
	_show_step()


func request_exit() -> void:
	_exit_layer.show()
	_keep_learning.grab_focus()


func _build() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = Tabletop.canvas()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_page_margin = MarginContainer.new()
	_page_margin.name = "PageMargin"
	add_child(_page_margin)
	_page_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var page := VBoxContainer.new()
	page.name = "Page"
	page.add_theme_constant_override("separation", 12)
	_page_margin.add_child(page)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	page.add_child(header)
	var title := _label("HOW TO PLAY", 25, Tabletop.BOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_step_label = _label("1 / 12", 20, Tabletop.SEMIBOLD)
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_step_label)
	var exit_button := _button("Exit", "quiet", 64)
	exit_button.name = "ExitButton"
	exit_button.pressed.connect(request_exit)
	header.add_child(exit_button)

	var progress_row := HBoxContainer.new()
	progress_row.name = "Progress"
	progress_row.add_theme_constant_override("separation", 4)
	page.add_child(progress_row)
	for i: int in range(LESSONS.size()):
		var segment := ColorRect.new()
		segment.custom_minimum_size = Vector2(0, 5)
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		progress_row.add_child(segment)
		_progress.append(segment)

	_example_scroll = ScrollContainer.new()
	_example_scroll.name = "ExampleScroll"
	_example_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_example_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_example_scroll)
	_demo = VBoxContainer.new()
	_demo.name = "Demo"
	_demo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_demo.alignment = BoxContainer.ALIGNMENT_CENTER
	_demo.add_theme_constant_override("separation", 8)
	_example_scroll.add_child(_demo)
	_example_scroll.resized.connect(_fit_demo)
	var demo: VBoxContainer = _demo

	var score_panel := PanelContainer.new()
	score_panel.name = "ExampleScores"
	score_panel.add_theme_stylebox_override("panel", Tabletop.panel(Tabletop.sage(), 18, 12))
	demo.add_child(score_panel)
	var score_row := HBoxContainer.new()
	score_panel.add_child(score_row)
	var you := _label("You\n0", 20, Tabletop.SEMIBOLD)
	you.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_row.add_child(you)
	var pot := _label("GEM POT\n0 / 20", 18, Tabletop.SEMIBOLD)
	pot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_row.add_child(pot)
	var rival := _label("Rival\n0", 20, Tabletop.SEMIBOLD)
	rival.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rival.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_row.add_child(rival)

	var turn := _label("EXAMPLE TURN  ·  NO TIME LIMIT", 17, Tabletop.MEDIUM)
	turn.name = "ExampleTurn"
	turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn.add_theme_color_override("font_color", Tabletop.muted())
	demo.add_child(turn)
	_board = TutorialExampleBoard.new()
	_board.name = "ExampleBoard"
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	demo.add_child(_board)
	_example_caption = _label("12 × 12 board · illustrated crop", 16, Tabletop.REGULAR)
	_example_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_example_caption.add_theme_color_override("font_color", Tabletop.muted())
	demo.add_child(_example_caption)
	_build_rack(demo)
	_build_action_bar(demo)
	_build_guide_card(page)
	_build_exit_sheet()


func _build_rack(parent: VBoxContainer) -> void:
	var rack := HBoxContainer.new()
	rack.name = "ExampleRack"
	rack.add_theme_constant_override("separation", 6)
	parent.add_child(rack)
	for glyph: String in ["A♥", "Q♠", "K♦", "J♣", "K♥", "A♠"]:
		var tile := PanelContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.custom_minimum_size.y = 42
		var style: StyleBoxFlat = Tabletop.panel(Color("#F6F2E9"), 7, 2)
		style.set_border_width_all(2)
		style.border_color = TilePainter.edge_color_for(TileEnums.EdgeColor.BLUE)
		tile.add_theme_stylebox_override("panel", style)
		rack.add_child(tile)
		var label := _label(glyph, 18, Tabletop.SEMIBOLD)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color("#173D42"))
		tile.add_child(label)


func _build_action_bar(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "ExampleActions"
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	for name: String in ["Undo", "Swap", "Play", "Resign", "Pot"]:
		var chip := PanelContainer.new()
		chip.name = name
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.custom_minimum_size.y = 42
		row.add_child(chip)
		var label := _label("Play hand" if name == "Play" else name, 14, Tabletop.MEDIUM)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(label)
		_action_chips[name] = chip


func _build_guide_card(parent: VBoxContainer) -> void:
	var card := PanelContainer.new()
	card.name = "GuideCard"
	var style: StyleBoxFlat = Tabletop.panel(Tabletop.canvas_alt(), 22, 16)
	style.shadow_color = Color(0, 0, 0, 0.13)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 3)
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	card.add_child(content)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	content.add_child(top)
	var portrait := TextureRect.new()
	portrait.name = "GuidePortrait"
	portrait.texture = GUIDE_PORTRAIT
	portrait.custom_minimum_size = Vector2(68, 68)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.accessibility_name = "Friendly cartoon tutorial guide"
	top.add_child(portrait)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	var tag := _label("YOUR GUIDE", 14, Tabletop.SEMIBOLD)
	tag.add_theme_color_override("font_color", Tabletop.muted())
	heading.add_child(tag)
	_guide_title = _label("Welcome to Pokabow!", 26, Tabletop.BOLD)
	_guide_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(_guide_title)
	_guide_body = _label("", 22, Tabletop.REGULAR)
	_guide_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_guide_body)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	content.add_child(actions)
	_back_button = _button("Back", "quiet", 58)
	_back_button.name = "BackButton"
	_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_button.pressed.connect(previous_step)
	actions.add_child(_back_button)
	_next_button = _button("Next", "primary", 58)
	_next_button.name = "NextButton"
	_next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_button.pressed.connect(next_step)
	actions.add_child(_next_button)


func _build_exit_sheet() -> void:
	_exit_layer = Control.new()
	_exit_layer.name = "ExitLayer"
	_exit_layer.visible = false
	add_child(_exit_layer)
	_exit_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.12, 0.13, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_exit_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.name = "Dialog"
	_exit_layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 280
	panel.add_theme_stylebox_override("panel", Tabletop.panel(Tabletop.canvas(), 22, 18))
	center.add_child(panel)
	var choices := VBoxContainer.new()
	choices.name = "Choices"
	choices.add_theme_constant_override("separation", 10)
	panel.add_child(choices)
	var heading := _label("Leave the tutorial?", 25, Tabletop.BOLD)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choices.add_child(heading)
	var later := _button("Remind me later", "primary", 56)
	later.pressed.connect(func() -> void: finished.emit("later"))
	choices.add_child(later)
	var never := _button("Don't show again", "secondary", 56)
	never.pressed.connect(func() -> void: finished.emit("never"))
	choices.add_child(never)
	_keep_learning = _button("Keep learning", "quiet", 56)
	_keep_learning.name = "KeepLearning"
	_keep_learning.pressed.connect(func() -> void: _exit_layer.hide())
	choices.add_child(_keep_learning)


func _show_step() -> void:
	var lesson: Dictionary = LESSONS[_index]
	_step_label.text = "%d / %d" % [_index + 1, LESSONS.size()]
	_guide_title.text = String(lesson["title"])
	_guide_body.text = String(lesson["body"])
	_board.example = String(lesson["example"])
	_board.accessibility_name = "Tutorial example: " + _guide_title.text + ". " + _guide_body.text
	_back_button.disabled = _index == 0
	_next_button.text = "Finish" if _index == LESSONS.size() - 1 else "Next"
	for i: int in range(_progress.size()):
		_progress[i].color = Tabletop.honey() if i <= _index else Tabletop.sage()
	for key: String in _action_chips:
		var chip: PanelContainer = _action_chips[key]
		var active: bool = key == String(lesson["focus"])
		chip.add_theme_stylebox_override("panel", Tabletop.panel(Tabletop.honey() if active else Tabletop.canvas_alt(), 10, 2))
		(chip.get_child(0) as Label).add_theme_color_override("font_color", Color("#173D42") if active else Tabletop.muted())


func _fit_layout() -> void:
	if _page_margin == null:
		return
	# Keep the board prominent on taller phones while reserving room for the
	# guide and controls on compact screens. The example strip may scroll.
	_board.custom_minimum_size.y = 190 if size.y < 700 else (250 if size.y < 900 else 280)
	var side: int = maxi(16, roundi(size.x * 0.04))
	var top: int = 16
	var bottom: int = 16
	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var window: Vector2i = DisplayServer.window_get_size()
		if window.y > 0 and safe.size.y > 0:
			var ratio: float = size.y / float(window.y)
			top = maxi(top, ceili(safe.position.y * ratio))
			bottom = maxi(bottom, ceili((window.y - safe.end.y) * ratio))
	_page_margin.add_theme_constant_override("margin_left", side)
	_page_margin.add_theme_constant_override("margin_right", side)
	_page_margin.add_theme_constant_override("margin_top", top)
	_page_margin.add_theme_constant_override("margin_bottom", bottom)
	_fit_demo()


func _fit_demo() -> void:
	if _demo != null and _example_scroll != null:
		_demo.custom_minimum_size.y = _example_scroll.size.y


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _exit_layer.visible:
			_exit_layer.hide()
		else:
			request_exit()
		get_viewport().set_input_as_handled()


func _label(value: String, font_size: int, font: Font) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Tabletop.ink())
	return label


func _button(value: String, style: String, minimum_height: int) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = minimum_height
	button.add_theme_font_size_override("font_size", 21)
	Tabletop.style_button(button, style)
	return button
