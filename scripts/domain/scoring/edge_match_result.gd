class_name EdgeMatchResult
extends RefCounted

## One matching tile-to-tile boundary worth the edge-match award
## (ADR-002 sections 1 and 7).
##
## ADR-002 section 1 awards exactly +1 when the second tile of a boundary is
## committed, and requires each undirected boundary to be evaluated once. The
## canonical identifier orders the coordinate pair, so the same boundary always
## produces the same id no matter which tile the caller started from.
##
## Edge-match points and cluster bonuses are separate score events: a matching
## boundary can contribute its +1 and also connect tiles inside a cluster.

## Canonical boundary identifier, `edge:<x1>,<y1>-<x2>,<y2>`.
var boundary_id: StringName = &""

## The shared edge colour, one of `TileEnums.EdgeColor`.
var color: int = -1

## The two cells of the boundary in canonical order.
var cells: Array[Vector2i] = []

## Points awarded for this boundary; always `ScoringEnums.EDGE_MATCH_POINTS`.
var points: int = ScoringEnums.EDGE_MATCH_POINTS


## Builds a result. The caller's cell array is copied.
static func create(
	boundary_id: StringName,
	color: int,
	cells: Array[Vector2i]
) -> EdgeMatchResult:
	var result: EdgeMatchResult = EdgeMatchResult.new()
	result.boundary_id = boundary_id
	result.color = color
	result.cells = cells.duplicate()
	result.points = ScoringEnums.EDGE_MATCH_POINTS
	return result


## Returns the colour's constant name, for diagnostics only.
func get_color_name() -> String:
	return TileEnums.edge_color_name(color)


## Returns a short human-readable description, for diagnostics only.
func describe() -> String:
	return "%s matching %s worth %d" % [
		String(boundary_id),
		get_color_name(),
		points,
	]


## Returns a JSON-safe dictionary, for save data and test fixtures.
func to_dictionary() -> Dictionary:
	var cell_records: Array = []
	for cell: Vector2i in cells:
		cell_records.append([cell.x, cell.y])
	return {
		"boundary_id": String(boundary_id),
		"color": color,
		"cells": cell_records,
		"points": points,
	}
