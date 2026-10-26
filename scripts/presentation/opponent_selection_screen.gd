class_name OpponentSelectionScreen
extends Control

## Local AI selection or an authenticated online matchmaking lobby.
signal opponent_selected(rival: Dictionary, rival_portrait: Texture2D)
signal back_requested

const T = preload("res://scripts/presentation/modern_tabletop_theme.gd")

const FAST_INTERVAL: float = 0.0225
const SLOW_INTERVAL: float = 0.17
const RESULT_HOLD_SECONDS: float = 0.275
const ONLINE_REVEAL_MIN_SECONDS: float = 3.0
const ONLINE_REVEAL_MAX_SECONDS: float = 5.0
const ONLINE_SPIN_INTERVAL: float = 0.12
const ONLINE_JOIN_SECONDS: float = 3.0
const CATALOG_CACHE_PATH: String = "user://ai_rivals.json"
const FALLBACK_PORTRAIT: Texture2D = preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_02.tres")
## Explicit references survive Android resource remapping during export.
const RIVAL_PORTRAITS = [
	preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_01.tres"),
	FALLBACK_PORTRAIT,
	preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_03.tres"),
	preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_04.tres"),
	preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_05.tres"),
	preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_06.tres"),
	preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_07.tres"),
	preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_08.tres"),
	preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_09.tres"),
	preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_10.tres"),
	preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_11.tres"),
	preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_12.tres"),
	preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_13.tres"),
	preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_14.tres"),
	preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_15.tres"),
	preload("res://assets/ui/modern_tabletop/avatars/rivals/rival_16.tres"),
]

@onready var mode_picker: OptionButton = %ModePicker
@onready var back_button: Button = %BackButton
var _matchmaking: MatchmakingApiClient = null
var _earnings_label: Label = null
var _online_portrait: Texture2D = null

@onready var rival_portrait: TextureRect = %RivalPortrait
@onready var status_label: Label = %StatusLabel
@onready var difficulty_picker: OptionButton = %DifficultyPicker
@onready var start_button: Button = %StartButton
@onready var cancel_match_button: Button = %CancelMatchButton
@onready var rival_name_label: Label = %RivalName

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _difficulty: int = AiEnums.DEFAULT_DIFFICULTY
var _rivals: Array[Dictionary] = []
var _spin_rivals: Array[Dictionary] = []
var _catalog_request: HTTPRequest = null
var _rival_portraits: Array[Texture2D] = [] as Array[Texture2D]
var _spin_index: int = 0
var _spin_steps: int = 0
var _spin_ticks: int = 0
var _spin_elapsed: float = 0.0
var _current_interval: float = FAST_INTERVAL
var _result_hold: float = 0.0
var _spinning: bool = false
var _started: bool = false
var _emitted: bool = false
var _online_portraits: Array[Texture2D] = [] as Array[Texture2D]
var _online_search_active: bool = false
var _online_revealed: bool = false
var _online_ready_sent: bool = false
var _online_reveal_elapsed: float = 0.0
var _online_reveal_duration: float = 0.0
var _online_spin_elapsed: float = 0.0
var _online_spin_index: int = -1
var _online_join_remaining: float = ONLINE_JOIN_SECONDS
var _online_lobby_key: String = ""


func _ready() -> void:
	_rng.randomize()
	_rivals = AiRivalCatalog.bundled()
	theme = T.create()
	resized.connect(_fit_layout)
	mode_picker.add_item("AI rival", 0)
	mode_picker.add_item("Online lobby", 1)
	mode_picker.select(0)
	mode_picker.item_selected.connect(_on_mode_selected)
	back_button.pressed.connect(_on_back_pressed)
	for difficulty: int in AiEnums.Difficulty.values():
		difficulty_picker.add_item(_difficulty_label(difficulty), difficulty)
	difficulty_picker.select(difficulty_picker.get_item_index(_difficulty))
	difficulty_picker.item_selected.connect(_on_difficulty_selected)
	start_button.pressed.connect(_begin_spin)
	cancel_match_button.pressed.connect(_on_cancel_match_pressed)
	rival_name_label.text = "%s AI" % _difficulty_label(_difficulty).to_upper()
	rival_portrait.texture = FALLBACK_PORTRAIT
	_build_controls()
	_refresh_controls()
	_fit_layout()
	_load_catalog()


func set_player_portrait(portrait: Texture2D) -> void:
	var view := %HumanPortrait as TextureRect
	if view is FramedPlayerAvatar:
		(view as FramedPlayerAvatar).set_portrait(portrait)
	else:
		view.texture = portrait


func set_online_opponent_portrait(portrait: Texture2D) -> void:
	_online_portrait = portrait
	if mode_picker.selected == 1 and _online_revealed:
		(rival_portrait as FramedPlayerAvatar).set_portrait(_online_portrait if _online_portrait != null else FALLBACK_PORTRAIT)


func _process(delta: float) -> void:
	if mode_picker.selected == 1:
		_process_online(delta)
		return
	if not _started or _emitted:
		return
	if not _spinning:
		_result_hold -= delta
		if _result_hold <= 0.0:
			_emitted = true
			opponent_selected.emit(_spin_rivals[_spin_index], _rival_portraits[_spin_index])
		return

	_spin_elapsed += delta
	while _spin_elapsed >= _current_interval and _spinning:
		_spin_elapsed -= _current_interval
		_spin_index = (_spin_index + 1) % _rival_portraits.size()
		_spin_ticks += 1
		(rival_portrait as FramedPlayerAvatar).set_portrait(_rival_portraits[_spin_index])
		rival_name_label.text = String(_spin_rivals[_spin_index]["displayName"])
		var progress: float = clampf(float(_spin_ticks) / float(_spin_steps), 0.0, 1.0)
		var ease_out: float = 1.0 - pow(1.0 - progress, 3.0)
		_current_interval = lerpf(FAST_INTERVAL, SLOW_INTERVAL, ease_out)
		if _spin_ticks >= _spin_steps:
			_spinning = false
			_result_hold = RESULT_HOLD_SECONDS
			status_label.text = "%s · %s" % [_spin_rivals[_spin_index]["displayName"], _difficulty_label(_difficulty)]
			rival_name_label.text = String(_spin_rivals[_spin_index]["displayName"])


func _start_online_search() -> void:
	_online_portraits = _load_difficulty_portraits(_difficulty)
	if _online_portraits.is_empty():
		_online_portraits.append(FALLBACK_PORTRAIT)
	_online_search_active = true
	_online_revealed = false
	_online_ready_sent = false
	_online_reveal_elapsed = 0.0
	_online_reveal_duration = _rng.randf_range(ONLINE_REVEAL_MIN_SECONDS, ONLINE_REVEAL_MAX_SECONDS)
	_online_spin_elapsed = 0.0
	_online_spin_index = _rng.randi_range(0, _online_portraits.size() - 1)
	_online_join_remaining = ONLINE_JOIN_SECONDS
	_online_lobby_key = ""
	(rival_portrait as FramedPlayerAvatar).set_portrait(_online_portraits[_online_spin_index])


func _stop_online_search() -> void:
	_online_search_active = false
	_online_revealed = false
	_online_ready_sent = false
	_online_lobby_key = ""
	_online_portraits.clear()
	_online_join_remaining = ONLINE_JOIN_SECONDS


func _process_online(delta: float) -> void:
	if not _online_search_active or _matchmaking == null:
		return
	if not _online_revealed:
		_online_reveal_elapsed += delta
		if not AccessibilitySettings.reduced_motion():
			_online_spin_elapsed += delta
			while _online_spin_elapsed >= ONLINE_SPIN_INTERVAL:
				_online_spin_elapsed -= ONLINE_SPIN_INTERVAL
				if _online_portraits.size() > 1:
					_online_spin_index = (_online_spin_index + _rng.randi_range(1, _online_portraits.size() - 1)) % _online_portraits.size()
					(rival_portrait as FramedPlayerAvatar).set_portrait(_online_portraits[_online_spin_index])
		if _matchmaking.state == "matched" and _online_reveal_elapsed >= _online_reveal_duration:
			_reveal_online_match()
		return
	if _matchmaking.state != "matched" or _online_ready_sent or bool(_matchmaking.lobby.get("ready", false)) or not bool(_matchmaking.lobby.get("canReady", false)):
		return
	_online_join_remaining = maxf(0.0, _online_join_remaining - delta)
	if _online_join_remaining > 0.0:
		start_button.text = "Joining in %d..." % ceili(_online_join_remaining)
		return
	_online_ready_sent = true
	start_button.text = "Joining..."
	_matchmaking.ready_up()


func _reveal_online_match() -> void:
	_online_revealed = true
	(rival_portrait as FramedPlayerAvatar).set_portrait(_online_portrait if _online_portrait != null else FALLBACK_PORTRAIT)
	_on_matchmaking_changed(_matchmaking.state, _matchmaking.message, _matchmaking.lobby)


func _on_cancel_match_pressed() -> void:
	if _matchmaking == null or mode_picker.selected != 1:
		return
	_stop_online_search()
	_matchmaking.leave()


func _on_difficulty_selected(index: int) -> void:
	_difficulty = difficulty_picker.get_item_id(index)
	_refresh_controls()


func _begin_spin() -> void:
	if mode_picker.selected == 1:
		if _matchmaking != null:
			if _matchmaking.state in ["idle", "failed"]:
				_matchmaking.start_search()
		return
	if _started:
		return
	_difficulty = difficulty_picker.get_item_id(difficulty_picker.selected)
	_spin_rivals.clear()
	_rival_portraits.clear()
	for rival: Dictionary in _rivals:
		if int(rival.get("difficulty", -1)) == _difficulty:
			_spin_rivals.append(rival)
			_rival_portraits.append(_portrait_for_key(String(rival.get("avatarKey", ""))))
	if _spin_rivals.is_empty():
		status_label.text = "No %s rivals are available." % _difficulty_label(_difficulty)
		return
	_spin_index = _rng.randi_range(0, _rival_portraits.size() - 1)
	# Two full passes show every available portrait; the random remainder selects
	# the final portrait uniformly from the selected difficulty's set.
	_spin_steps = _rival_portraits.size() * 2 + _rng.randi_range(0, _rival_portraits.size() - 1)
	_spin_ticks = 0
	_spin_elapsed = 0.0
	_current_interval = FAST_INTERVAL
	_spinning = true
	_started = true
	mode_picker.disabled = true
	difficulty_picker.disabled = true
	start_button.disabled = true
	(rival_portrait as FramedPlayerAvatar).set_portrait(_rival_portraits[_spin_index])
	status_label.text = "Choosing a %s AI rival..." % _difficulty_label(_difficulty)
	rival_name_label.text = "Selecting..."
	_refresh_controls()
	if AccessibilitySettings.reduced_motion():
		_spin_index = (_spin_index + _spin_steps) % _rival_portraits.size()
		(rival_portrait as FramedPlayerAvatar).set_portrait(_rival_portraits[_spin_index])
		_spinning = false
		_result_hold = RESULT_HOLD_SECONDS
		status_label.text = "%s · %s" % [_spin_rivals[_spin_index]["displayName"], _difficulty_label(_difficulty)]
		rival_name_label.text = String(_spin_rivals[_spin_index]["displayName"])


func _portrait_for_key(key: String) -> Texture2D:
	if not key.begins_with("rival_"):
		return FALLBACK_PORTRAIT
	var index: int = key.trim_prefix("rival_").to_int() - 1
	return RIVAL_PORTRAITS[index] if index >= 0 and index < RIVAL_PORTRAITS.size() else FALLBACK_PORTRAIT


func _load_catalog() -> void:
	if FileAccess.file_exists(CATALOG_CACHE_PATH):
		var cached: Array[Dictionary] = AiRivalCatalog.from_response(
			JSON.parse_string(FileAccess.get_file_as_string(CATALOG_CACHE_PATH)))
		if not cached.is_empty():
			_rivals = cached
	_catalog_request = HTTPRequest.new()
	add_child(_catalog_request)
	_catalog_request.request_completed.connect(_on_catalog_received)
	_catalog_request.request(ApiConfiguration.api_base_url() + "/ai-rivals/")


func _on_catalog_received(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var parsed: Array[Dictionary] = AiRivalCatalog.from_response(JSON.parse_string(body.get_string_from_utf8()))
		if not parsed.is_empty() and not _started:
			_rivals = parsed
			var cache: FileAccess = FileAccess.open(CATALOG_CACHE_PATH, FileAccess.WRITE)
			if cache != null:
				cache.store_string(JSON.stringify({"rivals": parsed}))
	if _catalog_request != null:
		_catalog_request.queue_free()
		_catalog_request = null


func _load_difficulty_portraits(difficulty: int) -> Array[Texture2D]:
	# Use the shared visual roster at every difficulty; skill is a text setting and
	# must not be suggested by a rival's age, gender or appearance (design system).
	var portraits: Array[Texture2D] = [] as Array[Texture2D]
	for portrait: Texture2D in RIVAL_PORTRAITS:
		portraits.append(portrait)
	return portraits


func _difficulty_label(difficulty: int) -> String:
	match difficulty:
		AiEnums.Difficulty.EASY:
			return "Easy"
		AiEnums.Difficulty.MEDIUM:
			return "Medium"
		AiEnums.Difficulty.HARD:
			return "Hard"
	return "Easy"


func attach_matchmaking(client: MatchmakingApiClient) -> void:
	if _matchmaking != null and _matchmaking.changed.is_connected(_on_matchmaking_changed):
		_matchmaking.changed.disconnect(_on_matchmaking_changed)
	if _matchmaking != null and _matchmaking.earnings_status_changed.is_connected(_on_earnings_status_changed):
		_matchmaking.earnings_status_changed.disconnect(_on_earnings_status_changed)
	_matchmaking = client
	if _matchmaking != null:
		_matchmaking.changed.connect(_on_matchmaking_changed)
		_matchmaking.earnings_status_changed.connect(_on_earnings_status_changed)
		_matchmaking.refresh_earnings_status()
	_on_mode_selected(mode_picker.selected)
	_refresh_earnings_label()


func _on_earnings_status_changed(_status: Dictionary) -> void:
	_refresh_earnings_label()


func _refresh_earnings_label() -> void:
	if _earnings_label == null:
		return
	_earnings_label.visible = mode_picker.selected == 1
	if not _earnings_label.visible:
		return
	var earnings: Dictionary = _matchmaking.lobby.get("gemEarnings", {}) if _matchmaking != null and _matchmaking.state in ["matched", "playing"] else \
		(_matchmaking.earnings_status if _matchmaking != null else {})
	if earnings.is_empty():
		_earnings_label.text = "Online Gem pot: up to 40 per match · 100 per day · first 2 matches with the same opponent earn Gems."
	elif int(earnings.get("pairMatchesRemaining", 1)) == 0:
		_earnings_label.text = "Gem earnings used for this opponent for 24 hours. You can still play this match."
	elif int(earnings.get("dailyRemaining", 100)) == 0:
		_earnings_label.text = "Today's online Gem earnings are used up. You can still play without earning Gems."
	else:
		_earnings_label.text = "Online Gems: %d of 100 remaining in 24 hours · pot up to 40 · first 2 matches with each opponent earn Gems." % int(earnings.get("dailyRemaining", 100))


func _on_mode_selected(index: int) -> void:
	var online: bool = index == 1
	if not online:
		_stop_online_search()
	get_node("%DifficultyRow").visible = not online
	(rival_portrait as FramedPlayerAvatar).set_portrait(FALLBACK_PORTRAIT)
	if online:
		start_button.text = "Find opponent"
		rival_name_label.text = "Online rival"
		if _matchmaking != null:
			_on_matchmaking_changed(_matchmaking.state, _matchmaking.message, _matchmaking.lobby)
		else:
			status_label.text = "Sign in to find an opponent."
			start_button.disabled = true
	else:
		status_label.text = ""
		rival_name_label.text = "%s AI" % _difficulty_label(_difficulty).to_upper()
		start_button.text = "Choose rival"
		start_button.visible = true
		start_button.disabled = _started
		back_button.text = ""
		cancel_match_button.hide()
	_refresh_controls()
	_refresh_earnings_label()


func _on_matchmaking_changed(state: String, message: String, lobby: Dictionary) -> void:
	if mode_picker.selected != 1:
		return
	var busy: bool = state not in ["idle", "failed"]
	if state in ["idle", "failed", "leaving", "playing"]:
		_stop_online_search()
	elif state == "matched":
		var lobby_key: String = String(lobby.get("id", ""))
		if not _online_search_active or (not _online_lobby_key.is_empty() and _online_lobby_key != lobby_key):
			_start_online_search()
		_online_lobby_key = lobby_key
		if _online_reveal_elapsed >= _online_reveal_duration and not _online_revealed:
			_online_revealed = true
	elif state in ["connecting", "searching", "reconnecting", "authentication"]:
		if not _online_search_active or (state == "searching" and not _online_lobby_key.is_empty()):
			_start_online_search()
		if state == "reconnecting" and _online_ready_sent:
			_online_ready_sent = false
			_online_join_remaining = ONLINE_JOIN_SECONDS
	mode_picker.disabled = busy
	start_button.disabled = busy
	start_button.visible = state != "playing"
	start_button.text = "Find opponent"
	status_label.text = message
	back_button.text = ""
	cancel_match_button.visible = busy and state != "playing" and state != "leaving"
	cancel_match_button.disabled = state == "leaving"
	rival_name_label.text = "SEARCHING..." if busy else "ONLINE RIVAL"
	if state in ["matched", "playing"]:
		if _online_revealed or state == "playing":
			rival_name_label.text = String(lobby.get("opponent", {}).get("displayName", "Opponent"))
			(rival_portrait as FramedPlayerAvatar).set_portrait(_online_portrait if _online_portrait != null else FALLBACK_PORTRAIT)
			if state == "playing":
				start_button.text = "Opening match..."
			elif bool(lobby.get("ready", false)) or _online_ready_sent:
				start_button.text = "Waiting for opponent"
			elif bool(lobby.get("canReady", false)):
				start_button.text = "Joining in %d..." % ceili(_online_join_remaining)
			else:
				start_button.text = "Match unavailable"
		else:
			rival_name_label.text = "MATCH FOUND"
			status_label.text = "Opponent found. Preparing your match..."
			start_button.text = "Finding opponent..."
	elif state in ["connecting", "searching", "reconnecting", "authentication"]:
		start_button.text = "Searching..." if state != "reconnecting" else "Reconnecting..."
	elif not _online_search_active:
		(rival_portrait as FramedPlayerAvatar).set_portrait(FALLBACK_PORTRAIT)
	_refresh_controls()
	_refresh_earnings_label()


func _on_back_pressed() -> void:
	if is_instance_valid(_matchmaking):
		_matchmaking.leave()
	back_requested.emit()


func _exit_tree() -> void:
	if is_instance_valid(_matchmaking):
		if _matchmaking.changed.is_connected(_on_matchmaking_changed):
			_matchmaking.changed.disconnect(_on_matchmaking_changed)
		if _matchmaking.earnings_status_changed.is_connected(_on_earnings_status_changed):
			_matchmaking.earnings_status_changed.disconnect(_on_earnings_status_changed)
		if mode_picker != null and mode_picker.selected == 1:
			_matchmaking.leave()


func select_online() -> void:
	mode_picker.select(1)
	_on_mode_selected(1)


## The hidden pickers retain the existing selection API; visible segments mirror
## their IDs and locks, so local AI and online matchmaking share one state path.
func _build_controls() -> void:
	$Background.color = T.canvas()
	_earnings_label = Label.new()
	_earnings_label.name = "OnlineGemEarnings"
	_earnings_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_earnings_label.add_theme_font_override("font", T.REGULAR)
	_earnings_label.add_theme_font_size_override("font_size", 16)
	_earnings_label.add_theme_color_override("font_color", T.muted())
	%Content.add_child(_earnings_label)
	%Content.move_child(_earnings_label, %Subtitle.get_index() + 1)
	_refresh_earnings_label()
	for i: int in range(%Modes.get_child_count()):
		(%Modes.get_child(i) as Button).pressed.connect(_select_mode.bind(i))
	for i: int in range(%Difficulties.get_child_count()):
		(%Difficulties.get_child(i) as Button).pressed.connect(_select_difficulty.bind(i))
	for label: Label in [%Brand, %Heading]:
		label.add_theme_font_override("font", T.BOLD)
	for label: Label in [%DifficultyLabel, %YouName, %RivalName, %Vs]:
		label.add_theme_font_override("font", T.SEMIBOLD)
	for label: Label in [%Subtitle, %DifficultyHint, %FooterHint, %StatusLabel]:
		label.add_theme_color_override("font_color", T.muted())
	T.style_button(start_button, "primary")
	T.style_button(cancel_match_button, "secondary")
	T.style_back_button(back_button)
	var divider := StyleBoxLine.new()
	divider.color = T.sage()
	divider.thickness = 1
	%Divider.add_theme_stylebox_override("separator", divider)


func _select_mode(index: int) -> void:
	if mode_picker.disabled:
		return
	mode_picker.select(index)
	_on_mode_selected(index)


func _select_difficulty(index: int) -> void:
	if difficulty_picker.disabled:
		return
	difficulty_picker.select(index)
	_on_difficulty_selected(index)


func _style_segment(button: Button, selected: bool, locked: bool) -> void:
	button.set_pressed_no_signal(selected)
	button.disabled = locked
	T.style_button(button, "secondary")
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var fill: Color = T.ink() if selected else (T.canvas_alt() if T.is_dark_mode() else T.canvas())
		if state == "hover":
			fill = fill.lerp(T.sage(), 0.15)
		var box := T.panel(fill, 20, 8)
		box.set_border_width_all(2)
		box.border_color = T.ink() if selected else (T.border() if T.is_dark_mode() else T.sage())
		button.add_theme_stylebox_override(state, box)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(key, T.canvas() if selected else T.muted())


func _refresh_controls() -> void:
	var online: bool = mode_picker.selected == 1
	%Heading.text = "Play online" if online else "Play AI"
	%Subtitle.text = "Find your next opponent." if online else "A friendly face. A fresh challenge."
	%FooterHint.visible = not online
	%ActionRow.add_theme_constant_override("separation", 8)
	%DifficultyRow.visible = not online
	status_label.visible = not status_label.text.is_empty()
	var descriptions: Array[String] = ["A relaxed place to start.", "A balanced challenge.", "Think a few moves ahead."]
	%DifficultyHint.text = descriptions[difficulty_picker.selected]
	for i: int in range(%Modes.get_child_count()):
		_style_segment(%Modes.get_child(i), mode_picker.selected == i, mode_picker.disabled)
	for i: int in range(%Difficulties.get_child_count()):
		var button := %Difficulties.get_child(i) as Button
		var selected: bool = difficulty_picker.selected == i
		button.text = _difficulty_label(difficulty_picker.get_item_id(i)) + (" ✓" if selected else "")
		_style_segment(button, selected, difficulty_picker.disabled)
	if not online and not _started:
		rival_name_label.text = "AI rival"
	# Long online leave/cancel actions need their complete, accessible labels.
	%Brand.get_parent().visible = back_button.text.length() < 8
	%Balance.visible = back_button.text.is_empty()
	back_button.tooltip_text = "Back" if back_button.text.is_empty() else back_button.text


func _fit_layout() -> void:
	if not is_node_ready():
		return
	var factor: float = clampf(size.x / 390.0, 0.7, 1.8)
	var scale: float = maxf(1.0, 1.0 / get_viewport().get_screen_transform().get_scale().x)
	var touch: float = maxf(48.0 * scale, 48.0 * factor)
	var compact: bool = size.y / maxf(size.x, 1.0) < 1.95
	var side: int = roundi(20 * factor)
	var top: int = roundi(12 * factor)
	var bottom: int = roundi(16 * factor)
	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var window: Vector2i = DisplayServer.window_get_size()
		if safe.has_area() and window.x > 0 and window.y > 0:
			var ratio := size / Vector2(window)
			side = maxi(side, ceili(maxi(safe.position.x, window.x - safe.end.x) * ratio.x))
			top = maxi(top, ceili(safe.position.y * ratio.y))
			bottom = maxi(bottom, ceili((window.y - safe.end.y) * ratio.y))
	for key: String in ["left", "right"]:
		$ScreenMargin.add_theme_constant_override("margin_" + key, side)
	$ScreenMargin.add_theme_constant_override("margin_top", top)
	$ScreenMargin.add_theme_constant_override("margin_bottom", bottom)
	$ScreenMargin/Layout.add_theme_constant_override("separation", roundi(10 * factor))
	%Content.add_theme_constant_override("separation", roundi((10 if compact else 16) * factor))
	%DifficultyRow.add_theme_constant_override("separation", roundi(12 * factor))
	%Modes.add_theme_constant_override("separation", roundi(4 * factor))
	%Difficulties.add_theme_constant_override("separation", roundi(6 * factor))
	%MatchupRow.add_theme_constant_override("separation", roundi(10 * factor))
	%Hero.add_theme_stylebox_override("panel", T.panel(T.sage(), roundi(24 * factor), 16 * factor))
	var diameter: float = maxf(72, (size.x - 2 * side - 72 * factor) * 0.5)
	if compact:
		diameter = maxf(72, diameter * 0.62)
	%TileArt.visible = not compact
	for key: String in ["HumanPortrait", "RivalPortrait"]:
		(get_node("%" + key).get_parent() as Control).custom_minimum_size = Vector2.ONE * diameter
		(get_node("%" + key).get_parent() as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	%TileArt.custom_minimum_size.y = 92 * factor
	%Mark.custom_minimum_size = Vector2.ONE * 24 * factor
	%Balance.custom_minimum_size.x = T.BACK_BUTTON_SIZE.x
	back_button.custom_minimum_size = T.BACK_BUTTON_SIZE
	start_button.custom_minimum_size.y = maxf(touch, 58 * factor)
	start_button.add_theme_font_size_override("font_size", roundi(22 * factor))
	cancel_match_button.custom_minimum_size.y = start_button.custom_minimum_size.y
	cancel_match_button.add_theme_font_size_override("font_size", roundi(18 * factor))
	for row: HBoxContainer in [%Modes, %Difficulties]:
		for button: Button in row.get_children():
			button.custom_minimum_size.y = touch
			button.add_theme_font_size_override("font_size", maxi(16, roundi(17 * factor)))
	for pair: Array in [[%Heading, 34], [%Brand, 24], [%Subtitle, 16], [%DifficultyLabel, 20], [%DifficultyHint, 16], [%YouName, 18], [%RivalName, 18], [%Vs, 16], [%StatusLabel, 16], [%FooterHint, 14]]:
		(pair[0] as Label).add_theme_font_size_override("font_size", maxi(14, roundi(float(pair[1]) * factor)))
	%TileArt.queue_redraw()
