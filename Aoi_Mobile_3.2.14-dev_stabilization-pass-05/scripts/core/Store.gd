extends Node
## All persistence, on the phone only: settings, API keys (encrypted), chat sessions, projects.
## Keys never leave the device except in requests to the provider you chose.

signal changed

var root := "user://"
var provider := ""        # selected provider id
var model := ""           # selected model, visible id "provider/model"
var mode := "chat"
var status: Dictionary = {}     # provider id -> {models_count, checked_at}
var integrations: Dictionary = {} # non-secret connection metadata/settings
var _keys: Dictionary = {}


func _ready() -> void:
	load_all()


func set_root(path: String) -> void:   # tests use an isolated folder
	root = path if path.ends_with("/") else path + "/"
	DirAccess.make_dir_recursive_absolute(root)
	load_all()


func _p(name: String) -> String:
	return root + name


func load_all() -> void:
	provider = ""
	model = ""
	mode = "chat"
	status = {}
	integrations = {}
	DirAccess.make_dir_recursive_absolute(_p("sessions"))
	DirAccess.make_dir_recursive_absolute(_p("projects"))
	DirAccess.make_dir_recursive_absolute(_p("knowledge"))
	var settings_path := _p("settings.cfg")
	_restore_backup_file(settings_path)
	var cf := ConfigFile.new()
	var settings_error := cf.load(settings_path)
	if settings_error != OK and FileAccess.file_exists(settings_path + ".bak"):
		_quarantine_file(settings_path)
		_restore_backup_file(settings_path)
		cf = ConfigFile.new()
		settings_error = cf.load(settings_path)
	if settings_error == OK:
		provider = str(cf.get_value("app", "provider", ""))
		model = str(cf.get_value("app", "model", ""))
		mode = str(cf.get_value("app", "mode", "chat"))
		var st: Variant = cf.get_value("app", "status", {})
		status = st if st is Dictionary else {}
		var saved_integrations: Variant = cf.get_value("app", "integrations", {})
		integrations = saved_integrations if saved_integrations is Dictionary else {}
	_keys = {}
	var keys_path := _p("keys.dat")
	_restore_backup_file(keys_path)
	if FileAccess.file_exists(keys_path):
		var password := _password()
		if password == "":
			push_error("Aoi could not unlock saved credentials. The encrypted credential file was preserved.")
			return
		var kf := ConfigFile.new()
		var keys_error := kf.load_encrypted_pass(keys_path, password)
		if keys_error != OK and FileAccess.file_exists(keys_path + ".bak"):
			_quarantine_file(keys_path)
			_restore_backup_file(keys_path)
			kf = ConfigFile.new()
			keys_error = kf.load_encrypted_pass(keys_path, password)
		if keys_error == OK:
			for k in kf.get_section_keys("keys"): _keys[k] = str(kf.get_value("keys", k, ""))
		else:
			push_error("Aoi could not decrypt saved credentials (error %d). The credential file was preserved." % keys_error)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("app", "provider", provider)
	cf.set_value("app", "model", model)
	cf.set_value("app", "mode", mode)
	cf.set_value("app", "status", status)
	cf.set_value("app", "integrations", integrations)
	var settings_path := _p("settings.cfg")
	var temporary_path := settings_path + ".tmp"
	var save_error := cf.save(temporary_path)
	if save_error != OK:
		push_error("Aoi could not write settings. Existing settings were preserved. Error %d" % save_error)
	else:
		_commit_temp_file(temporary_path, settings_path)
	changed.emit()



func workspace_autonomy_mode() -> String:
	var workspace := get_integration("workspace")
	var value := str(workspace.get("autonomy_mode", "workspace"))
	return value if value in ["workspace", "confirm"] else "workspace"


func set_workspace_autonomy_mode(value: String) -> void:
	if value not in ["workspace", "confirm"]:
		return
	var workspace := get_integration("workspace")
	workspace["autonomy_mode"] = value
	set_integration("workspace", workspace)

# ------------------------------------------------------------------- keys
func _password() -> String:
	# Obfuscates the key file against casual reads (backups, file managers). It is not protection against a rooted phone.
	var seed_path := _p("device.seed")
	var seed_text := ""
	if FileAccess.file_exists(seed_path):
		seed_text = FileAccess.get_file_as_string(seed_path).strip_edges()
	if seed_text == "":
		var c := Crypto.new()
		seed_text = c.generate_random_bytes(24).hex_encode()
		var f := FileAccess.open(seed_path, FileAccess.WRITE)
		if f == null:
			push_error("Aoi could not create the credential encryption seed. Existing credentials were preserved.")
			return ""
		f.store_string(seed_text)
		f.flush()
		var seed_error := f.get_error()
		f.close()
		if seed_error != OK:
			DirAccess.remove_absolute(seed_path)
			push_error("Aoi could not safely save the credential encryption seed. Credentials were not written.")
			return ""
	return "aoi-mobile|" + seed_text + "|" + OS.get_unique_id()


func get_key(pid: String) -> String:
	return str(_keys.get(pid, ""))


func has_key(pid: String) -> bool:
	return get_key(pid) != ""


func set_key(pid: String, key: String) -> void:
	_keys[pid] = key.strip_edges()
	_save_keys()


func remove_key(pid: String) -> void:
	_keys.erase(pid)
	status.erase(pid)
	_save_keys()
	save_settings()


func get_secret(id: String) -> String:
	return str(_keys.get("integration." + id, ""))


func has_secret(id: String) -> bool:
	return get_secret(id) != ""


func set_secret(id: String, value: String) -> void:
	var key := "integration." + id
	if value.strip_edges() == "":
		_keys.erase(key)
	else:
		_keys[key] = value.strip_edges()
	_save_keys()


func remove_secret(id: String) -> void:
	_keys.erase("integration." + id)
	_save_keys()


func get_integration(id: String) -> Dictionary:
	var value: Variant = integrations.get(id, {})
	return value if value is Dictionary else {}


func set_integration(id: String, value: Dictionary) -> void:
	integrations[id] = value.duplicate(true)
	save_settings()



func _save_keys() -> void:
	# ConfigFile cannot encrypt an empty configuration reliably. Remove the empty
	# credential file instead of asking the engine to serialize a blank resource.
	if _keys.is_empty():
		for path in [_p("keys.dat"), _p("keys.dat.bak"), _p("keys.dat.tmp")]:
			if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
		changed.emit()
		return
	var kf := ConfigFile.new()
	for k in _keys: kf.set_value("keys", k, _keys[k])
	var destination := _p("keys.dat")
	var temporary := destination + ".tmp"
	var password := _password()
	if password == "":
		push_error("Aoi did not save credentials because their encryption key is not durable.")
		return
	var error := kf.save_encrypted_pass(temporary, password)
	if error != OK:
		if FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)
		push_error("Aoi could not write encrypted credentials. The previous key file was preserved. Error %d" % error)
	else:
		_commit_temp_file(temporary, destination)
	changed.emit()


func connected_providers() -> Array:
	var out: Array = []
	var provider_ids := ["google_ai", "puter", "openrouter", "groq"]
	if not get_integration("custom_provider").is_empty():
		provider_ids.append("custom")
	if OS.get_environment("AOI_TEMPORAL_PROVIDER") == "1":
		provider_ids.append("temporal")
	for p in provider_ids:
		if has_key(p) and int((status.get(p, {}) as Dictionary).get("models_count", 0)) > 0: out.append(p)
	return out


# ----------------------------------------------------------------- helpers
func new_id() -> String:
	return "%d_%04x" % [int(Time.get_unix_time_from_system()), randi() & 0xffff]


func _write_json(path: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_error("Aoi could not open a temporary data file. Existing data was preserved: " + path)
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		push_error("Aoi could not flush a data file. Existing data was preserved: " + path)
		return false
	return _commit_temp_file(temporary, path)


func write_json_atomic(path: String, data: Dictionary) -> bool:
	return _write_json(path, data)


func read_json_recovering(path: String) -> Dictionary:
	return _read_json(path)


func write_text_atomic(path: String, content: String, preserve_backup: bool = false) -> bool:
	return write_bytes_atomic(path, content.to_utf8_buffer(), preserve_backup)


func write_bytes_atomic(path: String, bytes: PackedByteArray, preserve_backup: bool = false) -> bool:
	var parent := path.get_base_dir()
	var parent_error := DirAccess.make_dir_recursive_absolute(parent)
	if parent_error != OK and not DirAccess.dir_exists_absolute(parent):
		push_error("Aoi could not create a destination folder. Existing data was preserved: " + path)
		return false
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_error("Aoi could not open a temporary file. Existing data was preserved: " + path)
		return false
	file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		push_error("Aoi could not flush a temporary file. Existing data was preserved: " + path)
		return false
	if not _commit_temp_file(temporary, path):
		return false
	var backup := path + ".bak"
	if not preserve_backup and FileAccess.file_exists(backup):
		var cleanup_error := DirAccess.remove_absolute(backup)
		if cleanup_error != OK:
			push_warning("Aoi saved the project file but could not remove its temporary recovery copy: " + backup)
	return true


func _commit_temp_file(temporary: String, destination: String) -> bool:
	# Keep the previous version until the replacement is safely in place. If the
	# process stops between the two renames, _restore_backup_file() recovers it.
	if not FileAccess.file_exists(temporary):
		push_error("Aoi could not commit a missing temporary file: " + temporary)
		return false
	_restore_backup_file(destination)
	var backup := destination + ".bak"
	var had_previous := FileAccess.file_exists(destination)
	if had_previous:
		if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
		var backup_error := DirAccess.rename_absolute(destination, backup)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			push_error("Aoi could not preserve the previous file before saving. Error %d" % backup_error)
			return false
	var commit_error := DirAccess.rename_absolute(temporary, destination)
	if commit_error != OK:
		if had_previous and FileAccess.file_exists(backup):
			var restore_error := DirAccess.rename_absolute(backup, destination)
			if restore_error != OK: push_error("Aoi could not restore its previous data file. Backup remains at: " + backup)
		DirAccess.remove_absolute(temporary)
		push_error("Aoi could not replace a data file. Error %d" % commit_error)
		return false
	# Keep the previous complete file as the last-known-good recovery point.
	# The next commit rotates it only after a newer destination is fully written.
	return true


func _remove_persisted_file(path: String) -> void:
	# Remove all transaction sidecars too; otherwise a later load could resurrect
	# a deliberately deleted record from its recovery backup.
	for candidate in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(candidate):
			var error := DirAccess.remove_absolute(candidate)
			if error != OK:
				push_error("Aoi could not remove a deleted record sidecar: %s (error %d)" % [candidate, error])


func _restore_backup_file(path: String) -> bool:
	if FileAccess.file_exists(path): return true
	var backup := path + ".bak"
	if not FileAccess.file_exists(backup): return false
	var error := DirAccess.rename_absolute(backup, path)
	if error != OK:
		push_error("Aoi found a recoverable backup but could not restore it: " + backup)
		return false
	return true


func _quarantine_file(path: String) -> void:
	if not FileAccess.file_exists(path): return
	var corrupt := path + ".corrupt"
	if FileAccess.file_exists(corrupt): corrupt += ".%d" % int(Time.get_unix_time_from_system())
	var error := DirAccess.rename_absolute(path, corrupt)
	if error != OK: push_error("Aoi could not preserve a damaged file for inspection: " + path)


func _read_json(path: String) -> Dictionary:
	_restore_backup_file(path)
	if not FileAccess.file_exists(path): return {}
	var json_text := FileAccess.get_file_as_string(path)
	var parsed := JSON.new()
	if parsed.parse(json_text) == OK and parsed.data is Dictionary:
		return parsed.data
	# A malformed primary is quarantined, then the last known-good backup is
	# restored instead of returning an empty object and silently losing the item.
	_quarantine_file(path)
	if _restore_backup_file(path):
		var recovered := JSON.new()
		if recovered.parse(FileAccess.get_file_as_string(path)) == OK and recovered.data is Dictionary:
			return recovered.data
		push_error("Aoi's last known-good backup is also invalid: " + path)
	return {}


func _list(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(_p(dir))
	if d == null: return out
	for f in d.get_files():
		if f.ends_with(".json"):
			var obj := _read_json(_p(dir + "/" + f))
			if not obj.is_empty(): out.append(obj)
	out.sort_custom(func(a, b): return float(a.get("updated", 0)) > float(b.get("updated", 0)))
	return out


# ---------------------------------------------------------------- sessions
func new_session(session_mode: String = "", project_id: String = "") -> Dictionary:
	var now := Time.get_unix_time_from_system()
	return {"id": new_id(), "title": "New chat", "created": now, "updated": now, "mode": session_mode if session_mode != "" else mode,
		"model": model, "project_id": project_id, "messages": []}


func title_from(text: String) -> String:
	var t := text.strip_edges().replace("\n", " ")
	return t.left(42) + ("…" if t.length() > 42 else "") if t != "" else "New chat"


func save_session(s: Dictionary, force: bool = false) -> void:
	if (s.get("messages", []) as Array).is_empty() and not force: return   # empty casual chats are not written
	s["updated"] = Time.get_unix_time_from_system()
	_write_json(_p("sessions/%s.json" % str(s["id"])), s)
	changed.emit()


func load_session(id: String) -> Dictionary:
	return _read_json(_p("sessions/%s.json" % id))


func list_sessions() -> Array:
	var sessions := _list("sessions")
	sessions.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_pinned := bool(a.get("pinned", false))
		var b_pinned := bool(b.get("pinned", false))
		if a_pinned != b_pinned: return a_pinned
		return float(a.get("updated", 0)) > float(b.get("updated", 0)))
	return sessions


func rename_session(id: String, title: String) -> bool:
	return _update_session_metadata(id, {"title":title})


func set_session_pinned(id: String, pinned: bool) -> bool:
	return _update_session_metadata(id, {"pinned":pinned})


func _update_session_metadata(id: String, updates: Dictionary) -> bool:
	var session := load_session(id)
	if session.is_empty():
		push_warning("Aoi could not update a conversation that no longer exists: " + id)
		return false
	for key in updates:
		session[key] = updates[key]
	if not _write_json(_p("sessions/%s.json" % id), session): return false
	changed.emit()
	return true


func delete_session(id: String) -> void:
	_remove_persisted_file(_p("sessions/%s.json" % id))
	changed.emit()


# ---------------------------------------------------------------- projects
func new_project(title: String, goal: String = "") -> Dictionary:
	var now := Time.get_unix_time_from_system()
	var p := {"id": new_id(), "title": title.strip_edges() if title.strip_edges() != "" else "Untitled project", "goal": goal.strip_edges(),
		"notes": "", "tasks": [], "created": now, "updated": now}
	return p if save_project(p) else {}


func save_project(p: Dictionary) -> bool:
	var previous_updated: Variant = p.get("updated", null)
	p["updated"] = Time.get_unix_time_from_system()
	if not _write_json(_p("projects/%s.json" % str(p.get("id", ""))), p):
		if previous_updated == null:
			p.erase("updated")
		else:
			p["updated"] = previous_updated
		return false
	changed.emit()
	return true


func get_project(id: String) -> Dictionary:
	return _read_json(_p("projects/%s.json" % id))


func list_projects() -> Array:
	return _list("projects")


func delete_project(id: String) -> void:
	_remove_persisted_file(_p("projects/%s.json" % id))
	AgentFlow.delete_flow(id)
	changed.emit()


func add_task(p: Dictionary, text: String) -> void:
	text = text.strip_edges()
	if text == "": return
	for t in p["tasks"]: if str(t.get("text", "")) == text: return   # no duplicates
	(p["tasks"] as Array).append({"text": text, "done": false})


# ---------------------------------------------------------------- knowledge library
func add_knowledge(title: String, content: String, tags: Array = [], source: String = "manual") -> Dictionary:
	var clean_title := title.strip_edges().left(120)
	var clean_content := content.strip_edges().left(16000)
	if clean_title == "" or clean_content == "": return {}
	var clean_tags: Array[String] = []
	for tag in tags:
		var value := str(tag).strip_edges().left(32)
		if value != "" and value not in clean_tags: clean_tags.append(value)
	var item := {"id": new_id(), "title": clean_title, "content": clean_content, "tags": clean_tags,
		"source": source.left(40), "pinned": false, "created": Time.get_unix_time_from_system(), "updated": Time.get_unix_time_from_system()}
	_write_json(_p("knowledge/%s.json" % str(item.id)), item)
	changed.emit()
	return item


func update_knowledge(item: Dictionary) -> bool:
	var item_id := str(item.get("id", "")).validate_filename()
	if item_id == "" or not FileAccess.file_exists(_p("knowledge/%s.json" % item_id)): return false
	if str(item.get("title", "")).strip_edges() == "" or str(item.get("content", "")).strip_edges() == "": return false
	item["title"] = str(item.title).strip_edges().left(120)
	item["content"] = str(item.content).strip_edges().left(16000)
	item["updated"] = Time.get_unix_time_from_system()
	var ok := _write_json(_p("knowledge/%s.json" % item_id), item)
	if ok: changed.emit()
	return ok


func get_knowledge(item_id: String) -> Dictionary:
	return _read_json(_p("knowledge/%s.json" % item_id.validate_filename()))


func list_knowledge() -> Array:
	return _list("knowledge")


func delete_knowledge(item_id: String) -> void:
	var safe_id := item_id.validate_filename()
	if safe_id == "": return
	var path := _p("knowledge/%s.json" % safe_id)
	if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak"):
		_remove_persisted_file(path)
		changed.emit()


func search_knowledge(query: String, limit: int = 60) -> Array:
	var tokens: Array[String] = []
	for raw_token in query.strip_edges().to_lower().split(" "):
		var token := ""
		for c in raw_token:
			if c.is_valid_identifier() or c.is_valid_int(): token += c
		if token.length() >= 2 and token not in tokens: tokens.append(token)
	var ranked: Array = []
	for item in list_knowledge():
		var title := str(item.get("title", "")).to_lower()
		var content := str(item.get("content", "")).to_lower()
		var tags := ""
		for tag in item.get("tags", []): tags += " " + str(tag).to_lower()
		var score := 0
		for token in tokens:
			if title.contains(token): score += 4
			if tags.contains(token): score += 3
			if content.contains(token): score += 1
		if tokens.is_empty() or score > 0: ranked.append({"item": item, "score": score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.score) != int(b.score): return int(a.score) > int(b.score)
		if bool(a.item.get("pinned", false)) != bool(b.item.get("pinned", false)): return bool(a.item.get("pinned", false))
		return float(a.item.get("updated", 0)) > float(b.item.get("updated", 0)))
	var out: Array = []
	for row in ranked.slice(0, mini(ranked.size(), maxi(1, limit))): out.append(row.item)
	return out


func retrieve_knowledge(query: String, limit: int = 5) -> Array:
	var tokens: Array[String] = []
	var stopwords := ["the", "and", "for", "with", "from", "that", "this", "what", "when", "where", "how", "can", "could", "would", "should", "about", "into", "your", "you", "are", "was", "were", "have", "has", "had", "its", "but", "not", "use", "using"]
	for raw_token in query.to_lower().split(" "):
		var token := ""
		for c in raw_token:
			if c.is_valid_identifier() or c.is_valid_int(): token += c
		if token.length() >= 3 and token not in stopwords and token not in tokens: tokens.append(token)
	if tokens.is_empty(): return []
	var ranked: Array = []
	for item in list_knowledge():
		var title := str(item.get("title", "")).to_lower()
		var content := str(item.get("content", "")).to_lower()
		var tags := ""
		for tag in item.get("tags", []): tags += " " + str(tag).to_lower()
		var score := 0
		for token in tokens:
			if title.contains(token): score += 5
			if tags.contains(token): score += 4
			if content.contains(token): score += 1
		if score > 0: ranked.append({"item": item, "score": score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.score) != int(b.score): return int(a.score) > int(b.score)
		if bool(a.item.get("pinned", false)) != bool(b.item.get("pinned", false)): return bool(a.item.get("pinned", false))
		return float(a.item.get("updated", 0)) > float(b.item.get("updated", 0)))
	var out: Array = []
	for row in ranked.slice(0, mini(ranked.size(), maxi(1, limit))): out.append(row.item)
	return out


## Save an AI answer into a project: appended to the notes, and any "- [ ]" items become tasks.
func save_to_project(p: Dictionary, heading: String, markdown: String, md_helper) -> int:
	var previous := p.duplicate(true)
	var stamp := Time.get_datetime_string_from_system().replace("T", " ").left(16)
	var block := "## %s · %s\n%s\n" % [heading, stamp, markdown.strip_edges()]
	p["notes"] = (str(p.get("notes", "")).strip_edges() + "\n\n" + block).strip_edges()
	var before := (p["tasks"] as Array).size()
	for item in md_helper.checklist_items(markdown): add_task(p, str(item))
	if not save_project(p):
		p.clear()
		p.merge(previous, true)
		return -1
	return (p["tasks"] as Array).size() - before


func wipe_all() -> void:
	# Generated media is user data too; remove it alongside chats, projects and credentials.
	for dir in ["sessions", "projects", "knowledge", "workflows", "generated_images", "generated_videos"]:
		var d := DirAccess.open(_p(dir))
		if d != null:
			for file_name in d.get_files():
				DirAccess.remove_absolute(_p(dir + "/" + file_name))
	for file_name in ["settings.cfg", "keys.dat", "device.seed"]:
		_remove_persisted_file(_p(file_name))
	_keys = {}
	status = {}
	integrations = {}
	provider = ""
	model = ""
	mode = "chat"
	changed.emit()
