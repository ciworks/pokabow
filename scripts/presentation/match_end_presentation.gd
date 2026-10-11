class_name MatchEndPresentation
extends Control

## Presentation-only storyboard matching assets/competition_scene_1..5.png.
## A single timeline makes restart, resize, reduced motion and QA deterministic.
# Storyboard: panels join, portraits land, score plates slide out, then detail.
const PANEL_JOIN_START: float = 0.22
const PANEL_JOIN_DURATION: float = 0.72
const PLAYER_DROP_START: float = 0.98
const RIVAL_DROP_START: float = 1.16
const DROP_DURATION: float = 0.47
const SETTLE_START: float = 1.7
const SETTLE_DURATION: float = 0.55
const SCORE_SLIDE_START: float = SETTLE_START + SETTLE_DURATION
const SCORE_SLIDE_DURATION: float = 0.51
const DETAIL_SLIDE_START: float = SCORE_SLIDE_START + SCORE_SLIDE_DURATION + 0.12
const DETAIL_SLIDE_DURATION: float = 0.48
const RESULT_REVEAL_START: float = SCORE_SLIDE_START
const BODY_REVEAL_START: float = DETAIL_SLIDE_START + 0.12
const BUTTON_REVEAL_START: float = DETAIL_SLIDE_START + DETAIL_SLIDE_DURATION
const DURATION: float = BUTTON_REVEAL_START + 0.35
const BLUE: Color = Color("123da5")
const RED: Color = Color("c90000")
const BLUE_AVATAR: Texture2D = preload("res://assets/board/characters/avatar_default_rival.png")
const RED_AVATAR: Texture2D = preload("res://assets/board/characters/avatar_default.png")
const BLUE_PLATE: Texture2D = preload("res://assets/ui/avatar_panel_rival.png")
const RED_PLATE: Texture2D = preload("res://assets/ui/avatar_panel_default.png")

var _elapsed: float = 0.0
var _animation: Tween = null
var _result: MatchResult = null
var _celebrating: bool = false
var _result_key: String = ""
var _background: GradientTexture2D
var _blue_avatar: TextureRect
var _red_avatar: TextureRect
var _blue_clip: Control
var _red_clip: Control
var _detail_clip: Control
var _blue_plate: NinePatchRect
var _red_plate: NinePatchRect
var _detail_plate: NinePatchRect
var _you_name: Label
var _you_score: Label
var _rival_name: Label
var _rival_score: Label
var _detail_title: Label
var _detail_values: Label
var _title: Label
var _body: Label
var _button: Button
var _confetti: ConfettiLayer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_title = get_node("SummaryTitle") as Label
	_body = get_node("SummaryBody") as Label
	_button = get_node("SummaryHubButton") as Button
	_confetti = get_node("ConfettiLayer") as ConfettiLayer
	var gradient := Gradient.new()
	gradient.set_color(0, Color.BLACK)
	gradient.set_color(1, Color("040e22"))
	_background = GradientTexture2D.new()
	_background.gradient = gradient
	_background.fill_from = Vector2.ZERO
	_background.fill_to = Vector2(0, 1)
	_detail_clip = _make_clip("PlayerDetailReveal")
	_detail_plate = _make_plate(_detail_clip, BLUE_PLATE)
	_detail_title = _make_label(_detail_plate, "POINTS BREAKDOWN")
	_detail_values = _make_label(_detail_plate, "")
	_blue_clip = _make_clip("PlayerScoreReveal")
	_blue_plate = _make_plate(_blue_clip, BLUE_PLATE)
	_you_name = _make_label(_blue_plate, "You")
	_you_score = _make_label(_blue_plate, "0")
	_red_clip = _make_clip("RivalScoreReveal")
	_red_plate = _make_plate(_red_clip, RED_PLATE)
	_rival_name = _make_label(_red_plate, "Rival")
	_rival_score = _make_label(_red_plate, "0")
	_blue_avatar = _make_avatar("PlayerAvatar", BLUE_AVATAR)
	_red_avatar = _make_avatar("RivalAvatar", RED_AVATAR)
	# Confetti is above the color panels, below portraits/text/actions.
	move_child(_confetti, 0)
	for node: Control in [_title, _body, _button]:
		move_child(node, get_child_count() - 1)
	resized.connect(_render_frame)
	visibility_changed.connect(_on_visibility_changed)
	_render_frame()


func play(result: MatchResult) -> void:
	if result == null:
		return
	var key := "%d:%d:%d:%d" % [result.outcome, result.human_score, result.ai_score, result.move_count]
	if visible and _result_key == key:
		return
	_stop_animation()
	_result = result
	_result_key = key
	_celebrating = false
	_confetti.clear()
	_you_score.text = str(result.human_score)
	_rival_score.text = str(result.ai_score)
	var points: Dictionary = result.terms_for(TurnEnums.HUMAN_PLAYER_ID)
	_detail_values.text = "Poker %d\nEdges %d  ·  Clusters %d" % [
		int(points.get("poker", 0)), int(points.get("edge", 0)), int(points.get("cluster", 0))]
	visible = true
	_button.disabled = true
	if AccessibilitySettings.reduced_motion():
		seek(DURATION)
		return
	seek(0.0)
	_animation = create_tween()
	_animation.tween_method(seek, 0.0, DURATION, DURATION)


func clear() -> void:
	_stop_animation()
	_result_key = ""
	_result = null
	_celebrating = false
	_elapsed = 0.0
	if _confetti != null:
		_confetti.clear()
	if _button != null:
		_button.disabled = true
	visible = false


## Seek is also used by the frame-capture tool; it never changes game state.
func seek(seconds: float) -> void:
	_elapsed = clampf(seconds, 0.0, DURATION)
	_render_frame()
	var should_celebrate: bool = visible and _elapsed >= RESULT_REVEAL_START and _result != null and not _rival_won()
	if should_celebrate and not _celebrating:
		_celebrating = true
		_confetti.play()
	elif not should_celebrate and _celebrating:
		_celebrating = false
		_confetti.clear()


func _stop_animation() -> void:
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_animation = null


func _on_visibility_changed() -> void:
	if not visible:
		_stop_animation()
		_celebrating = false
		_result_key = ""
		if _confetti != null:
			_confetti.clear()


func _exit_tree() -> void:
	_stop_animation()


func _make_clip(node_name: String) -> Control:
	var clip := Control.new()
	clip.name = node_name
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	return clip


func _make_plate(parent: Control, texture: Texture2D) -> NinePatchRect:
	var plate := NinePatchRect.new()
	plate.texture = texture
	plate.patch_margin_left = 12
	plate.patch_margin_top = 12
	plate.patch_margin_right = 12
	plate.patch_margin_bottom = 12
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(plate)
	return plate


func _make_label(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color.WHITE)
	parent.add_child(label)
	return label


func _make_avatar(node_name: String, texture: Texture2D) -> TextureRect:
	var avatar := TextureRect.new()
	avatar.name = node_name
	avatar.texture = texture
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(avatar)
	return avatar


func _progress(start: float, duration: float) -> float:
	return clampf((_elapsed - start) / duration, 0.0, 1.0)


func _smooth(start: float, duration: float) -> float:
	return smoothstep(0.0, 1.0, _progress(start, duration))


func _render_frame() -> void:
	queue_redraw()
	if _blue_avatar == null or size.x <= 0 or size.y <= 0:
		return
	# Keep the portrait composition readable on both tall phones and wide screens.
	var width: float = minf(size.x, size.y * 0.86)
	var frame := Rect2(Vector2((size.x - width) * 0.5, 0), Vector2(width, size.y))
	var unit: float = width / 353.0
	var settle: float = _smooth(SETTLE_START, SETTLE_DURATION)
	var avatar_size: float = minf(width * 0.37, size.y * 0.28)
	var top: Vector2 = frame.position + Vector2(width * lerpf(0.25, 0.18, settle), size.y * lerpf(0.17, 0.15, settle))
	var bottom: Vector2 = frame.position + Vector2(width * 0.76, size.y * 0.76)
	var settled_size: float = avatar_size * lerpf(1.0, 0.82, settle)
	_place_avatar(_blue_avatar, top, settled_size, _progress(PLAYER_DROP_START, DROP_DURATION))
	_place_avatar(_red_avatar, bottom, settled_size, _progress(RIVAL_DROP_START, DROP_DURATION))

	var plate_height: float = settled_size * 0.69
	var blue_rect := Rect2(top + Vector2(-settled_size * 0.08, -plate_height * 0.43), Vector2(width * 0.40, plate_height))
	var red_rect := Rect2(bottom + Vector2(-width * 0.38, -plate_height * 0.43), Vector2(width * 0.42, plate_height))
	_reveal_plate(_blue_clip, _blue_plate, blue_rect, _smooth(SCORE_SLIDE_START, SCORE_SLIDE_DURATION), false)
	_reveal_plate(_red_clip, _red_plate, red_rect, _smooth(SCORE_SLIDE_START, SCORE_SLIDE_DURATION), true)
	var detail_rect := Rect2(Vector2(blue_rect.end.x - width * 0.03, blue_rect.position.y + plate_height * 0.04), Vector2(width * 0.37, plate_height * 0.92))
	_reveal_plate(_detail_clip, _detail_plate, detail_rect, _smooth(DETAIL_SLIDE_START, DETAIL_SLIDE_DURATION), false)
	_score_labels(_you_name, _you_score, blue_rect.size, true, unit)
	_score_labels(_rival_name, _rival_score, red_rect.size, false, unit)
	_set_label(_detail_title, Rect2(8 * unit, 7 * unit, detail_rect.size.x - 16 * unit, 15 * unit), maxi(9, roundi(10 * unit)))
	_set_label(_detail_values, Rect2(5 * unit, 22 * unit, detail_rect.size.x - 10 * unit, detail_rect.size.y - 26 * unit), maxi(10, roundi(11 * unit)))

	var reveal: float = _smooth(RESULT_REVEAL_START, 0.44)
	var title_rect := Rect2(frame.position + Vector2(10 * unit, size.y * 0.365 + (1.0 - reveal) * 18 * unit), Vector2(width - 20 * unit, size.y * 0.14))
	var font_size: int = roundi(minf(57 * unit, size.y * 0.105))
	var font: Font = _title.get_theme_font("font")
	while font_size > 18 and font.get_string_size(_title.text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > title_rect.size.x:
		font_size -= 1
	_set_label(_title, title_rect, font_size)
	_title.modulate.a = reveal
	_title.visible = reveal > 0.0
	# Preserve the real end reason and both category breakdowns from GameScreen.
	_set_label(_body, Rect2(frame.position + Vector2(width * 0.04, size.y * 0.51), Vector2(width * 0.92, size.y * 0.14)), maxi(10, roundi(minf(12 * unit, size.y * 0.023))))
	_body.modulate.a = _smooth(BODY_REVEAL_START, 0.40)
	_body.visible = _elapsed >= BODY_REVEAL_START
	_button.position = frame.position + Vector2(width * 0.14, size.y * 0.89)
	_button.size = Vector2(width * 0.72, maxf(44.0, minf(52 * unit, size.y * 0.085)))
	_button.add_theme_font_size_override("font_size", maxi(14, roundi(17 * unit)))
	_button.modulate.a = _smooth(BUTTON_REVEAL_START, 0.35)
	_button.visible = _elapsed >= BUTTON_REVEAL_START
	_button.disabled = _elapsed < DURATION


func _score_labels(name_label: Label, score_label: Label, plate_size: Vector2, on_left: bool, unit: float) -> void:
	var left: float = plate_size.x * (0.40 if on_left else 0.05)
	var text_width: float = plate_size.x * 0.53
	_set_label(name_label, Rect2(left, plate_size.y * 0.11, text_width, plate_size.y * 0.25), maxi(12, roundi(17 * unit)))
	var score_size: int = roundi(29 * unit)
	var font: Font = score_label.get_theme_font("font")
	while score_size > 12 and font.get_string_size(score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, score_size).x > text_width:
		score_size -= 1
	_set_label(score_label, Rect2(left, plate_size.y * 0.38, text_width, plate_size.y * 0.48), score_size)


func _set_label(label: Label, rect: Rect2, font_size: int) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.position = rect.position
	label.size = rect.size


func _place_avatar(avatar: TextureRect, center: Vector2, diameter: float, progress: float) -> void:
	avatar.visible = progress > 0.0
	# Back easing produces a short, soft landing after the large-to-small drop.
	var p: float = progress - 1.0
	var landed: float = 1.0 + 2.2 * p * p * p + 1.2 * p * p
	var scale_factor: float = lerpf(2.6, 1.0, landed)
	avatar.size = Vector2.ONE * diameter
	avatar.pivot_offset = avatar.size * 0.5
	avatar.scale = Vector2.ONE * scale_factor
	avatar.position = center - avatar.size * 0.5 - Vector2(0, (1.0 - progress) * diameter * 0.42)
	avatar.modulate.a = minf(1.0, progress * 5.0)


func _reveal_plate(clip: Control, plate: NinePatchRect, rect: Rect2, progress: float, from_right: bool) -> void:
	clip.visible = progress > 0.0
	# Move the complete artwork and its labels through a fixed mask. Resizing
	# only the mask was a wipe: the panel itself never actually slid out.
	clip.size = rect.size
	clip.position = rect.position
	plate.size = rect.size
	var direction: float = 1.0 if from_right else -1.0
	plate.position = Vector2(direction * rect.size.x * (1.0 - progress), 0.0)


func _rival_won() -> bool:
	return _result != null and _result.outcome == TurnEnums.MatchOutcome.AI_WIN


func _panel_sweep_direction() -> float:
	return -1.0 if _rival_won() else 1.0


func _draw() -> void:
	if _background == null:
		return
	draw_texture_rect(_background, Rect2(Vector2.ZERO, size), false)
	var join: float = _smooth(PANEL_JOIN_START, PANEL_JOIN_DURATION)
	if join <= 0.0:
		return
	var sweep: float = _smooth(SETTLE_START, SETTLE_DURATION)
	# Rival wins pull the boundary upward so the lower red panel fills the screen.
	var direction: float = _panel_sweep_direction()
	var left: float = size.y * (0.85 + direction * 1.05 * sweep)
	var right: float = size.y * (0.15 + direction * 1.05 * sweep)
	var gap: float = size.y * (1.0 - join)
	# Overscan keeps polygons covering the viewport during rotation/resizing.
	draw_colored_polygon(PackedVector2Array([Vector2(0, -size.y), Vector2(size.x, -size.y),
		Vector2(size.x, right - gap), Vector2(0, left - gap)]), BLUE)
	draw_colored_polygon(PackedVector2Array([Vector2(0, left + gap), Vector2(size.x, right + gap),
		Vector2(size.x, size.y * 3.0), Vector2(0, size.y * 3.0)]), RED)
