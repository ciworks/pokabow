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
## The three named destinations in the reference brief - Achievements, My Profile
## and the Shop - are Phase 3 features (docs/sections/06-game-modes.md sections 3
## and 4). They are shown as the reference asks, but pressing one says so plainly
## instead of opening an empty screen, so the hub never claims a feature the game
## does not have (AGENTS.md sections 14 and 22).
##
## The settings panel writes the same three project settings the rest of the app
## already reads: `accessibility/reduced_motion` through `AccessibilitySettings`
## and `feedback/haptics` / `feedback/audio` through `FeedbackAdapter`. The paths
## are taken from those classes rather than retyped here, so the panel cannot
## drift from what the systems actually read.

## Raised when the player asks to play. The composition root owns what that means
## (it hosts the screens); the hub only reports the request.
signal play_requested
signal profile_requested
signal achievements_requested
signal clear_game_cache_requested

## Notice copy. Constant so a test and the handler cannot disagree about wording.
const NOTICE_PROFILE: String = "Your profile is not built yet."
const NOTICE_SHOP: String = "The shop is not built yet."
const PLAY_LABEL_NEW_GAME: String = "New Game"
const PLAY_LABEL_RESUME: String = "Resume"
const NOTICE_SOUND_ON: String = "Sound on"
const NOTICE_SOUND_OFF: String = "Sound off"

## The audio bus the cue players use, muted along with `feedback/audio` so the
## switch is audible immediately rather than only from the next match on.
const MASTER_BUS: String = "Master"

## Icon tint when sound is on, and when it is muted.
const TINT_ON: Color = Color(1, 1, 1, 1)
const TINT_MUTED: Color = Color(1, 1, 1, 0.4)

## How much a button's fill brightens on hover and darkens while held.
const HOVER_LIGHTEN: float = 1.14
const PRESSED_DARKEN: float = 0.86

## Notice fade times in seconds: short, because a notice confirms a tap the player
## just made rather than telling them something new.
const NOTICE_FADE_IN: float = 0.14
const NOTICE_FADE_OUT: float = 0.2

var _background: TextureRect = null
var _settings_button: Button = null
var _sound_button: Button = null
var _play_button: Button = null
var _achievements_button: Button = null
var _profile_button: Button = null
var _shop_button: Button = null
var _notice: PanelContainer = null
var _notice_label: Label = null
var _notice_timer: Timer = null
var _settings_layer: Control = null
var _reduced_motion_toggle: CheckButton = null
var _haptics_toggle: CheckButton = null
var _sound_toggle: CheckButton = null
var _api_ip_input: LineEdit = null
var _api_ip_save_button: Button = null
var _api_ip_status: Label = null
var _settings_close_button: Button = null
var _clear_game_cache_button: Button = null

## The fade currently animating the notice, so a second tap cannot leave the
## first tap's fade-out running against the new notice.
var _notice_tween: Tween = null


func _ready() -> void:
	_bind_nodes()
	_apply_button_states()
	resized.connect(_fit_destination_buttons)
	_fit_destination_buttons()
	# Synced BEFORE the controls are connected, and with `set_pressed_no_signal`,
	# so reflecting the stored preference cannot be mistaken for the player
	# flipping a switch (which would write the setting straight back).
	_sync_from_settings()
	_connect_controls()
	set_play_button_label(PLAY_LABEL_NEW_GAME)


func _fit_destination_buttons() -> void:
	# Keep full labels readable in one row, with larger type on wider viewports.
	var font_size: int = clampi(int(size.x / 27.0), 14, 24)
	for button: Button in [_achievements_button, _profile_button, _shop_button]:
		if button != null:
			button.add_theme_font_size_override("font_size", font_size)


## Sets the Play action name from the saved match state owned by AppRoot.
func set_play_button_label(label: String) -> void:
	if _play_button == null:
		_bind_nodes()
	if _play_button != null:
		_play_button.text = label


## Resolves every node this screen drives.
##
## `get_node_or_null` rather than `@onready`, so a scene that lost a node reports
## one clear error per missing name instead of failing to instantiate at all.
func _bind_nodes() -> void:
	_background = get_node_or_null("%Background") as TextureRect
	_settings_button = get_node_or_null("%SettingsButton") as Button
	_sound_button = get_node_or_null("%SoundButton") as Button
	_play_button = get_node_or_null("%PlayButton") as Button
	_achievements_button = get_node_or_null("%AchievementsButton") as Button
	_profile_button = get_node_or_null("%ProfileButton") as Button
	_shop_button = get_node_or_null("%ShopButton") as Button
	_notice = get_node_or_null("%Notice") as PanelContainer
	_notice_label = get_node_or_null("%NoticeLabel") as Label
	_notice_timer = get_node_or_null("%NoticeTimer") as Timer
	_settings_layer = get_node_or_null("%SettingsLayer") as Control
	_reduced_motion_toggle = get_node_or_null("%ReducedMotionToggle") as CheckButton
	_haptics_toggle = get_node_or_null("%HapticsToggle") as CheckButton
	_sound_toggle = get_node_or_null("%SoundToggle") as CheckButton
	_api_ip_input = get_node_or_null("%ApiIpInput") as LineEdit
	_api_ip_save_button = get_node_or_null("%ApiIpSaveButton") as Button
	_api_ip_status = get_node_or_null("%ApiIpStatus") as Label
	_settings_close_button = get_node_or_null("%SettingsCloseButton") as Button
	_clear_game_cache_button = get_node_or_null("%ClearGameCacheButton") as Button


## Gives every styled button a hover and pressed look derived from its authored
## normal look.
##
## Godot falls back to the default theme for any state an override does not
## cover, which would flash a grey box over a gold gem the moment it is pressed.
## Deriving the two extra states from the authored style keeps the palette in the
## scene file and still leaves no state unstyled.
func _apply_button_states() -> void:
	var buttons: Array[Button] = [
		_settings_button,
		_sound_button,
		_play_button,
		_achievements_button,
		_profile_button,
		_shop_button,
		_api_ip_save_button,
		_settings_close_button,
		_clear_game_cache_button,
	]
	for button: Button in buttons:
		if button == null:
			continue
		var normal: StyleBox = button.get_theme_stylebox("normal")
		var hover: StyleBox = _shifted_style(normal, HOVER_LIGHTEN)
		var pressed: StyleBox = _shifted_style(normal, PRESSED_DARKEN)
		if hover != null:
			button.add_theme_stylebox_override("hover", hover)
			button.add_theme_stylebox_override("focus", hover)
		if pressed != null:
			button.add_theme_stylebox_override("pressed", pressed)


## Returns a copy of `style` with its fill scaled by `factor`.
##
## A null or non-flat style is returned unchanged, so a button whose look the
## theme owns simply keeps the theme's own hover and pressed states.
func _shifted_style(style: StyleBox, factor: float) -> StyleBox:
	var flat: StyleBoxFlat = style as StyleBoxFlat
	if flat == null:
		return null
	var adjusted: StyleBoxFlat = flat.duplicate() as StyleBoxFlat
	var colour: Color = adjusted.bg_color
	adjusted.bg_color = Color(
		clampf(colour.r * factor, 0.0, 1.0),
		clampf(colour.g * factor, 0.0, 1.0),
		clampf(colour.b * factor, 0.0, 1.0),
		colour.a
	)
	return adjusted


## Connects every control. Idempotent, and safe to call more than once.
func _connect_controls() -> void:
	_connect_button(_settings_button, _on_settings_pressed)
	_connect_button(_sound_button, _on_sound_pressed)
	_connect_button(_play_button, _on_play_pressed)
	_connect_button(_achievements_button, _on_achievements_pressed)
	_connect_button(_profile_button, _on_profile_pressed)
	_connect_button(_shop_button, _on_shop_pressed)
	_connect_button(_settings_close_button, _on_settings_close_pressed)
	_connect_button(_clear_game_cache_button, _on_clear_game_cache_pressed)
	_connect_toggle(_reduced_motion_toggle, _on_reduced_motion_toggled)
	_connect_toggle(_haptics_toggle, _on_haptics_toggled)
	_connect_toggle(_sound_toggle, _on_sound_toggled)
	_connect_button(_api_ip_save_button, _on_api_ip_save_pressed)
	if _api_ip_input != null and not _api_ip_input.text_submitted.is_connected(_on_api_ip_text_submitted):
		_api_ip_input.text_submitted.connect(_on_api_ip_text_submitted)
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
# A write is session-scoped on purpose: nothing here calls `ProjectSettings.save()`,
# because that would rewrite project.godot while the player is tapping a switch.
# The hub therefore changes the running build, and a fresh launch returns to the
# values in project.godot.

## Reflects the stored preferences into the panel without emitting `toggled`.
func _sync_from_settings() -> void:
	if _reduced_motion_toggle != null:
		_reduced_motion_toggle.set_pressed_no_signal(AccessibilitySettings.reduced_motion())
	if _haptics_toggle != null:
		_haptics_toggle.set_pressed_no_signal(_is_haptics_enabled())
	if _sound_toggle != null:
		_sound_toggle.set_pressed_no_signal(_is_audio_enabled())
	if _api_ip_input != null:
		_api_ip_input.text = ApiConfiguration.server_ip()
	if _api_ip_status != null:
		_api_ip_status.text = ""
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
		_sound_button.modulate = TINT_ON if enabled else TINT_MUTED


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


func _on_shop_pressed() -> void:
	show_notice(NOTICE_SHOP)


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


func _on_haptics_toggled(pressed: bool) -> void:
	ProjectSettings.set_setting(FeedbackAdapter.SETTING_PATH, pressed)


func _on_sound_toggled(pressed: bool) -> void:
	_set_audio_enabled(pressed)


## Saves a validated IP for auth, game sync and achievements immediately.
func _on_api_ip_save_pressed() -> void:
	if _api_ip_input == null or _api_ip_status == null:
		return
	if not ApiConfiguration.set_server_ip(_api_ip_input.text):
		_api_ip_status.text = "Enter a valid IP address."
		return
	_api_ip_input.text = ApiConfiguration.server_ip()
	_api_ip_status.text = "Server address saved."


func _on_api_ip_text_submitted(value: String) -> void:
	if _api_ip_input != null:
		_api_ip_input.text = value
	_on_api_ip_save_pressed()


# --- Settings panel --------------------------------------------------------

## Opens the settings panel. Public so a test can drive the panel without
## simulating a tap.
func open_settings() -> void:
	if _settings_layer == null:
		push_error("HubScreen.open_settings: the settings layer is missing.")
		return
	_settings_layer.visible = true


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
