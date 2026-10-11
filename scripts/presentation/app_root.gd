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

## How long the authored splash is held before the match boots, in seconds.
##
## Long enough to read the title, short enough not to feel like a wait. The hold
## is the whole of the splash's life: booting a match is synchronous and fast, so
## without a deliberate beat here the composition root would replace the splash in
## the same frame it appeared and no player would ever see it.
const SPLASH_HOLD_SECONDS: float = 1.2

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

## The active playable screen, or null while the hub is the visible screen.
var game_screen: GameScreen = null

## The short-lived selection screen shown before a new match.
var opponent_selection_screen: OpponentSelectionScreen = null

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

## Authenticated match creation and turn synchronization transport.
var game_sync_client: GameSyncApiClient = null
var _login_active: bool = false
var _profile_request_active: bool = false


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

	print("[AppRoot] bootstrap ready (screens hosted: %d)" % scene_host.get_child_count())
	achievement_client = AchievementApiClient.new()
	add_child(achievement_client)
	achievement_client.newly_unlocked.connect(_on_achievements_unlocked)
	achievement_client.catalog_received.connect(_on_achievement_catalog_received)
	game_sync_client = GameSyncApiClient.new()
	add_child(game_sync_client)
	game_sync_client.authentication_required.connect(_refresh_api_login)
	game_sync_client.sync_notice.connect(_on_sync_notice)
	game_sync_client.score_preview_received.connect(_on_api_score_preview)
	achievement_client.authentication_required.connect(_refresh_api_login)
	_begin_splash_hold(_after_splash)


## Splash hands over to the terms gate, or straight to the hub when this device
## already has an accepted account. Restore its saved user state, or request a
## fresh login when that state is missing.
func _after_splash() -> void:
	if UsersStateStore.has_accepted_account():
		user_state = UsersStateStore.load_user_state()
		achievement_client.set_access_token(String(user_state.get("token", "")))
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
	game_sync_client.set_access_token(String(user_state.get("token", "")))
	show_hub()
	achievement_client.fetch_catalog()


func _on_achievements_unlocked(ids: Array) -> void:
	var names: PackedStringArray = PackedStringArray()
	for achievement_id: Variant in ids:
		names.append(String(achievement_id).replace("_", " ").capitalize())
	if not names.is_empty() and game_screen != null:
		if session_controller != null:
			session_controller.notice.emit("Achievement unlocked: %s" % ", ".join(names))


func _on_achievement_catalog_received(rows: Array) -> void:
	if profile_screen != null and is_instance_valid(profile_screen):
		profile_screen.set_achievement_rows(rows)


## Posts the saved credentials to the login endpoint. Does not block the hub:
## a local server that is down must not trap a player who already accepted.
func _login_returning_account(record: Dictionary) -> void:
	if _login_active:
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
	var err: int = client.request(ApiConfiguration.login_url(), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_login_active = false
		push_warning("AppRoot: returning login could not start (%s)." % error_string(err))
		client.queue_free()
		return
	# The request is fire-and-observe. The hub is already the next screen.


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
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning(
			"AppRoot: returning login failed (result %s, HTTP %s)."
			% [result, response_code]
		)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("AppRoot: returning login returned invalid JSON.")
		return
	var response: Dictionary = parsed
	if not UsersStateStore.save_user_state(response):
		push_warning("AppRoot: returning login had no token or could not be saved.")
		return
	user_state = UsersStateStore.load_user_state()
	if achievement_client != null:
		achievement_client.set_access_token(String(user_state.get("token", "")))
	if game_sync_client != null:
		game_sync_client.set_access_token(String(user_state.get("token", "")))
	if game_screen != null:
		game_screen.set_player_display_name(_player_display_name())
	if profile_screen != null and is_instance_valid(profile_screen):
		_fetch_current_user()
		achievement_client.fetch_catalog()


func _refresh_api_login() -> void:
	_login_returning_account(UsersStateStore.load_record())


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
	if token != String(user_state.get("token", "")):
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
	hub.profile_requested.connect(_on_hub_profile_requested)
	hub.achievements_requested.connect(_on_hub_achievements_requested)
	hub.clear_game_cache_requested.connect(_on_clear_game_cache_requested)
	_update_hub_play_label()
	return true


func _update_hub_play_label() -> void:
	if hub_screen == null or not is_instance_valid(hub_screen):
		return
	var label: String = (
		HubScreen.PLAY_LABEL_RESUME
		if FileAccess.file_exists(GameSessionController.SAVE_PATH)
		else HubScreen.PLAY_LABEL_NEW_GAME
	)
	hub_screen.set_play_button_label(label)


## Handles the hub's Play request.
func _on_hub_play_requested() -> void:
	if FileAccess.file_exists(GameSessionController.SAVE_PATH):
		boot_game_screen()
	else:
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
	selection.opponent_selected.connect(_on_opponent_selected)
	return true


func _on_opponent_selected(difficulty: int, rival_portrait: Texture2D) -> void:
	if opponent_selection_screen != null:
		var selection: OpponentSelectionScreen = opponent_selection_screen
		if selection.get_parent() == scene_host:
			scene_host.remove_child(selection)
		selection.queue_free()
		opponent_selection_screen = null
	if not _boot_match(difficulty, rival_portrait):
		show_hub()


func _on_hub_profile_requested() -> void:
	if show_profile() and profile_screen != null:
		profile_screen.show_achievements_only(false)


func _on_hub_achievements_requested() -> void:
	if show_profile() and profile_screen != null:
		profile_screen.show_achievements_only(true)


func _on_clear_game_cache_requested() -> void:
	var match_id: String = _saved_match_id()
	if match_id.is_empty() and game_sync_client != null:
		match_id = game_sync_client.current_match_id()
	var had_game_cache: bool = (
		FileAccess.file_exists(GameSessionController.SAVE_PATH) or not match_id.is_empty()
	)
	if game_sync_client != null and not match_id.is_empty():
		game_sync_client.clear_match_cache(match_id)
	var had_save: bool = FileAccess.file_exists(GameSessionController.SAVE_PATH)
	if had_save:
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(GameSessionController.SAVE_PATH)
		)
	if session_controller != null:
		return_to_hub()
	if hub_screen != null:
		_update_hub_play_label()
		hub_screen.show_notice("Game cache cleared" if had_game_cache else "No saved game to clear")


## Reads the local match identity from the autosave so its remote sync record can
## be removed even when no match controller is currently attached.
func _saved_match_id() -> String:
	if not FileAccess.file_exists(GameSessionController.SAVE_PATH):
		return ""
	var file: FileAccess = FileAccess.open(GameSessionController.SAVE_PATH, FileAccess.READ)
	if file == null:
		return ""
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return ""
	var match_variant: Variant = (parsed as Dictionary).get("match", {})
	if not match_variant is Dictionary:
		return ""
	return String((match_variant as Dictionary).get("match_id", ""))


## Hosts the account profile and refreshes it through GET /auth/me.
func show_profile() -> bool:
	_bind_layers()
	if scene_host == null:
		return false
	if profile_screen != null and profile_screen.get_parent() == scene_host:
		profile_screen.visible = true
		_fetch_current_user()
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
	if hub_screen != null:
		hub_screen.visible = false
	profile_screen.back_requested.connect(_on_profile_back_requested)
	if achievement_client != null:
		achievement_client.fetch_catalog()
	_fetch_current_user()
	return true


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
	if feedback_adapter != null:
		feedback_adapter.free()
		feedback_adapter = null
	return show_hub()


## Creates the match services and shows the game screen instead of the hub.
##
## The hub is hidden rather than freed, so it survives the match and returning to
## it is instant.
func boot_game_screen() -> bool:
	if hub_screen != null:
		hub_screen.visible = false
	return _boot_match()


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

	# The way back to the hub. Reported by the screen and handled here, because
	# leaving a match means releasing the services this node owns (ADR-008
	# section 5); the screen holds no reference to the shell. Connected exactly
	# once: the engine refuses a second connect of the same callable and reports
	# it as an error, and this one already carries the screen's request across.
	screen.hub_requested.connect(_on_hub_requested)

	screen.attach_controller(session_controller)
	session_controller.score_awarded.connect(_on_score_events_for_achievements)
	session_controller.match_ended.connect(_on_match_result_for_achievements)

	# Milestone 8: the platform feedback service, created alongside the match
	# service and injected (ADR-008 section 5). The screen cues it at the moment
	# a human gesture resolved, so the rival's move never buzzes the player's
	# phone and a headless screen simply has no adapter to cue.
	feedback_adapter = FeedbackAdapter.new()
	add_child(feedback_adapter)
	screen.attach_feedback_adapter(feedback_adapter)

	# Milestone 7: a match that was interrupted is picked up where it left off.
	# The screen is attached first, so the resume outcome is reported through the
	# screen's own notice channel rather than to nobody. A save this build cannot
	# restore is refused by `resume_match`, which explains why and leaves the
	# record on disk; a fresh match then starts, so a bad save cannot strand the
	# player.
	if session_controller.resume_match():
		return true
	session_controller.start_new_match(&"", 0, ai_difficulty)
	return true


func _on_score_events_for_achievements(events: Array, _cell: Vector2i) -> void:
	if achievement_client == null:
		return
	var earned: Array[String] = []
	for event_variant: Variant in events:
		if not event_variant is ScoreEvent:
			continue
		var event: ScoreEvent = event_variant
		if event.player_id != TurnEnums.HUMAN_PLAYER_ID:
			continue
		if event.category == ScoringEnums.ScoreCategory.POKER_HAND:
			earned.append("first_hand")
			var hand: String = String(event.evidence.get("category", ""))
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


func _on_match_result_for_achievements(result: MatchResult) -> void:
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
