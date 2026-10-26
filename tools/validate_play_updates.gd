extends Node

class FakeUpdater extends InappUpdate:
	var checks: int = 0
	var downloads: int = 0
	var installs: int = 0

	func _bind() -> void:
		pass

	func is_available() -> bool:
		return true

	func is_flexible_allowed() -> bool:
		return true

	func get_install_status() -> int:
		return INSTALL_STATUS_UNKNOWN

	func check_for_update() -> void:
		checks += 1

	func start_flexible_update() -> void:
		downloads += 1

	func complete_flexible_update() -> void:
		installs += 1


var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var app: AppRoot = load("res://scenes/app/app_root.tscn").instantiate()
	add_child(app)
	var fake := FakeUpdater.new()
	app.add_child(fake)
	app._play_updater = fake
	_check(app.show_hub(), "Hub opens for update offer")
	_check(fake.checks == 1, "Opening the hub checks Play once")
	app._on_play_update_available(8, 0)
	_check(app._play_update_dialog != null and app._play_update_dialog.visible,
		"Available update shows a hub prompt")
	_check(app._play_update_dialog_action == "download", "Regular update uses flexible download")
	app._on_play_update_confirmed()
	_check(fake.downloads == 1, "Download action starts the flexible flow")
	app._on_play_update_downloaded()
	_check(app._play_update_dialog_action == "install", "Completed download offers a restart")
	app._on_play_update_confirmed()
	_check(fake.installs == 1, "Restart action completes the flexible update")
	app.queue_free()
	print("Play update checks: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
