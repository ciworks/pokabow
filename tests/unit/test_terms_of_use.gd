extends TestCase

const DIALOG_SCENE: String = "res://scenes/terms/terms_of_use_dialog.tscn"
const TEST_USERS_PATH: String = "user://test_users_state.json"
const TEST_LOGIN_PATH: String = "user://test_login_state.json"


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


func test_login_response_persists_token_and_user_details() -> void:
	UsersStateStore.save_accepted_account(
		"Player_123456789", "secret", "player@tiletopia.com", TEST_LOGIN_PATH
	)
	var response: Dictionary = {
		"token": "api-token",
		"user": {"id": 42, "displayName": "Player_123456789"},
		"expiresAt": "later",
	}
	check(UsersStateStore.save_user_state(response, TEST_LOGIN_PATH), "a token-bearing login response must be saved")
	check(UsersStateStore.has_user_state(TEST_LOGIN_PATH), "a later launch must find the saved user state")
	var state: Dictionary = UsersStateStore.load_user_state(TEST_LOGIN_PATH)
	check_eq(String(state.get("token", "")), "api-token", "the token must be directly accessible")
	check_eq(int((state.get("user", {}) as Dictionary).get("id", -1)), 42, "user details must be accessible")
	check_eq(String((state.get("response", {}) as Dictionary).get("expiresAt", "")), "later", "the full API response must be retained")
	check(UsersStateStore.has_accepted_account(TEST_LOGIN_PATH), "saving user state must retain the accepted account")
	DirAccess.remove_absolute(TEST_LOGIN_PATH)


func test_login_without_token_does_not_create_user_state() -> void:
	UsersStateStore.save_accepted_account(
		"Player_123456789", "secret", "player@tiletopia.com", TEST_LOGIN_PATH
	)
	check(not UsersStateStore.save_user_state({"user": {"id": 42}}, TEST_LOGIN_PATH), "a response without a token must be rejected")
	check(not UsersStateStore.has_user_state(TEST_LOGIN_PATH), "missing user state must trigger login on the next launch")
	DirAccess.remove_absolute(TEST_LOGIN_PATH)


func test_flat_login_response_exposes_user_details() -> void:
	var state: Dictionary = UsersStateStore.user_state_from_response({
		"token": "api-token", "id": 42, "displayName": "Player_123456789"
	})
	var user: Dictionary = state.get("user", {})
	check_eq(int(user.get("id", -1)), 42, "flat API user fields must be directly accessible")
	check(not user.has("token"), "user details should not duplicate the token")


func test_successful_login_populates_current_user_state() -> void:
	UsersStateStore.save_accepted_account(
		"Player_123456789", "secret", "player@tiletopia.com", TEST_LOGIN_PATH
	)
	var dialog: TermsOfUseDialog = _dialog()
	if dialog == null:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not check_not_null(tree, "a scene tree is needed to initialize the dialog"):
		dialog.free()
		return
	tree.root.add_child(dialog)
	dialog.set_users_path(TEST_LOGIN_PATH)
	# SceneTree test scripts run before ready notifications are dispatched.
	dialog.set("_accept_button", dialog.find_child("AcceptButton", true, false))
	var accepted_states: Array[Dictionary] = []
	dialog.accepted.connect(_collect_user_state.bind(accepted_states))
	dialog._on_request_completed(
		HTTPRequest.RESULT_SUCCESS,
		200,
		PackedStringArray(),
		'{"token":"api-token","user":{"id":42}}'.to_utf8_buffer()
	)
	check_eq(accepted_states.size(), 1, "HTTP 200 with a token must publish the current user")
	check_eq(String(UsersStateStore.load_user_state(TEST_LOGIN_PATH).get("token", "")), "api-token", "the login callback must persist the token")
	dialog.free()
	DirAccess.remove_absolute(TEST_LOGIN_PATH)


func _collect_user_state(state: Dictionary, states: Array[Dictionary]) -> void:
	states.append(state)


func _dialog() -> TermsOfUseDialog:
	var packed: PackedScene = load(DIALOG_SCENE) as PackedScene
	if not check_not_null(packed, "the terms dialog scene must load"):
		return null
	var dialog: TermsOfUseDialog = packed.instantiate() as TermsOfUseDialog
	if not check_not_null(dialog, "the terms dialog scene must be a TermsOfUseDialog"):
		return null
	return dialog
