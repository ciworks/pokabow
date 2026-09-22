class_name BoardView
extends Control

## The 12 x 12 board, drawn (ADR-008 sections 4 and 9).
##
## `BoardView` is a thin orchestrator: it owns one `BoardRenderState`, keeps it
## square and centred inside whatever space the layout allots, and asks its four
## layers to redraw. Each layer reads that shared state, so the layers cannot
## disagree with each other.
##
## It owns no rules. Legal placements come from the session's frontier, legality
## of a preview arrives from the application layer, and committed tiles come from
## `BoardState`. `BoardView` never validates, never scores, and never mutates the
## board.
##
## Responsiveness is a pure calculation (`BoardMetrics.fit_square`), so the board
## stays square and inside safe bounds on any viewport - a 1280x720 desktop
## window or a landscape phone.

## Gap in pixels kept between the board and the edge of the allotted space.
const PADDING: float = 14.0

var _state: BoardRenderState = BoardRenderState.new()

@onready var tile_layer: BoardTileLayer = %TileLayer
@onready var preview_layer: BoardPreviewLayer = %PreviewLayer
@onready var highlight_layer: BoardHighlightLayer = %HighlightLayer
@onready var effect_layer: BoardEffectLayer = %EffectsLayer


func _ready() -> void:
	# Pointer handling belongs to BoardInputController, which hit-tests the board
	# itself (ADR-008 section 8), so the board never swallows input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	resync()


## Binds the four layers and points them at the shared render state.
##
## Resolved lazily rather than only through `@onready`, because the board can be
## asked to render before its `_ready` has run: `AppRoot` attaches the controller
## as soon as the screen is in the tree (ADR-008 section 5). Re-running this is
## harmless, so both paths can call it.
func _ensure_layers() -> void:
	# The resize hook is established here as well as in `_ready`, because this
	# runs from every redraw path. A board that was asked to render before its
	# `_ready` ran would otherwise keep the rectangle it fitted at that moment and
	# draw the pending line against a stale board area, which is the same trap the
	# layer binding below exists to avoid. Connecting twice is harmless.
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	if tile_layer == null:
		tile_layer = get_node_or_null("%TileLayer") as BoardTileLayer
	if preview_layer == null:
		preview_layer = get_node_or_null("%PreviewLayer") as BoardPreviewLayer
	if highlight_layer == null:
		highlight_layer = get_node_or_null("%HighlightLayer") as BoardHighlightLayer
	if effect_layer == null:
		effect_layer = get_node_or_null("%EffectsLayer") as BoardEffectLayer
	if tile_layer != null:
		tile_layer.state = _state
	if preview_layer != null:
		preview_layer.state = _state
	if highlight_layer != null:
		highlight_layer.state = _state
	if effect_layer != null:
		effect_layer.state = _state


## Returns the board rectangle in this control's local coordinates.
func get_board_rect() -> Rect2:
	return _state.board_rect


## Returns the board rectangle in global coordinates, for pointer hit-testing.
func global_board_rect() -> Rect2:
	return BoardMetrics.fit_square(Rect2(global_position, size), PADDING)


## Returns the cell under a global point, or `BoardMetrics.NO_CELL`.
func cell_at_global(point: Vector2) -> Vector2i:
	return BoardMetrics.cell_from_point(global_board_rect(), point, BoardEnums.BOARD_WIDTH)


## Points the view at the board it should render.
func set_board(board: BoardState) -> void:
	_state.board = board
	resync()


## Gates frontier highlighting on the human action phase (ADR-008 section 8).
func set_human_turn(enabled: bool) -> void:
	if _state.human_turn == enabled:
		return
	_state.human_turn = enabled
	_redraw_all()


## Shows the ghost of the pending line, legal or not (ADR-011 section 11).
##
## `snapshots` is every staged tile in staging order; the last entry is the tile
## the rotate command acts on, which the preview layer marks. A single-tile call
## is a valid pending line of one: ADR-011 section 1 requires two tiles for a
## move, and `valid` says whether the line as it stands satisfies that.
func show_line(snapshots: Array[TileSnapshot], valid: bool, reason: String) -> void:
	var line: Array[TileSnapshot] = []
	for snapshot: TileSnapshot in snapshots:
		if snapshot != null:
			line.append(snapshot)
	_state.pending_line = line
	var first: TileSnapshot = null
	if not line.is_empty():
		first = line[0]
	_state.pending = first
	_state.pending_valid = valid
	_state.pending_reason = reason
	_redraw_all()


## Shows the ghost of a single pending placement.
##
## A one-tile pending line. Kept because a caller that previews one tile is still
## assembling the same staged line (ADR-011 section 1: the first tile of a line
## starts it).
func show_preview(snapshot: TileSnapshot, valid: bool, reason: String) -> void:
	var line: Array[TileSnapshot] = []
	if snapshot != null:
		line.append(snapshot)
	show_line(line, valid, reason)


## Removes the preview, leaving committed tiles untouched.
func clear_preview() -> void:
	_state.pending_line = []
	_state.pending = null
	_state.pending_valid = false
	_state.pending_reason = ""
	_redraw_all()


## Marks where the most recent tile landed.
func mark_committed(cell: Vector2i) -> void:
	_state.last_committed_cell = cell
	_state.last_committed_cells = [cell]
	_redraw_all()


## Marks every cell the most recent committed move wrote.
##
## ADR-011 section 1 makes a move a whole line, so the highlight marks the line
## rather than only its anchor; the anchor is still the first cell, so a caller
## that asks for one cell keeps getting the move's primary cell.
func mark_committed_line(cells: Array[Vector2i]) -> void:
	var line: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if not line.has(cell):
			line.append(cell)
	_state.last_committed_cells = line
	_state.last_committed_cell = line[0] if not line.is_empty() else BoardMetrics.NO_CELL
	_redraw_all()


## Returns every cell the most recent committed move wrote, as the board is
## drawing them. For smoke tests and diagnostics.
func get_last_committed_cells() -> Array[Vector2i]:
	return _state.last_committed_cells.duplicate()


## Rebuilds every layer from authoritative state.
##
## ADR-008 section 9 requires an interrupted or skipped animation to
## resynchronize immediately: this discards all visual interpolation, because the
## layers hold no state of their own to unwind.
func resync() -> void:
	_recompute_rect()
	_redraw_all()


## Returns the previewed snapshot (the pending line's first tile), or null.
## For smoke tests and diagnostics.
func get_pending_snapshot() -> TileSnapshot:
	return _state.pending


## Returns every tile of the pending line in staging order, as the board is
## drawing them. For smoke tests and diagnostics.
func get_pending_line() -> Array[TileSnapshot]:
	return _state.pending_line.duplicate()


## Returns how many tiles the board is drawing as the pending line. For smoke
## tests.
func get_pending_count() -> int:
	return _state.pending_count()


## Returns whether the current preview is legal. For smoke tests.
func is_pending_valid() -> bool:
	return _state.pending_valid


## Returns why the current preview is illegal. For smoke tests.
func get_pending_reason() -> String:
	return _state.pending_reason


## Returns the last committed cell. For smoke tests.
func get_last_committed_cell() -> Vector2i:
	return _state.last_committed_cell


func _on_resized() -> void:
	resync()


## Recomputes the square board area for the current control size.
func _recompute_rect() -> void:
	_state.board_rect = BoardMetrics.fit_square(Rect2(Vector2.ZERO, size), PADDING)


func _redraw_all() -> void:
	# Binding here as well as in `_ready` keeps a render request made before the
	# view is ready from dereferencing a null layer.
	_ensure_layers()
	# The rect is refitted on every redraw, so the drawn board follows the size
	# the layout has actually given this control. Fitting it only in `_ready` and
	# on `resized` means a board that was drawn before its `_ready` ran keeps the
	# rectangle it fitted at that moment and draws its tiles against a stale area,
	# while `global_board_rect()` - which hit-tests every gesture - recomputes from
	# the live size. Refitting here keeps the drawn board and the tappable board
	# the same rectangle.
	_recompute_rect()
	if tile_layer != null:
		tile_layer.queue_redraw()
	if preview_layer != null:
		preview_layer.queue_redraw()
	if highlight_layer != null:
		highlight_layer.queue_redraw()
	if effect_layer != null:
		effect_layer.queue_redraw()
