class_name ScoreRevealLayer
extends Control

## Shows committed poker-hand awards (AGENTS.md section 8,
## GAME_SPEC section 7.3, docs/sections/05-mobile-ux.md section 4).
##
## A tactile ripple and honey perimeter identify scored poker hands. High-value
## hands also receive a brief chip stamp; popups report the move's total points.
##
## ADR-008 section 4 keeps presentation out of the rules, so this layer is handed
## finished `ScoreEvent`s and reads only their cells and hand category. It never reads
## `BoardState`, never re-derives a match, and never decides what scored, so the
## reveal can only ever show an award that was really made - which is also why a
## refused placement reveals nothing.
##
## The lift moves a tile on screen without moving the board: a draw scale is
## written into the shared render state, which `BoardTileLayer` reads, and is
## cleared when the animation ends or the reveal is dropped.

## Time from full visibility to hidden.
const FADE: float = 2.0

## How much bigger a lifted tile grows at the peak, as a fraction of its size.
##
## The board is 2D, so the Z axis is expressed as scale: growing about the cell's
## centre reads as the tile rising toward the viewer. A positional hop would read
## as sliding across the grid, which could be mistaken for a different cell.
const BOUNCE_ZOOM_RATIO: float = 0.07

## How long one tile's bounce lasts, in seconds.
const BOUNCE_DURATION: float = 0.28

## Gap between one tile starting its bounce and the next, in seconds.
const BOUNCE_STAGGER: float = 0.11

const TRACE_DURATION: float = 0.72
const CHIP_START: float = 0.60
const CHIP_DURATION: float = 0.62
const CHIP_FONT_SIZE: int = 19
const CHIP_HEIGHT: float = 34.0
const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")

## Emitted every frame while the bounce runs, so `BoardView` repaints the tile
## layer whose tiles the scale has grown.
signal redraw_requested

## Poker hands to highlight: `{cells: Array[Vector2i], category: String}`.
var _hand_groups: Array = []

## The poker hand's tiles in the order they read, which bounce in sequence.
var _wave_cells: Array[Vector2i] = []

## Shared render state, assigned by `BoardView`.
var state: BoardRenderState = null

var _fade: Tween = null

## Seconds since the current reveal started, driving the bounce.
var _elapsed: float = 0.0

## True while the ripple or a chip stamp is advancing.
var _bouncing: bool = false
var _has_chip: bool = false


func _ready() -> void:
	# Decorative: pointer events pass straight through to the board.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## Reveals poker hands from this move's committed events. Edge-only awards do
## not identify a poker hand. Replacing a reveal clears the previous cue.
func reveal(events: Array) -> void:
	clear_reveal()
	for raw: Variant in events:
		if not (raw is ScoreEvent):
			continue
		var event: ScoreEvent = raw
		if event.cells.is_empty():
			continue
		if event.category == ScoringEnums.ScoreCategory.POKER_HAND:
			var cells: Array[Vector2i] = event.cells.duplicate()
			var category: String = String(event.evidence.get("category", ""))
			_hand_groups.append({"cells": cells, "category": category})
			if category == "FULL_HOUSE" or category == "FOUR_OF_A_KIND":
				_has_chip = true
			for cell: Vector2i in cells:
				if not _wave_cells.has(cell):
					_wave_cells.append(cell)
	if _hand_groups.is_empty():
		return
	if AccessibilitySettings.reduced_motion():
		# Reduced motion: hold the complete trace and hand name without movement.
		_start_hold_only()
		return
	if not _wave_cells.is_empty():
		_start_ripple()
	_restart_fade()


## Drops the reveal at once, leaving nothing drawn and no tile lifted.
##
## The screen calls this when the board is torn down, so a reveal cannot outlive
## the match it was drawn for (ADR-008 section 9).
func clear_reveal() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
	modulate.a = 1.0
	_clear_marks()


## Returns how many poker hands have an overlay. For smoke tests.
func group_count() -> int:
	return _hand_groups.size()


## Returns the tiles that bounce, in order. For smoke tests.
func wave_cells() -> Array[Vector2i]:
	return _wave_cells.duplicate()


## Returns true while anything is drawn, for smoke tests.
func has_marks() -> bool:
	return not _hand_groups.is_empty()


## Returns true while the tile ripple or chip stamp is still animating.
func is_animating() -> bool:
	return _bouncing


## Delay before online Gems travel, leaving the tile ripple readable first.
func ripple_duration() -> float:
	if AccessibilitySettings.reduced_motion() or _wave_cells.is_empty():
		return 0.0
	return maxf(TRACE_DURATION, float(_wave_cells.size() - 1) * BOUNCE_STAGGER + BOUNCE_DURATION)


func _process(delta: float) -> void:
	if not _bouncing or state == null:
		return
	_elapsed += delta
	var pops: Dictionary = {}
	for index: int in range(_wave_cells.size()):
		var scale: float = _bounce_zoom(index)
		if scale > 1.0:
			pops[_wave_cells[index]] = scale
	state.cell_zoom = pops
	if _elapsed >= maxf(ripple_duration(), CHIP_START + CHIP_DURATION if _has_chip else 0.0):
		# The wave is over: settle every tile back and stop ticking, so a
		# finished animation leaves the board exactly as the state describes it.
		_bouncing = false
		set_process(false)
		state.cell_zoom = {}
	queue_redraw()
	redraw_requested.emit()


## Returns the scale the `index`-th tile of the wave is drawn at right now.
##
## One smooth out-and-back arc per tile, so the wave reads as a pulse travelling
## along the line rather than as tiles jumping. 1.0 is rest and the value never
## falls below it, so a tile only ever grows and never shrinks into its cell.
func _bounce_zoom(index: int) -> float:
	var local: float = _elapsed - float(index) * BOUNCE_STAGGER
	if local <= 0.0 or local >= BOUNCE_DURATION:
		return 1.0
	return 1.0 + BOUNCE_ZOOM_RATIO * sin(PI * local / BOUNCE_DURATION)


func _start_ripple() -> void:
	if _wave_cells.is_empty() or state == null:
		_bouncing = false
		set_process(false)
		return
	_elapsed = 0.0
	_bouncing = true
	set_process(true)


## Holds the trace and hand label for the normal duration without animation.
func _start_hold_only() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	modulate.a = 1.0
	_bouncing = false
	set_process(false)
	queue_redraw()
	_fade = create_tween()
	_fade.tween_interval(FADE)
	_fade.tween_callback(_clear_marks)


## Fades the trace once, clearing it at the end of the two-second fade.
func _restart_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	modulate.a = 1.0
	queue_redraw()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, FADE)
	_fade.tween_callback(_clear_marks)


func _clear_marks() -> void:
	_hand_groups = []
	_wave_cells = []
	_has_chip = false
	_elapsed = 0.0
	_bouncing = false
	set_process(false)
	if state != null:
		state.cell_zoom = {}
	queue_redraw()
	redraw_requested.emit()


func _draw() -> void:
	if state == null or not state.board_rect.has_area():
		return
	var progress: float = 1.0 if AccessibilitySettings.reduced_motion() else clampf(_elapsed / TRACE_DURATION, 0.0, 1.0)
	for group: Dictionary in _hand_groups:
		var bounds: Rect2 = _hand_bounds(group)
		if not bounds.has_area():
			continue
		_draw_trace(bounds.grow(3.0), progress)
		var category: String = String(group.get("category", ""))
		if category == "FULL_HOUSE" or category == "FOUR_OF_A_KIND":
			_draw_chip(bounds, category)


func _hand_bounds(group: Dictionary) -> Rect2:
	var bounds := Rect2()
	for cell: Vector2i in group["cells"]:
		if not BoardMetrics.is_valid_cell(cell, state.grid):
			continue
		var tile_rect: Rect2 = BoardMetrics.cell_rect(state.board_rect, cell, state.grid)
		bounds = tile_rect if not bounds.has_area() else bounds.merge(tile_rect)
	return bounds


## Trace the outside of the completed line without painting over rank or edges.
func _draw_trace(bounds: Rect2, progress: float) -> void:
	var corners: Array[Vector2] = [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y), bounds.position]
	var remaining: float = 2.0 * (bounds.size.x + bounds.size.y) * progress
	var width: float = clampf(bounds.size.y * 0.035, 2.0, 3.5)
	for index: int in 4:
		var length: float = corners[index].distance_to(corners[index + 1])
		if remaining <= 0.0:
			break
		var endpoint: Vector2 = corners[index].lerp(corners[index + 1], minf(1.0, remaining / length))
		draw_line(corners[index], endpoint, Tabletop.honey(), width, true)
		remaining -= length


## A quiet tabletop chip marks only the two highest hand categories.
func _draw_chip(bounds: Rect2, category: String) -> void:
	var local: float = _elapsed - CHIP_START
	var reduced: bool = AccessibilitySettings.reduced_motion()
	if not reduced and (local < 0.0 or local >= CHIP_DURATION):
		return
	var label: String = category.replace("_", " ")
	var font: Font = Tabletop.SEMIBOLD
	var width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FONT_SIZE).x + 28.0
	var scale: float = 1.0 if reduced else lerpf(0.86, 1.0, smoothstep(0.0, 0.20, local / CHIP_DURATION))
	var opacity: float = 1.0 if reduced else 1.0 - smoothstep(0.72, 1.0, local / CHIP_DURATION)
	var center: Vector2 = bounds.get_center() + Vector2(0.0, -bounds.size.y * 0.5 - CHIP_HEIGHT * 0.6)
	if center.y - CHIP_HEIGHT * 0.5 < state.board_rect.position.y:
		center.y = bounds.end.y + CHIP_HEIGHT * 0.6
	center.x = clampf(center.x, state.board_rect.position.x + width * 0.5, state.board_rect.end.x - width * 0.5)
	var chip_rect := Rect2(center - Vector2(width, CHIP_HEIGHT) * scale * 0.5, Vector2(width, CHIP_HEIGHT) * scale)
	var fill: Color = Tabletop.honey()
	fill.a = opacity
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(14)
	style.set_border_width_all(1)
	style.border_color = Tabletop.ink()
	style.border_color.a = opacity
	draw_style_box(style, chip_rect)
	var ink: Color = Tabletop.ink()
	ink.a = opacity
	draw_string(font, Vector2(chip_rect.position.x, center.y + CHIP_FONT_SIZE * 0.34), label, HORIZONTAL_ALIGNMENT_CENTER, chip_rect.size.x, CHIP_FONT_SIZE, ink)
