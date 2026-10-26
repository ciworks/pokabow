class_name MatchEndPresentation
extends Control
## Modern Tabletop results. MatchResult remains the sole source of scoring.
signal share_requested
const T = preload("res://scripts/presentation/modern_tabletop_theme.gd")
const PORTRAIT = preload("res://scripts/presentation/matchup_portrait.gd")
const ACCENT = preload("res://scripts/presentation/result_accent.gd")
const GEM_ICON: Texture2D = preload("res://assets/ui/modern_tabletop/store_gem.svg")
const DURATION: float = 0.8
const ACCENT_CYCLE_SECONDS: float = 2.4
var _elapsed: float = DURATION
var _animation: Tween
var _accent_animation: Tween
var _accent_elapsed: float = 0.0
var _result_key: String = ""
var _result: MatchResult
var _margin: MarginContainer
var _column: VBoxContainer
var _content: VBoxContainer
var _scroll: ScrollContainer
var _brand: Label
var _mark: TextureRect
var _eyebrow: Label
var _subtitle: Label
var _title: Label
var _body: Label
var _button: Button
var _footer: HBoxContainer
var _share_button: Button
var _share_feedback: Label
var _card_slot: Control
var _card: PanelContainer
var _card_row: HBoxContainer
var _reward_card: PanelContainer
var _reward_heading: Label
var _reward_pending: Label
var _reward_divider: VSeparator
var _reward_columns: Array[VBoxContainer] = []
var _reward_names: Array[Label] = []
var _reward_values: Array[Label] = []
var _reward_details: Array[Label] = []
var _breakdown_title: Label
var _rows: VBoxContainer
var _portraits: Array[TextureRect] = []
var _badges: Array[Label] = []
var _scores: Array[Label] = []
var _names: Array[Label] = []
var _units: Array[Label] = []
var _accents: Array[Control] = []
var _terms: Dictionary = {}
var _factor: float = 1.0

func _ready() -> void:
	if _margin != null:
		return
	theme = T.create()
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	_title = get_node("SummaryTitle")
	_body = get_node("SummaryBody")
	_button = get_node("SummaryHubButton")
	get_node("ConfettiLayer").hide()
	var background := ColorRect.new()
	background.color = T.canvas()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	move_child(background, 0)
	_margin = MarginContainer.new()
	add_child(_margin)
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_column = VBoxContainer.new()
	_margin.add_child(_column)
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_child(header)
	_mark = TextureRect.new()
	_mark.texture = preload("res://assets/ui/modern_tabletop/mark.svg")
	_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_mark)
	_brand = _label(header, "POKABOW", T.BOLD)
	_separator(_column)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_eyebrow = _label(_content, "MATCH COMPLETE")
	_eyebrow.add_theme_color_override("font_color", T.muted())
	_move_to(_title, _content)
	_title.uppercase = false
	_title.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	_title.add_theme_font_override("font", T.BOLD)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle = _label(_content, "Well played.")
	_subtitle.add_theme_color_override("font_color", T.muted())
	_card_slot = Control.new()
	_content.add_child(_card_slot)
	_card = PanelContainer.new()
	_card_slot.add_child(_card)
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_row = HBoxContainer.new()
	_card.add_child(_card_row)
	for i: int in range(2):
		if i == 1:
			var divider := VSeparator.new()
			var line := StyleBoxLine.new()
			line.color = T.sage().darkened(0.1)
			line.vertical = true
			divider.add_theme_stylebox_override("separator", line)
			_card_row.add_child(divider)
		var player := VBoxContainer.new()
		player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_card_row.add_child(player)
		var portrait: TextureRect = PORTRAIT.new()
		portrait.name = "PlayerAvatar" if i == 0 else "RivalAvatar"
		portrait.texture = load("res://assets/ui/modern_tabletop/avatars/%s" % ("players/player_01.tres" if i == 0 else "rivals/rival_01.tres"))
		portrait.show_ring = false
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		player.add_child(portrait)
		_portraits.append(portrait)
		var accent: Control = ACCENT.new()
		accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.add_child(accent)
		accent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_accents.append(accent)
		var badge := _label(player, "✓ Winner", T.SEMIBOLD)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		badge.add_theme_stylebox_override("normal", T.panel(T.honey(), 16, 4))
		_badges.append(badge)
		_names.append(_label(player, "You" if i == 0 else "Rival", T.SEMIBOLD))
		_scores.append(_label(player, "0", T.BOLD))
		_units.append(_label(player, "points"))
	_reward_card = PanelContainer.new()
	_reward_card.name = "GemRewards"
	_reward_card.visible = false
	_content.add_child(_reward_card)
	var reward_column := VBoxContainer.new()
	_reward_card.add_child(reward_column)
	var reward_header := HBoxContainer.new()
	reward_column.add_child(reward_header)
	_reward_heading = _label(reward_header, "GEMS EARNED", T.SEMIBOLD)
	_reward_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reward_pending = _label(reward_header, "Pending", T.MEDIUM)
	_reward_pending.add_theme_color_override("font_color", T.muted())
	var reward_row := HBoxContainer.new()
	reward_column.add_child(reward_row)
	for i: int in range(2):
		if i == 1:
			var divider := VSeparator.new()
			var line := StyleBoxLine.new()
			line.color = T.sage().darkened(0.1)
			line.vertical = true
			divider.add_theme_stylebox_override("separator", line)
			reward_row.add_child(divider)
			_reward_divider = divider
		var player_reward := VBoxContainer.new()
		player_reward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reward_row.add_child(player_reward)
		_reward_columns.append(player_reward)
		_reward_names.append(_label(player_reward, "You" if i == 0 else "Rival", T.SEMIBOLD))
		var amount_row := HBoxContainer.new()
		amount_row.alignment = BoxContainer.ALIGNMENT_CENTER
		player_reward.add_child(amount_row)
		var gem := TextureRect.new()
		gem.texture = GEM_ICON
		gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		amount_row.add_child(gem)
		var amount := _label(amount_row, "+0", T.BOLD)
		_reward_values.append(amount)
		var detail := _label(player_reward, "", T.REGULAR)
		detail.add_theme_color_override("font_color", T.muted())
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_reward_details.append(detail)
	_breakdown_title = _label(_content, "Score breakdown", T.SEMIBOLD)
	_breakdown_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_rows = VBoxContainer.new()
	_content.add_child(_rows)
	_table_row("", "You", "Rival")
	var keys: Array[String] = ["poker", "edge", "cluster"]
	var titles: Array[String] = ["Poker hands", "Edge matches", "Clusters"]
	for i: int in range(3):
		_separator(_rows)
		_terms[keys[i]] = _table_row(titles[i], "0", "0")
	_separator(_rows)
	_move_to(_body, _content)
	_body.add_theme_font_override("font", T.REGULAR)
	_share_feedback = _label(_column, "")
	_share_feedback.add_theme_color_override("font_color", T.muted())
	_share_feedback.hide()
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 8)
	_column.add_child(_footer)
	_share_button = Button.new()
	_share_button.name = "ShareWinButton"
	_share_button.text = "Share"
	_share_button.icon = T.icon_texture("share")
	_share_button.add_theme_constant_override("icon_max_width", 24)
	_share_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	T.style_button(_share_button, "secondary")
	_share_button.pressed.connect(func() -> void: share_requested.emit())
	_footer.add_child(_share_button)
	_move_to(_button, _footer)
	_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	T.style_button(_button, "primary")
	_button.text = "Back to hub"
	_card.minimum_size_changed.connect(_sync_card_height)
	resized.connect(_fit_layout)
	visibility_changed.connect(_on_visibility_changed)
	_fit_layout()

func _move_to(node: Node, parent: Node) -> void:
	var scene_owner: Node = node.owner
	node.owner = null
	node.reparent(parent, false)
	node.owner = scene_owner

func _sync_card_height() -> void:
	_card_slot.custom_minimum_size.y = _card.get_combined_minimum_size().y

func _label(parent: Node, text: String, font: Font = T.REGULAR) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _separator(parent: Node) -> void:
	var separator := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = T.sage()
	line.thickness = 1
	separator.add_theme_stylebox_override("separator", line)
	parent.add_child(separator)

func _table_row(caption: String, human: String, rival: String) -> Array[Label]:
	var row := HBoxContainer.new()
	_rows.add_child(row)
	var cells: Array[Label] = []
	for text: String in [caption, human, rival]:
		var label := _label(row, text, T.MEDIUM)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = 2.0 if cells.is_empty() else 1.0
		if cells.is_empty():
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cells.append(label)
	return cells

func play(result: MatchResult, projected_rewards: Dictionary = {}) -> void:
	if result == null:
		return
	var result_key: String = JSON.stringify(result.to_dictionary()) + JSON.stringify(projected_rewards)
	if visible and _result_key == result_key:
		return
	_stop_animation()
	_result = result
	_result_key = result_key
	_share_button.visible = result.winner_id() == TurnEnums.HUMAN_PLAYER_ID
	_share_feedback.hide()
	_scores[0].text = str(result.human_score)
	_scores[1].text = str(result.ai_score)
	_reward_card.visible = not projected_rewards.is_empty()
	if _reward_card.visible:
		var ai_pot: bool = String(projected_rewards.get("mode", "")) == "ai"
		_reward_heading.text = "AI GEM POT" if ai_pot else "GEMS EARNED"
		_reward_pending.text = ("Confirmed" if bool(projected_rewards.get("confirmed", false)) else
			("Pending" if bool(projected_rewards.get("verified", false)) or not ai_pot else "Not credited"))
		_reward_columns[1].visible = not ai_pot
		_reward_divider.visible = not ai_pot
		for i: int in range(2):
			var prefix: String = "human" if i == 0 else "rival"
			var pot: int = int(projected_rewards.get(prefix + "_pot", 0))
			var completion: int = int(projected_rewards.get(prefix + "_completion", 0))
			_reward_values[i].text = "+%d" % int(projected_rewards.get(prefix + "_total", 0))
			if ai_pot and i == 0:
				var qualifier: String = "" if bool(projected_rewards.get("confirmed", false)) else " · projected"
				_reward_details[i].text = ("%d draw share%s" % [pot, qualifier] if result.is_draw() else
					"%d pot%s" % [pot, qualifier]) if pot > 0 else "Pot unclaimed"
			elif result.is_draw():
				_reward_details[i].text = "%d share + %d completion" % [pot, completion]
			elif pot > 0 and completion > 0:
				_reward_details[i].text = "%d pot + %d completion" % [pot, completion]
			elif pot > 0:
				_reward_details[i].text = "%d pot" % pot
			elif completion > 0:
				_reward_details[i].text = "Completion bonus"
			else:
				_reward_details[i].text = "No Gems"
	_eyebrow.text = "MATCH INCOMPLETE" if result.is_incomplete() else "MATCH COMPLETE"
	_subtitle.text = "Scores at interruption." if result.is_incomplete() else ("Honours shared." if result.is_draw() else ("Well played." if result.winner_id() == TurnEnums.HUMAN_PLAYER_ID else "Until the next match."))
	for i: int in range(2):
		var player: StringName = TurnEnums.HUMAN_PLAYER_ID if i == 0 else TurnEnums.AI_PLAYER_ID
		var winner: bool = result.winner_id() == player
		_accents[i].winner = winner
		_badges[i].modulate.a = 1.0 if winner else 0.0
		var points: Dictionary = result.terms_for(player)
		for key: String in _terms:
			_terms[key][i + 1].text = str(int(points.get(key, 0)))
	visible = true
	_button.disabled = false
	_scroll.scroll_vertical = 0
	_fit_layout()
	if AccessibilitySettings.reduced_motion():
		seek(DURATION)
		return
	seek(0)
	_animation = create_tween()
	_animation.tween_method(seek, 0.0, DURATION, DURATION)
	_animation.finished.connect(_start_accent_loop)

func seek(seconds: float) -> void:
	_elapsed = DURATION if AccessibilitySettings.reduced_motion() else clampf(seconds, 0, DURATION)
	var entrance: float = smoothstep(0, 0.25, _elapsed)
	# Fade only the panel surface: final scores remain readable immediately.
	_card.self_modulate.a = entrance
	var rise: float = (1.0 - entrance) * 8 * _factor
	_card.offset_top = rise
	_card.offset_bottom = rise
	for i: int in range(2):
		var badge_progress: float = smoothstep(0.12, 0.32, _elapsed)
		_badges[i].pivot_offset = _badges[i].size * 0.5
		_badges[i].scale = Vector2.ONE * lerpf(0.95, 1.0, badge_progress)
		_accents[i].pulse = sin(clampf((_elapsed - 0.25) / 0.45, 0, 1) * PI)
		_accents[i].sparkle_alpha = 0.0
		if _result != null and _result.winner_id() == TurnEnums.HUMAN_PLAYER_ID and i == 0:
			_accents[i].sparkle_alpha = sin(clampf((_elapsed - 0.35) / 0.4, 0, 1) * PI)
		_accents[i].queue_redraw()

func _start_accent_loop() -> void:
	_animation = null
	if not visible or _result == null or _result.winner_id() == &"" or AccessibilitySettings.reduced_motion():
		return
	_accent_elapsed = 0.0
	_accent_animation = create_tween().set_loops()
	_accent_animation.tween_method(_seek_winner_accent, 0.0, ACCENT_CYCLE_SECONDS, ACCENT_CYCLE_SECONDS)

func _seek_winner_accent(seconds: float) -> void:
	_accent_elapsed = seconds
	var phase: float = clampf(seconds / ACCENT_CYCLE_SECONDS, 0.0, 1.0)
	var pulse: float = sin(phase * PI)
	for i: int in range(2):
		_accents[i].pulse = pulse
		_accents[i].sparkle_alpha = 0.0
		if _result.winner_id() == TurnEnums.HUMAN_PLAYER_ID and i == 0:
			_accents[i].sparkle_alpha = 0.7 * sin(clampf((phase - 0.25) / 0.4, 0.0, 1.0) * PI)
		_accents[i].queue_redraw()

func clear() -> void:
	_stop_animation()
	_result = null
	_result_key = ""
	visible = false
	if _share_feedback != null:
		_share_feedback.hide()
	if _card != null:
		seek(DURATION)

func _stop_animation() -> void:
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_animation = null
	if _accent_animation != null and _accent_animation.is_valid():
		_accent_animation.kill()
	_accent_animation = null
	_accent_elapsed = 0.0


func can_share_win() -> bool:
	return visible and _result != null and _result.winner_id() == TurnEnums.HUMAN_PLAYER_ID


func set_share_capture_mode(enabled: bool) -> void:
	_footer.visible = not enabled
	if enabled:
		_share_feedback.hide()


func show_share_feedback(message: String) -> void:
	_share_feedback.text = message
	_share_feedback.visible = not message.is_empty()

func _on_visibility_changed() -> void:
	if not visible:
		_stop_animation()
		_result = null
		_result_key = ""

func _exit_tree() -> void:
	_stop_animation()

func _fit_layout() -> void:
	if _margin == null or not is_inside_tree():
		return
	_factor = clampf(size.x / 390.0, 0.65, 1.8)
	var physical: float = maxf(1, 1.0 / get_viewport().get_screen_transform().get_scale().x)
	var compact: bool = size.y / maxf(size.x, 1) < 1.95 or (_reward_card.visible and size.y < 1100.0 * _factor)
	var side: int = roundi(20 * _factor)
	var top: int = roundi(16 * _factor)
	var bottom: int = top
	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe := DisplayServer.get_display_safe_area()
		var window := DisplayServer.window_get_size()
		if safe.has_area() and window.x > 0 and window.y > 0:
			var ratio := size / Vector2(window)
			side = maxi(side, ceili(maxi(safe.position.x, window.x - safe.end.x) * ratio.x))
			top = maxi(top, ceili(safe.position.y * ratio.y))
			bottom = maxi(bottom, ceili((window.y - safe.end.y) * ratio.y))
	for key: String in ["left", "right"]:
		_margin.add_theme_constant_override("margin_" + key, side)
	_margin.add_theme_constant_override("margin_top", top)
	_margin.add_theme_constant_override("margin_bottom", bottom)
	_column.add_theme_constant_override("separation", roundi(12 * _factor))
	_content.add_theme_constant_override("separation", roundi((6 if compact else 10) * _factor))
	_rows.add_theme_constant_override("separation", roundi(5 * _factor))
	_mark.custom_minimum_size = Vector2.ONE * 26 * _factor
	var diameter: float = (70 if compact else 108) * _factor
	_card.add_theme_stylebox_override("panel", T.panel(T.sage(), roundi(24 * _factor), 14 * _factor))
	_card_row.add_theme_constant_override("separation", roundi(12 * _factor))
	for i: int in range(2):
		_portraits[i].custom_minimum_size = Vector2.ONE * diameter
		_portraits[i].get_parent().add_theme_constant_override("separation", roundi(3 * _factor))
		_font(_badges[i], 14, physical)
		_font(_names[i], 18, physical)
		_font(_scores[i], 38 if compact else 42, physical)
		_font(_units[i], 14, physical)
		var max_width: float = (size.x - 2 * side - 44 * _factor) * 0.5
		var font_size: int = _scores[i].get_theme_font_size("font_size")
		while font_size > ceili(14 * physical) and T.BOLD.get_string_size(_scores[i].text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
			font_size -= 1
		_scores[i].add_theme_font_size_override("font_size", font_size)
	_card_slot.custom_minimum_size.y = _card.get_combined_minimum_size().y
	_reward_card.add_theme_stylebox_override("panel", T.panel(T.sage(), roundi(20 * _factor), 10 * _factor))
	_font(_reward_heading, 15, physical)
	_font(_reward_pending, 13, physical)
	for i: int in range(2):
		_font(_reward_names[i], 15, physical)
		_font(_reward_values[i], 27, physical)
		_font(_reward_details[i], 12, physical)
		var gem: Control = _reward_values[i].get_parent().get_child(0)
		gem.custom_minimum_size = Vector2.ONE * 24 * _factor
	for pair: Array in [[_brand, 28], [_eyebrow, 14], [_title, 32 if compact else 38], [_subtitle, 16], [_breakdown_title, 22], [_body, 14]]:
		_font(pair[0], pair[1], physical)
	for row: Node in _rows.get_children():
		if row is HBoxContainer:
			for label: Label in row.get_children():
				_font(label, 16, physical)
	_button.custom_minimum_size.y = maxf(48 * physical, 56 * _factor)
	_button.add_theme_font_size_override("font_size", roundi(22 * _factor))
	_share_button.custom_minimum_size.y = _button.custom_minimum_size.y
	_share_button.add_theme_font_size_override("font_size", roundi(20 * _factor))
	_share_button.add_theme_constant_override("icon_max_width", roundi(22 * _factor))
	_font(_share_feedback, 14, physical)
	seek(_elapsed)
	if _accent_animation != null and _accent_animation.is_running():
		_seek_winner_accent(_accent_elapsed)

func _font(label: Label, reference: float, physical: float) -> void:
	label.add_theme_font_size_override("font_size", maxi(ceili(14 * physical), roundi(reference * _factor)))
