extends TestCase

const DIALOG_SCENE: String = "res://scenes/terms/terms_of_use_dialog.tscn"
const TEST_USERS_PATH: String = "user://test_users_state.json"


func after() -> void:
	if FileAccess.file_exists(TEST_USERS_PATH):
		DirAccess.remove_absolute(TEST_USERS_PATH)


func test_dialog_scene_exposes_the_terms_controls() -> void:
	var dialog: TermsOfUseDialog = _dialog()
	if dialog == null:
		return
	var heading: Label = dialog.find_child("Heading", true, false) as Label
	var copy: Label = dialog.find_child("Copy", true, false) as Label
	var terms: LinkButton = dialog.find_child("TermsLink", true, false) as LinkButton
	var privacy: LinkButton = dialog.find_child("PrivacyLink", true, false) as LinkButton
	var accept: Button = dialog.find_child("AcceptButton", true, false) as Button
	var close: Button = dialog.find_child("CloseButton", true, false) as Button
	check_eq(heading.text if heading != null else "", "Terms of Use", "the dialog heading must read Terms of Use")
	check(
		copy != null and copy.text.contains("agree to our Terms of Use"),
		"the dialog must explain that continuing requires agreement"
	)
	check_eq(terms.uri if terms != null else "", "https://tiletopia.com/terms", "the terms link must open the terms page")
	check_eq(privacy.uri if privacy != null else "", "https://tiletopia.com/privacy", "the privacy link must open the privacy page")
	check_eq(accept.text if accept != null else "", "ACCEPT", "the call to action must be labelled ACCEPT")
	check_eq(close.text if close != null else "", "[ x ]", "the close control must be the corner [ x ] icon")
	dialog.free()


func test_state_file_round_trips_an_accepted_account() -> void:
	var saved: bool = UsersStateStore.save_accepted_account(
		"Player_123456789",
		"Player_123456789",
		"Player_123456789@tiletopia.com",
		TEST_USERS_PATH
	)
	check(saved, "the users state file must be writable under user://")
	check(
		UsersStateStore.has_accepted_account(TEST_USERS_PATH),
		"a saved acceptance plus credentials must count as an accepted account"
	)
	var record: Dictionary = UsersStateStore.load_record(TEST_USERS_PATH)
	check_eq(String(record.get("username", "")), "Player_123456789", "the saved username must round-trip")
	check(bool(record.get("terms_agreed", false)), "the saved record must mark the terms as agreed")


func test_missing_state_file_is_not_an_accepted_account() -> void:
	check(
		not UsersStateStore.has_accepted_account(TEST_USERS_PATH),
		"a missing users state file must show the terms dialog on the next launch"
	)


func _dialog() -> TermsOfUseDialog:
	var packed: PackedScene = load(DIALOG_SCENE) as PackedScene
	if not check_not_null(packed, "the terms dialog scene must load"):
		return null
	var dialog: TermsOfUseDialog = packed.instantiate() as TermsOfUseDialog
	if not check_not_null(dialog, "the terms dialog scene must be a TermsOfUseDialog"):
		return null
	return dialog
