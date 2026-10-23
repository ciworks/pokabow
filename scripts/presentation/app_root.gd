class_name AppRoot
extends Node
## Application composition root (ADR-008 sections 4 and 5).
##
## Owns the persistent layer structure and the application-level services. ADR-008
## section 5 makes this node the composition root: it creates the match services
## and injects them into the active screen controller, so no scene script has to
## locate a service by an absolute path or pull one out of a global.
##
## Autoload policy: this node is NOT an autoload and owns the match only by
## holding a reference. ADR-008 section 6 forbids storing the game session, score
## ledger, board state, AI, or turn manager in a global, so the session lives
## inside `GameSessionController` and is released with it.
##
## Layer dependency direction: Presentation -> Application -> Domain
## (ADR-008 section 1). This script must not contain game rules, placement
## legality, or scoring.

const SCENE_HOST_PATH: NodePath = ^"SceneHost"
const OVERLAY_LAYER_PATH: NodePath = ^"OverlayLayer"
const ACCESSIBILITY_LAYER_PATH: NodePath = ^"AccessibilityLayer"

## The hub landing page: the first screen after the splash (owner direction,
## 2026-09-26). It is the shell's home, so it is created once and then only
## hidden while a match runs - never freed - so returning to it is instant and
## its switches keep the values the player set.
const HUB_SCREEN_SCENE: String = "res://scenes/hub/hub_screen.tscn"

## Separate terms scene, hosted on OverlayLayer until the local account has
## accepted. Designed so the dialog can be restyled later without touching boot.
const TERMS_DIALOG_SCENE: String = "res://scenes/terms/terms_of_use_dialog.tscn"

## The playable screen, loaded when the player asks for a match from the hub.
const GAME_SCREEN_SCENE: String = "res://scenes/game/game_screen.tscn"

## New matches begin with a brief local rival-selection reveal.
const OPPONENT_SELECTION_SCENE: String = "res://scenes/hub/opponent_selection_screen.tscn"

## Editable account details, hosted as a separate screen.
const PROFILE_SCREEN_SCENE: String = "res://scenes/profile/profile_screen.tscn"

const ProgressionClient = preload("res://scripts/infrastructure/progression_api_client.gd")

## How long the authored splash is held before the match boots, in seconds.
##
## Long enough to read the title, short enough not to feel like a wait. The hold
## is the whole of the splash's life: booting a match is synchronous and fast, so
## without a deliberate beat here the composition root would replace the splash in
## the same frame it appeared and no player would ever see it.
const SPLASH_HOLD_SECONDS: float = 1.2
const AUTH_RECOVERY_WINDOW_MSEC: int = 60000

## Host for the active screen. Screens are swapped inside this node.
var scene_host: Node = null

## Drawn above gameplay for transitions and error dialogs.
var overlay_layer: CanvasLayer = null

## Reserved for accessibility presentation that must sit above all other UI.
var accessibility_layer: CanvasLayer = null

## The application-level match service, created here and owned by the session.
var session_controller: GameSessionController = null

## The hub landing page, or null before the splash hold reveals it (owner
## direction, 2026-09-26).
var hub_screen: HubScreen = null
var tables_screen: MatchTablesScreen = null
var _active_ai_rival_path: String = ""

## The active playable screen, or null while the hub is the visible screen.
var game_screen: GameScreen = null

## Save selected by an active-game card, or allocated for a newly staged AI match.
var _pending_local_save_path: String = ""
var _pending_local_match_id: String = ""
var _open_online_when_received: bool = false

## The short-lived selection screen shown before a new match.
var opponent_selection_screen: OpponentSelectionScreen = null
var matchmaking_client: MatchmakingApiClient = null
var online_client: OnlineGameApiClient = null

## Account details screen, or null while another screen is visible.
var profile_screen: ProfileScreen = null

## The platform feedback service (ADR-008 section 5; Milestone 8). Owned here and
## injected into the screen, so haptics and audio are composed in one place and
## the screen holds no platform call of its own.
var feedback_adapter: FeedbackAdapter = null

## Terms gate. Null once the player has accepted, or when the local state file
## already records an accepted account.
var terms_dialog: TermsOfUseDialog = null

## Authenticated API user for this app session. Restored from the local account
## record at launch, or populated after a successful login.
var user_state: Dictionary = {}

## Authenticated achievement transport, owned by the application shell.
var achievement_client: AchievementApiClient = null
var achievement_toast: AchievementToast = null
var progression_client: ProgressionClient = null
var _last_progression_match_id: String = ""

## Authenticated match creation and turn synchronization transport.
var game_sync_client: GameSyncApiClient = null
var _account_delete_active: bool = false
var _remote_account_deleted: bool = false
var _account_deletion_client: AccountDeletionClient = null
var _login_active: bool = false
var _profile_request_active: bool = false
var _profile_save_active: bool = false
var _profile_avatar_request_version: int = 0
var _opponent_avatar_id: String = ""
var _opponent_avatar_texture: Texture2D = null
var _opponent_avatar_request: HTTPRequest = null
var users_path: String = UsersStateStore.DEFAULT_PATH
var _authentication_blocked: bool = false
var _last_login_success_msec: int = -AUTH_RECOVERY_WINDOW_MSEC
var _authentication_dialog: ConfirmationDialog = null
var _authentication_error: String = ""
var _account_reset_pending: bool = false
var _cleanup_account_id: String = ""


## Resolves the persistent layer nodes this composition root owns.
##
## Called from `_ready` and again from `boot_game_screen`, because the screen may
## be booted before this node's `_ready` has run: under `--script` the engine
## defers `_ready`, so `AppRoot` cannot assume its own `_ready` has happened
## (ADR-008 section 5). Re-running is harmless.
func _bind_layers() -> void:
	scene_host = get_node_or_null(SCENE_HOST_PATH)
	overlay_layer = get_node_or_null(OVERLAY_LAYER_PATH) as CanvasLayer
	accessibility_layer = get_node_or_null(ACCESSIBILITY_LAYER_PATH) as CanvasLayer


func _ready() -> void:
	_bind_layers()

	var missing: PackedStringArray = PackedStringArray()
	if scene_host == null:
		missing.append(String(SCENE_HOST_PATH))
	if overlay_layer == null:
		missing.append(String(OVERLAY_LAYER_PATH))
	if accessibility_layer == null:
		missing.append(String(ACCESSIBILITY_LAYER_PATH))
	if not missing.is_empty():
		push_error(
			"AppRoot bootstrap failed; missing layer node(s): %s (ADR-008 section 4)."
			% ", ".join(missing)
		)
		return
	achievement_toast = AchievementToast.new()
	achievement_toast.name = "AchievementToast"
	overlay_layer.add_child(achievement_toast)

	print("[AppRoot] bootstrap ready (screens hosted: %d)" % scene_host.get_child_count())
	achievement_client = AchievementApiClient.new()
	add_child(achievement_client)
	achievement_client.newly_unlocked.connect(_on_achievements_unlocked)
	achievement_client.catalog_received.connect(_on_achievement_catalog_received)
	achievement_client.catalog_loading.connect(_on_achievement_catalog_loading)
	achievement_client.catalog_failed.connect(_on_achievement_catalog_failed)
	progression_client = ProgressionClient.new()
	add_child(progression_client)
	progression_client.received.connect(_on_progression_received)
	progression_client.failed.connect(_on_progression_failed)
	progression_client.authentication_required.connect(_refresh_api_login)
	matchmaking_client = MatchmakingApiClient.new()
	add_child(matchmaking_client)
	matchmaking_client.authentication_required.connect(_refresh_api_login)
	matchmaking_client.changed.connect(_on_online_lobby_changed)
	online_client = OnlineGameApiClient.new()
	add_child(online_client)
	online_client.authentication_required.connect(_refresh_api_login)
	online_client.received.connect(_on_online_received)
	game_sync_client = GameSyncApiClient.new()
	add_child(game_sync_client)
	game_sync_client.authentication_required.connect(_refresh_api_login)
	game_sync_client.sync_notice.connect(_on_sync_notice)
	game_sync_client.score_preview_received.connect(_on_api_score_preview)
	achievement_client.authentication_required.connect(_refresh_api_login)
	_prepare_startup_assets()


## Loads sound cues and tile art while the splash is visible.
func _prepare_startup_assets() -> void:
	if scene_host == null:
		return
	var loading_bar := scene_host.get_node_or_null(
		"SplashScreen/CenterContainer/TitleBlock/LoadingProgress"
	) as ProgressBar
	if loading_bar != null:
		loading_bar.value = 0.0
	_ensure_feedback_adapter(loading_bar)
	await feedback_adapter.audio_preload_completed
	await _warm_tile_art(loading_bar)
	_begin_splash_hold(_after_splash)


func _ensure_feedback_adapter(loading_bar: ProgressBar = null) -> void:
	if feedback_adapter != null:
		return
	feedback_adapter = FeedbackAdapter.new()
	feedback_adapter.audio_preload_progress.connect(
		_on_startup_audio_preload_progress.bind(loading_bar)
	)
	add_child(feedback_adapter)


func _on_startup_audio_preload_progress(completed: int, total: int, loading_bar: ProgressBar) -> void:
	if not is_instance_valid(loading_bar) or total <= 0:
		return
	# Reserve the final 30 percent for tile textures.
	loading_bar.value = 70.0 * float(completed) / float(total)


## Resolve tile textures behind the splash so the first tile reveals do not
## synchronously load face and edge art during the deal animation.
func _warm_tile_art(loading_bar: ProgressBar) -> void:
	var paths: PackedStringArray = TilePainter.warmable_art_paths()
	if paths.is_empty():
		if is_instance_valid(loading_bar):
			loading_bar.value = 100.0
		return
	for index: int in range(paths.size()):
		TilePainter.warm_art_path(paths[index])
		if is_instance_valid(loading_bar):
			loading_bar.value = 70.0 + 30.0 * float(index + 1) / float(paths.size())
		await get_tree().process_frame


## Splash hands over to the terms gate, or straight to the hub when this device
## already has an accepted account. Restore its saved user state, or request a
## fresh login when that state is missing.
func _after_splash() -> void:
	if _account_reset_pending:
		return
	if UsersStateStore.has_accepted_account():
		user_state = UsersStateStore.load_user_state()
		achievement_client.set_access_token(String(user_state.get("token", "")))
		progression_client.set_credentials(String(user_state.get("token", "")), String(user_state.get("user", {}).get("id", "")))
		game_sync_client.set_access_token(String(user_state.get("token", "")))
		if user_state.is_empty():
			_login_returning_account(UsersStateStore.load_record())
		show_hub()
		return
	_show_terms_dialog()


## Hosts the terms scene on the overlay until Accept succeeds.
func _show_terms_dialog() -> void:
	_bind_layers()
	if overlay_layer == null:
		push_error("AppRoot: OverlayLayer is missing, so the terms dialog cannot be shown.")
		return
	if terms_dialog != null and is_instance_valid(terms_dialog):
		terms_dialog.visible = true
		return
	var packed: PackedScene = load(TERMS_DIALOG_SCENE) as PackedScene
	if packed == null:
		push_error("AppRoot: '%s' could not be loaded." % TERMS_DIALOG_SCENE)
		return
	var dialog: TermsOfUseDialog = packed.instantiate() as TermsOfUseDialog
	if dialog == null:
		push_error("AppRoot: '%s' is not a TermsOfUseDialog." % TERMS_DIALOG_SCENE)
		return
	terms_dialog = dialog
	overlay_layer.add_child(dialog)
	dialog.accepted.connect(_on_terms_accepted)


func _on_terms_declined() -> void:
	get_tree().quit()


func _on_terms_accepted(state: Dictionary) -> void:
	if terms_dialog != null and is_instance_valid(terms_dialog):
		terms_dialog.queue_free()
		terms_dialog = null
	user_state = state.duplicate(true)
	achievement_client.set_access_token(String(user_state.get("token", "")))
	progression_client.set_credentials(String(user_state.get("token", "")), String(user_state.get("user", {}).get("id", "")))
	game_sync_client.set_access_token(String(user_state.get("token", "")))
	show_hub()
	achievement_client.fetch_catalog()


func _on_achievements_unlocked(ids: Array) -> void:
	var catalog: Array[Dictionary] = UsersStateStore.achievement_catalog()
	for achievement_id: Variant in ids:
		var entry: Dictionary = achievement_id if achievement_id is Dictionary else {}
		var raw_id: Variant = entry.get("id", achievement_id)
		if not (raw_id is String or raw_id is StringName):
			continue
		var id: String = str(raw_id).strip_edges()
		if id.is_empty():
			continue
		var title: String = id.replace("_", " ").capitalize()
		var description: String = ""
		var badge_key: String = id
		for row: Dictionary in catalog:
			if str(row.get("id", "")) == id:
				title = str(row.get("name", title))
				description = str(row.get("description", ""))
				var art: Variant = row.get("badgeKey", "")
				if art is String and not str(art).is_empty():
					badge_key = str(art)
				break
		title = str(entry.get("name", title))
		description = str(entry.get("description", description))
		var entry_art: Variant = entry.get("badgeKey", "")
		if entry_art is String and not str(entry_art).is_empty():
			badge_key = str(entry_art)
		if achievement_toast != null:
			achievement_toast.show_achievement(id, title, description, badge_key)


func _on_achievement_catalog_loading() -> void:
	if is_instance_valid(profile_screen):
		profile_screen.set_achievement_loading()


func _on_achievement_catalog_failed(message: String) -> void:
	if is_instance_valid(profile_screen):
		profile_screen.set_achievement_error(message)


func _on_achievement_catalog_received(rows: Array) -> void:
	if profile_screen != null and is_instance_valid(profile_screen):
		profile_screen.set_achievement_rows(rows)


## Posts the saved credentials to the login endpoint. Does not block the hub:
## a local server that is down must not trap a player who already accepted.
func _login_returning_account(record: Dictionary) -> void:
	if _login_active or _account_delete_active or _remote_account_deleted or _authentication_blocked or _account_reset_pending:
		return
	_login_active = true
	var client := HTTPRequest.new()
	client.timeout = 15.0
	client.name = "ReturningLogin"
	add_child(client)
	client.request_completed.connect(_on_returning_login_completed.bind(client))
	var body := JSON.stringify({
		"username": String(record.get(UsersStateStore.KEY_USERNAME, "")),
		"email": String(record.get(UsersStateStore.KEY_EMAIL, "")),
		"password": String(record.get(UsersStateStore.KEY_PASSWORD, "")),
	})
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json"])
	var err: int = _send_login_request(client, headers, body)
	if err != OK:
		_login_active = false
		client.queue_free()
		_api_login_failed("Could not connect to your account. Check the Server IP in Settings and try again.")
		return
	# The request is fire-and-observe. The hub is already the next screen.


func _send_login_request(client: HTTPRequest, headers: PackedStringArray, body: String) -> int:
	return client.request(ApiConfiguration.login_url(), headers, HTTPClient.METHOD_POST, body)


func _on_returning_login_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	client: HTTPRequest
) -> void:
	_login_active = false
	if is_instance_valid(client):
		client.queue_free()
	if _account_delete_active or _remote_account_deleted or _account_reset_pending:
		return
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 401:
		_begin_unavailable_account_reset()
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_api_login_failed("Could not sign in. Check your connection and the Server IP in Settings, then retry.")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_api_login_failed("The server returned an invalid login response. Please retry.")
		return
	var response: Dictionary = parsed
	if not UsersStateStore.save_user_state(response, users_path):
		_api_login_failed("The login response had no token or could not be saved. Please retry.")
		return
	_last_login_success_msec = Time.get_ticks_msec()
	user_state = UsersStateStore.load_user_state(users_path)
	if achievement_client != null:
		achievement_client.set_access_token(String(user_state.get("token", "")))
	if progression_client != null:
		progression_client.set_credentials(String(user_state.get("token", "")), String(user_state.get("user", {}).get("id", "")))
	if game_sync_client != null:
		game_sync_client.set_access_token(String(user_state.get("token", "")))
	if matchmaking_client != null:
		matchmaking_client.set_credentials(String(user_state.get("token", "")), String(user_state.get("user", {}).get("id", "")))
	if online_client != null:
		online_client.set_credentials(String(user_state.get("token", "")), String(user_state.get("user", {}).get("id", "")))
		_refresh_online_hub_state()
	if game_screen != null:
		game_screen.set_player_display_name(_player_display_name())
	if profile_screen != null and is_instance_valid(profile_screen):
		_fetch_current_user()
		achievement_client.fetch_catalog()


func _refresh_api_login() -> void:
	if _login_active or _account_delete_active or _remote_account_deleted or _account_reset_pending:
		return
	if _authentication_blocked:
		_api_login_failed(_authentication_error)
		return
	_clear_api_session()
	# A fresh login token being rejected immediately must not create a loop.
	if Time.get_ticks_msec() - _last_login_success_msec < AUTH_RECOVERY_WINDOW_MSEC:
		_api_login_failed("The server rejected the refreshed session (401). Check the Server IP in Settings, then retry.")
		return
	_login_returning_account(UsersStateStore.load_record(users_path))


func _clear_api_session() -> void:
	_clear_opponent_avatar()
	user_state.erase("token")
	user_state.erase("response")
	UsersStateStore.clear_user_state(users_path)
	if achievement_client != null:
		achievement_client.set_access_token("")
	if progression_client != null:
		progression_client.set_credentials("", "")
	_last_progression_match_id = ""
	if game_sync_client != null:
		game_sync_client.set_access_token("")
	if matchmaking_client != null:
		matchmaking_client.set_credentials("", matchmaking_client.account_id)
	if online_client != null:
		online_client.set_credentials("", online_client.account_id)


func _api_login_failed(message: String) -> void:
	_authentication_blocked = true
	_authentication_error = message
	_clear_api_session()
	if matchmaking_client != null:
		matchmaking_client.authentication_failed(message)
	if online_client != null:
		online_client.authentication_failed(message)
	_show_authentication_error(message)


func _show_authentication_error(message: String = "") -> void:
	_bind_layers()
	if overlay_layer == null:
		return
	if _authentication_dialog == null:
		_authentication_dialog = ConfirmationDialog.new()
		_authentication_dialog.title = "Account connection failed"
		_authentication_dialog.ok_button_text = "Retry"
		_authentication_dialog.cancel_button_text = "Close"
		_authentication_dialog.dialog_autowrap = true
		overlay_layer.add_child(_authentication_dialog)
		_authentication_dialog.confirmed.connect(_retry_api_login)
	if not message.is_empty():
		_authentication_dialog.dialog_text = message if _account_reset_pending else message + "\n\nYou can still play against AI. Your saved game is kept."
	_authentication_dialog.get_cancel_button().visible = not _account_reset_pending
	_authentication_dialog.popup_centered(Vector2i(340, 240))


func _retry_api_login() -> void:
	if _account_reset_pending:
		_finish_unavailable_account_reset()
		return
	_authentication_blocked = false
	_last_login_success_msec = -AUTH_RECOVERY_WINDOW_MSEC
	_login_returning_account(UsersStateStore.load_record(users_path))


## A rejected saved-credential login means this installation needs a new account.
## Defer teardown until the HTTP completion signal has finished dispatching.
func _begin_unavailable_account_reset() -> void:
	if _account_reset_pending:
		return
	_account_reset_pending = true
	_authentication_blocked = true
	_cleanup_account_id = String(user_state.get("user", {}).get("id", ""))
	_finish_unavailable_account_reset.call_deferred()


func _finish_unavailable_account_reset() -> void:
	_release_account_services()
	if hub_screen != null:
		hub_screen.visible = false
	if not UsersStateStore.clear_local_state(users_path.get_base_dir(), _cleanup_account_id, true):
		_show_authentication_error("Your saved account is no longer available. Some local account data could not be removed. Retry cleanup to start a new account.")
		return
	_reset_account_preferences()
	_restart_for_new_account()


func _restart_for_new_account() -> void:
	if get_tree().reload_current_scene() != OK:
		_show_authentication_error("Account data was cleared, but the game could not restart. Retry to open new account setup.")


func _on_sync_notice(message: String) -> void:
	if session_controller != null and is_instance_valid(session_controller):
		session_controller.notice.emit(message)


func _on_api_score_preview(score: Dictionary) -> void:
	if game_screen != null and is_instance_valid(game_screen):
		game_screen.set_api_score_preview(score)


func _fetch_current_user() -> void:
	if _profile_request_active:
		return
	var token: String = String(user_state.get("token", ""))
	if token.is_empty():
		_refresh_api_login()
		return
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	request.request_completed.connect(_on_current_user_received.bind(request, token))
	_profile_request_active = true
	var error: int = request.request(ApiConfiguration.api_base_url() + "/auth/me",
		PackedStringArray(["Authorization: Bearer %s" % token]))
	if error != OK:
		_profile_request_active = false
		request.queue_free()


func _on_current_user_received(result: int, code: int, _headers: PackedStringArray,
	body: PackedByteArray, request: HTTPRequest, token: String) -> void:
	request.queue_free()
	_profile_request_active = false
	if _account_delete_active or _remote_account_deleted or _account_reset_pending or token != String(user_state.get("token", "")):
		return
	if code == 401:
		_refresh_api_login()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.has("id") or not data.has("displayName"):
		return
	user_state["user"] = data
	UsersStateStore.save_user_state({"token": token, "user": data})
	if profile_screen != null and is_instance_valid(profile_screen):
		profile_screen.set_user_state(user_state)
	_fetch_current_avatar(token)


func _save_profile(username: String, avatar_png_base64: String) -> void:
	if _profile_save_active or profile_screen == null or not is_instance_valid(profile_screen):
		return
	var token: String = String(user_state.get("token", ""))
	if token.is_empty():
		profile_screen.set_profile_save_result(false, "Sign in again before saving profile changes.")
		return
	_profile_save_active = true
	_profile_avatar_request_version += 1
	profile_screen.set_profile_save_pending(true)
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	request.request_completed.connect(_on_profile_avatar_saved.bind(request, token, username, avatar_png_base64))
	var payload: String = JSON.stringify({"contentType": "image/png", "data": avatar_png_base64})
	var error: int = request.request(ApiConfiguration.api_base_url() + "/auth/me/avatar",
		PackedStringArray(["Authorization: Bearer %s" % token, "Content-Type: application/json"]),
		HTTPClient.METHOD_PUT, payload)
	if error != OK:
		_profile_save_active = false
		profile_screen.set_profile_save_pending(false)
		profile_screen.set_profile_save_result(false, "Could not save avatar. Please try again.")
		request.queue_free()


func _on_profile_avatar_saved(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, request: HTTPRequest, token: String, submitted_name: String,
		submitted_avatar_data: String) -> void:
	request.queue_free()
	if _account_delete_active or _remote_account_deleted or _account_reset_pending or token != String(user_state.get("token", "")):
		_profile_save_active = false
		return
	if profile_screen == null or not is_instance_valid(profile_screen):
		_profile_save_active = false
		return
	if code == 401:
		_profile_save_active = false
		profile_screen.set_profile_save_pending(false)
		profile_screen.set_profile_save_result(false, "Session expired. Refresh your account and try again.")
		_refresh_api_login()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_profile_save_active = false
		var error_message: String = "Could not save avatar. Please try again."
		var error_data: Variant = JSON.parse_string(body.get_string_from_utf8())
		if code == 400 and error_data is Dictionary:
			error_message = "The avatar was rejected. Check the image and try again."
		profile_screen.set_profile_save_pending(false)
		profile_screen.set_profile_save_result(false, error_message)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("avatar") is Dictionary:
		_profile_save_active = false
		profile_screen.set_profile_save_pending(false)
		profile_screen.set_profile_save_result(false, "The server returned an invalid avatar response. Please try again.")
		return
	var avatar_record: Dictionary = data.avatar
	if (String(avatar_record.get("url", "")) != "/auth/me/avatar"
			or String(avatar_record.get("contentType", "")) != "image/png"
			or int(avatar_record.get("width", 0)) != PlayerAvatarStore.SIZE
			or int(avatar_record.get("height", 0)) != PlayerAvatarStore.SIZE):
		_profile_save_active = false
		profile_screen.set_profile_save_pending(false)
		profile_screen.set_profile_save_result(false, "The server returned an invalid avatar response. Please try again.")
		return
	if not profile_screen.set_profile_avatar_persisted(submitted_avatar_data):
		_profile_save_active = false
		profile_screen.set_profile_save_pending(false)
		profile_screen.set_profile_save_result(false, "Avatar saved online, but this device could not cache it. Please retry.")
		return
	var username_request := HTTPRequest.new()
	username_request.timeout = 15.0
	add_child(username_request)
	username_request.request_completed.connect(_on_profile_username_saved.bind(username_request, token, submitted_name))
	var username_payload: String = JSON.stringify({"displayName": submitted_name})
	var error: int = username_request.request(ApiConfiguration.api_base_url() + "/auth/me",
		PackedStringArray(["Authorization: Bearer %s" % token, "Content-Type: application/json"]),
		HTTPClient.METHOD_PATCH, username_payload)
	if error != OK:
		_profile_save_active = false
		profile_screen.set_profile_save_pending(false)
		profile_screen.set_profile_save_result(false, "Avatar saved, but username could not be saved. Please retry.")
		username_request.queue_free()


func _on_profile_username_saved(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, request: HTTPRequest, token: String, submitted_name: String) -> void:
	request.queue_free()
	_profile_save_active = false
	if _account_delete_active or _remote_account_deleted or _account_reset_pending or token != String(user_state.get("token", "")):
		return
	if profile_screen == null or not is_instance_valid(profile_screen):
		return
	if code == 401:
		profile_screen.set_profile_save_pending(false)
		profile_screen.set_profile_save_result(false, "Avatar saved, but session expired before the username was saved.")
		_refresh_api_login()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		var error_message: String = "Avatar saved, but the display name could not be saved. Please retry."
		var error_data: Variant = JSON.parse_string(body.get_string_from_utf8())
		var api_error: String = String(error_data.get("error", "")) if error_data is Dictionary else ""
		if code == 400:
			error_message = "Avatar saved, but the display name was rejected. Use 1–50 characters and retry."
		elif code == 404 or code == 405:
			error_message = "Avatar saved, but this API server does not support display-name updates. Restart it with the latest pokabow-api and retry."
		elif code > 0:
			error_message = "Avatar saved, but the display name could not be saved (HTTP %d%s). Please retry." % [
				code,
				" · %s" % api_error if not api_error.is_empty() else "",
			]
		elif result != HTTPRequest.RESULT_SUCCESS:
			error_message = "Avatar saved, but the display-name request could not reach the API. Check the connection and retry."
		profile_screen.set_profile_save_pending(false)
		profile_screen.set_profile_save_result(false, error_message)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or String(data.get("id", "")) != String((user_state.get("user", {}) as Dictionary).get("id", "")):
		profile_screen.set_profile_save_pending(false)
		profile_screen.set_profile_save_result(false, "Avatar saved, but the profile response was invalid. Please refresh.")
		return
	if not data.has("displayName") or String(data.get("displayName", "")) != submitted_name:
		profile_screen.set_profile_save_pending(false)
		profile_screen.set_profile_save_result(false, "Avatar saved, but the username response was invalid. Please refresh.")
		return
	user_state["user"] = data
	UsersStateStore.save_user_state({"token": token, "user": data})
	profile_screen.set_user_state(user_state)
	profile_screen.set_profile_save_result(true)


func _fetch_current_avatar(token: String) -> void:
	var request_version: int = _profile_avatar_request_version
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	request.request_completed.connect(_on_current_avatar_received.bind(request, token, request_version))
	var error: int = request.request(ApiConfiguration.api_base_url() + "/auth/me/avatar",
		PackedStringArray(["Authorization: Bearer %s" % token]))
	if error != OK:
		request.queue_free()


func _on_current_avatar_received(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, request: HTTPRequest, token: String, request_version: int) -> void:
	request.queue_free()
	if (_account_delete_active or _remote_account_deleted or _account_reset_pending
			or _profile_save_active or token != String(user_state.get("token", ""))
			or request_version != _profile_avatar_request_version
			or result != HTTPRequest.RESULT_SUCCESS or code != 200):
		return
	var encoded: String = Marshalls.raw_to_base64(body)
	if profile_screen != null and is_instance_valid(profile_screen):
		profile_screen.set_remote_avatar_data(encoded)
	else:
		PlayerAvatarStore.save_png_base64(encoded)


func _player_display_name() -> String:
	var user: Variant = user_state.get("user", {})
	if typeof(user) != TYPE_DICTIONARY:
		return ""
	return String((user as Dictionary).get("displayName", ""))


## Reveals the hub landing page: the app shell's home screen (owner direction,
## 2026-09-26).
##
## Idempotent. The hub is created once and then only hidden and revealed, so a
## player who plays a match, returns to the hub, and plays again never waits for
## a second hub to be built and never finds its settings switches reset.
##
## Returns true when the hub is on screen.
func show_hub() -> bool:
	_bind_layers()
	if scene_host == null:
		return false
	if hub_screen != null and hub_screen.get_parent() == scene_host:
		if profile_screen != null and profile_screen.get_parent() == scene_host:
			scene_host.remove_child(profile_screen)
			profile_screen.free()
			profile_screen = null
		hub_screen.visible = true
		_update_hub_play_label()
		_refresh_hub_active_games()
		_refresh_hub_recent_match()
		_refresh_online_hub_state()
		return true

	var wrapper: PackedScene = load(HUB_SCREEN_SCENE) as PackedScene
	if wrapper == null:
		push_error("AppRoot.show_hub: '%s' could not be loaded." % HUB_SCREEN_SCENE)
		return false
	var hub: HubScreen = wrapper.instantiate() as HubScreen
	if hub == null:
		push_error("AppRoot.show_hub: '%s' is not a HubScreen." % HUB_SCREEN_SCENE)
		return false

	hub_screen = hub
	_replace_hosted_screens()
	scene_host.add_child(hub)
	# The hub reports the intent; the shell decides what Play means. That way the
	# hub script holds no reference to the match, and Presentation stays out of
	# Application (ADR-008 section 1).
	hub.play_requested.connect(_on_hub_play_requested)
	hub.online_requested.connect(_on_hub_online_requested)
	hub.profile_requested.connect(_on_hub_profile_requested)
	hub.achievements_requested.connect(_on_hub_achievements_requested)
	hub.clear_game_cache_requested.connect(_on_clear_game_cache_requested)
	hub.delete_account_requested.connect(_on_delete_account_requested)
	hub.account_deletion_acknowledged.connect(_on_account_deletion_acknowledged)
	hub.resume_game_requested.connect(_on_active_game_resume_requested)
	hub.tables_requested.connect(_show_tables)
	hub.completed_match_requested.connect(_show_completed_match)
	_update_hub_play_label()
	_refresh_hub_active_games()
	_refresh_hub_recent_match()
	_refresh_online_hub_state()
	return true


func _update_hub_play_label() -> void:
	if hub_screen == null or not is_instance_valid(hub_screen):
		return
	hub_screen.set_play_button_label(HubScreen.PLAY_LABEL_NEW_GAME)


func _refresh_hub_active_games() -> void:
	if hub_screen == null or not is_instance_valid(hub_screen):
		return
	var games: Array[Dictionary] = GameSessionController.saved_match_entries()
	if online_client != null and not online_client.state.is_empty():
		var remote_state: Dictionary = online_client.state
		if String(remote_state.get("status", "active")) != "completed":
			var opponent: Dictionary = remote_state.get("opponent", {})
			var opponent_name: String = String(opponent.get("displayName", "Rival"))
			if opponent_name.strip_edges().is_empty():
				opponent_name = "Rival"
			var view: OnlineSessionView = OnlineSessionView.from_response(remote_state)
			var human_score: int = 0 if view == null else view.score_for(TurnEnums.HUMAN_PLAYER_ID)
			var rival_score: int = 0 if view == null else view.score_for(TurnEnums.AI_PLAYER_ID)
			games.append({
				"kind": "online",
				"id": online_client.match_id,
				"path": "",
				"opponent": opponent_name,
				"score": "You %d  |  %s %d" % [human_score, opponent_name, rival_score],
				"saved_at": "",
				"status_label": "YOUR TURN" if String(remote_state.get("turn", {}).get("active_player_id", "")) == String(remote_state.get("seat", "")) else "WAITING",
				"avatar_path": _online_avatar_path(String(opponent.get("id", ""))),
			})
	games.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_rank: int = _hub_game_rank(a)
		var b_rank: int = _hub_game_rank(b)
		return a_rank < b_rank if a_rank != b_rank else String(a.get("saved_at", "")) > String(b.get("saved_at", ""))
	)
	hub_screen.set_active_games(games)


static func _hub_game_rank(game: Dictionary) -> int:
	if String(game.get("kind", "")) == "online":
		return 0 if String(game.get("status_label", "")) == "YOUR TURN" else 2
	return 1


func _refresh_hub_recent_match() -> void:
	if hub_screen == null or not is_instance_valid(hub_screen):
		return
	var completed: Array[Dictionary] = MatchHistoryStore.entries(_account_id())
	hub_screen.set_recent_match(completed[0] if not completed.is_empty() else {})


func _account_id() -> String:
	return String(user_state.get("user", {}).get("id", ""))


func _show_tables() -> void:
	_bind_layers()
	if scene_host == null:
		return
	if tables_screen != null and is_instance_valid(tables_screen):
		tables_screen.set_records(_hub_active_entries(), MatchHistoryStore.entries(_account_id()))
		tables_screen.show_list()
		tables_screen.visible = true
	else:
		var screen := MatchTablesScreen.new()
		tables_screen = screen
		_replace_hosted_screens()
		scene_host.add_child(screen)
		screen.set_records(_hub_active_entries(), MatchHistoryStore.entries(_account_id()))
		screen.back_requested.connect(_on_tables_back)
		screen.resume_game_requested.connect(_on_tables_resume)
	if hub_screen != null:
		hub_screen.visible = false


func _show_completed_match(kind: String, id: String) -> void:
	_show_tables()
	if tables_screen != null:
		tables_screen.show_detail(kind, id)


func _on_tables_back() -> void:
	if tables_screen != null:
		if tables_screen.get_parent() == scene_host:
			scene_host.remove_child(tables_screen)
		tables_screen.queue_free()
		tables_screen = null
	show_hub()


func _on_tables_resume(kind: String, id: String, path: String) -> void:
	_on_tables_back()
	_on_active_game_resume_requested(kind, id, path)


func _hub_active_entries() -> Array[Dictionary]:
	var games: Array[Dictionary] = GameSessionController.saved_match_entries()
	if online_client != null and not online_client.state.is_empty() and String(online_client.state.get("status", "")) == "active":
		var data: Dictionary = online_client.state
		var opponent: Dictionary = data.get("opponent", {})
		var view: OnlineSessionView = OnlineSessionView.from_response(data)
		if view != null:
			games.append({"kind": "online", "id": online_client.match_id, "path": "",
				"opponent": String(opponent.get("displayName", "Rival")),
				"avatar_path": _online_avatar_path(String(opponent.get("id", ""))),
				"score": "You %d · Rival %d" % [view.score_for(TurnEnums.HUMAN_PLAYER_ID), view.score_for(TurnEnums.AI_PLAYER_ID)],
				"status_label": "YOUR TURN" if String(data.get("turn", {}).get("active_player_id", "")) == String(data.get("seat", "")) else "WAITING"})
	games.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_rank: int = _hub_game_rank(a)
		var b_rank: int = _hub_game_rank(b)
		return a_rank < b_rank if a_rank != b_rank else String(a.get("saved_at", "")) > String(b.get("saved_at", ""))
	)
	return games


func _refresh_online_hub_state() -> void:
	if online_client == null or user_state.is_empty():
		return
	online_client.set_credentials(
		String(user_state.get("token", "")),
		String(user_state.get("user", {}).get("id", ""))
	)
	if not online_client._wanted and game_screen == null:
		_open_online_when_received = false
		online_client.recover()


## Handles the hub's Play request.
func _on_hub_play_requested() -> void:
	show_opponent_selection()


## Shows the rival portrait spinner before creating a new match.
func show_opponent_selection() -> bool:
	_bind_layers()
	if scene_host == null:
		return false
	if opponent_selection_screen != null and is_instance_valid(opponent_selection_screen):
		opponent_selection_screen.visible = true
		return true
	var packed: PackedScene = load(OPPONENT_SELECTION_SCENE) as PackedScene
	if packed == null:
		push_error("AppRoot.show_opponent_selection: '%s' could not be loaded." % OPPONENT_SELECTION_SCENE)
		return false
	var selection: OpponentSelectionScreen = packed.instantiate() as OpponentSelectionScreen
	if selection == null:
		push_error("AppRoot.show_opponent_selection: '%s' is not an OpponentSelectionScreen." % OPPONENT_SELECTION_SCENE)
		return false
	if hub_screen != null:
		hub_screen.visible = false
	_replace_hosted_screens()
	opponent_selection_screen = selection
	scene_host.add_child(selection)
	selection.set_player_portrait(PlayerAvatarStore.texture())
	selection.set_online_opponent_portrait(_opponent_avatar_texture)
	selection.opponent_selected.connect(_on_opponent_selected)
	selection.back_requested.connect(_on_opponent_selection_back)
	if matchmaking_client != null:
		matchmaking_client.set_credentials(String(user_state.get("token", "")), String(user_state.get("user", {}).get("id", "")))
		selection.attach_matchmaking(matchmaking_client)
	return true


func _on_opponent_selection_back() -> void:
	if online_client != null:
		online_client.stop()
	if matchmaking_client != null:
		matchmaking_client.leave()
	if is_instance_valid(opponent_selection_screen):
		var selection: OpponentSelectionScreen = opponent_selection_screen
		if selection.get_parent() == scene_host:
			scene_host.remove_child(selection)
		selection.queue_free()
		opponent_selection_screen = null
	show_hub()


func _on_opponent_selected(difficulty: int, rival_portrait: Texture2D) -> void:
	if opponent_selection_screen != null:
		var selection: OpponentSelectionScreen = opponent_selection_screen
		if selection.get_parent() == scene_host:
			scene_host.remove_child(selection)
		selection.queue_free()
		opponent_selection_screen = null
	_pending_local_match_id = "ai-%d-%d" % [
		Time.get_unix_time_from_system(), Time.get_ticks_usec()
	]
	_pending_local_save_path = GameSessionController.save_path_for_match(
		_pending_local_match_id
	)
	if not _boot_match(difficulty, rival_portrait):
		_pending_local_match_id = ""
		_pending_local_save_path = ""
		show_hub()


func _on_active_game_resume_requested(kind: String, id: String, path: String) -> void:
	if kind == "online":
		if online_client == null:
			hub_screen.show_notice("Online match is unavailable")
			return
		_open_online_when_received = true
		if not user_state.is_empty():
			online_client.set_credentials(
				String(user_state.get("token", "")),
				String(user_state.get("user", {}).get("id", ""))
			)
		online_client.start(id)
		return
	if path.is_empty():
		return
	_pending_local_match_id = id
	_pending_local_save_path = path
	boot_game_screen()


func _on_hub_profile_requested() -> void:
	if show_profile() and profile_screen != null:
		profile_screen.show_achievements_only(false)


func _on_hub_achievements_requested() -> void:
	if show_profile() and profile_screen != null:
		profile_screen.show_achievements_only(true)


func _on_clear_game_cache_requested() -> void:
	var had_game_cache: bool = (
		not GameSessionController.saved_match_entries().is_empty()
		or (game_sync_client != null and game_sync_client.has_cached_matches())
	)
	if game_sync_client != null:
		game_sync_client.clear_all_match_caches()
	GameSessionController.clear_all_saved_matches()
	if session_controller != null:
		return_to_hub()
	if hub_screen != null:
		_update_hub_play_label()
		_refresh_hub_active_games()
		hub_screen.show_notice("Game cache cleared" if had_game_cache else "No saved game to clear")


## Hosts the account profile and refreshes it through GET /auth/me.
func show_profile() -> bool:
	_bind_layers()
	if scene_host == null:
		return false
	if profile_screen != null and profile_screen.get_parent() == scene_host:
		profile_screen.visible = true
		_fetch_current_user()
		progression_client.fetch()
		achievement_client.fetch_catalog()
		if hub_screen != null:
			hub_screen.visible = false
		return true

	var packed: PackedScene = load(PROFILE_SCREEN_SCENE) as PackedScene
	if packed == null:
		push_error("AppRoot.show_profile: '%s' could not be loaded." % PROFILE_SCREEN_SCENE)
		return false
	var screen: ProfileScreen = packed.instantiate() as ProfileScreen
	if screen == null:
		push_error("AppRoot.show_profile: '%s' is not a ProfileScreen." % PROFILE_SCREEN_SCENE)
		return false
	profile_screen = screen
	profile_screen.set_user_state(user_state)
	_replace_hosted_screens()
	scene_host.add_child(profile_screen)
	profile_screen.set_user_state(user_state)
	profile_screen.refresh_requested.connect(_fetch_current_user)
	profile_screen.refresh_requested.connect(progression_client.fetch)
	profile_screen.profile_save_requested.connect(_save_profile)
	profile_screen.achievement_refresh_requested.connect(achievement_client.fetch_catalog)
	if hub_screen != null:
		hub_screen.visible = false
	profile_screen.back_requested.connect(_on_profile_back_requested)
	if achievement_client != null:
		achievement_client.fetch_catalog()
	_fetch_current_user()
	if not progression_client.current.is_empty():
		profile_screen.set_progression(progression_client.current)
	progression_client.fetch()
	return true


func _on_progression_received(data: Dictionary) -> void:
	if is_instance_valid(profile_screen):
		profile_screen.set_progression(data)


func _on_progression_failed(message: String) -> void:
	if is_instance_valid(profile_screen):
		profile_screen.set_progression_error(message)


func _on_profile_back_requested() -> void:
	if profile_screen != null:
		if profile_screen.get_parent() == scene_host:
			scene_host.remove_child(profile_screen)
		# Back is emitted by the screen; release it after signal dispatch.
		profile_screen.queue_free()
		profile_screen = null
	show_hub()


## Handles the game screen's request to leave the match.
func _on_hub_requested() -> void:
	return_to_hub()


## Returns from a match to the hub, releasing the match's services.
##
## The match is not frozen, it is released: the controller autosaves after every
## committed move and clears the record once the match is over, so a half-played
## match is picked up by the next Play and a finished one starts fresh. Releasing
## it is also how the shell forgets it - ADR-008 section 6 forbids keeping the
## session in a global, so nothing may outlive the nodes that hold it.
##
## Returns true when the hub is on screen.
func return_to_hub() -> bool:
	if online_client != null:
		online_client.stop()
	if matchmaking_client != null and matchmaking_client.state == "playing":
		matchmaking_client._finish_leave()
	_bind_layers()
	if scene_host == null:
		return false

	if game_screen != null:
		if game_screen.get_parent() == scene_host:
			scene_host.remove_child(game_screen)
		# Released at the end of the frame rather than immediately. `return_to_hub`
		# runs inside the press handler of a control this screen owns, and a node
		# held by an in-flight signal emission cannot be freed outright: freeing it
		# failed with "Attempted to free a locked object", which left the screen
		# alive but hosted nowhere. Detaching first keeps the swap synchronous for
		# every observer - the host is clear and the hub comes up in this same call
		# - and `queue_free` is what actually lets the nodes go once the emission
		# has unwound.
		game_screen.queue_free()
		game_screen = null
	if session_controller != null:
		# The app-scoped sync queue survives this match, but its controller must not.
		if is_instance_valid(game_sync_client):
			game_sync_client.attach_controller(null)
		# Its own `_exit_tree` cancels an analysis still in flight (ADR-005
		# section 9), so the rival cannot land a move after the player has left.
		session_controller.free()
		session_controller = null
	return show_hub()


## Creates the match services and shows the game screen instead of the hub.
##
## The hub is hidden rather than freed, so it survives the match and returning to
## it is instant.
func boot_game_screen() -> bool:
	var booted: bool = _boot_match()
	if booted and hub_screen != null:
		hub_screen.visible = false
	return booted


## The match half of `boot_game_screen`, with the hub already out of the way.
##
## `MATCH_SETUP` lives here: the controller is constructed, injected into the
## screen, and then asked to start. That ordering means the screen already
## renders authoritative state by the time the first turn opens, so no UI code
## has to cope with a half-built session.
func _boot_match(ai_difficulty: int = -1, rival_portrait: Texture2D = null) -> bool:
	_bind_layers()
	if scene_host == null:
		return false
	_ensure_feedback_adapter()
	_active_ai_rival_path = rival_portrait.resource_path if rival_portrait != null else ""
	# Booting twice would build a second match service and host a second screen,
	# stranding the first one's session. The splash hold calls this after a caller
	# may already have booted, so the guard is what makes both paths safe together.
	if game_screen != null:
		return true

	var packed: PackedScene = load(GAME_SCREEN_SCENE) as PackedScene
	if packed == null:
		push_error(
			"AppRoot.boot_game_screen: '%s' could not be loaded." % GAME_SCREEN_SCENE
		)
		return false

	var screen: GameScreen = packed.instantiate() as GameScreen
	if screen == null:
		push_error(
			"AppRoot.boot_game_screen: '%s' is not a GameScreen." % GAME_SCREEN_SCENE
		)
		return false

	session_controller = GameSessionController.new()
	var target_save_path: String = (
		_pending_local_save_path
		if not _pending_local_save_path.is_empty()
		else GameSessionController.SAVE_PATH
	)
	var target_match_id: String = _pending_local_match_id
	session_controller.save_path = target_save_path
	_pending_local_save_path = ""
	_pending_local_match_id = ""
	add_child(session_controller)
	if game_sync_client != null:
		game_sync_client.attach_controller(session_controller)

	game_screen = screen
	_replace_hosted_screens()
	# Added to the host first, so the screen's `_ready` runs before the
	# controller is attached and the first render reflects real state.
	scene_host.add_child(screen)
	screen.set_player_display_name(_player_display_name())
	screen.set_rival_portrait(rival_portrait)
	screen.set_player_portrait(PlayerAvatarStore.texture())

	# The way back to the hub. Reported by the screen and handled here, because
	# leaving a match means releasing match-scoped services (ADR-008 section 5);
	# the app-scoped feedback adapter remains cached. Connected exactly
	# once: the engine refuses a second connect of the same callable and reports
	# it as an error, and this one already carries the screen's request across.
	screen.hub_requested.connect(_on_hub_requested)

	_sync_feedback_settings()
	screen.attach_feedback_adapter(feedback_adapter)
	screen.attach_controller(session_controller)
	session_controller.rival_avatar_path = _active_ai_rival_path
	session_controller.score_awarded.connect(_on_score_events_for_achievements)
	session_controller.match_ended.connect(_on_match_result_for_achievements)

	# Milestone 7: a match that was interrupted is picked up where it left off.
	# The screen is attached first, so the resume outcome is reported through the
	# screen's own notice channel rather than to nobody. A save this build cannot
	# restore is refused by `resume_match`, which explains why and leaves the
	# record on disk; a fresh match then starts, so a bad save cannot strand the
	# player.
	if session_controller.resume_match():
		_active_ai_rival_path = session_controller.rival_avatar_path
		if not _active_ai_rival_path.is_empty():
			screen.set_rival_portrait(HubScreen._portrait_for(_active_ai_rival_path))
		return true
	session_controller.start_new_match(StringName(target_match_id), 0, ai_difficulty)
	return true


func _on_score_events_for_achievements(events: Array, _cell: Vector2i) -> void:
	if achievement_client == null:
		return
	var earned: Array[String] = []
	var progress: Array[Dictionary] = []
	var board: BoardState = session_controller.get_board() if session_controller != null else null
	var match_id: String = String(session_controller.get_match_id()) if session_controller != null else ""
	for event_variant: Variant in events:
		if not event_variant is ScoreEvent:
			continue
		var event: ScoreEvent = event_variant
		if event.player_id != TurnEnums.HUMAN_PLAYER_ID:
			continue
		if event.category == ScoringEnums.ScoreCategory.POKER_HAND:
			earned.append("first_hand")
			var hand: String = String(event.evidence.get("category", ""))
			if hand == "TWO_PAIR":
				progress.append({"eventId": "%s:%s" % [match_id, String(event.event_id)], "metric": "two_pair_scored"})
			if hand == "FULL_HOUSE" and PerfectMatchEvaluator.qualifies(board, event.cells):
				progress.append({"eventId": "%s:%s" % [match_id, String(event.event_id)], "metric": "perfect_match_scored"})
			if hand == "STRAIGHT_3" or hand == "STRAIGHT_4":
				earned.append("straight")
			if hand == "FULL_HOUSE":
				earned.append("full_house")
		elif event.category == ScoringEnums.ScoreCategory.EDGE_CLUSTER:
			earned.append("edge_cluster")
	if not earned.is_empty():
		var unique: Array[String] = []
		for achievement_id: String in earned:
			if not unique.has(achievement_id):
				unique.append(achievement_id)
		achievement_client.report_unlocks(unique)
	if not progress.is_empty():
		achievement_client.report_progress(progress)


func _on_match_result_for_achievements(result: MatchResult) -> void:
	if result != null and session_controller != null:
		MatchHistoryStore.add(_account_id(), String(session_controller.get_match_id()), "ai",
			"AI Rival", result.to_dictionary(), _active_ai_rival_path)
	if result != null and result.outcome == TurnEnums.MatchOutcome.HUMAN_WIN and achievement_client != null:
		achievement_client.report_unlocks(["ai_victory"])


## Removes whatever the host is currently showing, except the hub.
##
## The splash screen is authored into the scene (Milestone 0 bootstrap), so it is
## detached here rather than deleted from the scene file. The hub is skipped
## because it is the shell's home rather than a member of the match: it is hidden
## while a match runs and revealed again afterwards, so a screen arriving or
## leaving never destroys the player's place in it.
func _replace_hosted_screens() -> void:
	# Detach first, then free immediately, so the swap is synchronous: a caller
	# that inspects the host straight after boot sees the new screen rather than
	# a node waiting for the end of the frame. `queue_free` alone would leave the
	# old screen addressable as a child.
	for child: Node in scene_host.get_children():
		if child == hub_screen:
			continue
		scene_host.remove_child(child)
		child.free()


## Holds the authored splash for a short fixed beat, then runs `on_complete`.
##
## The hold is branding rather than a loading wait (see `SPLASH_HOLD_SECONDS`).
## It also hands over cleanly: the engine's own boot splash is set to the same
## background colour (`application/boot_splash/bg_color`), so the engine splash,
## this screen, and the first drawn frame of the next screen are one continuous
## colour rather than a flash between them.
##
## The handler is a parameter rather than a fixed call to the match boot, because
## the splash now hands over to the hub (owner direction, 2026-09-26) and a hold
## that still opened a match would skip the landing page entirely. The hub is
## what a player sees after the splash, so `_ready` passes `show_hub`.
##
## A `Timer` child rather than an awaited coroutine, so a tree torn down mid-hold
## - which the test harness does between cases - simply drops the timer instead
## of resuming into a freed node.
func _begin_splash_hold(on_complete: Callable) -> void:
	var timer: Timer = Timer.new()
	timer.name = "SplashHold"
	timer.one_shot = true
	timer.wait_time = SPLASH_HOLD_SECONDS
	add_child(timer)
	timer.timeout.connect(on_complete)
	timer.start()


func _on_delete_account_requested() -> void:
	if _account_delete_active:
		return
	_account_delete_active = true
	if _remote_account_deleted:
		_finish_account_cleanup()
		return
	if _account_deletion_client == null:
		_account_deletion_client = AccountDeletionClient.new()
		add_child(_account_deletion_client)
		_account_deletion_client.completed.connect(_on_account_deleted)
	_account_deletion_client.delete_account(String(user_state.get("token", "")), UsersStateStore.load_record())


func _on_account_deleted(success: bool, message: String) -> void:
	if not success:
		_account_delete_active = false
		hub_screen.show_deletion_result(false, message)
		return
	_remote_account_deleted = true
	_cleanup_account_id = String(user_state.get("user", {}).get("id", ""))
	_release_account_services()
	_finish_account_cleanup()


## Stop every account writer before clearing disk state or starting a new user.
func _release_account_services() -> void:
	_clear_opponent_avatar()
	_bind_layers()
	if online_client != null:
		online_client.free()
		online_client = null
	if matchmaking_client != null:
		matchmaking_client.free()
		matchmaking_client = null
	# Free transports and their requests before erasing files: late replies must
	# never recreate credentials, unlock queues or a game-sync cache.
	if game_sync_client != null:
		game_sync_client.attach_controller(null)
		game_sync_client.free()
		game_sync_client = null
	if achievement_client != null:
		achievement_client.free()
		achievement_client = null
	if progression_client != null:
		progression_client.free()
		progression_client = null
	_last_progression_match_id = ""
	for child: Node in get_children():
		if child is HTTPRequest:
			child.cancel_request()
			child.queue_free()
	_login_active = false
	_profile_request_active = false
	if session_controller != null:
		session_controller.free()
		session_controller = null
	_replace_hosted_screens()
	game_screen = null
	profile_screen = null
	opponent_selection_screen = null
	user_state.clear()


func _finish_account_cleanup() -> void:
	_account_delete_active = false
	if not UsersStateStore.clear_local_state(users_path.get_base_dir(), _cleanup_account_id):
		hub_screen.show_deletion_result(false, "The server account was deleted, but some data could not be removed from this device. Retry local cleanup.", true)
		return
	_reset_account_preferences()
	_update_hub_play_label()
	hub_screen.show_deletion_result(true, "Account deleted successfully. Your account details and saved state have been removed.", true)


func _reset_account_preferences() -> void:
	ApiConfiguration.reset_runtime()
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, false)
	ProjectSettings.set_setting(FeedbackAdapter.SETTING_PATH, true)
	ProjectSettings.set_setting(FeedbackAdapter.AUDIO_SETTING_PATH, true)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), false)
	if feedback_adapter != null:
		feedback_adapter.set_haptics_enabled(true)
		feedback_adapter.set_audio_enabled(true)


func _sync_feedback_settings() -> void:
	if feedback_adapter == null:
		return
	feedback_adapter.set_haptics_enabled(
		bool(ProjectSettings.get_setting(FeedbackAdapter.SETTING_PATH, true))
	)
	feedback_adapter.set_audio_enabled(
		bool(ProjectSettings.get_setting(FeedbackAdapter.AUDIO_SETTING_PATH, true))
	)


func _on_account_deletion_acknowledged() -> void:
	# Reload the shell to discard every in-memory view and start at account setup.
	get_tree().reload_current_scene()


func _on_hub_online_requested() -> void:
	if show_opponent_selection():
		opponent_selection_screen.select_online()
		if online_client != null:
			online_client.set_credentials(String(user_state.get("token", "")), String(user_state.get("user", {}).get("id", "")))
			_open_online_when_received = true
			online_client.recover()


func _clear_opponent_avatar() -> void:
	if _opponent_avatar_request != null:
		_opponent_avatar_request.cancel_request()
		_opponent_avatar_request.queue_free()
		_opponent_avatar_request = null
	_opponent_avatar_id = ""
	_opponent_avatar_texture = null
	if is_instance_valid(opponent_selection_screen):
		opponent_selection_screen.set_online_opponent_portrait(null)


func _online_avatar_path(opponent_id: String) -> String:
	if opponent_id.is_empty() or _account_id().is_empty():
		return ""
	return "user://history_avatar_%s_%s.png" % [_account_id().sha256_text(), opponent_id.sha256_text()]


func _fetch_opponent_avatar(opponent_id: String) -> void:
	var token: String = String(user_state.get("token", ""))
	if opponent_id.is_empty() or token.is_empty():
		return
	if opponent_id == _opponent_avatar_id:
		return
	_clear_opponent_avatar()
	_opponent_avatar_id = opponent_id
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	_opponent_avatar_request = request
	request.request_completed.connect(_on_opponent_avatar_received.bind(request, opponent_id, token))
	var error: Error = request.request(
		ApiConfiguration.api_base_url() + "/auth/opponents/%s/avatar" % opponent_id,
		PackedStringArray(["Authorization: Bearer %s" % token])
	)
	if error != OK:
		request.queue_free()
		_opponent_avatar_request = null


func _on_opponent_avatar_received(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, request: HTTPRequest, opponent_id: String, token: String) -> void:
	request.queue_free()
	if _opponent_avatar_request == request:
		_opponent_avatar_request = null
	if (opponent_id != _opponent_avatar_id or token != String(user_state.get("token", ""))
			or result != HTTPRequest.RESULT_SUCCESS or code != 200
			or body.is_empty() or body.size() > PlayerAvatarStore.MAX_BYTES):
		return
	var image := Image.new()
	if image.load_png_from_buffer(body) != OK or image.get_size() != Vector2i(PlayerAvatarStore.SIZE, PlayerAvatarStore.SIZE):
		return
	_opponent_avatar_texture = ImageTexture.create_from_image(image)
	if not _opponent_avatar_id.is_empty():
		image.save_png(ProjectSettings.globalize_path(_online_avatar_path(_opponent_avatar_id)))
	if is_instance_valid(opponent_selection_screen):
		opponent_selection_screen.set_online_opponent_portrait(_opponent_avatar_texture)
	if is_instance_valid(game_screen) and session_controller is OnlineGameController:
		game_screen.set_rival_portrait(_opponent_avatar_texture)
	if is_instance_valid(hub_screen) and hub_screen.visible:
		_refresh_hub_active_games()
		_refresh_hub_recent_match()


func _on_online_lobby_changed(state: String, _message: String, lobby: Dictionary) -> void:
	if state in ["matched", "playing"]:
		var opponent: Dictionary = lobby.get("opponent", {})
		var opponent_id: Variant = opponent.get("id", "")
		_fetch_opponent_avatar(str(opponent_id) if opponent_id is String else "")
	elif state in ["idle", "searching", "failed", "leaving"]:
		_clear_opponent_avatar()
	if state == "playing" and online_client != null:
		online_client.set_credentials(String(user_state.get("token", "")), String(user_state.get("user", {}).get("id", "")))
		_open_online_when_received = true
		online_client.start(String(lobby.get("matchId", "")))


func _on_online_received(data: Dictionary) -> void:
	var opponent: Dictionary = data.get("opponent", {})
	var opponent_id: Variant = opponent.get("id", "")
	_fetch_opponent_avatar(str(opponent_id) if opponent_id is String else "")
	if String(data.get("status", "")) == "completed":
		var match_id: String = String(data.get("matchId", ""))
		var view: OnlineSessionView = OnlineSessionView.from_response(data)
		if view != null:
			MatchHistoryStore.add(_account_id(), match_id, "online",
				String(opponent.get("displayName", "Rival")), MatchResult.build(view).to_dictionary(),
				_online_avatar_path(String(opponent.get("id", ""))))
		if not match_id.is_empty() and match_id != _last_progression_match_id:
			_last_progression_match_id = match_id
			if progression_client != null:
				progression_client.fetch()
	if session_controller is OnlineGameController or game_screen != null:
		return
	_refresh_hub_active_games()
	_refresh_hub_recent_match()
	if not _open_online_when_received:
		return
	_open_online_when_received = false
	_boot_online_match.call_deferred(data)


func _boot_online_match(data: Dictionary) -> void:
	if game_screen != null or online_client == null:
		return
	_ensure_feedback_adapter()
	if not online_client._wanted and String(data.get("status")) != "completed":
		return
	if hub_screen != null:
		hub_screen.visible = false
	_replace_hosted_screens()
	opponent_selection_screen = null
	var controller: OnlineGameController = OnlineGameController.new()
	session_controller = controller
	add_child(controller)
	var screen: GameScreen = (load(GAME_SCREEN_SCENE) as PackedScene).instantiate()
	game_screen = screen
	scene_host.add_child(screen)
	screen.set_player_display_name(_player_display_name())
	screen.hub_requested.connect(_on_hub_requested)
	screen.set_player_portrait(PlayerAvatarStore.texture())
	if _opponent_avatar_texture != null:
		screen.set_rival_portrait(_opponent_avatar_texture)
	_sync_feedback_settings()
	screen.attach_feedback_adapter(feedback_adapter)
	screen.attach_controller(controller)
	controller.attach_client(online_client)
