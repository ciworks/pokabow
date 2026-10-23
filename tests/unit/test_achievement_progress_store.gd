extends TestCase

const PATH: String = "res://.tmp/test-achievement-progress-state.json"


func test_pending_unlock_id_round_trips() -> void:
	DirAccess.remove_absolute(PATH)
	check(UsersStateStore.queue_achievement_ids(["edge_cluster"], PATH), "unlock ID is queued")
	check_eq(UsersStateStore.pending_achievement_ids(PATH), ["edge_cluster"], "unlock ID reloads as text")
	check(UsersStateStore.clear_achievement_ids(["edge_cluster"], PATH), "acknowledged unlock is removed")
	check(UsersStateStore.pending_achievement_ids(PATH).is_empty(), "unlock queue is empty")
	DirAccess.remove_absolute(PATH)


func test_event_queue_deduplicates_and_survives_reload() -> void:
	DirAccess.remove_absolute(PATH)
	var first: Array[Dictionary] = [{"eventId": "match:score:1", "metric": "two_pair_scored"}]
	check(UsersStateStore.queue_achievement_progress(first, PATH), "the first event is saved")
	check(UsersStateStore.queue_achievement_progress(first, PATH), "retrying the same event is safe")
	check_eq(UsersStateStore.pending_achievement_progress(PATH).size(), 1, "the event is persisted once")
	check(not bool(UsersStateStore.pending_achievement_progress(PATH)[0].get("submitted", true)), "a new event can be projected locally")
	check(UsersStateStore.mark_achievement_progress_submitted(["match:score:1"], PATH), "the attempted submission is saved")
	check(bool(UsersStateStore.pending_achievement_progress(PATH)[0].get("submitted", false)), "a retry cannot inflate local projected progress")
	check(UsersStateStore.clear_achievement_progress(["match:score:1"], PATH), "an acknowledged event is removed")
	check(UsersStateStore.pending_achievement_progress(PATH).is_empty(), "the queue is empty after acknowledgement")
	DirAccess.remove_absolute(PATH)


func test_catalog_and_announcements_survive_reload() -> void:
	DirAccess.remove_absolute(PATH)
	var rows: Array[Dictionary] = [{"id": "two_pair_10", "metric": "two_pair_scored", "target": 10, "progress": 9}]
	check(UsersStateStore.save_achievement_catalog(rows, PATH), "catalogue is saved")
	check_eq(UsersStateStore.achievement_catalog(PATH)[0].id, "two_pair_10", "catalogue reloads")
	check(not UsersStateStore.achievement_was_announced("two_pair_10", PATH), "new badge has not been announced")
	check(UsersStateStore.mark_achievement_announced("two_pair_10", PATH), "announcement is saved")
	check(UsersStateStore.achievement_was_announced("two_pair_10", PATH), "announcement reloads")
	DirAccess.remove_absolute(PATH)
