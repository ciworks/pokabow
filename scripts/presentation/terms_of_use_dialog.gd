class_name TermsOfUseDialog
extends Control
## First-launch Terms of Use gate.
##
## The layout lives in terms_of_use_dialog.tscn so the copy and spacing can be
## redesigned without touching the account flow. This script only wires the
## close and accept actions, then asks the local auth API to provision or
## restore the account.

const TERMS_URL: String = "https://tiletopia.com/terms"
const PRIVACY_URL: String = "https://tiletopia.com/privacy"
const USERNAME_PREFIX: String = "Player_"
const EMAIL_DOMAIN: String = "@tiletopia.com"
const KEY_DIGITS: int = 9
const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")

static func json_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
	])

signal accepted(record: Dictionary)
signal failed(message: String)

@onready var _close_button: Button = %CloseButton
@onready var _accept_button: Button = %AcceptButton
@onready var _status_label: Label = %StatusLabel
@onready var _http: HTTPRequest = %AuthRequest

var _users_path: String = UsersStateStore.DEFAULT_PATH
var _pending_account: Dictionary = {}
var _busy: bool = false


func _ready() -> void:
	_apply_modern_tabletop_style()
	_close_button.pressed.connect(_on_close_pressed)
	_accept_button.pressed.connect(_on_accept_pressed)
	_http.request_completed.connect(_on_request_completed)
	_set_status("")


func _apply_modern_tabletop_style() -> void:
	theme = Tabletop.create()
	var panel: PanelContainer = $Scroll/Center/Panel
	var panel_style := Tabletop.panel(Tabletop.canvas(), 24, 28)
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color("#D8D0C2")
	panel.add_theme_stylebox_override("panel", panel_style)
	%Heading.add_theme_font_override("font", Tabletop.BOLD)
	%Heading.add_theme_color_override("font_color", Tabletop.ink())
	%Eyebrow.add_theme_font_override("font", Tabletop.SEMIBOLD)
	%Eyebrow.add_theme_color_override("font_color", Tabletop.muted())
	%Copy.add_theme_font_override("font", Tabletop.REGULAR)
	%Copy.add_theme_color_override("font_color", Tabletop.muted())
	%TermsLink.add_theme_font_override("font", Tabletop.SEMIBOLD)
	%PrivacyLink.add_theme_font_override("font", Tabletop.SEMIBOLD)
	for link: LinkButton in [%TermsLink, %PrivacyLink]:
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			link.add_theme_stylebox_override(state, Tabletop.button_style("quiet", state))
		link.add_theme_color_override("font_color", Tabletop.ink())
		link.add_theme_color_override("font_hover_color", Tabletop.ink())
		link.add_theme_color_override("font_pressed_color", Tabletop.ink())
		link.add_theme_font_size_override("font_size", 20)
	Tabletop.style_button(_accept_button, "primary")
	Tabletop.style_button(_close_button, "secondary")
	_accept_button.add_theme_font_size_override("font_size", 26)
	_close_button.add_theme_font_size_override("font_size", 20)
	_status_label.add_theme_font_override("font", Tabletop.REGULAR)
	_status_label.add_theme_color_override("font_color", Tabletop.muted())


## Tests point this at a temporary user:// file before the dialog is used.
func set_users_path(path: String) -> void:
	_users_path = path


## Later launches skip the dialog when the state file already holds an accepted
## account. The login itself is started by the shell, not by this scene.
static func has_accepted_account(path: String = UsersStateStore.DEFAULT_PATH) -> bool:
	return UsersStateStore.has_accepted_account(path)


static func load_account(path: String = UsersStateStore.DEFAULT_PATH) -> Dictionary:
	return UsersStateStore.load_record(path)


## Posts saved credentials and emits `accepted` only after a token is stored.
func login_saved_account() -> void:
	var record: Dictionary = UsersStateStore.load_record(_users_path)
	if not UsersStateStore.has_accepted_account(_users_path):
		_fail("No accepted account is saved.")
		return
	_post(
		ApiConfiguration.login_url(),
		{
			"username": String(record.get(UsersStateStore.KEY_USERNAME, "")),
			"email": String(record.get(UsersStateStore.KEY_EMAIL, "")),
			"password": String(record.get(UsersStateStore.KEY_PASSWORD, "")),
		},
		{}
	)


func _on_close_pressed() -> void:
	get_tree().quit()


func _on_accept_pressed() -> void:
	if _busy:
		return
	var key: String = _unique_key()
	var username: String = USERNAME_PREFIX + key
	var email: String = username + EMAIL_DOMAIN
	_pending_account = {
		"displayName": username,
		"password": username,
		"email": email,
	}
	_set_status("Creating your account...")
	_post(ApiConfiguration.register_url(), _pending_account, _pending_account)


func _post(url: String, body: Dictionary, pending: Dictionary) -> void:
	_busy = true
	_accept_button.disabled = true
	_pending_account = pending
	var error: Error = _http.request(
		url,
		json_headers(),
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	if error != OK:
		_fail("Could not reach the account service (%s)." % error_string(error))


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_busy = false
	_accept_button.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_fail(_failure_message(result, response_code, body))
		return

	var response: Dictionary = _parse_body(body)
	if not _pending_account.is_empty():
		var username: String = String(_pending_account.get("displayName", ""))
		var password: String = String(_pending_account.get("password", ""))
		var email: String = String(_pending_account.get("email", ""))
		if not UsersStateStore.save_accepted_account(username, password, email, _users_path):
			_fail("The account was created, but it could not be saved on this device.")
			return
		_pending_account = {}
		_set_status("Signing in...")
		login_saved_account()
		return

	if response_code != 200 or UsersStateStore.user_state_from_response(response).is_empty():
		_fail("The account service did not return a login token.")
		return
	if not UsersStateStore.save_user_state(response, _users_path):
		_fail("Signed in, but the user state could not be saved on this device.")
		return
	accepted.emit(UsersStateStore.load_user_state(_users_path))


func _failure_message(result: int, response_code: int, body: PackedByteArray) -> String:
	if result != HTTPRequest.RESULT_SUCCESS:
		return "Could not reach the account service."
	var parsed: Dictionary = _parse_body(body)
	var detail: String = String(parsed.get("message", parsed.get("error", "")))
	if detail.is_empty():
		return "The account service refused the request (%d)." % response_code
	return detail


func _parse_body(body: PackedByteArray) -> Dictionary:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed as Dictionary
	return {}


func _fail(message: String) -> void:
	_pending_account = {}
	_set_status(message)
	_status_label.add_theme_color_override("font_color", Tabletop.danger())
	failed.emit(message)


func _set_status(message: String) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.add_theme_color_override("font_color", Tabletop.muted())
	_status_label.visible = not message.is_empty()


func _unique_key() -> String:
	var digits: String = ""
	for _i: int in KEY_DIGITS:
		digits += str(randi() % 10)
	return digits
