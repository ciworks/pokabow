class_name PlayerAvatarStore
extends RefCounted
## Normalized avatar cache stored beside the account after API confirmation.

const AVATAR_DIRECTORY: String = "res://assets/ui/modern_tabletop/avatars/players"
const FALLBACK: Texture2D = preload("res://assets/ui/modern_tabletop/avatars/players/player_01.tres")
const SIZE: int = 195
const MAX_BYTES: int = 2 * 1024 * 1024
const MAX_DIMENSION: int = 2048
const EXTENSIONS: PackedStringArray = ["jpg", "jpeg", "png"]
const RECORD_KEY: String = "local_avatar"


static func default_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for filename: String in ResourceLoader.list_directory(AVATAR_DIRECTORY):
		if filename.get_extension().to_lower() == "tres":
			paths.append(AVATAR_DIRECTORY.path_join(filename))
	paths.sort()
	return paths


static func selection(path: String = UsersStateStore.DEFAULT_PATH) -> Dictionary:
	var value: Variant = UsersStateStore.load_record(path).get(RECORD_KEY, {})
	return value if value is Dictionary else {}


static func texture(path: String = UsersStateStore.DEFAULT_PATH) -> Texture2D:
	var saved: Dictionary = selection(path)
	var resource_path: String = String(saved.get("default", ""))
	if default_paths().has(resource_path):
		return load(resource_path) as Texture2D
	var encoded: String = String(saved.get("png", ""))
	if not encoded.is_empty() and encoded.length() <= MAX_BYTES:
		var image := Image.new()
		if image.load_png_from_buffer(Marshalls.base64_to_raw(encoded)) == OK and image.get_size() == Vector2i(SIZE, SIZE):
			return ImageTexture.create_from_image(image)
	return FALLBACK


static func save_default(resource_path: String, path: String = UsersStateStore.DEFAULT_PATH) -> bool:
	if not default_paths().has(resource_path):
		return false
	return _save({"default": resource_path}, path)


static func _save(value: Dictionary, path: String) -> bool:
	if not UsersStateStore.has_accepted_account(path):
		return false
	var record: Dictionary = UsersStateStore.load_record(path)
	record[RECORD_KEY] = value
	return UsersStateStore.save_record(record, path)


## Returns an error string or a normalized Image. Never retain the source path.
static func prepare_upload(filename: String) -> Dictionary:
	var extension: String = filename.get_extension().to_lower()
	if not extension in EXTENSIONS:
		return {"error": "Choose a JPG, JPEG, or PNG image."}
	var file := FileAccess.open(filename, FileAccess.READ)
	if file == null:
		return {"error": "This image could not be opened. Please choose it again."}
	var length: int = file.get_length()
	if length == 0 or length > MAX_BYTES:
		return {"error": "Choose an image no larger than 2 MB."}
	var bytes: PackedByteArray = file.get_buffer(length)
	file.close()
	# Check dimensions before decoding to avoid allocating oversized images.
	var dimensions: Vector2i = _dimensions(bytes, extension)
	if dimensions == Vector2i.ZERO:
		return {"error": "The file is not a valid %s image." % extension.to_upper()}
	if dimensions.x < SIZE or dimensions.y < SIZE or dimensions.x > MAX_DIMENSION or dimensions.y > MAX_DIMENSION:
		return {"error": "Each side must be between 195 and 2048 pixels."}
	var image := Image.new()
	var error: Error = image.load_png_from_buffer(bytes) if extension == "png" else image.load_jpg_from_buffer(bytes)
	if error != OK or image.is_empty() or image.get_size() != dimensions:
		return {"error": "This image is damaged or unsupported. Choose another JPG or PNG."}
	var side: int = mini(image.get_width(), image.get_height())
	image = image.get_region(Rect2i((image.get_width() - side) / 2, (image.get_height() - side) / 2, side, side))
	image.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return {"image": image}


static func save_upload(image: Image, path: String = UsersStateStore.DEFAULT_PATH) -> bool:
	if image == null or image.get_size() != Vector2i(SIZE, SIZE):
		return false
	return _save({"png": Marshalls.raw_to_base64(image.save_png_to_buffer())}, path)


## Produces the normalized PNG payload for an account profile save. Defaults and
## uploaded pictures share one server representation so the update is atomic.
static func png_base64_for_selection(
		path: String,
		pending_image: Image,
		selected_index: int,
		default_paths_value: PackedStringArray
	) -> String:
	var image: Image = null
	if pending_image != null:
		image = pending_image.duplicate()
	elif selected_index >= 0 and selected_index < default_paths_value.size():
		var texture: Texture2D = load(default_paths_value[selected_index]) as Texture2D
		if texture != null:
			image = texture.get_image()
	else:
		var saved: Dictionary = selection(path)
		var encoded: String = String(saved.get("png", ""))
		if not encoded.is_empty():
			image = Image.new()
			if image.load_png_from_buffer(Marshalls.base64_to_raw(encoded)) != OK:
				image = null
		else:
			var default_path: String = String(saved.get("default", FALLBACK.resource_path))
			var texture: Texture2D = load(default_path) as Texture2D
			if texture != null:
				image = texture.get_image()
	if image == null or image.is_empty():
		return ""
	image = _normalize_avatar(image)
	return Marshalls.raw_to_base64(image.save_png_to_buffer())


## Updates the device cache only after the matching server profile save succeeds.
static func save_png_base64(encoded: String, path: String = UsersStateStore.DEFAULT_PATH) -> bool:
	if encoded.is_empty() or encoded.length() > MAX_BYTES * 2:
		return false
	var image := Image.new()
	if image.load_png_from_buffer(Marshalls.base64_to_raw(encoded)) != OK:
		return false
	if image.get_size() != Vector2i(SIZE, SIZE):
		return false
	return _save({"png": encoded}, path)


static func default_index_for_png(encoded: String, paths: PackedStringArray) -> int:
	for index: int in range(paths.size()):
		if png_base64_for_selection("", null, index, paths) == encoded:
			return index
	return -1


static func _normalize_avatar(image: Image) -> Image:
	var side: int = mini(image.get_width(), image.get_height())
	image = image.get_region(Rect2i((image.get_width() - side) / 2, (image.get_height() - side) / 2, side, side))
	image.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return image


static func _be16(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 8) | int(bytes[offset + 1])


static func _be32(bytes: PackedByteArray, offset: int) -> int:
	return (_be16(bytes, offset) << 16) | _be16(bytes, offset + 2)


static func _dimensions(bytes: PackedByteArray, extension: String) -> Vector2i:
	if extension == "png":
		if bytes.size() < 33 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
			return Vector2i.ZERO
		if _be32(bytes, 8) != 13 or bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
			return Vector2i.ZERO
		return Vector2i(_be32(bytes, 16), _be32(bytes, 20))
	if bytes.size() < 4 or bytes[0] != 0xff or bytes[1] != 0xd8:
		return Vector2i.ZERO
	var offset: int = 2
	while offset + 3 < bytes.size():
		if bytes[offset] != 0xff:
			return Vector2i.ZERO
		while offset < bytes.size() and bytes[offset] == 0xff:
			offset += 1
		if offset + 2 >= bytes.size():
			return Vector2i.ZERO
		var marker: int = bytes[offset]
		offset += 1
		if marker == 0xda or marker == 0xd9:
			return Vector2i.ZERO
		var length: int = _be16(bytes, offset)
		if length < 2 or offset + length > bytes.size():
			return Vector2i.ZERO
		if marker in [0xc0, 0xc1, 0xc2]:
			if length < 8:
				return Vector2i.ZERO
			return Vector2i(_be16(bytes, offset + 5), _be16(bytes, offset + 3))
		offset += length
	return Vector2i.ZERO
