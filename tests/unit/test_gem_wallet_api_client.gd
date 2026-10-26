extends TestCase

class FakeWalletClient extends GemWalletApiClient:
	var requests: Array[Dictionary] = []

	func _send_http(request: HTTPRequest, url: String, headers: PackedStringArray) -> Error:
		requests.append({"request": request, "url": url, "headers": headers})
		return OK

	func complete(balance: int) -> void:
		var request: HTTPRequest = _request
		_on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(),
			JSON.stringify({"balance": balance, "transactions": []}).to_utf8_buffer(),
			request, access_token, account_id)


func test_settled_match_refresh_is_not_lost_during_an_earlier_wallet_read() -> void:
	var client := FakeWalletClient.new()
	client.set_credentials("token", "account")
	check_eq(client.requests.size(), 1, "login starts a wallet read")
	client.fetch()
	client.fetch()
	check_eq(client.requests.size(), 1, "concurrent refreshes coalesce")
	client.complete(0)
	check_eq(client.requests.size(), 2, "settlement starts a fresh read after the earlier one")
	client.complete(20)
	check_eq(int(client.current.get("balance", -1)), 20, "wallet keeps the confirmed balance")
	check_eq(client.requests.size(), 2, "one queued refresh makes one extra request")
	client.free()


func test_account_change_discards_an_old_queued_refresh() -> void:
	var client := FakeWalletClient.new()
	client.set_credentials("old-token", "old-account")
	client.fetch()
	client.set_credentials("new-token", "new-account")
	check_eq(client.requests.size(), 2, "new account starts its own wallet read")
	check(not client._refresh_queued, "old account refresh was discarded")
	client.complete(4)
	check_eq(int(client.current.get("balance", -1)), 4, "new account balance is used")
	check_eq(client.requests.size(), 2, "old queued refresh did not send again")
	client.free()
