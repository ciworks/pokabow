extends TestCase

## Milestone 3 ledger and event tests (ADR-007 sections 1, 5, and 11).
##
## Domain-level: no scene tree, no rendering. Every expectation is checked against
## `ScoreEvent` and `ScoreLedger` alone.

const POKER: int = ScoringEnums.ScoreCategory.POKER_HAND
const EDGE: int = ScoringEnums.ScoreCategory.EDGE_MATCH
const CLUSTER: int = ScoringEnums.ScoreCategory.EDGE_CLUSTER


func test_events_are_appended_and_totalled_per_player() -> void:
	var ledger: ScoreLedger = ScoreLedger.create()

	check(ledger.is_empty(), "a new ledger holds nothing")
	check_eq(ledger.size(), 0, "a new ledger holds nothing")
	check_eq(ledger.total_points(), 0, "a new ledger totals zero")

	check(
		ledger.add(_event(&"score:m1:poker:hand:H:5:4", POKER, 6, &"p1")),
		"a valid poker event must be appended"
	)
	check(
		ledger.add(_event(&"score:m1:edge:edge:7,5-8,5", EDGE, 1, &"p1")),
		"a valid edge event must be appended"
	)
	check(
		ledger.add(_event(&"score:m2:poker:hand:V:3:7", POKER, 2, &"p2")),
		"a valid poker event must be appended"
	)

	check_eq(ledger.size(), 3, "three events were committed")
	check_eq(ledger.total_for(&"p1"), 7, "a player total is the sum of that player's events")
	check_eq(ledger.total_for(&"p2"), 2, "a player total is the sum of that player's events")
	check_eq(ledger.total_for(&"p3"), 0, "a player with no events totals zero")
	check_eq(ledger.total_points(), 9, "the ledger total is the sum of every event")
	check_eq(ledger.total_for_category(POKER), 8, "category totals must be reported")
	check_eq(ledger.total_for_category(EDGE), 1, "category totals must be reported")
	check_eq(ledger.total_for_category(CLUSTER), 0, "a category with no events totals zero")
	check_eq(ledger.events_for(&"p1").size(), 2, "a player's events must be retrievable")
	check_eq(ledger.event_ids().size(), 3, "every committed event must be listed")
	check_eq(
		String(ledger.event_ids()[0]),
		"score:m1:poker:hand:H:5:4",
		"events must keep commit order"
	)
	check_eq(
		ledger.event_ids_for_category(POKER).size(),
		2,
		"a category's event ids must be retrievable"
	)
	check_eq(
		ledger.player_totals().get(&"p1", -1),
		7,
		"per-player totals must be reportable as a table"
	)
	check_eq(
		int(ledger.player_totals_by_name().get("p2", -1)),
		2,
		"named totals must agree with the identifier totals"
	)


func test_duplicate_and_invalid_events_are_refused() -> void:
	var ledger: ScoreLedger = ScoreLedger.create()
	var event: ScoreEvent = _event(&"score:m1:edge:edge:5,5-6,5", EDGE, 1, &"p1")

	check(ledger.add(event), "the first commit must succeed")
	check(not ledger.add(event), "the same event id must never be committed twice")
	check_eq(ledger.size(), 1, "a refused duplicate must not change the ledger")
	check(ledger.has_event(&"score:m1:edge:edge:5,5-6,5"), "the committed id must be findable")

	check(
		not ledger.add(_event(&"score:m2:edge:edge:5,5-6,5", EDGE, -1, &"p1")),
		"a negative award must be refused"
	)
	check(
		not ledger.add(_event(&"score:m2:edge:edge:5,5-6,5", 99, 5, &"p1")),
		"an unknown category must be refused"
	)
	check(
		not ledger.add(_event(&"", EDGE, 1, &"p1")),
		"an event without an identifier must be refused"
	)
	check(
		not ledger.add(_event(&"score:m2:edge:edge:5,5-6,5", EDGE, 5, &"")),
		"an event without a player cannot be attributed and must be refused"
	)
	check(not ledger.add(null), "a null event must be refused")
	check_eq(ledger.size(), 1, "refused events must not change the ledger")
	check_eq(ledger.total_points(), 1, "refused events must not change the total")


func test_zero_point_events_are_legal_but_never_required() -> void:
	var ledger: ScoreLedger = ScoreLedger.create()

	check(
		ledger.add(_event(&"score:m1:edge:edge:5,5-6,5", EDGE, 0, &"p1")),
		"zero is a non-negative integer award, so the ledger accepts it"
	)
	check_eq(ledger.total_points(), 0, "a zero-point event cannot change the total")
	check_eq(ledger.size(), 1, "the event is still recorded")


func test_event_dictionary_round_trip_preserves_the_record() -> void:
	var ledger: ScoreLedger = ScoreLedger.create()
	ledger.add(_event(&"score:m1:poker:hand:H:5:4", POKER, 6, &"p1"))
	ledger.add(_event(&"score:m1:edge:edge:7,5-8,5", EDGE, 1, &"p2"))

	var restored: ScoreLedger = ScoreLedger.from_dictionary(ledger.to_dictionary())

	check_eq(restored.size(), 2, "a round trip must keep every event")
	check_eq(
		restored.event_ids(),
		ledger.event_ids(),
		"a round trip must keep event order"
	)
	check_eq(
		restored.player_totals_by_name(),
		ledger.player_totals_by_name(),
		"a round trip must keep every total"
	)
	check_eq(
		restored.get_events()[0].evidence.get("hand_id", ""),
		"hand:H:5:4",
		"a round trip must keep the evidence that explains the award"
	)
	check_eq(
		restored.get_events()[1].cells,
		_event(&"probe", EDGE, 1, &"p2").cells,
		"a round trip must keep the affected coordinates"
	)

	var corrupt: ScoreLedger = ScoreLedger.from_dictionary({
		"events": [{"event_id": "", "points": 5}],
	})
	check_eq(corrupt.size(), 0, "a corrupted record must not be restored as an award")


func test_event_validation_rejects_incomplete_records() -> void:
	var valid: ScoreEvent = _event(&"score:m1:edge:edge:5,5-6,5", EDGE, 1, &"p1")
	check(valid.is_valid(), "a fully populated event must validate")
	check_eq(valid.turn_number, 3, "an event records the turn it was committed on")
	check_eq(valid.rules_version, "scoring:1", "an event records the rules version in force")
	check_eq(valid.get_category_name(), "EDGE_MATCH", "the category must be nameable")

	var no_move: ScoreEvent = ScoreEvent.create(&"score:x", &"", &"p1", EDGE, 1, _cells())
	check(not no_move.is_valid(), "an event without a move cannot be verified and must fail")

	var bad_schema: ScoreEvent = _event(&"score:m1:edge:edge:5,5-6,5", EDGE, 1, &"p1")
	bad_schema.schema_version = 99
	check(not bad_schema.is_valid(), "an unknown event schema version must be refused")

	check(
		not ScoreLedger.create().add(bad_schema),
		"a ledger must refuse an event with an unknown schema version"
	)


## Builds a valid event for the ledger tests.
func _event(event_id: StringName, category: int, points: int, player_id: StringName) -> ScoreEvent:
	var evidence: Dictionary = {}
	if category == POKER:
		evidence = {
			"hand_id": "hand:H:5:4",
			"category": "TWO_PAIR",
			"cells": "4,5|5,5|6,5|7,5|8,5",
		}
	elif category == EDGE:
		evidence = {"boundary_id": "edge:7,5-8,5", "color": "BLUE"}
	return ScoreEvent.create(
		event_id,
		&"move:test:3",
		player_id,
		category,
		points,
		_cells(),
		evidence,
		3,
		"scoring:1"
	)


## Returns the two-cell coordinate list used by the test events.
func _cells() -> Array[Vector2i]:
	return [Vector2i(7, 5), Vector2i(8, 5)]
