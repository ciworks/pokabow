class_name ClusterScoreResult
extends RefCounted

## One colour cluster's entitlement delta from a single placement
## (ADR-002 sections 5 and 7).
##
## ADR-002 section 2 defines a cluster as one connected component of the
## single-colour graph of matching boundaries; section 3 makes its size the number
## of unique tiles; section 4 makes its entitlement a flat award per completed
## milestone; and section 5 awards only the positive difference between the
## post-move entitlement and the sum of the pre-move entitlements.
##
## The event records the evidence ADR-002 section 7 requires: the colour, the
## newly placed coordinate's post-move component, the pre-entitlement total, the
## post-entitlement total, and the awarded delta.
##
## A result exists only when the delta is positive. Growing or merging clusters
## can correctly award zero, and a zero-point award is not a score event.

## The cluster's edge colour, one of `TileEnums.EdgeColor`.
var color: int = -1

## The post-move component's tiles in canonical order.
var cells: Array[Vector2i] = []

## Sum of the pre-move entitlements of the distinct components the new tile
## touched.
var previous_entitlement: int = 0

## Entitlement of the post-move component.
var current_entitlement: int = 0

## Awarded delta, `current_entitlement - previous_entitlement` and always
## positive for a real result.
var points: int = 0

## Canonical component identifier, `component:<colour>:<x>,<y>|...`.
##
## ADR-002 section 7 notes this key is diagnostic evidence rather than a stable
## identity: a growing component changes coordinates, which is why repeat
## prevention relies on entitlement deltas rather than on this key.
var component_key: StringName = &""


## Builds a result. The caller's cell array is copied.
static func create(
	color: int,
	cells: Array[Vector2i],
	previous_entitlement: int,
	current_entitlement: int,
	points: int
) -> ClusterScoreResult:
	var result: ClusterScoreResult = ClusterScoreResult.new()
	result.color = color
	result.cells = cells.duplicate()
	result.previous_entitlement = previous_entitlement
	result.current_entitlement = current_entitlement
	result.points = points
	result.component_key = ScoringEnums.component_key_for(color, result.cells)
	return result


## Returns the colour's constant name, for diagnostics only.
func get_color_name() -> String:
	return TileEnums.edge_color_name(color)


## Returns the number of unique tiles in the post-move component.
func size() -> int:
	return cells.size()


## Returns a short human-readable description, for diagnostics only.
func describe() -> String:
	return "%s cluster of %d tiles: entitlement %d -> %d, awarded %d" % [
		get_color_name(),
		cells.size(),
		previous_entitlement,
		current_entitlement,
		points,
	]


## Returns a JSON-safe dictionary, for save data and test fixtures.
func to_dictionary() -> Dictionary:
	var cell_records: Array = []
	for cell: Vector2i in cells:
		cell_records.append([cell.x, cell.y])
	return {
		"color": color,
		"component_key": String(component_key),
		"cells": cell_records,
		"previous_entitlement": previous_entitlement,
		"current_entitlement": current_entitlement,
		"points": points,
	}
