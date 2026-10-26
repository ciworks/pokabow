class_name AiRivalCatalog
extends RefCounted

## Stable bundled roster for local play and temporary API outages. The API
## catalogue replaces these display fields whenever it is reachable.
const NAMES: Array[String] = [
	"Pippa", "Milo", "Nia", "Theo", "Zuri",
	"Ada", "Hugo", "Iris", "Luca", "Mina",
	"Arlo", "Cleo", "Kai", "Nova", "Soren",
]

static func bundled() -> Array[Dictionary]:
	var rivals: Array[Dictionary] = []
	for index: int in range(NAMES.size()):
		var key: String = "rival_%02d" % (index + 1)
		rivals.append({"id": key, "displayName": NAMES[index],
			"avatarKey": key, "difficulty": int(index / 5)})
	return rivals


static func valid_rival(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var rival: Dictionary = value
	var id: String = String(rival.get("id", ""))
	var key: String = String(rival.get("avatarKey", ""))
	var name: String = String(rival.get("displayName", "")).strip_edges()
	return id in _known_ids() and key in _known_ids() and not name.is_empty() and \
		name.length() <= 40 and AiEnums.is_valid_difficulty(int(rival.get("difficulty", -1)))


static func from_response(value: Variant) -> Array[Dictionary]:
	var parsed: Array[Dictionary] = []
	if not value is Dictionary or not (value as Dictionary).get("rivals", null) is Array:
		return parsed
	var seen: Dictionary = {}
	for item: Variant in (value as Dictionary).get("rivals", []):
		if not valid_rival(item) or seen.has(item["id"]):
			return []
		seen[item["id"]] = true
		parsed.append(item)
	return parsed


static func _known_ids() -> Array[String]:
	var ids: Array[String] = []
	for index: int in range(1, 16):
		ids.append("rival_%02d" % index)
	return ids
