class_name AppRoot
extends Node
## Application composition root (ADR-008 sections 4 and 5).
##
## Milestone 0 scope: own the persistent layer structure and verify the
## bootstrap chain (project -> AppRoot -> SceneHost -> splash screen) loads.
##
## Autoload policy: this node is NOT an autoload and owns no active match
## state. ADR-008 section 6 forbids storing the game session, score ledger,
## board state, AI, or turn manager in a global. Per-match services are
## constructed by this node and released when the match ends, which begins in
## Milestone 4.
##
## Layer dependency direction: Presentation -> Application -> Domain
## (ADR-008 section 1). This script must not contain game rules, placement
## legality, or scoring.

const SCENE_HOST_PATH: NodePath = ^"SceneHost"
const OVERLAY_LAYER_PATH: NodePath = ^"OverlayLayer"
const ACCESSIBILITY_LAYER_PATH: NodePath = ^"AccessibilityLayer"

## Host for the active screen. Holds the splash screen and, from Milestone 5,
## the game screen. Screens are swapped inside this node.
var scene_host: Node = null

## Drawn above gameplay for transitions and error dialogs.
var overlay_layer: CanvasLayer = null

## Reserved for accessibility presentation that must sit above all other UI.
var accessibility_layer: CanvasLayer = null


func _ready() -> void:
	scene_host = get_node_or_null(SCENE_HOST_PATH)
	overlay_layer = get_node_or_null(OVERLAY_LAYER_PATH) as CanvasLayer
	accessibility_layer = get_node_or_null(ACCESSIBILITY_LAYER_PATH) as CanvasLayer

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
