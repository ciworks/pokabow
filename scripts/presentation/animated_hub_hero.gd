class_name AnimatedHubHero
extends TextureRect
## Moves original-pixel tile cutouts over a fixed copy of the approved artwork.
## The untouched source is drawn whenever all three tiles are resting.

const ORIGINAL: Texture2D = preload("res://assets/hub/modern-tabletop-hero-cartoon-v2.png")
const PLATE: Texture2D = preload("res://assets/hub/animated/static_plate.png")
const ACE: Texture2D = preload("res://assets/hub/animated/ace.png")
const QUEEN: Texture2D = preload("res://assets/hub/animated/queen.png")
const KING: Texture2D = preload("res://assets/hub/animated/king.png")
const TILE_BOUNDS: Array[Rect2] = [
	Rect2(300, 455, 385, 435),
	Rect2(878, 463, 371, 442),
	Rect2(573, 399, 380, 424),
]
const BOUNCE_HEIGHT: float = 18.0 # Source pixels; about 3px at hub display size.

var _tiles: Array[Texture2D] = [ACE, QUEEN, KING]
var _offsets: Array[float] = [0.0, 0.0, 0.0]
var _cooldowns: Array[float] = [0.0, 0.0, 0.0]
var _tweens: Array = [null, null, null]
var _rng := RandomNumberGenerator.new()
var _motion_enabled: bool = true
var _was_active: bool = false


func _ready() -> void:
	texture = null
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	resized.connect(queue_redraw)
	set_process(true)


func set_motion_enabled(enabled: bool) -> void:
	_motion_enabled = enabled
	if not enabled:
		_stop_bounces()
		_was_active = false


func _process(delta: float) -> void:
	if not _motion_enabled or not is_visible_in_tree():
		if _was_active:
			_stop_bounces()
			_was_active = false
		return
	if not _was_active:
		for index: int in range(3):
			_cooldowns[index] = _rng.randf_range(1.5, 5.0)
		_was_active = true
	for index: int in range(3):
		if _tweens[index] != null:
			continue
		_cooldowns[index] -= delta
		if _cooldowns[index] <= 0.0:
			_bounce(index)


func _bounce(index: int) -> void:
	var tween: Tween = create_tween()
	_tweens[index] = tween
	tween.tween_method(_set_offset.bind(index), 0.0, BOUNCE_HEIGHT, 0.19).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_offset.bind(index), BOUNCE_HEIGHT, 0.0, 0.29).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(_on_bounce_finished.bind(index))


func _set_offset(height: float, index: int) -> void:
	_offsets[index] = height
	queue_redraw()


func _on_bounce_finished(index: int) -> void:
	_tweens[index] = null
	_offsets[index] = 0.0
	_cooldowns[index] = _rng.randf_range(3.0, 8.0)
	queue_redraw()


func _stop_bounces() -> void:
	var changed: bool = false
	for index: int in range(3):
		if _tweens[index] != null:
			(_tweens[index] as Tween).kill()
			_tweens[index] = null
		if _offsets[index] != 0.0:
			_offsets[index] = 0.0
			changed = true
	if changed:
		queue_redraw()


func _draw() -> void:
	var source_size: Vector2 = ORIGINAL.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	var scale: float = minf(size.x / source_size.x, size.y / source_size.y)
	var origin: Vector2 = (size - source_size * scale) * 0.5
	var destination := Rect2(origin, source_size * scale)
	if _offsets[0] == 0.0 and _offsets[1] == 0.0 and _offsets[2] == 0.0:
		draw_texture_rect(ORIGINAL, destination, false)
		return
	draw_texture_rect(PLATE, destination, false)
	for index: int in range(3):
		var bounds: Rect2 = TILE_BOUNDS[index]
		var position: Vector2 = origin + (bounds.position - Vector2(0.0, _offsets[index])) * scale
		draw_texture_rect(_tiles[index], Rect2(position, bounds.size * scale), false)
