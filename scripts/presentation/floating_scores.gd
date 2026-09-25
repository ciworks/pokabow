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
## At most one popup is shown per committed event, so a placement that scores a
## hand, an edge match, and a cluster milestone produces three ordered popups.

## How far a popup drifts upward.
const RISE_PIXELS: float = 56.0

## How long a popup lives.
const DURATION: float = 1.15

## Popup font size.
const FONT_SIZE: int = 22


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Spawns one popup at `at`, which is in this control's local coordinates.
func spawn(at: Vector2, text: String, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	add_child(label)

	# Centre the label on the anchor point rather than growing from a corner.
	label.position = at - Vector2(float(text.length()) * 5.0, FONT_SIZE * 0.5)

	if AccessibilitySettings.reduced_motion():
		# Reduced motion: the points are still shown, because the number is the
		# whole point of a score popup, but it neither rises nor fades. It is
		# anchored where it was asked for and removed after the same delay, so
		# the ordering the ledger recorded still reads correctly.
		var hold: Tween = create_tween()
		hold.tween_interval(DURATION)
		hold.tween_callback(label.queue_free)
		return

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - RISE_PIXELS, DURATION)
	tween.tween_property(label, "modulate:a", 0.0, DURATION)
	tween.chain().tween_callback(label.queue_free)


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
