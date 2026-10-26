extends TestCase

func test_named_rival_is_sent_and_rejected_create_stops_retrying() -> void:
	var client := OnlineGameApiClient.new()
	client.start_verified_ai(AiEnums.Difficulty.MEDIUM, "rival_07")
	check_eq(client._create_payload.get("rivalId", ""), "rival_07",
		"verified match creation carries the stable rival ID")
	check_eq(int(client._create_payload.get("difficulty", -1)), AiEnums.Difficulty.MEDIUM,
		"verified match creation carries the rival's tier")
	var messages: Array[String] = []
	client.connection_changed.connect(func(_connected: bool, message: String) -> void:
		messages.append(message))
	var request := HTTPRequest.new()
	client._request = request
	client._completed(HTTPRequest.RESULT_SUCCESS, 400, PackedStringArray(),
		"{\"error\":\"INVALID_REQUEST\"}".to_utf8_buffer(), request, "create")
	check(not client._wanted and client._create_payload.is_empty(),
		"invalid match request does not retry indefinitely")
	check_eq(messages.back(), "The AI rival service rejected this match request.",
		"rejection gives the caller a specific fallback signal")
	client.free()
