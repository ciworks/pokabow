extends Node

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func verify(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var root: Window = get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i.ZERO
	var profile: ProfileScreen = load("res://scenes/profile/profile_screen.tscn").instantiate()
	root.add_child(profile)
	await get_tree().process_frame
	var requests: Array[int] = []
	var acknowledgements: Array[int] = []
	profile.delete_account_requested.connect(func() -> void: requests.append(1))
	profile.account_deletion_acknowledged.connect(func() -> void: acknowledgements.append(1))
	verify(profile._profile_content.get_child(profile._profile_content.get_child_count() - 1) == profile._delete_account_button,
		"Delete account is the last action on the profile overview")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(540, 960)]:
		root.size = dimensions
		await get_tree().process_frame
		profile._delete_account_button.pressed.emit()
		await get_tree().process_frame
		verify(profile._delete_confirmation.visible and not profile._profile_content.visible,
			"Confirmation replaces profile content at %s" % dimensions)
		verify(profile._delete_warning.text.contains("irrevocably"),
			"Confirmation explains irreversible deletion")
		verify(requests.is_empty(), "Opening confirmation does not delete")
		verify(profile._delete_confirm_button.size.y >= 48 and profile._delete_cancel_button.size.y >= 48,
			"Confirmation actions remain touchable at %s" % dimensions)
		profile._delete_cancel_button.pressed.emit()
		verify(profile._profile_content.visible and not profile._delete_confirmation.visible,
			"Cancel returns to profile")
	profile._delete_account_button.pressed.emit()
	profile._delete_confirm_button.pressed.emit()
	profile._delete_confirm_button.pressed.emit()
	verify(requests.size() == 1, "Confirm sends one deletion request while busy")
	profile._on_back_pressed()
	verify(profile._delete_confirmation.visible, "Busy deletion cannot be dismissed")
	profile.show_deletion_result(false, "Server unavailable")
	verify(not profile._delete_confirm_button.disabled, "Failure permits retry")
	profile.show_deletion_result(false, "Retry cleanup", true)
	verify(not profile._delete_cancel_button.visible, "Deleted server account cannot return to profile")
	profile.show_deletion_result(true, "Account deleted successfully", true)
	verify(profile._delete_confirm_button.text == "Continue", "Success requires acknowledgement")
	profile._delete_confirm_button.pressed.emit()
	verify(acknowledgements.size() == 1, "Continue acknowledges completion")
	print("Profile deletion checks: ", "PASS" if failures.is_empty() else failures)
	profile.free()
	get_tree().quit(0 if failures.is_empty() else 1)
