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

## The playable screen, loaded once the splash has served its purpose.
const GAME_SCREEN_SCENE: String = "res://scenes/game/game_screen.tscn"

## Host for the active screen. Screens are swapped inside this node.
var scene_host: Node = null

## Drawn above gameplay for transitions and error dialogs.
var overlay_layer: CanvasLayer = null

## Reserved for accessibility presentation that must sit above all other UI.
var accessibility_layer: CanvasLayer = null

## The application-level match service, created here and owned by the session.
var session_controller: GameSessionController = null

## The active playable screen, or null before the match boot completes.
var game_screen: GameScreen = null


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
	boot_game_screen()


## Creates the match services and swaps the splash screen for the game screen.
##
## `MATCH_SETUP` lives here: the controller is constructed, injected into the
## screen, and then asked to start. That ordering means the screen already
## renders authoritative state by the time the first turn opens, so no UI code
## has to cope with a half-built session.
func boot_game_screen() -> bool:
	_bind_layers()
	if scene_host == null:
		return false

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

	screen.attach_controller(session_controller)
	session_controller.start_new_match()
	return true


## Removes whatever the host is currently showing.
##
## The splash screen is authored into the scene (Milestone 0 bootstrap), so it is
## detached here rather than deleted from the scene file.
func _replace_hosted_screens() -> void:
	# Detach first, then free immediately, so the swap is synchronous: a caller
	# that inspects the host straight after boot sees the new screen rather than
	# a node waiting for the end of the frame. `queue_free` alone would leave the
	# old screen addressable as a child.
	for child: Node in scene_host.get_children():
		scene_host.remove_child(child)
		child.free()
