extends TestCase


func test_achievement_identifiers_accept_json_strings_and_string_names() -> void:
	check_eq(AchievementApiClient._achievement_id("edge_cluster"), "edge_cluster", "API string ID is preserved")
	check_eq(AchievementApiClient._achievement_id(&"edge_cluster"), "edge_cluster", "StringName ID is normalized")
	check_eq(AchievementApiClient._achievement_id({"id": &"edge_cluster"}), "edge_cluster", "detail row ID is normalized")
	check_eq(AchievementApiClient._achievement_id({"id": null}), "", "invalid detail ID is ignored")
	check_eq(AchievementApiClient._text(null), "", "missing achievement text stays empty")
