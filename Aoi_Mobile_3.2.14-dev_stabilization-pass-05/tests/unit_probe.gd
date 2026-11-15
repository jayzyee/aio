extends Node
# Pure-logic tests: SSE parsing, markdown, catalog/model normalisation, grouping, encrypted storage, sessions, projects.
const Sse = preload("res://scripts/core/Sse.gd")
const Md = preload("res://scripts/core/Md.gd")
const Catalog = preload("res://scripts/core/Catalog.gd")
const MG = preload("res://scripts/core/ModelGroups.gd")
const AoiPresence = preload("res://scripts/ui/AoiPresence.gd")
const AoiSignalField = preload("res://scripts/ui/AoiSignalField.gd")
const AoiProgressRail = preload("res://scripts/ui/AoiProgressRail.gd")
const StudioScreen = preload("res://scripts/ui/StudioScreen.gd")
var results: Array = []

func _ready() -> void:
	_check("AOI_presence_maps_real_research_events", AoiPresence.resolve_state("running", "Searching official documentation") == "researching")
	_check("AOI_presence_maps_file_mutations_to_writing", AoiPresence.resolve_state("running", "Writing project files") == "writing")
	_check("AOI_presence_distinguishes_planning_from_creation", AoiPresence.resolve_state("planning", "") == "planning" and AoiPresence.resolve_state("running", "Rendering visual assets") == "creating")
	_check("AOI_presence_stops_on_pause_and_approval", AoiPresence.resolve_state("cancelled", "") == "paused" and AoiPresence.resolve_state("waiting", "") == "waiting")
	_check("AOI_presence_distinguishes_retry_error_and_completion", AoiPresence.resolve_state("retrying", "") == "retrying" and AoiPresence.resolve_state("error", "") == "error" and AoiPresence.resolve_state("ready", "") == "complete")
	_check("AOI_presence_activity_details_map_to_appropriate_motion", AoiPresence.resolve_state("running", "Reading the existing project") == "thinking" and AoiPresence.resolve_state("running", "Running Godot tests") == "checking" and AoiPresence.resolve_state("running", "Finishing final touches") == "finishing")
	var presence_probe := AoiPresence.new()
	presence_probe.custom_minimum_size = Vector2(72, 72)
	add_child(presence_probe)
	presence_probe.set_state("researching", "Searching references")
	await get_tree().process_frame
	var active_presence_animates := presence_probe.is_processing()
	presence_probe.set_state("paused", "The task is paused")
	await get_tree().create_timer(0.65).timeout
	var paused_presence_settles := not presence_probe.is_processing()
	presence_probe.set_reduced_motion(true)
	presence_probe.set_state("creating", "Building the scene")
	await get_tree().process_frame
	var reduced_motion_is_respected := not presence_probe.is_processing()
	_check("AOI_presence_motion_tracks_active_paused_and_reduced_motion", active_presence_animates and paused_presence_settles and reduced_motion_is_respected)
	presence_probe.queue_free()
	var signal_probe := AoiSignalField.new()
	add_child(signal_probe)
	await get_tree().process_frame
	var visible_signal_animates := signal_probe.is_processing()
	signal_probe.hide()
	await get_tree().process_frame
	var hidden_signal_stops := not signal_probe.is_processing()
	signal_probe.show()
	await get_tree().process_frame
	var visible_signal_resumes := signal_probe.is_processing()
	signal_probe._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await get_tree().process_frame
	var suspended_signal_stops := not signal_probe.is_processing()
	signal_probe._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await get_tree().process_frame
	var resumed_signal_animates := signal_probe.is_processing()
	_check("AOI_signal_field_pauses_for_hidden_views_and_app_focus", visible_signal_animates and hidden_signal_stops and visible_signal_resumes and suspended_signal_stops and resumed_signal_animates)
	signal_probe.queue_free()
	var rail_probe := AoiProgressRail.new()
	add_child(rail_probe)
	await get_tree().process_frame
	var visible_rail_animates := rail_probe.is_processing()
	rail_probe.hide()
	await get_tree().process_frame
	var hidden_rail_stops := not rail_probe.is_processing()
	rail_probe.show()
	await get_tree().process_frame
	var visible_rail_resumes := rail_probe.is_processing()
	rail_probe._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await get_tree().process_frame
	var suspended_rail_stops := not rail_probe.is_processing()
	rail_probe._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await get_tree().process_frame
	var resumed_rail_animates := rail_probe.is_processing()
	_check("AOI_progress_rail_pauses_for_hidden_views_and_app_focus", visible_rail_animates and hidden_rail_stops and visible_rail_resumes and suspended_rail_stops and resumed_rail_animates)
	rail_probe.queue_free()
	var small_source_request := StudioScreen._source_upload_request("main.gd", "project/sources/main.gd", "extends Node\n".to_utf8_buffer())
	var oversized_text_bytes := PackedByteArray()
	oversized_text_bytes.resize(StudioScreen.REMOTE_TEXT_FILE_LIMIT + 1)
	oversized_text_bytes.fill(65)
	var oversized_source_request := StudioScreen._source_upload_request("notes.txt", "project/sources/notes.txt", oversized_text_bytes)
	var invalid_utf8_bytes := PackedByteArray([0xC3, 0x28])
	var binary_text_request := StudioScreen._source_upload_request("data.json", "project/sources/data.json", invalid_utf8_bytes)
	var empty_source_request := StudioScreen._source_upload_request("empty.png", "project/sources/empty.png", PackedByteArray())
	_check("STUDIO_source_import_preserves_text_limits_invalid_utf8_and_empty_files",
		small_source_request.route == "/v1/write"
		and oversized_source_request.route == "/v1/upload"
		and Marshalls.base64_to_raw(str(oversized_source_request.payload.data)) == oversized_text_bytes
		and binary_text_request.route == "/v1/upload"
		and Marshalls.base64_to_raw(str(binary_text_request.payload.data)) == invalid_utf8_bytes
		and empty_source_request.route == "/v1/write" and str(empty_source_request.payload.content) == "")
	var data := ("data: {\"d\":\"naïve 日本語 🙂\"}\n\ndata: [DONE]\n\n").to_utf8_buffer()
	var s := Sse.new()
	var got: Array = []
	for i in range(0, data.size(), 2): got.append_array(s.feed(data.slice(i, i + 2)))
	_check("SSE_split_bytes", got.size() == 2 and JSON.parse_string(str(got[0]))["d"] == "naïve 日本語 🙂" and got[1] == "[DONE]")
	var s2 := Sse.new()
	_check("SSE_crlf_comments_flush", s2.feed("data: a\r\n: ping\r\nevent: x\r\ndata: b\r\n".to_utf8_buffer()) == ["a", "b"] and s2.feed("data: tail".to_utf8_buffer()) == [] and s2.flush() == ["tail"])
	_check("MD_bold_italic_code", Md.inline("**b** and *i* and `c`") == "[b][color=#171717]b[/color][/b] and [i][color=#555555]i[/color][/i] and [bgcolor=#f2f2f2][color=#343434][code]c[/code][/color][/bgcolor]")
	_check("MD_bracket_escape", Md.to_bbcode("array[0] is [tag]") == "array[lb]0] is [lb]tag]" and not "[[" in Md.to_bbcode("[x] [y]"))
	_check("MD_link", Md.inline("see [docs](https://a.b/c)") == "see [url=https://a.b/c][color=#242424][u]docs[/u][/color][/url]")
	_check("MD_plain_text_formats_spoken_replies", Md.to_plain_text("# Overview\nSee **Aoi** and [docs](https://a.example).\n- [x] Ready\n```gdscript\nvar x = 1\n```") == "Overview\nSee Aoi and docs.\nReady\nCode block omitted.")
	var fenced := Md.to_bbcode("```gdscript\nvar a = [1]\n```\nafter")
	_check("MD_fence_literal", fenced.begins_with("[color=#343434][font_size=21][code]") and "var a = [lb]1]" in fenced and "[/code][/font_size][/color]" in fenced and fenced.ends_with("after"))
	_check("MD_lists_headings", Md.to_bbcode("# T\n- one\n1. two\n- [ ] task\n- [x] done") == "[font_size=34][b][color=#111111]T[/color][/b][/font_size]\n[color=#888888]•[/color]  one\n1. two\n[color=#888888]◯[/color]  task\n[color=#548b79]✓[/color]  done")
	_check("MD_checklist_items", Md.checklist_items("x\n- [ ] Buy domain\n- [x] done\n* [ ] Post offer") == ["Buy domain", "Post offer"])
	_check("MD_snake_case_not_italic", Md.inline("use my_var_name here") == "use my_var_name here")
	var table_render := Md.to_bbcode("| Feature | Detail | Status |\n| :--- | --- | :---: |\n| Keyboard | Composer stays visible | Fixed |\n| Tables | No raw pipes | In review |")
	_check("MD_tables_render_as_phone_friendly_labelled_rows", "[b][color=#171717]Keyboard[/color][/b]" in table_render and "[color=#777777]Status:[/color] Fixed" in table_render and not "|" in table_render)
	var escaped_table := Md.to_bbcode("| Name | Value |\n| --- | --- |\n| Pipe | a\\|b |")
	_check("MD_table_escaped_pipe_is_preserved_as_content", "a|b" in escaped_table and not "| Name" in escaped_table)
	var g := Catalog.normalize_models("google_ai", {"data": [{"id": "models/gemini-2.5-flash", "inputTokenLimit": 1048576}, {"id": "models/text-embedding-004"}, {"id": "models/imagen-3.0"}]})
	_check("CAT_google_filters_nonchat", g.size() == 1 and g[0]["id"] == "google_ai/gemini-2.5-flash" and g[0]["free"] == true)
	var o := Catalog.normalize_models("openrouter", {"data": [{"id": "a/b:free", "context_length": 10}, {"id": "openai/gpt-4o", "pricing": {"prompt": "0.1", "completion": "0.2"}}, {"id": "z/zero", "pricing": {"prompt": "0", "completion": "0"}}]})
	var free_map := {}
	for r in o: free_map[r["model"]] = r["free"]
	_check("CAT_openrouter_free_detection", free_map == {"a/b:free": true, "openai/gpt-4o": false, "z/zero": true})
	var puter_models := Catalog.normalize_models("puter", {"models": [
		{"id":"gpt-5.4-nano", "puterId":"azure:openai/gpt-5.4-nano", "name":null, "context":400000,
			"costs_currency":"usd-cents", "costs":{"tokens":1000000, "prompt_tokens":20, "completion_tokens":125}},
		{"id":"meta-llama/llama-3.3-free", "puterId":"meta-llama:meta-llama/llama-3.3-free", "name":"Llama Free", "context":100000,
			"costs_currency":"usd-cents", "costs":{"tokens":1000000, "prompt_tokens":0, "completion_tokens":0}},
		{"id":"openai/embed", "puterId":"openai:openai/embed", "name":"Embedding", "context":1000}]})
	var puter_default := Catalog.default_model("puter", puter_models)
	var puter_paid_default := Catalog.default_model("puter", [puter_models[0]])
	var puter_groups := MG.group([puter_models[0]["id"]], {puter_models[0]["id"]:{"provider":"puter", "label":puter_models[0]["label"], "free":puter_models[0]["free"], "cost_label":puter_models[0]["cost_label"]}})
	var puter_base_override := OS.get_environment("AOI_MOBILE_BASE_PUTER").rstrip("/")
	var expected_puter_models_url := puter_base_override + "/models" if puter_base_override != "" else "https://api.puter.com/puterai/chat/models/details"
	var puter_catalog_ok: bool = puter_models.size() == 2 and puter_models[0]["id"] == "puter/azure:openai/gpt-5.4-nano" and puter_models[0]["label"] == "gpt-5.4-nano" and not puter_models[0]["free"] and puter_models[0]["cost_label"].contains("$0.20") and puter_models[1]["free"] and puter_default == puter_models[1]["id"] and puter_paid_default == puter_models[0]["id"] and Catalog.models_url("puter") == expected_puter_models_url
	_check("CAT_puter_details_normalize_canonical_ids_null_names_costs_and_defaults", puter_catalog_ok,
		{"models":puter_models, "default":puter_default, "expected_url":expected_puter_models_url, "actual_url":Catalog.models_url("puter")})
	_check("MG_puter_label_and_price_are_preserved", puter_groups.size() == 1 and puter_groups[0]["name"] == "Puter AI" and puter_groups[0]["items"][0]["cost_label"].contains("$0.20"))
	_check("LLM_puter_errors_explain_token_and_plan_requirements", LLM.explain("puter", 403, "app_or_api_token_required").contains("full-access API token") and LLM.explain("puter", 402, "subscription_required").contains("paid Puter plan"))
	_check("CAT_split_visible", Catalog.split_visible("groq/openai/gpt-oss-20b") == ["groq", "openai/gpt-oss-20b"] and Catalog.split_visible("meta/llama:free") == ["", "meta/llama:free"])
	_check("CAT_custom_endpoint_requires_https_except_loopback", Catalog.is_safe_custom_base_url("https://api.example.com/v1") and Catalog.is_safe_custom_base_url("http://localhost:8199/v1") and Catalog.is_safe_custom_base_url("http://127.0.0.1/v1") and not Catalog.is_safe_custom_base_url("http://api.example.com/v1") and not Catalog.is_safe_custom_base_url("https://user@api.example.com/v1") and not Catalog.is_safe_custom_base_url("https://api.example.com/v1?token=secret") and not Catalog.is_safe_custom_base_url("https://api.example.com:70000/v1"))
	_check("CAT_default_model", Catalog.default_model("google_ai", Catalog.normalize_models("google_ai", {"data": [{"id": "models/gemini-2.5-pro"}, {"id": "models/gemini-2.5-flash"}]})) == "google_ai/gemini-2.5-flash"
		and Catalog.default_model("openrouter", [{"id": "openrouter/x-vl:free", "model": "x-vl:free", "free": true}, {"id": "openrouter/y:free", "model": "y:free", "free": true}]) == "openrouter/y:free")
	_check("CAT_prompts", "income coach" in Catalog.system_prompt("money").to_lower() and "- [ ]" in Catalog.system_prompt("money") and "Builder" in Catalog.system_prompt("build")
		and "non-judgmental" in Catalog.system_prompt("chat") and "end-to-end" in Catalog.system_prompt("build") and "avoid toy-only stubs" in Catalog.system_prompt("build")
		and "CURRENT PROJECT: Shop" in Catalog.system_prompt("chat", {"title": "Shop", "goal": "sell", "notes": "n", "tasks": [{"text": "t1", "done": false}, {"text": "t2", "done": true}]}) and not "t2" in Catalog.system_prompt("chat", {"title": "S", "goal": "g", "tasks": [{"text": "t2", "done": true}]}))
	var rows: Array = []
	for r in Catalog.normalize_models("google_ai", {"data": [{"id": "models/gemini-2.5-flash"}]}): rows.append(r)
	for i in range(150): rows.append({"id": "openrouter/v/m%d:free" % i, "model": "v/m%d:free" % i, "free": true, "provider": "openrouter", "context_length": i, "label": "v/m%d" % i})
	var meta := {}
	var ids: Array = []
	for r in rows: ids.append(r["id"]); meta[r["id"]] = {"provider": r["provider"], "free": r["free"], "label": r["label"]}
	var groups := MG.group(ids, meta, false)
	_check("MG_google_not_crowded_out", groups[0]["provider"] == "google_ai" and groups.size() == 2)
	var root := "user://unit_%d/" % Time.get_ticks_msec()
	Store.set_root(root)
	const ChatVisionTest = preload("res://scripts/ui/ChatScreen.gd")
	var vision_image := Image.create(1600, 900, false, Image.FORMAT_RGBA8)
	vision_image.fill(Color(0.2, 0.4, 0.7, 1.0))
	var vision_source := root + "vision_source.png"
	var vision_saved := vision_image.save_png(vision_source) == OK
	var vision_chat := ChatVisionTest.new()
	var vision_message: Dictionary = vision_chat._build_vision_message("Review this screenshot", vision_source) if vision_saved else {}
	var vision_parts: Array = vision_message.get("content", [])
	var vision_url := str((vision_parts[1] as Dictionary).get("image_url", {}).get("url", "")) if vision_parts.size() == 2 else ""
	var vision_jpeg := Marshalls.base64_to_raw(vision_url.trim_prefix("data:image/jpeg;base64,")) if vision_url.begins_with("data:image/jpeg;base64,") else PackedByteArray()
	var decoded_vision := Image.new()
	var vision_dimensions_ok := decoded_vision.load_jpg_from_buffer(vision_jpeg) == OK and decoded_vision.get_width() == 1024 and decoded_vision.get_height() == 576
	_check("VISION_capture_becomes_bounded_multimodal_chat_message", vision_message.get("role", "") == "user" and vision_parts.size() == 2 and vision_dimensions_ok)
	vision_chat.free()
	Store.remove_key("missing")
	_check("STORE_empty_credentials_do_not_write_invalid_encrypted_file", not FileAccess.file_exists(root + "keys.dat"))
	Store.set_key("openrouter", "sk-or-v1-SUPERSECRET123")
	Store.set_key("puter", "puter-test-token")
	Store.set_secret("github", "ghp-private-test-token")
	Store.set_integration("github", {"login": "aoi-test", "permissions": "metadata:read, contents:read"})
	Store.set_integration("piston", {"url": "https://runner.example.com"})
	Store.set_secret("huggingface", "hf-private-test-token")
	Store.set_integration("huggingface", {"username": "aoi-test", "model": "stabilityai/stable-diffusion-3-medium-diffusers"})
	var raw := FileAccess.get_file_as_bytes(root + "keys.dat")
	_check("STORE_key_not_plaintext_on_disk", raw.size() > 0 and raw.get_string_from_ascii().find("SUPERSECRET") < 0 and raw.get_string_from_utf8().find("SUPERSECRET") < 0)
	Store.provider = "openrouter"; Store.model = "openrouter/a:free"; Store.mode = "money"; Store.status = {"openrouter": {"models_count": 3}, "puter": {"models_count": 2}}
	Store.save_settings()
	Store.load_all()
	_check("STORE_restart_restores_key_and_settings", Store.get_key("openrouter") == "sk-or-v1-SUPERSECRET123" and Store.get_key("puter") == "puter-test-token" and Store.provider == "openrouter" and Store.mode == "money" and Store.connected_providers() == ["puter", "openrouter"])
	_check("STORE_integration_settings_and_secrets_survive_restart", Store.has_secret("github") and Store.get_integration("github").get("login", "") == "aoi-test" and Store.get_integration("piston").get("url", "") == "https://runner.example.com" and Store.has_secret("huggingface") and Store.get_integration("huggingface").get("model", "") == "stabilityai/stable-diffusion-3-medium-diffusers")
	_check("TOOL_repository_validation", ToolRunner._normalize_repository("https://github.com/godotengine/godot.git") == "godotengine/godot" and ToolRunner._normalize_repository("owner/repo/extra") == "")
	_check("TOOL_piston_url_validation", ToolRunner._is_valid_http_base("https://runner.test") and ToolRunner._is_valid_http_base("http://192.168.1.5:2000") and not ToolRunner._is_valid_http_base("https://runner.example.com?token=secret") and not ToolRunner._is_valid_http_base("https://user@runner.example.com"))
	_check("TOOL_godot_project_path_is_workspace_relative", ToolRunner._is_safe_godot_project_path("projects/MyGame") and not ToolRunner._is_safe_godot_project_path("../other-project") and not ToolRunner._is_safe_godot_project_path("/etc") and not ToolRunner._is_safe_godot_project_path("projects\\outside"))
	var api_summary := GodotSandbox.ensure_index()
	_check("GODOT_API_live_class_index", bool(api_summary.get("ok", false)) and int(api_summary.get("count", 0)) > 100 and not GodotSandbox.search_classes("CharacterBody2D", 10).is_empty())
	var body_api := GodotSandbox.inspect_class("CharacterBody2D")
	var body_methods: Array = body_api.get("methods", [])
	var has_move := false
	for method in body_methods:
		if str(method.get("name", "")) == "move_and_slide": has_move = true
	_check("GODOT_API_class_details_include_methods_properties_signals", bool(body_api.get("ok", false)) and has_move and body_api.get("properties", []).any(func(p): return p.get("name", "") == "velocity"))
	_check("GODOT_GDSCRIPT_compiler_accepts_valid_source", bool(GodotSandbox.validate_gdscript("extends Node\nfunc _ready() -> void:\n\tpass\n").get("ok", false)))
	_check("GODOT_GDSCRIPT_size_guard", not bool(GodotSandbox.validate_gdscript("x".repeat(270000)).get("ok", true)))
	_check("GODOT_SANDBOX_rejects_traversal_paths", GodotSandbox.is_safe_project_path("scripts/player.gd") and not GodotSandbox.is_safe_project_path("../escape.gd") and not GodotSandbox.is_safe_project_path("/etc/passwd"))
	var sandbox_root := ProjectSettings.globalize_path(root + "sandbox_project")
	DirAccess.make_dir_recursive_absolute(sandbox_root)
	var safe_write := GodotSandbox.write_project_text(sandbox_root, "scripts/generated.gd", "extends Node\n")
	_check("GODOT_SANDBOX_writes_native_project_files", bool(safe_write.get("ok", false)) and FileAccess.file_exists(sandbox_root.path_join("scripts/generated.gd")))
	var replacement_write := GodotSandbox.write_project_text(sandbox_root, "scripts/generated.gd", "extends Node\n\nfunc ready_for_review() -> bool:\n\treturn true\n")
	var generated_script_path := sandbox_root.path_join("scripts/generated.gd")
	_check("GODOT_SANDBOX_replaces_source_atomically_without_exposing_sidecars", bool(replacement_write.get("ok", false)) and FileAccess.get_file_as_string(generated_script_path).contains("ready_for_review") and not FileAccess.file_exists(generated_script_path + ".bak") and not FileAccess.file_exists(generated_script_path + ".tmp"))
	var binary_fixture := PackedByteArray([0, 17, 128, 255])
	var binary_path := sandbox_root.path_join("sources/asset.bin")
	_check("STORE_atomic_binary_write_preserves_exact_bytes", Store.write_bytes_atomic(binary_path, binary_fixture) and FileAccess.get_file_as_bytes(binary_path) == binary_fixture)
	var scene_result := GodotSandbox.create_scene(sandbox_root, "scenes/platformer.tscn", {"root_type":"Node2D", "root_name":"Platformer", "nodes":[{"name":"Player", "type":"CharacterBody2D", "parent":"root"}, {"name":"PlayerCollision", "type":"CollisionShape2D", "parent":"Player", "shape_kind":"capsule"}, {"name":"Ground", "type":"StaticBody2D", "parent":"root"}, {"name":"GroundCollision", "type":"CollisionShape2D", "parent":"Ground", "shape_kind":"rectangle"}]})
	var loaded_scene: PackedScene = load(sandbox_root.path_join("scenes/platformer.tscn")) if bool(scene_result.get("ok", false)) else null
	var scene_instance: Node = loaded_scene.instantiate() if loaded_scene != null else null
	_check("GODOT_SANDBOX_packs_native_scene_hierarchy", bool(scene_result.get("ok", false)) and scene_instance != null and scene_instance.get_child_count() == 2)
	var player_shape: CollisionShape2D = scene_instance.get_node_or_null("Player/PlayerCollision") if scene_instance != null else null
	var ground_shape: CollisionShape2D = scene_instance.get_node_or_null("Ground/GroundCollision") if scene_instance != null else null
	_check("GODOT_SANDBOX_generates_real_physics_shapes", player_shape != null and player_shape.shape is CapsuleShape2D and ground_shape != null and ground_shape.shape is RectangleShape2D)
	if scene_instance != null: scene_instance.free()
	var unsafe_scene := GodotSandbox.create_scene(sandbox_root, "scenes/unsafe.tscn", {"root_type":"Node2D", "nodes":[{"name":"Process", "type":"OS", "parent":"root"}]})
	_check("GODOT_SANDBOX_blocks_unapproved_node_types", not bool(unsafe_scene.get("ok", true)))
	var discovery_project := Store.new_project("Flappy Prototype", "A side-scrolling arcade game with obstacle gaps")
	var discovery_result: Array = []
	ToolRunner.completed.connect(func(result: Dictionary): discovery_result.append(result), CONNECT_ONE_SHOT)
	ToolRunner._search_saved_projects("flappy")
	_check("WORKSPACE_search_finds_saved_project_by_title", not discovery_result.is_empty() and bool(discovery_result[0].get("ok", false)) and "Flappy Prototype" in str(discovery_result[0].get("output", "")))
	var missing_project_result: Array = []
	ToolRunner.completed.connect(func(result: Dictionary): missing_project_result.append(result), CONNECT_ONE_SHOT)
	ToolRunner._search_saved_projects("not-a-real-project")
	_check("WORKSPACE_search_states_its_scope_when_no_project_matches", not missing_project_result.is_empty() and "does not cover the phone's general storage" in str(missing_project_result[0].get("output", "")))
	var sess := Store.new_session()
	Store.save_session(sess)
	_check("STORE_empty_chat_not_written", Store.list_sessions().is_empty())
	sess["messages"] = [{"role": "user", "content": "hi 🙂"}, {"role": "assistant", "content": "hello"}]
	sess["title"] = Store.title_from("a very long first message that should be shortened because titles are short okay")
	Store.save_session(sess)
	var back := Store.load_session(str(sess["id"]))
	_check("STORE_session_roundtrip", back["messages"][0]["content"] == "hi 🙂" and Store.list_sessions().size() == 1 and str(back["title"]).ends_with("…"))
	var f := FileAccess.open(root + "sessions/bad.json", FileAccess.WRITE); f.store_string("{not json"); f.close()
	_check("STORE_corrupt_file_ignored_not_crash", Store.list_sessions().size() == 1 and FileAccess.file_exists(root + "sessions/bad.json.corrupt"))
	var proj := Store.new_project("Print shop", "sell stickers")
	var added := Store.save_to_project(proj, "Plan", "Intro\n- [ ] Make 3 designs\n- [ ] Post on market\n- [ ] Make 3 designs", Md)
	var p2 := Store.get_project(str(proj["id"]))
	_check("STORE_save_to_project_makes_tasks_no_dupes", added == 2 and p2["tasks"].size() == 2 and "## Plan" in str(p2["notes"]) and Store.list_projects().any(func(item): return str(item.get("id", "")) == str(proj.get("id", ""))))
	var saved_knowledge := Store.add_knowledge("Godot mobile safe areas", "Use display safe-area insets and keep controls inside the physical gesture-safe bounds.", ["Godot", "mobile"], "chat")
	_check("KNOWLEDGE_global_note_created", not saved_knowledge.is_empty() and Store.list_knowledge().size() == 1)
	_check("KNOWLEDGE_searches_title_content_and_tags", Store.search_knowledge("gesture").size() == 1 and Store.search_knowledge("mobile").size() == 1)
	var edited_knowledge := Store.get_knowledge(str(saved_knowledge.id))
	edited_knowledge["pinned"] = true
	edited_knowledge["title"] = "Safe-area layout rules"
	_check("KNOWLEDGE_update_persists_edits_and_pin", Store.update_knowledge(edited_knowledge) and bool(Store.get_knowledge(str(saved_knowledge.id)).get("pinned", false)) and str(Store.get_knowledge(str(saved_knowledge.id)).get("title", "")) == "Safe-area layout rules")
	_check("KNOWLEDGE_pinned_notes_rank_first", Store.search_knowledge("", 10)[0].get("pinned", false))
	Store.add_knowledge("Termux Python installation", "Use pkg update then pkg install python git clang. Termux is the local Android Linux environment.", ["Termux", "Android", "Python"], "manual")
	_check("KNOWLEDGE_retrieval_matches_related_words_across_note", not Store.retrieve_knowledge("How do I install Python in Termux?", 3).is_empty() and str(Store.retrieve_knowledge("How do I install Python in Termux?", 3)[0].get("title", "")).contains("Termux"))
	_check("KNOWLEDGE_multiword_search_is_not_exact_phrase_only", Store.search_knowledge("Python Termux").size() >= 1)
	var knowledge_tool_results: Array = []
	var knowledge_tool_capture := func(result: Dictionary): knowledge_tool_results.append(result)
	ToolRunner.completed.connect(knowledge_tool_capture)
	ToolRunner.execute_tool({"name":"knowledge.search", "query":"Install Python Termux"})
	ToolRunner.completed.disconnect(knowledge_tool_capture)
	var knowledge_tool_result: Dictionary = knowledge_tool_results[0] if not knowledge_tool_results.is_empty() else {}
	_check("TOOL_global_knowledge_search_returns_real_matches", bool(knowledge_tool_result.get("ok", false)) and str(knowledge_tool_result.get("output", "")).contains("Termux Python installation"))
	var knowledge_save_results: Array = []
	var knowledge_save_capture := func(result: Dictionary): knowledge_save_results.append(result)
	ToolRunner.completed.connect(knowledge_save_capture)
	ToolRunner.execute_tool({"name":"knowledge.save", "title":"Approved tool note", "content":"Only save after user approval.", "tags":["approval"]})
	ToolRunner.completed.disconnect(knowledge_save_capture)
	var knowledge_save_result: Dictionary = knowledge_save_results[0] if not knowledge_save_results.is_empty() else {}
	_check("TOOL_global_knowledge_save_creates_durable_note", bool(knowledge_save_result.get("ok", false)) and not Store.search_knowledge("Approved tool note").is_empty())
	Store.delete_knowledge(str(saved_knowledge.id))
	_check("KNOWLEDGE_delete_removes_note", Store.get_knowledge(str(saved_knowledge.id)).is_empty())
	var project_id := str(proj["id"])
	var detailed_plan := {"summary":"Deliver the complete project through a traceable sequence from discovery to verified user-facing release.", "tasks":[
		{"title":"Define the project architecture", "detail":"Inspect the project entry points, requirements, supported runtime and existing conventions, then document the complete implementation boundary and dependencies.", "deliverables":["Project architecture and constraints brief"], "role":"Planner", "priority":"high", "acceptance":"The brief covers the primary experience, supporting screens, persistence, constraints and delivery conditions.", "verification":"Compare the brief with the user's request and inspect the existing project entry points.", "file_scope":["project brief"], "depends_on":[]},
		{"title":"Build the application foundation", "detail":"Create the shared application structure, navigation foundation, theme resources and initialization path while preserving the project's existing conventions.", "deliverables":["Application shell and shared foundation"], "role":"Engineer", "priority":"high", "acceptance":"The application opens through its primary entry point and all core routes resolve without missing resources.", "verification":"Run the project entry point and inspect initialization and navigation behavior.", "file_scope":["main scene", "shared UI"], "depends_on":["Define the project architecture"]},
		{"title":"Implement the primary user experience", "detail":"Implement the main user-facing flow with complete input handling, meaningful states, persistent data behavior and the core outcome requested for this project.", "deliverables":["Primary experience with its complete user flow"], "role":"Engineer", "priority":"high", "acceptance":"A user can complete the main flow from entry to its expected result without dead ends or placeholder actions.", "verification":"Exercise the main flow with representative input and inspect saved state and visible results.", "file_scope":["primary experience"], "depends_on":["Build the application foundation"]},
		{"title":"Add supporting screens and persistence", "detail":"Implement the relevant secondary screens, settings, empty and error states, plus durable persistence and recovery for user-created data.", "deliverables":["Supporting screens", "Persistence and recovery behavior"], "role":"Engineer", "priority":"normal", "acceptance":"Supporting flows remain usable and user data survives a close and reopen cycle without losing valid state.", "verification":"Navigate every supporting flow and reload the project data from a fresh application session.", "file_scope":["supporting screens", "storage"], "depends_on":["Implement the primary user experience"]},
		{"title":"Verify and polish the complete result", "detail":"Review the finished user experience for visual consistency, accessibility, runtime errors and acceptance gaps, then correct defects before delivery.", "deliverables":["Verified project result", "Review record and remaining limitations"], "role":"Reviewer", "priority":"high", "acceptance":"All agreed user-facing flows work and remaining limitations are explicit rather than presented as completed features.", "verification":"Run focused runtime checks, inspect fresh screenshots and compare behavior against the acceptance criteria.", "file_scope":["whole project"], "depends_on":["Add supporting screens and persistence"]}
	]}
	# New-project research is a hard gate: every required investigation and citation
	# must be backed by extracted source text before any roadmap can be applied.
	var research_project := Store.new_project("Research gate test", "An original 2D tactical physics game with readable combat and short sessions.")
	research_project["project_kind"] = "game"
	research_project["research_required"] = true
	Store.save_project(research_project)
	var research_project_id := str(research_project.get("id", ""))
	# First prove that a missing paid search credential no longer blocks a new
	# project. Then enable a mock credential to exercise the evidence gate itself.
	var limited_flow := AgentFlow.ensure_flow(research_project)
	_check("RESEARCH_missing_search_key_uses_limited_mode", str(limited_flow.get("research", {}).get("status", "")) == "unavailable" and not bool(Store.get_project(research_project_id).get("research_required", true)) and bool(AgentFlow.validate_plan(detailed_plan, research_project_id).get("ok", false)))
	Store.set_secret("brave_search", "unit-test-search-credential")
	research_project = Store.get_project(research_project_id)
	research_project["research_required"] = true
	Store.save_project(research_project)
	var research_flow := AgentFlow.ensure_flow(research_project)
	AgentFlow.begin_research(research_project_id)
	_check("RESEARCH_new_project_starts_in_discovery", str(AgentFlow.get_flow(research_project_id).get("research", {}).get("status", "")) == "collecting")
	_check("RESEARCH_plan_is_blocked_before_any_evidence", not bool(AgentFlow.validate_plan(detailed_plan, research_project_id).get("ok", false)) and not AgentFlow.apply_plan(research_project_id, detailed_plan))
	var research_fixture := [
		{"label":"ref_a", "angle":"reference_landscape", "query":"2D physics tactics game reference design", "url":"https://indie-db.test/games/physics-tactics", "host":"indie-db.test", "snippet":"The reference game uses physics-driven units, readable arenas and short repeatable encounters to create emergent tactical outcomes."},
		{"label":"ref_b", "angle":"reference_landscape", "query":"2D physics tactics game reference design", "url":"https://openreview.test/interactive-systems/tactical-sandbox", "host":"openreview.test", "snippet":"A sandbox tactics experience benefits from clear unit roles, predictable controls and enough environmental variation to create multiple solutions."},
		{"label":"feedback_a", "angle":"player_feedback", "query":"player feedback physics tactics games controls frustration", "url":"https://reddit.com/r/gamedev/comments/abc/player_feedback", "host":"reddit.com", "snippet":"Players complain that inconsistent physics and unclear unit selection make losses feel random rather than earned, especially on small screens."},
		{"label":"feedback_b", "angle":"player_feedback", "query":"player feedback physics tactics games controls frustration", "url":"https://steamcommunity.com/app/123/discussions/456/player-feedback", "host":"steamcommunity.com", "snippet":"Community feedback praises surprising emergent battles but dislikes long setup time, poor camera framing and units that fail to respond to input."},
		{"label":"tech_a", "angle":"technical_docs", "query":"Godot 2D physics documentation mobile performance", "url":"https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html", "host":"docs.godotengine.org", "snippet":"Godot physics uses a fixed timestep for simulation and recommends choosing collision shapes and physics settings according to the needs of the project."},
		{"label":"tech_b", "angle":"technical_docs", "query":"Android game performance documentation frame pacing", "url":"https://developer.android.com/games/optimize", "host":"developer.android.com", "snippet":"Android game performance guidance recommends measuring frame pacing, memory pressure and thermal behavior on representative target devices."},
		{"label":"asset_a", "angle":"production_assets", "query":"game asset licensing original audio sprite animation requirements", "url":"https://opengameart.org/content/licensing-guide", "host":"opengameart.org", "snippet":"Open game assets can carry attribution and share-alike obligations, so each imported sprite, sound and animation should retain its provenance and license."},
		{"label":"asset_b", "angle":"production_assets", "query":"creative commons game assets licenses attribution adaptation", "url":"https://creativecommons.org/share-your-work/cclicenses/", "host":"creativecommons.org", "snippet":"Creative Commons licenses differ in attribution, commercial use and adaptation permissions, and those restrictions must be checked before redistributing assets."}
	]
	var research_source_ids: Dictionary = {}
	var research_snippets: Dictionary = {}
	var angle_queries := {"reference_landscape":"2D physics tactics game reference design", "player_feedback":"player feedback physics tactics games controls frustration", "technical_docs":"Godot 2D physics documentation mobile performance", "production_assets":"game asset licensing original audio sprite animation requirements"}
	for angle_name in angle_queries:
		var incoming_sources: Array = []
		for fixture in research_fixture:
			if str(fixture.angle) == str(angle_name):
				incoming_sources.append({"url":fixture.url, "hostname":fixture.host, "title":str(fixture.label), "snippets":[str(fixture.snippet)]})
		var stored_ids: Array = AgentFlow.record_research_sources(research_project_id, str(angle_queries[angle_name]), incoming_sources, str(angle_name))
		for fixture in research_fixture:
			if str(fixture.angle) == str(angle_name):
				var digest := HashingContext.new()
				digest.start(HashingContext.HASH_SHA256)
				digest.update(str(fixture.url).to_utf8_buffer())
				research_source_ids[str(fixture.label)] = "src_" + digest.finish().hex_encode().left(12)
				research_snippets[str(fixture.label)] = str(fixture.snippet)
	var brief_sources := func(labels: Array) -> Array:
		var refs: Array = []
		for label in labels: refs.append(str(research_source_ids.get(str(label), "")))
		return refs
	var research_brief := {
		"executive_summary":"The project should deliver a complete original 2D tactical physics game built around readable short battles, meaningful preparation and surprising but controllable emergent outcomes across a clear progression structure.",
		"user_and_context":"The primary audience wants quick strategic sessions on a phone, with legible unit selection, clear feedback, responsive controls and enough tactical depth to replay encounters without long menus or confusing setup.",
		"core_experience":"The player assembles a small squad, chooses positions and equipment, starts a battle, observes the physics-driven encounter, intervenes through clear controls, then reviews outcomes and unlocks meaningful options for the next challenge.",
		"differentiation":"The game will use an original visual identity, original units and authored scenarios rather than copying recognizable assets, names, interfaces or exact battle rules from existing games.",
		"feel_and_pacing":"Preparation should be deliberate but brief, impacts should read clearly, physics outcomes should feel surprising without appearing arbitrary, and each encounter should resolve quickly enough to invite another attempt.",
		"reference_analysis":[
			{"title":"Physics Tactics Reference A", "pattern":"Physics-driven units create emergent encounters inside readable arenas with short repeatable rounds.", "transferable_lesson":"Use a small set of legible unit behaviors and compact arenas so unexpected interactions remain understandable to new players.", "tradeoff":"Emergent motion can feel random if selection and collision feedback are not precise.", "source_ids":brief_sources.call(["ref_a"])},
			{"title":"Sandbox Tactics Reference B", "pattern":"Distinct unit roles and arena variation encourage players to discover alternate solutions to a common encounter.", "transferable_lesson":"Make each unit role mechanically distinct and use authored arena modifiers to create tactical variety without excessive content volume.", "tradeoff":"Too many unit rules can overwhelm the small-screen interface and tutorial.", "source_ids":brief_sources.call(["ref_b"])}
		],
		"user_feedback":[
			{"issue":"Players report that inconsistent physics and unclear unit selection make a defeat appear random instead of understandable.", "impact":"The player loses confidence in the rules and stops experimenting with tactics.", "evidence_type":"player community discussion", "source_ids":brief_sources.call(["feedback_a"])},
			{"issue":"Players value emergent battles but criticize slow setup and camera framing that hides important units.", "impact":"The battle loses momentum and becomes difficult to read on a small display.", "evidence_type":"store community discussion", "source_ids":brief_sources.call(["feedback_b"])},
			{"issue":"Touch control reliability and readable selection are repeated usability risks for compact strategy encounters.", "impact":"Players may attribute input mistakes to unfair simulation behavior.", "evidence_type":"player community discussion", "source_ids":brief_sources.call(["feedback_a", "feedback_b"])}
		],
		"positive_patterns":[
			{"title":"Emergent encounters", "detail":"Allow a small set of understandable forces to combine into varied outcomes while preserving readable causes and effects.", "source_ids":brief_sources.call(["feedback_b"])},
			{"title":"Distinct roles", "detail":"Give every unit a recognizable purpose so team composition is a meaningful decision rather than a cosmetic choice.", "source_ids":brief_sources.call(["ref_b"])},
			{"title":"Short repeatable battles", "detail":"Keep match setup and resolution compact so experimentation and replay remain attractive on mobile.", "source_ids":brief_sources.call(["ref_a"])}
		],
		"avoidance_patterns":[
			{"title":"Unexplained physics losses", "detail":"Expose collision causes and predictable baseline movement before adding chaotic interactions.", "source_ids":brief_sources.call(["feedback_a"])},
			{"title":"Overlong preparation", "detail":"Keep squad setup shallow and progressive so the player enters the first battle quickly.", "source_ids":brief_sources.call(["feedback_b"])},
			{"title":"Poor camera framing", "detail":"Keep units and relevant arena hazards visible and provide a controlled recenter action.", "source_ids":brief_sources.call(["feedback_b"])},
			{"title":"Unlicensed borrowed assets", "detail":"Use original assets or explicitly compatible licenses and preserve attribution and provenance.", "source_ids":brief_sources.call(["asset_a", "asset_b"])}
		],
		"design_pillars":[{"title":"Readable chaos", "detail":"Every decisive impact must have a visible cause, recognizable response and clear result."}, {"title":"Short tactical loop", "detail":"Squad preparation, battle and result review should form a compact repeatable loop."}, {"title":"Original world identity", "detail":"Use new units, arenas, names, visual assets and rules rather than copying reference expression."}],
		"required_systems":[{"title":"Squad roster", "detail":"Provide unit identity, role, stats and availability with clear selection feedback."}, {"title":"Battle simulation", "detail":"Use deterministic fixed-step simulation and bounded collision behavior for stable outcomes."}, {"title":"Arena authoring", "detail":"Support designed layouts, hazards, boundaries and readable camera framing."}, {"title":"Touch controls", "detail":"Provide reliable selection, placement, camera and pause actions with cancellation handling."}, {"title":"Progression", "detail":"Unlock new options through meaningful rewards and persist the campaign state."}, {"title":"Result review", "detail":"Explain battle outcomes and provide rematch or next-challenge actions."}],
		"assets_and_inputs":[{"title":"Unit sprites", "detail":"Create original unit silhouettes, directional states, damage and defeat poses with documented provenance."}, {"title":"Arena visuals", "detail":"Create reusable background, floor, wall and hazard tiles with strong foreground separation."}, {"title":"UI iconography", "detail":"Design original unit-role, squad, pause, settings and results icons with accessible contrast."}, {"title":"Audio feedback", "detail":"Create or license impact, selection, victory, defeat and interface cues with clear source licenses."}, {"title":"Animation set", "detail":"Provide idle, movement, attack, recoil, impact and defeat animation states for each unit family."}],
		"technical_risks":[{"risk":"Variable physics outcomes can look unfair.", "mitigation":"Use fixed timestep, controlled initial conditions and replayable scenarios to inspect decisive interactions."}, {"risk":"Touch controls can conflict with camera gestures.", "mitigation":"Separate control zones and test swipes from interactive surfaces on target aspect ratios."}, {"risk":"Too many active physics bodies can hurt low-end mobile performance.", "mitigation":"Profile representative battles, cap body counts and pool effects where measurements justify it."}, {"risk":"Asset licenses may restrict redistribution or modification.", "mitigation":"Track source URL, license, author and attribution for every third-party asset."}],
		"validation_experiments":[{"title":"First battle readability", "hypothesis":"New players can identify why a unit wins or loses after one short battle.", "method":"Build one arena with two unit types and record five repeated battles with visible collision feedback.", "success_metric":"At least four of five outcomes can be explained from visible positioning and action cues.", "failure_condition":"Players cannot identify the decisive interaction or describe the cause of failure."}, {"title":"Touch placement precision", "hypothesis":"Players can select and place units without accidental camera movement or missed input.", "method":"Prototype placement and panning with a compact squad on a 720-pixel portrait viewport.", "success_metric":"All unit placements and camera gestures are distinguishable in the usability script.", "failure_condition":"Placement attempts routinely move the camera or select the wrong unit."}, {"title":"Simulation performance", "hypothesis":"The intended battle body count can sustain target-device frame pacing.", "method":"Run a worst-case arena with the planned maximum units and effects while tracking frame time and thermals.", "success_metric":"Frame pacing remains within the chosen target budget without sustained thermal throttling.", "failure_condition":"The target body count creates sustained frame spikes or thermal slowdowns."}],
		"citations":[],
		"inferences":[{"title":"Physics clarity is a core differentiator", "detail":"The game should make cause and effect more legible than chaotic sandbox simulations.", "basis":"This follows from reported confusion around unpredictable collisions and the need for readable cause-and-effect feedback.", "source_ids":brief_sources.call(["feedback_a", "feedback_b"])}, {"title":"Mobile session length should stay compact", "detail":"A short setup-to-result loop is likely better suited to casual mobile sessions.", "basis":"This is an inference from user complaints about long setup and camera readability.", "source_ids":brief_sources.call(["feedback_b"])}],
		"unknowns":["Which initial squad size provides meaningful tactical variety without overwhelming touch selection?", "Should the campaign be level-based or use a generated challenge ladder for longer-term replay?", "What minimum device tier can support the chosen simultaneous physics body count?"]
	}
	for citation_source in ["ref_a", "feedback_a", "feedback_b", "tech_a", "tech_b", "asset_a"]:
		var claim := "This source supports a concrete production or experience decision for the original tactical physics game."
		research_brief["citations"].append({"claim":claim, "evidence_excerpt":str(research_snippets[citation_source]), "source_ids":brief_sources.call([citation_source])})
	research_brief["critical_assumption"] = {"assumption":"Players will find short physics-driven tactical encounters understandable enough to replay and improve their strategy.", "why_it_matters":"If the simulation feels arbitrary, every progression and content feature will be built on an unstable core experience.", "failure_consequence":"A large campaign, unit roster and visual asset set could be produced without proving the underlying battles are satisfying.", "cheapest_falsification":"Prototype one compact arena with two units and ask new players to explain the decisive interaction after five short trials.", "source_ids":brief_sources.call(["feedback_a", "feedback_b", "ref_a"])}
	var incomplete_brief: Dictionary = research_brief.duplicate(true)
	(incomplete_brief["citations"] as Array)[0]["evidence_excerpt"] = "This sentence never appeared in any retrieved source passage and is fabricated evidence."
	_check("RESEARCH_rejects_fabricated_citation_excerpt", not bool(AgentFlow.validate_research_brief(research_project_id, incomplete_brief).get("ok", false)))
	var accepted_research := AgentFlow.validate_research_brief(research_project_id, research_brief)
	_check("RESEARCH_requires_all_project_angles_and_source_coverage", bool(accepted_research.get("ok", false)) and int(accepted_research.get("query_count", 0)) == 4 and int(accepted_research.get("source_count", 0)) == 8 and int(accepted_research.get("domain_count", 0)) == 8)
	_check("RESEARCH_persists_source_ids_and_extracted_passages", (AgentFlow.get_flow(research_project_id).get("research", {}).get("sources", []) as Array).size() == 8 and (AgentFlow.get_flow(research_project_id).get("research", {}).get("angles", []) as Array).size() == 4)
	_check("RESEARCH_brief_commit_unlocks_plan_gate", AgentFlow.commit_research_brief(research_project_id, research_brief) and bool(AgentFlow.validate_plan(detailed_plan, research_project_id).get("ok", false)))
	Store.delete_project(research_project_id)
	Store.remove_secret("brave_search")
	_check("RESEARCH_deleting_project_removes_research_ledger", AgentFlow.get_flow(research_project_id).is_empty())
	_check("FLOW_rejects_short_or_vague_project_plan", not bool(AgentFlow.validate_plan({"summary":"Short plan", "tasks":[{"title":"One task"}]}).get("ok", false)))
	var missing_scope_plan: Dictionary = detailed_plan.duplicate(true)
	(missing_scope_plan["tasks"] as Array)[0].erase("file_scope")
	_check("FLOW_rejects_tasks_without_project_scope", not bool(AgentFlow.validate_plan(missing_scope_plan).get("ok", false)))
	var cyclic_plan: Dictionary = detailed_plan.duplicate(true)
	(cyclic_plan["tasks"] as Array)[0]["depends_on"] = ["Verify and polish the complete result"]
	_check("FLOW_rejects_cyclic_project_roadmap", not bool(AgentFlow.validate_plan(cyclic_plan).get("ok", false)))
	var plan_ok := AgentFlow.apply_plan(project_id, detailed_plan)

	var workflow := AgentFlow.get_flow(project_id)
	var workflow_tasks: Array = workflow.get("tasks", [])
	_check("FLOW_plan_persisted_with_dependency_ids", plan_ok and workflow_tasks.size() == 5 and (workflow_tasks[1]["depends_on"] as Array).size() == 1 and str(workflow_tasks[1]["depends_on"][0]) == str(workflow_tasks[0]["id"]))
	_check("FLOW_dependency_blocks_downstream_work", not AgentFlow.can_run_task(project_id, str(workflow_tasks[1]["id"])) and AgentFlow.can_run_task(project_id, str(workflow_tasks[0]["id"])))
	AgentFlow.update_task(project_id, str(workflow_tasks[0]["id"]), {"status":"done", "title":"Create architecture brief", "role":"Planner"})
	_check("FLOW_dependency_unblocks_after_completion", AgentFlow.can_run_task(project_id, str(workflow_tasks[1]["id"])))
	AgentFlow.add_decision(project_id, "Keep the interface light and accessible")
	_check("FLOW_searches_persistent_project_knowledge", not AgentFlow.search_knowledge(project_id, "accessible", 5).is_empty())
	_check("FLOW_default_graph_has_review_gate", (workflow.get("workflow_graph", []) as Array).size() == 5)
	var second_id := str(workflow_tasks[1]["id"])
	AgentFlow.update_task(project_id, second_id, {"status":"in_progress", "title":"Implement foundation", "role":"Engineer"})
	AgentFlow.update_task(project_id, second_id, {"status":"review", "title":"Implement foundation", "role":"Engineer"})
	_check("FLOW_task_stays_pending_human_review", str(AgentFlow.get_flow(project_id).get("tasks", [])[1].get("status", "")) == "review" and not AgentFlow.can_run_task(project_id, second_id))
	_check("FLOW_human_approval_completes_reviewed_task", AgentFlow.approve_task(project_id, second_id) and str(AgentFlow.get_flow(project_id).get("tasks", [])[1].get("status", "")) == "done")
	var third_id := str(workflow_tasks[2]["id"])
	AgentFlow.update_task(project_id, third_id, {"status":"in_progress", "title":"Review foundation", "role":"Reviewer"})
	AgentFlow.update_task(project_id, third_id, {"status":"review", "title":"Review foundation", "role":"Reviewer"})
	_check("FLOW_revision_reopens_review_task", AgentFlow.request_task_revision(project_id, third_id, "Add a test report") and str(AgentFlow.get_flow(project_id).get("tasks", [])[2].get("status", "")) == "todo")
	_check("FLOW_adds_searchable_knowledge_note", AgentFlow.add_knowledge(project_id, "Branch policy", "Use feature branches for all repository changes.", ["github", "workflow"]) and not AgentFlow.search_knowledge(project_id, "feature branches", 5).is_empty())
	_check("FLOW_saves_searchable_reusable_playbook", AgentFlow.add_playbook(project_id, "Release verification", "Before packaging", "1. Run tests\n2. Build app\n3. Inspect screenshots") and not AgentFlow.search_knowledge(project_id, "release verification", 5).is_empty())
	var prompt_context := Catalog.system_prompt("build", Store.get_project(project_id))
	_check("FLOW_injects_reusable_playbook_into_project_context", prompt_context.contains("Release verification") and prompt_context.contains("Before packaging"))
	const ChatScriptForApproval = preload("res://scripts/ui/ChatScreen.gd")
	var approval_probe: Node = ChatScriptForApproval.new()
	approval_probe.session = {"mode":"chat", "project_id":""}
	var approval_check := func(tool_name: String) -> bool: return approval_probe._tool_requires_approval({"name":tool_name})
	_check("FLOW_mutating_tools_require_approval", approval_check.call("linux.exec") and approval_check.call("github.write_file") and not approval_check.call("project.save_playbook") and approval_check.call("knowledge.save") and not approval_check.call("github.read_file"))
	_check("FLOW_godot_run_stop_and_test_require_approval", approval_check.call("godot.run") and approval_check.call("godot.stop") and approval_check.call("godot.test"))
	_check("FLOW_godot_capture_and_logs_are_read_only", not approval_check.call("godot.capture") and not approval_check.call("godot.logs"))
	approval_probe.free()
	_check("FLOW_godot_tool_runner_dispatch_exists", ToolRunner.has_method("execute_tool") and ToolRunner.has_method("_godot_request"))
	_check("FLOW_vision_model_detection_is_conservative", ChatScriptForApproval._model_supports_images("openrouter/openai/gpt-4o-mini") and ChatScriptForApproval._model_supports_images("google/gemini-2.5-flash") and not ChatScriptForApproval._model_supports_images("deepseek/deepseek-chat"))
	AgentFlow.record_approval(project_id, "linux.exec", true, "python -m unittest")
	_check("FLOW_approval_is_audited", str(AgentFlow.get_flow(project_id).get("activity", [])[0].get("action", "")).contains("Approved linux.exec"))
	const ChatScript = preload("res://scripts/ui/ChatScreen.gd")
	_check("FLOW_tool_scopes_researcher_read_only", ChatScript._role_allows_tool("Researcher", "github.read_file") and not ChatScript._role_allows_tool("Researcher", "linux.exec"))
	_check("FLOW_researcher_can_read_godot_capture_and_logs", ChatScript._role_allows_tool("Researcher", "godot.capture") and ChatScript._role_allows_tool("Researcher", "godot.logs") and not ChatScript._role_allows_tool("Researcher", "godot.run"))
	_check("FLOW_reviewer_can_verify_but_not_launch_project", ChatScript._role_allows_tool("Reviewer", "godot.test") and not ChatScript._role_allows_tool("Reviewer", "godot.run"))
	_check("FLOW_engineer_can_run_godot_project", ChatScript._role_allows_tool("Engineer", "godot.run") and ChatScript._role_allows_tool("Engineer", "godot.capture"))
	_check("FLOW_tool_scopes_reviewer_no_repository_writes", ChatScript._role_allows_tool("Reviewer", "piston.run") and not ChatScript._role_allows_tool("Reviewer", "github.write_file"))
	_check("FLOW_planner_can_publish_reusable_sops", ChatScript._role_allows_tool("Planner", "project.save_playbook") and not ChatScript._role_allows_tool("Researcher", "project.save_playbook"))
	_check("FLOW_engineer_has_mutation_tools", ChatScript._role_allows_tool("Engineer", "github.write_file") and ChatScript._role_allows_tool("Engineer", "linux.exec"))
	Store.delete_session(str(sess["id"])); Store.delete_project(project_id)
	_check("FLOW_project_delete_removes_workflow", AgentFlow.get_flow(project_id).is_empty())
	DirAccess.make_dir_recursive_absolute(root + "generated_images")
	var generated := FileAccess.open(root + "generated_images/test.png", FileAccess.WRITE)
	generated.store_buffer(PackedByteArray([1, 2, 3]))
	generated.close()
	Store.wipe_all()
	_check("STORE_wipe_removes_generated_media_and_credentials", not FileAccess.file_exists(root + "generated_images/test.png") and not FileAccess.file_exists(root + "keys.dat") and not FileAccess.file_exists(root + "device.seed") and not Store.has_secret("github") and Store.list_sessions().is_empty() and Store.list_projects().is_empty())
	Store.load_all()
	_check("STORE_delete_and_remove_key", Store.list_sessions().is_empty() and Store.list_projects().is_empty() and Store.list_knowledge().is_empty() and not Store.has_key("openrouter") and not Store.has_secret("github") and not Store.has_secret("huggingface"))
	var bad := 0
	for r in results: if not r[1]: bad += 1
	print("UNIT_SUMMARY ", results.size() - bad, "/", results.size(), " passed")
	get_tree().quit(1 if bad > 0 else 0)

func _check(n: String, ok: bool, detail: Variant = null) -> void:
	results.append([n, ok]); print("UNIT_", n, " ", "PASS" if ok else "FAIL", "" if ok or detail == null else " :: " + JSON.stringify(detail))
