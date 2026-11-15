extends Node
## Explicit tool bridge. GitHub mutations and Linux commands require approval cards; code runs only on configured endpoints.
signal completed(result: Dictionary)
signal manual_completed(result: Dictionary)
signal state_changed(state: String, detail: String)

var busy := false
var _active_request: HTTPRequest
var _active_tool := ""
var _active_manual := false
var _cancel_requested := false
var _active_job_id := ""


func _ready() -> void:
	if not JobRunner.job_finished.is_connected(_on_job_finished):
		JobRunner.job_finished.connect(_on_job_finished)
	if not JobRunner.job_progress.is_connected(_on_job_progress):
		JobRunner.job_progress.connect(_on_job_progress)

const MAX_CODE_CHARS := 15000
const MAX_PROMPT_CHARS := 2400
const MAX_TOOL_OUTPUT_CHARS := 7000
const MAX_IMAGE_BYTES := 18 * 1024 * 1024
const MAX_VIDEO_BYTES := 100 * 1024 * 1024
const MAX_IMAGE_DIMENSION := 4096
const GITHUB_API := "https://api.github.com"
const HUGGINGFACE_ROUTER := "https://router.huggingface.co/hf-inference/models/"
const GITHUB_USER_AGENT := "AoiMobile/3.2.14"
const DEFAULT_IMAGE_MODEL := "stabilityai/stable-diffusion-3-medium-diffusers"


func execute_tool(data: Dictionary) -> void:
	if busy:
		_emit_result({"ok": false, "tool": "Tool runner", "error": "Another tool is already running. Wait for it to finish first."}, false)
		return

	var name := str(data.get("name", "")).strip_edges()
	state_changed.emit("running", name)
	match name:
		"piston.run":
			var language := str(data.get("language", "python")).to_lower().strip_edges()
			if language not in ["python", "javascript", "bash"]:
				_finish({"ok": false, "tool": name, "error": "Supported languages are Python, JavaScript and Bash."}, false)
				return
			_run_piston(language, str(data.get("code", "")), false)
		"github.search_repositories":
			_search_github(str(data.get("query", "")).strip_edges(), false)
		"github.repository_info":
			_get_repository_info(str(data.get("repository", "")).strip_edges(), false)
		"github.read_file":
			_read_repository_file(str(data.get("repository", "")).strip_edges(), str(data.get("path", "")).strip_edges(), str(data.get("ref", "")).strip_edges(), false)
		"github.list_tree":
			_list_repository_tree(str(data.get("repository", "")).strip_edges(), str(data.get("branch", "")).strip_edges(), false)
		"github.create_branch":
			_create_github_branch(str(data.get("repository", "")).strip_edges(), str(data.get("branch", "")).strip_edges(), str(data.get("from", "")).strip_edges(), false)
		"github.write_file":
			_write_github_file(str(data.get("repository", "")).strip_edges(), str(data.get("path", "")).strip_edges(), str(data.get("content", "")), str(data.get("message", "Update via Aoi")), str(data.get("branch", "")).strip_edges(), str(data.get("sha", "")).strip_edges(), false)
		"github.create_issue":
			_create_github_issue(str(data.get("repository", "")).strip_edges(), str(data.get("title", "")).strip_edges(), str(data.get("body", "")), false)
		"github.create_pull_request":
			_create_github_pull_request(str(data.get("repository", "")).strip_edges(), str(data.get("head", "")).strip_edges(), str(data.get("base", "main")).strip_edges(), str(data.get("title", "")), str(data.get("body", "")), false)
		"linux.exec":
			_linux_request("exec", {"command":str(data.get("command", "")), "cwd":str(data.get("cwd", ".")), "timeout":int(data.get("timeout", 30))}, false)
		"linux.list_files":
			_linux_request("list", {"path":str(data.get("path", "."))}, false)
		"linux.read_file":
			_linux_request("read", {"path":str(data.get("path", ""))}, false)
		"linux.write_file":
			_linux_request("write", {"path":str(data.get("path", "")), "content":str(data.get("content", ""))}, false)
		"linux.search_files":
			_linux_request("search", {"query":str(data.get("query", "")), "path":str(data.get("path", "."))}, false)
		"godot.run":
			_godot_request("run", {"path":str(data.get("path", ""))}, false)
		"godot.create":
			_godot_create(str(data.get("project_id", "")), str(data.get("name", "New project")), str(data.get("goal", "")))
		"godot.stop":
			_godot_request("stop", {"path":str(data.get("path", ""))}, false)
		"godot.status":
			_godot_request("status", {"path":str(data.get("path", ""))}, false)
		"godot.test":
			_godot_request("test", {"path":str(data.get("path", ""))}, false)
		"godot.capture":
			_godot_request("capture", {"path":str(data.get("path", ""))}, false)
		"godot.logs":
			_godot_request("logs", {"path":str(data.get("path", ""))}, false)
		"workspace.create_project":
			_finish(_create_project_workspace(str(data.get("title", "")), str(data.get("goal", "")), str(data.get("kind", "general"))), false)
		"workspace.search_projects":
			_search_saved_projects(str(data.get("query", "")))
		"project.inspect":
			var inspect_result := JobRunner.inspect_project(str(data.get("project_id", "")))
			inspect_result["tool"] = name
			_finish(inspect_result, false)
		"project.read_file":
			var read_result := JobRunner.read_project_file(str(data.get("project_id", "")), str(data.get("path", "")))
			read_result["tool"] = name
			_finish(read_result, false)
		"project.write_file":
			_write_project_file(str(data.get("project_id", "")), str(data.get("path", "")), str(data.get("content", "")))
		"project.tasks":
			var task_result := JobRunner.list_project_tasks(str(data.get("project_id", "")))
			task_result["tool"] = name
			_finish(task_result, false)
		"project.run_task":
			_start_project_task(str(data.get("project_id", "")), str(data.get("task_id", "")), data.get("parameters", {}))
		"jobs.status":
			_finish({"ok":true,"tool":name,"jobs":JobRunner.list_jobs(str(data.get("project_id", "")))}, false)
		"jobs.read_artifact":
			var artifact_result := JobRunner.read_artifact(str(data.get("job_id", "")), str(data.get("artifact", "report.md")))
			artifact_result["tool"] = name
			_finish(artifact_result, false)
		"jobs.pause":
			_finish(JobRunner.pause_job(str(data.get("job_id", ""))), false)
		"jobs.resume":
			_resume_project_task(str(data.get("job_id", "")))
		"jobs.cancel":
			_finish(JobRunner.cancel_job(str(data.get("job_id", ""))), false)
		"knowledge.search":
			_search_global_knowledge(str(data.get("query", "")))
		"knowledge.save":
			_save_global_knowledge(str(data.get("title", "")), str(data.get("content", "")), data.get("tags", []))
		"project.search_knowledge":
			_search_project_knowledge(str(data.get("project_id", "")), str(data.get("query", "")))
		"project.capture_decision":
			_capture_project_decision(str(data.get("project_id", "")), str(data.get("decision", "")))
		"project.save_knowledge":
			_save_project_knowledge(str(data.get("project_id", "")), str(data.get("title", "")), str(data.get("content", "")), data.get("tags", []))
		"project.save_playbook":
			_save_project_playbook(str(data.get("project_id", "")), str(data.get("title", "")), str(data.get("trigger", "")), str(data.get("steps", "")))
		"wikipedia.search":
			_search_wikipedia(str(data.get("query", "")).strip_edges(), false)
		"wikipedia.read_page":
			_read_wikipedia_page(str(data.get("title", "")).strip_edges(), false)
		"research.web_context":
			_research_web_context(str(data.get("project_id", "")).strip_edges(), str(data.get("query", "")).strip_edges(), str(data.get("angle", "")).strip_edges())
		"huggingface.generate_image":
			if not _require_secret("huggingface", "Hugging Face Inference"): return
			_generate_huggingface_image(str(data.get("prompt", "")).strip_edges(), false)
		"huggingface.generate_video":
			if not _require_secret("huggingface", "Hugging Face Inference"): return
			_generate_huggingface_video(str(data.get("prompt", "")).strip_edges(), false)
		"android.set_alarm":
			_set_android_alarm(data)
		"android.add_calendar_event":
			_add_android_calendar_event(data)
		_:
			_finish({"ok": false, "tool": name if name != "" else "Unknown tool", "error": "That tool is not installed in Aoi."}, false)


func _android_actions_plugin() -> Object:
	if OS.get_name() != "Android" or not Engine.has_singleton("AoiAndroidActions"):
		return null
	return Engine.get_singleton("AoiAndroidActions")


func _set_android_alarm(data: Dictionary) -> void:
	var hour := int(data.get("hour", -1))
	var minute := int(data.get("minute", -1))
	var label := str(data.get("label", "")).strip_edges().left(80)
	if hour < 0 or hour > 23 or minute < 0 or minute > 59:
		_finish({"ok":false, "tool":"android.set_alarm", "error":"Choose a local device time with hour 0–23 and minute 0–59."}, false)
		return
	var plugin := _android_actions_plugin()
	if plugin == null:
		_finish({"ok":false, "tool":"android.set_alarm", "error":"Android Clock actions are available only in the Aoi Android build."}, false)
		return
	if not bool(plugin.call("setAlarm", hour, minute, label)):
		_finish({"ok":false, "tool":"android.set_alarm", "error":"Aoi could not open an installed Android Clock app for this alarm."}, false)
		return
	_finish({"ok":true, "tool":"android.set_alarm", "output":"Opened Android Clock with the alarm details. Confirm Save in Clock; Aoi cannot verify the alarm was saved."}, false)


func _add_android_calendar_event(data: Dictionary) -> void:
	var title := str(data.get("title", "")).strip_edges().left(120)
	var year := int(data.get("year", 0))
	var month := int(data.get("month", 0))
	var day := int(data.get("day", 0))
	var hour := int(data.get("hour", -1))
	var minute := int(data.get("minute", -1))
	var duration := int(data.get("duration_minutes", 0))
	if title == "" or year < 2020 or year > 2100 or month < 1 or month > 12 or day < 1 or day > 31 or hour < 0 or hour > 23 or minute < 0 or minute > 59 or duration < 1 or duration > 1440:
		_finish({"ok":false, "tool":"android.add_calendar_event", "error":"Provide a title, valid local date/time, and a duration between 1 and 1,440 minutes."}, false)
		return
	var plugin := _android_actions_plugin()
	if plugin == null:
		_finish({"ok":false, "tool":"android.add_calendar_event", "error":"Android Calendar actions are available only in the Aoi Android build."}, false)
		return
	var description := str(data.get("description", "")).strip_edges().left(1000)
	var location := str(data.get("location", "")).strip_edges().left(160)
	if not bool(plugin.call("addCalendarEvent", title, year, month, day, hour, minute, duration, description, location)):
		_finish({"ok":false, "tool":"android.add_calendar_event", "error":"Aoi could not open an installed Android calendar app, or the supplied date is invalid."}, false)
		return
	_finish({"ok":true, "tool":"android.add_calendar_event", "output":"Opened Android Calendar with the event details. Confirm Save in Calendar; Aoi cannot verify the event was saved."}, false)


func _create_project_workspace(raw_title: String, raw_goal: String, raw_kind: String) -> Dictionary:
	var title := raw_title.strip_edges().left(80)
	var goal := raw_goal.strip_edges().left(2400)
	var kind := raw_kind.strip_edges().to_lower()
	if title == "" or goal == "":
		return {"ok":false, "tool":"workspace.create_project", "error":"A project title and goal are required."}
	if kind not in ["game", "app", "website", "ai", "research", "general"]:
		kind = "general"
	var project := Store.new_project(title, goal)
	var project_id := str(project.get("id", ""))
	if project_id == "":
		return {"ok":false, "tool":"workspace.create_project", "error":"Aoi could not save the project record. Check available storage and try again."}
	var relative := "studio/projects/" + project_id
	var root_uri := Store.root.path_join(relative)
	var absolute := ProjectSettings.globalize_path(root_uri)
	for folder in ["sources", "data", "outputs", ".aoi"]:
		var make_error := DirAccess.make_dir_recursive_absolute(absolute.path_join(folder))
		if make_error != OK:
			_remove_created_project_tree(absolute)
			Store.delete_project(project_id)
			return {"ok":false, "tool":"workspace.create_project", "error":"Aoi could not prepare the project folders (error %d). No project was attached to this chat." % make_error}
	var safe_title := title.replace("\r", " ").replace("\n", " ")
	var safe_goal := goal.replace("\r", "")
	var files := {
		"README.md":"# %s\n\n%s\n\n## Workspace\n\nThis project belongs to your Aoi workspace. Aoi will detect its format and available runtime from the actual files before running it.\n" % [safe_title, safe_goal],
		".aoi/project.json":JSON.stringify({"schema_version":1,"project_id":project_id,"kind":kind,"title":title,"goal":goal,"created_by":"Aoi"}, "\t") + "\n",
		".aoi/tasks.json":JSON.stringify({"schema_version":1,"tasks":[]}, "\t") + "\n"
	}
	for relative_file in files:
		var full_path := absolute.path_join(str(relative_file))
		var file := FileAccess.open(full_path, FileAccess.WRITE)
		if file == null:
			_remove_created_project_tree(absolute)
			Store.delete_project(project_id)
			return {"ok":false, "tool":"workspace.create_project", "error":"Aoi could not create %s. The incomplete workspace was removed." % str(relative_file)}
		file.store_string(str(files[relative_file]))
		file.flush()
		var write_error := file.get_error()
		file.close()
		if write_error != OK:
			_remove_created_project_tree(absolute)
			Store.delete_project(project_id)
			return {"ok":false, "tool":"workspace.create_project", "error":"Aoi could not finish writing %s (error %d). The incomplete workspace was removed." % [str(relative_file), write_error]}
	project["studio_local_path"] = relative
	project["studio_origin"] = "chat-created"
	project["project_kind"] = kind
	project["workspace_status"] = "active"
	var live_research_available := Store.has_secret("brave_search")
	project["research_required"] = live_research_available
	if not Store.save_project(project):
		_remove_created_project_tree(absolute)
		Store.delete_project(project_id)
		return {"ok":false, "tool":"workspace.create_project", "error":"Aoi could not save the project location. The incomplete workspace was removed."}
	AgentFlow.ensure_flow(project)
	if not live_research_available:
		AgentFlow.continue_without_external_research(project_id)
	var next_step := "Aoi will conduct evidence-backed web research before creating the implementation roadmap." if live_research_available else "Live web search is not connected, so Aoi will continue in limited research mode using your brief, saved project files and stable background knowledge. It will not claim current web sources or external citations."
	return {"ok":true, "tool":"workspace.create_project", "project_created":true, "project_id":project_id, "title":title, "goal":goal, "kind":kind, "local_path":relative, "output":"Created the %s workspace and attached it to this conversation. %s" % [kind, next_step]}


func _write_project_file(project_id: String, relative_path: String, content: String) -> void:
	var result := JobRunner.write_project_file(project_id, relative_path, content)
	result["tool"] = "project.write_file"
	if not bool(result.get("ok", false)):
		_finish(result, false)
		return
	var project := Store.get_project(project_id)
	var remote_root := str(project.get("studio_remote_path", "")).strip_edges().trim_suffix("/")
	if remote_root == "":
		_finish(result, false)
		return
	if not is_linux_connected():
		result["local_saved"] = true
		result["cloud_sync_pending"] = true
		result["output"] = str(result.get("output", "Saved project file.")) + "\nSaved on this device. Cloud sync is paused until the workspace is reconnected."
		_finish(result, false)
		return
	if not _safe_relative_project_path(relative_path):
		result["ok"] = false
		result["error"] = "The local file was saved, but its cloud workspace path was rejected as unsafe."
		result["local_saved"] = true
		_finish(result, false)
		return
	var remote_file := remote_root.path_join(relative_path.replace("\\", "/"))
	var cfg := Store.get_integration("linux_bridge")
	var base := str(cfg.get("url", "")).strip_edges().trim_suffix("/")
	var token := Store.get_secret("linux_bridge")
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json", "X-Aoi-Token: " + token])
	var payload := JSON.stringify({"path":remote_file,"content":content})
	_start_request(base + "/v1/write", HTTPClient.METHOD_POST, headers, payload, 45.0,
		func(request_result: int, code: int, body: PackedByteArray) -> void:
			var current_cfg := Store.get_integration("linux_bridge")
			if str(current_cfg.get("url", "")).strip_edges().trim_suffix("/") != base or Store.get_secret("linux_bridge") != token:
				result["ok"] = false
				result["error"] = "The file is saved on this device, but the cloud connection changed before it could sync. Test the new workspace and sync again."
				result["local_saved"] = true
				_finish(result, false)
				return
			var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
			if request_result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300 or not parsed is Dictionary or not bool(parsed.get("ok", false)):
				var failure := str(parsed.get("error", "HTTP %d" % code) if parsed is Dictionary else "connection failed")
				if request_result != HTTPRequest.RESULT_SUCCESS or code in [401, 404, 502, 503, 504]:
					_mark_linux_disconnected(base, token, failure)
				result["ok"] = false
				result["error"] = "The file was saved on this device, but could not be synced to the cloud workspace: %s" % failure
				result["local_saved"] = true
			else:
				result["output"] = str(result.get("output", "Saved project file.")) + "\nSynced to your cloud workspace."
				result["remote_path"] = remote_file
			_finish(result, false)
	, "Sync project file", false)


func _safe_relative_project_path(raw_path: String) -> bool:
	var value := raw_path.strip_edges().replace("\\", "/")
	if value == "" or value.begins_with("/") or ":" in value or value.length() > 420:
		return false
	for segment in value.split("/"):
		if segment in ["", ".", ".."]:
			return false
	return true


func _godot_create(project_id: String, name: String, goal: String) -> void:
	if not is_linux_connected():
		_finish({"ok":false,"tool":"Create game workspace","error":"Test and connect the saved cloud Linux workspace before creating a remote game project."}, false)
		return
	if not bool(Store.get_integration("linux_bridge").get("godot_available", false)):
		_finish({"ok":false,"tool":"Create game workspace","error":"The cloud workspace is connected, but Godot is not available there yet. Rebuild the Codespace setup and test the connection again."}, false)
		return
	if project_id == "" or name.strip_edges() == "" or name.length() > 80:
		_finish({"ok":false,"tool":"Create game workspace","error":"An active project and a short project name are required."}, false)
		return
	if not Store.has_secret("linux_bridge"):
		_finish({"ok":false,"tool":"Create game workspace","error":"Connect a cloud Linux workspace before creating a remote runtime project."}, false)
		return
	var project := Store.get_project(project_id)
	if project.is_empty():
		_finish({"ok":false,"tool":"Create game workspace","error":"The active Aoi project could not be found."}, false)
		return
	var cfg := Store.get_integration("linux_bridge")
	var base := str(cfg.get("url", "http://127.0.0.1:8765")).strip_edges().trim_suffix("/")
	if not _is_valid_http_base(base):
		_finish({"ok":false,"tool":"Create game workspace","error":"The cloud workspace has an invalid connection address."}, false)
		return
	var token := Store.get_secret("linux_bridge")
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json", "X-Aoi-Token: " + token])
	var remote_path := str(project.get("studio_remote_path", "")).strip_edges()
	if remote_path == "":
		remote_path = "aoi_projects/" + project_id
	if not _safe_relative_project_path(remote_path):
		_finish({"ok":false,"tool":"Create game workspace","error":"The saved cloud project folder is invalid. Reconnect the cloud workspace and try again."}, false)
		return
	var payload := JSON.stringify({"name":name,"goal":goal,"path":remote_path})
	_start_request(base + "/v1/godot/create", HTTPClient.METHOD_POST, headers, payload, 45.0,
		func(request_result: int, code: int, body: PackedByteArray) -> void:
			var current_cfg := Store.get_integration("linux_bridge")
			if str(current_cfg.get("url", "")).strip_edges().trim_suffix("/") != base or Store.get_secret("linux_bridge") != token:
				_finish({"ok":false,"tool":"Create game workspace","error":"The cloud connection changed while the project was being created. Test the new workspace before continuing."}, false)
				return
			var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
			if request_result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300 or not parsed is Dictionary or not bool(parsed.get("ok", false)):
				var failure := str(parsed.get("error", "Cloud workspace did not respond (HTTP %d)." % code) if parsed is Dictionary else "The cloud workspace could not be reached.")
				if request_result != HTTPRequest.RESULT_SUCCESS or code in [401, 404, 502, 503, 504]:
					_mark_linux_disconnected(base, token, failure)
				_finish({"ok":false,"tool":"Create game workspace","error":failure}, false)
				return
			var returned_remote_path := str(parsed.get("path", "")).strip_edges()
			if returned_remote_path == "":
				_finish({"ok":false,"tool":"Create game workspace","error":"The cloud workspace did not return a project path."}, false)
				return
			project["studio_remote_path"] = returned_remote_path
			project["studio_runtime"] = "godot"
			project["runtime_device"] = "cloud_linux"
			if not Store.save_project(project):
				_finish({"ok":false,"tool":"Create game workspace","error":"The cloud project exists at %s, but Aoi couldn't save its local connection. Reconnect or import it again before continuing." % returned_remote_path}, false)
				return
			var created_now := not bool(parsed.get("existing", false))
			var message := "Created a Godot project in the cloud workspace. Aoi can now build and run it." if created_now else "Reconnected to the existing Godot project in this cloud workspace."
			_finish({"ok":true,"tool":"Create game workspace","project_id":project_id,"path":returned_remote_path,"output":message}, false)
	, "Create game workspace", false)


func _remove_created_project_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
		return
	directory.include_hidden = true
	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "":
		if entry not in [".", ".."]:
			var child := path.path_join(entry)
			if directory.current_is_dir():
				_remove_created_project_tree(child)
			else:
				DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func run_manual(language: String, code: String) -> void:
	if busy:
		_emit_result({"ok": false, "tool": "Piston runner", "error": "Another tool is already running."}, true)
		return
	_run_piston(language.to_lower().strip_edges(), code, true)


func run_manual_linux(command: String, cwd: String = ".") -> void:
	if busy:
		_emit_result({"ok":false,"tool":"Linux command","error":"Another tool is already running."}, true)
		return
	_linux_request("exec", {"command":command,"cwd":cwd,"timeout":30}, true)


func test_linux_bridge() -> void:
	if busy:
		_emit_result({"ok":false,"tool":"Linux connection test","error":"Another tool is already running."}, true)
		return
	var cfg := Store.get_integration("linux_bridge")
	var base := str(cfg.get("url", "http://127.0.0.1:8765")).strip_edges().trim_suffix("/")
	var tested_token := Store.get_secret("linux_bridge")
	if not _is_valid_http_base(base) or not base.begins_with("https://") or tested_token.length() != 64 or not tested_token.is_valid_hex_number(false):
		_emit_result({"ok":false,"tool":"Linux connection test","error":"Use the forwarded HTTPS address and the 64-character hexadecimal key saved as AOI_BRIDGE_TOKEN in Codespaces."}, true)
		return
	cfg["last_test_ok"] = false
	cfg["last_test_at"] = Time.get_unix_time_from_system()
	cfg["last_test_error"] = "Connection check in progress."
	Store.set_integration("linux_bridge", cfg)
	var headers := PackedStringArray(["Accept: application/json", "X-Aoi-Token: " + tested_token])
	var cb := func(result: int, code: int, body: PackedByteArray):
		# A late health response must never bless a different endpoint or token.
		var current_cfg := Store.get_integration("linux_bridge")
		var current_base := str(current_cfg.get("url", "")).strip_edges().trim_suffix("/")
		if current_base != base or Store.get_secret("linux_bridge") != tested_token:
			_finish({"ok":false,"tool":"Linux connection test","error":"Connection details changed while the test was running. Test the newly saved address and token."}, true)
			return
		var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
		var bridge_cfg := Store.get_integration("linux_bridge")
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and payload is Dictionary and bool(payload.get("ok", false)):
			var capabilities: Dictionary = payload.get("capabilities", {}) if payload.get("capabilities", {}) is Dictionary else {}
			var codespaces_target := str(bridge_cfg.get("provider", "")) == "github_codespaces" or str(bridge_cfg.get("target", "")) == "codespaces"
			if codespaces_target and not bool(capabilities.get("isolated_execution", false)):
				var isolation_message := "This Codespace is running an older bridge without the separate project runner. Rebuild the Codespace container, then restart and test it again. Aoi will not run project code beside the credential-bearing bridge."
				bridge_cfg["last_test_ok"] = false
				bridge_cfg["isolated_execution"] = false
				bridge_cfg["last_test_at"] = Time.get_unix_time_from_system()
				bridge_cfg["last_test_error"] = isolation_message
				bridge_cfg["godot_available"] = false
				Store.set_integration("linux_bridge", bridge_cfg)
				_finish({"ok":false,"tool":"Linux connection test","error":isolation_message}, true)
				return
			bridge_cfg["isolated_execution"] = bool(capabilities.get("isolated_execution", false))
			bridge_cfg["last_test_ok"] = true
			bridge_cfg["last_test_at"] = Time.get_unix_time_from_system()
			bridge_cfg["last_test_error"] = ""
			bridge_cfg["tested_url"] = base
			bridge_cfg["tested_token_sha256"] = _linux_token_fingerprint(tested_token)
			bridge_cfg["bridge_name"] = str(payload.get("bridge", "Aoi Linux Bridge"))
			bridge_cfg["workspace"] = str(payload.get("workspace", ""))
			var godot_info: Dictionary = payload.get("godot", {}) if payload.get("godot", {}) is Dictionary else {}
			bridge_cfg["godot_available"] = bool(godot_info.get("available", false))
			bridge_cfg["godot_version"] = str(godot_info.get("version", ""))
			Store.set_integration("linux_bridge", bridge_cfg)
			var godot_status := str(godot_info.get("version", "Godot detected")) if bool(godot_info.get("available", false)) else "Not detected · remote file tools are available, but game execution is not ready"
			var output := "Connected to %s\nWorkspace: %s\nGodot: %s" % [str(payload.get("bridge", "Aoi Linux Bridge")), str(payload.get("workspace", "unknown")), godot_status]
			_finish({"ok":true,"tool":"Linux connection test","output":output,"error":""}, true)
		else:
			var message := ""
			if result != HTTPRequest.RESULT_SUCCESS:
				message = "Aoi could not reach the cloud workspace. Confirm the Codespace is running, port 8765 is forwarded as Public, and the saved HTTPS address is current."
			elif code == 401:
				message = "The cloud workspace rejected the connection key. Use the same 64-character key in Aoi and the AOI_BRIDGE_TOKEN Codespaces secret, then restart the Codespace."
			elif code == 404:
				message = "The workspace bridge returned 404. Check that the saved address ends with the forwarded port 8765 and that the Codespace has the current Aoi bridge files."
			elif code >= 500:
				message = "The Linux bridge returned HTTP %d. Check the companion terminal for its error, then restart it." % code
			else:
				message = str(payload.get("error", "HTTP %d" % code)) if payload is Dictionary else "HTTP %d" % code
			bridge_cfg["last_test_ok"] = false
			bridge_cfg["last_test_at"] = Time.get_unix_time_from_system()
			bridge_cfg["last_test_error"] = message.left(300)
			Store.set_integration("linux_bridge", bridge_cfg)
			_finish({"ok":false,"tool":"Linux connection test","error":message}, true)
	_start_request(base + "/health", HTTPClient.METHOD_GET, headers, "", 12.0, cb, "Linux connection test", true)


func cancel() -> void:
	if not busy: return
	if _active_job_id != "":
		var job_id := _active_job_id
		_active_job_id = ""
		JobRunner.cancel_job(job_id)
		_finish({"ok":false,"tool":"Project task stopped","error":"The project task was stopped. Its latest checkpoint and run artifacts are preserved."}, _active_manual)
		return
	_cancel_requested = true
	state_changed.emit("cancelling", _active_tool)
	if _active_request != null and is_instance_valid(_active_request):
		_active_request.cancel_request()


func _start_project_task(project_id: String, task_id: String, parameters: Variant) -> void:
	if project_id == "" or task_id == "":
		_finish({"ok":false,"tool":"Project task","error":"A project ID and declared task ID are required."}, false)
		return
	var result := JobRunner.start_project_task(project_id, task_id, parameters if parameters is Dictionary else {})
	if not bool(result.get("ok", false)):
		result["tool"] = "Project task"
		_finish(result, false)
		return
	busy = true
	_active_manual = false
	_active_tool = "Project task · " + task_id
	_active_job_id = str(result.get("job_id", ""))
	state_changed.emit("running", "%s · %s" % [_active_tool, _active_job_id])


func _resume_project_task(job_id: String) -> void:
	var result := JobRunner.resume_job(job_id)
	if not bool(result.get("ok", false)):
		result["tool"] = "Resume project task"
		_finish(result, false)
		return
	busy = true
	_active_manual = false
	_active_job_id = job_id
	_active_tool = "Project task · resumed"
	state_changed.emit("running", "%s · %s" % [_active_tool, job_id])


func _on_job_finished(result: Dictionary) -> void:
	if _active_job_id == "" or str(result.get("job_id", "")) != _active_job_id:
		return
	_active_job_id = ""
	var output := result.duplicate(true)
	output["tool"] = _active_tool
	if bool(output.get("ok", false)):
		output["output"] = str(output.get("output", "Job completed."))
	_finish(output, _active_manual)


func _on_job_progress(job_id: String, progress: float, detail: String) -> void:
	if job_id == _active_job_id:
		state_changed.emit("running", "%s · %d%% · %s" % [_active_tool, roundi(progress * 100.0), detail])


func _require_secret(secret_id: String, display_name: String) -> bool:
	if Store.has_secret(secret_id): return true
	_finish({"ok": false, "tool": display_name, "error": "Connect %s in Plugins & tools before using this tool." % display_name}, false)
	return false


func _github_token_fingerprint(token: String) -> String:
	var digest := HashingContext.new()
	if digest.start(HashingContext.HASH_SHA256) != OK:
		return ""
	digest.update(token.to_utf8_buffer())
	return digest.finish().hex_encode()


func is_github_connected() -> bool:
	var token := Store.get_secret("github")
	if token == "":
		return false
	var integration := Store.get_integration("github")
	return (
		str(integration.get("login", "")).strip_edges() != ""
		and str(integration.get("token_sha256", "")) == _github_token_fingerprint(token)
	)


func _linux_token_fingerprint(token: String) -> String:
	var digest := HashingContext.new()
	if digest.start(HashingContext.HASH_SHA256) != OK:
		return ""
	digest.update(token.to_utf8_buffer())
	return digest.finish().hex_encode()


func is_linux_connected() -> bool:
	var token := Store.get_secret("linux_bridge")
	if token.length() != 64 or not token.is_valid_hex_number(false):
		return false
	var integration := Store.get_integration("linux_bridge")
	var base := str(integration.get("url", "")).strip_edges().trim_suffix("/")
	var codespaces_target := str(integration.get("provider", "")) == "github_codespaces" or str(integration.get("target", "")) == "codespaces"
	var isolated_runner_ok := not codespaces_target or bool(integration.get("isolated_execution", false))
	return (
		base.begins_with("https://")
		and _is_valid_http_base(base)
		and bool(integration.get("last_test_ok", false))
		and str(integration.get("tested_url", "")) == base
		and str(integration.get("tested_token_sha256", "")) == _linux_token_fingerprint(token)
		and isolated_runner_ok
	)


func _mark_linux_disconnected(base: String, token: String, reason: String) -> void:
	var integration := Store.get_integration("linux_bridge")
	var current_base := str(integration.get("url", "")).strip_edges().trim_suffix("/")
	if current_base != base or Store.get_secret("linux_bridge") != token:
		return
	integration["last_test_ok"] = false
	integration["last_test_error"] = reason.left(300)
	integration["last_test_at"] = Time.get_unix_time_from_system()
	integration["godot_available"] = false
	Store.set_integration("linux_bridge", integration)


func _require_verified_github(action_name: String, manual: bool) -> bool:
	if not Store.has_secret("github"):
		_finish({"ok":false,"tool":action_name,"error":"Connect and verify a GitHub personal access token before requesting repository changes."}, manual)
		return false
	if not is_github_connected():
		_finish({"ok":false,"tool":action_name,"error":"A GitHub token is saved but not verified. Open Plugins & tools → GitHub and verify the account before requesting repository changes."}, manual)
		return false
	return true


func _github_headers() -> PackedStringArray:
	var headers := PackedStringArray([
		"Accept: application/vnd.github+json",
		"X-GitHub-Api-Version: 2026-03-10",
		"User-Agent: " + GITHUB_USER_AGENT
	])
	var token := Store.get_secret("github")
	if token != "" and is_github_connected(): headers.append("Authorization: Bearer " + token)
	return headers


func _run_piston(language: String, code: String, manual: bool) -> void:
	var cfg := Store.get_integration("piston")
	var base := str(cfg.get("url", "")).strip_edges().trim_suffix("/")
	if base.ends_with("/api/v2"):
		base = base.trim_suffix("/api/v2")
	elif base.ends_with("/api"):
		base = base.trim_suffix("/api")
	if not _is_valid_http_base(base):
		_finish({"ok": false, "tool": "Piston runner", "error": "Connect a valid HTTP or HTTPS Piston API server in Plugins & tools first."}, manual)
		return
	if language not in ["python", "javascript", "bash"]:
		_finish({"ok": false, "tool": "Piston runner", "error": "Supported languages are Python, JavaScript and Bash."}, manual)
		return
	if code.strip_edges() == "":
		_finish({"ok": false, "tool": "Piston runner", "error": "There is no code to run."}, manual)
		return
	if code.length() > MAX_CODE_CHARS:
		_finish({"ok": false, "tool": "Piston runner", "error": "Code is too long for a single run (%d characters maximum)." % MAX_CODE_CHARS}, manual)
		return

	var file_name := "main.py" if language == "python" else ("main.js" if language == "javascript" else "main.sh")
	var payload := {
		"language": language,
		"version": "*",
		"files": [{"name": file_name, "content": code}],
		"stdin": ""
	}
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json", "User-Agent: " + GITHUB_USER_AGENT])
	var token := Store.get_secret("piston")
	if token != "": headers.append("Authorization: Bearer " + token)
	_request_json(base + "/api/v2/execute", payload, headers, "Piston runner", manual, 75.0)


func _request_json(url: String, payload: Dictionary, headers: PackedStringArray, tool_name: String, manual: bool, timeout: float) -> void:
	_start_request(url, HTTPClient.METHOD_POST, headers, JSON.stringify(payload), timeout, func(result: int, code: int, body: PackedByteArray):
		_handle_piston_response(result, code, body, manual), tool_name, manual)


func _handle_piston_response(result: int, code: int, body: PackedByteArray, manual: bool) -> void:
	var output := ""
	var error_text := ""
	var run_exit := 0
	var compile_exit := 0
	if result != HTTPRequest.RESULT_SUCCESS:
		error_text = "The runner could not be reached. Check the URL, server status and network connection."
	else:
		var obj: Variant = JSON.parse_string(body.get_string_from_utf8())
		if code < 200 or code >= 300:
			var message := ""
			if obj is Dictionary: message = str(obj.get("message", obj.get("error", "")))
			error_text = "Piston rejected the request (HTTP %d). %s" % [code, message.left(350)]
		elif obj is Dictionary and obj.has("run"):
			var run_value: Variant = obj.get("run", {})
			var compile_value: Variant = obj.get("compile", {})
			var run_data: Dictionary = run_value if run_value is Dictionary else {}
			var compile_data: Dictionary = compile_value if compile_value is Dictionary else {}
			var stdout := str(run_data.get("stdout", ""))
			var stderr := str(run_data.get("stderr", ""))
			var compile_stderr := str(compile_data.get("stderr", ""))
			run_exit = int(run_data.get("code", 0))
			compile_exit = int(compile_data.get("code", 0))
			output = stdout
			if compile_stderr != "": output += ("\n" if output != "" else "") + compile_stderr
			if stderr != "": output += ("\n" if output != "" else "") + stderr
			if compile_exit != 0:
				error_text = "Compilation failed (exit code %d)." % compile_exit
			elif run_exit != 0:
				error_text = "Program exited with code %d." % run_exit
			if output.strip_edges() == "" and error_text == "": output = "Program finished with no output."
		else:
			error_text = "Piston returned an unexpected response (HTTP %d)." % code

	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300 and run_exit == 0 and compile_exit == 0 and error_text == ""
	_finish({"ok": ok, "tool": "Piston runner", "output": output.left(MAX_TOOL_OUTPUT_CHARS), "error": error_text}, manual)


func _search_github(query: String, manual: bool) -> void:
	if query == "" or query.length() > 256:
		_finish({"ok": false, "tool": "GitHub search", "error": "Provide a repository search query (1–256 characters)."}, manual)
		return
	var url := GITHUB_API + "/search/repositories?q=" + query.uri_encode() + "&sort=stars&order=desc&per_page=6"
	var handle_response := func(result: int, code: int, body: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_finish({"ok": false, "tool": "GitHub repository search", "error": _github_error(result, code, body)}, manual)
			return
		var obj: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not obj is Dictionary:
			_finish({"ok": false, "tool": "GitHub repository search", "error": "GitHub returned data Aoi could not read."}, manual)
			return
		var lines: Array[String] = []
		for item in obj.get("items", []):
			if not item is Dictionary: continue
			var description := str(item.get("description", "No description provided.")).strip_edges()
			if description == "": description = "No description provided."
			lines.append("%s  ·  %s stars  ·  %s\n%s\n%s" % [
				str(item.get("full_name", "Unknown repository")),
				str(item.get("stargazers_count", 0)),
				str(item.get("language", "Language not listed")),
				description,
				str(item.get("html_url", ""))
			])
		var text := "\n\n".join(lines) if not lines.is_empty() else "No repositories matched that query."
		_finish({"ok": true, "tool": "GitHub repository search", "output": text, "error": ""}, manual)
	_start_request(url, HTTPClient.METHOD_GET, _github_headers(), "", 30.0, handle_response, "GitHub repository search", manual)


func _get_repository_info(repository: String, manual: bool) -> void:
	var normalized := _normalize_repository(repository)
	if normalized == "":
		_finish({"ok": false, "tool": "GitHub repository info", "error": "Use a repository in owner/repository format."}, manual)
		return
	var handle_response := func(result: int, code: int, body: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_finish({"ok": false, "tool": "GitHub repository info", "error": _github_error(result, code, body)}, manual)
			return
		var obj: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not obj is Dictionary:
			_finish({"ok": false, "tool": "GitHub repository info", "error": "GitHub returned data Aoi could not read."}, manual)
			return
		var license_value: Variant = obj.get("license", {})
		var license_name := str(license_value.get("spdx_id", "Not specified")) if license_value is Dictionary else "Not specified"
		var topics: Array = obj.get("topics", [])
		var topic_names := PackedStringArray()
		for topic in topics: topic_names.append(str(topic))
		var summary := "Repository: %s\nDescription: %s\nLanguage: %s\nStars: %s\nForks: %s\nDefault branch: %s\nLicense: %s\nTopics: %s\nLast updated: %s\nURL: %s" % [
			str(obj.get("full_name", normalized)),
			str(obj.get("description", "No description provided.")),
			str(obj.get("language", "Not listed")),
			str(obj.get("stargazers_count", 0)),
			str(obj.get("forks_count", 0)),
			str(obj.get("default_branch", "main")),
			license_name,
			", ".join(topic_names),
			str(obj.get("updated_at", "Unknown")),
			str(obj.get("html_url", ""))
		]
		_finish({"ok": true, "tool": "GitHub repository info", "output": summary, "error": ""}, manual)
	_start_request(GITHUB_API + "/repos/" + normalized, HTTPClient.METHOD_GET, _github_headers(), "", 30.0, handle_response, "GitHub repository info", manual)


func _read_repository_file(repository: String, path: String, ref: String, manual: bool) -> void:
	var normalized := _normalize_repository(repository)
	var clean_path := path.strip_edges().trim_prefix("/")
	if normalized == "":
		_finish({"ok": false, "tool": "GitHub file reader", "error": "Use a repository in owner/repository format."}, manual)
		return
	if clean_path == "" or clean_path.contains("..") or clean_path.contains("\\") or clean_path.length() > 240:
		_finish({"ok": false, "tool": "GitHub file reader", "error": "Provide a safe repository-relative file path."}, manual)
		return
	var encoded_segments: Array[String] = []
	for segment in clean_path.split("/", false): encoded_segments.append(segment.uri_encode())
	var url := GITHUB_API + "/repos/" + normalized + "/contents/" + "/".join(encoded_segments)
	if ref != "": url += "?ref=" + ref.uri_encode()
	var handle_response := func(result: int, code: int, body: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_finish({"ok": false, "tool": "GitHub file reader", "error": _github_error(result, code, body)}, manual)
			return
		var obj: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not obj is Dictionary or str(obj.get("type", "")) != "file":
			_finish({"ok": false, "tool": "GitHub file reader", "error": "That path did not resolve to a single file. Choose a file rather than a directory."}, manual)
			return
		if str(obj.get("encoding", "")) != "base64":
			_finish({"ok": false, "tool": "GitHub file reader", "error": "GitHub did not provide this file as base64 text. It may be too large or binary."}, manual)
			return
		if int(obj.get("size", 0)) > 120000:
			_finish({"ok": false, "tool": "GitHub file reader", "error": "That file is larger than Aoi's 120 KB reading limit. Choose a smaller source file."}, manual)
			return
		var encoded := str(obj.get("content", "")).replace("\n", "").replace("\r", "").replace(" ", "")
		var decoded := Marshalls.base64_to_raw(encoded).get_string_from_utf8()
		var heading := "%s · %s bytes · SHA %s\n" % [str(obj.get("path", clean_path)), str(obj.get("size", 0)), str(obj.get("sha", ""))]
		_finish({"ok": true, "tool": "GitHub file reader", "output": heading + decoded.left(MAX_TOOL_OUTPUT_CHARS), "error": ""}, manual)
	_start_request(url, HTTPClient.METHOD_GET, _github_headers(), "", 30.0, handle_response, "GitHub file reader", manual)


func _list_repository_tree(repository: String, branch: String, manual: bool) -> void:
	var normalized := _normalize_repository(repository)
	if normalized == "":
		_finish({"ok":false,"tool":"GitHub tree","error":"Use owner/repository format."}, manual); return
	if branch == "": branch = "HEAD"
	var url := GITHUB_API + "/repos/" + normalized + "/git/trees/" + branch.uri_encode() + "?recursive=1"
	var callback := func(result: int, code: int, body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_finish({"ok":false,"tool":"GitHub repository tree","error":_github_error(result, code, body)}, manual); return
		var data: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not data is Dictionary:
			_finish({"ok":false,"tool":"GitHub repository tree","error":"GitHub returned invalid tree data."}, manual); return
		var rows: Array[String] = []
		for entry in data.get("tree", []):
			if not entry is Dictionary: continue
			var path := str(entry.get("path", ""))
			if path == "": continue
			rows.append(("[dir] " if str(entry.get("type", "")) == "tree" else "[file] ") + path)
			if rows.size() >= 160: break
		var suffix := "\n… tree truncated to 160 entries" if int(data.get("truncated_count", 0)) > 0 else ""
		_finish({"ok":true,"tool":"GitHub repository tree","output":"Repository tree for %s\n%s%s" % [normalized, "\n".join(rows), suffix],"error":""}, manual)
	_start_request(url, HTTPClient.METHOD_GET, _github_headers(), "", 35.0, callback, "GitHub repository tree", manual)

func list_github_codespaces() -> void:
	if busy:
		_emit_result({"ok":false,"tool":"GitHub Codespaces list","error":"Another GitHub request is already running."}, true)
		return
	if not _require_verified_github("GitHub Codespaces", true): return
	_fetch_github_codespaces_page(1, [], Store.get_secret("github"))


func _fetch_github_codespaces_page(page: int, accumulated: Array[Dictionary], github_token_snapshot: String) -> void:
	if Store.get_secret("github") != github_token_snapshot or not is_github_connected():
		_finish({"ok":false,"tool":"GitHub Codespaces list","error":"The GitHub connection changed while Aoi was loading your workspaces. Verify it again and refresh."}, true)
		return
	var url := GITHUB_API + "/user/codespaces?per_page=100&page=%d" % page
	var callback := func(result: int, code: int, body: PackedByteArray) -> void:
		if Store.get_secret("github") != github_token_snapshot or not is_github_connected():
			_finish({"ok":false,"tool":"GitHub Codespaces list","error":"The GitHub connection changed while Aoi was loading your workspaces. Verify it again and refresh."}, true)
			return
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			var message := _github_error(result, code, body)
			if code == 403:
				message = "GitHub denied Codespaces access. Set Codespaces repository permission to Read and write on the selected repositories, then reconnect the token. " + message
			_finish({"ok":false,"tool":"GitHub Codespaces list","error":message}, true)
			return
		var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not payload is Dictionary or not payload.get("codespaces", []) is Array:
			_finish({"ok":false,"tool":"GitHub Codespaces list","error":"GitHub returned an unexpected Codespaces response."}, true)
			return
		var page_items: Array = payload.get("codespaces", [])
		for raw_item in page_items:
			if not raw_item is Dictionary: continue
			var name := str(raw_item.get("name", "")).strip_edges()
			if name == "": continue
			var repo_data: Dictionary = raw_item.get("repository", {}) if raw_item.get("repository", {}) is Dictionary else {}
			var machine_data: Dictionary = raw_item.get("machine", {}) if raw_item.get("machine", {}) is Dictionary else {}
			var git_data: Dictionary = raw_item.get("git_status", {}) if raw_item.get("git_status", {}) is Dictionary else {}
			accumulated.append({
				"name":name,
				"repository":str(repo_data.get("full_name", "")),
				"state":str(raw_item.get("state", "Unknown")),
				"web_url":str(raw_item.get("web_url", "")),
				"machine":str(machine_data.get("display_name", machine_data.get("name", ""))),
				"ref":str(git_data.get("ref", "")),
				"created_at":str(raw_item.get("created_at", "")),
				"updated_at":str(raw_item.get("updated_at", "")),
				"last_used_at":str(raw_item.get("last_used_at", ""))
			})
		# GitHub pages Codespaces at 100 entries. Only release the uncertain-create
		# lock after a complete list; a truncated first page cannot prove the new
		# workspace is absent.
		if page_items.size() >= 100:
			if page >= 10:
				var partial_saved := Store.get_integration("github_codespaces")
				partial_saved["items"] = accumulated
				partial_saved["items_complete"] = false
				partial_saved["refreshed_at"] = Time.get_unix_time_from_system()
				Store.set_integration("github_codespaces", partial_saved)
				_finish({"ok":false,"tool":"GitHub Codespaces list","error":"GitHub returned more than 1,000 Codespaces. The list is partial, so Aoi has kept the duplicate-creation safeguard active."}, true)
				return
			_fetch_github_codespaces_page(page + 1, accumulated, github_token_snapshot)
			return
		var saved := Store.get_integration("github_codespaces")
		saved["items"] = accumulated
		saved["items_complete"] = true
		saved["refreshed_at"] = Time.get_unix_time_from_system()
		saved.erase("creation_uncertain")
		Store.set_integration("github_codespaces", saved)
		_finish({"ok":true,"tool":"GitHub Codespaces list","codespaces":accumulated,"output":"Found %d Codespace(s)." % accumulated.size()}, true)
	_start_request(url, HTTPClient.METHOD_GET, _github_headers(), "", 35.0, callback, "GitHub Codespaces list", true)


func create_github_codespace(repository: String, branch: String = "") -> void:
	if busy:
		_emit_result({"ok":false,"tool":"GitHub Codespaces create","error":"Another request is already running. Wait for it to finish before creating a workspace."}, true)
		return
	if not _require_verified_github("GitHub Codespaces creation", true): return
	var pending_create: Variant = Store.get_integration("github_codespaces").get("creation_uncertain", {})
	if pending_create is Dictionary and not pending_create.is_empty():
		_finish({"ok":false,"tool":"GitHub Codespaces create","error":"Refresh the complete Codespaces list before creating another workspace. The previous request may already have succeeded."}, true)
		return
	var github_token_snapshot := Store.get_secret("github")
	var normalized := _normalize_repository(repository)
	if normalized == "":
		_finish({"ok":false,"tool":"GitHub Codespaces create","error":"Enter a GitHub repository in owner/repository format."}, true)
		return
	var bridge_key := Store.get_secret("linux_bridge")
	if bridge_key.length() != 64 or not bridge_key.is_valid_hex_number(false):
		_finish({"ok":false,"tool":"GitHub Codespaces create","error":"Generate and save the cloud connection key first. Add that exact key to the repository's Codespaces secret named AOI_BRIDGE_TOKEN before creating the workspace."}, true)
		return
	var clean_branch := branch.strip_edges()
	if clean_branch.length() > 255 or clean_branch.contains(" ") or clean_branch.contains(".."):
		_finish({"ok":false,"tool":"GitHub Codespaces create","error":"The branch name is invalid. Leave it blank to use the repository's default branch."}, true)
		return

	# Ask GitHub for repository-eligible machine sizes first. Choosing the
	# smallest Linux option makes included core-hour usage go further and avoids
	# silently selecting an unnecessarily large billable machine.
	var machine_url := GITHUB_API + "/repos/" + normalized + "/codespaces/machines"
	if clean_branch != "": machine_url += "?ref=" + clean_branch.uri_encode()
	var machine_callback := func(result: int, code: int, body: PackedByteArray) -> void:
		if Store.get_secret("github") != github_token_snapshot or not is_github_connected():
			_finish({"ok":false,"tool":"GitHub Codespaces create","error":"The GitHub connection changed while Aoi was checking machine availability. Verify the current token and try again; no workspace was created."}, true)
			return
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			var message := _github_error(result, code, body)
			if code == 403:
				message = "GitHub denied the machine-size lookup. Add repository permission Codespaces metadata = Read, as well as Codespaces = Read and write, then reconnect the token. " + message
			elif code == 404:
				message = "GitHub cannot inspect machine options for that repository/branch. Check its spelling, selected token repositories and branch."
			_finish({"ok":false,"tool":"GitHub Codespaces create","error":message}, true)
			return
		var machine_payload: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not machine_payload is Dictionary or not machine_payload.get("machines", []) is Array:
			_finish({"ok":false,"tool":"GitHub Codespaces create","error":"GitHub returned an unexpected machine availability response. Nothing was provisioned."}, true)
			return
		var chosen_machine: Dictionary = {}
		for raw_machine in machine_payload.get("machines", []):
			if not raw_machine is Dictionary: continue
			if str(raw_machine.get("operating_system", "linux")).to_lower() != "linux": continue
			var machine_name := str(raw_machine.get("name", "")).strip_edges()
			var machine_cpus := int(raw_machine.get("cpus", 0))
			if machine_name == "" or machine_cpus <= 0: continue
			var candidate_memory := int(raw_machine.get("memory_in_bytes", 0))
			var candidate_storage := int(raw_machine.get("storage_in_bytes", 0))
			if chosen_machine.is_empty():
				chosen_machine = raw_machine
				continue
			var chosen_cpus := int(chosen_machine.get("cpus", 0))
			var chosen_memory := int(chosen_machine.get("memory_in_bytes", 0))
			var chosen_storage := int(chosen_machine.get("storage_in_bytes", 0))
			if machine_cpus < chosen_cpus or (machine_cpus == chosen_cpus and candidate_memory < chosen_memory) or (machine_cpus == chosen_cpus and candidate_memory == chosen_memory and candidate_storage < chosen_storage):
				chosen_machine = raw_machine
		if chosen_machine.is_empty():
			_finish({"ok":false,"tool":"GitHub Codespaces create","error":"GitHub did not offer an eligible Linux machine for this repository. Nothing was provisioned."}, true)
			return
		_create_github_codespace_request(normalized, clean_branch, chosen_machine, github_token_snapshot)
	_start_request(machine_url, HTTPClient.METHOD_GET, _github_headers(), "", 35.0, machine_callback, "GitHub Codespaces machine options", true)


func _mark_github_codespace_creation_uncertain(repository: String, branch: String, reason: String) -> void:
	var saved := Store.get_integration("github_codespaces")
	saved["creation_uncertain"] = {
		"repository":repository,
		"ref":branch,
		"at":Time.get_unix_time_from_system(),
		"reason":reason.left(240)
	}
	Store.set_integration("github_codespaces", saved)


func _create_github_codespace_request(repository: String, branch: String, machine: Dictionary, github_token_snapshot: String) -> void:
	if Store.get_secret("github") != github_token_snapshot or not is_github_connected():
		_finish({"ok":false,"tool":"GitHub Codespaces create","error":"The GitHub connection changed before provisioning. Verify the current token and try again; no workspace was created."}, true)
		return
	var request_body := {
		"devcontainer_path":".devcontainer/devcontainer.json",
		"idle_timeout_minutes":30,
		"display_name":"Aoi Linux workspace",
		"machine":str(machine.get("name", ""))
	}
	if branch != "": request_body["ref"] = branch
	var endpoint := GITHUB_API + "/repos/" + repository + "/codespaces"
	var callback := func(result: int, code: int, body: PackedByteArray) -> void:
		var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
		if Store.get_secret("github") != github_token_snapshot or not is_github_connected():
			_mark_github_codespace_creation_uncertain(repository, branch, "GitHub connection changed after the create request was sent.")
			_finish({"ok":false,"tool":"GitHub Codespaces create","error":"The GitHub connection changed while provisioning. GitHub may have accepted the request, so Aoi has blocked another create until you refresh existing Codespaces."}, true)
			return
		if result != HTTPRequest.RESULT_SUCCESS:
			_mark_github_codespace_creation_uncertain(repository, branch, "GitHub did not return a conclusive create response.")
			_finish({"ok":false,"tool":"GitHub Codespaces create","error":"GitHub did not return the creation result. It may still have created the workspace, so Aoi has temporarily blocked another create. Refresh existing Codespaces first; if one appeared, select it instead of creating a duplicate."}, true)
			return
		if code not in [201, 202]:
			var detail := str(payload.get("message", "")) if payload is Dictionary else ""
			var message := "GitHub could not create the Codespace (HTTP %d). %s" % [code, detail.left(220)]
			# A gateway/server error or rate limit can arrive after GitHub has
			# accepted a create. Keep the create action locked until a fresh list
			# confirms whether the Codespace exists; do not risk a duplicate.
			if code == 401:
				message = "GitHub rejected the saved token. Reconnect GitHub with a valid token."
			elif code == 403:
				message = "GitHub denied Codespaces creation. Your fine-grained token needs Codespaces = Read and write for this repository, and the repository must be included in the token's repository access. " + detail.left(180)
			elif code == 404:
				message = "GitHub could not access that repository. Check owner/repository spelling and the token's selected repository access."
			elif code == 402 or code == 422:
				message = "GitHub could not provision this Codespace. Check your included compute/storage allowance, repository Codespaces policy, dev-container configuration and machine capacity. " + detail.left(180)
			elif code in [408, 425, 429] or code >= 500:
				_mark_github_codespace_creation_uncertain(repository, branch, "GitHub returned HTTP %d after the create request." % code)
				message = "GitHub returned HTTP %d and the creation result is uncertain. Refresh existing Codespaces before trying again; Aoi will not risk creating a duplicate. %s" % [code, detail.left(160)]
			_finish({"ok":false,"tool":"GitHub Codespaces create","error":message}, true)
			return
		if not payload is Dictionary:
			_mark_github_codespace_creation_uncertain(repository, branch, "GitHub accepted the create but returned unreadable workspace data.")
			_finish({"ok":false,"tool":"GitHub Codespaces create","error":"GitHub accepted the request but returned an unreadable workspace record. Aoi has blocked another create until you refresh the Codespaces list."}, true)
			return
		var name := str(payload.get("name", "")).strip_edges()
		if name == "":
			_mark_github_codespace_creation_uncertain(repository, branch, "GitHub accepted the create but did not return a workspace name.")
			_finish({"ok":false,"tool":"GitHub Codespaces create","error":"GitHub accepted the request but did not return a workspace name. Refresh Codespaces before attempting another create."}, true)
			return
		var web_url := str(payload.get("web_url", "https://github.com/codespaces"))
		var bridge_url := "https://%s-8765.app.github.dev" % name
		var state := str(payload.get("state", "Queued" if code == 202 else "Starting"))
		var selected_machine := str(machine.get("display_name", machine.get("name", "smallest available Linux machine")))
		var cloud_cfg := Store.get_integration("linux_bridge")
		cloud_cfg["url"] = bridge_url
		cloud_cfg["target"] = "codespaces"
		cloud_cfg["provider"] = "github_codespaces"
		cloud_cfg["last_test_ok"] = false
		cloud_cfg["last_test_at"] = 0
		cloud_cfg["last_test_error"] = "Codespace is provisioning. Test the bridge after its dev-container setup has finished."
		cloud_cfg["tested_url"] = ""
		cloud_cfg["tested_token_sha256"] = ""
		cloud_cfg["godot_available"] = false
		cloud_cfg["godot_version"] = ""
		cloud_cfg["isolated_execution"] = false
		cloud_cfg["codespace_name"] = name
		cloud_cfg["codespace_web_url"] = web_url
		cloud_cfg["codespace_state"] = state
		cloud_cfg["repository"] = repository
		cloud_cfg["ref"] = branch
		cloud_cfg["machine"] = str(machine.get("name", ""))
		cloud_cfg["machine_display_name"] = selected_machine
		cloud_cfg["machine_cpus"] = int(machine.get("cpus", 0))
		Store.set_integration("linux_bridge", cloud_cfg)
		var saved := Store.get_integration("github_codespaces")
		saved.erase("creation_uncertain")
		saved["repository"] = repository
		saved["last_created"] = {"name":name,"repository":repository,"state":state,"web_url":web_url,"bridge_url":bridge_url,"ref":branch,"machine":str(machine.get("name", "")),"machine_display_name":selected_machine,"machine_cpus":int(machine.get("cpus", 0))}
		Store.set_integration("github_codespaces", saved)
		var machine_copy := "%s (%d cores)" % [selected_machine, int(machine.get("cpus", 0))]
		_finish({"ok":true,"tool":"GitHub Codespaces create","output":"GitHub %s the Codespace %s for %s using the smallest available Linux machine: %s. Its Linux bridge URL has been saved; allow the dev-container setup to finish before testing it." % ["accepted" if code == 202 else "created", name, repository, machine_copy],"codespace":{"name":name,"repository":repository,"state":state,"web_url":web_url,"bridge_url":bridge_url,"ref":branch,"machine":str(machine.get("name", "")),"machine_display_name":selected_machine,"machine_cpus":int(machine.get("cpus", 0))}}, true)
	# Codespace creation is a billable resource mutation. Never automatically retry this POST.
	_start_request(endpoint, HTTPClient.METHOD_POST, _github_headers() + PackedStringArray(["Content-Type: application/json"]), JSON.stringify(request_body), 90.0, callback, "GitHub Codespaces create", true, false)


func use_github_codespace(codespace: Dictionary) -> void:
	if busy:
		_emit_result({"ok":false,"tool":"GitHub Codespaces use","error":"Another request is already running. Wait for it to finish."}, true)
		return
	if not _require_verified_github("GitHub Codespaces", true): return
	var name := str(codespace.get("name", "")).strip_edges()
	var valid_name := RegEx.new()
	valid_name.compile("^[A-Za-z0-9][A-Za-z0-9-]{0,99}$")
	if name == "" or valid_name.search(name) == null:
		_finish({"ok":false,"tool":"GitHub Codespaces use","error":"GitHub returned an invalid Codespace name. Refresh the workspace list."}, true)
		return
	var bridge_key := Store.get_secret("linux_bridge")
	if bridge_key.length() != 64 or not bridge_key.is_valid_hex_number(false):
		_finish({"ok":false,"tool":"GitHub Codespaces use","error":"Generate and add the cloud connection key to AOI_BRIDGE_TOKEN before using this workspace."}, true)
		return
	var state := str(codespace.get("state", "Unknown")).to_lower()
	if state in ["available", "running"]:
		var attached := attach_github_codespace(codespace)
		_finish({"ok":bool(attached.get("ok", false)),"tool":"GitHub Codespaces use","codespace":codespace,"output":"Selected the running Codespace %s. Test the Linux bridge to confirm Godot and project execution are ready." % name,"error":str(attached.get("error", ""))}, true)
		return
	if state in ["creating", "queued", "starting"]:
		var attached_pending := attach_github_codespace(codespace)
		_finish({"ok":bool(attached_pending.get("ok", false)),"tool":"GitHub Codespaces use","codespace":codespace,"output":"Codespace %s is still %s. Aoi saved its bridge address; wait for GitHub to finish provisioning, then test the connection." % [name, state],"error":str(attached_pending.get("error", ""))}, true)
		return
	var github_token_snapshot := Store.get_secret("github")
	var endpoint := GITHUB_API + "/user/codespaces/" + name.uri_encode() + "/start"
	var callback := func(result: int, code: int, body: PackedByteArray) -> void:
		if Store.get_secret("github") != github_token_snapshot or not is_github_connected():
			_finish({"ok":false,"tool":"GitHub Codespaces use","error":"The GitHub account changed while Aoi was starting the workspace. Verify the current account and refresh Codespaces."}, true)
			return
		var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
		if result != HTTPRequest.RESULT_SUCCESS or code not in [200, 304]:
			var detail := str(payload.get("message", "")) if payload is Dictionary else ""
			var message := "GitHub could not start this Codespace (HTTP %d). %s" % [code, detail.left(180)]
			if code == 403:
				message = "GitHub denied the start request. Add repository permission Codespaces lifecycle admin = Read and write to this fine-grained token, then reconnect GitHub. " + detail.left(140)
			elif code == 402:
				message = "GitHub could not resume this Codespace because its compute or billing allowance is unavailable. Check your Codespaces usage and billing settings."
			elif code == 409:
				message = "GitHub is already changing this Codespace's state. Refresh existing workspaces and try Use again once its state settles."
			elif code == 404:
				message = "GitHub no longer has this Codespace. Refresh the workspace list and select an existing one."
			elif result != HTTPRequest.RESULT_SUCCESS:
				message = "Aoi could not confirm whether GitHub started this Codespace. Refresh the workspace list before trying again."
			_finish({"ok":false,"tool":"GitHub Codespaces use","error":message}, true)
			return
		var started: Dictionary = codespace.duplicate(true)
		if payload is Dictionary:
			started["state"] = str(payload.get("state", "Available"))
			started["web_url"] = str(payload.get("web_url", started.get("web_url", "")))
		var attached := attach_github_codespace(started)
		if not bool(attached.get("ok", false)):
			_finish({"ok":false,"tool":"GitHub Codespaces use","error":str(attached.get("error", "The Codespace started but could not be selected."))}, true)
			return
		_finish({"ok":true,"tool":"GitHub Codespaces use","codespace":started,"output":"GitHub accepted the start request for %s. Its Linux bridge may take a short time to wake; test the connection after the Codespace reports Available." % name}, true)
	# Starting a stopped Codespace is a billable lifecycle mutation; do not retry automatically.
	_start_request(endpoint, HTTPClient.METHOD_POST, _github_headers(), "", 45.0, callback, "GitHub Codespaces use", true, false)


func attach_github_codespace(codespace: Dictionary) -> Dictionary:
	var name := str(codespace.get("name", "")).strip_edges()
	if name == "": return {"ok":false,"error":"Choose a valid Codespace first."}
	var web_url := str(codespace.get("web_url", ""))
	if web_url == "": return {"ok":false,"error":"GitHub did not provide a Codespace URL."}
	var bridge_url := "https://%s-8765.app.github.dev" % name
	var cloud_cfg := Store.get_integration("linux_bridge")
	cloud_cfg["url"] = bridge_url
	cloud_cfg["target"] = "codespaces"
	cloud_cfg["provider"] = "github_codespaces"
	cloud_cfg["last_test_ok"] = false
	cloud_cfg["last_test_at"] = 0
	cloud_cfg["last_test_error"] = "Selected Codespace has not been tested from this device."
	cloud_cfg["tested_url"] = ""
	cloud_cfg["tested_token_sha256"] = ""
	cloud_cfg["godot_available"] = false
	cloud_cfg["godot_version"] = ""
	cloud_cfg["isolated_execution"] = false
	cloud_cfg["codespace_name"] = name
	cloud_cfg["codespace_web_url"] = web_url
	cloud_cfg["codespace_state"] = str(codespace.get("state", "Unknown"))
	cloud_cfg["repository"] = str(codespace.get("repository", ""))
	cloud_cfg["ref"] = str(codespace.get("ref", ""))
	Store.set_integration("linux_bridge", cloud_cfg)
	var saved := Store.get_integration("github_codespaces")
	saved["last_created"] = {"name":name,"repository":str(codespace.get("repository", "")),"state":str(codespace.get("state", "Unknown")),"web_url":web_url,"bridge_url":bridge_url,"ref":str(codespace.get("ref", ""))}
	Store.set_integration("github_codespaces", saved)
	return {"ok":true,"bridge_url":bridge_url,"web_url":web_url,"name":name}


func _create_github_branch(repository: String, branch: String, source_branch: String, manual: bool) -> void:
	var normalized := _normalize_repository(repository)
	if normalized == "" or branch.length() < 2 or branch.length() > 100 or branch.contains(" ") or branch.contains(".."):
		_finish({"ok":false,"tool":"GitHub create branch","error":"Provide owner/repository and a valid branch name."}, manual); return
	if not _require_verified_github("GitHub branch creation", manual): return
	if source_branch == "": source_branch = "HEAD"
	var ref_url := GITHUB_API + "/repos/" + normalized + "/git/ref/heads/" + source_branch.uri_encode()
	var get_ref := func(result: int, code: int, body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_finish({"ok":false,"tool":"GitHub create branch","error":"Could not resolve source branch. " + _github_error(result, code, body)}, manual); return
		var obj: Variant = JSON.parse_string(body.get_string_from_utf8())
		var sha := str(obj.get("object", {}).get("sha", "")) if obj is Dictionary and obj.get("object") is Dictionary else ""
		if sha == "":
			_finish({"ok":false,"tool":"GitHub create branch","error":"GitHub did not provide a source commit SHA."}, manual); return
		var payload := JSON.stringify({"ref":"refs/heads/" + branch,"sha":sha})
		var create_cb := func(r: int, c: int, b: PackedByteArray):
			if r == HTTPRequest.RESULT_SUCCESS and c >= 200 and c < 300:
				_finish({"ok":true,"tool":"GitHub create branch","output":"Created branch %s in %s from %s." % [branch, normalized, source_branch],"error":""}, manual)
			else: _finish({"ok":false,"tool":"GitHub create branch","error":_github_error(r, c, b)}, manual)
		_start_request(GITHUB_API + "/repos/" + normalized + "/git/refs", HTTPClient.METHOD_POST, _github_headers() + PackedStringArray(["Content-Type: application/json"]), payload, 35.0, create_cb, "GitHub create branch", manual)
	_start_request(ref_url, HTTPClient.METHOD_GET, _github_headers(), "", 30.0, get_ref, "GitHub source branch", manual)

func _write_github_file(repository: String, path: String, content: String, message: String, branch: String, sha: String, manual: bool) -> void:
	if branch.strip_edges() == "" or branch.to_lower() in ["main", "master"]:
		_finish({"ok":false,"tool":"GitHub write file","error":"Aoi only writes to a named topic branch. Create a feature branch first; writes to main/master are blocked."}, manual); return
	var normalized := _normalize_repository(repository)
	var clean_path := path.strip_edges().trim_prefix("/")
	if normalized == "" or clean_path == "" or clean_path.contains("..") or clean_path.contains("\\") or clean_path.length() > 240 or content.length() > 100000:
		_finish({"ok":false,"tool":"GitHub write file","error":"Provide a safe repository path and file content up to 100 KB."}, manual); return
	if not _require_verified_github("GitHub file write", manual): return
	var segments: Array[String] = []
	for segment in clean_path.split("/", false): segments.append(segment.uri_encode())
	var payload := {"message": message.left(200), "content": Marshalls.raw_to_base64(content.to_utf8_buffer())}
	if branch != "": payload["branch"] = branch
	if sha != "": payload["sha"] = sha
	var cb := func(result: int, code: int, body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			_finish({"ok":false,"tool":"GitHub write file","error":_github_error(result, code, body) + (" If this is an existing file, read it first and pass its SHA." if code == 422 and sha == "" else "")}, manual); return
		var obj: Variant = JSON.parse_string(body.get_string_from_utf8())
		var commit: Dictionary = obj.get("commit", {}) if obj is Dictionary and obj.get("commit") is Dictionary else {}
		_finish({"ok":true,"tool":"GitHub write file","output":"Committed %s to %s. Commit: %s\n%s" % [clean_path, normalized, str(commit.get("sha", "")), str(commit.get("html_url", ""))],"error":""}, manual)
	_start_request(GITHUB_API + "/repos/" + normalized + "/contents/" + "/".join(segments), HTTPClient.METHOD_PUT, _github_headers() + PackedStringArray(["Content-Type: application/json"]), JSON.stringify(payload), 45.0, cb, "GitHub write file", manual)

func _create_github_issue(repository: String, title: String, body_text: String, manual: bool) -> void:
	var normalized := _normalize_repository(repository)
	if normalized == "" or title == "" or title.length() > 240:
		_finish({"ok":false,"tool":"GitHub create issue","error":"Provide owner/repository and an issue title up to 240 characters."}, manual); return
	if not _require_verified_github("GitHub issue creation", manual): return
	var cb := func(result: int, code: int, body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			_finish({"ok":false,"tool":"GitHub create issue","error":_github_error(result, code, body)}, manual); return
		var obj: Variant = JSON.parse_string(body.get_string_from_utf8())
		_finish({"ok":true,"tool":"GitHub create issue","output":"Created issue #%s: %s\n%s" % [str(obj.get("number", "")), str(obj.get("title", title)), str(obj.get("html_url", ""))],"error":""}, manual)
	_start_request(GITHUB_API + "/repos/" + normalized + "/issues", HTTPClient.METHOD_POST, _github_headers() + PackedStringArray(["Content-Type: application/json"]), JSON.stringify({"title":title,"body":body_text.left(60000)}), 40.0, cb, "GitHub create issue", manual)

func _create_github_pull_request(repository: String, head: String, base: String, title: String, body_text: String, manual: bool) -> void:
	var normalized := _normalize_repository(repository)
	if normalized == "" or head == "" or base == "" or title.strip_edges() == "":
		_finish({"ok":false,"tool":"GitHub create pull request","error":"Provide repository, head branch, base branch and title."}, manual); return
	if not _require_verified_github("GitHub pull request", manual): return
	var cb := func(result: int, code: int, body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			_finish({"ok":false,"tool":"GitHub create pull request","error":_github_error(result, code, body)}, manual); return
		var obj: Variant = JSON.parse_string(body.get_string_from_utf8())
		_finish({"ok":true,"tool":"GitHub create pull request","output":"Opened PR #%s: %s\n%s" % [str(obj.get("number", "")), str(obj.get("title", title)), str(obj.get("html_url", ""))],"error":""}, manual)
	_start_request(GITHUB_API + "/repos/" + normalized + "/pulls", HTTPClient.METHOD_POST, _github_headers() + PackedStringArray(["Content-Type: application/json"]), JSON.stringify({"head":head,"base":base,"title":title,"body":body_text.left(60000)}), 40.0, cb, "GitHub create pull request", manual)

func _search_saved_projects(query: String) -> void:
	var clean_query := query.strip_edges().to_lower()
	if clean_query == "" or clean_query.length() > 160:
		_finish({"ok":false, "tool":"Saved project search", "error":"Provide a project name or a short search phrase (up to 160 characters)."}, false)
		return
	var tokens: Array[String] = []
	for raw_token in clean_query.split(" "):
		var token := raw_token.strip_edges()
		if token.length() >= 2 and token not in tokens: tokens.append(token)
	var ranked: Array[Dictionary] = []
	for item in Store.list_projects():
		if not item is Dictionary: continue
		var haystack := (str(item.get("title", "")) + " " + str(item.get("goal", "")) + " " + str(item.get("notes", ""))).to_lower()
		var task_names := ""
		var tasks: Variant = item.get("tasks", [])
		if tasks is Array:
			for task in tasks:
				if task is Dictionary: task_names += " " + str(task.get("text", task.get("title", "")))
				else: task_names += " " + str(task)
		haystack += " " + task_names.to_lower()
		var score := 0
		for token in tokens:
			if str(item.get("title", "")).to_lower().contains(token): score += 5
			if str(item.get("goal", "")).to_lower().contains(token): score += 3
			if haystack.contains(token): score += 1
		if score > 0: ranked.append({"item":item, "score":score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.score) != int(b.score): return int(a.score) > int(b.score)
		return float(a.item.get("updated", 0)) > float(b.item.get("updated", 0)))
	var lines: Array[String] = []
	for row in ranked.slice(0, mini(ranked.size(), 8)):
		var item: Dictionary = row.item
		lines.append("- %s (project_id: %s)\n  Goal: %s" % [str(item.get("title", "Untitled project")), str(item.get("id", "")), str(item.get("goal", "No goal recorded.")).left(420)])
	var output := "No matching projects were found in Aoi's saved project list on this device. This search does not cover the phone's general storage, cloud drives or an unconnected computer. Search the personal Knowledge Library and any explicitly connected workspace separately before concluding the project is unavailable." if lines.is_empty() else "Matching Aoi-managed projects on this device:\n" + "\n".join(lines) + "\n\nSearch scope: Aoi's own saved project records only; not the entire phone filesystem or cloud storage."
	_finish({"ok":true, "tool":"Saved project search", "output":output, "error":""}, false)


func _search_global_knowledge(query: String) -> void:
	if query.strip_edges() == "":
		_finish({"ok":false,"tool":"Knowledge search","error":"Provide a search query."}, false)
		return
	var matches := Store.retrieve_knowledge(query, 8)
	var lines: Array[String] = []
	for item in matches:
		lines.append("[%s] %s\n%s" % [str(item.get("title", "Note")), ", ".join(PackedStringArray(item.get("tags", []))), str(item.get("content", "")).left(1800)])
	_finish({"ok":true,"tool":"Personal knowledge search","output":"No saved personal knowledge matched that query." if lines.is_empty() else "Relevant personal knowledge:\n" + "\n\n".join(lines),"error":""}, false)


func _save_global_knowledge(title: String, content: String, tags: Variant) -> void:
	var tag_array: Array = tags if tags is Array else []
	var saved := Store.add_knowledge(title, content, tag_array, "assistant")
	if saved.is_empty():
		_finish({"ok":false,"tool":"Personal knowledge","error":"Provide a title and content for the note."}, false)
		return
	_finish({"ok":true,"tool":"Personal knowledge","output":"Saved ‘%s’ to the personal Knowledge Library. It can now be retrieved in relevant future chats." % title.left(120),"error":""}, false)


func _search_project_knowledge(project_id: String, query: String) -> void:
	if project_id == "" or query.strip_edges() == "":
		_finish({"ok":false,"tool":"Project knowledge search","error":"This tool needs an active project and a search query."}, false)
		return
	var matches := AgentFlow.search_knowledge(project_id, query, 8)
	var lines: Array[String] = []
	for item in matches: lines.append("[%s] %s" % [str(item.get("type", "note")), str(item.get("text", ""))])
	_finish({"ok":true,"tool":"Project knowledge search","output":"No saved project knowledge matched that query." if lines.is_empty() else "Saved project knowledge:\n" + "\n\n".join(lines),"error":""}, false)


func _capture_project_decision(project_id: String, decision: String) -> void:
	if project_id == "" or decision.strip_edges() == "" or decision.length() > 1200:
		_finish({"ok":false,"tool":"Capture project decision","error":"Provide an active project and a decision up to 1,200 characters."}, false)
		return
	AgentFlow.add_decision(project_id, decision)
	_finish({"ok":true,"tool":"Capture project decision","output":"Saved this decision to the project's shared memory: " + decision.left(500),"error":""}, false)


func _save_project_knowledge(project_id: String, title: String, content: String, tags: Variant) -> void:
	var tag_array: Array = tags if tags is Array else []
	if not AgentFlow.add_knowledge(project_id, title, content, tag_array):
		_finish({"ok":false,"tool":"Project knowledge","error":"Provide an active project, title and content."}, false)
		return
	_finish({"ok":true,"tool":"Project knowledge","output":"Saved ‘%s’ to project knowledge. Future project runs can retrieve it." % title.left(120),"error":""}, false)


func _save_project_playbook(project_id: String, title: String, trigger: String, steps: String) -> void:
	if not AgentFlow.add_playbook(project_id, title, trigger, steps):
		_finish({"ok":false,"tool":"Project playbook","error":"Provide an active project, a title and ordered procedure steps."}, false)
		return
	_finish({"ok":true,"tool":"Project playbook","output":"Saved playbook ‘%s’. It will be included in future relevant project context and knowledge searches." % title.left(120),"error":""}, false)


func _linux_request(operation: String, payload: Dictionary, manual: bool) -> void:
	var cfg := Store.get_integration("linux_bridge")
	var base := str(cfg.get("url", "")).strip_edges().trim_suffix("/")
	var token := Store.get_secret("linux_bridge")
	if not is_linux_connected():
		_finish({"ok":false,"tool":"Linux environment","error":"Test and connect the saved cloud Linux workspace in Connections before using workspace tools."}, manual); return
	if operation == "exec":
		var command := str(payload.get("command", ""))
		if command.strip_edges() == "" or command.length() > 5000:
			_finish({"ok":false,"tool":"Linux command","error":"Command must be 1–5000 characters."}, manual); return
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json", "X-Aoi-Token: " + token, "User-Agent: AoiMobile/3.2.14"])
	var title := "Linux " + operation
	var cb := func(result: int, code: int, body: PackedByteArray):
		var current_cfg := Store.get_integration("linux_bridge")
		if str(current_cfg.get("url", "")).strip_edges().trim_suffix("/") != base or Store.get_secret("linux_bridge") != token:
			_finish({"ok":false,"tool":title,"error":"The cloud connection changed while this request was running. Retry after testing the new workspace."}, manual)
			return
		var obj: Variant = JSON.parse_string(body.get_string_from_utf8())
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300 or not obj is Dictionary:
			var error_text := "Linux bridge request failed (HTTP %d)." % code
			if obj is Dictionary: error_text = str(obj.get("error", error_text))
			if result != HTTPRequest.RESULT_SUCCESS or code in [401, 404, 502, 503, 504]:
				_mark_linux_disconnected(base, token, error_text)
			_finish({"ok":false,"tool":title,"error":error_text}, manual); return
		var output := ""
		if operation == "exec":
			output = str(obj.get("stdout", ""))
			if str(obj.get("stderr", "")) != "": output += ("\n" if output != "" else "") + "STDERR:\n" + str(obj.get("stderr", ""))
			if int(obj.get("exit_code", 0)) != 0: output += "\nExit code: %d" % int(obj.get("exit_code", 0))
			output += "\nDuration: %d ms" % int(obj.get("duration_ms", 0))
		elif operation == "list":
			var rows: Array[String] = []
			for entry in obj.get("items", []): rows.append(("[dir] " if str(entry.get("type", "")) == "directory" else "[file] ") + str(entry.get("name", "")))
			output = "Workspace: %s\n%s" % [str(obj.get("path", ".")), "\n".join(rows)]
		elif operation == "read": output = str(obj.get("path", "")) + "\n" + str(obj.get("content", ""))
		elif operation == "write": output = "Wrote %d bytes to %s" % [int(obj.get("bytes", 0)), str(obj.get("path", ""))]
		elif operation == "search": output = "Matching files:\n" + "\n".join(obj.get("matches", []))
		var ok := bool(obj.get("ok", true)) and (operation != "exec" or int(obj.get("exit_code", 0)) == 0)
		_finish({"ok":ok,"tool":title,"output":output.left(MAX_TOOL_OUTPUT_CHARS),"error":"Command returned non-zero exit code." if not ok and operation == "exec" else ""}, manual)
	_start_request(base + "/v1/" + operation, HTTPClient.METHOD_POST, headers, JSON.stringify(payload), 70.0, cb, title, manual)

static func _is_safe_godot_project_path(path: String) -> bool:
	var value := path.strip_edges()
	if value == "" or value.length() > 900 or value.begins_with("/") or "\\" in value or ":" in value:
		return false
	for segment in value.split("/"):
		if segment == ".." or segment == "" or segment == ".": return false
	return true


func _godot_request(operation: String, payload: Dictionary, manual: bool) -> void:
	var project_path := str(payload.get("path", "")).strip_edges()
	if not _is_safe_godot_project_path(project_path):
		_finish({"ok":false,"tool":"Godot " + operation,"error":"A valid project path inside the cloud workspace is required."}, manual)
		return
	var cfg := Store.get_integration("linux_bridge")
	var base := str(cfg.get("url", "")).strip_edges().trim_suffix("/")
	var token := Store.get_secret("linux_bridge")
	if not is_linux_connected():
		_finish({"ok":false,"tool":"Godot " + operation,"error":"Test and connect the saved cloud Linux workspace before using Godot runtime tools."}, manual)
		return
	if not bool(cfg.get("godot_available", false)):
		_finish({"ok":false,"tool":"Godot " + operation,"error":"The cloud workspace is connected, but its Godot installation is not ready. Rebuild the Codespace setup, then test the connection again."}, manual)
		return
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json", "X-Aoi-Token: " + token, "User-Agent: " + GITHUB_USER_AGENT])
	var title := "Godot " + operation
	var timeout := 25.0
	if operation == "test": timeout = 185.0
	var callback := func(result: int, code: int, body: PackedByteArray) -> void:
		var current_cfg := Store.get_integration("linux_bridge")
		if str(current_cfg.get("url", "")).strip_edges().trim_suffix("/") != base or Store.get_secret("linux_bridge") != token:
			_finish({"ok":false,"tool":title,"error":"The cloud connection changed while this Godot request was running. Retry after testing the new workspace."}, manual)
			return
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300 or not parsed is Dictionary:
			var message := "Godot bridge request failed (HTTP %d)." % code
			if parsed is Dictionary: message = str(parsed.get("error", message))
			if result != HTTPRequest.RESULT_SUCCESS or code in [401, 404, 502, 503, 504]:
				_mark_linux_disconnected(base, token, message)
			_finish({"ok":false,"tool":title,"error":message.left(900)}, manual)
			return
		var response: Dictionary = parsed
		var output := ""
		var extra: Dictionary = {}
		match operation:
			"run":
				output = "Godot project is running in the cloud workspace.\nProcess ID: %s\nProject: %s" % [str(response.get("pid", "unknown")), str(response.get("path", project_path))]
			"stop": output = str(response.get("message", "Godot project stopped."))
			"status": output = "Godot project is running in the cloud workspace." if bool(response.get("running", false)) else "The Godot project is not currently running in the cloud workspace."
			"test":
				output = str(response.get("output", "No test output returned."))
				output += "\nExit code: %s" % str(response.get("exit_code", "?"))
				extra["exit_code"] = int(response.get("exit_code", -1))
				extra["test_kind"] = str(response.get("test_kind", "Godot verification"))
			"logs": output = str(response.get("logs", "No Godot logs returned."))
			"capture":
				output = "Captured the cloud workspace display for visual review."
				extra["runtime_running"] = bool(response.get("running", false))
				extra["runtime_pid"] = int(response.get("pid", 0))
				var encoded := str(response.get("image_base64", ""))
				if encoded == "":
					_finish({"ok":false,"tool":title,"error":"The bridge saved the screenshot but did not return image data. Check that the capture backend is installed."}, manual)
					return
				var image_bytes := Marshalls.base64_to_raw(encoded)
				if image_bytes.size() < 64 or image_bytes.size() > 2 * 1024 * 1024:
					_finish({"ok":false,"tool":title,"error":"Screenshot data is empty or exceeds the 2 MB mobile preview limit."}, manual)
					return
				var image := Image.new()
				if image.load_png_from_buffer(image_bytes) != OK or image.get_width() > 4096 or image.get_height() > 4096:
					_finish({"ok":false,"tool":title,"error":"The bridge returned an invalid or oversized PNG screenshot."}, manual)
					return
				var image_path := "user://studio_captures/capture_%d_%d.png" % [int(Time.get_unix_time_from_system()), int(Time.get_ticks_usec() % 1000000)]
				if not Store.write_bytes_atomic(image_path, image_bytes):
					_finish({"ok":false,"tool":title,"error":"Could not save the screenshot to Aoi's local gallery."}, manual)
					return
				extra["image_path"] = image_path
		var ok := bool(response.get("ok", true))
		if operation == "run":
			ok = bool(response.get("running", false))
			extra["runtime_running"] = ok
			extra["runtime_pid"] = int(response.get("pid", 0))
		if operation == "stop":
			ok = not bool(response.get("running", false))
			extra["runtime_running"] = not ok
			extra["runtime_pid"] = int(response.get("pid", 0)) if not ok else 0
		if operation == "status":
			ok = bool(response.get("ok", true))
			extra["runtime_running"] = bool(response.get("running", false))
			extra["runtime_pid"] = int(response.get("pid", 0))
		var tool_result := {"ok":ok,"tool":title,"output":output.left(MAX_TOOL_OUTPUT_CHARS),"error":"Godot verification failed with exit code %s." % str(response.get("exit_code", "?")) if not ok and operation == "test" else ""}
		tool_result.merge(extra, true)
		_finish(tool_result, manual)
	_start_request(base + "/v1/godot/" + operation, HTTPClient.METHOD_POST, headers, JSON.stringify(payload), timeout, callback, title, manual)


func _generate_huggingface_image(prompt: String, manual: bool) -> void:
	if prompt == "" or prompt.length() > MAX_PROMPT_CHARS:
		_finish({"ok": false, "tool": "Hugging Face image generation", "error": "Provide an image prompt of 1–%d characters." % MAX_PROMPT_CHARS}, manual)
		return
	var config := Store.get_integration("huggingface")
	var model := str(config.get("model", DEFAULT_IMAGE_MODEL)).strip_edges()
	var matcher := RegEx.new()
	matcher.compile("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
	if matcher.search(model) == null:
		_finish({"ok": false, "tool": "Hugging Face image generation", "error": "The configured image model name is invalid. Reconnect Hugging Face to restore the default model."}, manual)
		return
	var model_parts: PackedStringArray = model.split("/")
	var endpoint := HUGGINGFACE_ROUTER + model_parts[0].uri_encode() + "/" + model_parts[1].uri_encode()
	var payload := {
		"inputs": prompt,
		"parameters": {
			"width": 768,
			"height": 768,
			"num_inference_steps": 24
		}
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: image/png, application/json",
		"Authorization: Bearer " + Store.get_secret("huggingface")
	])
	var handle_response := func(result: int, code: int, body: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			var message := "The image provider could not complete the request. Check your token, model access and available credits."
			var response_text := body.get_string_from_utf8()
			var obj: Variant = JSON.parse_string(response_text)
			if obj is Dictionary:
				message = str(obj.get("error", obj.get("message", message)))
			elif code > 0:
				message += " (HTTP %d)" % code
			_finish({"ok": false, "tool": "Hugging Face image generation", "error": message.left(650)}, manual)
			return
		if body.size() < 100 or body.size() > MAX_IMAGE_BYTES:
			_finish({"ok": false, "tool": "Hugging Face image generation", "error": "The image response was empty or exceeded Aoi's 18 MB safety limit."}, manual)
			return
		var image := Image.new()
		var decode_error := image.load_png_from_buffer(body)
		var extension := "png"
		if decode_error != OK:
			decode_error = image.load_jpg_from_buffer(body)
			extension = "jpg"
		if decode_error != OK:
			_finish({"ok": false, "tool": "Hugging Face image generation", "error": "The provider response was not a supported PNG or JPEG image."}, manual)
			return
		var dimensions := image.get_size()
		if dimensions.x <= 0 or dimensions.y <= 0 or dimensions.x > MAX_IMAGE_DIMENSION or dimensions.y > MAX_IMAGE_DIMENSION:
			_finish({"ok": false, "tool": "Hugging Face image generation", "error": "The generated image dimensions exceed Aoi's safety limit."}, manual)
			return
		var file_name := "aoi_%d_%04x.%s" % [int(Time.get_unix_time_from_system()), randi() & 0xffff, extension]
		var local_path := "user://generated_images/" + file_name
		if not Store.write_bytes_atomic(local_path, body):
			_finish({"ok": false, "tool": "Hugging Face image generation", "error": "Aoi could not save the generated image to local storage."}, manual)
			return
		_finish({
			"ok": true,
			"tool": "Hugging Face image generation",
			"output": "Image generated and saved to Aoi's local image gallery (%d × %d)." % [dimensions.x, dimensions.y],
			"image_path": local_path,
			"error": ""
		}, manual)
	_start_request(endpoint, HTTPClient.METHOD_POST, headers, JSON.stringify(payload), 180.0, handle_response, "Hugging Face image generation", manual)


func _generate_huggingface_video(prompt: String, manual: bool) -> void:
	if prompt == "" or prompt.length() > MAX_PROMPT_CHARS:
		_finish({"ok": false, "tool": "Hugging Face video generation", "error": "Provide a video prompt of 1–%d characters." % MAX_PROMPT_CHARS}, manual)
		return
	if busy:
		_emit_result({"ok": false, "tool": "Hugging Face video generation", "error": "Another tool is already running."}, manual)
		return
	busy = true
	_active_tool = "Hugging Face video generation"
	_active_manual = manual
	_cancel_requested = false
	state_changed.emit("running", "Submitting a short video generation job to Hugging Face / Fal AI…")
	_run_huggingface_video_job(prompt, manual)


func _video_http(url: String, method: int, headers: PackedStringArray, body: String, timeout: float) -> Array:
	var request := HTTPRequest.new()
	request.timeout = timeout
	request.body_size_limit = MAX_VIDEO_BYTES
	request.accept_gzip = true
	_active_request = request
	add_child(request)
	var err := request.request(url, headers, method, body)
	if err != OK:
		if _active_request == request: _active_request = null
		request.queue_free()
		return [HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray()]
	var response: Array = await request.request_completed
	if _active_request == request: _active_request = null
	if is_instance_valid(request): request.queue_free()
	return response


func _run_huggingface_video_job(prompt: String, manual: bool) -> void:
	var token := Store.get_secret("huggingface")
	var headers := PackedStringArray([
		"Authorization: Bearer " + token,
		"Content-Type: application/json",
		"Accept: application/json",
		"User-Agent: AoiMobile/2.4"
	])
	# HF's Fal provider mapping for Wan 2.2. The queue subdomain is required for long-running video jobs.
	var submit_url := "https://router.huggingface.co/fal-ai/fal-ai/wan/v2.2-5b/text-to-video?_subdomain=queue"
	var payload := {"prompt": prompt, "num_frames": 49}
	var submitted: Array = await _video_http(submit_url, HTTPClient.METHOD_POST, headers, JSON.stringify(payload), 180.0)
	if _cancel_requested:
		_finish({"ok": false, "tool": "Video generation cancelled", "error": "The video request was stopped."}, manual)
		return
	if int(submitted[0]) != HTTPRequest.RESULT_SUCCESS or int(submitted[1]) < 200 or int(submitted[1]) >= 300:
		_finish({"ok": false, "tool": "Hugging Face video generation", "error": _video_error(submitted)}, manual)
		return
	var queued: Variant = JSON.parse_string((submitted[3] as PackedByteArray).get_string_from_utf8())
	if not queued is Dictionary:
		_finish({"ok": false, "tool": "Hugging Face video generation", "error": "The video provider returned an unreadable queue response."}, manual)
		return
	var response_url := str(queued.get("response_url", ""))
	var response_path := ""
	if response_url.begins_with("https://queue.fal.run"):
		response_path = response_url.trim_prefix("https://queue.fal.run").split("?", false)[0]
	elif response_url.begins_with("https://router.huggingface.co/fal-ai"):
		response_path = response_url.trim_prefix("https://router.huggingface.co/fal-ai").split("?", false)[0]
	if not response_path.begins_with("/") or response_path.contains(".."):
		_finish({"ok": false, "tool": "Hugging Face video generation", "error": "The video queue returned an invalid job URL."}, manual)
		return
	var router_base := "https://router.huggingface.co/fal-ai"
	var status_url := router_base + response_path + "/status?_subdomain=queue"
	var result_url := router_base + response_path + "?_subdomain=queue"
	var completed := false
	var status_payload: Dictionary = {}
	for poll_index in range(150):
		if _cancel_requested:
			_finish({"ok": false, "tool": "Video generation cancelled", "error": "The video request was stopped."}, manual)
			return
		state_changed.emit("processing", "Video rendering is running in the cloud… (%d/150)" % (poll_index + 1))
		await get_tree().create_timer(2.0).timeout
		if _cancel_requested:
			_finish({"ok": false, "tool": "Video generation cancelled", "error": "The video request was stopped."}, manual)
			return
		var status_response: Array = await _video_http(status_url, HTTPClient.METHOD_GET, PackedStringArray(["Authorization: Bearer " + token, "Accept: application/json"]), "", 45.0)
		if _cancel_requested:
			_finish({"ok": false, "tool": "Video generation cancelled", "error": "The video request was stopped."}, manual)
			return
		if int(status_response[0]) != HTTPRequest.RESULT_SUCCESS or int(status_response[1]) < 200 or int(status_response[1]) >= 300:
			_finish({"ok": false, "tool": "Hugging Face video generation", "error": _video_error(status_response)}, manual)
			return
		var status_variant: Variant = JSON.parse_string((status_response[3] as PackedByteArray).get_string_from_utf8())
		if not status_variant is Dictionary:
			_finish({"ok": false, "tool": "Hugging Face video generation", "error": "The video queue returned an unreadable status."}, manual)
			return
		status_payload = status_variant
		var job_status := str(status_payload.get("status", "")).to_upper()
		if job_status == "COMPLETED":
			completed = true
			break
		if job_status in ["FAILED", "CANCELLED"]:
			_finish({"ok": false, "tool": "Hugging Face video generation", "error": str(status_payload.get("error", "The video provider marked this job as %s." % job_status)).left(650)}, manual)
			return
	if not completed:
		_finish({"ok": false, "tool": "Hugging Face video generation", "error": "The video job did not finish within five minutes. Check provider status and try again."}, manual)
		return
	state_changed.emit("downloading", "Video rendered. Downloading the MP4…")
	var result_response: Array = await _video_http(result_url, HTTPClient.METHOD_GET, PackedStringArray(["Authorization: Bearer " + token, "Accept: application/json"]), "", 60.0)
	if _cancel_requested:
		_finish({"ok": false, "tool": "Video generation cancelled", "error": "The video download was stopped."}, manual)
		return
	if int(result_response[0]) != HTTPRequest.RESULT_SUCCESS or int(result_response[1]) < 200 or int(result_response[1]) >= 300:
		_finish({"ok": false, "tool": "Hugging Face video generation", "error": _video_error(result_response)}, manual)
		return
	var output_payload: Variant = JSON.parse_string((result_response[3] as PackedByteArray).get_string_from_utf8())
	if not output_payload is Dictionary or not output_payload.get("video", {}) is Dictionary:
		_finish({"ok": false, "tool": "Hugging Face video generation", "error": "The completed job did not include a video file."}, manual)
		return
	var video_url := str(output_payload["video"].get("url", ""))
	var video_host := video_url.trim_prefix("https://").get_slice("/", 0).to_lower()
	if not video_url.begins_with("https://") or not (video_host.ends_with(".fal.media") or video_host == "fal.media"):
		_finish({"ok": false, "tool": "Hugging Face video generation", "error": "The provider returned an unsupported video download address."}, manual)
		return
	var video_response: Array = await _video_http(video_url, HTTPClient.METHOD_GET, PackedStringArray(["Accept: video/mp4"]), "", 180.0)
	if _cancel_requested:
		_finish({"ok": false, "tool": "Video generation cancelled", "error": "The video download was stopped."}, manual)
		return
	if int(video_response[0]) != HTTPRequest.RESULT_SUCCESS or int(video_response[1]) < 200 or int(video_response[1]) >= 300:
		_finish({"ok": false, "tool": "Hugging Face video generation", "error": "The rendered MP4 could not be downloaded (HTTP %d)." % int(video_response[1])}, manual)
		return
	var video_bytes: PackedByteArray = video_response[3]
	if video_bytes.size() < 512 or video_bytes.size() > MAX_VIDEO_BYTES or video_bytes.slice(4, 8).get_string_from_ascii() != "ftyp":
		_finish({"ok": false, "tool": "Hugging Face video generation", "error": "The provider response was not a valid MP4 or exceeded Aoi's 100 MB safety limit."}, manual)
		return
	var file_name := "aoi_%d_%04x.mp4" % [int(Time.get_unix_time_from_system()), randi() & 0xffff]
	var local_path := "user://generated_videos/" + file_name
	if not Store.write_bytes_atomic(local_path, video_bytes):
		_finish({"ok": false, "tool": "Hugging Face video generation", "error": "Aoi could not save the generated MP4 to local storage."}, manual)
		return
	_finish({"ok": true, "tool": "Hugging Face video generation", "output": "Video generated and saved locally as MP4 (%d MB)." % int(round(float(video_bytes.size()) / 1048576.0)), "video_path": local_path, "error": ""}, manual)


func _video_error(response: Array) -> String:
	var code := int(response[1])
	var body: PackedByteArray = response[3]
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
		return "The video provider could not be reached. Check your connection and token permission."
	var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
	var message := "The video provider rejected the request (HTTP %d)." % code
	if payload is Dictionary:
		message = str(payload.get("error", payload.get("message", message)))
	return message.left(650)


func _search_wikipedia(query: String, manual: bool) -> void:
	if query == "" or query.length() > 240:
		_finish({"ok": false, "tool": "Wikipedia search", "error": "Provide a search phrase (1–240 characters)."}, manual)
		return
	var url := "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=" + query.uri_encode() + "&format=json&utf8=1&srlimit=5"
	var handler := func(result: int, code: int, body: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_finish({"ok": false, "tool": "Wikipedia search", "error": "Wikipedia could not be reached (HTTP %d)." % code}, manual)
			return
		var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not payload is Dictionary:
			_finish({"ok": false, "tool": "Wikipedia search", "error": "Wikipedia returned an unreadable response."}, manual)
			return
		var query_data: Dictionary = payload.get("query", {})
		var search_rows: Array = query_data.get("search", [])
		var lines: Array[String] = []
		for row in search_rows:
			if not row is Dictionary: continue
			var title := str(row.get("title", ""))
			var snippet := _strip_html(str(row.get("snippet", ""))).strip_edges()
			var encoded_title := title.replace(" ", "_").uri_encode()
			lines.append("%s\n%s\nhttps://en.wikipedia.org/wiki/%s" % [title, snippet, encoded_title])
		var output := "\n\n".join(lines) if not lines.is_empty() else "No Wikipedia articles matched that phrase."
		_finish({"ok": true, "tool": "Wikipedia article search", "output": output.left(MAX_TOOL_OUTPUT_CHARS), "error": ""}, manual)
	_start_request(url, HTTPClient.METHOD_GET, PackedStringArray(["Accept: application/json", "User-Agent: AoiMobile/2.3 (mobile assistant)"]), "", 35.0, handler, "Wikipedia article search", manual)


func _research_web_context(project_id: String, query: String, angle: String) -> void:
	if not Store.has_secret("brave_search"):
		_finish({"ok":false, "tool":"Web research", "error":"Connect Brave Search in Plugins & tools → Research before Aoi can complete the evidence-backed research phase. No research or roadmap has been claimed."}, false)
		return
	var allowed_angles := ["reference_landscape", "player_feedback", "user_needs", "technical_docs", "production_assets"]
	if project_id == "" or query == "" or query.length() > 600 or angle not in allowed_angles:
		_finish({"ok":false, "tool":"Web research", "error":"A project ID, a targeted query of 1–600 characters and one valid research angle are required."}, false)
		return
	var project := Store.get_project(project_id)
	if project.is_empty():
		_finish({"ok":false, "tool":"Web research", "error":"The selected project no longer exists. Research was not saved."}, false)
		return
	var flow := AgentFlow.ensure_flow(project)
	var research: Dictionary = flow.get("research", {})
	if not bool(research.get("required", false)) or str(research.get("status", "")) in ["ready", "legacy"]:
		_finish({"ok":false, "tool":"Web research", "error":"This project is not currently accepting new research queries."}, false)
		return
	AgentFlow.begin_research(project_id)
	var url := "https://api.search.brave.com/res/v1/llm/context?q=" + query.uri_encode() + "&count=12&maximum_number_of_urls=12&maximum_number_of_tokens=4096&maximum_number_of_tokens_per_url=1024&context_threshold_mode=balanced&enable_source_metadata=true&safesearch=moderate"
	var headers := PackedStringArray(["Accept: application/json", "X-Subscription-Token: " + Store.get_secret("brave_search")])
	var handle_response := func(result: int, code: int, body: PackedByteArray) -> void:
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if result != HTTPRequest.RESULT_SUCCESS:
			_finish({"ok":false, "tool":"Web research", "error":"Brave Search could not be reached. Check the connection and try a narrower or different query."}, false)
			return
		if code < 200 or code >= 300:
			var detail := ""
			if parsed is Dictionary:
				var error_value: Variant = parsed.get("error", {})
				if error_value is Dictionary: detail = str(error_value.get("detail", error_value.get("code", "")))
			_finish({"ok":false, "tool":"Web research", "error":"Brave Search returned HTTP %d. %s" % [code, detail.left(300)]}, false)
			return
		if not parsed is Dictionary:
			_finish({"ok":false, "tool":"Web research", "error":"Brave Search returned a response Aoi could not parse."}, false)
			return
		var grounding: Variant = parsed.get("grounding", {})
		var generic: Variant = grounding.get("generic", []) if grounding is Dictionary else []
		if not generic is Array or generic.is_empty():
			_finish({"ok":false, "tool":"Web research", "error":"That query returned no usable extracted sources. Try a more specific query or a different angle."}, false)
			return
		var source_metadata: Variant = parsed.get("sources", {})
		var incoming: Array = []
		for item in generic:
			if not item is Dictionary: continue
			var source_url := str(item.get("url", "")).strip_edges()
			if source_url == "": continue
			var metadata: Dictionary = source_metadata.get(source_url, {}) if source_metadata is Dictionary and source_metadata.get(source_url, {}) is Dictionary else {}
			var snippets: Array = item.get("snippets", []) if item.get("snippets", []) is Array else []
			var hostname := source_url.trim_prefix("https://").trim_prefix("http://").get_slice("/", 0).get_slice(":", 0).trim_prefix("www.")
			incoming.append({"url":source_url, "title":str(item.get("title", metadata.get("site_name", hostname))),
				"hostname":hostname, "site_name":str(metadata.get("site_name", hostname)),
				"fetched_at":str(metadata.get("fetched_content_timestamp", "")), "age":str(metadata.get("age", "")), "snippets":snippets})
		var source_ids: Array = AgentFlow.record_research_sources(project_id, query, incoming, angle)
		if source_ids.is_empty():
			_finish({"ok":false, "tool":"Web research", "error":"The search returned pages, but none could be stored as valid source records. No findings were added to the research ledger."}, false)
			return
		var lines: Array[String] = []
		for entry in incoming:
			var entry_url := str(entry.get("url", ""))
			var source_id := ""
			for stored_id in source_ids:
				# Stable IDs are derived from the URL; read the ledger to avoid trusting model-supplied IDs.
				var saved_flow := AgentFlow.get_flow(project_id)
				for stored_source in saved_flow.get("research", {}).get("sources", []):
					if str(stored_source.get("url", "")) == entry_url: source_id = str(stored_source.get("source_id", ""))
			if source_id == "": continue
			lines.append("SOURCE_ID: %s\nTitle: %s\nDomain: %s\nURL: %s" % [source_id, str(entry.get("title", "Untitled")), str(entry.get("hostname", "")), entry_url])
			var snippet_count := 0
			for snippet in entry.get("snippets", []):
				if snippet_count >= 2: break
				lines.append("Extract: " + str(snippet).left(900))
				snippet_count += 1
		var output := "Research angle: %s\nSearch query: %s\nRetrieved and saved %d source pages. Cite their SOURCE_ID values in the research brief; do not invent citations.\n\n%s" % [angle, query, source_ids.size(), "\n\n".join(lines)]
		_finish({"ok":true, "tool":"Web research", "output":output.left(MAX_TOOL_OUTPUT_CHARS), "source_ids":source_ids, "query":query}, false)
	_start_request(url, HTTPClient.METHOD_GET, headers, "", 30.0, handle_response, "Web research", false)


func _read_wikipedia_page(title: String, manual: bool) -> void:
	if title == "" or title.length() > 220:
		_finish({"ok": false, "tool": "Wikipedia article", "error": "Provide an article title (1–220 characters)."}, manual)
		return
	var url := "https://en.wikipedia.org/w/api.php?action=query&prop=extracts&explaintext=1&exchars=5200&titles=" + title.uri_encode() + "&format=json&redirects=1"
	var handler := func(result: int, code: int, body: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_finish({"ok": false, "tool": "Wikipedia article", "error": "Wikipedia could not retrieve that article (HTTP %d)." % code}, manual)
			return
		var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not payload is Dictionary:
			_finish({"ok": false, "tool": "Wikipedia article", "error": "Wikipedia returned an unreadable response."}, manual)
			return
		var query_data: Dictionary = payload.get("query", {})
		var pages: Dictionary = query_data.get("pages", {})
		for page_value in pages.values():
			if not page_value is Dictionary: continue
			var extract := str(page_value.get("extract", "")).strip_edges()
			if extract == "":
				_finish({"ok": false, "tool": "Wikipedia article", "error": "No article extract was available for that title."}, manual)
				return
			var resolved_title := str(page_value.get("title", title))
			_finish({"ok": true, "tool": "Wikipedia article: " + resolved_title, "output": extract.left(MAX_TOOL_OUTPUT_CHARS) + "\n\nSource: https://en.wikipedia.org/wiki/" + resolved_title.replace(" ", "_"), "error": ""}, manual)
			return
		_finish({"ok": false, "tool": "Wikipedia article", "error": "No article was returned."}, manual)
	_start_request(url, HTTPClient.METHOD_GET, PackedStringArray(["Accept: application/json", "User-Agent: AoiMobile/2.3 (mobile assistant)"]), "", 35.0, handler, "Wikipedia article", manual)


func _strip_html(value: String) -> String:
	var expression := RegEx.new()
	expression.compile("<[^>]*>")
	var plain := expression.sub(value, " ", true)
	plain = plain.replace("&quot;", "\"").replace("&#039;", "'").replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
	return plain


func _normalize_repository(value: String) -> String:
	var clean := value.strip_edges().trim_suffix("/").trim_suffix(".git")
	clean = clean.trim_prefix("https://github.com/").trim_prefix("http://github.com/")
	var matcher := RegEx.new()
	matcher.compile("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
	if matcher.search(clean) == null: return ""
	return clean


func _github_error(result: int, code: int, body: PackedByteArray) -> String:
	if result != HTTPRequest.RESULT_SUCCESS:
		return "GitHub could not be reached. Check your connection and try again."
	var message := ""
	var obj: Variant = JSON.parse_string(body.get_string_from_utf8())
	if obj is Dictionary: message = str(obj.get("message", ""))
	if code == 401: return "GitHub rejected the token. Reconnect with a valid fine-grained token."
	if code == 403: return "GitHub denied the request or its API rate limit was reached. A fine-grained token can increase the public API quota. " + message.left(200)
	if code == 404: return "GitHub could not find that repository or file, or the token cannot access it."
	return "GitHub request failed (HTTP %d). %s" % [code, message.left(250)]


func _is_valid_http_base(value: String) -> bool:
	var clean := value.strip_edges()
	if clean == "" or clean.contains("?") or clean.contains("#") or clean.contains("@") or clean.contains(" "):
		return false
	var matcher := RegEx.new()
	matcher.compile("^https?://([A-Za-z0-9.-]+)(?::([0-9]{1,5}))?(/[A-Za-z0-9._~!$&'()*+,;=:@%/-]*)?$")
	var found := matcher.search(clean)
	if found == null:
		return false
	var host := found.get_string(1).to_lower()
	# Reject unresolved placeholders and reserved examples from older setup screens.
	if host in ["192.168.1.x", "example", "example.com", "your-host", "your-pc"] or host.contains("your-pc") or host.ends_with(".example.com"):
		return false
	# A numeric host must be a real IPv4 address, not merely four numeric-looking labels.
	var numeric_host := RegEx.new()
	numeric_host.compile("^[0-9.]+$")
	if numeric_host.search(host) != null:
		var octets := host.split(".")
		if octets.size() != 4:
			return false
		for octet in octets:
			if octet == "" or octet.length() > 3:
				return false
			var octet_value := int(octet)
			if octet_value < 0 or octet_value > 255 or str(octet_value) != octet:
				return false
	var port_text := found.get_string(2)
	if port_text != "":
		var port := int(port_text)
		if port < 1 or port > 65535:
			return false
	return true


func _start_request(url: String, method: int, headers: PackedStringArray, body: String, timeout: float, callback: Callable, tool_name: String, manual: bool, retryable: bool = true) -> void:
	if busy:
		_emit_result({"ok": false, "tool": tool_name, "error": "Another tool is already running."}, manual)
		return
	busy = true
	_active_tool = tool_name
	_active_manual = manual
	_cancel_requested = false
	state_changed.emit("running", tool_name)
	_perform_request(url, method, headers, body, timeout, callback, retryable)


func _perform_request(url: String, method: int, headers: PackedStringArray, body: String, timeout: float, callback: Callable, retryable: bool = true) -> void:
	var final_result := HTTPRequest.RESULT_REQUEST_FAILED
	var final_code := 0
	var final_body := PackedByteArray()
	for attempt in range(3):
		if _cancel_requested: break
		var request := HTTPRequest.new()
		request.timeout = timeout
		request.accept_gzip = true
		request.body_size_limit = 3 * 1024 * 1024 # Bounded room for a 2 MB screenshot encoded as JSON/base64.
		_active_request = request
		add_child(request)
		var request_error := request.request(url, headers, method, body)
		if request_error != OK:
			final_result = HTTPRequest.RESULT_REQUEST_FAILED
			final_code = 0
			final_body = PackedByteArray()
			_active_request = null
			request.queue_free()
		else:
			var response: Array = await request.request_completed
			final_result = int(response[0])
			final_code = int(response[1])
			final_body = response[3]
			if _active_request == request: _active_request = null
			if is_instance_valid(request): request.queue_free()
		if _cancel_requested: break
		# Retrying an HTTP mutation after a timeout can duplicate a remote side
		# effect (create a Codespace/issue/branch, launch a process, or write a
		# project). Automatic retries are therefore limited to safe read requests.
		var request_is_read_only := method in [HTTPClient.METHOD_GET, HTTPClient.METHOD_HEAD]
		if retryable and request_is_read_only and attempt < 2 and _should_retry(final_result, final_code):
			state_changed.emit("retrying", "Attempt %d/3 failed; retrying %s after a temporary network or server error…" % [attempt + 1, _active_tool])
			await get_tree().create_timer(0.8 * pow(2.0, attempt)).timeout
			continue
		break
	var completed_tool_name := _active_tool
	busy = false
	_active_tool = ""
	_active_request = null
	if _cancel_requested:
		# A cancellation cannot roll back a POST already sent to GitHub. If a
		# Codespaces create was in flight, require a fresh server-side list before
		# enabling Create again. The server may have provisioned it already.
		if method == HTTPClient.METHOD_POST and completed_tool_name == "GitHub Codespaces create":
			var codespace_cfg := Store.get_integration("github_codespaces")
			_mark_github_codespace_creation_uncertain(str(codespace_cfg.get("repository", "")), str(codespace_cfg.get("ref", "")), "The create request was cancelled after it was sent; GitHub may still have provisioned the workspace.")
		_cancel_requested = false
		var cancelled_result := {"ok": false, "tool": "Request cancelled", "error": "The request was stopped."}
		state_changed.emit("cancelled", "Request cancelled")
		_emit_result(cancelled_result, _active_manual)
		return
	callback.call(final_result, final_code, final_body)


func _should_retry(result: int, code: int) -> bool:
	if result != HTTPRequest.RESULT_SUCCESS: return true
	return code in [408, 425, 429, 500, 502, 503, 504]


func _finish(result: Dictionary, manual: bool) -> void:
	busy = false
	_active_job_id = ""
	_active_tool = ""
	_cancel_requested = false
	state_changed.emit("success" if bool(result.get("ok", false)) else "error", str(result.get("tool", "Tool")))
	_emit_result(result, manual)


func _emit_result(result: Dictionary, manual: bool) -> void:
	if manual:
		manual_completed.emit(result)
	else:
		completed.emit(result)
