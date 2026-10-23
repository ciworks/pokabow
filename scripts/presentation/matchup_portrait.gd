extends FramedPlayerAvatar
## Mask neighbouring atlas-cell pixels at the larger pre-match portrait size.
const MASK = preload("res://scripts/presentation/matchup_portrait.gdshader")
var _atlas_mask: ShaderMaterial

func _fit_portrait() -> void:
	super._fit_portrait()
	if not texture is AtlasTexture or size.x <= 0 or size.y <= 0:
		return
	if _atlas_mask == null:
		_atlas_mask = ShaderMaterial.new()
		_atlas_mask.shader = MASK
	_atlas_mask.set_shader_parameter("view_size", size)
	material = _atlas_mask
