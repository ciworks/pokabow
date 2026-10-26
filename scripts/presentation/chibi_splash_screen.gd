extends Control
## A quiet first brand card before the existing loading splash.

@onready var _logo: TextureRect = $Logo

func _ready() -> void:
	resized.connect(_fit_logo)
	_fit_logo()

func _fit_logo() -> void:
	var side: float = minf(size.x * 0.78, size.y * 0.58) * 0.5
	_logo.size = Vector2.ONE * side
	_logo.position = (size - _logo.size) * 0.5
