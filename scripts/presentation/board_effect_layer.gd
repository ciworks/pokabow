class_name BoardEffectLayer
extends Control

## Draws board-level feedback text and frame (ADR-008 section 4,
## GAME_SPEC section 7.2).
##
## This layer carries the *reason* a placement was refused, rendered next to the
## cell that was refused, so mobile players get specific feedback without the UI
## re-deriving any rule: the message arrives already worded by the application
## layer from a `PlacementRejection` value.
##
## It never blocks input and never draws over the HUD; `BoardView` sizes it to
## the board.

## Board frame colour.
const FRAME_COLOR: Color = Color(0.32, 0.36, 0.44, 1.0)

## Refusal text colour.
const REASON_COLOR: Color = Color(0.98, 0.62, 0.60, 1.0)

## Current render state, assigned by `BoardView`.
var state: BoardRenderState = null


func _ready() -> void:
	# Feedback text must not become a hit target above the board
	# (ADR-008 section 8).
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if state == null or state.board == null:
		return
	_draw_frame()
	_draw_reason()


## Draws the board's outer frame.
func _draw_frame() -> void:
	if state.board_rect.size.x <= 1.0:
		return
	draw_rect(state.board_rect, FRAME_COLOR, false, 2.0)


## Draws the refusal reason under the refused cell.
func _draw_reason() -> void:
	if state.has_pending() and state.pending_valid:
		return
	if state.pending_reason.is_empty():
		return

	var font: Font = ThemeDB.fallback_font
	if font == null:
		return

	# Anchor the message under the refused cell when there is one, so the player
	# can see which cell it refers to.
	var anchor: Vector2 = state.board_rect.position + Vector2(0.0, state.board_rect.size.y)
	if state.has_pending() and BoardMetrics.is_valid_cell(state.pending.get_cell(), state.grid):
		anchor = BoardMetrics.cell_rect(
			state.board_rect, state.pending.get_cell(), state.grid
		).end

	var font_size: int = 16
	var text: String = state.pending_reason
	var text_size: Vector2 = font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
	)
	var origin: Vector2 = Vector2(
		clampf(anchor.x - text_size.x * 0.5, 0.0, maxf(state.board_rect.size.x - text_size.x, 0.0)),
		minf(anchor.y + font.get_ascent(font_size) + 6.0, size.y - 2.0)
	)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, REASON_COLOR)
