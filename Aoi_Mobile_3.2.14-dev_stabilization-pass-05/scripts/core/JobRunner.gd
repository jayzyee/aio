extends Node
## Project-agnostic, resumable task runner for imported Aoi projects.
## Projects may declare headless GDScript tasks in .aoi/tasks.json.
## Task scripts run in Aoi's process with the app's permissions: this is a TRUSTED-CODE
## runner, not an OS security sandbox. Every task start/resume requires explicit approval.

signal jobs_changed
signal job_progress(job_id: String, progress: float, detail: String)
signal job_finished(result: Dictionary)

const TASK_MANIFEST := ".aoi/tasks.json"
const JOBS_DIRECTORY := "studio/runs"
const MAX_MANIFEST_BYTES := 128 * 1024
const MAX_TASKS := 32
const MAX_TASK_SCRIPT_BYTES := 512 * 1024
const MAX_CHECKPOINT_BYTES := 512 * 1024
const MAX_ARTIFACT_BYTES := 4 * 1024 * 1024
const MAX_LOG_BYTES := 128 * 1024
const MAX_JOB_RUNTIME_SECONDS := 1800
const MAX_STEP_UNITS := 256
const STEP_WARNING_MS := 80
const MAX_RECENT_JOBS := 80
# Cooperative tasks may step every rendered frame. Keep the durable checkpoint
# frequent enough for recovery without writing JSON and refreshing the UI at 60 Hz.
const CHECKPOINT_PERSIST_INTERVAL := 1.0
const JOB_UI_UPDATE_INTERVAL := 0.20

var _jobs: Dictionary = {}
var _instances: Dictionary = {}
var _cancelled: Dictionary = {}
var _active_ids: Array[String] = []
var _last_checkpoint_persist_at: Dictionary = {}
var _last_ui_update_at: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_global(JOBS_DIRECTORY))
	_load_recent_jobs()
	set_process(true)


func inspect_project(project_id: String) -> Dictionary:
	var project := Store.get_project(project_id)
	if project.is_empty():
		return {"ok": false, "error": "Project not found."}
	var root_uri := _project_root(project)
	if root_uri == "":
		return {"ok": false, "error": "This project has no local workspace. Import it onto this device or connect its external runtime."}
	var markers := _detect_project_types(root_uri)
	var project_kind := _project_kind(project, root_uri)
	var manifest_result := _read_task_manifest(root_uri)
	var tasks: Array = manifest_result.get("tasks", []) if bool(manifest_result.get("ok", false)) else []
	return {
		"ok": true,
		"project_id": project_id,
		"name": str(project.get("title", "Untitled project")),
		"root": root_uri,
		"root_exists": DirAccess.open(root_uri) != null,
		"detected_types": markers,
		"primary_type": _primary_type(markers),
		"project_kind": project_kind,
		"task_manifest": TASK_MANIFEST,
		"task_manifest_exists": bool(manifest_result.get("exists", false)),
		"task_manifest_error": str(manifest_result.get("error", "")),
		"tasks": tasks,
		"task_count": tasks.size(),
		"runtimes": _available_runtimes()
	}


func list_project_tasks(project_id: String) -> Dictionary:
	var info := inspect_project(project_id)
	if not bool(info.get("ok", false)):
		return info
	var manifest := _read_task_manifest(str(info.get("root", "")))
	if not bool(manifest.get("ok", false)):
		return {"ok": false, "error": str(manifest.get("error", "No task manifest.")), "project": info}
	return {"ok": true, "project": info, "tasks": manifest.get("tasks", [])}


func start_project_task(project_id: String, task_id: String, parameters: Dictionary = {}) -> Dictionary:
	if _active_ids.size() >= 1:
		return {"ok": false, "error": "A local project task is already running. Wait for it or stop it before starting another."}
	var listed := list_project_tasks(project_id)
	if not bool(listed.get("ok", false)):
		return listed
	var task: Dictionary = {}
	for row in listed.get("tasks", []):
		if str(row.get("id", "")) == task_id:
			task = row
			break
	if task.is_empty():
		return {"ok": false, "error": "That task is not declared by this project's .aoi/tasks.json manifest."}
	if str(task.get("runtime", "")) != "gdscript_steps":
		return {"ok": false, "error": "Runtime '%s' is not available on this device. Connect a cloud Linux workspace or choose an installed runtime." % str(task.get("runtime", "unknown"))}
	var project: Dictionary = Store.get_project(project_id)
	var root_uri := _project_root(project)
	var script_path := str(task.get("script", ""))
	if not GodotSandbox.is_safe_project_path(script_path) or not script_path.ends_with(".gd"):
		return {"ok": false, "error": "The task script path is unsafe or is not a GDScript file."}
	var script_full_path := root_uri.path_join(script_path)
	if not FileAccess.file_exists(script_full_path):
		return {"ok": false, "error": "Task script is missing: %s" % script_path}
	var script_bytes := FileAccess.get_file_as_bytes(script_full_path)
	if script_bytes.size() > MAX_TASK_SCRIPT_BYTES:
		return {"ok": false, "error": "Task script exceeds the 512 KiB mobile limit."}
	var task_parameters := _validate_parameters(task.get("parameters", []), parameters)
	if not bool(task_parameters.get("ok", false)):
		return task_parameters
	var limits: Dictionary = task.get("limits", {}) if task.get("limits", {}) is Dictionary else {}
	var max_runtime := clampi(int(limits.get("max_runtime_seconds", 600)), 1, MAX_JOB_RUNTIME_SECONDS)
	var job_id := Store.new_id()
	var now := Time.get_unix_time_from_system()
	var job := {
		"id": job_id,
		"project_id": project_id,
		"project_name": str(project.get("title", "Project")),
		"task_id": task_id,
		"task_name": str(task.get("name", task_id)),
		"task_description": str(task.get("description", "")),
		"runtime": "gdscript_steps",
		"script": script_path,
		"state": "queued",
		"progress": 0.0,
		"summary": "Preparing trusted project task…",
		"parameters": task_parameters.get("values", {}),
		"checkpoint": {},
		"max_runtime_seconds": max_runtime,
		"created_at": now,
		"started_at": 0.0,
		"updated_at": now,
		"finished_at": 0.0,
		"elapsed_seconds": 0.0,
		"step_count": 0,
		"last_detail": "",
		"error": "",
		"resumable": true
	}
	_jobs[job_id] = job
	DirAccess.make_dir_recursive_absolute(_job_absolute(job_id).path_join("artifacts"))
	if not _save_job(job):
		_jobs.erase(job_id)
		return {"ok": false, "error": "Aoi could not create a durable run record. Check available storage and try again."}
	_job_log(job_id, "Starting project-declared task '%s' from %s." % [task_id, script_path])
	var initialized := _create_task_instance(job, root_uri, {})
	if not bool(initialized.get("ok", false)):
		job["state"] = "failed"
		job["error"] = str(initialized.get("error", "Task initialization failed."))
		job["summary"] = job.error
		job["finished_at"] = Time.get_unix_time_from_system()
		_save_job(job)
		jobs_changed.emit()
		return {"ok": false, "error": job.error, "job_id": job_id}
	job["state"] = "running"
	job["started_at"] = Time.get_unix_time_from_system()
	job["summary"] = "Running · 0%"
	job["checkpoint"] = initialized.get("state", {})
	var started_at := Time.get_unix_time_from_system()
	job["heartbeat_at"] = started_at
	if not _save_checkpoint(job_id, job["checkpoint"]):
		job["state"] = "failed"
		job["error"] = "Aoi could not safely save the initial task checkpoint. The task was not started."
		job["summary"] = job["error"]
		job["finished_at"] = Time.get_unix_time_from_system()
		job["resumable"] = false
		_save_job(job)
		return {"ok": false, "error": job["error"], "job_id": job_id}
	if not _save_job(job):
		job["state"] = "failed"
		job["error"] = "Aoi could not save the task state. The task was not started."
		job["summary"] = job["error"]
		job["finished_at"] = Time.get_unix_time_from_system()
		job["resumable"] = false
		_save_job(job)
		return {"ok": false, "error": job["error"], "job_id": job_id}
	_instances[job_id] = initialized.get("instance")
	_active_ids.append(job_id)
	_last_checkpoint_persist_at[job_id] = started_at
	_last_ui_update_at[job_id] = started_at
	_job_log(job_id, "Task started. Project source remains unchanged; outputs are written to this run's artifact folder.")
	jobs_changed.emit()
	job_progress.emit(job_id, 0.0, str(initialized.get("detail", "Task initialized.")))
	return {"ok": true, "job_id": job_id, "state": "running", "task": task_id, "runtime": "on-device GDScript task"}


func _process(_delta: float) -> void:
	if _active_ids.is_empty():
		return
	var current := _active_ids.duplicate()
	for job_id in current:
		if not _jobs.has(job_id):
			_active_ids.erase(job_id)
			continue
		var job: Dictionary = _jobs[job_id]
		if str(job.get("state", "")) != "running":
			_active_ids.erase(job_id)
			continue
		_step_job(job_id)


func _step_job(job_id: String) -> void:
	var job: Dictionary = _jobs[job_id]
	var instance: Variant = _instances.get(job_id)
	if instance == null or not is_instance_valid(instance):
		_finish_failed(job_id, "The project task instance is no longer available.")
		return
	var elapsed := _elapsed(job)
	if elapsed > float(job.get("max_runtime_seconds", 600)):
		_finish_failed(job_id, "Task exceeded its configured runtime limit.")
		return
	var context := _make_context(job_id)
	var state: Dictionary = job.get("checkpoint", {})
	var started := Time.get_ticks_msec()
	var response: Variant = instance.call("step", context, state, MAX_STEP_UNITS)
	var duration := Time.get_ticks_msec() - started
	if duration > STEP_WARNING_MS:
		_job_log(job_id, "Warning: task step took %d ms. Keep steps bounded so the mobile UI remains responsive." % duration)
	if not response is Dictionary:
		_finish_failed(job_id, "Task step must return a Dictionary result.")
		return
	if not bool(response.get("ok", true)):
		_finish_failed(job_id, str(response.get("error", "Task reported a failure.")))
		return
	var next_state: Variant = response.get("state", state)
	if not next_state is Dictionary or JSON.stringify(next_state).to_utf8_buffer().size() > MAX_CHECKPOINT_BYTES:
		_finish_failed(job_id, "Task checkpoint is invalid or exceeds the 512 KiB limit.")
		return
	job["checkpoint"] = next_state
	job["step_count"] = int(job.get("step_count", 0)) + 1
	job["elapsed_seconds"] = elapsed
	var progress := clampf(float(response.get("progress", job.get("progress", 0.0))), 0.0, 1.0)
	job["progress"] = progress
	var detail := str(response.get("detail", job.get("last_detail", "Working…"))).left(360)
	job["last_detail"] = detail
	job["summary"] = "%s · %d%%" % [str(job.get("task_name", "Task")), roundi(progress * 100.0)]
	if response.has("artifacts") and response.artifacts is Dictionary:
		for artifact_name in response.artifacts:
			var write_result := _write_artifact(job_id, str(artifact_name), response.artifacts[artifact_name])
			if not bool(write_result.get("ok", false)):
				_finish_failed(job_id, str(write_result.get("error", "Could not write task artifact.")))
				return
	if response.has("metrics") and response.metrics is Dictionary:
		job["metrics"] = response.metrics.duplicate(true)
		_write_artifact(job_id, "metrics.json", response.metrics)
	var now := Time.get_unix_time_from_system()
	job["heartbeat_at"] = now
	# The in-memory checkpoint advances on every cooperative step. Persist at a
	# bounded cadence; pause, failure, cancellation and completion force a save.
	var last_persist := float(_last_checkpoint_persist_at.get(job_id, 0.0))
	if now - last_persist >= CHECKPOINT_PERSIST_INTERVAL:
		if not _save_checkpoint(job_id, next_state) or not _save_job(job):
			_finish_failed(job_id, "The task is still running, but Aoi could not save its latest checkpoint. Work was stopped rather than continue without a recoverable state.")
			return
		_last_checkpoint_persist_at[job_id] = now
	# Keep progress responsive without emitting a scene refresh on every frame.
	var last_ui_update := float(_last_ui_update_at.get(job_id, 0.0))
	if now - last_ui_update >= JOB_UI_UPDATE_INTERVAL and not bool(response.get("done", false)):
		job_progress.emit(job_id, progress, detail)
		jobs_changed.emit()
		_last_ui_update_at[job_id] = now
	if bool(response.get("done", false)):
		_finish_completed(job_id, response)


func _finish_completed(job_id: String, response: Dictionary) -> void:
	var job: Dictionary = _jobs[job_id]
	var result: Dictionary = response.get("result", {}) if response.get("result", {}) is Dictionary else {}
	var metrics: Dictionary = response.get("metrics", {}) if response.get("metrics", {}) is Dictionary else {}
	var summary := str(response.get("summary", result.get("summary", "Task completed successfully."))).left(500)
	job["metrics"] = metrics.duplicate(true)
	job["result"] = result.duplicate(true)
	job["state"] = "completed"
	job["progress"] = 1.0
	job["summary"] = summary
	job["finished_at"] = Time.get_unix_time_from_system()
	job["elapsed_seconds"] = _elapsed(job)
	job["resumable"] = false
	if not _save_checkpoint(job_id, job.get("checkpoint", {})):
		_finish_failed(job_id, "The task completed, but Aoi could not safely persist its final checkpoint. The run is marked failed rather than reporting a result that may be lost.")
		return
	var result_write := _write_artifact(job_id, "result.json", result)
	if not bool(result_write.get("ok", false)):
		_finish_failed(job_id, "The task completed, but its result could not be saved: " + str(result_write.get("error", "storage error")))
		return
	if not metrics.is_empty():
		var metrics_write := _write_artifact(job_id, "metrics.json", metrics)
		if not bool(metrics_write.get("ok", false)):
			_finish_failed(job_id, "The task completed, but its metrics could not be saved: " + str(metrics_write.get("error", "storage error")))
			return
	var report := _build_report(job, result, metrics)
	var report_write := _write_artifact(job_id, "report.md", report)
	if not bool(report_write.get("ok", false)):
		_finish_failed(job_id, "The task completed, but its report could not be saved: " + str(report_write.get("error", "storage error")))
		return
	if not _save_job(job):
		_finish_failed(job_id, "The task completed, but Aoi could not persist the final run state. The result is retained, but completion was not confirmed.")
		return
	_job_log(job_id, summary)
	_instances.erase(job_id)
	_active_ids.erase(job_id)
	_last_checkpoint_persist_at.erase(job_id)
	_last_ui_update_at.erase(job_id)
	var output := {"ok": true, "job_id": job_id, "project_id": str(job.project_id), "state": "completed", "output": summary, "metrics": metrics}
	_prune_old_jobs(job_id)
	jobs_changed.emit()
	job_finished.emit(output)


func _finish_failed(job_id: String, message: String) -> void:
	if not _jobs.has(job_id): return
	var job: Dictionary = _jobs[job_id]
	job["state"] = "failed"
	job["error"] = message.left(1200)
	job["summary"] = "Failed · " + message.left(320)
	job["finished_at"] = Time.get_unix_time_from_system()
	job["elapsed_seconds"] = _elapsed(job)
	job["resumable"] = true
	_save_checkpoint(job_id, job.get("checkpoint", {}))
	_save_job(job)
	_job_log(job_id, "ERROR: " + message)
	_instances.erase(job_id)
	_active_ids.erase(job_id)
	_last_checkpoint_persist_at.erase(job_id)
	_last_ui_update_at.erase(job_id)
	_prune_old_jobs(job_id)
	jobs_changed.emit()
	job_finished.emit({"ok": false, "job_id": job_id, "project_id": str(job.get("project_id", "")), "state": "failed", "error": message})


func pause_job(job_id: String) -> Dictionary:
	if not _jobs.has(job_id) or str(_jobs[job_id].get("state", "")) != "running":
		return {"ok": false, "error": "Only a running job can be paused."}
	var job: Dictionary = _jobs[job_id]
	var previous_summary := str(job.get("summary", "Running"))
	job["state"] = "paused"
	job["elapsed_seconds"] = _elapsed(job)
	job["summary"] = "Paused · %d%%" % roundi(float(job.get("progress", 0.0)) * 100.0)
	if not _save_checkpoint(job_id, job.get("checkpoint", {})) or not _save_job(job):
		job["state"] = "running"
		job["summary"] = previous_summary
		return {"ok": false, "error": "Aoi could not safely save this pause. The run remains active; check storage and try again."}
	_active_ids.erase(job_id)
	_last_checkpoint_persist_at.erase(job_id)
	_last_ui_update_at.erase(job_id)
	jobs_changed.emit()
	return {"ok": true, "job_id": job_id, "state": "paused", "summary": job.summary}


func resume_job(job_id: String) -> Dictionary:
	if not _jobs.has(job_id): return {"ok": false, "error": "Run not found."}
	var job: Dictionary = _jobs[job_id]
	if str(job.get("state", "")) not in ["paused", "interrupted", "failed"] or not bool(job.get("resumable", true)):
		return {"ok": false, "error": "This run cannot be resumed."}
	if not _active_ids.is_empty(): return {"ok": false, "error": "Another on-device task is already running."}
	var project := Store.get_project(str(job.get("project_id", "")))
	var root_uri := _project_root(project)
	var restored := _create_task_instance(job, root_uri, job.get("checkpoint", {}))
	if not bool(restored.get("ok", false)):
		return restored
	var previous_state := str(job.get("state", "interrupted"))
	var previous_summary := str(job.get("summary", "Interrupted"))
	job["state"] = "running"
	job["started_at"] = Time.get_unix_time_from_system() - float(job.get("elapsed_seconds", 0.0))
	job["summary"] = "Resumed · %d%%" % roundi(float(job.get("progress", 0.0)) * 100.0)
	job["heartbeat_at"] = Time.get_unix_time_from_system()
	if not _save_job(job):
		job["state"] = previous_state
		job["summary"] = previous_summary
		return {"ok": false, "error": "Aoi could not save the resumed run state. The task was not restarted."}
	_instances[job_id] = restored.get("instance")
	_active_ids.append(job_id)
	_last_checkpoint_persist_at[job_id] = Time.get_unix_time_from_system()
	_last_ui_update_at[job_id] = Time.get_unix_time_from_system()
	_job_log(job_id, "Run resumed from its last saved checkpoint.")
	jobs_changed.emit()
	return {"ok": true, "job_id": job_id, "state": "running"}


func cancel_job(job_id: String) -> Dictionary:
	if not _jobs.has(job_id): return {"ok": false, "error": "Run not found."}
	var job: Dictionary = _jobs[job_id]
	if str(job.get("state", "")) not in ["running", "queued"]:
		return {"ok": false, "error": "Only an active run can be stopped. Paused and recoverable runs are retained for review or resume."}
	_cancelled[job_id] = true
	job["finished_at"] = Time.get_unix_time_from_system()
	job["elapsed_seconds"] = _elapsed(job)
	var checkpoint_saved := _save_checkpoint(job_id, job.get("checkpoint", {}))
	job["state"] = "cancelled" if checkpoint_saved else "interrupted"
	job["summary"] = "Stopped by user · checkpoint preserved" if checkpoint_saved else "Interrupted · previous checkpoint retained"
	job["error"] = "" if checkpoint_saved else "The task was stopped, but its latest checkpoint could not be confirmed."
	job["resumable"] = not checkpoint_saved
	var job_saved := _save_job(job)
	_instances.erase(job_id)
	_active_ids.erase(job_id)
	_last_checkpoint_persist_at.erase(job_id)
	_last_ui_update_at.erase(job_id)
	_job_log(job_id, "Run cancelled by user. The last completed step and artifacts were preserved.")
	if not job_saved:
		job["state"] = "interrupted"
		job["summary"] = "Interrupted · checkpoint preserved"
		job["error"] = "Aoi stopped the task but could not persist its final run state."
		job["resumable"] = true
		if not _save_job(job):
			push_error("Aoi could not persist the recoverable stopped state for run: " + job_id)
	_prune_old_jobs(job_id)
	jobs_changed.emit()
	if not checkpoint_saved or not job_saved:
		return {"ok": false, "job_id": job_id, "state": "interrupted", "resumable": true, "error": "The task was stopped, but Aoi could not confirm its latest state. The previous checkpoint remains available to resume."}
	return {"ok": true, "job_id": job_id, "state": "cancelled"}


func interrupt_stale_job(job_id: String, stale_after_seconds: float = 100.0) -> Dictionary:
	if not _jobs.has(job_id):
		return {"ok": false, "error": "Run not found."}
	var job: Dictionary = _jobs[job_id]
	if str(job.get("state", "")) not in ["running", "queued"]:
		return {"ok": false, "error": "The run is no longer active."}
	var now := Time.get_unix_time_from_system()
	var last_heartbeat := float(job.get("heartbeat_at", job.get("updated_at", 0.0)))
	if last_heartbeat > 0.0 and now - last_heartbeat < maxf(stale_after_seconds, 10.0):
		return {"ok": false, "error": "The run is still reporting activity."}
	job["state"] = "interrupted"
	job["error"] = "The task stopped reporting progress. The last saved checkpoint is available to resume."
	job["summary"] = "Interrupted · checkpoint preserved"
	job["finished_at"] = now
	job["elapsed_seconds"] = _elapsed(job)
	job["resumable"] = true
	var checkpoint_saved := _save_checkpoint(job_id, job.get("checkpoint", {}))
	var job_saved := _save_job(job)
	_instances.erase(job_id)
	_active_ids.erase(job_id)
	_last_checkpoint_persist_at.erase(job_id)
	_last_ui_update_at.erase(job_id)
	_job_log(job_id, "Run marked interrupted after its progress heartbeat became stale.")
	jobs_changed.emit()
	if not checkpoint_saved or not job_saved:
		return {"ok": false, "job_id": job_id, "state": "interrupted", "resumable": true, "error": "The run was stopped, but its latest recovery state could not be fully saved."}
	return {"ok": true, "job_id": job_id, "state": "interrupted", "resumable": true}


func list_jobs(project_id: String) -> Array:
	var output: Array = []
	for value in _jobs.values():
		if project_id == "" or str(value.get("project_id", "")) == project_id:
			output.append(value.duplicate(true))
	output.sort_custom(func(a, b): return float(a.get("created_at", 0.0)) > float(b.get("created_at", 0.0)))
	return output


func get_job(job_id: String) -> Dictionary:
	return (_jobs.get(job_id, {}) as Dictionary).duplicate(true)


func has_artifact(job_id: String, artifact_name: String) -> bool:
	if not _jobs.has(job_id) or not _safe_artifact_name(artifact_name): return false
	var path := _job_absolute(job_id).path_join("artifacts").path_join(artifact_name)
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")


func read_artifact(job_id: String, artifact_name: String) -> Dictionary:
	if not _jobs.has(job_id): return {"ok": false, "error": "Run not found."}
	if not _safe_artifact_name(artifact_name): return {"ok": false, "error": "Unsafe artifact name."}
	var path := _job_absolute(job_id).path_join("artifacts").path_join(artifact_name)
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".bak"):
		path += ".bak"
	if not FileAccess.file_exists(path): return {"ok": false, "error": "Artifact not found."}
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > MAX_ARTIFACT_BYTES: return {"ok": false, "error": "Artifact exceeds the 4 MiB read limit."}
	return {"ok": true, "content": bytes.get_string_from_utf8(), "bytes": bytes.size(), "job_id": job_id, "artifact": artifact_name}


func read_project_file(project_id: String, relative_path: String) -> Dictionary:
	var info := inspect_project(project_id)
	if not bool(info.get("ok", false)): return info
	if not GodotSandbox.is_safe_project_path(relative_path): return {"ok": false, "error": "Unsafe project-relative path."}
	var path := str(info.root).path_join(relative_path)
	if not FileAccess.file_exists(path): return {"ok": false, "error": "File not found."}
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > 256 * 1024: return {"ok": false, "error": "File exceeds the 256 KiB read limit."}
	if _looks_binary(bytes): return {"ok": false, "error": "This appears to be a binary asset. Use the Sources viewer instead."}
	return {"ok": true, "path": relative_path, "content": bytes.get_string_from_utf8(), "bytes": bytes.size()}


func write_project_file(project_id: String, relative_path: String, content: String) -> Dictionary:
	var info := inspect_project(project_id)
	if not bool(info.get("ok", false)): return info
	if not GodotSandbox.is_safe_project_path(relative_path): return {"ok": false, "error": "Unsafe project-relative path."}
	if content.to_utf8_buffer().size() > 256 * 1024: return {"ok": false, "error": "Project text write exceeds the 256 KiB limit."}
	return GodotSandbox.write_project_text(str(info.root), relative_path, content)


func _create_task_instance(job: Dictionary, root_uri: String, checkpoint: Dictionary) -> Dictionary:
	var manifest := _read_task_manifest(root_uri)
	if not bool(manifest.get("ok", false)): return {"ok": false, "error": str(manifest.get("error", "Task manifest unavailable."))}
	var task: Dictionary = {}
	for row in manifest.tasks:
		if str(row.get("id", "")) == str(job.get("task_id", "")): task = row; break
	if task.is_empty(): return {"ok": false, "error": "Task was removed from the project manifest."}
	var relative := str(task.get("script", ""))
	if not GodotSandbox.is_safe_project_path(relative): return {"ok": false, "error": "Task script path failed safety validation."}
	var uri := root_uri.path_join(relative)
	var source := FileAccess.get_file_as_string(uri)
	if source.to_utf8_buffer().size() > MAX_TASK_SCRIPT_BYTES: return {"ok": false, "error": "Task script exceeds the 512 KiB mobile limit."}
	# Compile project-owned task source as an ephemeral Script resource. Do not run it
	# through ResourceLoader: imported projects are user:// data and must not pollute
	# Aoi's global resource cache or produce an unhandled loader failure.
	var dynamic_script := GDScript.new()
	dynamic_script.source_code = source
	var reload_error := dynamic_script.reload(false)
	if reload_error != OK: return {"ok": false, "error": "Task script failed Godot GDScript compilation (%d)." % reload_error}
	var script_resource: Variant = dynamic_script
	if not script_resource is GDScript:
		return {"ok": false, "error": "Task entry must be a GDScript file."}
	if not script_resource.can_instantiate():
		return {"ok": false, "error": "Task script could not be compiled or instantiated."}
	var instance: Variant = script_resource.new()
	if not instance is RefCounted:
		return {"ok": false, "error": "A task must extend RefCounted, not Node or SceneTree."}
	if not instance.has_method("start") or not instance.has_method("step"):
		return {"ok": false, "error": "Task script must implement start(context, parameters, checkpoint) and step(context, state, budget_units)."}
	var context := _make_context(str(job.get("id", "")))
	var started := Time.get_ticks_msec()
	var start_result: Variant = instance.call("start", context, job.get("parameters", {}), checkpoint)
	var duration := Time.get_ticks_msec() - started
	if duration > STEP_WARNING_MS: _job_log(str(job.id), "Warning: task startup took %d ms; keep initialization bounded." % duration)
	if not start_result is Dictionary or not bool(start_result.get("ok", true)):
		return {"ok": false, "error": str(start_result.get("error", "Task start() failed.")) if start_result is Dictionary else "Task start() must return a Dictionary."}
	var state: Variant = start_result.get("state", checkpoint)
	if not state is Dictionary or JSON.stringify(state).to_utf8_buffer().size() > MAX_CHECKPOINT_BYTES:
		return {"ok": false, "error": "Task start state is invalid or too large."}
	return {"ok": true, "instance": instance, "state": state, "detail": str(start_result.get("detail", "Task initialized."))}


func _make_context(job_id: String) -> Dictionary:
	var job: Dictionary = _jobs.get(job_id, {})
	var project: Dictionary = Store.get_project(str(job.get("project_id", "")))
	var root_uri := _project_root(project)
	var log_callable := func(message: Variant) -> void: _job_log(job_id, str(message))
	var progress_callable := func(value: float, detail: String = "") -> void:
		_set_progress(job_id, value, detail)
	var read_callable := func(relative: String) -> Dictionary:
		return read_project_file(str(job.get("project_id", "")), relative)
	var artifact_callable := func(name: String, value: Variant) -> Dictionary:
		return _write_artifact(job_id, name, value)
	var cancelled_callable := func() -> bool:
		return bool(_cancelled.get(job_id, false))
	var files_callable := func(limit: int = 200) -> Array:
		return _scan_project_files(root_uri, clampi(limit, 1, 500))
	return {
		"project_id": str(job.get("project_id", "")),
		"project_root": root_uri,
		"project_root_absolute": _global(root_uri),
		"job_id": job_id,
		"parameters": job.get("parameters", {}),
		"log": log_callable,
		"progress": progress_callable,
		"read_file": read_callable,
		"write_artifact": artifact_callable,
		"is_cancelled": cancelled_callable,
		"list_files": files_callable
	}


func _read_task_manifest(root_uri: String) -> Dictionary:
	var manifest_path := root_uri.path_join(TASK_MANIFEST)
	if not FileAccess.file_exists(manifest_path):
		return {"ok": false, "exists": false, "tasks": [], "error": "This project has no .aoi/tasks.json task manifest yet."}
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null: return {"ok": false, "exists": true, "tasks": [], "error": "Could not open the task manifest."}
	if file.get_length() > MAX_MANIFEST_BYTES:
		file.close()
		return {"ok": false, "exists": true, "tasks": [], "error": "Task manifest exceeds 128 KiB."}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		return {"ok": false, "exists": true, "tasks": [], "error": "Task manifest must be a JSON object with schema_version 1."}
	var raw_tasks: Variant = parsed.get("tasks", [])
	if not raw_tasks is Array or raw_tasks.size() > MAX_TASKS:
		return {"ok": false, "exists": true, "tasks": [], "error": "Manifest tasks must be an array of at most %d entries." % MAX_TASKS}
	var output: Array[Dictionary] = []
	var seen := {}
	for raw in raw_tasks:
		if not raw is Dictionary: return {"ok": false, "exists": true, "tasks": [], "error": "Each task entry must be an object."}
		var task: Dictionary = raw
		var id := str(task.get("id", ""))
		var name := str(task.get("name", id)).strip_edges()
		var script := str(task.get("script", task.get("entry", "")))
		var runtime := str(task.get("runtime", "gdscript_steps"))
		if not _valid_identifier(id) or seen.has(id): return {"ok": false, "exists": true, "tasks": [], "error": "Task IDs must be unique and use letters, numbers, hyphens or underscores."}
		if name == "" or name.length() > 100: return {"ok": false, "exists": true, "tasks": [], "error": "Task names must contain 1–100 characters."}
		if not GodotSandbox.is_safe_project_path(script): return {"ok": false, "exists": true, "tasks": [], "error": "Task '%s' must reference a safe project-relative entry file." % id}
		if runtime not in ["gdscript_steps", "python_companion", "shell_companion", "godot_project"]:
			return {"ok": false, "exists": true, "tasks": [], "error": "Task '%s' declares an unknown runtime." % id}
		var expected_extension: String = str({"gdscript_steps":"gd", "python_companion":"py", "shell_companion":"sh"}.get(runtime, ""))
		if expected_extension != "" and script.get_extension().to_lower() != expected_extension:
			return {"ok": false, "exists": true, "tasks": [], "error": "Task '%s' entry does not match runtime '%s'." % [id, runtime]}
		seen[id] = true
		output.append({
			"id": id,
			"name": name,
			"description": str(task.get("description", "")).left(500),
			"script": script,
			"runtime": runtime,
			"available_on_device": runtime == "gdscript_steps",
			"parameters": task.get("parameters", []) if task.get("parameters", []) is Array else [],
			"limits": task.get("limits", {}) if task.get("limits", {}) is Dictionary else {},
			"mode": str(task.get("mode", "headless")),
			"requires_approval": true
		})
	return {"ok": true, "exists": true, "tasks": output, "name": str(parsed.get("project_name", ""))}


func _validate_parameters(schema: Array, supplied: Dictionary) -> Dictionary:
	if schema.size() > 32: return {"ok": false, "error": "A task may declare at most 32 parameters."}
	var values := {}
	for item in schema:
		if not item is Dictionary: return {"ok": false, "error": "Invalid task parameter schema."}
		var key := str(item.get("name", ""))
		if not _valid_identifier(key): return {"ok": false, "error": "Invalid task parameter name."}
		var kind := str(item.get("type", "string"))
		var value: Variant = supplied.get(key, item.get("default", null))
		if value == null:
			if bool(item.get("required", false)): return {"ok": false, "error": "Missing required parameter '%s'." % key}
			continue
		match kind:
			"int":
				if not (value is int or value is float): return {"ok": false, "error": "Parameter '%s' must be an integer." % key}
				value = int(value)
				value = clampi(int(value), int(item.get("min", -2147483648)), int(item.get("max", 2147483647)))
			"float":
				if not (value is int or value is float): return {"ok": false, "error": "Parameter '%s' must be numeric." % key}
				value = clampf(float(value), float(item.get("min", -1.0e9)), float(item.get("max", 1.0e9)))
			"bool":
				if not value is bool: return {"ok": false, "error": "Parameter '%s' must be boolean." % key}
			"string":
				if not value is String or str(value).length() > 2000: return {"ok": false, "error": "Parameter '%s' must be a string of at most 2000 characters." % key}
			_:
				return {"ok": false, "error": "Unsupported parameter type '%s'." % kind}
		values[key] = value
	for supplied_key in supplied:
		var known := false
		for item in schema:
			if item is Dictionary and str(item.get("name", "")) == str(supplied_key): known = true; break
		if not known: return {"ok": false, "error": "Unknown task parameter '%s'." % str(supplied_key)}
	return {"ok": true, "values": values}


func _detect_project_types(root_uri: String) -> Array[String]:
	var types: Array[String] = []
	if FileAccess.file_exists(root_uri.path_join("project.godot")): types.append("godot")
	if FileAccess.file_exists(root_uri.path_join("pyproject.toml")) or FileAccess.file_exists(root_uri.path_join("requirements.txt")) or FileAccess.file_exists(root_uri.path_join("setup.py")): types.append("python")
	if FileAccess.file_exists(root_uri.path_join("package.json")): types.append("node")
	if FileAccess.file_exists(root_uri.path_join("Cargo.toml")): types.append("rust")
	if FileAccess.file_exists(root_uri.path_join("CMakeLists.txt")) or FileAccess.file_exists(root_uri.path_join("Makefile")): types.append("native")
	if FileAccess.file_exists(root_uri.path_join(".ipynb")) or not _scan_project_files(root_uri, 200).filter(func(x): return str(x.get("path", "")).ends_with(".ipynb")).is_empty(): types.append("notebook")
	if types.is_empty(): types.append("generic")
	return types


func _primary_type(types: Array) -> String:
	for kind in ["godot", "python", "node", "rust", "native", "notebook"]:
		if kind in types: return kind
	return "generic"


func _project_kind(project: Dictionary, root_uri: String) -> String:
	# Project intent is a separate dimension from the detected implementation
	# technology. A game may be Godot, web, Python or a different runtime.
	var known_kinds := ["game", "app", "website", "ai", "research", "general"]
	var stored := str(project.get("project_kind", project.get("kind", ""))).to_lower().strip_edges()
	if stored in known_kinds and stored != "general":
		return stored
	var metadata_path := root_uri.path_join(".aoi/project.json")
	if FileAccess.file_exists(metadata_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
		if parsed is Dictionary:
			var from_file := str(parsed.get("kind", "")).to_lower().strip_edges()
			if from_file in known_kinds and from_file != "general":
				return from_file
	return stored if stored in known_kinds else "general"


func _available_runtimes() -> Array[Dictionary]:
	return [
		{"id":"gdscript_steps", "available":true, "scope":"on-device", "description":"Cooperative trusted GDScript tasks with checkpoint and artifact support."},
		{"id":"godot_project", "available":ToolRunner.is_linux_connected() and bool(Store.get_integration("linux_bridge").get("godot_available", false)), "scope":"companion", "description":"Full Godot project runtime is available through the verified cloud Linux workspace when Godot is installed there."},
		{"id":"python_companion", "available":ToolRunner.is_linux_connected(), "scope":"companion", "description":"Python execution requires a verified cloud Linux workspace."},
		{"id":"shell_companion", "available":ToolRunner.is_linux_connected(), "scope":"companion", "description":"Command-line tasks require a verified cloud Linux workspace."}
	]


func _project_root(project: Dictionary) -> String:
	var external := str(project.get("studio_local_external_path", "")).strip_edges()
	if external != "": return external
	var relative := str(project.get("studio_local_path", "")).strip_edges()
	if relative == "": relative = "studio/projects/" + str(project.get("id", ""))
	if not GodotSandbox.is_safe_project_path(relative): return ""
	return Store.root.path_join(relative)


func _scan_project_files(root_uri: String, limit: int = 200) -> Array:
	var rows: Array = []
	_scan_directory(root_uri, "", rows, 0, limit)
	return rows


func _scan_directory(root_uri: String, relative: String, rows: Array, depth: int, limit: int) -> void:
	if depth > 8 or rows.size() >= limit: return
	var directory := DirAccess.open(root_uri.path_join(relative) if relative != "" else root_uri)
	if directory == null: return
	# Include hidden entries so explicitly supported project metadata (notably
	# .aoi) can be inspected. Private files/caches remain filtered below.
	directory.include_hidden = true
	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "" and rows.size() < limit:
		if entry in [".godot", ".git", "node_modules", "__pycache__", ".venv", ".env"] or (entry.begins_with(".") and entry not in [".aoi", ".gitignore", ".editorconfig", ".gitattributes"]):
			entry = directory.get_next()
			continue
		var rel := relative.path_join(entry) if relative != "" else entry
		var is_dir := directory.current_is_dir()
		rows.append({"path": rel, "type": "directory" if is_dir else "file"})
		if is_dir: _scan_directory(root_uri, rel, rows, depth + 1, limit)
		entry = directory.get_next()
	directory.list_dir_end()


func _set_progress(job_id: String, value: float, detail: String) -> void:
	if not _jobs.has(job_id): return
	# Progress callbacks can be invoked repeatedly inside a cooperative task.
	# Update memory immediately, but let _step_job own the bounded disk/UI cadence.
	# Writing here used to bypass throttling and could hit storage once per frame.
	var job: Dictionary = _jobs[job_id]
	job["progress"] = clampf(value, 0.0, 1.0)
	job["last_detail"] = detail.left(360)


func _write_artifact(job_id: String, artifact_name: String, value: Variant) -> Dictionary:
	if not _safe_artifact_name(artifact_name): return {"ok": false, "error": "Artifact names must be simple filenames without path separators."}
	var bytes := PackedByteArray()
	if value is PackedByteArray:
		bytes = value
	elif value is String:
		bytes = str(value).to_utf8_buffer()
	else:
		bytes = JSON.stringify(value, "\t").to_utf8_buffer()
	if bytes.size() > MAX_ARTIFACT_BYTES: return {"ok": false, "error": "Artifact exceeds the 4 MiB limit."}
	var directory := _job_absolute(job_id).path_join("artifacts")
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join(artifact_name)
	if not _atomic_write(path, bytes):
		return {"ok": false, "error": "Could not safely save run artifact. The previous copy was preserved where possible."}
	return {"ok": true, "artifact": artifact_name, "bytes": bytes.size()}


func _write_job_text(job_id: String, name: String, content: String) -> void:
	_write_artifact(job_id, name, content)


func _save_checkpoint(job_id: String, checkpoint: Dictionary) -> bool:
	var result := _write_artifact(job_id, "checkpoint.json", checkpoint)
	return bool(result.get("ok", false))


func _save_job(job: Dictionary) -> bool:
	job["updated_at"] = Time.get_unix_time_from_system()
	var path := _job_absolute(str(job.get("id", ""))).path_join("job.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return _write_json(path, job)


func _remove_nul_bytes(value: String) -> String:
	# Strip binary NULs at the UTF-8 byte boundary. Avoid embedding a NUL
	# escape in this script: Godot's source decoder warns during import.
	var source := value.to_utf8_buffer()
	var clean := PackedByteArray()
	for byte_value in source:
		if byte_value != 0:
			clean.append(byte_value)
	return clean.get_string_from_utf8()


func _job_log(job_id: String, message: String) -> void:
	var path := _job_absolute(job_id).path_join("artifacts").path_join("run.log")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var existing := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var line := "[%s] %s\n" % [Time.get_datetime_string_from_system(), _remove_nul_bytes(message).left(1000)]
	var combined := existing + line
	if combined.to_utf8_buffer().size() > MAX_LOG_BYTES:
		combined = combined.right(MAX_LOG_BYTES / 2)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(combined); file.close()


func _build_report(job: Dictionary, result: Dictionary, metrics: Dictionary) -> String:
	var lines: Array[String] = [
		"# Project task report",
		"",
		"- Project: %s" % str(job.get("project_name", "Project")),
		"- Task: %s (`%s`)" % [str(job.get("task_name", "Task")), str(job.get("task_id", ""))],
		"- Runtime: %s" % str(job.get("runtime", "unknown")),
		"- Status: completed",
		"- Steps: %d" % int(job.get("step_count", 0)),
		"- Duration: %.2f seconds" % float(job.get("elapsed_seconds", 0.0)),
		"",
		"## Result",
		str(result.get("summary", job.get("summary", "Task completed."))),
		""
	]
	if not metrics.is_empty():
		lines.append("## Metrics")
		lines.append("```json")
		lines.append(JSON.stringify(metrics, "\t"))
		lines.append("```")
	return "\n".join(lines)


func _finish_job(job_id: String, state: String, message: String) -> void:
	if not _jobs.has(job_id): return
	var job: Dictionary = _jobs[job_id]
	job["state"] = state
	job["error"] = message if state == "failed" else ""
	job["summary"] = message.left(500)
	job["finished_at"] = Time.get_unix_time_from_system()
	job["elapsed_seconds"] = _elapsed(job)
	job["resumable"] = state in ["failed", "interrupted"]
	_save_checkpoint(job_id, job.get("checkpoint", {}))
	_save_job(job)
	_job_log(job_id, ("ERROR: " if state == "failed" else "") + message)
	_instances.erase(job_id)
	_active_ids.erase(job_id)
	jobs_changed.emit()
	job_finished.emit({"ok": state == "completed", "job_id": job_id, "project_id": str(job.get("project_id", "")), "state": state, "output": message, "error": message if state == "failed" else ""})


func _elapsed(job: Dictionary) -> float:
	var started := float(job.get("started_at", 0.0))
	return maxf(0.0, Time.get_unix_time_from_system() - started) if started > 0.0 else float(job.get("elapsed_seconds", 0.0))


func _load_recent_jobs() -> void:
	var root := _global(JOBS_DIRECTORY)
	var dir := DirAccess.open(root)
	if dir == null: return
	dir.list_dir_begin()
	var item := dir.get_next()
	while item != "":
		if dir.current_is_dir() and _valid_identifier(item):
			var job_path := root.path_join(item).path_join("job.json")
			var job := _read_json(job_path)
			if not job.is_empty():
				# The checkpoint file is committed before job.json. If Android kills
				# Aoi between those writes, the checkpoint can be newer than the job
				# summary. Recover it first so Resume never silently discards a step.
				var checkpoint_path := root.path_join(item).path_join("artifacts").path_join("checkpoint.json")
				var recovered_checkpoint := _read_json(checkpoint_path)
				if not recovered_checkpoint.is_empty():
					job["checkpoint"] = recovered_checkpoint
				if str(job.get("id", "")) != item:
					item = dir.get_next()
					continue
				if str(job.get("state", "")) in ["running", "queued"]:
					job["state"] = "interrupted"
					job["heartbeat_at"] = 0.0
					job["summary"] = "Interrupted when Aoi closed. Checkpoint preserved; review before resuming."
					job["resumable"] = true
					_write_json(job_path, job)
				_jobs[item] = job
		item = dir.get_next()
	dir.list_dir_end()
	_prune_old_jobs()


func _job_absolute(job_id: String) -> String:
	return _global(JOBS_DIRECTORY).path_join(job_id)


func _prune_old_jobs(protected_job_id: String = "") -> void:
	var excess := _jobs.size() - MAX_RECENT_JOBS
	if excess <= 0:
		return
	var candidates: Array[Dictionary] = []
	for value in _jobs.values():
		var job: Dictionary = value
		var job_id := str(job.get("id", ""))
		if job_id == protected_job_id or job_id in _active_ids or str(job.get("state", "")) not in ["completed", "cancelled"]:
			continue
		candidates.append(job)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_created := float(a.get("created_at", 0.0))
		var b_created := float(b.get("created_at", 0.0))
		if a_created == b_created:
			return str(a.get("id", "")) < str(b.get("id", ""))
		return a_created < b_created
	)
	for job in candidates:
		if excess <= 0:
			break
		var job_id := str(job.get("id", ""))
		if not _remove_job_directory(job_id):
			push_warning("Aoi could not prune old terminal run data: " + job_id)
			continue
		_jobs.erase(job_id)
		excess -= 1


func _remove_job_directory(job_id: String) -> bool:
	if not _valid_identifier(job_id):
		return false
	var root := _global(JOBS_DIRECTORY)
	var path := _job_absolute(job_id)
	if path.get_base_dir() != root:
		return false
	return _remove_job_tree(path)


func _remove_job_tree(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		if not FileAccess.file_exists(path):
			return true
		return DirAccess.remove_absolute(path) == OK
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	directory.include_hidden = true
	directory.list_dir_begin()
	var name := directory.get_next()
	while name != "":
		if name not in [".", ".."]:
			var child := path.path_join(name)
			var removed := _remove_job_tree(child) if directory.current_is_dir() else DirAccess.remove_absolute(child) == OK
			if not removed:
				directory.list_dir_end()
				return false
		name = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(path) == OK or not DirAccess.dir_exists_absolute(path)


func _global(path: String) -> String:
	return ProjectSettings.globalize_path(Store.root.path_join(path)).simplify_path()


func _write_json(path: String, data: Dictionary) -> bool:
	return _atomic_write(path, JSON.stringify(data, "\t").to_utf8_buffer())


func _atomic_write(path: String, bytes: PackedByteArray) -> bool:
	# Keep the last known-good file until the replacement is fully written.
	# The backup also lets the reader recover if the app closes between renames.
	var temp := path + ".tmp"
	var backup := path + ".bak"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes)
	file.flush()
	file.close()
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup):
			if DirAccess.remove_absolute(backup) != OK:
				DirAccess.remove_absolute(temp)
				return false
		if DirAccess.rename_absolute(path, backup) != OK:
			DirAccess.remove_absolute(temp)
			return false
	if DirAccess.rename_absolute(temp, path) != OK:
		if not FileAccess.file_exists(path) and FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, path)
		DirAccess.remove_absolute(temp)
		return false
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	return true


func _read_json(path: String) -> Dictionary:
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			return parsed
	var backup := path + ".bak"
	if FileAccess.file_exists(backup):
		var recovered: Variant = JSON.parse_string(FileAccess.get_file_as_string(backup))
		if recovered is Dictionary:
			# Repair the primary copy so subsequent reads do not depend on the backup.
			_write_json(path, recovered)
			return recovered
	return {}


func _safe_artifact_name(name: String) -> bool:
	if name == "" or name.length() > 80 or name in [".", ".."] or name.contains("/") or name.contains("\\") or name.contains(":"): return false
	for index in range(name.length()):
		var code := name.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code in [45, 46, 95]): return false
	return true


func _valid_identifier(value: String) -> bool:
	if value == "" or value.length() > 64: return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code in [45, 95]): return false
	return true


func _looks_binary(bytes: PackedByteArray) -> bool:
	var sample := bytes.slice(0, mini(bytes.size(), 4096))
	return sample.has(0) or sample.get_string_from_utf8().contains("\uFFFD")
