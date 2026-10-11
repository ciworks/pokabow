class_name DebugOverlay
extends Control

## Development diagnostics drawn over the board (AGENTS.md section 17;
## Milestone 7's development overlays).
##
## This layer exists so a reported bug can be diagnosed from one screen. It draws
## the board's own coordinates, the legal frontier, the score events the last move
## produced, and the opponent's analysis
## state.
##
## Every value is read from authoritative state - `BoardRenderState` for the
## geometry and the last move, `BoardState` for the frontier and revision, the
## committed move history for the move record, the `AiCoordinator` for the
## rival's status, and the score events the screen was handed - so the overlay
## reports what the game actually decided rather than recalculating a rule
## (AGENTS.md section 19).
##
## It is development tooling, not part of play. It starts hidden, opens on the
## `debug/overlays` project setting or the toggle key, and it is read-only: no
## path here mutates the session, the board, the ledger, or the turn, so leaving
## it open cannot change a match.

## Project setting that opens the overlay at boot.
##
## Read with a false default, so a project that never sets it never shows the
## overlay and nothing has to be written to project.godot for the normal case.
const SETTING_PATH: String = "debug/overlays"

## Key that toggles the overlay during play.
const TOGGLE_KEY: int = KEY_F3

## Key that exports a replayable bug-report fixture (Milestone 7).
##
## Bound here rather than in the player-facing UI for the same reason the overlay
## exists at all: it is development tooling, so it must not be reachable in a
## normal session (AGENTS.md section 17).
const EXPORT_KEY: int = KEY_F4

## Coordinate label size, in pixels.
const COORD_FONT_SIZE: int = 10

## Coordinate label colour. Dim, so it never competes with the tile face under it.
const COORD_COLOR: Color = Color(0.75, 0.85, 1.0, 0.55)

## Outline colour of a cell the active player may legally choose.
const FRONTIER_COLOR: Color = Color(1.0, 0.35, 0.85, 0.9)

## Outline colour of a cell the last committed move wrote.
## Diagnostic text block.
const PANEL_BG: Color = Color(0.02, 0.03, 0.05, 0.82)
const PANEL_TEXT: Color = Color(0.72, 0.96, 0.78, 1.0)
const PANEL_FONT_SIZE: int = 12
const PANEL_PADDING: float = 6.0
const PANEL_LINE_HEIGHT: float = 15.0

## Outline thickness of a marked cell, in pixels.
const MARK_WIDTH: float = 2.0

## Shared render state, assigned by `BoardView`.
var state: BoardRenderState = null

## The application-layer controller the diagnostics are read from, assigned by
## `GameScreen`. Null before a match is composed, which is why every read below
## is guarded.
var controller: GameSessionController = null

## Score events of the most recent award, as the screen received them.
##
## Presentation only: the ledger stays the authority, and this is a copy kept so
## the panel can report the last move's scoring without recomputing it.
var last_events: Array = []

var _enabled: bool = false


func _ready() -> void:
	# Decorative: the overlay must never take a gesture away from the board.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enabled = bool(ProjectSettings.get_setting(SETTING_PATH, false))


## Opens or closes the overlay and repaints.
func set_enabled(value: bool) -> void:
	if _enabled == value:
		return
	_enabled = value
	queue_redraw()


## Returns whether the overlay is drawing.
func is_enabled() -> bool:
	return _enabled


## Records the score events of the latest award for the diagnostic panel.
func set_last_events(events: Array) -> void:
	last_events = events.duplicate()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	if key.keycode == TOGGLE_KEY:
		set_enabled(not _enabled)
		return
	if key.keycode == EXPORT_KEY and controller != null:
		# The export writes a file and mutates nothing, so a mistyped key cannot
		# change the match. The outcome arrives through the controller's own
		# notice channel rather than being decided here.
		controller.export_fixture()


func _draw() -> void:
	if not _enabled or state == null or not state.board_rect.has_area():
		return
	_draw_coords()
	_draw_frontier()
	_draw_panel()


## Draws the coordinate of every cell, so a bug report can name a cell exactly.
func _draw_coords() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	for y: int in range(state.grid):
		for x: int in range(state.grid):
			var rect: Rect2 = BoardMetrics.cell_rect(
				state.board_rect, Vector2i(x, y), state.grid
			)
			draw_string(
				font,
				rect.position + Vector2(2.0, float(COORD_FONT_SIZE)),
				"%d,%d" % [x, y],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				COORD_FONT_SIZE,
				COORD_COLOR
			)


## Outlines every cell the active player may legally choose (ADR-006 section 7).
##
## The frontier comes from `BoardState`, which owns it as a derived index, so the
## overlay marks the cells the rules offer rather than deciding legality itself.
func _draw_frontier() -> void:
	if controller == null or state.board == null:
		return
	_outline_cells(state.board.get_frontier_cells(), FRONTIER_COLOR)


## Outlines each cell of `cells` just inside its own slot.
func _outline_cells(cells: Array, color: Color) -> void:
	for raw: Variant in cells:
		var cell: Vector2i = raw
		if not BoardMetrics.is_valid_cell(cell, state.grid):
			continue
		var rect: Rect2 = BoardMetrics.cell_rect(state.board_rect, cell, state.grid)
		draw_rect(rect.grow(-MARK_WIDTH * 0.5), color, false, MARK_WIDTH)


## Draws the diagnostic text block over the board's top-left corner.
func _draw_panel() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var lines: PackedStringArray = _diagnostic_lines()
	if lines.is_empty():
		return
	var width: float = 0.0
	for line: String in lines:
		width = maxf(
			width,
			font.get_string_size(
				line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, PANEL_FONT_SIZE
			).x
		)
	var panel: Rect2 = Rect2(
		state.board_rect.position + Vector2(2.0, 2.0),
		Vector2(
			width + PANEL_PADDING * 2.0,
			float(lines.size()) * PANEL_LINE_HEIGHT + PANEL_PADDING * 2.0
		)
	)
	draw_rect(panel, PANEL_BG, true)
	var baseline: float = panel.position.y + PANEL_PADDING + float(PANEL_FONT_SIZE)
	for line: String in lines:
		draw_string(
			font,
			Vector2(panel.position.x + PANEL_PADDING, baseline),
			line,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			PANEL_FONT_SIZE,
			PANEL_TEXT
		)
		baseline += PANEL_LINE_HEIGHT


## Returns the diagnostic lines, each read from authoritative state.
func _diagnostic_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if state.board != null:
		lines.append(
			"board rev %d  cells %d/%d  frontier %d"
			% [
				state.board.get_revision(),
				state.board.occupied_count(),
				BoardEnums.CELL_COUNT,
				state.board.get_frontier_cells().size(),
			]
		)
	if controller != null:
		var session: GameSessionState = controller.get_session()
		if session != null:
			var move: ScoringMove = session.last_move()
			if move == null:
				lines.append("last move: none")
			else:
				lines.append(
					"last move %s turn %d  %d tile(s)"
					% [String(move.move_id), move.move_number, move.placement_count()]
				)
			lines.append(
				"human %d  rival %d  turn %d  pot %d"
				% [
					controller.human_score(),
					controller.ai_score(),
					controller.turn_number(),
					controller.remaining_tiles(),
				]
			)
		var coordinator: AiCoordinator = controller.get_ai_coordinator()
		if coordinator != null:
			lines.append(
				"ai %s  %s  thinking=%s"
				% [
					AiEnums.difficulty_name(coordinator.difficulty()),
					coordinator.status_name(),
					str(coordinator.is_thinking()),
				]
			)
	lines.append(_event_summary())
	return lines


## Returns one line totalling the latest award by scoring category.
##
## The three categories are the whole of ADR-002 and ADR-007's Phase 1 award set,
## so a category that is missing from the events was not awarded.
func _event_summary() -> String:
	if last_events.is_empty():
		return "last award: none"
	var poker: int = 0
	var edge: int = 0
	var cluster: int = 0
	for raw: Variant in last_events:
		if not (raw is ScoreEvent):
			continue
		var event: ScoreEvent = raw
		match event.category:
			ScoringEnums.ScoreCategory.POKER_HAND:
				poker += event.points
			ScoringEnums.ScoreCategory.EDGE_MATCH:
				edge += event.points
			ScoringEnums.ScoreCategory.EDGE_CLUSTER:
				cluster += event.points
	return "last award: poker %d  edge %d  cluster %d" % [poker, edge, cluster]
