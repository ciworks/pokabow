extends TestCase

## Milestone 7 match persistence tests (ADR-008 section 11, ADR-003 section 9).
##
## No scene tree, no rendering, no input: every check drives a real
## `GameSessionController` through the same commands the game screen uses, so the
## autosave path under test is the one a committed move actually takes.
##
## The save path is redirected to a temporary file in `user://` for every test.
## That matters: `start_new_match` autosaves, so a test that used the real path
## would overwrite the player's own save on every run.

const TEST_MATCH_ID: StringName = &"persist-test"
const TEST_SEED: int = 20260924

## A save file of this suite's own, never the game's.
const TEST_SAVE_PATH: String = "user://test_match_persistence.json"

## Tiles the shortest legal opening line places (ADR-011 sections 1 and 4).
const TILES_PER_LINE: int = 2


func test_starting_a_match_leaves_a_resume_point() -> void:
	var controller: GameSessionController = _new_controller()
	check(controller.start_new_match(TEST_MATCH_ID, TEST_SEED), "the match must start")

	# Milestone 7: automatic save after each committed move. Setup is the first
	# committed state, so a termination during the opening turn still leaves
	# something to resume.
	check(
		controller.has_saved_match(),
		"a started match must leave a resume point (Milestone 7)"
	)
	check(_save_exists(), "the resume point must reach the disk, not just the flag")
	_cleanup(controller)


func test_a_committed_move_saves_and_resumes_to_the_same_position() -> void:
	var controller: GameSessionController = _new_controller()
	if not check(controller.start_new_match(TEST_MATCH_ID, TEST_SEED), "the match must start"):
		_cleanup(controller)
		return

	var committed: LineResult = _commit_opening_line(controller)
	if not check(
		committed != null and committed.was_committed(),
		"the human's opening line must commit through the controller"
	):
		_cleanup(controller)
		return

	# The value being protected: everything a relaunch has to reproduce.
	var occupied: int = controller.get_board().occupied_count()
	var moves: int = controller.get_session().move_count()
	var total_score: int = controller.human_score() + controller.ai_score()
	check(occupied > 0, "the committed line must reach the board")
	check(controller.has_saved_match(), "a committed move must leave a resume point")

	# A second controller on the same path stands in for a relaunch.
	var relaunched: GameSessionController = _new_controller()
	if not check(relaunched.resume_match(), "the saved match must resume"):
		_cleanup(relaunched)
		_cleanup(controller)
		return

	check_eq(
		relaunched.get_board().occupied_count(),
		occupied,
		"the resumed board must hold the same committed tiles (Milestone 7 exit criterion)"
	)
	check_eq(
		relaunched.get_session().move_count(),
		moves,
		"the resumed history must hold the same moves"
	)
	check_eq(
		relaunched.human_score() + relaunched.ai_score(),
		total_score,
		"the resumed match must carry the same score"
	)
	check_eq(
		relaunched.remaining_tiles(),
		controller.remaining_tiles(),
		"the resumed pot must hold the same tiles"
	)
	check_eq(
		relaunched.staged_count(),
		0,
		"ADR-003 section 9: a transient preview must never be restored"
	)
	_cleanup(relaunched)
	_cleanup(controller)


func test_a_save_this_build_cannot_restore_is_refused_and_reported() -> void:
	var controller: GameSessionController = _new_controller()
	if not check(controller.start_new_match(TEST_MATCH_ID, TEST_SEED), "the match must start"):
		_cleanup(controller)
		return
	# Parseable JSON holding no match record: the shape a save from a future
	# schema, or a truncated write, would present.
	_write_save("{\"saved_at\": \"now\", \"match\": \"not-a-record\"}")

	var notices: Array = []
	var relaunched: GameSessionController = _new_controller()
	relaunched.notice.connect(_collect_notice.bind(notices))

	check(
		not relaunched.resume_match(),
		"a save with no match record must be refused rather than half-applied"
	)
	check(
		relaunched.get_session() == null,
		"a refused resume must leave no partially restored session"
	)
	check_eq(notices.size(), 1, "a refused resume must report why it failed")
	check(
		_save_exists(),
		"a refused save must be kept, so the player can recover it rather than lose it"
	)
	_cleanup(relaunched)
	_cleanup(controller)


func test_autosave_refuses_once_the_match_is_over() -> void:
	var controller: GameSessionController = _new_controller()
	check(controller.start_new_match(TEST_MATCH_ID, TEST_SEED), "the match must start")

	# A finished match clears its resume point, so there is nothing to autosave
	# and a save must not resurrect one (ADR-003 section 9).
	controller.clear_saved_match()
	check(not controller.has_saved_match(), "clearing must remove the resume point")
	check(not _save_exists(), "clearing must remove the file itself")
	_cleanup(controller)


func test_a_refused_restore_reports_the_recovery_failure_and_keeps_the_save() -> void:
	var controller: GameSessionController = _new_controller()
	if not check(controller.start_new_match(TEST_MATCH_ID, TEST_SEED), "the match must start"):
		_cleanup(controller)
		return
	# Parseable JSON holding no match record: the shape a save from a future
	# schema, or a truncated write, presents.
	_write_save("{\"saved_at\": \"now\", \"match\": \"not-a-record\"}")

	var reasons: Array = []
	var relaunched: GameSessionController = _new_controller()
	relaunched.recovery_failed.connect(_collect_notice.bind(reasons))

	check(not relaunched.resume_match(), "a save with no match record must be refused")
	check_eq(reasons.size(), 1, "a refused restore must report the recovery failure once")
	check(
		relaunched.get_session() == null,
		"a refused restore must create no session, so the screen has no half-built match"
	)
	check(
		_save_exists(),
		"the refusal must keep the save, so the last valid transaction stays recoverable"
	)
	_cleanup(relaunched)
	_cleanup(controller)


func test_the_exported_fixture_restores_to_the_same_position() -> void:
	var fixture_path: String = "user://test_match_fixture.json"
	var controller: GameSessionController = _new_controller()
	if not check(controller.start_new_match(TEST_MATCH_ID, TEST_SEED), "the match must start"):
		_cleanup(controller)
		return
	var committed: LineResult = _commit_opening_line(controller)
	if not check(
		committed != null and committed.was_committed(),
		"the human's opening line must commit through the controller"
	):
		_cleanup(controller)
		return
	var occupied: int = controller.get_board().occupied_count()
	var moves: int = controller.get_session().move_count()

	controller.fixture_path = fixture_path
	check(controller.export_fixture(), "the match must export a bug-report fixture")
	check(FileAccess.file_exists(fixture_path), "the fixture must reach the disk")
	check_eq(
		controller.get_session().move_count(),
		moves,
		"exporting a fixture must not change the match it describes"
	)

	# The fixture is the same record a save holds, so pointing a second
	# controller's save path at it restores through the ordinary path. That is
	# what makes the export reproducible rather than a second, drifting summary.
	var relaunched: GameSessionController = _new_controller()
	relaunched.save_path = fixture_path
	if not check(relaunched.resume_match(), "the exported fixture must restore"):
		_cleanup(relaunched)
		_cleanup(controller)
		_remove_fixture(fixture_path)
		return
	check_eq(
		relaunched.get_board().occupied_count(),
		occupied,
		"the fixture must restore the same committed board"
	)
	check_eq(
		relaunched.get_session().move_count(),
		moves,
		"the fixture must restore the same move history the replay verifier reads"
	)
	_cleanup(relaunched)
	_cleanup(controller)
	_remove_fixture(fixture_path)


# --- Helpers ---------------------------------------------------------------


## Removes a fixture this suite wrote, so no test leaks a file into the next.
func _remove_fixture(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Returns a controller wired to this suite's own save path.
func _new_controller() -> GameSessionController:
	var controller: GameSessionController = GameSessionController.new()
	controller.save_path = TEST_SAVE_PATH
	return controller


## Frees a controller and removes the test save, so no test leaks into the next.
func _cleanup(controller: GameSessionController) -> void:
	if controller != null:
		controller.free()
	_remove_save()


## Appends a reported notice, so a test can assert one arrived.
func _collect_notice(text: String, into: Array) -> void:
	into.append(text)


func _save_exists() -> bool:
	return FileAccess.file_exists(TEST_SAVE_PATH)


func _remove_save() -> void:
	if _save_exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))


func _write_save(text: String) -> void:
	var file: FileAccess = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("the test could not write its own save file")
		return
	file.store_string(text)
	file.close()


## Assembles and commits the human's opening line through the controller.
##
## ADR-011 sections 1, 3, and 11 with the ADR-012 section 1 hand list: a legal
## move is a contiguous line of two or more deck tiles of one rank, staged on the
## board and confirmed as a whole. Returns the commit result, or null when this
## hand cannot supply the pair the line needs.
func _commit_opening_line(controller: GameSessionController) -> LineResult:
	var board: BoardState = controller.get_board()
	if board == null:
		return null
	var pair: Array[TileDefinition] = _rank_pair(controller.human_deck(), TILES_PER_LINE)
	if pair.size() < TILES_PER_LINE:
		return null
	var cells: Array[Vector2i] = _line_cells(board, TILES_PER_LINE)
	if cells.size() < TILES_PER_LINE:
		return null
	for index: int in range(cells.size()):
		controller.select_deck_tile(pair[index].tile_id)
		if not controller.stage_tile(pair[index].tile_id, cells[index], 0):
			return null
	return controller.commit_line()


## Returns `count` cells of the first legal line the frontier offers, in
## row-major order, or as many as the board can supply.
func _line_cells(board: BoardState, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var first: Vector2i = _first_frontier(board)
	if first == BoardMetrics.NO_CELL:
		return cells
	cells.append(first)
	for offset: Vector2i in BoardEnums.neighbor_offsets():
		if cells.size() >= count:
			break
		var neighbor: Vector2i = first + offset
		if board.is_empty_cell(neighbor):
			cells.append(neighbor)
	return cells


## Returns `count` tiles of one rank from `deck`, or an empty array.
func _rank_pair(deck: Array[TileDefinition], count: int) -> Array[TileDefinition]:
	var empty: Array[TileDefinition] = []
	if count <= 0:
		return empty
	var by_rank: Dictionary = {}
	for tile: TileDefinition in deck:
		if tile == null:
			continue
		var rank: int = int(tile.rank)
		var group: Array = by_rank.get(rank, [])
		group.append(tile)
		by_rank[rank] = group
	for rank: Variant in by_rank.keys():
		var group: Array = by_rank[rank]
		if group.size() < count:
			continue
		var chosen: Array[TileDefinition] = []
		for tile: TileDefinition in group:
			chosen.append(tile)
			if chosen.size() == count:
				return chosen
	return empty


## Returns the first legal frontier cell in row-major order.
func _first_frontier(board: BoardState) -> Vector2i:
	var frontier: Array[Vector2i] = board.get_frontier_cells()
	if frontier.is_empty():
		return BoardMetrics.NO_CELL
	return frontier[0]
