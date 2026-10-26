class_name ProfileScreen
extends Control
## API-backed account profile with a local avatar cache and photo selector.

signal back_requested
signal refresh_requested
signal achievement_refresh_requested
signal tournaments_requested
signal profile_save_requested(username: String, avatar_png_base64: String)
signal delete_account_requested
signal account_deletion_acknowledged

const PROFILE_FIELD_KEYS: Dictionary = {
	"Username": ["username", "userName", "handle", "displayName", "display_name"],
	"Email": ["email", "emailAddress", "email_address"],
}
const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")

var _fields: Dictionary = {}
var avatar_store_path: String = UsersStateStore.DEFAULT_PATH
var _avatar_paths: PackedStringArray = []
var _avatar_index: int = -1
var _avatar_preview: TextureRect
var _avatar_caption: Label
var _avatar_status: Label
var _username_status: Label
var _username_edit_button: Button
var _username_editor: LineEdit
var _username_display_row: HBoxContainer
var _username_edit_row: VBoxContainer
var _username_save_button: Button
var _username_cancel_button: Button
var _username_editing: bool = false
var _username_update_pending: bool = false
var _profile_save_pending: bool = false
var _saved_username: String = ""
var _draft_username: String = ""
var _profile_name: Label
var _progression_level_label: Label
var _progression_tier_label: Label
var _progression_xp_label: Label
var _progression_bar: ProgressBar
var _avatar_dialog: FileDialog
var _pending_avatar: Image
var _profile_card: Panel
var _profile_content: VBoxContainer
var _delete_confirmation: VBoxContainer
var _delete_account_button: Button
var _delete_confirm_button: Button
var _delete_cancel_button: Button
var _delete_status: Label
var _delete_warning: Label
var _deletion_busy: bool = false
var _deletion_complete: bool = false
var _remote_account_deleted: bool = false
var _profile_scroll_before_delete: int = 0
var _photo_content: VBoxContainer
var _photo_preview: TextureRect
var _upload_target: Button
var _change_photo: Button
var _avatar_choices: Array[Button] = []
var _photo_mode: bool = false
var _photo_before: Dictionary = {}
const PHOTO_HELP: String = "JPG or PNG · Max. 2 MB\nEach side: 195–2048 pixels\nYour photo is cropped to a 195 × 195 square."

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
	_fields["Email"] = get_node_or_null("%EmailField") as LineEdit
	for field: LineEdit in _fields.values():
		if field != null:
			field.editable = false
	_setup_achievements()
	_setup_avatar_selector()


func _setup_avatar_selector() -> void:
	theme = Tabletop.create()
	($Background as ColorRect).color = Tabletop.canvas()
	_profile_card = Panel.new()
	_profile_card.name = "ProfileCard"
	_profile_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(_profile_card)
	move_child(_profile_card, 1)
	$Title.text = "My profile"
	$Title.add_theme_font_override("font", Tabletop.BOLD)
	$Title.add_theme_color_override("font_color", Tabletop.ink())
	$Title.add_theme_font_size_override("font_size", 40)
	$Title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Tabletop.style_back_button(%BackButton)
	%BackButton.tooltip_text = "Back to hub"
	var divider := HSeparator.new()
	divider.name = "ProfileDivider"
	var divider_style := StyleBoxLine.new()
	divider_style.color = Tabletop.border()
	divider_style.thickness = 1
	divider.add_theme_stylebox_override("separator", divider_style)
	_profile_card.add_child(divider)
	var form: VBoxContainer = $ScrollContainer/Form
	for child: Control in form.get_children():
		child.hide()
	_profile_content = VBoxContainer.new()
	_profile_content.name = "ProfileOverview"
	_profile_content.add_theme_constant_override("separation", 16)
	form.add_child(_profile_content)
	var summary := VBoxContainer.new()
	summary.name = "ProfileSummary"
	summary.alignment = BoxContainer.ALIGNMENT_CENTER
	summary.add_theme_constant_override("separation", 8)
	_profile_content.add_child(summary)
	_avatar_preview = FramedPlayerAvatar.new()
	_avatar_preview.name = "AvatarPreview"
	_avatar_preview.custom_minimum_size = Vector2(176, 176)
	_avatar_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_avatar_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_avatar_preview.show_ring = false
	_avatar_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	summary.add_child(_avatar_preview)
	_username_display_row = HBoxContainer.new()
	_username_display_row.name = "UsernameDisplayRow"
	_username_display_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_username_display_row.size_flags_horizontal = Control.SIZE_FILL
	_username_display_row.add_theme_constant_override("separation", 6)
	summary.add_child(_username_display_row)
	_profile_name = _label("Player", 34, Tabletop.ink())
	_profile_name.name = "ProfileDisplayName"
	_profile_name.add_theme_font_override("font", Tabletop.BOLD)
	_profile_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_profile_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	_profile_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_profile_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_username_display_row.add_child(_profile_name)
	_username_edit_button = Button.new()
	_username_edit_button.name = "EditUsername"
	_username_edit_button.tooltip_text = "Edit username"
	_username_edit_button.accessibility_name = "Edit username"
	_username_edit_button.icon = Tabletop.icon_texture("edit")
	_username_edit_button.expand_icon = false
	_username_edit_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_username_edit_button.custom_minimum_size = Vector2(48, 48)
	Tabletop.style_button(_username_edit_button, "quiet")
	for state: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		_username_edit_button.add_theme_color_override(state, Tabletop.ink())
	_username_edit_button.pressed.connect(_begin_username_edit)
	_username_display_row.add_child(_username_edit_button)
	_username_edit_row = VBoxContainer.new()
	_username_edit_row.name = "UsernameEditRow"
	_username_edit_row.size_flags_horizontal = Control.SIZE_FILL
	_username_edit_row.add_theme_constant_override("separation", 8)
	_username_edit_row.hide()
	summary.add_child(_username_edit_row)
	_username_editor = LineEdit.new()
	_username_editor.name = "UsernameEditor"
	_username_editor.placeholder_text = "Username"
	_username_editor.accessibility_name = "Username"
	_username_editor.max_length = 50
	_username_editor.custom_minimum_size = Vector2(0, 52)
	_username_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_username_editor.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_username_editor.add_theme_font_override("font", Tabletop.REGULAR)
	_username_editor.add_theme_font_size_override("font_size", 24)
	_username_editor.add_theme_stylebox_override("normal", Tabletop.panel(Tabletop.canvas_alt(), 12, 10.0))
	_username_editor.add_theme_stylebox_override("focus", Tabletop.panel(Tabletop.canvas_alt(), 12, 10.0))
	_username_editor.text_submitted.connect(_submit_username)
	_username_edit_row.add_child(_username_editor)
	var username_actions := HBoxContainer.new()
	username_actions.name = "UsernameEditActions"
	username_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	username_actions.size_flags_horizontal = Control.SIZE_FILL
	username_actions.add_theme_constant_override("separation", 8)
	_username_edit_row.add_child(username_actions)
	_username_save_button = _avatar_button("Save")
	_username_save_button.name = "SaveUsername"
	_username_save_button.custom_minimum_size = Vector2(76, 48)
	Tabletop.style_button(_username_save_button, "quiet")
	_username_save_button.add_theme_font_size_override("font_size", 18)
	_username_save_button.text = "Done"
	_username_save_button.pressed.connect(_submit_current_username)
	username_actions.add_child(_username_save_button)
	_username_cancel_button = _avatar_button("Cancel")
	_username_cancel_button.name = "CancelUsernameEdit"
	_username_cancel_button.custom_minimum_size = Vector2(76, 48)
	Tabletop.style_button(_username_cancel_button, "quiet")
	_username_cancel_button.add_theme_font_size_override("font_size", 18)
	_username_cancel_button.pressed.connect(_cancel_username_edit)
	username_actions.add_child(_username_cancel_button)
	_username_status = _label("", 16, Tabletop.muted())
	_username_status.name = "UsernameStatus"
	_username_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_username_status.hide()
	summary.add_child(_username_status)
	var progression_panel := PanelContainer.new()
	progression_panel.name = "PlayerProgression"
	progression_panel.add_theme_stylebox_override("panel", Tabletop.panel(Tabletop.sage(), 18, 16.0))
	summary.add_child(progression_panel)
	var progression_column := VBoxContainer.new()
	progression_column.add_theme_constant_override("separation", 8)
	progression_panel.add_child(progression_column)
	var progression_row := VBoxContainer.new()
	progression_row.add_theme_constant_override("separation", 2)
	progression_column.add_child(progression_row)
	_progression_level_label = _label("Table Level", 24, Tabletop.ink())
	_progression_level_label.name = "TableLevel"
	_progression_level_label.add_theme_font_override("font", Tabletop.BOLD)
	_progression_level_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_progression_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progression_row.add_child(_progression_level_label)
	_progression_tier_label = _label("Online Tier unavailable", 18, Tabletop.muted())
	_progression_tier_label.name = "OnlineTier"
	_progression_tier_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_progression_tier_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	progression_row.add_child(_progression_tier_label)
	_progression_bar = ProgressBar.new()
	_progression_bar.name = "LevelProgress"
	_progression_bar.custom_minimum_size.y = 12
	_progression_bar.show_percentage = false
	_progression_bar.add_theme_stylebox_override("background", Tabletop.panel(Tabletop.canvas(), 6, 0))
	_progression_bar.add_theme_stylebox_override("fill", Tabletop.panel(Tabletop.honey(), 6, 0))
	progression_column.add_child(_progression_bar)
	_progression_bar.hide()
	_progression_xp_label = _label("Loading your level...", 16, Tabletop.muted())
	_progression_xp_label.name = "LevelExperience"
	progression_column.add_child(_progression_xp_label)
	_fields["Username"] = _username_editor
	var account_panel := PanelContainer.new()
	account_panel.name = "AccountDetails"
	summary.add_child(account_panel)
	account_panel.add_theme_stylebox_override("panel", Tabletop.panel(Tabletop.canvas_alt(), 18, 16.0))
	var account_column := VBoxContainer.new()
	account_column.add_theme_constant_override("separation", 8)
	account_panel.add_child(account_column)
	var account_heading_row := HBoxContainer.new()
	account_heading_row.alignment = BoxContainer.ALIGNMENT_CENTER
	account_column.add_child(account_heading_row)
	var account_header := _label("Account details", 22, Tabletop.ink())
	account_header.add_theme_font_override("font", Tabletop.SEMIBOLD)
	account_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account_heading_row.add_child(account_header)
	var refresh: Button = %UpdateButton
	refresh.owner = null
	refresh.reparent(account_heading_row)
	refresh.owner = self
	refresh.show()
	refresh.text = "Refresh"
	refresh.custom_minimum_size = Vector2(112, 44)
	refresh.size_flags_horizontal = Control.SIZE_SHRINK_END
	_style_profile_button(refresh, false)
	refresh.add_theme_font_size_override("font_size", 18)
	for field_name: String in ["Email"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		account_column.add_child(row)
		var field_label := _label(field_name, 18, Tabletop.muted())
		field_label.custom_minimum_size.x = 86
		field_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(field_label)
		var field: LineEdit = _fields[field_name]
		field.owner = null
		field.reparent(row)
		field.owner = self
		field.show()
		field.editable = false
		field.custom_minimum_size = Vector2(0, 40)
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.expand_to_text_length = false
		field.add_theme_font_override("font", Tabletop.REGULAR)
		field.add_theme_font_size_override("font_size", 18)
		field.add_theme_color_override("font_uneditable_color", Tabletop.ink())
		field.add_theme_stylebox_override("normal", Tabletop.panel(Tabletop.canvas(), 12, 10.0))
		field.add_theme_stylebox_override("read_only", Tabletop.panel(Tabletop.canvas(), 12, 10.0))
	var edit := _avatar_button("Edit photo")
	edit.name = "EditPhoto"
	edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	edit.add_theme_font_size_override("font_size", 22)
	Tabletop.style_button(edit, "quiet")
	edit.pressed.connect(_open_photo_editor)
	summary.add_child(edit)
	var save_profile := _avatar_button("Save profile")
	save_profile.name = "SaveProfile"
	save_profile.custom_minimum_size.y = 64
	save_profile.pressed.connect(_save_profile)
	_profile_content.add_child(save_profile)
	_build_delete_account_section(form)
	_setup_photo_editor()
	var selector_heading := _label("Pick your look", 30, Tabletop.ink())
	selector_heading.add_theme_font_override("font", Tabletop.BOLD)
	_photo_content.add_child(selector_heading)
	var choices := GridContainer.new()
	choices.name = "AvatarChoices"
	choices.columns = 3
	choices.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	choices.add_theme_constant_override("h_separation", 12)
	choices.add_theme_constant_override("v_separation", 12)
	_photo_content.add_child(choices)
	_avatar_paths = PlayerAvatarStore.default_paths()
	for index: int in range(_avatar_paths.size()):
		var choice := Button.new()
		choice.name = "Avatar%d" % (index + 1)
		choice.custom_minimum_size = Vector2(112, 112)
		choice.size_flags_horizontal = Control.SIZE_FILL
		choice.tooltip_text = "Avatar %d" % (index + 1)
		choice.add_theme_stylebox_override("normal", Tabletop.panel(Color.TRANSPARENT, 56, 0.0))
		var thumbnail := FramedPlayerAvatar.new()
		thumbnail.name = "AvatarPreview"
		thumbnail.show_ring = false
		thumbnail.set_portrait(load(_avatar_paths[index]) as Texture2D)
		choice.add_child(thumbnail)
		thumbnail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		thumbnail.offset_left = 5
		thumbnail.offset_top = 5
		thumbnail.offset_right = -5
		thumbnail.offset_bottom = -5
		var selected_mark := PanelContainer.new()
		selected_mark.name = "SelectedMark"
		selected_mark.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		selected_mark.offset_left = -38
		selected_mark.offset_top = -38
		selected_mark.offset_right = -4
		selected_mark.offset_bottom = -4
		selected_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		selected_mark.add_theme_stylebox_override("panel", Tabletop.panel(Tabletop.ink(), 17, 0.0))
		choice.add_child(selected_mark)
		var checkmark := Label.new()
		checkmark.text = "✓"
		checkmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		checkmark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		checkmark.add_theme_font_override("font", Tabletop.BOLD)
		checkmark.add_theme_font_size_override("font_size", 22)
		checkmark.add_theme_color_override("font_color", Tabletop.canvas())
		checkmark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		checkmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		selected_mark.add_child(checkmark)
		choice.pressed.connect(_select_avatar.bind(index))
		choices.add_child(choice)
		_avatar_choices.append(choice)
	_avatar_caption = _label("", 18, Tabletop.muted())
	_avatar_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_photo_content.add_child(_avatar_caption)
	var save := _avatar_button("Save changes")
	save.name = "SaveAvatar"
	save.custom_minimum_size.y = 64
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Tabletop.style_button(save, "primary")
	save.add_theme_font_size_override("font_size", 30)
	save.pressed.connect(_save_profile)
	_photo_content.add_child(save)
	_avatar_status = _label("", 18, Tabletop.muted())
	_avatar_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	form.add_child(_avatar_status)
	_avatar_dialog = FileDialog.new()
	_avatar_dialog.title = "Choose a profile picture"
	_avatar_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_avatar_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_avatar_dialog.use_native_dialog = true
	_avatar_dialog.filters = PackedStringArray(["*.jpg,*.jpeg,*.png;JPEG and PNG images;image/jpeg,image/png"])
	_avatar_dialog.file_selected.connect(_on_avatar_file_selected)
	add_child(_avatar_dialog)
	var saved_avatar: Dictionary = PlayerAvatarStore.selection(avatar_store_path)
	_avatar_index = -1 if saved_avatar.has("png") else _avatar_paths.find(
		String(saved_avatar.get("default", PlayerAvatarStore.FALLBACK.resource_path))
	)
	(_avatar_preview as FramedPlayerAvatar).set_portrait(PlayerAvatarStore.texture(avatar_store_path))
	_avatar_caption.text = "Your uploaded picture" if _avatar_index == -1 else "Avatar %d of %d" % [_avatar_index + 1, _avatar_paths.size()]
	_sync_profile_identity()
	_update_avatar_choices()
	resized.connect(_fit_profile)
	_fit_profile()


func _build_delete_account_section(form: VBoxContainer) -> void:
	var divider := HSeparator.new()
	divider.name = "AccountActionDivider"
	var divider_style := StyleBoxLine.new()
	divider_style.color = Tabletop.border()
	divider.add_theme_stylebox_override("separator", divider_style)
	_profile_content.add_child(divider)
	_delete_account_button = _avatar_button("Delete account")
	_delete_account_button.name = "DeleteAccountButton"
	_delete_account_button.tooltip_text = "Permanently delete this account"
	_style_delete_button(_delete_account_button)
	_delete_account_button.pressed.connect(_on_delete_account_pressed)
	_profile_content.add_child(_delete_account_button)

	_delete_confirmation = VBoxContainer.new()
	_delete_confirmation.name = "DeleteConfirmation"
	_delete_confirmation.add_theme_constant_override("separation", 16)
	_delete_confirmation.hide()
	form.add_child(_delete_confirmation)
	var panel := PanelContainer.new()
	panel.name = "DeleteConfirmationPanel"
	panel.add_theme_stylebox_override("panel", Tabletop.panel(Tabletop.canvas_alt(), 18, 16))
	_delete_confirmation.add_child(panel)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 12)
	panel.add_child(copy)
	var heading := _label("Delete account?", 26, Tabletop.ink())
	heading.name = "DeleteHeading"
	heading.add_theme_font_override("font", Tabletop.SEMIBOLD)
	copy.add_child(heading)
	_delete_warning = _label("Your account details, achievements and saved games will be irrevocably removed from the server. All saved account and game state on this device will also be deleted. This cannot be undone.", 18, Tabletop.ink())
	_delete_warning.name = "DeleteWarning"
	copy.add_child(_delete_warning)
	_delete_status = _label("", 18, Tabletop.muted())
	_delete_status.name = "DeleteStatus"
	copy.add_child(_delete_status)
	_delete_confirm_button = _avatar_button("Permanently delete account")
	_delete_confirm_button.name = "ConfirmDeleteButton"
	_style_delete_button(_delete_confirm_button)
	_delete_confirm_button.pressed.connect(_on_confirm_delete_pressed)
	_delete_confirmation.add_child(_delete_confirm_button)
	_delete_cancel_button = _avatar_button("Cancel")
	_delete_cancel_button.name = "CancelDeleteButton"
	_style_profile_button(_delete_cancel_button, false)
	_delete_cancel_button.pressed.connect(_on_cancel_delete_pressed)
	_delete_confirmation.add_child(_delete_cancel_button)


func _style_delete_button(button: Button) -> void:
	_style_profile_button(button, false)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Tabletop.danger())


func _on_delete_account_pressed() -> void:
	if _profile_save_pending or _deletion_busy:
		return
	_profile_scroll_before_delete = $ScrollContainer.scroll_vertical
	_profile_content.hide()
	_delete_status.text = ""
	_delete_warning.show()
	_delete_confirm_button.text = "Permanently delete account"
	_delete_confirmation.show()
	$ScrollContainer.scroll_vertical = 0
	_delete_cancel_button.grab_focus()


func _on_cancel_delete_pressed() -> void:
	if _deletion_busy or _remote_account_deleted:
		return
	_delete_confirmation.hide()
	_profile_content.show()
	$ScrollContainer.set_deferred("scroll_vertical", _profile_scroll_before_delete)
	_delete_account_button.grab_focus()


func _on_confirm_delete_pressed() -> void:
	if _deletion_busy:
		return
	if _deletion_complete:
		account_deletion_acknowledged.emit()
		return
	set_deletion_busy()
	delete_account_requested.emit()


func set_deletion_busy() -> void:
	_deletion_busy = true
	_delete_status.text = "Deleting account…"
	_delete_confirm_button.disabled = true
	_delete_cancel_button.disabled = true
	%BackButton.disabled = true


func show_deletion_result(success: bool, message: String, remote_deleted: bool = false) -> void:
	_deletion_busy = false
	_deletion_complete = success
	_remote_account_deleted = remote_deleted or success
	_delete_status.text = message
	_delete_confirm_button.disabled = false
	_delete_confirm_button.text = "Continue" if success else ("Retry local cleanup" if remote_deleted else "Retry deletion")
	_delete_cancel_button.disabled = false
	_delete_cancel_button.visible = not _remote_account_deleted
	_delete_warning.visible = not success
	%BackButton.disabled = _remote_account_deleted
	_delete_confirm_button.grab_focus()


func _fit_profile() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var margin: float = maxf(16.0, (size.x - 560.0) * 0.5)
	_profile_card.position = Vector2(margin, 12)
	_profile_card.size = Vector2(size.x - margin * 2.0, maxf(0.0, size.y - 24.0))
	$Title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	$Title.position = Vector2(margin + 56, 24)
	$Title.size = Vector2(_profile_card.size.x - 112, 52)
	%BackButton.position = Vector2(margin + 4, 24)
	%BackButton.size = Vector2(48, 48)
	_profile_card.get_node("ProfileDivider").position = Vector2(0, 88)
	_profile_card.get_node("ProfileDivider").size = Vector2(_profile_card.size.x, 1)
	$ScrollContainer.set_anchors_preset(Control.PRESET_TOP_LEFT)
	$ScrollContainer.position = Vector2(margin + 20, 104)
	$ScrollContainer.size = Vector2(_profile_card.size.x - 40, maxf(0.0, size.y - 128))
	var choices: GridContainer = _photo_content.get_node_or_null("AvatarChoices") as GridContainer
	if choices != null:
		var gap: float = 12.0 if $ScrollContainer.size.x >= 360.0 else 8.0
		var side: float = clampf(($ScrollContainer.size.x - gap * 2.0) / 3.0, 76.0, 112.0)
		choices.add_theme_constant_override("h_separation", int(gap))
		for choice: Button in _avatar_choices:
			choice.custom_minimum_size = Vector2.ONE * side


func _setup_photo_editor() -> void:
	_photo_content = VBoxContainer.new()
	_photo_content.name = "PhotoEditor"
	_photo_content.add_theme_constant_override("separation", 24)
	$ScrollContainer/Form.add_child(_photo_content)
	_upload_target = Button.new()
	_upload_target.set_script(preload("res://scripts/presentation/avatar_upload_target.gd"))
	_upload_target.name = "UploadAvatar"
	_upload_target.text = "Tap here\nto upload your photo"
	_style_profile_button(_upload_target, false)
	_upload_target.custom_minimum_size.y = 280
	for state: String in ["normal", "hover", "pressed"]:
		var upload_style := Tabletop.panel(Tabletop.canvas_alt(), 18, 12.0)
		upload_style.set_border_width_all(1)
		upload_style.border_color = Tabletop.muted()
		_upload_target.add_theme_stylebox_override(state, upload_style)
	_upload_target.pressed.connect(_open_avatar_dialog)
	_photo_content.add_child(_upload_target)
	_photo_preview = FramedPlayerAvatar.new()
	_photo_preview.name = "PhotoPreview"
	_photo_preview.custom_minimum_size = Vector2(260, 260)
	_photo_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_photo_preview.show_ring = false
	_photo_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_photo_content.add_child(_photo_preview)
	_change_photo = _avatar_button("CHANGE PHOTO")
	_style_profile_button(_change_photo, false)
	_change_photo.pressed.connect(_open_avatar_dialog)
	_photo_content.add_child(_change_photo)
	var help := _label(PHOTO_HELP, 18, Tabletop.muted())
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_photo_content.add_child(help)
	_photo_content.hide()


func _open_photo_editor() -> void:
	_photo_before = {"image": _pending_avatar, "index": _avatar_index, "texture": _avatar_preview.texture, "caption": _avatar_caption.text}
	_photo_mode = true
	_profile_content.hide()
	_photo_content.show()
	$Title.text = "Edit photo"
	%BackButton.tooltip_text = "Back to My Profile"
	_avatar_status.text = ""
	var has_photo: bool = _pending_avatar != null or (_avatar_index == -1 and PlayerAvatarStore.selection(avatar_store_path).has("png"))
	(_photo_preview as FramedPlayerAvatar).set_portrait(_avatar_preview.texture if has_photo else null)
	_show_photo_state(has_photo)
	$ScrollContainer.scroll_vertical = 0


func _show_photo_state(has_photo: bool) -> void:
	_upload_target.visible = not has_photo
	_photo_preview.visible = has_photo
	_change_photo.visible = has_photo


func _close_photo_editor() -> void:
	_photo_mode = false
	_photo_content.hide()
	_profile_content.show()
	$Title.text = "My profile"
	%BackButton.tooltip_text = "Back to hub"
	$ScrollContainer.scroll_vertical = 0


func _select_avatar(index: int) -> void:
	_avatar_index = index
	_pending_avatar = null
	(_avatar_preview as FramedPlayerAvatar).set_portrait(load(_avatar_paths[index]) as Texture2D)
	if _photo_mode:
		_show_photo_state(false)
	_avatar_caption.text = "Avatar %d of %d" % [index + 1, _avatar_paths.size()]
	_avatar_status.text = "Preview selected · Save changes to keep it."
	_avatar_status.add_theme_color_override("font_color", Tabletop.muted())
	_update_avatar_choices()


func _sync_profile_identity() -> void:
	if _profile_name == null:
		return
	var name: String = _saved_username
	if not _draft_username.is_empty():
		name = _draft_username
	_profile_name.text = name if not name.is_empty() else "Player"


func _begin_username_edit() -> void:
	if _username_update_pending or _username_editor == null:
		return
	_username_editing = true
	_draft_username = _saved_username
	_username_editor.text = _draft_username
	_username_status.text = ""
	_username_status.hide()
	_username_display_row.hide()
	_username_edit_row.show()
	if is_inside_tree():
		_username_editor.grab_focus()
		_username_editor.select_all()


func _submit_current_username() -> void:
	if _username_editor != null:
		_submit_username(_username_editor.text)


func _cancel_username_edit() -> void:
	if _username_update_pending:
		return
	_username_editor.text = _saved_username
	_draft_username = _saved_username
	_username_editing = false
	_username_edit_row.hide()
	_username_display_row.show()
	_username_status.text = ""
	_username_status.hide()
	_sync_profile_identity()
	if is_inside_tree():
		_username_edit_button.grab_focus()


func _submit_username(value: String) -> void:
	if _username_status == null or not _username_editing or _profile_save_pending:
		return
	var username: String = value.strip_edges()
	if username.is_empty() or username.length() > 50:
		_username_status.text = "Enter a username between 1 and 50 characters."
		_username_status.add_theme_color_override("font_color", Tabletop.danger())
		_username_status.show()
		return
	_draft_username = username
	_username_editor.text = username
	_username_editing = false
	_username_edit_row.hide()
	_username_display_row.show()
	_sync_profile_identity()
	_username_status.text = "Ready to save with your avatar."
	_username_status.add_theme_color_override("font_color", Tabletop.muted())
	_username_status.show()


func set_username_update_pending(pending: bool) -> void:
	_username_update_pending = pending
	set_profile_save_pending(pending)


func set_profile_save_pending(pending: bool) -> void:
	_profile_save_pending = pending
	_username_update_pending = pending
	_username_editor.editable = not pending
	_username_save_button.disabled = pending
	_username_save_button.text = "Saving…" if pending else "Done"
	_username_cancel_button.disabled = pending
	_username_edit_button.disabled = pending
	for choice: Button in _avatar_choices:
		choice.disabled = pending
	for button_name: String in ["SaveAvatar", "SaveProfile"]:
		var save_button: Button = find_child(button_name, true, false) as Button
		if save_button != null:
			save_button.disabled = pending
	if pending:
		_avatar_status.text = "Saving profile…"
		_avatar_status.show()


func set_username_update_result(success: bool, message: String = "") -> void:
	set_profile_save_result(success, message)


func show_username_taken(attempted_name: String) -> void:
	set_profile_save_pending(false)
	_username_editing = true
	_draft_username = attempted_name
	_username_editor.text = attempted_name
	_username_display_row.hide()
	_username_edit_row.show()
	_username_status.text = "That username is already in use. Choose another."
	_username_status.add_theme_color_override("font_color", Tabletop.danger())
	_username_status.show()
	_avatar_status.text = "Avatar saved, but that username is already in use. Choose another."
	_avatar_status.add_theme_color_override("font_color", Tabletop.danger())
	_avatar_status.show()
	if _photo_mode:
		_close_photo_editor()
	if is_inside_tree() and _profile_content.visible:
		_username_editor.grab_focus()
		_username_editor.select_all()


func set_profile_save_result(success: bool, message: String = "") -> void:
	set_profile_save_pending(false)
	if success:
		_saved_username = _username_editor.text.strip_edges() if _username_editor != null else _saved_username
		_draft_username = _saved_username
		_username_editor.text = _saved_username
		_username_editing = false
		_username_edit_row.hide()
		_username_display_row.show()
		_username_status.hide()
		_avatar_status.text = message if not message.is_empty() else "Profile saved."
		_avatar_status.add_theme_color_override("font_color", Tabletop.ink())
		if _photo_mode:
			_close_photo_editor()
	else:
		_avatar_status.text = message if not message.is_empty() else "Could not save profile. Please try again."
		_avatar_status.add_theme_color_override("font_color", Tabletop.danger())
	_avatar_status.show()
	_sync_profile_identity()


func _save_profile() -> void:
	if _profile_save_pending:
		return
	var username: String = _username_editor.text.strip_edges() if _username_editing else _draft_username
	if username.is_empty() or username.length() > 50:
		var status: Label = _avatar_status if _photo_mode else _username_status
		status.text = "Enter a username between 1 and 50 characters."
		status.add_theme_color_override("font_color", Tabletop.danger())
		status.show()
		return
	var avatar_data: String = PlayerAvatarStore.png_base64_for_selection(avatar_store_path, _pending_avatar, _avatar_index, _avatar_paths)
	if avatar_data.is_empty():
		_avatar_status.text = "Could not prepare your avatar. Please choose it again."
		_avatar_status.add_theme_color_override("font_color", Tabletop.danger())
		_avatar_status.show()
		return
	_avatar_status.text = ""
	_avatar_status.hide()
	profile_save_requested.emit(username, avatar_data)


func _update_avatar_choices() -> void:
	for index: int in range(_avatar_choices.size()):
		var style := Tabletop.panel(Color.TRANSPARENT, 56, 0.0)
		style.draw_center = false
		style.set_border_width_all(3 if index == _avatar_index else 0)
		style.border_color = Tabletop.ink()
		for state: String in ["normal", "hover", "pressed"]:
			_avatar_choices[index].add_theme_stylebox_override(state, style)
		var focus := Tabletop.panel(Color.TRANSPARENT, 56, 0.0)
		focus.draw_center = false
		focus.set_border_width_all(3)
		focus.border_color = Tabletop.honey()
		_avatar_choices[index].add_theme_stylebox_override("focus", focus)
		_avatar_choices[index].get_node("SelectedMark").visible = index == _avatar_index


func _avatar_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 24)
	_style_profile_button(button, true)
	return button


func _style_profile_button(button: Button, filled: bool) -> void:
	button.custom_minimum_size.y = 52
	button.add_theme_font_size_override("font_size", 24)
	Tabletop.style_button(button, "primary" if filled else "secondary")
	button.add_theme_color_override("font_color", Tabletop.ink())
	button.add_theme_color_override("font_hover_color", Tabletop.ink())
	button.add_theme_color_override("font_pressed_color", Tabletop.ink())
	button.add_theme_color_override("font_focus_color", Tabletop.ink())


func _cycle_avatar(direction: int) -> void:
	if _avatar_paths.is_empty():
		return
	_avatar_index = (0 if direction > 0 else _avatar_paths.size() - 1) if _avatar_index == -1 else posmod(_avatar_index + direction, _avatar_paths.size())
	_select_avatar(_avatar_index)


func _open_avatar_dialog() -> void:
	_avatar_dialog.popup_centered_ratio(0.9)


func _on_avatar_file_selected(filename: String) -> void:
	var result: Dictionary = PlayerAvatarStore.prepare_upload(filename)
	if result.has("error"):
		_avatar_status.text = result.error
		_avatar_status.add_theme_color_override("font_color", Tabletop.danger())
		return
	_pending_avatar = result.image as Image
	_avatar_index = -1
	(_avatar_preview as FramedPlayerAvatar).set_portrait(ImageTexture.create_from_image(_pending_avatar))
	(_photo_preview as FramedPlayerAvatar).set_portrait(_avatar_preview.texture)
	_show_photo_state(true)
	_update_avatar_choices()
	_avatar_caption.text = "Your uploaded picture"
	_avatar_status.text = "Preview selected · Save changes to keep it."
	_avatar_status.add_theme_color_override("font_color", Tabletop.muted())


func has_unsaved_avatar_changes() -> bool:
	if _pending_avatar != null:
		return true
	var saved: Dictionary = PlayerAvatarStore.selection(avatar_store_path)
	if saved.is_empty():
		return false
	if _avatar_index >= 0 and _avatar_index < _avatar_paths.size():
		if saved.has("png"):
			var current_png: String = PlayerAvatarStore.png_base64_for_selection(avatar_store_path, null, -1, _avatar_paths)
			var selected_png: String = PlayerAvatarStore.png_base64_for_selection(avatar_store_path, null, _avatar_index, _avatar_paths)
			return current_png != selected_png
		return String(saved.get("default", "")) != _avatar_paths[_avatar_index]
	return not saved.has("png")


## Applies an avatar after its API write succeeds and updates the device cache.
func set_profile_avatar_persisted(encoded: String) -> bool:
	if not PlayerAvatarStore.save_png_base64(encoded, avatar_store_path):
		return false
	_pending_avatar = null
	_avatar_index = PlayerAvatarStore.default_index_for_png(encoded, _avatar_paths)
	(_avatar_preview as FramedPlayerAvatar).set_portrait(PlayerAvatarStore.texture(avatar_store_path))
	_avatar_caption.text = "Your uploaded picture" if _avatar_index < 0 else "Avatar %d of %d" % [_avatar_index + 1, _avatar_paths.size()]
	_update_avatar_choices()
	return true


## Hydrates the local cache from GET /auth/me/avatar without overwriting a
## preview the player has changed but not yet submitted.
func set_remote_avatar_data(encoded: String) -> bool:
	if has_unsaved_avatar_changes():
		return false
	return set_profile_avatar_persisted(encoded)


## Populates account fields from AppRoot's authenticated state.
func set_user_state(state: Dictionary) -> void:
	var user: Variant = state.get("user", {})
	var details: Dictionary = user as Dictionary if typeof(user) == TYPE_DICTIONARY else {}
	var keep_username_draft: bool = _profile_save_pending or _username_editing or _draft_username != _saved_username
	for field_name: String in PROFILE_FIELD_KEYS:
		var field: LineEdit = _fields.get(field_name) as LineEdit
		if field == null:
			continue
		if field_name == "Username" and keep_username_draft:
			continue
		field.text = _value_for(details, PROFILE_FIELD_KEYS[field_name])
	var username_field: LineEdit = _fields.get("Username") as LineEdit
	if username_field != null and not keep_username_draft:
		_saved_username = username_field.text.strip_edges()
		_draft_username = _saved_username
		_username_editing = false
		_username_edit_row.hide()
		_username_display_row.show()
		_username_status.text = ""
		_username_status.hide()
	_sync_profile_identity()


func set_progression(data: Dictionary) -> void:
	if _progression_level_label == null or int(data.get("level", 0)) < 1:
		return
	var level: int = int(data.level)
	var experience: int = int(data.get("experience", 0))
	var start: int = int(data.get("levelStartExperience", 0))
	var next: int = int(data.get("nextLevelExperience", experience + 1))
	_progression_level_label.text = "Level %d" % level
	_progression_tier_label.text = "%s online" % String(data.get("onlineTier", "Provisional"))
	_progression_bar.max_value = maxf(1.0, float(next - start))
	_progression_bar.value = clampf(float(experience - start), 0.0, _progression_bar.max_value)
	_progression_bar.show()
	_progression_xp_label.text = "%d / %d XP to Level %d" % [experience - start, next - start, level + 1]


func set_progression_error(message: String) -> void:
	if _progression_xp_label != null and not _progression_bar.visible:
		_progression_xp_label.text = message

func set_achievement_rows(rows: Array) -> void:
	%AchievementsPage.set_rows(rows)


func set_achievement_loading() -> void:
	%AchievementsPage.set_loading()


func set_achievement_error(message: String) -> void:
	%AchievementsPage.set_error(message)


func show_achievements_only(enabled: bool) -> void:
	%AchievementsPage.visible = enabled
	_profile_card.visible = not enabled
	for node_path: String in ["Title", "BackButton", "ScrollContainer"]:
		(get_node(node_path) as Control).visible = not enabled
	($Background as ColorRect).color = Tabletop.canvas()
	if enabled:
		%AchievementsPage.show_overview()
	else:
		%BackButton.grab_focus()


func _setup_achievements() -> void:
	%AchievementsPage.home_requested.connect(_on_back_pressed)
	%AchievementsPage.profile_requested.connect(show_achievements_only.bind(false))
	%AchievementsPage.tournaments_requested.connect(func() -> void: tournaments_requested.emit())
	%AchievementsPage.refresh_requested.connect(func() -> void: achievement_refresh_requested.emit())


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
	if _profile_save_pending or _deletion_busy or _remote_account_deleted:
		return
	if _delete_confirmation != null and _delete_confirmation.visible:
		_on_cancel_delete_pressed()
		return
	if _photo_mode:
		_pending_avatar = _photo_before.image as Image
		_avatar_index = int(_photo_before.index)
		(_avatar_preview as FramedPlayerAvatar).set_portrait(_photo_before.texture as Texture2D)
		_avatar_caption.text = String(_photo_before.caption)
		_update_avatar_choices()
		_avatar_status.text = ""
		_close_photo_editor()
		return
	back_requested.emit()


## Reload from the documented account endpoint.
func _on_update_pressed() -> void:
	refresh_requested.emit()
