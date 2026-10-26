extends SceneTree
## One-time extraction of unchanged tile pixels from the approved hero artwork.

const SOURCE := "res://assets/hub/modern-tabletop-hero-cartoon-v2.png"
const BACKING := "res://assets/hub/modern-tabletop-hero-tileless-backing.png"
const OUTPUT := "res://assets/hub/animated"


func _initialize() -> void:
	var original: Image = load(SOURCE).get_image()
	var backing: Image = load(BACKING).get_image()
	if original.get_size() != backing.get_size():
		push_error("Hub hero and tile-free backing dimensions differ")
		quit(1)
		return
	var plate: Image = original.duplicate()
	var tiles: Array[Dictionary] = _tile_shapes()
	var king_polygon: PackedVector2Array = tiles[2]["polygon"]
	var king_face: PackedVector2Array = tiles[2]["face"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for entry: Dictionary in tiles:
		var bounds: Rect2i = entry["bounds"]
		var polygon: PackedVector2Array = entry["polygon"]
		var cutout := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
		cutout.fill(Color.TRANSPARENT)
		for y: int in range(bounds.position.y, bounds.end.y):
			for x: int in range(bounds.position.x, bounds.end.x):
				var point := Vector2(x + 0.5, y + 0.5)
				var pixel: Color = original.get_pixel(x, y)
				var tile_pixel: bool = _is_tile_pixel(point, pixel, polygon, entry["face"])
				var lower_shadow: bool = Geometry2D.is_point_in_polygon(point, polygon) and (
					y > 775 if entry["name"] == "ace" else (y > 805 if entry["name"] == "queen" else y > 745))
				if not tile_pixel and not lower_shadow:
					continue
				plate.set_pixel(x, y, backing.get_pixel(x, y))
				if not tile_pixel:
					continue
				if entry["name"] != "king" and _is_tile_pixel(point, pixel, king_polygon, king_face):
					continue
				cutout.set_pixel(x - bounds.position.x, y - bounds.position.y, pixel)
		var error: Error = cutout.save_png(OUTPUT.path_join("%s.png" % entry["name"]))
		if error != OK:
			push_error("Could not save %s tile cutout: %s" % [entry["name"], error_string(error)])
			quit(1)
			return
	var error: Error = plate.save_png(OUTPUT.path_join("static_plate.png"))
	if error != OK:
		push_error("Could not save hub plate: %s" % error_string(error))
		quit(1)
		return
	print("[hub hero] extracted unchanged tile pixels and preserved original outside tile outlines")
	quit()


func _tile_shapes() -> Array[Dictionary]:
	return [
		{"name": "ace", "bounds": Rect2i(300, 455, 385, 435),
			"polygon": PackedVector2Array([
				Vector2(308, 550), Vector2(328, 538), Vector2(546, 469),
				Vector2(569, 460), Vector2(597, 476), Vector2(620, 499),
				Vector2(681, 747), Vector2(669, 778), Vector2(643, 812),
				Vector2(620, 831), Vector2(442, 880), Vector2(410, 886),
				Vector2(383, 871), Vector2(373, 845), Vector2(304, 586),
			]),
			"face": PackedVector2Array([
				Vector2(353, 578), Vector2(571, 493), Vector2(646, 782), Vector2(402, 850),
			])},
		{"name": "queen", "bounds": Rect2i(878, 463, 371, 442),
			"polygon": PackedVector2Array([
				Vector2(969, 469), Vector2(995, 469), Vector2(1208, 559),
				Vector2(1237, 583), Vector2(1247, 609), Vector2(1238, 640),
				Vector2(1159, 865), Vector2(1136, 891), Vector2(1107, 901),
				Vector2(1077, 895), Vector2(906, 821), Vector2(880, 803),
				Vector2(877, 775), Vector2(940, 503),
			]),
			"face": PackedVector2Array([
				Vector2(996, 492), Vector2(1224, 587), Vector2(1139, 879), Vector2(899, 781),
			])},
		{"name": "king", "bounds": Rect2i(573, 399, 380, 424),
			"polygon": PackedVector2Array([
				Vector2(651, 403), Vector2(680, 402), Vector2(909, 439),
				Vector2(936, 453), Vector2(949, 481), Vector2(949, 508),
				Vector2(931, 782), Vector2(915, 810), Vector2(883, 822),
				Vector2(853, 822), Vector2(608, 791), Vector2(580, 775),
				Vector2(574, 741), Vector2(613, 437), Vector2(625, 414),
			]),
			"face": PackedVector2Array([
				Vector2(666, 416), Vector2(932, 454), Vector2(907, 795), Vector2(617, 755),
			])},
	]


func _is_tile_pixel(point: Vector2, pixel: Color, outline: PackedVector2Array,
		face: PackedVector2Array) -> bool:
	if not Geometry2D.is_point_in_polygon(point, outline):
		return false
	if Geometry2D.is_point_in_polygon(point, face):
		return true
	# Outside the printed face, keep only the original border/edge colors. This
	# leaves overlapping hair, clothing and cool green backdrop stationary.
	var cream: bool = pixel.r > 0.65 and pixel.g > 0.62 and pixel.b > 0.53 and pixel.r >= pixel.g - 0.04
	var blue: bool = pixel.r < 0.3 and pixel.b > 0.4 and pixel.b > pixel.g + 0.03
	var green: bool = pixel.g > 0.35 and pixel.g > pixel.r + 0.15 and pixel.g > pixel.b + 0.05
	var warm_edge: bool = pixel.r > 0.62 and pixel.g < 0.6 and pixel.b < 0.35
	return cream or blue or green or warm_edge
