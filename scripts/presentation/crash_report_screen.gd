class_name CrashReportScreen
extends Control
## Player-reviewed report. Email opens only after the player taps the action.

signal back_requested
signal email_requested(report: String)
signal discard_requested

const T = preload("res://scripts/presentation/modern_tabletop_theme.gd")
const MAX_NOTES_LENGTH := 2000
const MAX_LOG_LENGTH := 3000

var _margin: MarginContainer
var _notes: TextEdit
var _log: TextEdit
var _status: Label
var _intro: Label
var _discard: Button


func _ready() -> void:
	theme = T.create()
	_build()
	resized.connect(_fit)
	_fit()


func _build() -> void:
	var background := ColorRect.new()
	background.color = T.canvas()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin = MarginContainer.new()
	add_child(_margin)
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	_margin.add_child(page)
	var header := HBoxContainer.new()
	page.add_child(header)
	var back := Button.new()
	back.name = "BackButton"
	back.tooltip_text = "Back to Home"
	T.style_back_button(back)
	back.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(back)
	var title := _label("Report a problem", 30, T.BOLD, T.ink())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "ReportScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	page.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "ReportBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroll.add_child(body)
	_intro = _label("Tell us what happened. Review the log excerpt before opening your email app.", 18, T.REGULAR, T.muted())
	body.add_child(_intro)
	var description := _card(body, "DescriptionCard")
	description.add_child(_label("What happened?", 23, T.SEMIBOLD, T.ink()))
	description.add_child(_label("What were you doing just before the problem?", 16, T.REGULAR, T.muted()))
	_notes = TextEdit.new()
	_notes.name = "PlayerDescription"
	_notes.custom_minimum_size.y = 190
	_notes.placeholder_text = "Describe the steps, the screen you were on, and anything you noticed..."
	_notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_notes.add_theme_font_size_override("font_size", 18)
	_notes.add_theme_stylebox_override("normal", T.panel(T.canvas(), 14, 12))
	_notes.add_theme_color_override("font_color", T.ink())
	description.add_child(_notes)
	var log_card := _card(body, "LogCard")
	log_card.add_child(_label("Engine log excerpt", 23, T.SEMIBOLD, T.ink()))
	log_card.add_child(_label("The latest 3,000 characters are included. You can edit or remove anything private.", 16, T.REGULAR, T.muted()))
	_log = TextEdit.new()
	_log.name = "LogExcerpt"
	_log.custom_minimum_size.y = 170
	_log.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_log.add_theme_font_size_override("font_size", 15)
	_log.add_theme_stylebox_override("normal", T.panel(T.canvas(), 14, 12))
	_log.add_theme_color_override("font_color", T.ink())
	log_card.add_child(_log)
	var disclosure := _label("Your email app will open with this report addressed to support@pokabow.game. Check it there before sending.", 16, T.REGULAR, T.muted())
	body.add_child(disclosure)
	_discard = Button.new()
	_discard.name = "DiscardCrashLog"
	_discard.text = "Discard saved crash log"
	_discard.custom_minimum_size.y = 52
	T.style_button(_discard, "quiet")
	_discard.pressed.connect(func() -> void: discard_requested.emit())
	_discard.hide()
	body.add_child(_discard)
	_status = _label("", 16, T.REGULAR, T.muted())
	_status.name = "EmailStatus"
	_status.hide()
	page.add_child(_status)
	var email := Button.new()
	email.name = "EmailSupportButton"
	email.text = "Open email to support"
	email.custom_minimum_size.y = 56
	T.style_button(email, "primary")
	email.pressed.connect(_on_email_pressed)
	page.add_child(email)


func set_report(report: Dictionary, is_pending: bool) -> void:
	_intro.text = "The previous session ended unexpectedly. Tell us what happened and review the log before opening your email app." \
		if is_pending else "Tell us what happened. Review the log excerpt before opening your email app."
	var excerpt := String(report.get("log", "No engine log was available for this session."))
	_log.text = excerpt.right(MAX_LOG_LENGTH)
	_discard.visible = is_pending


func show_email_status(message: String) -> void:
	_status.text = message
	_status.show()


func clear_saved_state() -> void:
	_discard.hide()
	show_email_status("Saved crash log discarded. You can still send the text currently shown.")


func _on_email_pressed() -> void:
	var description := _notes.text.strip_edges()
	if description.length() > MAX_NOTES_LENGTH:
		show_email_status("Please shorten your description to 2,000 characters.")
		_notes.grab_focus()
		return
	_status.hide()
	email_requested.emit(CrashReportService.report_text(description, _log.text.right(MAX_LOG_LENGTH)))


func _card(parent: VBoxContainer, name: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = name
	panel.add_theme_stylebox_override("panel", T.panel(T.canvas_alt(), 18, 16))
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	return column


func _label(value: String, font_size: int, font: Font, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _fit() -> void:
	if not is_node_ready():
		return
	var side := maxi(16, roundi(24 * clampf(size.x / 540.0, 0.66, 1.0)))
	var top := side
	var bottom := side
	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe := DisplayServer.get_display_safe_area()
		var window := DisplayServer.window_get_size()
		if window.x > 0 and window.y > 0 and safe.has_area():
			var ratio := size / Vector2(window)
			side = maxi(side, ceili(maxi(safe.position.x, window.x - safe.end.x) * ratio.x))
			top = maxi(top, ceili(safe.position.y * ratio.y))
			bottom = maxi(bottom, ceili((window.y - safe.end.y) * ratio.y))
	_margin.add_theme_constant_override("margin_left", side)
	_margin.add_theme_constant_override("margin_right", side)
	_margin.add_theme_constant_override("margin_top", top)
	_margin.add_theme_constant_override("margin_bottom", bottom)


func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		back_requested.emit()
