extends "res://tests/harness/test_case.gd"


func test_poker_and_adjacency_warnings_use_the_label_below_the_board() -> void:
	var screen := GameScreen.new()
	screen.board_message_label = Label.new()
	screen.add_child(screen.board_message_label)
	for message: String in [
		GameSessionController.INVALID_POKER_HAND_NOTICE,
		GameSessionController.NOT_CONNECTED_NOTICE,
	]:
		screen._header_notice = message
		screen._refresh_board_message()
		check_eq(screen.board_message_label.text, message, "warning is shown below the board: %s" % message)
		check(screen._is_header_notice(message), "warning is routed through the board caption: %s" % message)
		check(BoardEffectLayer.HEADER_ONLY_REASONS.has(message), "warning is suppressed on the board itself: %s" % message)
	screen.free()
