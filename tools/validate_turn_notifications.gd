extends Node

var failures: int = 0
var alerts: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _state(version: int, active: String, status: String = "active") -> Dictionary:
	return {"matchId": "match-1", "seat": "a", "version": version, "status": status,
		"turn": {"active_player_id": active, "phase": TurnEnums.MatchPhase.AWAIT_ACTION},
		"opponent": {"displayName": "Rival"}}


func _run() -> void:
	var hub: HubScreen = load("res://scenes/hub/hub_screen.tscn").instantiate()
	add_child(hub)
	var toggle: CheckButton = hub.get_node("%PushNotificationsToggle")
	_check(toggle != null, "Settings exposes the notification switch")
	_check(toggle.disabled == not TurnNotifications.is_available(), "Switch reflects platform availability")
	hub.queue_free()
	var service: Node = load("res://scripts/application/turn_notification_service.gd").new()
	add_child(service)
	service.enabled = true # Test the transition detector without a mobile singleton.
	service.turn_alert_due.connect(func(name: String) -> void: alerts.append(name))
	service.observe_online_state(_state(1, "b"), "account-a")
	_check(alerts.is_empty(), "First snapshot must establish a baseline")
	service.observe_online_state(_state(2, "a"), "account-a")
	_check(alerts == ["Rival"], "Opponent-to-player transition should alert once")
	service.observe_online_state(_state(2, "a"), "account-a")
	_check(alerts.size() == 1, "Repeated polls must not alert again")
	service.observe_online_state(_state(3, "a"), "account-a")
	_check(alerts.size() == 1, "Updates within the player's turn must not alert")
	service.observe_online_state(_state(4, "b"), "account-a")
	service.enabled = false
	service.observe_online_state(_state(5, "a"), "account-a")
	_check(alerts.size() == 1, "Disabled alerts must stay quiet")
	service.enabled = true
	service.observe_online_state(_state(6, "b"), "account-a")
	service.observe_online_state(_state(7, "a", "completed"), "account-a")
	_check(alerts.size() == 1, "Completed matches must stay quiet")
	service.observe_online_state(_state(8, "a"), "account-b")
	_check(alerts.size() == 1, "Account changes must establish a new baseline")
	service.queue_free()
	print("Turn notification checks: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
