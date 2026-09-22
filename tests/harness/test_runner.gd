extends SceneTree

## Headless smoke-test runner (Milestone 0).
##
## Usage:
##   godot --headless --path <project-dir> --script res://tests/harness/test_runner.gd
##
## Or use the repeatable wrapper: tools/validate.cmd (Windows) / tools/validate.sh.
##
## The runner discovers every `test_*.gd` under res://tests/unit and
## res://tests/integration, runs the public `test_` methods of each discovered
## test case, prints a per-test report, and exits with 0 only when every
## assertion passed.
##
## Discovery uses duck typing (`has_method("check")`) rather than the TestCase
## global class, so the harness still runs if the editor's global class cache has
## not been generated yet.

const TEST_DIRECTORIES: PackedStringArray = [
	"res://tests/unit",
	"res://tests/integration",
]


func _initialize() -> void:
	quit(_run_suites())


func _run_suites() -> int:
	var script_paths: PackedStringArray = _collect_test_scripts()
	if script_paths.is_empty():
		print("[harness] no test scripts found in %s" % ", ".join(TEST_DIRECTORIES))
		return 1

	var suite_count: int = 0
	var test_count: int = 0
	var assertion_count: int = 0
	var failure_lines: PackedStringArray = PackedStringArray()

	for script_path: String in script_paths:
		var test_case: Object = _instantiate_test_case(script_path)
		if test_case == null:
			failure_lines.append("%s - could not be instantiated" % script_path)
			continue
		suite_count += 1
		print("[harness] %s" % script_path)
		for method_name: String in _test_method_names(test_case):
			var failures_before: int = test_case.failures.size()
			var assertions_before: int = test_case.assertions
			test_case.call(method_name)
			var assertions_ran: int = test_case.assertions - assertions_before
			assertion_count += assertions_ran
			test_count += 1
			if assertions_ran == 0 and test_case.failures.size() == failures_before:
				# A GDScript runtime error aborts the test method without
				# recording an assertion failure, which would otherwise be
				# reported as a pass. Every legitimate test evaluates at least
				# one assertion, so zero assertions means it did not really run.
				test_case.failures.append(
					"no assertions were evaluated; the test aborted early (likely a script error)"
				)
			if test_case.failures.size() > failures_before:
				print("  FAIL %s" % method_name)
				for index: int in range(failures_before, test_case.failures.size()):
					failure_lines.append("%s::%s - %s" % [script_path, method_name, test_case.failures[index]])
			else:
				print("  ok   %s" % method_name)

	print("")
	print("[harness] suites: %d  tests: %d  assertions: %d  failures: %d" % [
		suite_count,
		test_count,
		assertion_count,
		failure_lines.size(),
	])

	if failure_lines.is_empty():
		print("[harness] PASS")
		return 0

	print("[harness] FAIL")
	for line: String in failure_lines:
		print("  - %s" % line)
	return 1


func _collect_test_scripts() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for directory: String in TEST_DIRECTORIES:
		_collect_from_directory(directory, found)
	found.sort()
	return found


func _collect_from_directory(directory: String, found: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_from_directory(directory.path_join(entry), found)
		elif entry.begins_with("test_") and entry.ends_with(".gd"):
			found.append(directory.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()


func _instantiate_test_case(script_path: String) -> Object:
	var script_resource: Resource = load(script_path)
	if not (script_resource is GDScript):
		push_error("[harness] %s is not a GDScript file" % script_path)
		return null
	var script: GDScript = script_resource as GDScript
	if not script.can_instantiate():
		push_error(
			"[harness] %s failed to compile, so its tests cannot run" % script_path
		)
		return null
	var instance: Variant = script.new()
	if instance == null or not (instance is Object) or not (instance as Object).has_method("check"):
		push_error("[harness] %s must extend res://tests/harness/test_case.gd" % script_path)
		return null
	return instance as Object


func _test_method_names(test_case: Object) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var script: GDScript = test_case.get_script() as GDScript
	if script == null:
		return names
	for method: Dictionary in script.get_script_method_list():
		var method_name: String = String(method.get("name", ""))
		if method_name.begins_with("test_"):
			names.append(method_name)
	names.sort()
	return names
