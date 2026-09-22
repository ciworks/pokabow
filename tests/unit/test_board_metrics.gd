extends TestCase

## Board geometry tests (ADR-008 sections 4, 8, and 13).
##
## These are pure functions, so the responsive-fit and pointer-mapping behaviour
## ADR-008 section 13 asks scene smoke tests to cover can be verified headlessly
## and exactly, instead of by eyeballing a layout.
##
## The cases deliberately cover a desktop window (1280 x 720), a wider display,
## and a portrait phone, because the board must stay a centred square on all of
## them.

const DESKTOP: Vector2 = Vector2(1280.0, 720.0)
const WIDE: Vector2 = Vector2(1920.0, 900.0)
const PORTRAIT: Vector2 = Vector2(400.0, 800.0)


func test_the_board_stays_a_centred_square_on_every_viewport() -> void:
	var viewports: Array[Vector2] = [DESKTOP, WIDE, PORTRAIT, Vector2(1440.0, 1440.0)]
	for viewport_size: Vector2 in viewports:
		var available: Rect2 = Rect2(Vector2.ZERO, viewport_size)
		var board: Rect2 = BoardMetrics.fit_square(available, 14.0)

		check_eq(
			snappedf(board.size.x, 0.001),
			snappedf(board.size.y, 0.001),
			"the board must be square on a %s viewport" % str(viewport_size)
		)
		check(
			board.size.x > 0.0,
			"the board must have a positive side on a %s viewport" % str(viewport_size)
		)
		check(
			available.encloses(board),
			"the board must fit inside a %s viewport" % str(viewport_size)
		)

		# Centred: equal gaps on each axis.
		var left_gap: float = board.position.x - available.position.x
		var right_gap: float = available.end.x - board.end.x
		var top_gap: float = board.position.y - available.position.y
		var bottom_gap: float = available.end.y - board.end.y
		check(
			absf(left_gap - right_gap) < 0.001,
			"the board must be horizontally centred on a %s viewport" % str(viewport_size)
		)
		check(
			absf(top_gap - bottom_gap) < 0.001,
			"the board must be vertically centred on a %s viewport" % str(viewport_size)
		)


func test_padding_keeps_the_board_clear_of_the_edges() -> void:
	var available: Rect2 = Rect2(Vector2.ZERO, DESKTOP)
	var padded: Rect2 = BoardMetrics.fit_square(available, 20.0)

	check(
		padded.position.x >= 20.0 - 0.001 and padded.position.y >= 20.0 - 0.001,
		"padding must be honoured on the leading edges"
	)
	check(
		available.end.x - padded.end.x >= 20.0 - 0.001,
		"padding must be honoured on the trailing edge"
	)


func test_every_cell_round_trips_through_its_centre_point() -> void:
	var board: Rect2 = BoardMetrics.fit_square(Rect2(Vector2.ZERO, DESKTOP), 14.0)
	var samples: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(5, 5),
		Vector2i(6, 6),
		Vector2i(11, 11),
		Vector2i(0, 11),
		Vector2i(11, 0),
	]

	for cell: Vector2i in samples:
		var centre: Vector2 = BoardMetrics.cell_center(board, cell)
		check_eq(
			BoardMetrics.cell_from_point(board, centre),
			cell,
			"the centre of %s must map back to %s" % [BoardEnums.cell_name(cell), BoardEnums.cell_name(cell)]
		)


func test_a_cell_covers_every_point_inside_it() -> void:
	var board: Rect2 = BoardMetrics.fit_square(Rect2(Vector2.ZERO, DESKTOP), 14.0)
	var side: float = BoardMetrics.cell_size(board)
	var cell: Vector2i = Vector2i(7, 3)
	var origin: Vector2 = BoardMetrics.cell_rect(board, cell).position

	# Just inside the cell's own corners.
	var probes: Array[Vector2] = [
		origin + Vector2(0.5, 0.5),
		origin + Vector2(side - 0.5, 0.5),
		origin + Vector2(0.5, side - 0.5),
		origin + Vector2(side - 0.5, side - 0.5),
	]
	for probe: Vector2 in probes:
		check_eq(
			BoardMetrics.cell_from_point(board, probe),
			cell,
			"every point inside the cell must resolve to that cell"
		)


func test_points_off_the_board_report_no_cell() -> void:
	var board: Rect2 = BoardMetrics.fit_square(Rect2(Vector2.ZERO, DESKTOP), 14.0)

	var outside: Array[Vector2] = [
		board.position - Vector2(1.0, 0.0),
		board.position - Vector2(0.0, 1.0),
		board.position - Vector2(5.0, 5.0),
		Vector2(board.end.x, board.position.y),
		Vector2(board.position.x, board.end.y),
		board.end + Vector2(1.0, 1.0),
	]
	for point: Vector2 in outside:
		check_eq(
			BoardMetrics.cell_from_point(board, point),
			BoardMetrics.NO_CELL,
			"a point outside the board must not resolve to a cell: %s" % str(point)
		)


func test_cell_size_divides_the_board_exactly() -> void:
	var board: Rect2 = BoardMetrics.fit_square(Rect2(Vector2.ZERO, DESKTOP), 14.0)
	var side: float = BoardMetrics.cell_size(board)

	check(
		absf(side * float(BoardEnums.BOARD_WIDTH) - board.size.x) < 0.001,
		"twelve cells must span the board exactly"
	)
	check(
		absf(BoardMetrics.cell_rect(board, Vector2i(11, 11)).end.x - board.end.x) < 0.001,
		"the last cell must end at the board's edge"
	)


func test_degenerate_inputs_are_handled_without_error() -> void:
	check_eq(
		BoardMetrics.cell_size(Rect2(Vector2.ZERO, Vector2.ZERO)),
		0.0,
		"a zero-sized board has no cell size"
	)
	check_eq(
		BoardMetrics.cell_from_point(Rect2(Vector2.ZERO, Vector2.ZERO), Vector2.ZERO),
		BoardMetrics.NO_CELL,
		"an empty board cannot contain a point"
	)
	check_eq(
		BoardMetrics.cell_from_point(Rect2(Vector2.ZERO, DESKTOP), Vector2.ONE, 0),
		BoardMetrics.NO_CELL,
		"a grid of zero has no cells"
	)
	check_eq(
		BoardMetrics.fit_square(Rect2(Vector2.ZERO, Vector2(10.0, 10.0)), 50.0).size,
		Vector2.ZERO,
		"padding larger than the space must not produce a negative square"
	)
	check(
		BoardMetrics.is_valid_cell(Vector2i(0, 0)),
		"the first cell is on the board"
	)
	check(
		not BoardMetrics.is_valid_cell(Vector2i(12, 0)),
		"a column past the board is not a cell"
	)
	check(
		not BoardMetrics.is_valid_cell(Vector2i(0, -1)),
		"a negative row is not a cell"
	)
