class_name PokerHandResult
extends RefCounted

## The outcome of classifying one five-cell poker window
## (ADR-001 section 6).
##
## ADR-001 section 6 requires the rules layer to return data instead of
## triggering visual effects, so this type carries only the category, the points
## it is worth, the window's cells, and its canonical identifier. Presentation
## consumes it for highlights, animation, sound, and floating-score text; nothing
## here depends on a scene node.
##
## A result exists only for a window that classified as a real poker category.
## `NONE` is never represented by a result, because an unclassified window awards
## nothing and therefore produces no score event.

## `ScoringEnums.PokerHandCategory` value; never `NONE` for a real result.
var category: int = ScoringEnums.PokerHandCategory.NONE

## Points awarded for this category, read from the versioned rules resource.
var points: int = 0

## The window's five cells in walk order along its orientation.
var cells: Array[Vector2i] = []

## Canonical window identifier (ADR-001 section 1, ADR-007 section 5).
## One-time scoring is tracked by this identifier.
var hand_id: StringName = &""


## Builds a result. The caller's cell array is copied so later changes cannot
## reach back into the created result.
static func create(
	hand_id: StringName,
	category: int,
	points: int,
	cells: Array[Vector2i]
) -> PokerHandResult:
	var result: PokerHandResult = PokerHandResult.new()
	result.hand_id = hand_id
	result.category = category
	result.points = points
	result.cells = cells.duplicate()
	return result


## Returns the category's constant name, for diagnostics only.
func get_category_name() -> String:
	return ScoringEnums.poker_hand_name(category)


## Returns a short human-readable description, for diagnostics only.
func describe() -> String:
	return "%s (%s) worth %d at %s" % [
		String(hand_id),
		get_category_name(),
		points,
		ScoringEnums.cells_label(cells),
	]


## Returns a JSON-safe dictionary, for save data and test fixtures.
func to_dictionary() -> Dictionary:
	var cell_records: Array = []
	for cell: Vector2i in cells:
		cell_records.append([cell.x, cell.y])
	return {
		"hand_id": String(hand_id),
		"category": category,
		"points": points,
		"cells": cell_records,
	}
