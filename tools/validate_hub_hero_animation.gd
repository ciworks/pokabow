extends SceneTree

const Original: Texture2D = preload("res://assets/hub/modern-tabletop-hero-cartoon-v2.png")
const Plate: Texture2D = preload("res://assets/hub/animated/static_plate.png")
const Tiles: Array[Texture2D] = [
	preload("res://assets/hub/animated/ace.png"),
	preload("res://assets/hub/animated/queen.png"),
	preload("res://assets/hub/animated/king.png"),
]


func _initialize() -> void:
	var failures: int = 0
	var original: Image = Original.get_image()
	var plate: Image = Plate.get_image()
	if original.get_size() != plate.get_size():
		failures += 1
	for avatar_region: Rect2i in [Rect2i(45, 170, 470, 290), Rect2i(1045, 170, 450, 290)]:
		for y: int in range(avatar_region.position.y, avatar_region.end.y):
			for x: int in range(avatar_region.position.x, avatar_region.end.x):
				if original.get_pixel(x, y) != plate.get_pixel(x, y):
					failures += 1
					break
			if failures > 0:
				break
	for index: int in range(3):
		var bounds: Rect2 = AnimatedHubHero.TILE_BOUNDS[index]
		var tile: Image = Tiles[index].get_image()
		if tile.get_size() != Vector2i(bounds.size):
			failures += 1
			continue
		for y: int in range(tile.get_height()):
			for x: int in range(tile.get_width()):
				var pixel: Color = tile.get_pixel(x, y)
				if pixel.a > 0.99 and pixel != original.get_pixel(x + int(bounds.position.x), y + int(bounds.position.y)):
					failures += 1
					break
			if failures > 0:
				break
	var directory: String = OS.get_environment("HUB_HERO_QA_DIR")
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
		for moving: int in range(3):
			var preview: Image = plate.duplicate()
			for index: int in range(3):
				var bounds: Rect2 = AnimatedHubHero.TILE_BOUNDS[index]
				var tile: Image = Tiles[index].get_image()
				var destination := Vector2i(bounds.position) - Vector2i(0, roundi(AnimatedHubHero.BOUNCE_HEIGHT) if index == moving else 0)
				preview.blend_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), destination)
			preview.save_png(directory.path_join("%d-bounce.png" % moving))
	print("[hub hero animation] %d pixel invariance failures" % failures)
	quit(0 if failures == 0 else 1)
