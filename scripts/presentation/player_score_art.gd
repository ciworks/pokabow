extends Control

## Fits the overlapping portrait and score plate without changing score state.
const EXTRA_VERTICAL_PADDING: float = 5.0

var _warning_tween: Tween
var _warning_origin: Vector2


## Brief motion on the whole artwork keeps portrait, plate, text, and border
## together. Reduced-motion preference suppresses the shake.
func warn_time_running_out() -> void:
	stop_turn_warning()
	if not is_inside_tree() or AccessibilitySettings.reduced_motion():
		return
	_warning_origin = position
	_warning_tween = create_tween()
	for offset: float in [-2.0, 2.0, -1.5, 1.5, 0.0]:
		_warning_tween.tween_property(self, "position", _warning_origin + Vector2(offset, 0.0), 0.06)


func stop_turn_warning() -> void:
	if _warning_tween != null:
		_warning_tween.kill()
		position = _warning_origin
		_warning_tween = null

@export var portrait_on_right: bool = false
@export var title_path: NodePath = ^"HumanScoreTitle"
@export var value_path: NodePath = ^"HumanScoreValue"

@onready var portrait: TextureRect = $Portrait
@onready var plate: NinePatchRect = $Plate
@onready var outline: PanelContainer = $TurnOutline
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
	outline.position = plate.position + Vector2(2, 2)
	outline.size = plate.size - Vector2(4, 4)
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
