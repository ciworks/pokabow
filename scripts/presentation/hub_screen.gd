class_name HubScreen
extends Control
## The hub landing page: the app's front door.
##
## Reached from the splash hold, and the place a finished match returns to. The
## hub is app-shell presentation, not a rules phase: it owns no match state, reads
## no board, and decides nothing about the game (ADR-008 sections 1 and 6). Every
## value it shows comes from a project setting or from the screen the player is
## asking to open, so the match plays identically whether or not the hub exists.
##
## Modern Tabletop hub: presentation follows docs/DESIGN_SYSTEM.md.
## Active games and navigation still come from the app shell.
##
## The settings panel updates the app's accessibility and feedback preferences,
## API endpoint and locally persisted appearance choice. The existing setting
## paths are taken from their owning classes so controls cannot drift from the
## systems that consume them.

## Raised when the player asks to play. The composition root owns what that means
## (it hosts the screens); the hub only reports the request.
signal play_requested
signal resume_game_requested(kind: String, id: String, path: String)
signal profile_requested
signal achievements_requested
signal shop_requested
signal gem_history_requested
signal report_problem_requested
signal tournaments_requested
signal tutorial_requested
signal clear_game_cache_requested
signal tables_requested
signal completed_match_requested(kind: String, id: String)
signal music_volume_changed(level: float)

## Notice copy. Constant so a test and the handler cannot disagree about wording.
const PLAY_LABEL_NEW_GAME: String = "Play Now"
const NOTICE_SOUND_ON: String = "Sound on"
const NOTICE_SOUND_OFF: String = "Sound off"

## The audio bus the cue players use, muted along with `feedback/audio` so the
## switch is audible immediately rather than only from the next match on.
const MASTER_BUS: String = "Master"
const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")

## Fully visible tint for notices; sound state uses a distinct icon.
const TINT_ON: Color = Color(1, 1, 1, 1)

## Notice fade times in seconds: short, because a notice confirms a tap the player
## just made rather than telling them something new.
const NOTICE_FADE_IN: float = 0.14
const NOTICE_FADE_OUT: float = 0.2

var _background: TextureRect = null
var _settings_button: Button = null
var _sound_button: Button = null
var _play_button: Button = null
var _active_game_list: VBoxContainer = null
var _active_games_scroll: ScrollContainer = null
var _active_games_empty: Label = null
var _achievements_button: Button = null
var _profile_button: Button = null
var _home_button: Button = null
var _shop_button: Button = null
var _tournaments_button: Button = null
var _gem_balance_button: Button = null
var _confirmed_gems: int = -1
var _has_active_games: bool = false
var _active_games_snapshot: Array[Dictionary] = []
var _recent_match: Dictionary = {}
var _tables_link: Button
var _recent_panel: PanelContainer
var _recent_row: HBoxContainer
var _more_active: Button
var _notice: PanelContainer = null
var _notice_label: Label = null
var _notice_timer: Timer = null
var _settings_layer: Control = null
var _reduced_motion_toggle: CheckButton = null
var _haptics_toggle: CheckButton = null
var _sound_toggle: CheckButton = null
var _music_volume_slider: HSlider = null
var _music_volume_value: Label = null
var _push_notifications_toggle: CheckButton = null
var _dark_mode_toggle: CheckButton = null
var _settings_close_button: Button = null
var _clear_game_cache_button: Button = null

## The fade currently animating the notice, so a second tap cannot leave the
## first tap's fade-out running against the new notice.
var _notice_tween: Tween = null


func _ready() -> void:
	_bind_nodes()
	theme = Tabletop.create()
	_apply_tabletop_style()
	resized.connect(_fit_layout)
	_fit_layout()
	set_active_games([])
	# Synced BEFORE the controls are connected, and with `set_pressed_no_signal`,
	# so reflecting the stored preference cannot be mistaken for the player
	# flipping a switch (which would write the setting straight back).
	_sync_from_settings()
	_connect_controls()
	set_play_button_label(PLAY_LABEL_NEW_GAME)


func _fit_layout() -> void:
	if not is_node_ready():
		return
	var scale: float = clampf(size.x / 540.0, 0.66, 1.0)
	var margin: MarginContainer = get_node("%PageMargin")
	var side: int = maxi(16, roundi(24 * scale))
	var top: int = maxi(16, roundi(20 * scale))
	var bottom: int = maxi(16, roundi(24 * scale))
	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var window: Vector2i = DisplayServer.window_get_size()
		if window.y > 0 and safe.size.y > 0:
			var ratio: float = size.y / float(window.y)
			top = maxi(top, ceili(safe.position.y * ratio))
			bottom = maxi(bottom, ceili((window.y - safe.end.y) * ratio))
	margin.add_theme_constant_override("margin_left", side)
	margin.add_theme_constant_override("margin_right", side)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_bottom", bottom)
	get_node("%Brand").add_theme_font_size_override("font_size", maxi(32, roundi(55 * scale)))
	var header: HBoxContainer = get_node("%Header") as HBoxContainer
	header.add_theme_constant_override("separation", 4 if size.x < 400 else 10)
	(get_node("%Mark") as Control).custom_minimum_size = Vector2.ONE * maxi(40, roundi(48 * scale))
	_gem_balance_button.custom_minimum_size = Vector2(80 if size.x < 400 else 102, maxi(48, roundi(68 * scale)))
	_gem_balance_button.add_theme_font_size_override("font_size", maxi(14, roundi(19 * scale)))
	_gem_balance_button.add_theme_constant_override("icon_max_width", maxi(22, roundi(28 * scale)))
	_refresh_gem_chip()
	get_node("%Hero").custom_minimum_size.y = minf(190, maxf(125, (size.x - side * 2) * 0.35))
	get_node("%FooterHint").add_theme_font_size_override("font_size", maxi(14, roundi(20 * scale)))
	get_node("%ActiveGamesTitle").add_theme_font_size_override("font_size", maxi(20, roundi(26 * scale)))
	if _tables_link != null:
		_tables_link.add_theme_font_size_override("font_size", maxi(17, roundi(22 * scale)))
		_tables_link.custom_minimum_size.y = maxi(48, roundi(52 * scale))
	if _more_active != null:
		_more_active.add_theme_font_size_override("font_size", maxi(17, roundi(22 * scale)))
	get_node("%Content").add_theme_constant_override("separation", maxi(12, roundi(16 * scale)))
	for button: Button in [_shop_button, _profile_button, _settings_button, _sound_button]:
		button.custom_minimum_size = Vector2.ONE * maxi(48, roundi(72 * scale))
		button.add_theme_constant_override("icon_max_width", maxi(22, roundi(28 * scale)))
	_play_button.custom_minimum_size.y = maxi(52, roundi(72 * scale))
	_play_button.add_theme_font_size_override("font_size", maxi(22, roundi(30 * scale)))
	for button: Button in [_home_button, _achievements_button, _tournaments_button]:
		button.custom_minimum_size.y = maxi(64, roundi(80 * scale))
		var label: Label = button.get_node("Contents/Caption")
		label.add_theme_font_size_override("font_size", maxi(13, roundi(20 * scale)))
	for card: Node in _active_game_list.get_children():
		var status: Label = card.find_child("Status", true, false) as Label
		if status != null:
			status.add_theme_font_size_override("font_size", maxi(14, roundi(19 * scale)))
		var portrait: TextureRect = card.find_child("RivalPortrait", true, false) as TextureRect
		if portrait != null:
			portrait.custom_minimum_size = Vector2.ONE * maxi(44, roundi(64 * scale))
		var score: Label = card.find_child("Score", true, false) as Label
		if score != null:
			score.add_theme_font_size_override("font_size", maxi(18, roundi(22 * scale)))
		var resume: Button = card.find_child("Resume", true, false) as Button
		if resume != null:
			resume.custom_minimum_size = Vector2(maxi(82, roundi(112 * scale)), maxi(48, roundi(72 * scale)))
			resume.add_theme_font_size_override("font_size", maxi(17, roundi(23 * scale)))
	if _recent_row != null:
		var outcome: Label = _recent_row.find_child("RecentOutcome", true, false) as Label
		if outcome != null:
			outcome.add_theme_font_size_override("font_size", maxi(14, roundi(19 * scale)))
		var result_dot: Label = _recent_row.find_child("ResultDot", true, false) as Label
		if result_dot != null:
			result_dot.add_theme_font_size_override("font_size", maxi(13, roundi(17 * scale)))
		var date: Label = _recent_row.find_child("ResultDate", true, false) as Label
		if date != null:
			date.add_theme_font_size_override("font_size", maxi(14, roundi(19 * scale)))
		var portrait: TextureRect = _recent_row.find_child("RecentRivalPortrait", true, false) as TextureRect
		if portrait != null:
			portrait.custom_minimum_size = Vector2.ONE * maxi(44, roundi(64 * scale))
	var notice: Control = _notice
	notice.offset_left = -minf(250, size.x / 2.0 - 20)
	notice.offset_right = minf(250, size.x / 2.0 - 20)
	_fit_settings_panel()


func _apply_tabletop_style() -> void:
	theme = Tabletop.create()
	_background.modulate = Tabletop.canvas()
	get_node("%Brand").add_theme_font_override("font", Tabletop.BOLD)
	Tabletop.style_button(_gem_balance_button, "selected")
	_gem_balance_button.add_theme_color_override("font_color", Tabletop.ink())
	_gem_balance_button.add_theme_font_override("font", Tabletop.SEMIBOLD)
	_gem_balance_button.icon = Tabletop.icon_texture("gem_balance")
	_refresh_gem_chip()
	get_node("%FooterHint").add_theme_color_override("font_color", Tabletop.muted())
	get_node("%ActiveGamesPanel").add_theme_stylebox_override("panel", Tabletop.panel(Tabletop.sage(), 24, 18))
	_recent_panel.add_theme_stylebox_override("panel", Tabletop.panel(Tabletop.sage(), 24, 18))
	get_node("%ActiveGamesTitle").add_theme_color_override("font_color", Tabletop.ink())
	get_node("%ActiveGamesTitle").add_theme_font_override("font", Tabletop.SEMIBOLD)
	_ensure_tables_controls()
	Tabletop.style_button(_tables_link, "quiet")
	Tabletop.style_button(_more_active, "quiet")
	get_node("%SettingsPanel").add_theme_stylebox_override("panel", Tabletop.panel(Tabletop.canvas(), 24, 20))
	for card_name: String in ["PlayAlertsCard", "DisplayCard", "HelpCard"]:
		get_node("%SettingsBox").get_node(card_name).add_theme_stylebox_override(
			"panel", Tabletop.panel(Tabletop.canvas_alt(), 18, 16))
	for heading_name: String in ["PlayAlertsHeading", "DisplayHeading", "HelpHeading"]:
		var heading: Label = get_node("%SettingsBox").find_child(heading_name, true, false) as Label
		heading.add_theme_font_override("font", Tabletop.SEMIBOLD)
		heading.add_theme_color_override("font_color", Tabletop.ink())
	get_node("%SettingsBox").get_node("SettingsTitle").add_theme_font_override("font", Tabletop.BOLD)
	if _music_volume_slider != null:
		Tabletop.style_slider(_music_volume_slider)
	_notice.add_theme_stylebox_override("panel", Tabletop.panel(Tabletop.ink(), 18, 16))
	_notice_label.add_theme_color_override("font_color", Tabletop.canvas())
	for button: Button in [_shop_button, _profile_button, _settings_button, _sound_button]:
		Tabletop.style_button(button, "quiet")
		button.expand_icon = false
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for state: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			button.add_theme_color_override(state, Tabletop.icon_ink())
	_shop_button.icon = Tabletop.icon_texture("shop")
	_profile_button.icon = Tabletop.icon_texture("profile")
	_settings_button.icon = Tabletop.icon_texture("settings")
	_sound_button.icon = Tabletop.icon_texture("sound" if _is_audio_enabled() else "muted")
	for name: String in ["SettingsCloseButton", "HowToPlayButton", "ReportProblemButton", "ClearGameCacheButton"]:
		Tabletop.style_button(get_node("%" + name), "secondary")
	for control: Node in get_node("%SettingsPanel").find_children("*", "Control", true, false):
		if control is BaseButton:
			control.custom_minimum_size.y = maxf(56, control.custom_minimum_size.y)
		if control is Label:
			var label: Label = control
			label.add_theme_font_size_override("font_size", maxi(18, label.get_theme_font_size("font_size")))
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		elif control is CheckButton or control is LineEdit:
			control.add_theme_font_size_override("font_size", 20)
	_make_nav(_home_button, "Home", "home", true)
	_make_nav(_achievements_button, "Achievements", "achievements")
	_make_nav(_tournaments_button, "Tournaments", "tournaments")


func _ensure_tables_controls() -> void:
	if _tables_link != null:
		return
	var box: VBoxContainer = get_node("%ActiveGamesPanel/ActiveGamesBox") as VBoxContainer
	var header: HBoxContainer = get_node("%ActiveGamesHeader") as HBoxContainer
	_tables_link = Button.new()
	_tables_link.name = "ViewAllTables"
	_tables_link.text = "View all ›"
	_tables_link.tooltip_text = "View all active and completed matches"
	Tabletop.style_button(_tables_link, "quiet")
	_tables_link.pressed.connect(func() -> void: tables_requested.emit())
	header.add_child(_tables_link)
	_more_active = Button.new()
	_more_active.name = "MoreActive"
	_more_active.visible = false
	Tabletop.style_button(_more_active, "quiet")
	_more_active.pressed.connect(func() -> void: tables_requested.emit())
	box.add_child(_more_active)


func _make_nav(button: Button, caption: String, icon_name: String, selected: bool = false) -> void:
	button.text = ""
	button.tooltip_text = caption + (" — current page" if selected else "")
	Tabletop.style_button(button, "selected" if selected else "quiet")
	var contents: VBoxContainer = button.get_node_or_null("Contents") as VBoxContainer
	if contents == null:
		contents = VBoxContainer.new()
		contents.name = "Contents"
		contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(contents)
		contents.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		contents.offset_top = 7
		contents.offset_bottom = -7
		contents.alignment = BoxContainer.ALIGNMENT_CENTER
		contents.add_theme_constant_override("separation", 3)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		contents.add_child(icon)
		var label := Label.new()
		label.name = "Caption"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		contents.add_child(label)
	(contents.get_node("Icon") as TextureRect).texture = Tabletop.icon_texture(icon_name)
	var label: Label = contents.get_node("Caption") as Label
	label.text = caption
	label.add_theme_font_override("font", Tabletop.SEMIBOLD if selected else Tabletop.MEDIUM)
	label.add_theme_color_override("font_color", Tabletop.ink() if selected else Tabletop.muted())


func _on_home_pressed() -> void:
	get_node("%PageScroll").scroll_vertical = 0


## Sets the Play action name from the saved match state owned by AppRoot.
func set_play_button_label(label: String) -> void:
	if _play_button == null:
		_bind_nodes()
	if _play_button != null:
		_play_button.text = label


func set_gem_wallet(data: Dictionary) -> void:
	_confirmed_gems = maxi(0, int(data.get("balance", 0))) if data.has("balance") else -1
	_refresh_gem_chip()


func _refresh_gem_chip() -> void:
	if _gem_balance_button == null:
		return
	if _confirmed_gems < 0:
		_gem_balance_button.text = "—"
		_gem_balance_button.tooltip_text = "Gem balance unavailable · Open Gem history"
		return
	var full: String = _format_gems(_confirmed_gems)
	_gem_balance_button.text = _compact_gems(_confirmed_gems) if size.x < 400 else full
	_gem_balance_button.tooltip_text = "%s confirmed Gems · Open Gem history" % full


static func _compact_gems(value: int) -> String:
	if value < 10000:
		return _format_gems(value)
	if value < 1000000:
		return "%.1fk" % (value / 1000.0)
	return "%.1fm" % (value / 1000000.0)


static func _format_gems(value: int) -> String:
	var digits: String = str(value)
	var formatted: String = ""
	for index: int in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			formatted += ","
		formatted += digits.substr(index, 1)
	return formatted


## Rebuilds the active-game panel from the app shell's resumable match records.
func set_active_games(games: Array[Dictionary]) -> void:
	_active_games_snapshot = games.duplicate(true)
	if _active_game_list == null:
		_bind_nodes()
	if _active_game_list == null:
		return
	for child: Node in _active_game_list.get_children():
		_active_game_list.remove_child(child)
		child.free()
	_has_active_games = not games.is_empty()
	var has_tables: bool = _has_active_games or not _recent_match.is_empty()
	get_node("%ActiveGamesSection").visible = has_tables
	get_node("%ActiveGamesPanel").visible = _has_active_games
	Tabletop.style_button(_play_button, "primary")
	if _active_games_empty != null:
		_active_games_empty.visible = false
	if _active_games_scroll != null:
		_active_games_scroll.visible = not games.is_empty()
	if not games.is_empty():
		_active_game_list.add_child(_make_active_game_card(games[0], true))
	if _more_active != null:
		_more_active.visible = games.size() > 1
		_more_active.text = "%d more active ›" % (games.size() - 1)
	_fit_layout()


func _make_active_game_card(game: Dictionary, primary: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Tabletop.panel(Color.TRANSPARENT, 0, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var portrait := TextureRect.new()
	portrait.name = "RivalPortrait"
	portrait.texture = _portrait_for(String(game.get("avatar_path", "")))
	portrait.custom_minimum_size = Vector2(64, 64)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(portrait)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	details.add_theme_constant_override("separation", 2)
	row.add_child(details)
	var status := Label.new()
	status.name = "Status"
	status.text = String(game.get("status_label", "RESUMABLE"))
	status.add_theme_font_override("font", Tabletop.MEDIUM)
	status.add_theme_color_override("font_color", Tabletop.ink())
	status.add_theme_font_size_override("font_size", 19)
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(status)
	var score := Label.new()
	score.name = "Score"
	score.text = String(game.get("score", "You 0  |  Rival 0")).replace("  |  ", " · ")
	score.add_theme_color_override("font_color", Tabletop.muted())
	score.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	details.add_child(score)
	var resume := Button.new()
	resume.name = "Resume"
	resume.text = "Resume"
	resume.tooltip_text = "Resume your game with " + String(game.get("opponent", "Rival"))
	resume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Tabletop.style_button(resume, "primary" if primary else "selected")
	resume.pressed.connect(
		_on_active_game_resume_pressed.bind(
			String(game.get("kind", "ai")),
			String(game.get("id", "")),
			String(game.get("path", ""))
		)
	)
	row.add_child(resume)
	return card


func set_recent_match(entry: Dictionary) -> void:
	_recent_match = entry.duplicate(true)
	if _recent_row == null:
		return
	for child: Node in _recent_row.get_children():
		_recent_row.remove_child(child)
		child.free()
	_recent_panel.visible = not entry.is_empty()
	var has_tables: bool = _has_active_games or not entry.is_empty()
	get_node("%ActiveGamesSection").visible = has_tables
	get_node("%ActiveGamesPanel").visible = _has_active_games
	if entry.is_empty():
		return
	var avatar := TextureRect.new()
	avatar.name = "RecentRivalPortrait"
	avatar.texture = _portrait_for(String(entry.get("avatar_path", "")))
	avatar.custom_minimum_size = Vector2(64, 64)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_recent_row.add_child(avatar)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recent_row.add_child(text_box)
	var result: Dictionary = entry.get("result", {})
	var outcome: int = int(result.get("outcome", 0))
	var result_status := HBoxContainer.new()
	result_status.add_theme_constant_override("separation", 6)
	text_box.add_child(result_status)
	var dot := Label.new()
	dot.name = "ResultDot"
	dot.text = "●"
	dot.add_theme_color_override("font_color", Color("#22B47D") if outcome == TurnEnums.MatchOutcome.HUMAN_WIN else Tabletop.muted())
	dot.add_theme_font_size_override("font_size", 17)
	result_status.add_child(dot)
	var state := Label.new()
	state.name = "RecentOutcome"
	state.text = _outcome_label(outcome).to_upper()
	state.add_theme_font_override("font", Tabletop.MEDIUM)
	state.add_theme_font_size_override("font_size", 19)
	state.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_status.add_child(state)
	var opponent_name: String = String(entry.get("opponent", "Rival"))
	var score := Label.new()
	score.text = "You %d · %s %d" % [int(result.get("human_score", 0)), opponent_name, int(result.get("ai_score", 0))]
	score.add_theme_color_override("font_color", Tabletop.muted())
	score.add_theme_font_size_override("font_size", 21)
	score.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_box.add_child(score)
	var actions := VBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_recent_row.add_child(actions)
	var date := Label.new()
	date.name = "ResultDate"
	date.text = _recent_date(String(entry.get("finished_at", "")))
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	date.add_theme_color_override("font_color", Tabletop.muted())
	date.add_theme_font_size_override("font_size", 19)
	actions.add_child(date)
	var details := Button.new()
	details.name = "Details"
	details.text = "Details ›"
	details.tooltip_text = "View completed match with " + opponent_name
	details.custom_minimum_size = Vector2(92, 72)
	Tabletop.style_button(details, "quiet")
	details.add_theme_font_size_override("font_size", 21)
	details.pressed.connect(func() -> void:
		completed_match_requested.emit(String(entry.get("kind", "")), String(entry.get("id", ""))))
	actions.add_child(details)
	_fit_layout()


static func _outcome_label(outcome: int) -> String:
	match outcome:
		TurnEnums.MatchOutcome.HUMAN_WIN:
			return "Win"
		TurnEnums.MatchOutcome.AI_WIN:
			return "Loss"
		TurnEnums.MatchOutcome.DRAW:
			return "Draw"
	return "Incomplete"


static func _recent_date(iso: String) -> String:
	if iso.length() < 10:
		return "Recently"
	var day: String = iso.substr(0, 10)
	var today: String = Time.get_date_string_from_system(true)
	if day == today:
		return "Today"
	var yesterday: String = Time.get_date_string_from_unix_time(
		Time.get_unix_time_from_datetime_string(today + "T00:00:00") - 86400)
	return "Yesterday" if day == yesterday else day


static func _portrait_for(path: String) -> Texture2D:
	if path.begins_with("res://"):
		return load(path) as Texture2D
	if path.begins_with("user://") and FileAccess.file_exists(path):
		var image := Image.new()
		if image.load(ProjectSettings.globalize_path(path)) == OK:
			return ImageTexture.create_from_image(image)
	return load("res://assets/ui/modern_tabletop/avatars/rivals/rival_01.tres") as Texture2D


func _on_active_game_resume_pressed(kind: String, id: String, path: String) -> void:
	resume_game_requested.emit(kind, id, path)


## Resolves every node this screen drives.
##
## `get_node_or_null` rather than `@onready`, so a scene that lost a node reports
## one clear error per missing name instead of failing to instantiate at all.
func _bind_nodes() -> void:
	_background = get_node_or_null("%Background") as TextureRect
	_settings_button = get_node_or_null("%SettingsButton") as Button
	_sound_button = get_node_or_null("%SoundButton") as Button
	_play_button = get_node_or_null("%PlayButton") as Button
	_active_game_list = get_node_or_null("%ActiveGameList") as VBoxContainer
	_active_games_scroll = get_node_or_null("%ActiveGamesScroll") as ScrollContainer
	_active_games_empty = get_node_or_null("%ActiveGamesEmpty") as Label
	_recent_panel = get_node_or_null("%RecentMatchPanel") as PanelContainer
	_recent_row = get_node_or_null("%RecentResultRow") as HBoxContainer
	_achievements_button = get_node_or_null("%AchievementsButton") as Button
	_profile_button = get_node_or_null("%ProfileButton") as Button
	_home_button = get_node_or_null("%HomeButton") as Button
	_shop_button = get_node_or_null("%ShopButton") as Button
	_tournaments_button = get_node_or_null("%TournamentsButton") as Button
	_gem_balance_button = get_node_or_null("%GemBalanceButton") as Button
	_notice = get_node_or_null("%Notice") as PanelContainer
	_notice_label = get_node_or_null("%NoticeLabel") as Label
	_notice_timer = get_node_or_null("%NoticeTimer") as Timer
	_settings_layer = get_node_or_null("%SettingsLayer") as Control
	_reduced_motion_toggle = get_node_or_null("%ReducedMotionToggle") as CheckButton
	_haptics_toggle = get_node_or_null("%HapticsToggle") as CheckButton
	_sound_toggle = get_node_or_null("%SoundToggle") as CheckButton
	_music_volume_slider = get_node_or_null("%MusicVolumeSlider") as HSlider
	_music_volume_value = get_node_or_null("%MusicVolumeValue") as Label
	_push_notifications_toggle = get_node_or_null("%PushNotificationsToggle") as CheckButton
	_dark_mode_toggle = get_node_or_null("%DarkModeToggle") as CheckButton
	_settings_close_button = get_node_or_null("%SettingsCloseButton") as Button
	_clear_game_cache_button = get_node_or_null("%ClearGameCacheButton") as Button


## Connects every control. Idempotent, and safe to call more than once.
func _connect_controls() -> void:
	_connect_button(_settings_button, _on_settings_pressed)
	_connect_button(_sound_button, _on_sound_pressed)
	_connect_button(_play_button, _on_play_pressed)
	_connect_button(_achievements_button, _on_achievements_pressed)
	_connect_button(_profile_button, _on_profile_pressed)
	_connect_button(_home_button, _on_home_pressed)
	_connect_button(_shop_button, _on_shop_pressed)
	_connect_button(_gem_balance_button, _on_gem_history_pressed)
	_connect_button(_tournaments_button, _on_tournaments_pressed)
	_connect_button(_settings_close_button, _on_settings_close_pressed)
	_connect_button(_clear_game_cache_button, _on_clear_game_cache_pressed)
	_connect_button(get_node("%HowToPlayButton"), _on_how_to_play_pressed)
	_connect_button(get_node("%ReportProblemButton"), _on_report_problem_pressed)
	_connect_toggle(_reduced_motion_toggle, _on_reduced_motion_toggled)
	_connect_toggle(_haptics_toggle, _on_haptics_toggled)
	_connect_toggle(_sound_toggle, _on_sound_toggled)
	if _music_volume_slider != null and not _music_volume_slider.value_changed.is_connected(_on_music_volume_changed):
		_music_volume_slider.value_changed.connect(_on_music_volume_changed)
	_connect_toggle(_push_notifications_toggle, _on_push_notifications_toggled)
	_connect_toggle(_dark_mode_toggle, _on_dark_mode_toggled)
	if not TurnNotifications.preference_changed.is_connected(_on_notification_preference_changed):
		TurnNotifications.preference_changed.connect(_on_notification_preference_changed)
	if _notice_timer != null and not _notice_timer.timeout.is_connected(_on_notice_timeout):
		_notice_timer.timeout.connect(_on_notice_timeout)


func _connect_button(button: Button, handler: Callable) -> void:
	if button == null:
		push_error("HubScreen: a control is missing; '%s' was not wired." % handler.get_method())
		return
	if not button.pressed.is_connected(handler):
		button.pressed.connect(handler)


func _connect_toggle(toggle: BaseButton, handler: Callable) -> void:
	if toggle == null:
		push_error("HubScreen: a toggle is missing; '%s' was not wired." % handler.get_method())
		return
	if not toggle.toggled.is_connected(handler):
		toggle.toggled.connect(handler)


# --- Preferences -----------------------------------------------------------
#
# The panel is the writing end of settings the rest of the app already reads.
# Runtime accessibility/audio settings remain session-scoped; appearance uses its
# own small user:// config so the player's theme choice survives a fresh launch.

## Reflects the stored preferences into the panel without emitting `toggled`.
func _sync_from_settings() -> void:
	if _reduced_motion_toggle != null:
		_reduced_motion_toggle.set_pressed_no_signal(AccessibilitySettings.reduced_motion())
	if _haptics_toggle != null:
		_haptics_toggle.set_pressed_no_signal(_is_haptics_enabled())
	if _sound_toggle != null:
		_sound_toggle.set_pressed_no_signal(_is_audio_enabled())
	if _music_volume_slider != null:
		_music_volume_slider.set_value_no_signal(roundi(MusicPreferences.volume() * 100.0))
		_update_music_volume_label()
	if _push_notifications_toggle != null:
		_push_notifications_toggle.set_pressed_no_signal(TurnNotifications.enabled)
		_push_notifications_toggle.disabled = not TurnNotifications.is_available()
	if _dark_mode_toggle != null:
		_dark_mode_toggle.set_pressed_no_signal(AppearanceSettings.dark_mode)
	(get_node("%Hero") as AnimatedHubHero).set_motion_enabled(not AccessibilitySettings.reduced_motion())
	_apply_audio_state()


## Reads the haptics preference with the same default `FeedbackAdapter` uses.
func _is_haptics_enabled() -> bool:
	return bool(ProjectSettings.get_setting(FeedbackAdapter.SETTING_PATH, true))


## Reads the cue-sound preference with the same default `FeedbackAdapter` uses.
func _is_audio_enabled() -> bool:
	return bool(ProjectSettings.get_setting(FeedbackAdapter.AUDIO_SETTING_PATH, true))


## Applies the stored cue-sound preference to the running build.
func _apply_audio_state() -> void:
	var enabled: bool = _is_audio_enabled()
	AudioServer.set_bus_mute(AudioServer.get_bus_index(MASTER_BUS), not enabled)
	if _sound_button != null:
		_sound_button.modulate = TINT_ON
		_sound_button.icon = Tabletop.icon_texture("sound" if enabled else "muted")
		_sound_button.tooltip_text = "Sound on" if enabled else "Sound off"


## Stores the cue-sound preference and applies it immediately.
##
## Both halves matter: the setting is what the next match's `FeedbackAdapter`
## reads, and the bus mute is what makes the switch audible right now, on a screen
## where no adapter exists yet.
func _set_audio_enabled(enabled: bool) -> void:
	ProjectSettings.set_setting(FeedbackAdapter.AUDIO_SETTING_PATH, enabled)
	_apply_audio_state()
	if _sound_toggle != null:
		_sound_toggle.set_pressed_no_signal(enabled)


# --- Controls --------------------------------------------------------------

func _on_play_pressed() -> void:
	play_requested.emit()


func _on_achievements_pressed() -> void:
	achievements_requested.emit()


func _on_profile_pressed() -> void:
	profile_requested.emit()


func _on_how_to_play_pressed() -> void:
	close_settings()
	tutorial_requested.emit()


func _on_report_problem_pressed() -> void:
	close_settings()
	report_problem_requested.emit()


func _on_shop_pressed() -> void:
	shop_requested.emit()


func _on_gem_history_pressed() -> void:
	gem_history_requested.emit()


func _on_tournaments_pressed() -> void:
	tournaments_requested.emit()


## Flips the cue-sound preference from the corner icon.
func _on_sound_pressed() -> void:
	var enabled: bool = not _is_audio_enabled()
	_set_audio_enabled(enabled)
	show_notice(NOTICE_SOUND_ON if enabled else NOTICE_SOUND_OFF)


func _on_settings_pressed() -> void:
	# Re-read on open, so the panel always shows what the build is actually using
	# rather than what it showed last time it was opened.
	_sync_from_settings()
	open_settings()


func _on_settings_close_pressed() -> void:
	close_settings()


func _on_clear_game_cache_pressed() -> void:
	clear_game_cache_requested.emit()


func _on_reduced_motion_toggled(pressed: bool) -> void:
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, pressed)
	(get_node("%Hero") as AnimatedHubHero).set_motion_enabled(not pressed)


func _on_haptics_toggled(pressed: bool) -> void:
	ProjectSettings.set_setting(FeedbackAdapter.SETTING_PATH, pressed)


func _on_sound_toggled(pressed: bool) -> void:
	_set_audio_enabled(pressed)


func _on_music_volume_changed(value: float) -> void:
	var level: float = value / 100.0
	MusicPreferences.set_volume(level)
	_update_music_volume_label()
	music_volume_changed.emit(level)


func _update_music_volume_label() -> void:
	if _music_volume_value != null and _music_volume_slider != null:
		_music_volume_value.text = "%d%%" % roundi(_music_volume_slider.value)


func _on_push_notifications_toggled(pressed: bool) -> void:
	if not TurnNotifications.set_enabled(pressed):
		_sync_from_settings()
		show_notice("Notifications are unavailable on this device")


func _on_notification_preference_changed(_enabled: bool) -> void:
	_sync_from_settings()


func _on_dark_mode_toggled(pressed: bool) -> void:
	AppearanceSettings.set_dark_mode(pressed)
	_apply_tabletop_style()
	set_active_games(_active_games_snapshot)
	set_recent_match(_recent_match)


# --- Settings panel --------------------------------------------------------

## Opens the settings panel. Public so a test can drive the panel without
## simulating a tap.
func open_settings() -> void:
	if _settings_layer == null:
		push_error("HubScreen.open_settings: the settings layer is missing.")
		return
	_settings_layer.visible = true
	_settings_close_button.grab_focus()
	get_node("%SettingsScroll").set_deferred("scroll_vertical", 0)


## Closes the settings panel.
func close_settings() -> void:
	if _settings_layer != null:
		_settings_layer.visible = false


## Returns whether the settings panel is open.
func is_settings_open() -> bool:
	return _settings_layer != null and _settings_layer.visible


## Lets the platform's back action close the panel. No mouse mode is captured
## anywhere in this screen, so this is a convenience rather than an escape hatch.
func _unhandled_input(event: InputEvent) -> void:
	if not is_settings_open():
		return
	if event.is_action_pressed("ui_cancel"):
		close_settings()
		get_viewport().set_input_as_handled()


# --- Notice ----------------------------------------------------------------

## Shows a short message over the hub.
##
## Honours reduced motion: with animation switched off the notice simply appears
## and disappears, and nothing about what it says changes
## (docs/sections/05-mobile-ux.md section 6).
func show_notice(text: String) -> void:
	if _notice == null or _notice_label == null:
		return
	_notice_label.text = text
	_notice.visible = true
	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()
	if AccessibilitySettings.reduced_motion():
		_notice.modulate = TINT_ON
	else:
		_notice.modulate = Color(1, 1, 1, 0)
		_notice_tween = create_tween()
		_notice_tween.tween_property(_notice, "modulate:a", 1.0, NOTICE_FADE_IN)
	if _notice_timer != null:
		# A second tap restarts the hold rather than queueing a second hide.
		_notice_timer.start()


func _on_notice_timeout() -> void:
	if _notice == null:
		return
	if AccessibilitySettings.reduced_motion():
		_hide_notice()
		return
	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, NOTICE_FADE_OUT)
	_notice_tween.tween_callback(_hide_notice)


func _hide_notice() -> void:
	if _notice != null:
		_notice.visible = false


## Returns whether the notice is currently visible, for a smoke test.
func is_notice_visible() -> bool:
	return _notice != null and _notice.visible


## Returns the text the notice is currently showing.
func current_notice() -> String:
	return "" if _notice_label == null else _notice_label.text


## The hub's background, so the composition root can report whether the artwork
## has landed without knowing the node layout.
func background_texture() -> Texture2D:
	return null if _background == null else _background.texture


func _fit_settings_panel() -> void:
	var panel: Control = get_node("%SettingsPanel")
	var dimensions := Vector2(minf(500.0, maxf(0.0, size.x - 32.0)), minf(680.0, maxf(0.0, size.y - 32.0)))
	panel.offset_left = -dimensions.x / 2.0
	panel.offset_right = dimensions.x / 2.0
	panel.offset_top = -dimensions.y / 2.0
	panel.offset_bottom = dimensions.y / 2.0
