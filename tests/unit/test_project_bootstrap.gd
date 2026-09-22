extends TestCase

## Milestone 0 bootstrap smoke test.
##
## Verifies that the repository scaffold matches its authoritative documents:
## project settings (landscape 1280x720, GL Compatibility renderer), the AppRoot
## composition root as the entry scene, the ADR-008 section 4 scene layers, the
## ADR-008 section 2 directory layout, and the ADR-008 section 6 autoload policy.
##
## This test covers project structure and bootstrap wiring only. No milestone 1+
## gameplay rules exist yet, so nothing here evaluates rules.

const MAIN_SCENE_PATH: String = "res://scenes/app/app_root.tscn"
const SPLASH_SCENE_PATH: String = "res://scenes/splash/splash_screen.tscn"

const REQUIRED_DIRECTORIES: PackedStringArray = [
	"res://assets/audio",
	"res://assets/fonts",
	"res://assets/textures",
	"res://resources/rules",
	"res://resources/themes",
	"res://scenes/app",
	"res://scenes/splash",
	"res://scenes/game",
	"res://scenes/components",
	"res://scenes/debug",
	"res://scripts/domain/tile",
	"res://scripts/domain/board",
	"res://scripts/domain/placement",
	"res://scripts/domain/scoring",
	"res://scripts/domain/turn",
	"res://scripts/domain/ai",
	"res://scripts/application",
	"res://scripts/infrastructure",
	"res://scripts/presentation",
	"res://tests/unit",
	"res://tests/integration",
	"res://tests/fixtures",
]

const LANDSCAPE_ORIENTATIONS: PackedStringArray = [
	"landscape",
	"reverse_landscape",
	"sensor_landscape",
]


func test_main_scene_is_the_app_root() -> void:
	var main_scene: String = String(ProjectSettings.get_setting("application/run/main_scene", ""))
	check_eq(main_scene, MAIN_SCENE_PATH, "application/run/main_scene must point at the AppRoot composition root")
	check(ResourceLoader.exists(MAIN_SCENE_PATH), "the AppRoot scene file must exist on disk")


func test_viewport_is_landscape_1280x720() -> void:
	var width: int = int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var height: int = int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	check_eq(width, 1280, "viewport width must be 1280")
	check_eq(height, 720, "viewport height must be 720")
	check(width > height, "viewport must be landscape (width greater than height)")

	var orientation: String = String(ProjectSettings.get_setting("display/window/handheld/orientation", ""))
	check(
		LANDSCAPE_ORIENTATIONS.has(orientation),
		"display/window/handheld/orientation must allow landscape, got '%s'" % orientation
	)


func test_renderer_is_gl_compatibility() -> void:
	check_eq(
		String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"gl_compatibility",
		"the mobile-first renderer must be GL Compatibility"
	)


func test_stretch_mode_is_canvas_items() -> void:
	check_eq(
		String(ProjectSettings.get_setting("display/window/stretch/mode", "")),
		"canvas_items",
		"stretch mode must keep UI crisp on varied mobile resolutions"
	)


func test_no_autoload_holds_match_state() -> void:
	var autoloads: PackedStringArray = PackedStringArray()
	for property: Dictionary in ProjectSettings.get_property_list():
		var property_name: String = String(property.get("name", ""))
		if property_name.begins_with("autoload/"):
			autoloads.append(property_name)
	check_eq(
		autoloads.size(),
		0,
		"no autoload may be registered in Milestone 0; ADR-008 section 6 forbids active match state in a global (found: %s)" % ", ".join(autoloads)
	)


func test_app_root_scene_has_required_layers() -> void:
	var packed: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if not check_not_null(packed, "the AppRoot scene must load as a PackedScene"):
		return
	var app_root: Node = packed.instantiate()
	if not check_not_null(app_root, "the AppRoot scene must instantiate"):
		return

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(app_root)

	check_not_null(app_root.get_node_or_null("SceneHost"), "ADR-008 section 4 requires a SceneHost node")
	check_not_null(
		app_root.get_node_or_null("SceneHost/SplashScreen"),
		"SceneHost must host the splash screen for Milestone 0"
	)
	check_not_null(app_root.get_node_or_null("OverlayLayer"), "ADR-008 section 4 requires an OverlayLayer node")
	check_not_null(
		app_root.get_node_or_null("AccessibilityLayer"),
		"ADR-008 section 4 requires an AccessibilityLayer node"
	)

	app_root.free()


func test_splash_scene_is_a_landscape_control_with_a_title() -> void:
	var packed: PackedScene = load(SPLASH_SCENE_PATH) as PackedScene
	if not check_not_null(packed, "the splash scene must load as a PackedScene"):
		return
	var splash: Node = packed.instantiate()
	if not check_not_null(splash, "the splash scene must instantiate"):
		return
	if not check(splash is Control, "the splash scene root must be a Control so it fills the viewport"):
		splash.free()
		return

	var title: Label = _first_label_with_text(splash)
	check_not_null(title, "the splash screen must display a non-empty title label")

	splash.free()


func test_directory_layout_matches_adr_008() -> void:
	for directory: String in REQUIRED_DIRECTORIES:
		check_not_null(DirAccess.open(directory), "ADR-008 section 2 requires the directory %s" % directory)


func _first_label_with_text(node: Node) -> Label:
	if node is Label and not (node as Label).text.is_empty():
		return node as Label
	for child: Node in node.get_children():
		var found: Label = _first_label_with_text(child)
		if found != null:
			return found
	return null
