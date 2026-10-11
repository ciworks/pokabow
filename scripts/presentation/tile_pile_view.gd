class_name TilePileView
extends Control

## Decorative shared bag artwork; pictured faces do not describe unseen tiles.
## The screen supplies the authoritative count and deals from the bag opening.
const POT_TEXTURE: Texture2D = preload("res://assets/ui/tile_pot.png")
## Visible artwork plus a small edge allowance; excludes faint alpha noise in
## the source's large transparent top and bottom margins.
const POT_ART_REGION: Rect2 = Rect2(0, 264, 1005, 1030)
## Soft ellipse cast under the bag. Cropped to the shape's visible pixels,
## because the source canvas carries 128px of empty margin above and below it.
const POT_SHADOW_TEXTURE: Texture2D = preload("res://assets/ui/tile_pot_shadow.png")
const POT_SHADOW_ART_REGION: Rect2 = Rect2(0, 128, 970, 282)
## The artwork is drawn this much larger than the space the header reserves for
## it, so the pot reads as a foreground object rather than a small badge.
const POT_DRAW_SCALE: float = 1.25
## Fraction of the drawn artwork its base is lowered below the header slot. The
## slot ends 12px above the board's outer border, so the bag is shifted only far
## enough to clear that border: at 25% above its slot the bag cannot both stay
## on screen and sit flush with the slot.
const POT_BASE_DROP: float = 0.075

## Tiles the pile currently stands for.
var _tile_count: int = 0
var _pot_texture: AtlasTexture
var _pot_rect: Rect2
var _shadow_texture: AtlasTexture
var _shadow_rect: Rect2

@onready var count_plate: NinePatchRect = $CountPlate
@onready var count_label: Label = $CountPlate/AvailableTilesLabel
@onready var caption: Label = $PotCaption


func _ready() -> void:
	# Decorative: pointer events pass straight through to whatever is behind.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Ignore transparent source margins without altering the supplied assets.
	_pot_texture = AtlasTexture.new()
	_pot_texture.atlas = POT_TEXTURE
	_pot_texture.region = POT_ART_REGION
	_shadow_texture = AtlasTexture.new()
	_shadow_texture.atlas = POT_SHADOW_TEXTURE
	_shadow_texture.region = POT_SHADOW_ART_REGION
	resized.connect(_layout)
	_layout()


## Shows a pile standing for `tile_count` tiles still in the bag.
func set_tile_count(tile_count: int) -> void:
	var clamped: int = maxi(tile_count, 0)
	if clamped == _tile_count:
		return
	_tile_count = clamped
	queue_redraw()


## Returns the number of tiles the pile stands for.
func tile_count() -> int:
	return _tile_count


## Returns the point a dealt tile should leave from, in GLOBAL coordinates.
##
## The screen measures the deal's flight without knowing how the bag is drawn.
func stack_origin_global() -> Vector2:
	return get_global_transform() * (_pot_rect.position + _pot_rect.size * Vector2(0.5, 0.3))


func _draw() -> void:
	# Shadow first: the bag's base sits over the shadow's upper half.
	if _shadow_texture != null:
		draw_texture_rect(_shadow_texture, _shadow_rect, false)
	if _pot_texture != null:
		draw_texture_rect(_pot_texture, _pot_rect, false)


func _layout() -> void:
	var source_size: Vector2 = _pot_texture.get_size()
	var scale: float = minf(size.x / source_size.x, size.y / source_size.y) * POT_DRAW_SCALE
	var drawn_size: Vector2 = source_size * scale
	# Taller than its slot, so the base is shifted a little past the slot's
	# bottom edge: that keeps the art clear of the board's border below while
	# leaving the top on screen. The panel draws no background of its own.
	_pot_rect = Rect2(
		Vector2((size.x - drawn_size.x) * 0.5, size.y - drawn_size.y * (1.0 - POT_BASE_DROP)),
		drawn_size
	)
	# Centred on the bag's base: the shadow's upper half reads behind the bag and
	# its lower half crosses onto the board's border.
	var shadow_size: Vector2 = _shadow_texture.get_size() * scale
	_shadow_rect = Rect2(
		Vector2((size.x - shadow_size.x) * 0.5, _pot_rect.end.y - shadow_size.y * 0.5),
		shadow_size
	)
	count_plate.position = _pot_rect.position + drawn_size * Vector2(0.23, 0.58)
	count_plate.size = drawn_size * Vector2(0.54, 0.28)
	count_label.add_theme_font_size_override("font_size", clampi(roundi(drawn_size.y * 0.21), 18, 26))
	caption.position = _pot_rect.position + Vector2(0.0, drawn_size.y * 0.85)
	caption.size = Vector2(drawn_size.x, 18.0)
	queue_redraw()
