class_name ScoredHandSet
extends RefCounted

## The set of poker windows that have already scored (ADR-001 section 5).
##
## ADR-001 section 5 requires each canonical window to score only once for the
## whole match, and section 8 (ADR-007 section 10) requires the set to be
## persisted for efficient play and verified against replay. This type is the
## smallest thing that can hold that fact.
##
## It is deliberately separate from `ScoreLedger`: the ledger records the points
## that were awarded, while this set answers "has this window scored?" without
## scanning events. Both are rebuilt from replay, and replay is authoritative
## (ADR-007 sections 9 and 10).

## Window identifier -> true.
var _hand_ids: Dictionary = {}


## Creates an empty set.
static func create() -> ScoredHandSet:
	return ScoredHandSet.new()


## Returns true when this window has already scored.
func has(hand_id: StringName) -> bool:
	return _hand_ids.has(hand_id)


## Records a window as scored.
##
## Returns true only when the identifier was new, so a caller can detect an
## attempt to score the same window twice.
func add(hand_id: StringName) -> bool:
	if String(hand_id).is_empty():
		return false
	if _hand_ids.has(hand_id):
		return false
	_hand_ids[hand_id] = true
	return true


## Returns how many windows have scored.
func size() -> int:
	return _hand_ids.size()


## Returns true when no window has scored.
func is_empty() -> bool:
	return _hand_ids.is_empty()


## Returns every scored identifier, sorted for deterministic comparison.
func to_array() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key: Variant in _hand_ids.keys():
		ids.append(StringName(String(key)))
	ids.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			return String(a) < String(b)
	)
	return ids


## Returns an independent copy of this set.
func copy() -> ScoredHandSet:
	var clone: ScoredHandSet = ScoredHandSet.new()
	clone._hand_ids = _hand_ids.duplicate()
	return clone


## Builds a set from a list of identifiers.
static func from_array(hand_ids: Array) -> ScoredHandSet:
	var set: ScoredHandSet = ScoredHandSet.new()
	for hand_id: Variant in hand_ids:
		set.add(StringName(String(hand_id)))
	return set
