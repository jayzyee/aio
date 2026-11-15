extends Node

var _failures := 0

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Store.set_root("user://aoi_persistence_recovery_probe/")
	var project := Store.new_project("Recovery workspace", "Keep the last good project record available during interrupted saves.")
	Store.save_project(project)
	var project_id := str(project.get("id", ""))
	var data_path := Store._p("projects/%s.json" % project_id)
	var original_text := FileAccess.get_file_as_string(data_path)
	_check("project is saved as readable structured data", not original_text.is_empty() and Store.get_project(project_id).get("title") == "Recovery workspace")
	var flow := AgentFlow.ensure_flow(project)
	var flow_path := AgentFlow._path(project_id)
	flow["summary"] = "First durable workflow checkpoint."
	AgentFlow.save_flow(flow)
	flow["summary"] = "Latest workflow checkpoint."
	AgentFlow.save_flow(flow)
	var broken_flow := FileAccess.open(flow_path, FileAccess.WRITE)
	broken_flow.store_string("{ interrupted workflow write")
	broken_flow.close()
	var recovered_flow := AgentFlow.get_flow(project_id)
	_check("workflow corruption recovers its last complete checkpoint", str(recovered_flow.get("summary", "")) == "First durable workflow checkpoint." and FileAccess.file_exists(flow_path + ".corrupt"))
	AgentFlow.delete_flow(project_id)
	_check("deleting a workflow removes its recovery backup", AgentFlow.get_flow(project_id).is_empty() and not FileAccess.file_exists(flow_path + ".bak"))

	# Reproduce process interruption after moving the previous record to its backup.
	var backup_path := data_path + ".bak"
	var moved := DirAccess.rename_absolute(data_path, backup_path) == OK
	var after_interruption := Store.get_project(project_id)
	_check("interrupted replacement restores the previous project automatically", moved and str(after_interruption.get("title", "")) == "Recovery workspace" and FileAccess.file_exists(data_path))

	# Reproduce a damaged primary while a last-known-good backup is available.
	var backup_file := FileAccess.open(backup_path, FileAccess.WRITE)
	backup_file.store_string(original_text)
	backup_file.close()
	var damaged_file := FileAccess.open(data_path, FileAccess.WRITE)
	damaged_file.store_string("{ this is an interrupted JSON write")
	damaged_file.close()
	var recovered := Store.get_project(project_id)
	_check("corrupt primary is quarantined and recovered from the last good copy", str(recovered.get("title", "")) == "Recovery workspace" and FileAccess.file_exists(data_path + ".corrupt"))

	# Verify the replacement path and settings/credential persistence still work.
	project["goal"] = "Updated after recovery."
	Store.save_project(project)
	_check("a successful save retains the previous known-good project snapshot", FileAccess.file_exists(data_path + ".bak"))
	var broken_latest := FileAccess.open(data_path, FileAccess.WRITE)
	broken_latest.store_string("{ truncated after the most recent save")
	broken_latest.close()
	var last_good := Store.get_project(project_id)
	_check("a later corrupt save recovers the previous complete snapshot", str(last_good.get("title", "")) == "Recovery workspace" and str(last_good.get("goal", "")) != "Updated after recovery.")
	project["goal"] = "Updated after recovery."
	Store.save_project(project)
	Store.set_integration("workspace", {"working_preferences":"Previous global preference"})
	Store.set_integration("workspace", {"working_preferences":"Recovery probe preference"})
	var settings_path := Store._p("settings.cfg")
	_check("settings retain a last-known-good snapshot after saving", FileAccess.file_exists(settings_path + ".bak"))
	var damaged_settings := FileAccess.open(settings_path, FileAccess.WRITE)
	damaged_settings.store_string("[broken settings")
	damaged_settings.close()
	Store.load_all()
	_check("corrupt settings recover from the last known-good configuration", str(Store.get_integration("workspace").get("working_preferences", "")) == "Previous global preference")
	Store.set_integration("workspace", {"working_preferences":"Recovery probe preference"})

	Store.set_key("google_ai", "previous-probe-key")
	Store.set_key("google_ai", "recovery-probe-key")
	var keys_path := Store._p("keys.dat")
	_check("encrypted credentials retain a last-known-good snapshot", FileAccess.file_exists(keys_path + ".bak"))
	var damaged_keys := FileAccess.open(keys_path, FileAccess.WRITE)
	damaged_keys.store_string("damaged encrypted payload")
	damaged_keys.close()
	Store.load_all()
	_check("corrupt encrypted credentials recover without losing the previous key", Store.get_key("google_ai") == "previous-probe-key")
	Store.set_key("google_ai", "recovery-probe-key")
	Store.load_all()
	_check("project updates remain writable after recovery", str(Store.get_project(project_id).get("goal", "")) == "Updated after recovery.")
	_check("workspace settings survive an app-data reload", str(Store.get_integration("workspace").get("working_preferences", "")) == "Recovery probe preference")
	_check("encrypted provider credentials survive an app-data reload", Store.get_key("google_ai") == "recovery-probe-key")
	Store.delete_project(project_id)
	_check("deleting a project also removes recovery data and cannot resurrect it", Store.get_project(project_id).is_empty())

	_finish()


func _check(label: String, condition: bool) -> void:
	if condition: print("PERSISTENCE_BEHAVIOR_OK ", label)
	else:
		_failures += 1
		push_error("PERSISTENCE_BEHAVIOR_FAIL " + label)


func _finish() -> void:
	print("PERSISTENCE_BEHAVIOR_RESULT ", "OK" if _failures == 0 else "FAILED", " failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
