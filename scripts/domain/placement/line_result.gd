class_name LineResult
extends RefCounted

## The outcome of validating one assembled line (ADR-011 sections 1 to 5).
##
## ADR-011 section 1 makes a move one line of two or more tiles in a single row or
## column, contiguous, and section 2 lets that line extend across tiles already
## committed to the board. This type is the structured answer `LineValidator`
## returns and `MoveCommitter.commit_line` fills in: a refusal names the reason
## and the cell that caused it, and an acceptance carries the line that was
## judged, so presentation and tests explain a move without re-deriving a rule
## (AGENTS.md section 19).
##
## `orientation` uses `ScoringEnums.HandOrientation`: a row is `HORIZONTAL` and a
## column is `VERTICAL`. It is -1 when no single orientation could be
## determined, so the board, the scorer, and this result share one definition of
## "one row or one column" instead of three.
##
## The counts are deliberately separate: `staged_tiles` are the tiles this move
## writes, and `merged_cells` is the line the hand is judged over, which may be
## longer because it includes committed tiles the move joins (section 2).

## True only when the line is a legal whole move.
var accepted: bool = false

## `PlacementEnums.PlacementRejection` value; `NONE` when accepted.
var rejection: int = PlacementEnums.PlacementRejection.NONE

## The cell the refusal is about; the first staged cell when it is the whole line.
var rejection_cell: Vector2i = Vector2i.ZERO

## `ScoringEnums.HandOrientation` value, or -1 when undetermined.
var orientation: int = -1

## The staged tiles in line order (row-major along the line's orientation).
var staged_tiles: Array[TileSnapshot] = []

## Every cell of the merged line, in line order, committed tiles included.
var merged_cells: Array[Vector2i] = []

## The merged line's face ranks, in line order. Empty when rejected.
var merged_ranks: Array[int] = []

## Cells whose score contribution this move can change: the merged line first in
## row-major order, then the occupied orthogonal neighbours of those cells, also
## in row-major order and de-duplicated. Empty when rejected.
var changed_cells: Array[Vector2i] = []

## Deterministic identifier of the committed move, ADR-011 section 5. Empty when
## the result came from validation alone.
var move_id: StringName = &""

## Score events the commit awarded, in the deterministic order of ADR-007
## section 7. Empty when rejected, and legitimately empty for a legal line that
## scores nothing (ADR-011 section 10 leaves scoring unchanged).
var score_events: Array[ScoreEvent] = []

## The merged line's poker category as `ScoringEnums.PokerHandCategory`, or
## `NONE` when the merged line is not five cells long. ADR-001 section 2 defines
## the categories only for a five-cell window, so a shorter line reports its
## legality (a repeated rank) rather than a category this type invents.
var hand_category: int = ScoringEnums.PokerHandCategory.NONE


## Returns how many tiles the move stages, which is the move's own tile count.
func staged_count() -> int:
	return staged_tiles.size()


## Returns the number of cells of the merged line the hand is judged over.
func merged_size() -> int:
	return merged_cells.size()


## Returns true when the move joins a line already on the board (section 2).
func is_extending_a_board_line() -> bool:
	return staged_count() > 0 and merged_size() > staged_count()


## Returns the cells the staged tiles occupy.
func staged_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for snapshot: TileSnapshot in staged_tiles:
		cells.append(snapshot.get_cell())
	return cells


## Returns the cell a presentation layer should centre the move on: the first
## staged cell in line order, or the origin when nothing is staged.
func primary_cell() -> Vector2i:
	if staged_tiles.is_empty():
		return Vector2i.ZERO
	return staged_tiles[0].get_cell()


## Returns the first staged tile of the line, or null when nothing is staged.
##
## The one-tile anchor a placement-shaped view of this move is built from; the
## line itself is `staged_tiles`.
func anchor_snapshot() -> TileSnapshot:
	if staged_tiles.is_empty():
		return null
	return staged_tiles[0]


## Returns the points this move awarded.
func get_total_points() -> int:
	var total: int = 0
	for event: ScoreEvent in score_events:
		total += event.points
	return total


## Returns true when a move identifier was recorded, which means the line was
## committed rather than merely validated.
func was_committed() -> bool:
	return accepted and not String(move_id).is_empty()


## Returns the constant name of the rejection reason, for diagnostics only.
func get_rejection_name() -> String:
	return PlacementEnums.rejection_name(rejection)


## Builds an accepted line result.
static func create_accepted(
	orientation: int,
	staged_tiles: Array[TileSnapshot],
	merged_cells: Array[Vector2i],
	merged_ranks: Array[int],
	changed_cells: Array[Vector2i],
	hand_category: int = ScoringEnums.PokerHandCategory.NONE
) -> LineResult:
	var result: LineResult = LineResult.new()
	result.accepted = true
	result.rejection = PlacementEnums.PlacementRejection.NONE
	result.orientation = orientation
	result.staged_tiles = staged_tiles.duplicate()
	result.merged_cells = merged_cells.duplicate()
	result.merged_ranks = merged_ranks.duplicate()
	result.changed_cells = changed_cells.duplicate()
	result.hand_category = hand_category
	if not result.staged_tiles.is_empty():
		result.rejection_cell = result.staged_tiles[0].get_cell()
	return result


## Builds a rejected line result carrying a structured reason.
static func create_rejected(rejection: int, cell: Vector2i) -> LineResult:
	var result: LineResult = LineResult.new()
	result.accepted = false
	result.rejection = rejection
	result.rejection_cell = cell
	result.orientation = -1
	result.staged_tiles = [] as Array[TileSnapshot]
	result.merged_cells = [] as Array[Vector2i]
	result.merged_ranks = [] as Array[int]
	result.changed_cells = [] as Array[Vector2i]
	return result


## Returns a short human-readable description, for diagnostics only.
func describe() -> String:
	if not accepted:
		return "rejected line at %s: %s" % [
			BoardEnums.cell_name(rejection_cell),
			get_rejection_name(),
		]
	return "accepted %s line of %d staged tile(s) over %d cell(s)" % [
		ScoringEnums.orientation_name(orientation),
		staged_count(),
		merged_size(),
	]
