class_name ScoreEvent
extends RefCounted

## One immutable committed scoring award (ADR-007 sections 1 and 5).
##
## The player's displayed total is the sum of that player's committed events
## (ADR-007 section 1), so events are the authoritative score record and totals
## are derived data.
##
## `event_id` is deterministic and may appear in the ledger at most once
## (ADR-007 section 5), which is what makes a repeated commit request idempotent
## instead of scoring twice.
##
## Phase 1 accepts only non-negative integer points with no multipliers
## (ADR-007 section 11). Presentation-only messages are not score events and
## cannot change totals.

const SCHEMA_VERSION: int = 1

## Deterministic event identifier, `score:<move-id>:<category>:<discriminator>`.
var event_id: StringName = &""

## The move that created this award.
var move_id: StringName = &""

## The player credited with the award: whoever committed the scoring tile
## (ADR-007 constraint 8).
var player_id: StringName = &""

## `ScoringEnums.ScoreCategory` value.
var category: int = ScoringEnums.ScoreCategory.POKER_HAND

## Non-negative integer points.
var points: int = 0

## Turn number the award was committed on. 0 means "not recorded".
var turn_number: int = 0

## Coordinates the award is attributed to, in canonical order.
var cells: Array[Vector2i] = []

## Category-specific evidence: the hand identifier, boundary identifier, or
## cluster entitlement figures that explain the award (ADR-007 section 1).
var evidence: Dictionary = {}

## Schema version of this event record, persisted with saves.
var schema_version: int = SCHEMA_VERSION

## Scoring rules versions in force when the award was made.
var rules_version: String = ""


## Builds an event. The caller's cell array and dictionary are copied so later
## changes cannot reach back into the created event.
static func create(
	event_id: StringName,
	move_id: StringName,
	player_id: StringName,
	category: int,
	points: int,
	cells: Array[Vector2i],
	evidence: Dictionary = {},
	turn_number: int = 0,
	rules_version: String = ""
) -> ScoreEvent:
	var event: ScoreEvent = ScoreEvent.new()
	event.event_id = event_id
	event.move_id = move_id
	event.player_id = player_id
	event.category = category
	event.points = points
	event.cells = cells.duplicate()
	event.evidence = evidence.duplicate()
	event.turn_number = turn_number
	event.rules_version = rules_version
	return event


## Returns true when this event is acceptable to the ledger.
##
## Rejects a missing identity, an unassigned or unknown category, and negative
## points (ADR-007 section 11).
func is_valid() -> bool:
	if schema_version != SCHEMA_VERSION:
		return false
	if String(event_id).is_empty():
		return false
	if String(move_id).is_empty():
		return false
	if String(player_id).is_empty():
		return false
	if not ScoringEnums.is_valid_score_category(category):
		return false
	if points < 0:
		return false
	return true


## Returns the category's constant name, for diagnostics only.
func get_category_name() -> String:
	return ScoringEnums.score_category_name(category)


## Returns a short human-readable description, for diagnostics only.
func describe() -> String:
	return "%s -> %s %s %d at %s" % [
		String(event_id),
		String(player_id),
		get_category_name(),
		points,
		ScoringEnums.cells_label(cells),
	]


## Returns a JSON-safe dictionary.
func to_dictionary() -> Dictionary:
	var cell_records: Array = []
	for cell: Vector2i in cells:
		cell_records.append([cell.x, cell.y])
	return {
		"schema_version": schema_version,
		"event_id": String(event_id),
		"move_id": String(move_id),
		"player_id": String(player_id),
		"category": category,
		"points": points,
		"turn_number": turn_number,
		"cells": cell_records,
		"evidence": evidence,
		"rules_version": rules_version,
	}


## Builds an event from a dictionary produced by `to_dictionary()`.
static func from_dictionary(source: Dictionary) -> ScoreEvent:
	var event: ScoreEvent = ScoreEvent.new()
	event.schema_version = int(source.get("schema_version", 0))
	event.event_id = StringName(String(source.get("event_id", "")))
	event.move_id = StringName(String(source.get("move_id", "")))
	event.player_id = StringName(String(source.get("player_id", "")))
	# An absent category becomes -1 so `is_valid()` refuses the record rather than
	# silently defaulting a corrupted save to a real category.
	event.category = int(source.get("category", -1))
	event.points = int(source.get("points", 0))
	event.turn_number = int(source.get("turn_number", 0))
	event.cells = []
	var raw_cells: Variant = source.get("cells", [])
	if raw_cells is Array:
		for record: Variant in raw_cells:
			if record is Array and record.size() >= 2:
				event.cells.append(Vector2i(int(record[0]), int(record[1])))
	var raw_evidence: Variant = source.get("evidence", {})
	if raw_evidence is Dictionary:
		event.evidence = raw_evidence
	event.rules_version = String(source.get("rules_version", ""))
	return event
