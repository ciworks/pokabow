extends SceneTree
## Pixel-bound regression check for player deal backs, using the actual renderer.
class Face extends Control:
	var tile: TileDefinition
	var bounds := Rect2(16, 16, 128, 128)
	func _draw() -> void:
		TilePainter.paint_tile(self, bounds, TileSnapshot.create(tile, BoardMetrics.NO_CELL, 0))

var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error(message)

func render(view: SubViewport, name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = view.get_texture().get_image()
	var directory: String = OS.get_environment("DEAL_QA_DIR")
	if not directory.is_empty():
		image.save_png(directory.path_join(name + ".png"))
	return image

func opaque_bounds(image: Image) -> Rect2i:
	var low := Vector2i(image.get_width(), image.get_height())
	var high := Vector2i(-1, -1)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a >= 0.5:
				low.x = mini(low.x, x)
				low.y = mini(low.y, y)
				high.x = maxi(high.x, x)
				high.y = maxi(high.y, y)
	return Rect2i(low, high - low + Vector2i.ONE)

func _run() -> void:
	var suite: TestCase = load("res://tests/integration/test_game_screen.gd").new()
	suite.test_deal_tracks_live_pot_and_rack_geometry_without_restarting()
	suite.test_tile_flip_depth_peaks_at_twenty_percent_of_tile_width()
	assertions += suite.assertions
	failures += suite.failures.size()
	for message: String in suite.failures:
		push_error(message)
	var tile: TileDefinition = TileDefinition.create(&"qa-back", TileEnums.TileRank.ACE, TileEnums.FaceColor.BLACK,
		[TileEnums.EdgeColor.BLUE, TileEnums.EdgeColor.RED, TileEnums.EdgeColor.GREEN, TileEnums.EdgeColor.YELLOW], TileEnums.Suit.SPADES)
	var view := SubViewport.new()
	view.size = Vector2i(160, 160)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var layer := DealLayer.new()
	view.add_child(layer)
	var target := Rect2(16, 16, 128, 128)
	layer.deal([tile], func() -> Vector2: return Vector2(80, 80), [func() -> Rect2: return target])
	layer.set_process(false)
	layer._elapsed = DealLayer.FLIGHT + DealLayer.HOLD * 0.5
	layer.queue_redraw()
	var held: Image = await render(view, "back-held")
	var held_bounds: Rect2i = opaque_bounds(held)
	check(Rect2i(target).encloses(held.get_used_rect()), "No extra outline is drawn outside the tile")
	layer._elapsed = DealLayer.FLIGHT + DealLayer.HOLD + layer.flip_duration * 0.25
	layer.queue_redraw()
	var turning: Image = await render(view, "back-half-width")
	var turning_bounds: Rect2i = opaque_bounds(turning)
	check(absi(turning_bounds.size.y - held_bounds.size.y) <= 1, "Turning back preserves height")
	check(absi(turning_bounds.size.x * 2 - held_bounds.size.x) <= 2, "Turning back compresses the complete artwork")
	layer._elapsed = DealLayer.FLIGHT + DealLayer.HOLD + layer.flip_duration * 0.99
	layer.queue_redraw()
	var revealed: Image = await render(view, "face-end-of-turn")
	layer.hide()
	var face := Face.new()
	face.tile = tile
	view.add_child(face)
	var resting: Image = await render(view, "face-resting")
	var face_bounds: Rect2i = opaque_bounds(resting)
	print("[tile bounds] back=%s face=%s" % [held_bounds, face_bounds])
	check(absi(held_bounds.size.x - face_bounds.size.x) <= 2, "Back and resting face have matching visible widths")
	check(absi(held_bounds.size.y - face_bounds.size.y) <= 2, "Back and resting face have matching visible heights")
	check(held_bounds.position.distance_to(face_bounds.position) <= 2, "Back and face align at the same origin")
	check(absi(opaque_bounds(revealed).size.x - face_bounds.size.x) <= 3, "Reveal reaches the resting face width without a size jump")
	# The bottom lip belongs to the supplied base, below the face/edge overlays.
	# Check its actual rendered pixels at rack, board and enlarged preview sizes.
	var supplied_base: Image = load("res://assets/tiles/tile_base.png").get_image()
	var lip_color: Color = supplied_base.get_pixel(100, 194)
	for side: int in [32, 48, 64, 128]:
		face.bounds = Rect2(16, 16, side, side)
		face.queue_redraw()
		var complete: Image = await render(view, "base-lip-%d" % side)
		var lip: Color = complete.get_pixel(16 + side / 2, 16 + side - 2)
		check(lip.a > 0.95, "Base bottom lip remains opaque at %dpx" % side)
		check(Vector3(lip.r, lip.g, lip.b).distance_to(Vector3(lip_color.r, lip_color.g, lip_color.b)) < 0.12,
			"Supplied base bottom lip remains visible at %dpx" % side)
	view.queue_free()
	await process_frame
	print("[deal back QA] %d assertions, %d failures" % [assertions, failures])
	quit.call_deferred(0 if failures == 0 else 1)

