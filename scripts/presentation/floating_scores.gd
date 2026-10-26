class_name FloatingScores
extends Control

## Floating score popups (ADR-008 sections 4 and 9, GAME_SPEC section 7.4).
##
## ADR-008 section 9 requires score animation to run from committed score events
## in deterministic event order, and forbids animation from affecting rules
## completion. These labels are therefore purely additive: they read points that
## were already awarded, they never compute a score, and clearing them cannot
## change any state.
##
## One popup shows the sum of the committed awards for a played move.
## How far a popup drifts upward.
const RISE_PIXELS: float = 56.0

## How long a popup lives.
const DURATION: float = 1.15

## Popup font size.
const FONT_SIZE: int = 55
const OUTLINE_SIZE: int = 5
const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")

## A fixed light-on-dark treatment stays readable over ivory tiles and sage cells.
const SCORE_COLOR: Color = Color("#F6F2E9")
const SCORE_OUTLINE_COLOR: Color = Color("#173D42")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Spawns one popup at `at`, which is in this control's local coordinates.
func spawn(at: Vector2, points: int) -> void:
	var label: Label = Label.new()
	label.text = str(points)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", Tabletop.BOLD)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", SCORE_COLOR)
	label.add_theme_color_override("font_outline_color", SCORE_OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	add_child(label)

	# Measure Fredoka Bold so large totals stay centred and on screen.
	label.size = label.get_combined_minimum_size()
	var inset: Vector2 = Vector2.ONE * OUTLINE_SIZE
	var maximum: Vector2 = (size - label.size - inset).max(inset)
	label.position = (at - label.size * 0.5).clamp(inset, maximum)

	if AccessibilitySettings.reduced_motion():
		# Reduced motion: the points are still shown, because the number is the
		# whole point of a score popup, but it neither rises nor fades. It is
		# anchored where it was asked for and removed after the same delay, so
		# the ordering the ledger recorded still reads correctly.
		var hold: Tween = label.create_tween()
		hold.tween_interval(DURATION)
		hold.tween_callback(label.queue_free)
		return

	var rise: Tween = label.create_tween()
	rise.tween_property(label, "position:y", maxf(OUTLINE_SIZE, label.position.y - RISE_PIXELS), DURATION)
	# One brief flash, a readable hold, then disappearance.
	var flash: Tween = label.create_tween()
	flash.tween_property(label, "modulate:a", 0.35, 0.12)
	flash.tween_property(label, "modulate:a", 1.0, 0.12)
	flash.tween_interval(0.36)
	flash.tween_property(label, "modulate:a", 0.0, DURATION - 0.60)
	flash.tween_callback(label.queue_free)


## Removes every popup immediately.
##
## Called when the view resynchronizes to authoritative state, so an interrupted
## animation leaves nothing behind (ADR-008 section 9).
func clear_all() -> void:
	for child: Node in get_children():
		child.queue_free()


## Returns how many popups are currently alive, for smoke tests.
func active_count() -> int:
	return get_child_count()
