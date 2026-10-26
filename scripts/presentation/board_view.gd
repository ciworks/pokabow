class_name BoardView
extends Control

## The 12 x 12 board, drawn (ADR-008 sections 4 and 9).
##
## `BoardView` is a thin orchestrator: it owns one `BoardRenderState`, keeps it
## centred inside whatever space the layout allots, and asks its four
## layers to redraw. Each layer reads that shared state, so the layers cannot
## disagree with each other.
##
## It owns no rules. Legal placements come from the session's frontier, legality
## of a preview arrives from the application layer, and committed tiles come from
## `BoardState`. `BoardView` never validates, never scores, and never mutates the
## board.
##
## The default viewport shows six columns and eight rows of square cells.
## Zooming out fits the full square board inside the available space.

## Space around the grid reserved for its decorative frame.
const PADDING: float = 20.0
## Distance from the sprite's outer edge to its clear interior, in source pixels.
## Source-space nine-patch margin that maps to the board's visible frame width.
const FRAME_PATCH_INSET: float = 40.0

signal zoom_changed
const CLOSE_ZOOM: float = 2.0
const OVERVIEW_ZOOM: float = 1.0
const DEFAULT_VISIBLE_CELLS: Vector2 = Vector2(6.0, 8.0)
## Keep the widest close view large enough for reliable touch placement.
const MIN_CLOSE_CELL_SIZE: float = 64.0
## Game-screen layout can fill its central window; standalone views retain 6x8.
@export var fill_available_space: bool = false
var zoom: float = CLOSE_ZOOM
var _camera_center := Vector2(0.5, 0.5)
var _last_close_zoom: float = CLOSE_ZOOM
var _canvas: Control

var _state: BoardRenderState = BoardRenderState.new()
var _frame: NinePatchRect = null

@onready var tile_layer: BoardTileLayer = %TileLayer
@onready var preview_layer: BoardPreviewLayer = %PreviewLayer
@onready var highlight_layer: BoardHighlightLayer = %HighlightLayer
@onready var cluster_layer: ClusterDisplayLayer = %ClusterDisplayLayer
@onready var reveal_layer: ScoreRevealLayer = %ScoreRevealLayer
@onready var debug_overlay: DebugOverlay = %DebugOverlay
@onready var effect_layer: BoardEffectLayer = %EffectsLayer


func _ready() -> void:
	# Pointer handling belongs to BoardInputController, which hit-tests the board
	# itself (ADR-008 section 8), so the board never swallows input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	zoom = close_zoom_for_width()
	_last_close_zoom = zoom
	resync()


## Binds the four layers and points them at the shared render state.
##
## Resolved lazily rather than only through `@onready`, because the board can be
## asked to render before its `_ready` has run: `AppRoot` attaches the controller
## as soon as the screen is in the tree (ADR-008 section 5). Re-running this is
## harmless, so both paths can call it.
func _ensure_layers() -> void:
	if _canvas == null:
		_canvas = get_node_or_null("BoardCanvas") as Control
	if _frame == null:
		_frame = get_node_or_null("BoardFrame") as NinePatchRect
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
	if cluster_layer == null:
		# Resolved by `%` first and by plain path second, like the layers above:
		# the cluster node is added under the board with a unique name, but a
		# board built without one must still bind rather than silently stop
		# drawing its persistent outlines.
		cluster_layer = get_node_or_null("%ClusterDisplayLayer") as ClusterDisplayLayer
	if cluster_layer == null:
		cluster_layer = get_node_or_null("ClusterDisplayLayer") as ClusterDisplayLayer
	if reveal_layer == null:
		reveal_layer = get_node_or_null("%ScoreRevealLayer") as ScoreRevealLayer
	if debug_overlay == null:
		debug_overlay = get_node_or_null("%DebugOverlay") as DebugOverlay
	if effect_layer == null:
		effect_layer = get_node_or_null("%EffectsLayer") as BoardEffectLayer
	if tile_layer != null:
		tile_layer.state = _state
	if preview_layer != null:
		preview_layer.state = _state
	if highlight_layer != null:
		highlight_layer.state = _state
	if cluster_layer != null:
		cluster_layer.state = _state
	if reveal_layer != null:
		reveal_layer.state = _state
		# The bounce moves tiles by writing a draw scale the tile layer reads, so the
		# board has to repaint while it runs. The layer reports each frame rather
		# than `BoardView` polling it, which keeps the animation owned by the
		# layer that started it.
		if not reveal_layer.redraw_requested.is_connected(_redraw_all):
			reveal_layer.redraw_requested.connect(_redraw_all)
	if debug_overlay != null:
		debug_overlay.state = _state
	if effect_layer != null:
		effect_layer.state = _state


## Returns the board rectangle in this control's local coordinates.
func get_board_rect() -> Rect2:
	return _state.board_rect


## Returns the board rectangle in global coordinates, for pointer hit-testing.
func global_board_rect() -> Rect2:
	var visible_rect: Rect2 = global_visible_rect()
	var camera: Rect2 = BoardMetrics.camera_rect(visible_rect.size, zoom, _camera_center)
	return Rect2(visible_rect.position + camera.position, camera.size)


## The cell side visible when the full board is zoomed out, independent of the
## current camera zoom. Used to keep the concealed rival tiles in scale with
## the board's overview grid.
func overview_cell_size() -> float:
	var overview_rect: Rect2 = BoardMetrics.fit_square(Rect2(Vector2.ZERO, size), PADDING)
	return BoardMetrics.cell_size(overview_rect, BoardEnums.BOARD_WIDTH)


## The stationary, clipped play area. UI sizing must use this, not the enlarged grid.
func global_visible_rect() -> Rect2:
	var viewport_rect: Rect2 = _viewport_rect()
	return Rect2(global_position + viewport_rect.position, viewport_rect.size)


func _viewport_rect() -> Rect2:
	var close_zoom: float = close_zoom_for_width()
	var amount: float = 0.0
	if close_zoom > OVERVIEW_ZOOM:
		amount = clampf((zoom - OVERVIEW_ZOOM) / (close_zoom - OVERVIEW_ZOOM), 0.0, 1.0)
	var close_aspect: float = DEFAULT_VISIBLE_CELLS.x / DEFAULT_VISIBLE_CELLS.y
	if fill_available_space:
		var inner: Vector2 = (size - Vector2.ONE * PADDING * 2.0).max(Vector2.ONE)
		close_aspect = maxf(0.5, inner.x / inner.y)
	var aspect: float = lerpf(1.0, close_aspect, amount)
	return BoardMetrics.fit_aspect(Rect2(Vector2.ZERO, size), aspect, PADDING)


## Uses the widest close view that keeps cells at least the mobile touch size.
## The 12-column rule still caps the result when a wider viewport has room.
func close_zoom_for_width() -> float:
	if not fill_available_space:
		return CLOSE_ZOOM
	var available_width: float = maxf(0.0, size.x - PADDING * 2.0)
	var max_visible_columns: int = mini(
		BoardEnums.BOARD_WIDTH,
		int(floor(available_width / MIN_CLOSE_CELL_SIZE))
	)
	if max_visible_columns <= 0:
		return CLOSE_ZOOM
	return clampf(
		float(BoardEnums.BOARD_WIDTH) / float(max_visible_columns),
		OVERVIEW_ZOOM,
		CLOSE_ZOOM
	)


func set_close_view(close: bool) -> void:
	var target: float = close_zoom_for_width() if close else OVERVIEW_ZOOM
	if zoom == target:
		return
	zoom = target
	if close:
		_last_close_zoom = target
	clear_drag()
	_redraw_all()
	zoom_changed.emit()


## Return to the full board and discard the previous close-view pan.
func show_centered_overview() -> void:
	_camera_center = Vector2(0.5, 0.5)
	set_close_view(false)


## An accepted placement in overview returns to the close view around that tile.
## Clamp against the new viewport so edge tiles stay as central as possible
## without exposing space outside the board. Other zoom levels stay untouched.
func focus_placed_tile(cell: Vector2i) -> void:
	if not is_equal_approx(zoom, OVERVIEW_ZOOM) or not BoardMetrics.is_valid_cell(cell, _state.grid):
		return
	zoom = close_zoom_for_width()
	_last_close_zoom = zoom
	var viewport_size: Vector2 = _viewport_rect().size
	var side: float = maxf(viewport_size.x * zoom, viewport_size.y)
	var target: Vector2 = (Vector2(cell) + Vector2.ONE * 0.5) / float(_state.grid)
	if side > 0.0:
		var half_visible: Vector2 = viewport_size / (2.0 * side)
		_camera_center = target.clamp(half_visible, Vector2.ONE - half_visible)
	clear_drag()
	_redraw_all()
	zoom_changed.emit()


## Keeps the board point beneath the old midpoint under the moving fingers.
func pinch_by(factor: float, previous_midpoint: Vector2, midpoint: Vector2) -> void:
	var visible_rect: Rect2 = global_visible_rect()
	if visible_rect.size.x <= 0.0 or factor <= 0.0:
		return
	var old_rect: Rect2 = global_board_rect()
	var anchor: Vector2 = (previous_midpoint - old_rect.position) / old_rect.size
	var previous_zoom: float = zoom
	zoom = clampf(zoom * factor, OVERVIEW_ZOOM, CLOSE_ZOOM)
	visible_rect = global_visible_rect()
	var side: float = visible_rect.size.x * zoom
	var half_visible: Vector2 = visible_rect.size / (2.0 * side)
	_camera_center = (anchor - (midpoint - visible_rect.get_center()) / side).clamp(
		half_visible, Vector2.ONE - half_visible)
	_redraw_all()
	if zoom != previous_zoom:
		zoom_changed.emit()


func pan_by(delta: Vector2) -> void:
	var side: float = global_visible_rect().size.x * zoom
	if zoom == OVERVIEW_ZOOM or side <= 0.0:
		return
	var half_visible: Vector2 = global_visible_rect().size / (2.0 * side)
	_camera_center = (_camera_center - delta / side).clamp(
		half_visible, Vector2.ONE - half_visible)
	_redraw_all()


func is_staged_cell(cell: Vector2i) -> bool:
	for tile: TileSnapshot in _state.pending_line:
		if tile.get_cell() == cell:
			return true
	return false


## Returns the cell under a global point, or `BoardMetrics.NO_CELL`.
func cell_at_global(point: Vector2) -> Vector2i:
	if not global_visible_rect().has_point(point):
		return BoardMetrics.NO_CELL
	return BoardMetrics.cell_from_point(global_board_rect(), point, BoardEnums.BOARD_WIDTH)


## Points the view at the board it should render.
func set_board(board: BoardState, preserve_camera: bool = false) -> void:
	if _state.board != board:
		_state.concealed_cells.clear()
		if not preserve_camera:
			zoom = close_zoom_for_width()
			_last_close_zoom = zoom
			_camera_center = Vector2(0.5, 0.5)
			zoom_changed.emit()
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
	# A hint belongs to one exact line: it describes the adjacencies around the
	# tile the rotate command was acting on. Once the line changes - a tile
	# staged, unstaged, moved, or rotated - those verdicts are stale, so they are
	# dropped here and the caller republishes them for the new line. Without this
	# a rotation would leave the previous orientation's marks up.
	_state.edge_match_cell = BoardMetrics.NO_CELL
	_state.edge_matches = [] as Array[bool]
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
	# No staged line means no tile to hint at, so the marks go with it.
	_state.edge_match_cell = BoardMetrics.NO_CELL
	_state.edge_matches = [] as Array[bool]
	_redraw_all()


## Shows the tile being dragged, snapped to `cell`, with the verdict for dropping
## it there (AGENTS.md section 8, ADR-011 section 11).
##
## `cell` is the board cell `BoardMetrics` derives for the pointer, so the ghost is
## drawn on the grid and a drop lands on the cell it was drawn over. Whether the
## drop is legal is the application layer's answer for this exact tile and cell, so
## the board draws a legal target and an illegal one without judging either.
##
## `BoardMetrics.NO_CELL` or a null snapshot clears the drag, because a pointer
## that is not over the board has no target to draw.
## `draw_tile` is false for deck drags: their freely moving screen overlay draws
## the tile while these board layers draw the drop-cell highlight artwork.
func show_drag(snapshot: TileSnapshot, cell: Vector2i, legal: bool, draw_scale: float = 1.0, draw_tile: bool = true) -> void:
	if snapshot == null or cell == BoardMetrics.NO_CELL:
		clear_drag()
		return
	if not BoardMetrics.is_valid_cell(cell, _state.grid):
		clear_drag()
		return
	_state.drag_snapshot = snapshot
	_state.drop_cell = cell
	_state.drag_legal = legal
	_state.drag_scale = draw_scale
	_state.drag_tile_visible = draw_tile
	_redraw_all()


## Removes the dragged tile and its target highlight, leaving the pending line and
## the committed tiles untouched.
##
## Called on every kind of drag end, which is what lets a refused release change
## nothing (ADR-011 section 5): the drag was only ever drawn, never staged.
func clear_drag() -> void:
	if _state.drag_snapshot == null and _state.drop_cell == BoardMetrics.NO_CELL:
		return
	_state.drag_snapshot = null
	_state.drop_cell = BoardMetrics.NO_CELL
	_state.drag_legal = false
	_state.drag_scale = 1.0
	_state.drag_tile_visible = true
	_redraw_all()


## Returns the dragged tile snapped to its cell, or null. For smoke tests.
func get_drag_snapshot() -> TileSnapshot:
	return _state.drag_snapshot


## Returns the board cell a drop would land on, or `BoardMetrics.NO_CELL`.
func get_drop_cell() -> Vector2i:
	return _state.drop_cell


## Returns whether dropping the dragged tile at `get_drop_cell()` is legal.
func is_drop_legal() -> bool:
	return _state.drag_legal


## Returns true while a drag target is being drawn. For smoke tests.
func has_drag() -> bool:
	return _state.has_drag()


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


## Briefly reveals scored hands and paying edge clusters from this move's events.
##
## `events` is the same authoritative list the score popups read, so a mark and
## the points beside it always describe one award. Nothing here decides what
## scored - the events are already committed (ADR-008 section 4).
func show_score_reveal(events: Array) -> void:
	_ensure_layers()
	if reveal_layer != null:
		reveal_layer.reveal(events)


## Drops the reveal immediately, leaving nothing drawn.
func clear_score_reveal() -> void:
	_ensure_layers()
	if reveal_layer != null:
		reveal_layer.clear_reveal()


## Shows the same-colour edge regions the committed board currently holds
## (AGENTS.md section 8, docs/sections/05-mobile-ux.md section 4).
##
## `clusters` arrives ready to draw: `GameSessionController.current_edge_clusters()`
## enumerated the components with `EdgeClusterScorer`, so the board outlines the
## regions the rules already recognise rather than deriving them itself (AGENTS.md
## section 19). An empty list is a valid answer and clears the marks.
##
## The regions persist until this is called again, which is what separates them
## from `show_score_reveal`: that mark answers "what did the move that just
## committed score" and fades, while this one always describes the board as it
## stands now.
func show_clusters(clusters: Array) -> void:
	_ensure_layers()
	if cluster_layer == null:
		return
	cluster_layer.show_clusters(clusters)


## Drops the persistent cluster outlines, leaving committed tiles untouched.
func clear_clusters() -> void:
	_ensure_layers()
	if cluster_layer != null:
		cluster_layer.clear_clusters()


## Shows, for one staged cell, which of its four edges currently matches the
## committed tile across it (top, right, bottom, left).
##
## The verdicts are a factual read-out of current adjacencies that
## `GameSessionController.staged_edge_matches` derived from `EdgeMatchScorer`;
## the board carries them and the preview layer draws them, but neither decides
## them, so the hint cannot become a score prediction (AGENTS.md sections 2 and
## 19).
##
## `BoardMetrics.NO_CELL` clears the hint, because a hint with no cell has
## nothing to attach its marks to.
func show_edge_matches(cell: Vector2i, matches: Array[bool]) -> void:
	_ensure_layers()
	if cell == BoardMetrics.NO_CELL:
		clear_edge_matches()
		return
	_state.edge_match_cell = cell
	_state.edge_matches = matches.duplicate()
	_redraw_all()


## Removes the rotation hint, leaving the staged line untouched.
func clear_edge_matches() -> void:
	_ensure_layers()
	if _state.edge_match_cell == BoardMetrics.NO_CELL and _state.edge_matches.is_empty():
		return
	_state.edge_match_cell = BoardMetrics.NO_CELL
	_state.edge_matches = [] as Array[bool]
	_redraw_all()


## Rebuilds every layer from authoritative state.
##
## ADR-008 section 9 requires an interrupted or skipped animation to
## resynchronize immediately: this discards all visual interpolation, because the
## layers hold no state of their own to unwind.
func resync() -> void:
	_recompute_rect()
	# Tearing the board down drops any reveal with it, so a mark cannot outlive
	# the match it was drawn for. A rebuild during play keeps the reveal: it is
	# driven by committed score events, which a redraw does not change.
	if _state.board == null:
		clear_score_reveal()
		# A persistent outline is a statement about a board, so tearing the board
		# down drops it and the hint with it: neither mark may outlive the match
		# whose state it described.
		clear_clusters()
		clear_edge_matches()
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
	var next_close_zoom: float = close_zoom_for_width()
	if is_equal_approx(zoom, _last_close_zoom):
		zoom = next_close_zoom
	_last_close_zoom = next_close_zoom
	resync()


## Recomputes the square board area for the current control size.
func _recompute_rect() -> void:
	var viewport_rect: Rect2 = _viewport_rect()
	_state.board_rect = BoardMetrics.camera_rect(viewport_rect.size, zoom, _camera_center)
	if _canvas != null:
		_canvas.position = viewport_rect.position
		_canvas.size = viewport_rect.size
	if _frame != null:
		var frame_rect: Rect2 = viewport_rect.grow(PADDING)
		# Scale the source corners uniformly; nine-patch stretches only the rails.
		var frame_scale: float = PADDING / FRAME_PATCH_INSET
		_frame.scale = Vector2.ONE * frame_scale
		_frame.position = frame_rect.position
		_frame.size = frame_rect.size / frame_scale
		_frame.visible = _state.board != null and _state.board_rect.has_area()


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
	if cluster_layer != null:
		# Repainted on every redraw rather than only when the clusters are
		# republished: the marks resolve their geometry from the board rectangle,
		# so a refit or a resize has to move them with the tiles they outline.
		cluster_layer.queue_redraw()
	if reveal_layer != null:
		reveal_layer.queue_redraw()
	if debug_overlay != null:
		debug_overlay.queue_redraw()
	if effect_layer != null:
		effect_layer.queue_redraw()


## Conceal only the presentation of tiles currently flying to their committed cells.
func set_concealed_cells(cells: Array[Vector2i]) -> void:
	if _state.concealed_cells == cells:
		return
	_state.concealed_cells = cells.duplicate()
	if tile_layer != null:
		tile_layer.queue_redraw()


func tile_global_rect(cell: Vector2i) -> Rect2:
	var rect: Rect2 = BoardMetrics.cell_rect(global_board_rect(), cell, BoardEnums.BOARD_WIDTH)
	if rect.size.x <= BoardTileLayer.CELL_INSET * 2.0 or rect.size.y <= BoardTileLayer.CELL_INSET * 2.0:
		return Rect2()
	return rect.grow(-BoardTileLayer.CELL_INSET)


## Keep an arriving rival line visible, including moves near the board edges.
func reveal_cells(cells: Array[Vector2i]) -> void:
	if cells.is_empty() or not tile_global_rect(cells[0]).has_area():
		return
	var visible: Rect2 = global_visible_rect().grow(1.0)
	var all_visible: bool = true
	for cell: Vector2i in cells:
		all_visible = all_visible and visible.encloses(tile_global_rect(cell))
	if all_visible:
		return
	var low: Vector2 = Vector2(cells[0])
	var high: Vector2 = low
	for cell: Vector2i in cells:
		low = low.min(Vector2(cell))
		high = high.max(Vector2(cell))
	_camera_center = (low + high + Vector2.ONE) * 0.5 / float(BoardEnums.BOARD_WIDTH)
	_redraw_all()
	for cell: Vector2i in cells:
		if not global_visible_rect().grow(1.0).encloses(tile_global_rect(cell)):
			set_close_view(false)
			break
