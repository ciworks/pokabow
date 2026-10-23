class_name MatchHistoryStore
extends RefCounted

## Small account-scoped, read-only index of finished matches for the hub.
## The live controller/server remains authoritative for scores and outcomes.
const MAX_ENTRIES: int = 50

static func path_for(account_id: String) -> String:
	return "user://match_history_%s.json" % account_id.sha256_text()


static func entries(account_id: String) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if account_id.is_empty() or not FileAccess.file_exists(path_for(account_id)):
		return items
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path_for(account_id)))
	if not parsed is Array:
		return items
	for value: Variant in parsed:
		if value is Dictionary and _valid(value):
			items.append(value)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("finished_at", "")) > String(b.get("finished_at", ""))
	)
	return items


static func add(account_id: String, match_id: String, kind: String, opponent: String,
		result: Dictionary, avatar_path: String = "") -> bool:
	if account_id.is_empty() or match_id.is_empty() or kind not in ["ai", "online"]:
		return false
	if int(result.get("outcome", TurnEnums.MatchOutcome.IN_PROGRESS)) in [
		TurnEnums.MatchOutcome.IN_PROGRESS, TurnEnums.MatchOutcome.INCOMPLETE
	]:
		return false
	var items: Array[Dictionary] = entries(account_id)
	for existing: Dictionary in items:
		if String(existing.get("id", "")) == match_id and String(existing.get("kind", "")) == kind:
			return true
	items.push_front({
		"id": match_id, "kind": kind,
		"opponent": opponent if not opponent.strip_edges().is_empty() else "Rival",
		"finished_at": Time.get_datetime_string_from_system(true),
		"avatar_path": avatar_path,
		"result": result.duplicate(true),
	})
	if items.size() > MAX_ENTRIES:
		items.resize(MAX_ENTRIES)
	var file: FileAccess = FileAccess.open(path_for(account_id), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(items, "\t"))
	file.close()
	return true


static func _valid(value: Dictionary) -> bool:
	var result: Variant = value.get("result")
	return not String(value.get("id", "")).is_empty() and result is Dictionary \
		and result.has("outcome") and result.has("human_score") and result.has("ai_score")
