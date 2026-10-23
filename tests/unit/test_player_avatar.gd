extends "res://tests/harness/test_case.gd"

const ROOT: String = "user://avatar_tests"
const ACCOUNT: String = ROOT + "/users_state.json"


func _account() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	UsersStateStore.save_accepted_account("avatar-test", "test", "", ACCOUNT)


func _image(width: int = 390, height: int = 195) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	return image


func _write(filename: String, bytes: PackedByteArray) -> String:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var path: String = ROOT.path_join(filename)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return path


func test_avatar_accepts_jpg_jpeg_png_and_normalizes_center_crop() -> void:
	var image: Image = _image(585, 195)
	image.fill_rect(Rect2i(195, 0, 195, 195), Color.GREEN)
	for extension: String in ["png", "jpg", "JPEG", "PNG"]:
		var bytes: PackedByteArray = image.save_png_to_buffer() if extension.to_lower() == "png" else image.save_jpg_to_buffer()
		var result: Dictionary = PlayerAvatarStore.prepare_upload(_write("valid." + extension, bytes))
		check(result.has("image"), extension + " is accepted")
		if result.has("image"):
			var normalized: Image = result.image
			check_eq(normalized.get_size(), Vector2i(195, 195), "stored size is exactly 195 square")
			check(normalized.get_pixel(97, 97).g > 0.9, "center crop retains the middle of the picture")


func test_avatar_rejects_formats_corruption_and_spoofed_extensions() -> void:
	var png: PackedByteArray = _image().save_png_to_buffer()
	for extension: String in ["gif", "webp", "svg", "bmp", "txt", ""]:
		check(PlayerAvatarStore.prepare_upload(_write("invalid." + extension, png)).has("error"), extension + " is rejected")
	check(PlayerAvatarStore.prepare_upload(_write("renamed.jpg", png)).has("error"), "PNG renamed to JPEG is rejected")
	check(PlayerAvatarStore.prepare_upload(_write("broken.png", "not an image".to_utf8_buffer())).has("error"), "corrupt image is rejected")
	check(PlayerAvatarStore.prepare_upload(ROOT + "/missing.png").has("error"), "missing image is rejected")


func test_avatar_enforces_byte_and_dimension_limits() -> void:
	var large := PackedByteArray()
	large.resize(PlayerAvatarStore.MAX_BYTES + 1)
	check(PlayerAvatarStore.prepare_upload(_write("large.png", large)).has("error"), "over 2 MB rejected before decoding")
	for dimensions: Vector2i in [Vector2i(194, 195), Vector2i(195, 194), Vector2i(2049, 195), Vector2i(195, 2049)]:
		var result: Dictionary = PlayerAvatarStore.prepare_upload(_write("size.png", _image(dimensions.x, dimensions.y).save_png_to_buffer()))
		check(result.has("error"), "out of bounds dimensions rejected: %s" % dimensions)
	for side: int in [195, 2048]:
		check(PlayerAvatarStore.prepare_upload(_write("boundary.png", _image(side, side).save_png_to_buffer())).has("image"), "dimension boundary accepted: %d" % side)


func test_avatar_persists_through_refresh_and_removes_with_account() -> void:
	_account()
	var paths: PackedStringArray = PlayerAvatarStore.default_paths()
	check(paths.size() >= 7, "all supplied default avatars are discovered")
	check(PlayerAvatarStore.save_default(paths[0], ACCOUNT), "default selection saved")
	check_eq(PlayerAvatarStore.selection(ACCOUNT).get("default"), paths[0], "default selection restored")
	var default_png: String = PlayerAvatarStore.png_base64_for_selection(ACCOUNT, null, 0, paths)
	check(not default_png.is_empty(), "default portrait can be encoded for the profile endpoint")
	check_eq(PlayerAvatarStore.default_index_for_png(default_png, paths), 0, "server avatar data resolves to its matching roster choice")
	UsersStateStore.save_user_state({"token": "test", "user": {"id": "user-1"}}, ACCOUNT)
	check_eq(PlayerAvatarStore.selection(ACCOUNT).get("default"), paths[0], "API refresh preserves local avatar")
	check(PlayerAvatarStore.save_upload(_image(195, 195), ACCOUNT), "normalized upload saved")
	check_eq(PlayerAvatarStore.texture(ACCOUNT).get_size(), Vector2(195, 195), "upload restored without original source")
	check(not PlayerAvatarStore.selection(ACCOUNT).has("default"), "upload replaces default choice")
	check(not PlayerAvatarStore.save_default("res://project.godot", ACCOUNT), "arbitrary resource paths rejected")
	check(not PlayerAvatarStore.save_upload(_image(), ACCOUNT), "unnormalized upload cannot be persisted")
	check(UsersStateStore.clear_local_state(ROOT), "account cleanup succeeds")
	check(PlayerAvatarStore.selection(ACCOUNT).is_empty(), "account cleanup removes uploaded bytes")
	check(not PlayerAvatarStore.save_default(paths[0], ACCOUNT), "cannot resurrect a deleted account")


func test_profile_hydrates_server_avatar_without_overwriting_a_preview() -> void:
	_account()
	var screen: ProfileScreen = load("res://scenes/profile/profile_screen.tscn").instantiate()
	screen.avatar_store_path = ACCOUNT
	screen._ready()
	screen.set_user_state({"user": {"id": "user-1", "displayName": "Player"}})
	var paths: PackedStringArray = PlayerAvatarStore.default_paths()
	var remote_avatar: String = PlayerAvatarStore.png_base64_for_selection(ACCOUNT, null, 2, paths)
	check(screen.set_remote_avatar_data(remote_avatar), "server PNG hydrates the profile cache")
	check_eq(screen._avatar_index, 2, "remote default portrait selects its roster button")
	check(not screen.has_unsaved_avatar_changes(), "hydrated server avatar is not considered an unsaved change")
	screen._select_avatar(1)
	check(not screen.set_remote_avatar_data(remote_avatar), "background refresh does not overwrite a changed preview")
	check_eq(screen._avatar_index, 1, "local avatar preview survives the refresh")
	screen.free()
	UsersStateStore.clear_local_state(ROOT)


func test_avatar_selector_saves_username_and_avatar_as_one_profile_change() -> void:
	_account()
	var screen: ProfileScreen = load("res://scenes/profile/profile_screen.tscn").instantiate()
	screen.avatar_store_path = ACCOUNT
	screen._ready()
	var choices: GridContainer = screen._profile_content.get_node("AvatarChoices") as GridContainer
	check_eq(choices.columns, 3, "the profile selector presents avatars in a three-column grid")
	check_eq(screen._avatar_choices.size(), PlayerAvatarStore.default_paths().size(), "the grid includes the full cartoon roster")
	check_eq((screen.get_node("Background") as ColorRect).color, Color("#F6F2E9"), "profile uses the shared ivory canvas")
	check_eq(screen.get_node("Title").get_theme_font("font"), preload("res://assets/fonts/fredoka/Fredoka-Bold.tres"), "profile heading uses Fredoka Bold")
	check_eq((screen.find_child("SaveAvatar", true, false) as Button).text, "Save changes", "avatar choice has one clear save action")
	check_eq(screen._avatar_index, 0, "the fallback portrait is initially selected")
	check((screen._avatar_choices[0].get_node("SelectedMark") as Control).visible, "current avatar shows its checkmark")
	screen._cycle_avatar(-1)
	check_eq(screen._avatar_index, screen._avatar_paths.size() - 1, "Previous wraps from the first default to the last")
	screen._cycle_avatar(1)
	check_eq(screen._avatar_index, 0, "Next wraps from the last default to the first")
	check((screen._avatar_choices[0].get_node("SelectedMark") as Control).visible, "selected avatar shows its checkmark")
	var selected_style: StyleBoxFlat = screen._avatar_choices[0].get_theme_stylebox("normal") as StyleBoxFlat
	check_eq(selected_style.border_color, Color("#173D42"), "selected avatar uses the primary-ink outline")
	check(PlayerAvatarStore.selection(ACCOUNT).is_empty(), "browsing does not save")
	screen.set_user_state({"user": {"id": "user-1", "displayName": "Old name"}})
	screen._begin_username_edit()
	screen._username_editor.text = "New name"
	screen._submit_current_username()
	var submitted: Array[Dictionary] = []
	screen.profile_save_requested.connect(func(username: String, avatar: String) -> void:
		submitted.append({"username": username, "avatar": avatar})
	)
	(screen.find_child("SaveAvatar", true, false) as Button).pressed.emit()
	check_eq(submitted.size(), 1, "one button submits one combined profile update")
	check_eq(submitted[0].username, "New name", "combined request contains the edited username")
	check(not PlayerAvatarStore.selection(ACCOUNT).has("png"), "avatar is not locally committed before the server confirms")
	check(screen.set_profile_avatar_persisted(submitted[0].avatar), "server-confirmed avatar is cached")
	screen.set_profile_save_result(true)
	var saved: Dictionary = PlayerAvatarStore.selection(ACCOUNT)
	check(saved.has("png"), "confirmed profile save caches the avatar locally")
	var previous: Texture2D = screen._avatar_preview.texture
	screen._on_avatar_file_selected(_write("rejected.svg", "bad".to_utf8_buffer()))
	check_eq(screen._avatar_preview.texture, previous, "bad upload leaves preview unchanged")
	check_eq(PlayerAvatarStore.selection(ACCOUNT), saved, "bad upload leaves saved avatar unchanged")
	screen._on_avatar_file_selected(_write("custom.png", _image().save_png_to_buffer()))
	check_eq(screen._avatar_preview.texture.get_size(), Vector2(195, 195), "upload previews normalized picture")
	check_eq(PlayerAvatarStore.selection(ACCOUNT), saved, "upload waits for Save")
	(screen.find_child("SaveAvatar", true, false) as Button).pressed.emit()
	check_eq(submitted.size(), 2, "the same profile action saves uploaded avatars")
	screen.set_profile_avatar_persisted(submitted[1].avatar)
	screen.set_profile_save_result(true)
	check(PlayerAvatarStore.selection(ACCOUNT).has("png"), "server-confirmed Save changes persists upload locally")
	check(screen._avatar_dialog.use_native_dialog, "uses native file picker where available")
	screen.free()
	var reopened: ProfileScreen = load("res://scenes/profile/profile_screen.tscn").instantiate()
	reopened.avatar_store_path = ACCOUNT
	reopened._ready()
	check_eq(reopened._avatar_preview.texture.get_size(), Vector2(195, 195), "reopening profile restores upload")
	reopened.avatar_store_path = ROOT + "/missing/account.json"
	reopened.set_user_state({"user": {"id": "user-1", "displayName": "Player"}})
	reopened._cycle_avatar(1)
	reopened.profile_save_requested.connect(func(_username: String, _avatar: String) -> void: pass)
	(reopened.find_child("SaveAvatar", true, false) as Button).pressed.emit()
	reopened.set_profile_save_result(false, "Could not save profile. Please try again.")
	check(reopened._avatar_status.text.begins_with("Could not save"), "save failure is visible")
	reopened.free()
	UsersStateStore.clear_local_state(ROOT)


func test_photo_editor_previews_cancels_and_saves_without_losing_the_current_avatar() -> void:
	_account()
	var screen: ProfileScreen = load("res://scenes/profile/profile_screen.tscn").instantiate()
	screen.avatar_store_path = ACCOUNT
	screen._ready()
	screen.set_user_state({"user": {"id": "user-1", "displayName": "Player"}})
	screen._avatar_choices[0].pressed.emit()
	check_eq(screen._avatar_index, 0, "thumbnail selects the default avatar")
	PlayerAvatarStore.save_default(PlayerAvatarStore.default_paths()[0], ACCOUNT)
	var saved: Dictionary = PlayerAvatarStore.selection(ACCOUNT)
	var original_texture: Texture2D = screen._avatar_preview.texture
	screen._open_photo_editor()
	check(screen._upload_target.visible, "default avatar opens the empty upload state")
	check(not screen._photo_preview.visible, "empty photo state has no preview")
	var photo_path: String = _write("photo_editor.png", _image().save_png_to_buffer())
	screen._on_avatar_file_selected(photo_path)
	check(screen._photo_preview.visible, "valid image opens circular photo preview")
	check(screen._change_photo.visible and screen._use_photo.visible, "preview offers change and Use photo")
	check_eq(PlayerAvatarStore.selection(ACCOUNT), saved, "preview does not persist before Save")
	screen._on_back_pressed()
	check(not screen._photo_mode, "Back returns to profile")
	check_eq(screen._avatar_preview.texture, original_texture, "Back discards unsaved photo preview")
	check_eq(screen._avatar_index, 0, "Back restores selected default")
	check(screen._pending_avatar == null, "Back discards the pending image")
	screen._open_photo_editor()
	screen._on_avatar_file_selected(photo_path)
	screen._use_photo.pressed.emit()
	check(not screen._photo_mode, "Use photo returns to the profile preview")
	check_eq(PlayerAvatarStore.selection(ACCOUNT), saved, "Use photo does not persist before profile Save changes")
	var submitted: Array[Dictionary] = []
	screen.profile_save_requested.connect(func(username: String, avatar: String) -> void:
		submitted.append({"username": username, "avatar": avatar})
	)
	(screen.find_child("SaveAvatar", true, false) as Button).pressed.emit()
	check_eq(submitted.size(), 1, "profile Save changes submits the selected photo")
	screen.set_profile_avatar_persisted(submitted[0].avatar)
	screen.set_profile_save_result(true)
	check(PlayerAvatarStore.selection(ACCOUNT).has("png"), "Save persists the chosen photo")
	screen.free()
	screen = load("res://scenes/profile/profile_screen.tscn").instantiate()
	screen.avatar_store_path = ACCOUNT
	screen._ready()
	screen.set_user_state({"user": {"id": "user-1", "displayName": "Player"}})
	screen._open_photo_editor()
	check(screen._photo_preview.visible and screen._change_photo.visible, "saved photo opens the populated state")
	check(not screen._use_photo.visible, "unchanged saved photo needs no second save")
	screen._on_avatar_file_selected(photo_path)
	screen.avatar_store_path = ROOT + "/missing/account.json"
	screen._use_photo.pressed.emit()
	screen.profile_save_requested.connect(func(_username: String, _avatar: String) -> void: pass)
	(screen.find_child("SaveAvatar", true, false) as Button).pressed.emit()
	screen.set_profile_save_result(false, "Could not save profile. Please try again.")
	check(not screen._photo_mode, "photo remains previewed on the profile after a failed save")
	check(screen._pending_avatar != null, "storage failure retains the chosen photo for retry")
	screen.free()
	UsersStateStore.clear_local_state(ROOT)


func test_avatar_game_screen_receives_player_portrait() -> void:
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	screen.get_node("FeedbackLayer/SummaryOverlay")._ready()
	var picture := ImageTexture.create_from_image(_image(195, 195))
	screen.set_player_portrait(picture)
	check_eq(screen.get_node("Root/Column/Hud/HumanScorePanel/HumanScoreBox/Portrait").texture, picture, "game HUD applies player avatar")
	check_eq(screen.get_node("FeedbackLayer/SummaryOverlay").find_child("PlayerAvatar", true, false).texture, picture, "match results apply player avatar")
	screen.free()
	var selection_screen: OpponentSelectionScreen = load("res://scenes/hub/opponent_selection_screen.tscn").instantiate()
	selection_screen.set_player_portrait(picture)
	check_eq(selection_screen.get_node("%HumanPortrait").texture, picture, "pre-match screen applies player avatar")
	selection_screen.free()
