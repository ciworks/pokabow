extends Control

## Fits the overlapping portrait and score plate without changing score state.
const EXTRA_VERTICAL_PADDING: float = 5.0
const GAME_AVATAR_SCALE: Vector2 = Vector2.ONE * 1.25
const COMPACT_HORIZONTAL_GAP: float = 20.0

@export var stacked: bool = false
@export var compact_horizontal: bool = false
@export var portrait_on_right: bool = false
@export var title_path: NodePath = ^"HumanScoreTitle"
@export var value_path: NodePath = ^"HumanScoreValue"

@onready var portrait: TextureRect = $Portrait
@onready var plate: NinePatchRect = $Plate
@onready var title: Label = get_node(title_path) as Label
@onready var value: Label = get_node(value_path) as Label


func _ready() -> void:
	resized.connect(_layout)
	title.minimum_size_changed.connect(_queue_layout)
	value.minimum_size_changed.connect(_queue_layout)
	_layout()


func _queue_layout() -> void:
	call_deferred("_layout")


func _layout() -> void:
	if compact_horizontal:
		_layout_compact_horizontal()
		return
	if stacked:
		_layout_stacked()
		return
	var artwork_width: float = minf(size.x, size.y * 2.5)
	var artwork_left: float = (size.x - artwork_width) * 0.5
	var portrait_width: float = minf(size.y * 0.95, artwork_width * 0.55)
	portrait.position = Vector2(artwork_left, 0.0)
	portrait.size = Vector2(portrait_width, size.y)
	plate.position = Vector2(artwork_left + portrait_width * 0.45, size.y * 0.25 - EXTRA_VERTICAL_PADDING)
	plate.size = Vector2(artwork_width - portrait_width * 0.45, size.y * 0.64 + EXTRA_VERTICAL_PADDING * 2.0)
	if portrait_on_right:
		portrait.position.x = artwork_left + artwork_width - portrait_width
		plate.position.x = artwork_left
	var text_left: float = artwork_left + portrait_width * 0.96
	var text_width: float = maxf(1.0, artwork_width - portrait_width * 0.96 - 5.0)
	if portrait_on_right:
		text_left = artwork_left + 5.0
	var title_font_size: int = 14 if size.x < 140.0 else 16
	if title.get_theme_font_size("font_size") != title_font_size:
		title.add_theme_font_size_override("font_size", title_font_size)
	var font: Font = value.get_theme_font("font")
	var font_size: int = 28 if size.x < 140.0 else 32
	while font_size > 12 and font.get_string_size(value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > text_width:
		font_size -= 1
	if value.get_theme_font_size("font_size") != font_size:
		value.add_theme_font_size_override("font_size", font_size)
	# Center the complete text stack so its top and bottom padding are equal.
	var title_height: float = title.get_minimum_size().y
	var value_height: float = value.get_minimum_size().y
	var text_top: float = plate.position.y + (plate.size.y - title_height - value_height) * 0.5
	title.position = Vector2(text_left, text_top)
	title.size = Vector2(text_width, title_height)
	value.position = Vector2(text_left, text_top + title_height)
	value.size = Vector2(text_width, value_height)


## Keep portrait and score in the outer portion, clear of the central pot.
func _layout_stacked() -> void:
	plate.position = Vector2.ZERO
	plate.size = size
	var center_x: float = size.x * (0.65 if portrait_on_right else 0.35)
	var portrait_side: float = minf(size.y * 0.57, size.x * 0.55)
	portrait.position = Vector2(center_x - portrait_side * 0.5, 8.0)
	portrait.size = Vector2.ONE * portrait_side
	# Scale the player and its frame around the same vertical center as the rival.
	portrait.pivot_offset = portrait.size * 0.5
	var text_width: float = size.x * 0.50
	var font_size: int = 34
	var font: Font = value.get_theme_font("font")
	while font_size > 16 and font.get_string_size(value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > text_width:
		font_size -= 1
	font_size = maxi(1, roundi(float(font_size) * 0.5))
	if value.get_theme_font_size("font_size") != font_size:
		value.add_theme_font_size_override("font_size", font_size)
	if title.get_theme_font_size("font_size") != 20:
		title.add_theme_font_size_override("font_size", 20)
	var title_height: float = title.get_minimum_size().y
	var value_height: float = value.get_minimum_size().y
	var text_top: float = maxf(portrait.position.y + portrait_side, size.y - title_height - value_height - 10.0)
	title.position = Vector2(center_x - text_width * 0.5, text_top)
	title.size = Vector2(text_width, title_height)
	value.position = Vector2(title.position.x, text_top + title_height)
	value.size = Vector2(text_width, value_height)


## Small portrait and score pair used by the Modern Tabletop score strip.
func _layout_compact_horizontal() -> void:
	plate.hide()
	var side: float = minf(54.0, maxf(32.0, size.y - 12.0))
	var inset: float = 8.0
	portrait.size = Vector2.ONE * side
	portrait.pivot_offset = portrait.size * 0.5
	portrait.scale = GAME_AVATAR_SCALE
	portrait.position = Vector2(inset, (size.y - side) * 0.5)
	var text_left: float = portrait.position.x + side + COMPACT_HORIZONTAL_GAP
	var text_width: float = maxf(1.0, size.x - text_left - inset)
	if portrait_on_right:
		portrait.position.x = size.x - inset - side
		text_left = inset
		text_width = maxf(1.0, portrait.position.x - COMPACT_HORIZONTAL_GAP - text_left)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if not portrait_on_right else HORIZONTAL_ALIGNMENT_RIGHT
	value.horizontal_alignment = title.horizontal_alignment
	if title.get_theme_font_size("font_size") != 18:
		title.add_theme_font_size_override("font_size", 18)
	var font: Font = value.get_theme_font("font")
	var font_size: int = 36
	while font_size > 18 and font.get_string_size(value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > text_width:
		font_size -= 1
	if value.get_theme_font_size("font_size") != font_size:
		value.add_theme_font_size_override("font_size", font_size)
	var title_height: float = title.get_minimum_size().y
	var value_height: float = value.get_minimum_size().y
	var top: float = (size.y - title_height - value_height) * 0.5
	title.position = Vector2(text_left, top)
	title.size = Vector2(text_width, title_height)
	value.position = Vector2(text_left, top + title_height)
	value.size = Vector2(text_width, value_height)
