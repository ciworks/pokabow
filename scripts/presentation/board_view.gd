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


## Shows the ghost of a pending placement, legal or not.
func show_preview(snapshot: TileSnapshot, valid: bool, reason: String) -> void:
	_state.pending = snapshot
	_state.pending_valid = valid
	_state.pending_reason = reason
	_redraw_all()


## Removes the preview, leaving committed tiles untouched.
func clear_preview() -> void:
	_state.pending = null
	_state.pending_valid = false
	_state.pending_reason = ""
	_redraw_all()


## Marks where the most recent tile landed.
func mark_committed(cell: Vector2i) -> void:
	_state.last_committed_cell = cell
	_redraw_all()


## Rebuilds every layer from authoritative state.
##
## ADR-008 section 9 requires an interrupted or skipped animation to
## resynchronize immediately: this discards all visual interpolation, because the
## layers hold no state of their own to unwind.
func resync() -> void:
	_recompute_rect()
	_redraw_all()


## Returns the previewed snapshot, or null. For smoke tests and diagnostics.
func get_pending_snapshot() -> TileSnapshot:
	return _state.pending


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
	if tile_layer != null:
		tile_layer.queue_redraw()
	if preview_layer != null:
		preview_layer.queue_redraw()
	if highlight_layer != null:
		highlight_layer.queue_redraw()
	if effect_layer != null:
		effect_layer.queue_redraw()
