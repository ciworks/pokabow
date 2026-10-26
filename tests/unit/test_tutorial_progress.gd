extends TestCase


func test_first_run_exit_and_completion_are_scoped_to_account() -> void:
	var directory := "user://tutorial_progress_test"
	var absolute_directory: String = ProjectSettings.globalize_path(directory)
	check(DirAccess.make_dir_recursive_absolute(absolute_directory) == OK, "test directory is available")
	var first := "tutorial-test-first"
	var second := "tutorial-test-second"
	var first_path: String = TutorialProgressStore.path_for(first, directory)
	var second_path: String = TutorialProgressStore.path_for(second, directory)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(first_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(second_path))
	check(not TutorialProgressStore.should_show(first, directory), "existing players are not auto-enrolled")
	check(TutorialProgressStore.mark_eligible(first, directory), "new player becomes eligible")
	check(TutorialProgressStore.should_show(first, directory), "eligible player sees tutorial on launch")
	check(not TutorialProgressStore.should_show(second, directory), "another account is unaffected")
	check(TutorialProgressStore.mark_eligible(second, directory), "second player becomes eligible separately")
	check(TutorialProgressStore.finish(first, false, directory), "completion is saved")
	check(not TutorialProgressStore.should_show(first, directory), "completed player is not prompted")
	check(TutorialProgressStore.mark_eligible(first, directory), "re-registration check preserves stored choice")
	check_eq(TutorialProgressStore.status(first, directory), TutorialProgressStore.STATUS_COMPLETE,
		"completed status survives eligibility check")
	check(TutorialProgressStore.should_show(second, directory), "other player remains pending")
	check(TutorialProgressStore.finish(second, true, directory), "never choice is saved")
	check_eq(TutorialProgressStore.status(second, directory), TutorialProgressStore.STATUS_NEVER,
		"never choice is stored")
	check(not TutorialProgressStore.should_show(second, directory), "never choice suppresses automatic guide")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(first_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(second_path))
	DirAccess.remove_absolute(absolute_directory)


func test_missing_account_cannot_create_tutorial_state() -> void:
	check_eq(TutorialProgressStore.path_for(""), "", "missing account has no path")
	check(not TutorialProgressStore.mark_eligible(""), "missing account cannot be enrolled")
	check(not TutorialProgressStore.finish("", true), "missing account cannot save a choice")
