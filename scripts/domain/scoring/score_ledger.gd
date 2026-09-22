class_name ScoreLedger
extends RefCounted

## Append-only record of committed score events (ADR-007 sections 1 and 5).
##
## The ledger is the authoritative score record: a player's total is the sum of
## that player's committed events, so totals can always be rebuilt from it
## (ADR-007 section 10). Cached totals would be derived data and are not stored
## here.
##
## Events are immutable once added, and an event identifier may appear at most
## once. A repeated commit request therefore returns the original result instead
## of awarding points again (ADR-007 section 5).
##
## The ledger owns no board, no turn state, and no presentation, and it is not an
## autoload: the match that owns it holds it (ADR-008 section 6).

## Committed events in the order they were added.
var _events: Array[ScoreEvent] = []

## Event identifier -> true, for duplicate rejection and idempotency.
var _event_ids: Dictionary = {}


## Creates an empty ledger.
static func create() -> ScoreLedger:
	return ScoreLedger.new()


## Appends one event, unless it is invalid or already present.
##
## Returns true only when the event was added. Repeating an event identifier is
## refused rather than silently ignored, so callers can tell a duplicate from a
## fresh award (ADR-007 section 11).
func add(event: ScoreEvent) -> bool:
	if event == null or not event.is_valid():
		return false
	if _event_ids.has(event.event_id):
		return false
	_events.append(event)
	_event_ids[event.event_id] = true
	return true


## Returns true when an event with this identifier has been committed.
func has_event(event_id: StringName) -> bool:
	return _event_ids.has(event_id)


## Returns how many events have been committed.
func size() -> int:
	return _events.size()


## Returns true when nothing has been committed.
func is_empty() -> bool:
	return _events.is_empty()


## Returns a copy of the committed events, in commit order.
##
## A copy keeps callers from appending to the ledger's own array and bypassing
## duplicate rejection.
func get_events() -> Array[ScoreEvent]:
	return _events.duplicate()


## Returns one player's events, in commit order.
func events_for(player_id: StringName) -> Array[ScoreEvent]:
	var events: Array[ScoreEvent] = []
	for event: ScoreEvent in _events:
		if event.player_id == player_id:
			events.append(event)
	return events


## Returns one player's committed total.
func total_for(player_id: StringName) -> int:
	var total: int = 0
	for event: ScoreEvent in _events:
		if event.player_id == player_id:
			total += event.points
	return total


## Returns every player's total, keyed by player identifier.
func player_totals() -> Dictionary:
	var totals: Dictionary = {}
	for event: ScoreEvent in _events:
		totals[event.player_id] = int(totals.get(event.player_id, 0)) + event.points
	return totals


## Returns every player's total, keyed by the lowercase player name.
##
## Keyed by string so a report stays readable and comparable across runs.
func player_totals_by_name() -> Dictionary:
	var totals: Dictionary = {}
	for event: ScoreEvent in _events:
		var key: String = String(event.player_id)
		totals[key] = int(totals.get(key, 0)) + event.points
	return totals


## Returns the committed total across every player.
func total_points() -> int:
	var total: int = 0
	for event: ScoreEvent in _events:
		total += event.points
	return total


## Returns the committed points for one category.
func total_for_category(category: int) -> int:
	var total: int = 0
	for event: ScoreEvent in _events:
		if event.category == category:
			total += event.points
	return total


## Returns every committed event identifier, in commit order.
func event_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for event: ScoreEvent in _events:
		ids.append(event.event_id)
	return ids


## Returns one category's events, in commit order.
##
## Used by verification to recheck each committed award against the board
## (ADR-007 section 9).
func events_for_category(category: int) -> Array[ScoreEvent]:
	var events: Array[ScoreEvent] = []
	for event: ScoreEvent in _events:
		if event.category == category:
			events.append(event)
	return events


## Returns every event identifier of one category, in commit order.
func event_ids_for_category(category: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	for event: ScoreEvent in _events:
		if event.category == category:
			ids.append(event.event_id)
	return ids


## Returns a JSON-safe list of every committed event.
func to_dictionary() -> Dictionary:
	var records: Array = []
	for event: ScoreEvent in _events:
		records.append(event.to_dictionary())
	return {"events": records}


## Restores a ledger from a dictionary produced by `to_dictionary()`.
##
## Returns a ledger holding only the records that are valid and unique, so a
## corrupted save cannot inject a negative award or a duplicate identifier.
static func from_dictionary(source: Dictionary) -> ScoreLedger:
	var ledger: ScoreLedger = ScoreLedger.new()
	var raw_events: Variant = source.get("events", [])
	if raw_events is Array:
		for record: Variant in raw_events:
			if record is Dictionary:
				ledger.add(ScoreEvent.from_dictionary(record))
	return ledger
