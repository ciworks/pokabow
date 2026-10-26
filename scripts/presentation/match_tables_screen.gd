class_name MatchTablesScreen
extends Control

## Read-only list and completed-match detail. Receives display records from AppRoot.
signal back_requested
signal resume_game_requested(kind: String, id: String, path: String)

const T = preload("res://scripts/presentation/modern_tabletop_theme.gd")
const PORTRAIT = preload("res://scripts/presentation/matchup_portrait.gd")
const SHARE_TEXT: String = "I'm having fun playing Pokabow (and winning)! Download it free from the Android or iOS store: https://example.com"
const SHARE_IMAGE_PATH: String = "user://pokabow-history-share.png"

var _active: Array[Dictionary] = []
var _completed: Array[Dictionary] = []
var _detail: Dictionary = {}
var _scroll: ScrollContainer
var _content: VBoxContainer
var _footer: VBoxContainer
var _share_button: Button
var _back_button: Button
var _share_plugin: Share


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = T.create()
	var background := ColorRect.new()
	background.color = T.canvas()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_back_button = Button.new()
	_back_button.tooltip_text = "Back"
	T.style_back_button(_back_button)
	_back_button.pressed.connect(_on_back)
	header.add_child(_back_button)
	var wordmark := Label.new()
	wordmark.text = "POKABOW"
	wordmark.add_theme_font_override("font", T.BOLD)
	wordmark.add_theme_font_size_override("font_size", _scaled(30))
	wordmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wordmark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(wordmark)
	var balance := Control.new()
	balance.custom_minimum_size.x = T.BACK_BUTTON_SIZE.x
	header.add_child(balance)
	var divider := HSeparator.new()
	column.add_child(divider)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 16)
	_scroll.add_child(_content)
	_footer = VBoxContainer.new()
	_footer.add_theme_constant_override("separation", 8)
	column.add_child(_footer)
	_share_button = Button.new()
	_share_button.text = "Share"
	_share_button.icon = T.icon_texture("share")
	_share_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_share_button.custom_minimum_size.y = 72
	T.style_button(_share_button, "secondary")
	_share_button.pressed.connect(_share_result)
	_footer.add_child(_share_button)
	var home := Button.new()
	home.text = "Back to tables"
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home.custom_minimum_size.y = 72
	T.style_button(home, "primary")
	home.pressed.connect(func() -> void: show_list())
	_footer.add_child(home)
	if Engine.has_singleton(Share.PLUGIN_SINGLETON_NAME):
		_share_plugin = Share.new()
		add_child(_share_plugin)
	_show_current()


func set_records(active: Array[Dictionary], completed: Array[Dictionary]) -> void:
	_active = active.duplicate(true)
	_completed = completed.duplicate(true)
	if is_node_ready():
		_show_current()


func show_detail(kind: String, id: String) -> bool:
	for entry: Dictionary in _completed:
		if String(entry.get("kind", "")) == kind and String(entry.get("id", "")) == id:
			_detail = entry.duplicate(true)
			if is_node_ready():
				_show_current()
			return true
	return false


func show_list() -> void:
	_detail = {}
	_show_current()


func _on_back() -> void:
	if not _detail.is_empty():
		show_list()
	else:
		back_requested.emit()


func _show_current() -> void:
	if _content == null:
		return
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.free()
	if _detail.is_empty():
		_build_list()
	else:
		_build_detail()
	_scroll.scroll_vertical = 0
	_footer.visible = not _detail.is_empty()
	var result: Dictionary = _detail.get("result", {})
	_share_button.visible = not _detail.is_empty() and int(result.get("outcome", 0)) == TurnEnums.MatchOutcome.HUMAN_WIN


func _build_list() -> void:
	_label(_content, "Your tables", 32, T.BOLD)
	_label(_content, "Active matches", 22, T.SEMIBOLD)
	if _active.is_empty():
		_label(_content, "No active matches. Your next table is waiting.", 17, T.REGULAR)
	for game: Dictionary in _active:
		var card := _panel(_content, T.sage())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		row.add_child(_avatar(String(game.get("avatar_path", ""))))
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		_label(column, "ACTIVE · %s" % String(game.get("status_label", "RESUMABLE")), 16, T.MEDIUM)
		_label(column, String(game.get("opponent", "Rival")), 23, T.SEMIBOLD)
		_label(column, String(game.get("score", "")), 17, T.REGULAR)
		var button := Button.new()
		button.text = "Resume"
		button.custom_minimum_size.y = 72
		T.style_button(button, "primary")
		button.pressed.connect(func() -> void:
			resume_game_requested.emit(String(game.get("kind", "ai")), String(game.get("id", "")), String(game.get("path", ""))))
		column.add_child(button)
	_label(_content, "Completed matches", 22, T.SEMIBOLD)
	if _completed.is_empty():
		_label(_content, "Your completed matches will appear here.", 17, T.REGULAR)
	for entry: Dictionary in _completed:
		var result: Dictionary = entry.get("result", {})
		var kind: String = String(entry.get("kind", ""))
		var id: String = String(entry.get("id", ""))
		var card := _panel(_content, T.sage())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		row.add_child(_avatar(String(entry.get("avatar_path", ""))))
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		_label(column, "%s · %s" % [HubScreen._outcome_label(int(result.get("outcome", 0))).to_upper(), _date_label(String(entry.get("finished_at", "")))], 16, T.MEDIUM)
		_label(column, "You %d · %s %d" % [int(result.get("human_score", 0)),
			String(entry.get("opponent", "Rival")), int(result.get("ai_score", 0))], 17, T.REGULAR)
		var button := Button.new()
		button.text = "Details ›"
		button.custom_minimum_size.y = 72
		T.style_button(button, "quiet")
		button.pressed.connect(func() -> void: show_detail(kind, id))
		column.add_child(button)


func _build_detail() -> void:
	var result: Dictionary = _detail.get("result", {})
	var outcome: int = int(result.get("outcome", 0))
	var eyebrow := _label(_content, "MATCH DETAILS", 16, T.MEDIUM)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title_text: String = "You win!" if outcome == TurnEnums.MatchOutcome.HUMAN_WIN else ("It's a draw" if outcome == TurnEnums.MatchOutcome.DRAW else "Rival wins")
	var title := _label(_content, title_text, 38, T.BOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var opponent: String = String(_detail.get("opponent", "Rival"))
	var subtitle := _label(_content, "vs %s · %s" % [opponent, _date_label(String(_detail.get("finished_at", "")))], 17, T.REGULAR)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var score_card := _panel(_content, T.sage())
	var score_row := HBoxContainer.new()
	score_card.add_child(score_row)
	for i: int in range(2):
		var player := VBoxContainer.new()
		player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		score_row.add_child(player)
		var portrait: FramedPlayerAvatar = PORTRAIT.new()
		portrait.name = "PlayerAvatar" if i == 0 else "RivalAvatar"
		portrait.texture = PlayerAvatarStore.texture() if i == 0 else HubScreen._portrait_for(String(_detail.get("avatar_path", "")))
		portrait.custom_minimum_size = Vector2(125, 125)
		portrait.show_ring = false
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		player.add_child(portrait)
		if (i == 0 and outcome == TurnEnums.MatchOutcome.HUMAN_WIN) or (i == 1 and outcome == TurnEnums.MatchOutcome.AI_WIN):
			var winner := _label(player, "✓ Winner", 16, T.SEMIBOLD)
			winner.add_theme_stylebox_override("normal", T.panel(T.honey(), 12, 3))
			winner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var name := _label(player, "You" if i == 0 else opponent, 19, T.SEMIBOLD)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var score := _label(player, str(int(result.get("human_score" if i == 0 else "ai_score", 0))), 40, T.BOLD)
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var unit := _label(player, "points", 15, T.REGULAR)
		unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(_content, "Score breakdown", 24, T.SEMIBOLD)
	var terms: Dictionary = result.get("terms", {})
	var human: Dictionary = terms.get("human", {})
	var rival: Dictionary = terms.get("ai", {})
	_breakdown_row("", "You", opponent)
	for spec: Array in [["poker", "Poker hands"], ["edge", "Edge matches"], ["cluster", "Clusters"]]:
		_breakdown_row(String(spec[1]), str(int(human.get(spec[0], 0))), str(int(rival.get(spec[0], 0))))
	var end_text: String = _end_reason(int(result.get("end_reason", 0)))
	var moves: int = int(result.get("move_count", 0))
	var ending := _label(_content, "%s · %d %s" % [end_text, moves, "move" if moves == 1 else "moves"], 16, T.REGULAR)
	ending.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ending.add_theme_color_override("font_color", T.muted())


func _breakdown_row(caption: String, own: String, rival: String) -> void:
	var row := HBoxContainer.new()
	_content.add_child(row)
	for value: String in [caption, own, rival]:
		var cell := _label(row, value, 17, T.MEDIUM)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = 2.0 if value == caption else 1.0
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if value == caption else HORIZONTAL_ALIGNMENT_CENTER


func _share_result() -> void:
	if _detail.is_empty():
		return
	if not Engine.has_singleton(Share.PLUGIN_SINGLETON_NAME):
		DisplayServer.clipboard_set(SHARE_TEXT)
		_share_button.text = "Message copied"
		return
	_footer.hide()
	await RenderingServer.frame_post_draw
	var screenshot: Image = get_viewport().get_texture().get_image()
	_footer.show()
	if screenshot.is_empty() or screenshot.save_png(ProjectSettings.globalize_path(SHARE_IMAGE_PATH)) != OK:
		_share_plugin.share_text("Pokabow", "I won at Pokabow", SHARE_TEXT)
		return
	_share_plugin.share_image(ProjectSettings.globalize_path(SHARE_IMAGE_PATH), "Pokabow", "I won at Pokabow", SHARE_TEXT)


static func _date_label(iso: String) -> String:
	return HubScreen._recent_date(iso)


static func _end_reason(reason: int) -> String:
	match reason:
		TurnEnums.EndReason.BOARD_FULL:
			return "The board filled up"
		TurnEnums.EndReason.TILE_SOURCE_EXHAUSTED:
			return "No tiles remained"
		TurnEnums.EndReason.RESIGNATION:
			return "Match ended by resignation"
	return "The match ended"


static func _panel(parent: Node, fill: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", T.panel(fill, 24, 22))
	parent.add_child(panel)
	return panel


static func _avatar(path: String) -> TextureRect:
	var portrait: FramedPlayerAvatar = PORTRAIT.new()
	portrait.name = "RivalAvatar"
	portrait.texture = HubScreen._portrait_for(path)
	portrait.custom_minimum_size = Vector2(90, 90)
	portrait.show_ring = false
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return portrait


static func _label(parent: Node, value: String, size: int, font: Font) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", _scaled(size))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


static func _scaled(reference: int) -> int:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var viewport: Viewport = tree.root
	return roundi(reference * clampf(viewport.get_visible_rect().size.x / 390.0, 0.9, 1.4))
