extends SceneTree
## Focused checks for the four-rank tile rules and affected gameplay systems.
const SUITES: PackedStringArray = [
    "res://tests/unit/test_tile_generation.gd",
    "res://tests/unit/test_tile_save.gd",
    "res://tests/unit/test_tile_source.gd",
    "res://tests/unit/test_poker_evaluator.gd",
    "res://tests/unit/test_variable_poker_hands.gd",
    "res://tests/unit/test_hand_multipliers.gd",
    "res://tests/unit/test_score_preview.gd",
    "res://tests/unit/test_scoring_verification.gd",
    "res://tests/unit/test_ai_move_generation.gd",
    "res://tests/unit/test_ai_difficulties.gd",
    "res://tests/unit/test_match_lifecycle.gd",
    "res://tests/unit/test_turn_manager.gd",
    "res://tests/unit/test_game_api_client.gd",
    "res://tests/integration/test_score_reveal.gd",
]
func _initialize() -> void:
    var assertions: int = 0
    var failures: int = 0
    var tests: int = 0
    for path: String in SUITES:
        var script: GDScript = load(path)
        if script == null:
            push_error("could not load " + path)
            failures += 1
            continue
        var suite: TestCase = script.new()
        for method: Dictionary in script.get_script_method_list():
            var name: String = String(method.get("name", ""))
            if not name.begins_with("test_"):
                continue
            var before: int = suite.assertions
            suite.call(name)
            tests += 1
            if suite.assertions == before:
                suite.failures.append("%s::%s ran no assertions" % [path, name])
        assertions += suite.assertions
        failures += suite.failures.size()
        for message: String in suite.failures:
            push_error("%s: %s" % [path, message])
    var matchmaking: TestCase = load("res://tests/integration/test_matchmaking.gd").new()
    matchmaking.test_search_pairs_and_keeps_the_lobby_alive()
    tests += 1
    assertions += matchmaking.assertions
    failures += matchmaking.failures.size()
    for message: String in matchmaking.failures:
        push_error("matchmaking contract: %s" % message)
    print("[four-rank regression] %d tests, %d assertions, %d failures" % [tests, assertions, failures])
    quit(0 if failures == 0 else 1)
