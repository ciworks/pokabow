extends TestCase

func test_bundled_roster_has_fifteen_stable_distinct_rivals() -> void:
	var rivals: Array[Dictionary] = AiRivalCatalog.bundled()
	check_eq(rivals.size(), 15, "bundled catalogue has fifteen rivals")
	var ids: Dictionary = {}
	var names: Dictionary = {}
	var counts: Array[int] = [0, 0, 0]
	for rival: Dictionary in rivals:
		check(AiRivalCatalog.valid_rival(rival), "rival identity is valid")
		ids[rival["id"]] = true
		names[rival["displayName"]] = true
		counts[int(rival["difficulty"])] += 1
	check_eq(ids.size(), 15, "rival IDs are distinct")
	check_eq(names.size(), 15, "rival names are distinct")
	check_eq(counts, [5, 5, 5], "difficulty tiers each have five rivals")


func test_api_catalogue_rejects_duplicate_or_unknown_identity() -> void:
	var rivals: Array[Dictionary] = AiRivalCatalog.bundled()
	check_eq(AiRivalCatalog.from_response({"rivals": rivals}).size(), 15,
		"valid API catalogue is accepted")
	check(AiRivalCatalog.from_response({"rivals": [rivals[0], rivals[0]]}).is_empty(),
		"duplicate ID rejects the catalogue")
	check(AiRivalCatalog.from_response({"rivals": [{"id": "rival_99",
		"displayName": "Unknown", "avatarKey": "rival_99", "difficulty": 0}]}).is_empty(),
		"unknown portrait is rejected")
