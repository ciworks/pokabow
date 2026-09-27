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

## The platform feedback service (ADR-008 section 5; Milestone 8). Owned here and
## injected into the screen, so haptics and audio are composed in one place and
## the screen holds no platform call of its own.
var feedback_adapter: FeedbackAdapter = null

## Terms gate. Null once the player has accepted, or when the local state file
## already records an accepted account.
var terms_dialog: TermsOfUseDialog = null


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
	_begin_splash_hold(_after_splash)


## Splash hands over to the terms gate, or straight to the hub when this device
## already has an accepted account. A returning account is logged in before the
## hub appears; a failed login still opens the hub and is reported on the dialog
## only when the player has not accepted yet.
func _after_splash() -> void:
	if UsersStateStore.has_accepted_account():
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


func _on_terms_accepted(record: Dictionary) -> void:
	if terms_dialog != null and is_instance_valid(terms_dialog):
		terms_dialog.queue_free()
		terms_dialog = null
	print("[AppRoot] terms accepted for %s" % String(record.get("username", "")))
	show_hub()


## Posts the saved credentials to the login endpoint. Does not block the hub:
## a local server that is down must not trap a player who already accepted.
func _login_returning_account(record: Dictionary) -> void:
	var client := HTTPRequest.new()
	client.name = "ReturningLogin"
	add_child(client)
	client.request_completed.connect(_on_returning_login_completed.bind(client))
	var body := JSON.stringify({
		"username": String(record.get(UsersStateStore.KEY_USERNAME, "")),
		"email": String(record.get(UsersStateStore.KEY_EMAIL, "")),
		"password": String(record.get(UsersStateStore.KEY_PASSWORD, "")),
	})
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json"])
	var err: int = client.request(TermsOfUseDialog.LOGIN_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
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
	if is_instance_valid(client):
		client.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		push_warning(
			"AppRoot: returning login failed (result %s, HTTP %s)."
			% [result, response_code]
		)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var user: Dictionary = {}
	if typeof(parsed) == TYPE_DICTIONARY:
		var payload: Dictionary = parsed
		var nested: Variant = payload.get("user", payload)
		if typeof(nested) == TYPE_DICTIONARY:
			user = nested
	if user.is_empty():
		return
	var record: Dictionary = UsersStateStore.load_record()
	record["last_login_user"] = user
	UsersStateStore.save_record(record)


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
		hub_screen.visible = true
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
	return true


## Handles the hub's Play request.
func _on_hub_play_requested() -> void:
	boot_game_screen()


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
		game_screen.free()
		game_screen = null
	if session_controller != null:
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
func _boot_match() -> bool:
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

	game_screen = screen
	_replace_hosted_screens()
	# Added to the host first, so the screen's `_ready` runs before the
	# controller is attached and the first render reflects real state.
	scene_host.add_child(screen)

	# The screen reports the wish to leave; the shell performs it (ADR-008
	# section 5), so only this node releases the match services.
	screen.hub_requested.connect(_on_hub_requested)

	screen.attach_controller(session_controller)

	# Milestone 8: the platform feedback service, created alongside the match
	# service and injected (ADR-008 section 5). The screen cues it at the moment
	# a human gesture resolved, so the rival's move never buzzes the player's
	# phone and a headless screen simply has no adapter to cue.
	feedback_adapter = FeedbackAdapter.new()
	add_child(feedback_adapter)
	screen.attach_feedback_adapter(feedback_adapter)

	# The way back to the hub. Reported by the screen and handled here, because
	# leaving a match means releasing the services this node owns (ADR-008
	# section 5); the screen holds no reference to the shell.
	screen.hub_requested.connect(_on_hub_requested)

	# Milestone 7: a match that was interrupted is picked up where it left off.
	# The screen is attached first, so the resume outcome is reported through the
	# screen's own notice channel rather than to nobody. A save this build cannot
	# restore is refused by `resume_match`, which explains why and leaves the
	# record on disk; a fresh match then starts, so a bad save cannot strand the
	# player.
	if session_controller.resume_match():
		return true
	session_controller.start_new_match()
	return true


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
