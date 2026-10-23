extends SceneTree
## One bounded server job; no HTTP listener, UI, local saves or AI coordinator.
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	var input: FileAccess = FileAccess.open(args[0], FileAccess.READ)
	if input == null:
		quit(2)
		return
	var payload: Variant = JSON.parse_string(input.get_as_text())
	input.close()
	if not payload is Dictionary:
		quit(2)
		return
	var result: Dictionary = OnlineRules.execute(payload)
	var output: FileAccess = FileAccess.open(args[1], FileAccess.WRITE)
	if output == null:
		quit(2)
		return
	output.store_string(JSON.stringify(result))
	output.close()
	quit(0)
