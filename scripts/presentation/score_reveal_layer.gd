class_name ScoreRevealLayer
extends Control

## Briefly shows committed poker-hand and edge-cluster awards (AGENTS.md section 8,
## GAME_SPEC section 7.3, docs/sections/05-mobile-ux.md section 4).
##
## The layer outlines the scored hands and paying edge clusters for the latest
## move. Poker hands also bounce; floating score popups report their points.
##
## ADR-008 section 4 keeps presentation out of the rules, so this layer is handed
## finished `ScoreEvent`s and reads only what they already carry: `cells` and the
## colour in `evidence` (ADR-002 section 7 records both). It never reads
## `BoardState`, never re-derives a match, and never decides what scored, so the
## reveal can only ever show an award that was really made - which is also why a
## refused placement reveals nothing.
##
## The bounce moves a tile on screen without moving the board: a draw scale is
## written into the shared render state, which `BoardTileLayer` reads, and is
## cleared when the animation ends or the reveal is dropped.

## Total lifetime: fade from full visibility to hidden over three seconds.
const FADE: float = 3.0

## Perimeter stroke thickness, half the former hand-tile border width.
const OUTLINE_RATIO: float = 0.055

## How much bigger a bouncing tile grows at the peak, as a fraction of its size.
##
## The board is 2D, so the Z axis is expressed as scale: growing about the cell's
## centre reads as the tile rising toward the viewer. A positional hop would read
## as sliding across the grid, which could be mistaken for a different cell.
const BOUNCE_ZOOM_RATIO: float = 0.30

## How long one tile's bounce lasts, in seconds.
const BOUNCE_DURATION: float = 0.34

## Gap between one tile starting its bounce and the next, in seconds.
const BOUNCE_STAGGER: float = 0.13

## Green perimeter around the tiles that scored.
const REVEAL_COLOR: Color = Color(0.25, 0.92, 0.42, 1.0)

## Emitted every frame while the bounce runs, so `BoardView` repaints the tile
## layer whose tiles the scale has grown.
signal redraw_requested

## Scored groups to outline: `{cells: Array[Vector2i]}`, one entry per award.
var _groups: Array = []

## The poker hand's tiles in the order they read, which bounce in sequence.
var _wave_cells: Array[Vector2i] = []

## Shared render state, assigned by `BoardView`.
var state: BoardRenderState = null

var _fade: Tween = null

## Seconds since the current reveal started, driving the bounce.
var _elapsed: float = 0.0

## True while the bounce is advancing, so `_process` is not left running.
var _bouncing: bool = false


func _ready() -> void:
	# Decorative: pointer events pass straight through to the board.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## Reveals only the hands and edge clusters in this move's committed events.
## Replacing a reveal cancels its timer, even when the new move scored nothing.
func reveal(events: Array) -> void:
	clear_reveal()
	for raw: Variant in events:
		if not (raw is ScoreEvent):
			continue
		var event: ScoreEvent = raw
		if event.cells.is_empty():
			continue
		if event.category == ScoringEnums.ScoreCategory.POKER_HAND:
			_wave_cells.append_array(event.cells)
		elif event.category != ScoringEnums.ScoreCategory.EDGE_CLUSTER:
			# Individual edge-match points do not outline a tile group.
			continue
		_groups.append({"cells": event.cells.duplicate()})
	if _groups.is_empty() and _wave_cells.is_empty():
		return
	if AccessibilitySettings.reduced_motion():
		# Reduced motion: the marks still appear. Which tiles scored is
		# information, not decoration, so suppressing it would take away the
		# answer rather than the movement - what goes is the bounce and the
		# fade, which are the two animations the player asked to be spared.
		_start_hold_only()
		return
	if not _wave_cells.is_empty():
		_start_bounce()
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


## Returns how many scored groups are outlined. For smoke tests.
func group_count() -> int:
	return _groups.size()


## Returns the tiles that bounce, in order. For smoke tests.
func wave_cells() -> Array[Vector2i]:
	return _wave_cells.duplicate()


## Returns true while anything is drawn, for smoke tests.
func has_marks() -> bool:
	return not _groups.is_empty()


func _process(delta: float) -> void:
	if not _bouncing or state == null:
		return
	_elapsed += delta
	var pops: Dictionary = {}
	var running: bool = false
	for index: int in range(_wave_cells.size()):
		var scale: float = _bounce_zoom(index)
		if scale > 1.0:
			pops[_wave_cells[index]] = scale
		if _elapsed - float(index) * BOUNCE_STAGGER < BOUNCE_DURATION:
			running = true
	state.cell_zoom = pops
	if not running:
		# The wave is over: settle every tile back and stop ticking, so a
		# finished animation leaves the board exactly as the state describes it.
		_bouncing = false
		set_process(false)
		state.cell_zoom = {}
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


func _start_bounce() -> void:
	if _wave_cells.is_empty() or state == null:
		_bouncing = false
		set_process(false)
		return
	_elapsed = 0.0
	_bouncing = true
	set_process(true)


## Holds the marks for the usual time and then clears them without animating
## anything, for a player who has asked for reduced motion.
##
## The timer is still a tween, but it animates no property: it waits and then
## calls `_clear_marks`. That keeps the marks on screen for exactly as long as
## the animated reveal does, so the player is not rushed to read which tiles
## scored, while the opacity stays at full and no tile ever moves.
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


## Each new move starts fully visible and fades once, without a hold or loop.
func _restart_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	modulate.a = 1.0
	queue_redraw()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, FADE)
	_fade.tween_callback(_clear_marks)


func _clear_marks() -> void:
	_groups = []
	_wave_cells = []
	_bouncing = false
	set_process(false)
	if state != null:
		state.cell_zoom = {}
	queue_redraw()
	redraw_requested.emit()


func _draw() -> void:
	if state == null or not state.board_rect.has_area():
		return
	var line: float = maxf(
		1.0, BoardMetrics.cell_size(state.board_rect, state.grid) * OUTLINE_RATIO
	)
	for group: Dictionary in _groups:
		_outline_group(group["cells"], line)


## Draws the outside perimeter of one scored group.
##
## Shared sides between tiles in the same group are omitted, so joined hands read
## as one shape instead of showing borders on their touching edges.
func _outline_group(cells: Array, line: float) -> void:
	var members: Dictionary = {}
	for raw: Variant in cells:
		var candidate: Vector2i = raw
		if BoardMetrics.is_valid_cell(candidate, state.grid):
			members[candidate] = true
	if members.is_empty():
		return
	var offsets: Array[Vector2i] = BoardEnums.neighbor_offsets()
	for raw: Variant in members.keys():
		var cell: Vector2i = raw
		var rect: Rect2 = BoardMetrics.cell_rect(state.board_rect, cell, state.grid)
		var scale: float = state.zoom_for(cell)
		if scale > 1.0:
			var grown: Vector2 = rect.size * scale
			rect = Rect2(rect.get_center() - grown * 0.5, grown)
		var inner: Rect2 = rect.grow(-line * 0.5)
		var top_left: Vector2 = inner.position
		var top_right: Vector2 = Vector2(inner.end.x, inner.position.y)
		var bottom_left: Vector2 = Vector2(inner.position.x, inner.end.y)
		var bottom_right: Vector2 = inner.end
		if not members.has(cell + offsets[TileEnums.EdgePosition.TOP]):
			draw_line(top_left, top_right, REVEAL_COLOR, line)
		if not members.has(cell + offsets[TileEnums.EdgePosition.RIGHT]):
			draw_line(top_right, bottom_right, REVEAL_COLOR, line)
		if not members.has(cell + offsets[TileEnums.EdgePosition.BOTTOM]):
			draw_line(bottom_left, bottom_right, REVEAL_COLOR, line)
		if not members.has(cell + offsets[TileEnums.EdgePosition.LEFT]):
			draw_line(top_left, bottom_left, REVEAL_COLOR, line)
