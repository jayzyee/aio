extends Node
## Project-agnostic headless task contract regression suite.

var passed := 0
var failed := 0


func _ready() -> void:
	Store.set_root("user://project_jobs_probe_%d/" % int(Time.get_unix_time_from_system()))
	var project := Store.new_project("Generic task fixture", "Verify arbitrary project task contracts")
	var relative := "studio/projects/" + str(project.id)
	var root_uri := Store.root.path_join(relative)
	var root_absolute := ProjectSettings.globalize_path(root_uri)
	DirAccess.make_dir_recursive_absolute(root_absolute)
	var copied := _copy_fixture("res://tests/fixtures/generic_task_project", root_absolute)
	DirAccess.make_dir_recursive_absolute(root_absolute.path_join(".aoi"))
	var hidden_manifest_source := FileAccess.open("res://tests/fixtures/generic_task_project/.aoi/tasks.json", FileAccess.READ)
	if hidden_manifest_source != null:
		var hidden_manifest_output := FileAccess.open(root_absolute.path_join(".aoi/tasks.json"), FileAccess.WRITE)
		if hidden_manifest_output != null:
			hidden_manifest_output.store_string(hidden_manifest_source.get_as_text())
			hidden_manifest_output.close()
		hidden_manifest_source.close()
	project["studio_local_path"] = relative
	Store.save_project(project)
	await get_tree().process_frame

	_check("fixture_copy_succeeded", bool(copied.get("ok", false)))
	var info := JobRunner.inspect_project(str(project.id))
	_check("detects_multiple_project_formats", bool(info.get("ok", false)) and "godot" in info.get("detected_types", []) and "python" in info.get("detected_types", []) and "node" in info.get("detected_types", []))
	var listed := JobRunner.list_project_tasks(str(project.id))
	_check("discovers_project_owned_tasks", bool(listed.get("ok", false)) and listed.get("tasks", []).size() == 2 and str(listed.tasks[0].get("id", "")) == "count-up")
	_check("marks_missing_runtime_as_unavailable", bool(listed.get("ok", false)) and not bool(listed.tasks[1].get("available_on_device", true)))
	_check("reads_project_file_without_screen_preview", bool(JobRunner.read_project_file(str(project.id), "README.md").get("ok", false)))
	_check("rejects_project_path_traversal", not bool(JobRunner.read_project_file(str(project.id), "../settings.cfg").get("ok", true)))
	_check("writes_project_files_inside_root", bool(JobRunner.write_project_file(str(project.id), "notes/generated.md", "# Test output\n").get("ok", false)) and FileAccess.file_exists(root_absolute.path_join("notes/generated.md")))
	_check("rejects_write_path_traversal", not bool(JobRunner.write_project_file(str(project.id), "../../outside.txt", "bad").get("ok", true)))

	var start := JobRunner.start_project_task(str(project.id), "count-up", {"steps": 4096})
	var job_id := str(start.get("job_id", ""))
	_check("starts_generic_headless_task", bool(start.get("ok", false)) and job_id != "" and str(start.get("state", "")) == "running")
	_check("pause_preserves_checkpoint", bool(JobRunner.pause_job(job_id).get("ok", false)) and str(JobRunner.get_job(job_id).get("state", "")) == "paused")
	_check("resume_reloads_task_from_checkpoint", bool(JobRunner.resume_job(job_id).get("ok", false)) and str(JobRunner.get_job(job_id).get("state", "")) == "running")

	var frames := 0
	while frames < 120 and str(JobRunner.get_job(job_id).get("state", "")) == "running":
		await get_tree().process_frame
		frames += 1
	var completed := JobRunner.get_job(job_id)
	_check("runs_without_preview_or_PC", str(completed.get("state", "")) == "completed")
	_check("reports_progress_and_steps", float(completed.get("progress", 0.0)) == 1.0 and int(completed.get("step_count", 0)) > 0)
	var metrics_read := JobRunner.read_artifact(job_id, "metrics.json")
	var metrics: Variant = JSON.parse_string(str(metrics_read.get("content", "")))
	_check("saves_machine_readable_metrics", bool(metrics_read.get("ok", false)) and metrics is Dictionary and int(metrics.get("completed_steps", 0)) == 4096)
	var output_read := JobRunner.read_artifact(job_id, "output.txt")
	_check("saves_custom_task_artifacts", bool(output_read.get("ok", false)) and str(output_read.get("content", "")).contains("checksum="))
	var report := JobRunner.read_artifact(job_id, "report.md")
	_check("generates_generic_run_report", bool(report.get("ok", false)) and str(report.get("content", "")).contains("Project task report"))
	_check("rejects_unsafe_artifact_paths", not bool(JobRunner.read_artifact(job_id, "../../settings.cfg").get("ok", true)))

	DirAccess.make_dir_recursive_absolute(root_absolute.path_join(".aoi"))
	var invalid_manifest := FileAccess.open(root_uri.path_join(".aoi/tasks.json"), FileAccess.WRITE)
	if invalid_manifest != null:
		invalid_manifest.store_string("{\"schema_version\":1,\"tasks\":[{\"id\":\"escape\",\"runtime\":\"gdscript_steps\",\"script\":\"../evil.gd\"}]}")
		invalid_manifest.close()
	_check("rejects_unsafe_task_script_paths", not bool(JobRunner.list_project_tasks(str(project.id)).get("ok", true)))
	_check("keeps_jobs_scoped_to_project", JobRunner.list_jobs(str(project.id)).size() == 1 and JobRunner.list_jobs("another-project").is_empty())

	# Restore a safe manifest but point it at a deliberately invalid script to test compiler rejection.
	DirAccess.make_dir_recursive_absolute(root_absolute.path_join(".aoi"))
	var bad_manifest := FileAccess.open(root_uri.path_join(".aoi/tasks.json"), FileAccess.WRITE)
	if bad_manifest != null:
		bad_manifest.store_string(JSON.stringify({"schema_version": 1, "tasks": [{"id":"count-up", "name":"Bad task", "runtime":"gdscript_steps", "script":"tasks/bad.gd", "parameters": []}]}))
		bad_manifest.close()
	DirAccess.make_dir_recursive_absolute(root_absolute.path_join("tasks"))
	var bad := FileAccess.open(root_uri.path_join("tasks/bad.gd"), FileAccess.WRITE)
	if bad != null:
		bad.store_string("extends RefCounted\n\nfunc unrelated_helper() -> void:\n\tpass\n")
		bad.close()
	var bad_start := JobRunner.start_project_task(str(project.id), "count-up", {})
	var bad_job_id := str(bad_start.get("job_id", ""))
	_check("rejects_task_scripts_without_required_start_and_step_contract", not bool(bad_start.get("ok", true)))
	var cancelled_failed_job := JobRunner.cancel_job(bad_job_id)
	_check("stop_cannot_discard_a_recoverable_failed_run", not bool(cancelled_failed_job.get("ok", true)) and str(JobRunner.get_job(bad_job_id).get("state", "")) == "failed")

	# Restore the valid task again before cancellation coverage.
	var restored_manifest := FileAccess.open(root_uri.path_join(".aoi/tasks.json"), FileAccess.WRITE)
	if restored_manifest != null:
		var source_manifest := FileAccess.open("res://tests/fixtures/generic_task_project/.aoi/tasks.json", FileAccess.READ)
		if source_manifest != null:
			restored_manifest.store_string(source_manifest.get_as_text())
			source_manifest.close()
		restored_manifest.close()
	var cancelled := JobRunner.start_project_task(str(project.id), "count-up", {"steps": 10000})
	var cancelled_id := str(cancelled.get("job_id", ""))
	var paused_cancel_start := JobRunner.pause_job(cancelled_id)
	var paused_cancel := JobRunner.cancel_job(cancelled_id)
	var still_paused := str(JobRunner.get_job(cancelled_id).get("state", "")) == "paused"
	var resumed_cancel := JobRunner.resume_job(cancelled_id)
	var stopped := JobRunner.cancel_job(cancelled_id)
	_check("stop_preserves_paused_run_until_explicit_resume", bool(cancelled.get("ok", false)) and bool(paused_cancel_start.get("ok", false)) and not bool(paused_cancel.get("ok", true)) and still_paused and bool(resumed_cancel.get("ok", false)) and bool(stopped.get("ok", false)) and str(JobRunner.get_job(cancelled_id).get("state", "")) == "cancelled")

	JobRunner._jobs.clear()
	var runs_root := ProjectSettings.globalize_path(Store.root.path_join("studio/runs"))
	var retention_base := Time.get_unix_time_from_system() + 1000.0
	for index in range(83):
		var retention_id := "retention_%03d" % index
		var retention_job := {"id":retention_id,"project_id":"retention-fixture","state":"completed","created_at":retention_base + index,"resumable":false}
		JobRunner._jobs[retention_id] = retention_job
		JobRunner._save_job(retention_job)
	for state in ["paused", "failed", "interrupted"]:
		var protected_id := "retention_%s" % state
		var protected_job := {"id":protected_id,"project_id":"retention-fixture","state":state,"created_at":retention_base + 100.0,"resumable":true}
		JobRunner._jobs[protected_id] = protected_job
		JobRunner._save_job(protected_job)
	JobRunner._jobs.clear()
	JobRunner._load_recent_jobs()
	_check("run_retention_caps_terminal_history", JobRunner.list_jobs("").size() <= 80 and not FileAccess.file_exists(runs_root.path_join("retention_000").path_join("job.json")) and FileAccess.file_exists(runs_root.path_join("retention_082").path_join("job.json")))
	_check("run_retention_keeps_paused_failed_and_interrupted_checkpoints", JobRunner.get_job("retention_paused").size() > 0 and JobRunner.get_job("retention_failed").size() > 0 and JobRunner.get_job("retention_interrupted").size() > 0)

	var errors := failed
	print("PROJECT_JOB_SUMMARY %d/%d passed" % [passed, passed + failed])
	get_tree().quit(1 if errors > 0 else 0)


func _copy_fixture(source_root: String, target_root: String) -> Dictionary:
	var dir := DirAccess.open(source_root)
	if dir == null: return {"ok": false, "error": "fixture folder missing"}
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name not in [".", ".."]:
			var src := source_root.path_join(name)
			var dst := target_root.path_join(name)
			if dir.current_is_dir():
				DirAccess.make_dir_recursive_absolute(dst)
				var nested := _copy_fixture(src, dst)
				if not bool(nested.get("ok", false)): dir.list_dir_end(); return nested
			else:
				DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
				if name == "project.godot.fixture": dst = target_root.path_join("project.godot")
				var input := FileAccess.open(src, FileAccess.READ)
				if input == null: dir.list_dir_end(); return {"ok":false,"error":"cannot read fixture file"}
				var bytes := input.get_buffer(input.get_length()); input.close()
				var output := FileAccess.open(dst, FileAccess.WRITE)
				if output == null: dir.list_dir_end(); return {"ok":false,"error":"cannot write fixture file"}
				output.store_buffer(bytes); output.close()
		name = dir.get_next()
	dir.list_dir_end()
	return {"ok": true}


func _check(label: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("PROJECT_JOB_", label, " PASS")
	else:
		failed += 1
		print("PROJECT_JOB_", label, " FAIL")
