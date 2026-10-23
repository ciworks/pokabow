class_name FramedPlayerAvatar
extends TextureRect
## Circular portrait with a quiet teal ring used throughout the app.

const PORTRAIT_SHADER: Shader = preload("res://scripts/presentation/framed_player_avatar.gdshader")
const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")
const RING_INSET: float = 2.0

@export var show_ring: bool = true

var _ring: PanelContainer
var _photo_material: ShaderMaterial


func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	_photo_material = ShaderMaterial.new()
	_photo_material.shader = PORTRAIT_SHADER
	if show_ring:
		_ring = PanelContainer.new()
		_ring.name = "AvatarRing"
		_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_ring.offset_left = -RING_INSET
		_ring.offset_top = -RING_INSET
		_ring.offset_right = RING_INSET
		_ring.offset_bottom = RING_INSET
		var outline := StyleBoxFlat.new()
		outline.bg_color = Color.TRANSPARENT
		outline.draw_center = false
		outline.border_color = Tabletop.ink()
		outline.set_border_width_all(2)
		outline.set_corner_radius_all(512)
		_ring.add_theme_stylebox_override("panel", outline)
		add_child(_ring)
	resized.connect(_fit_portrait)
	_fit_portrait()


func _fit_portrait() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	# Generated roster atlas cells already contain their own round backdrops;
	# uploaded photographs need the circular crop shader.
	if texture is AtlasTexture:
		material = null
	else:
		material = _photo_material
		var diameter: float = minf(size.x, size.y)
		var origin := (size - Vector2.ONE * diameter) * 0.5
		_photo_material.set_shader_parameter("portrait_rect", Vector4(
			origin.x / size.x, origin.y / size.y, diameter / size.x, diameter / size.y
		))


func set_portrait(portrait: Texture2D) -> void:
	texture = portrait
	if is_node_ready():
		_fit_portrait()
