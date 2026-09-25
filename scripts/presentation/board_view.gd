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
func show_drag(snapshot: TileSnapshot, cell: Vector2i, legal: bool) -> void:
	if snapshot == null or cell == BoardMetrics.NO_CELL:
		clear_drag()
		return
	if not BoardMetrics.is_valid_cell(cell, _state.grid):
		clear_drag()
		return
	_state.drag_snapshot = snapshot
	_state.drop_cell = cell
	_state.drag_legal = legal
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


## Reveals what the given committed score events awarded: the matching edge
## boundaries and the paying colour clusters (AGENTS.md section 8, Milestone 8).
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
