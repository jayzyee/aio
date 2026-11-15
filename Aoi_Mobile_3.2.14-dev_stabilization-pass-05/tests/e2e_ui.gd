extends Node
# Whole phone UI against the mock provider: connect, chat (streamed), history, model switch, save to project, regenerate, errors.
var results: Array = []
var main: Control

const ChatScreenForPolicy = preload("res://scripts/ui/ChatScreen.gd")
const BuildCardForAcceptance = preload("res://scripts/ui/BuildExperienceCard.gd")

func _approval_required(tool_name: String, mode: String = "chat", project_id: String = "") -> bool:
	var probe: Node = ChatScreenForPolicy.new()
	probe.session = {"mode":mode, "project_id":project_id}
	var required: bool = probe._tool_requires_approval({"name":tool_name})
	probe.free()
	return required

func _ready() -> void:
	Store.set_root("user://ui_%s/" % Crypto.new().generate_random_bytes(12).hex_encode())
	main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await _wait(0.8)
	var chat = main.chat
	var setup = main.setup
	# first run: nothing connected -> chat explains, send is refused politely
	_check("U1_first_run_explains_provider_setup", Store.connected_providers().is_empty() and _text(chat._msgs).contains("What do you want to do?") and _text(chat._msgs).contains("Connect an AI provider"))
	var aoi_wordmark := chat.find_child("AoiWordmark", true, false) as Label
	_check("U1B_first_run_identifies_Aoi_with_its_constellation_mark", aoi_wordmark != null and aoi_wordmark.text == "Aoi" and chat.find_child("AoiConstellation", true, false) != null)
	var starter_prompt := chat.find_child("StarterPrompt0", true, false) as Button
	if starter_prompt != null: starter_prompt.pressed.emit()
	_check("U1A_first_run_starter_prompt_is_a_draft_not_an_automatic_request", starter_prompt != null and chat._input.text == "Explain something simply" and Store.list_sessions().is_empty())
	chat._input.text = ""
	chat._fit_input()
	main.open_navigation_drawer()
	var drawer_copy := _text(main._drawer) if main._drawer != null else ""
	_check("U0_navigation_drawer_exposes_primary_destinations", main._drawer != null and drawer_copy.contains("Projects") and drawer_copy.contains("Library") and drawer_copy.contains("Workbench") and drawer_copy.contains("Connections") and drawer_copy.contains("Settings"))
	main._close_navigation_drawer()
	main.go("projects")
	_check("U0A_projects_open_from_primary_navigation", main.tab == "projects" and main.projects.visible)
	main.go("knowledge")
	_check("U0B_library_is_a_primary_destination", main.tab == "knowledge" and main.knowledge.visible)
	main.go("explore")
	_check("U0C_explore_is_a_primary_destination", main.tab == "explore" and main.explore.visible)
	main.go("chat")
	# Setup: bad key is rejected and not stored
	main.go("setup")
	setup.connect_provider("openrouter", "bad-key")
	await _wait(1.2)
	_check("U2_bad_key_rejected_not_stored", not Store.has_key("openrouter") and _text(setup).contains("rejected your key"))
	setup.connect_provider("openrouter", "good-key")
	await _wait(1.5)
	_check("U3_good_key_connects_and_picks_model", Store.has_key("openrouter") and Store.connected_providers() == ["openrouter"] and Store.model.begins_with("openrouter/") and not "-vl" in Store.model and _text(setup).contains("Connected"))
	var custom_url := "http://127.0.0.1:%s/v1" % OS.get_environment("MOCK_PORT")
	setup.connect_custom_provider("Mock-compatible provider", custom_url, "good-key")
	await _wait(1.5)
	var custom_config := Store.get_integration("custom_provider")
	_check("U3A_custom_provider_is_verified_and_discovers_models", Store.has_key("custom") and Store.connected_providers().has("custom") and custom_config.get("name", "") == "Mock-compatible provider" and custom_config.get("base_url", "") == custom_url and int(Store.status.get("custom", {}).get("models_count", 0)) > 0)
	LLM.chat("custom/meta-llama/llama-3.3-70b-instruct:free", [{"role":"user", "content":"custom endpoint route"}])
	var custom_chat: Dictionary = await LLM.chat_finished
	_check("U3B_custom_provider_routes_chat_to_saved_endpoint", custom_chat.get("ok", false) and "custom endpoint route" in str(custom_chat.get("text", "")))
	# Chat: stream a reply, history is saved
	main.go("chat")
	chat.send_text("hello phone")
	await _wait_idle()
	_check("U4_streamed_reply_shown_and_saved", _text(chat._msgs).contains("You said: hello phone") and Store.list_sessions().size() == 1 and Store.list_sessions()[0]["messages"].size() == 2)
	_check("U4C_thinking_presence_clears_after_reply_starts", main.find_child("AoiThinkingStatus", true, false) == null)
	_check("U4A_normal_chat_does_not_show_agent_activity", chat._activity_strip == null or not is_instance_valid(chat._activity_strip))
	var read_aloud := chat.find_child("ReadAloud", true, false) as Button
	_check("U4B_assistant_replies_expose_explicit_read_aloud_action", read_aloud != null and read_aloud.tooltip_text.contains("tap again to stop"))
	chat.send_text("second question")
	await _wait_idle()
	var log := await _log()
	var posts: Array = []
	for e in log: if e["m"] == "POST": posts.append(e)
	_check("U5_second_message_carries_history", int(posts[posts.size() - 1]["n_messages"]) == 4)   # system + user + assistant + user
	var saved_chat_session: Dictionary = chat.session
	chat.session = {"messages":[{"role":"user", "content":"Visible question"}, {"role":"assistant", "content":"Visible answer"}, {"role":"tool", "content":"Hidden tool result"}, {"role":"assistant", "content":"Hidden workflow state", "internal":true}]}
	main._copy_current_conversation()
	var copied_transcript := DisplayServer.clipboard_get()
	_check("U5A_copy_conversation_includes_only_visible_chat_messages", copied_transcript.contains("Visible question") and copied_transcript.contains("Visible answer") and not copied_transcript.contains("Hidden tool result") and not copied_transcript.contains("Hidden workflow state"))
	chat.session = saved_chat_session
	# Model switch applies to the next message
	main._choose_model("openrouter/cohere/north-mini-code:free", "cohere/north-mini-code:free")
	chat.send_text("third")
	await _wait_idle()
	_check("U6_model_switch_used_next_message", _text(chat._msgs).contains("[cohere/north-mini-code:free]"))
	# Errors are shown with a way out, and the app keeps working
	chat.send_text("ERR401 please")
	await _wait_idle()
	_check("U7_error_card_with_retry", _text(chat._msgs).contains("I couldn't get a reply") and _text(chat._msgs).contains("rejected your key"))
	var failed_session_id := str(chat.session.get("id", ""))
	chat.open_session(failed_session_id)
	var failed_turn_is_hidden_from_model := true
	for history_message in chat._history():
		if str(history_message.get("content", "")).contains("rejected your key"):
			failed_turn_is_hidden_from_model = false
	_check("U7A_failed_response_card_survives_reload_without_entering_model_history", _text(chat._msgs).contains("I couldn't get a reply") and _text(chat._msgs).contains("Try again") and failed_turn_is_hidden_from_model)
	chat.send_text("still alive?")
	await _wait_idle()
	_check("U8_chat_continues_after_error", _text(chat._msgs).contains("You said: still alive?"))
	# Save an answer into a project: notes + tasks
	var p := Store.new_project("Sticker shop", "sell stickers")
	main._save_into(str(p["id"]), "Plan\n- [ ] Draw 5 designs\n- [ ] Open a shop")
	var p2 := Store.get_project(str(p["id"]))
	_check("U9_save_to_project_creates_tasks", p2["tasks"].size() == 2 and str(p2["notes"]).contains("Draw 5 designs"))
	# Seed the project-scoped workflow so Work details has a real persisted event.
	AgentFlow.ensure_flow(p2)
	main.go("projects")
	main.projects.show_list()
	var project_search: LineEdit = main.projects._project_search
	if project_search != null: project_search.text = "Sticker"; project_search.text_changed.emit("Sticker")
	await get_tree().process_frame
	var project_cards_visible := 0
	for row in main.projects._project_card_rows:
		if (row.get("control") as Control).visible: project_cards_visible += 1
	_check("U9A_projects_can_be_searched_by_name_and_goal", project_search != null and project_cards_visible == 1)
	if project_search != null: project_search.text = "no-such-project"; project_search.text_changed.emit("no-such-project")
	await get_tree().process_frame
	var no_projects_match: Label = main.projects._no_results
	_check("U9B_project_search_has_a_real_no-results_state", no_projects_match != null and no_projects_match.visible)
	if project_search != null: project_search.text = ""; project_search.text_changed.emit("")
	# Consumer-facing project home: the first view must show the goal and next
	# action, while developer operations remain behind Work details.	
	var project_id := str(p.get("id", ""))
	main.projects.open_project(project_id)
	var home_copy := _text(main.projects)
	_check("U9C_project_home_prioritises_saved_output_and_continue_action", home_copy.contains("Continue with Aoi") and home_copy.contains("Work details") and home_copy.contains("Nothing to review yet"))
	_check("U9D_project_home_hides_progress_management_by_default", not home_copy.contains("WORK STATUS") and not home_copy.contains("RECENT ACTIVITY") and not home_copy.contains("NEXT MILESTONE") and not home_copy.contains("Add a task"))
	# A preview is only exposed when a persisted capture file is actually present.
	var preview_project: Dictionary = Store.get_project(project_id)
	var home_capture_path := ProjectSettings.globalize_path(Store.root + "project_home_capture_fixture.png")
	var home_capture_image := Image.create(64, 40, false, Image.FORMAT_RGBA8)
	home_capture_image.fill(Color("#a8b2c7"))
	var preview_write := home_capture_image.save_png(home_capture_path)
	preview_project["project_kind"] = "game"
	preview_project["preview_path"] = home_capture_path
	preview_project["preview_kind"] = "paired_runtime_capture"
	Store.save_project(preview_project)
	main.projects.open_project(project_id)
	var preview_copy := _text(main.projects)
	var preview_button := main.projects.find_child("OpenProjectCaptureButton", true, false) as Button
	_check("U9D1_project_home_shows_only_an_existing_saved_capture", preview_write == OK and preview_copy.contains("Capture from the connected running game") and preview_button != null)
	if preview_button != null:
		preview_button.pressed.emit()
		await get_tree().process_frame
		var capture_sheet: Node = main.projects.find_child("ProjectCaptureSheet", true, false)
		_check("U9D2_saved_game_capture_opens_in_review_sheet", capture_sheet != null)
		if capture_sheet != null and capture_sheet.has_method("close"):
			capture_sheet.call("close")
			await get_tree().process_frame
	var restored_project: Dictionary = Store.get_project(project_id)
	restored_project.erase("preview_path")
	restored_project.erase("preview_kind")
	restored_project.erase("project_kind")
	Store.save_project(restored_project)
	DirAccess.remove_absolute(home_capture_path)
	main.projects.open_project(project_id)
	# Continuing from Project Home must reopen the most recent build conversation
	# for this project instead of creating a duplicate thread.
	var existing_build := Store.new_session("build", project_id)
	existing_build["title"] = "Sticker shop build"
	existing_build["messages"] = [{"role":"user", "content":"Continue the sticker shop"}]
	Store.save_session(existing_build, true)
	var session_count_before_continue := Store.list_sessions().size()
	main._continue_project_chat(project_id)
	_check("U9E_continue_project_reuses_existing_build_conversation", str(chat.session.get("id", "")) == str(existing_build.get("id", "")) and Store.list_sessions().size() == session_count_before_continue and main.tab == "chat")
	main.projects.open_project(project_id)
	main.projects._show_work_details = true
	main.projects.render()
	var work_details_copy := _text(main.projects)
	_check("U9F_work_details_preserves_status_activity_tasks_and_notes", work_details_copy.contains("Work status") and work_details_copy.contains("Recent activity") and work_details_copy.contains("Tasks") and work_details_copy.contains("Notes") and work_details_copy.contains("Draw 5 designs"))
	_check("U9G_work_details_does_not_duplicate_notes_section", work_details_copy.count("Notes") == 1)
	main.projects.open_project(project_id)
	# Regenerate re-asks and replaces the last answer
	var before: int = Store.load_session(str(chat.session["id"]))["messages"].size()
	chat.regenerate()
	await _wait_idle()
	_check("U10_regenerate_replaces_last_answer", Store.load_session(str(chat.session["id"]))["messages"].size() == before)
	# Plan with Aoi: new money-mode session with project context
	main._plan_with_aoi(str(p["id"]))
	await _wait_idle()
	var s2: Dictionary = chat.session
	_check("U11_plan_with_aoi_uses_project_context", str(s2["mode"]) == "money" and str(s2["project_id"]) == str(p["id"]) and (s2["messages"] as Array).size() == 2)
	# Persistence: restart the store, everything is still there
	var sid := str(s2["id"])
	Store.load_all()
	_check("U12_restart_keeps_key_chats_projects", Store.has_key("openrouter") and Store.load_session(sid)["messages"].size() == 2 and Store.list_projects().size() == 1)
	# Cancel mid-stream
	chat.new_session()
	chat.send_text("SLOW cancel me")
	await _wait(0.7)
	var thinking_status := chat.find_child("AoiThinkingStatus", true, false) as HBoxContainer
	_check("U13A_slow_chat_shows_animated_truthful_thinking_state", thinking_status != null and chat._stream_status_label != null and chat._stream_status_label.text == "Thinking" and chat._stream_presence != null and chat._stream_presence.call("get_state") == "thinking")
	chat._on_send_pressed()   # the send button is the stop button while streaming
	await _wait(0.4)
	_check("U13_stop_button_cancels", not LLM.busy)
	chat.new_session()
	chat.send_text("SLOW system back")
	await _wait(0.7)
	var back_session_id := str(chat.session.get("id", ""))
	main._handle_back_request()
	var back_session := Store.load_session(back_session_id)
	_check("U13B_android_back_stops_and_persists_active_reply", not LLM.busy and main.tab == "chat" and _text(chat._msgs).contains("Response stopped before any text arrived.") and (back_session.get("messages", []) as Array).any(func(message): return str(message.get("content", "")).contains("Response stopped before any text arrived.")))
	# Delete all data
	main._wipe()
	_check("U14_delete_all_data", Store.list_sessions().is_empty() and Store.list_projects().is_empty() and not Store.has_key("openrouter"))
	_check("U15_linux_bridge_setup_signal", main.explore.has_signal("request_linux_config"))
	_check("U16_connections_prioritise_native_tools_and_collapse_external_services", _text(main.explore).contains("Cloud Linux workspace") and _text(main.explore).contains("Browse 22 external services") and not _text(main.explore).contains("GitHub Codespaces"))
	var browse_external := main.explore.find_child("BrowseExternalServices", true, false) as Button
	if browse_external != null: browse_external.pressed.emit()
	_check("U16E_external_services_remain_browsable_on_demand", browse_external != null and _text(main.explore).contains("GitHub Codespaces") and _text(main.explore).contains("Puter AI"))
	var collapse_external := main.explore.find_child("CollapseExternalServices", true, false) as Button
	if collapse_external != null: collapse_external.pressed.emit()
	await get_tree().process_frame
	_check("U16A_cloud_runtime_does_not_imply_personal_pc_pairing", not _text(main.explore).contains("Linux device connected") and _text(main.explore).contains("Cloud Linux workspace"))
	if main.explore._search != null:
		main.explore._search.text = "Puter"
		main.explore._search.text_changed.emit("Puter")
	await get_tree().process_frame
	_check("U16F_collapsed_external_services_remain_searchable", _text(main.explore).contains("Puter AI") and _text(main.explore).contains("Search results"))
	if main.explore._search != null:
		main.explore._search.text = ""
		main.explore._search.text_changed.emit("")
	await get_tree().process_frame
	main.explore._show_integration_details({"id":"linux_bridge", "name":"Cloud Linux workspace", "eyebrow":"REMOTE PROJECT RUNTIME", "category":"Workspaces", "description":"Connect Aoi to GitHub Codespaces for remote Godot work.", "detail":"HTTPS bridge · Codespaces quota applies", "action":"Connect cloud workspace", "url":"", "icon":"terminal", "featured":true})
	await get_tree().process_frame
	var linux_details_found := main.explore._detail_sheet != null and _text(main.explore._detail_sheet).contains("GitHub Codespaces") and _text(main.explore._detail_sheet).contains("Connect cloud workspace")
	_check("U16B_cloud_workspace_has_a_clear_existing_connection_entry", linux_details_found)
	if main.explore._detail_sheet != null: main.explore._detail_sheet.queue_free(); main.explore._detail_sheet = null
	main._configure_linux()
	await get_tree().process_frame
	var cloud_sheet := main.get_child(main.get_child_count() - 1) as Control
	var linux_config_copy := _text(cloud_sheet)
	_check("U16C_cloud_setup_explains_codespaces_secret_and_phone_independence", linux_config_copy.contains("GitHub Codespaces") and linux_config_copy.contains("AOI_BRIDGE_TOKEN") and linux_config_copy.contains("build machine runs in GitHub's cloud") and linux_config_copy.contains("not on your phone or personal computer"))
	cloud_sheet.queue_free()
	main.go("explore")
	await get_tree().process_frame
	_check("U16D_explore_uses_one_phone_friendly_category_selector", main.explore._category_select != null and main.explore._category_select.item_count == main.explore.CATEGORIES.size() and main.explore._category_select.size.x > 0)
	_check("U17_agent_workflow_is_registered", main.workflow != null and main.workflow.has_signal("run_task_requested"))
	# A saved cloud key exposes the authenticated health-check action.
	Store.set_integration("linux_bridge", {"url":"https://aoi-test-8765.app.github.dev", "target":"codespaces", "provider":"github_codespaces"})
	Store.set_secret("linux_bridge", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
	main.explore._show_integration_details({"id":"linux_bridge", "name":"Cloud Linux workspace", "eyebrow":"REMOTE PROJECT RUNTIME", "category":"Workspaces", "description":"Connect Aoi to GitHub Codespaces for remote Godot work.", "detail":"HTTPS bridge · Codespaces quota applies", "action":"Connect cloud workspace", "url":"", "icon":"terminal", "featured":true})
	await get_tree().process_frame
	var linux_test_button := main.explore._detail_sheet.find_child("LinuxBridgeTestButton", true, false) as Button if main.explore._detail_sheet != null else null
	_check("U18_saved_cloud_workspace_exposes_authenticated_health_check", linux_test_button != null and not linux_test_button.disabled and _text(main.explore._detail_sheet).contains("Permissions and safety"))
	Store.remove_secret("linux_bridge")
	Store.set_integration("linux_bridge", {})
	var flow_project := Store.new_project("Review-gated workflow", "Build a reliable small app")
	var ui_plan_tasks: Array = []
	for plan_index in range(5):
		var plan_title: String = ["Define the application scope", "Build the application foundation", "Implement the main user experience", "Add supporting flows and storage", "Verify and polish the finished result"][plan_index]
		var plan_detail: String = [
			"Inspect the project requirements, entry points, target runtime and constraints before documenting the complete delivery scope.",
			"Create the shared application structure, navigation foundation and reusable resources while preserving the current project conventions.",
			"Implement the primary user-facing flow with complete inputs, meaningful states and the core behavior requested for this project.",
			"Implement supporting screens, preferences, error states and durable persistence for all user-created information.",
			"Review the finished experience, run its supported checks, inspect fresh screenshots and correct acceptance gaps before delivery."
		][plan_index]
		var plan_acceptance: String = [
			"The scope describes the main experience, supporting flows and what qualifies as a complete delivery.",
			"The app opens through its entry point and the primary navigation routes load without missing resources.",
			"A user can complete the main flow from entry to the intended result without placeholder actions.",
			"Supporting flows remain usable and saved user data survives a close and reopen cycle.",
			"The agreed user-facing flows work and every remaining limitation is documented honestly."
		][plan_index]
		ui_plan_tasks.append({"title":plan_title, "detail":plan_detail, "deliverables":[plan_title + " output"], "role":"Engineer" if plan_index in [1,2,3] else ("Planner" if plan_index == 0 else "Reviewer"), "priority":"high", "acceptance":plan_acceptance, "verification":"Inspect the relevant application state, run a focused runtime check and compare the result against the stated acceptance criteria.", "file_scope":["project scope"], "depends_on":[] if plan_index == 0 else [str(ui_plan_tasks[plan_index-1].get("title", ""))]})
	AgentFlow.apply_plan(str(flow_project.id), {"summary":"Deliver a complete small app through discovery, implementation, supporting flows and verified release.", "tasks":ui_plan_tasks})
	var flow_data: Dictionary = AgentFlow.get_flow(str(flow_project.id))
	AgentFlow.update_task(str(flow_project.id), str(flow_data.tasks[0].id), {"status":"in_progress", "role":"Engineer", "title":"First task"})
	AgentFlow.update_task(str(flow_project.id), str(flow_data.tasks[0].id), {"status":"review", "role":"Engineer", "title":"First task"})
	main.workflow.open_project(str(flow_project.id)); main.go("workflow")
	_check("U19_workflow_has_human_review_gate", _text(main.workflow).contains("Approve result") and _text(main.workflow).contains("Request changes"))
	_check("U20_workflow_exposes_project_knowledge", _text(main.workflow).contains("Project knowledge") and _text(main.workflow).contains("Add note"))
	var workflow_project_id := str(flow_project.id)
	var workflow_tasks: Array = AgentFlow.get_flow(workflow_project_id).get("tasks", [])
	var owned_task_id := str(workflow_tasks[0].get("id", ""))
	var owned_session := Store.new_session("build", workflow_project_id)
	Store.save_session(owned_session, true)
	var owned_session_id := str(owned_session.get("id", ""))
	AgentFlow.update_task(workflow_project_id, owned_task_id, {"status":"in_progress", "session_id":owned_session_id, "role":"Engineer", "title":"First task"})
	chat.assistant_answer_finished.emit(workflow_project_id, owned_task_id, "another-session", "Unrelated project reply")
	var task_after_unrelated_reply: Dictionary = AgentFlow.get_flow(workflow_project_id).get("tasks", [])[0]
	_check("U20A_unrelated_project_chat_cannot_complete_workflow_task", str(task_after_unrelated_reply.get("status", "")) == "in_progress")
	chat.assistant_answer_finished.emit(workflow_project_id, owned_task_id, owned_session_id, "Task work is ready for your review.")
	var task_after_owned_reply: Dictionary = AgentFlow.get_flow(workflow_project_id).get("tasks", [])[0]
	var review_chat_button := main.workflow.find_child("OpenWorkflowTaskChat", true, false) as Button
	var review_result_preview := main.workflow.find_child("WorkflowTaskResultPreview", true, false) as Label
	_check("U20B_owned_task_completion_surfaces_result_preview_for_review", str(task_after_owned_reply.get("status", "")) == "review" and str(task_after_owned_reply.get("review_summary", "")) == "Task work is ready for your review." and review_result_preview != null and review_result_preview.text == "Task work is ready for your review." and review_chat_button != null and _text(main.workflow).contains("Review task chat"))
	if review_chat_button != null: review_chat_button.pressed.emit()
	_check("U20C_review_action_reopens_the_exact_task_conversation", str(chat.session.get("id", "")) == owned_session_id and main.tab == "chat")
	var background_task_session := Store.new_session("build", workflow_project_id)
	background_task_session["workflow_task_id"] = owned_task_id
	Store.save_session(background_task_session, true)
	var background_task_session_id := str(background_task_session.get("id", ""))
	AgentFlow.update_task(workflow_project_id, owned_task_id, {"status":"in_progress", "session_id":background_task_session_id, "role":"Engineer", "title":"First task"})
	var foreground_session := Store.new_session("chat")
	Store.save_session(foreground_session, true)
	chat.open_session(str(foreground_session.get("id", "")))
	chat._stream_request_active = true
	chat._stream_session_id = background_task_session_id
	chat._stream_project_id = workflow_project_id
	chat._on_finished({"ok":true, "text":"Background task result is ready for your review.", "tool_calls":[]})
	var background_task_result: Dictionary = AgentFlow.get_flow(workflow_project_id).get("tasks", [])[0]
	_check("U20C1_background_task_completion_updates_its_owner_after_chat_switch", str(background_task_result.get("status", "")) == "review" and str(background_task_result.get("review_summary", "")) == "Background task result is ready for your review." and str(chat.session.get("id", "")) == str(foreground_session.get("id", "")))
	AgentFlow.approve_task(workflow_project_id, owned_task_id)
	var remaining_task: Dictionary = AgentFlow.get_flow(workflow_project_id).get("tasks", [])[1]
	main._run_workflow_task(workflow_project_id, remaining_task)
	var blocked_task: Dictionary = AgentFlow.get_flow(workflow_project_id).get("tasks", [])[1]
	_check("U20D_workflow_task_requires_a_provider_before_becoming_active", str(blocked_task.get("status", "")) == "todo" and str(blocked_task.get("session_id", "")) == "" and main.tab == "setup")
	setup.connect_provider("openrouter", "good-key")
	await _wait(1.5)
	var runnable_task: Dictionary = AgentFlow.get_flow(workflow_project_id).get("tasks", [])[1]
	main._run_workflow_task(workflow_project_id, runnable_task)
	await _wait_idle()
	var executed_task: Dictionary = AgentFlow.get_flow(workflow_project_id).get("tasks", [])[1]
	var executed_session_id := str(executed_task.get("session_id", ""))
	_check("U20E_workflow_execution_persists_its_exact_chat_and_review_state", str(executed_task.get("status", "")) == "review" and str(executed_task.get("review_summary", "")) != "" and executed_session_id != "" and str(chat.session.get("id", "")) == executed_session_id and str(chat.session.get("workflow_task_id", "")) == str(executed_task.get("id", "")) and (chat.session.get("messages", []) as Array).size() >= 2)
	main.workflow.open_project(workflow_project_id)
	main.go("workflow")
	var executed_review_chat := main.workflow.find_child("OpenWorkflowTaskChat", true, false) as Button
	if executed_review_chat != null: executed_review_chat.pressed.emit()
	_check("U20F_review_reopens_the_persisted_execution_conversation", executed_review_chat != null and str(chat.session.get("id", "")) == executed_session_id and main.tab == "chat")
	var failed_attempt_session := Store.new_session("build", workflow_project_id)
	failed_attempt_session["workflow_task_id"] = str(executed_task.get("id", ""))
	Store.save_session(failed_attempt_session, true)
	var failed_attempt_session_id := str(failed_attempt_session.get("id", ""))
	AgentFlow.update_task(workflow_project_id, str(executed_task.get("id", "")), {"status":"in_progress", "session_id":failed_attempt_session_id, "role":"Engineer", "title":str(executed_task.get("title", ""))})
	chat.open_session(failed_attempt_session_id)
	chat._stream_request_active = true
	chat._stream_session_id = failed_attempt_session_id
	chat._stream_project_id = workflow_project_id
	chat._stream_widget = VBoxContainer.new()
	chat._msgs.add_child(chat._stream_widget)
	chat._on_finished({"ok":false, "error":"Temporary provider failure", "text":"", "tool_calls":[]})
	var retryable_task: Dictionary = AgentFlow.get_flow(workflow_project_id).get("tasks", [])[1]
	main.workflow.open_project(workflow_project_id)
	main.go("workflow")
	_check("U20G_failed_task_returns_to_retry_with_previous_chat", str(retryable_task.get("status", "")) == "todo" and str(retryable_task.get("last_error", "")) == "Temporary provider failure" and _text(main.workflow).contains("Retry task") and _text(main.workflow).contains("Last attempt stopped") and main.workflow.find_child("OpenWorkflowTaskChat", true, false) is Button)
	var searchable_session := Store.new_session("chat")
	searchable_session["title"] = "Ceramic shop launch"
	searchable_session["messages"] = [{"role":"user", "content":"Help me create a weekly launch schedule for my ceramic shop."}]
	Store.save_session(searchable_session, true)
	main.open_sessions()
	var history_search := main.find_child("ConversationSearchField", true, false) as LineEdit
	if history_search != null: history_search.text = "weekly launch schedule"; history_search.text_changed.emit(history_search.text)
	await _wait(0.25)
	var history_results := main.find_child("ConversationSearchResults", true, false) as VBoxContainer
	_check("U20H_chat_search_finds_message_content_and_shows_context", history_search != null and history_results != null and _text(history_results).contains("Ceramic shop launch") and _text(history_results).contains("weekly launch schedule"))
	var rename_conversation := main.find_child("RenameConversationButton", true, false) as Button
	var rename_action_available := rename_conversation != null
	if rename_conversation != null: rename_conversation.pressed.emit()
	var rename_dialog := main.find_child("ConversationRenameField", true, false) as LineEdit
	var rename_editor_opened := rename_dialog != null
	var blank_title_disables_save := false
	var valid_title_enables_save := false
	if rename_dialog != null:
		rename_dialog.text = "   "
		rename_dialog.text_changed.emit(rename_dialog.text)
		blank_title_disables_save = (rename_dialog.get_parent() as AcceptDialog).get_ok_button().disabled
		rename_dialog.text = "Clay shop launch"
		rename_dialog.text_changed.emit(rename_dialog.text)
		valid_title_enables_save = not (rename_dialog.get_parent() as AcceptDialog).get_ok_button().disabled
		(rename_dialog.get_parent() as AcceptDialog).confirmed.emit()
		(rename_dialog.get_parent() as AcceptDialog).hide()
		(rename_dialog.get_parent() as AcceptDialog).queue_free()
	await get_tree().process_frame
	var renamed_session := Store.load_session(str(searchable_session.get("id", "")))
	var renamed_title := str(renamed_session.get("title", ""))
	var renamed_card_visible := _text(history_results).contains("Clay shop launch")
	_check("U20H1_history_renames_and_persists_conversations", rename_action_available and rename_editor_opened and renamed_title == "Clay shop launch" and renamed_card_visible and blank_title_disables_save and valid_title_enables_save, "button=%s field=%s saved_title=%s card_visible=%s blank_disabled=%s valid_enabled=%s" % [rename_action_available, rename_editor_opened, renamed_title, renamed_card_visible, blank_title_disables_save, valid_title_enables_save])
	var pin_conversation := main.find_child("PinConversationButton", true, false) as Button
	var pin_action_available := pin_conversation != null
	if pin_conversation != null: pin_conversation.pressed.emit()
	var pinned_session := Store.load_session(str(searchable_session.get("id", "")))
	var pinned_sessions := Store.list_sessions()
	var pinned_to_top := not pinned_sessions.is_empty() and str(pinned_sessions[0].get("id", "")) == str(searchable_session.get("id", ""))
	_check("U20H2_pinned_conversations_move_above_recent_chats", pin_action_available and bool(pinned_session.get("pinned", false)) and pinned_to_top and _text(history_results).contains("Pinned"))
	var drawer_preview := VBoxContainer.new()
	main.add_child(drawer_preview)
	main._render_drawer_sessions(drawer_preview, "")
	_check("U20H4_navigation_drawer_marks_pinned_conversations", _text(drawer_preview).contains("Pinned"))
	drawer_preview.queue_free()
	await get_tree().process_frame
	var unpin_conversation := main.find_child("PinConversationButton", true, false) as Button
	if unpin_conversation != null: unpin_conversation.pressed.emit()
	var unpinned_session := Store.load_session(str(searchable_session.get("id", "")))
	_check("U20H3_conversations_can_be_unpinned", unpin_conversation != null and not bool(unpinned_session.get("pinned", false)))
	var delete_conversation := main.find_child("DeleteConversationButton", true, false) as Button
	if delete_conversation != null: delete_conversation.pressed.emit()
	var confirm_delete := main.find_child("ConfirmActionButton", true, false) as Button
	_check("U20I_history_deletion_requires_explicit_confirmation", Store.load_session(str(searchable_session.get("id", ""))).size() > 0 and confirm_delete != null)
	if confirm_delete != null: confirm_delete.pressed.emit()
	await get_tree().process_frame
	_check("U20J_confirmed_history_deletion_removes_the_saved_conversation", Store.load_session(str(searchable_session.get("id", ""))).is_empty())
	var history_sheet_panel := main.find_child("SheetPanel", true, false) as PanelContainer
	if history_sheet_panel != null: history_sheet_panel.get_parent().call("close")
	Store.remove_key("openrouter")
	main.workflow.open_project(workflow_project_id)
	main.go("workflow")
	var multiline_project := Store.new_project("Multiline goal", "A deliberately long project goal that must remain readable and editable on a narrow mobile screen.")
	main.projects.open_project(str(multiline_project.id))
	main.projects._on_project_menu_action(3) # Edit project details
	var goal_editor := main.projects.find_child("ProjectGoalEditor", true, false) as TextEdit
	_check("U21_project_goal_uses_multiline_editor", goal_editor != null and goal_editor.wrap_mode == TextEdit.LINE_WRAPPING_BOUNDARY)
	var delete_position: int = main.projects._project_menu.get_item_index(1) if main.projects._project_menu is PopupMenu else -1
	_check("U35_project_delete_is_in_context_menu", main.projects._project_menu is PopupMenu and delete_position >= 0 and main.projects._project_menu.get_item_text(delete_position) == "Delete project")
	# Safe-area mapping regression: physical display pixels must be converted on
	# both axes, including a centred top camera cutout and a right-side inset.
	var portrait_insets: Dictionary = main._compute_safe_insets(
		Rect2i(0, 24, 720, 1436), Vector2i(720, 1520), Vector2i.ZERO,
		Vector2i(720, 1520), Vector2(720, 1520), [Rect2(280, 0, 160, 42)]
	)
	_check("U22_top_cutout_safe_inset", int(portrait_insets.top) >= 52)
	_check("U23_bottom_gesture_safe_inset", int(portrait_insets.bottom) == 60)
	var side_insets: Dictionary = main._compute_safe_insets(
		Rect2i(24, 40, 672, 1440), Vector2i(720, 1520), Vector2i.ZERO,
		Vector2i(720, 1520), Vector2(720, 1520)
	)
	_check("U24_left_right_camera_grip_insets", int(side_insets.left) == 24 and int(side_insets.right) == 24)
	var scaled_insets: Dictionary = main._compute_safe_insets(
		Rect2i(36, 90, 1008, 2220), Vector2i(1080, 2400), Vector2i.ZERO,
		Vector2i(1080, 2400), Vector2(720, 1600)
	)
	_check("U25_density_scaling_is_independent_on_both_axes", int(scaled_insets.left) == 24 and int(scaled_insets.top) == 60 and int(scaled_insets.right) == 24 and int(scaled_insets.bottom) == 60)
	# Long drafts should not let the composer grow without limit.
	var draft_lines := PackedStringArray()
	for i in range(12): draft_lines.append("line %d" % i)
	chat._input.text = "\n".join(draft_lines)
	chat._fit_input()
	_check("U26_composer_growth_is_capped", chat._input.custom_minimum_size.y <= 144.0 and chat._input.custom_minimum_size.y > 58.0)
	_check("U27_composer_keeps_phone_gutters", chat._input.size_flags_horizontal == Control.SIZE_EXPAND_FILL)
	# First-run send must route to Setup without discarding the typed message.
	chat._input.text = "Keep this draft until a model is connected"
	chat._on_send_pressed()
	_check("U28_first_run_send_preserves_draft", chat._input.text == "Keep this draft until a model is connected")
	# A personal library exists independently from project-specific knowledge.
	main.go("knowledge")
	var note := Store.add_knowledge("UI review checklist", "Inspect cutouts, composer, keyboard behavior and bottom gesture area.", ["mobile", "quality"], "chat")
	main.knowledge._render_results()
	_check("U29_knowledge_library_is_a_main_screen", main.knowledge != null and main.knowledge.visible and main.tab == "knowledge" and _text(main.knowledge).contains("Notes and answers"))
	_check("U30_knowledge_library_renders_searchable_notes", not note.is_empty() and _text(main.knowledge).contains("UI review checklist"))
	_check("U31_knowledge_library_has_search_input", main.knowledge._search != null and main.knowledge._search.placeholder_text.contains("Search"))
	Store.add_knowledge("Godot safe-area reference", "Respect the camera cutout, Android gesture area, display safe-area insets and keyboard before laying out chat controls.", ["Godot", "Android", "mobile"], "manual")
	chat.session["messages"] = [{"role":"user", "content":"How should I handle a camera cutout on Android?"}]
	var knowledge_context: Array = chat._history()
	_check("U32_relevant_personal_knowledge_enters_chat_context", not knowledge_context.is_empty() and str(knowledge_context[0].get("content", "")).contains("Godot safe-area reference"))
	_check("U33_global_knowledge_save_needs_approval", _approval_required("knowledge.save") and not _approval_required("knowledge.search"))
	var android_tool_probe := ChatScreenForPolicy.new()
	var android_tool_definitions := android_tool_probe._build_native_tool_definitions(ChatScreenForPolicy._android_tool_descriptions())
	var android_native_names: Array[String] = []
	for definition in android_tool_definitions:
		android_native_names.append(str(definition.get("function", {}).get("name", "")))
	android_tool_probe._request_tool_definitions = android_tool_definitions
	android_tool_probe.session = {"mode":"chat", "project_id":""}
	var invalid_alarm_request := android_tool_probe._normalise_tool_request("aoi_android__set_alarm", {"hour":24, "minute":0})
	var invalid_event_request := android_tool_probe._normalise_tool_request("aoi_android__add_calendar_event", {"title":"Event", "year":2026, "month":2, "day":31, "hour":9, "minute":0, "duration_minutes":30})
	_check("U33A_android_clock_and_calendar_tools_are_native_calls_and_mutations_need_approval",
		android_native_names == ["aoi_android__set_alarm", "aoi_android__add_calendar_event"]
		and _approval_required("android.set_alarm") and _approval_required("android.add_calendar_event")
		and not ChatScreenForPolicy._role_allows_tool("Researcher", "android.set_alarm")
		and not invalid_alarm_request.get("ok", true) and not invalid_event_request.get("ok", true))
	android_tool_probe.free()
	chat.request_save_to_library.emit("## A reusable answer\nPreserve this as a durable personal note.")
	await get_tree().process_frame
	_check("U34_save_from_chat_opens_library_editor", main.knowledge.visible and main.knowledge._editor_window != null and is_instance_valid(main.knowledge._editor_window))
	if main.knowledge._editor_window != null and is_instance_valid(main.knowledge._editor_window): main.knowledge._editor_window.queue_free()
	# Aoi Studio: dedicated Godot build workspace, project scaffolding, source tree,
	# build-mode chat context and an explicit logs-inclusion control.
	main.go("studio")
	_check("U36_aoi_studio_is_a_first_class_screen", main.studio != null and main.studio.visible and main.studio.embedded_chat != null)
	main.studio._create_local_workspace("Studio regression", "Build a small 2D platformer with a controllable character.")
	await get_tree().process_frame
	var studio_project_id := str(main.studio._selected_project.get("id", ""))
	var studio_project := Store.get_project(studio_project_id)
	var studio_root: String = main.studio._local_project_absolute_path()
	_check("U37_studio_creates_a_real_godot_project", FileAccess.file_exists(studio_root.path_join("project.godot")) and FileAccess.file_exists(studio_root.path_join("scenes/main.tscn")))
	var escaped_project_title := "Quoted \"title\"\n[rendering]\nrenderer/rendering_method=\"mobile\""
	main.studio._create_local_workspace(escaped_project_title, "Verify project names cannot inject config sections.")
	await get_tree().process_frame
	var escaped_project_id := str(main.studio._selected_project.get("id", ""))
	var escaped_project_root: String = main.studio._local_project_absolute_path()
	var escaped_config := ConfigFile.new()
	var escaped_config_error := escaped_config.load(escaped_project_root.path_join("project.godot"))
	_check("U37D_studio_escapes_project_names_in_godot_config", escaped_config_error == OK and str(escaped_config.get_value("application", "config/name", "")) == escaped_project_title.replace("\n", " ") and str(escaped_config.get_value("rendering", "renderer/rendering_method", "")) == "gl_compatibility")
	main.studio._create_local_workspace("", "This should not create a workspace.")
	_check("U37E_studio_rejects_empty_project_name", str(main.studio._selected_project.get("id", "")) == escaped_project_id)
	main.studio._create_local_workspace("Missing goal", "")
	_check("U37F_studio_rejects_empty_project_goal", str(main.studio._selected_project.get("id", "")) == escaped_project_id)
	main.studio._remove_tree(escaped_project_root)
	Store.delete_project(escaped_project_id)
	main.studio.select_project(studio_project)
	main.studio._create_starter_2d_scene()
	await get_tree().process_frame
	var prototype_scene := load(studio_root.path_join("scenes/platformer_prototype.tscn")) as PackedScene
	var prototype_instance: Node = prototype_scene.instantiate() if prototype_scene != null else null
	_check("U37A_studio_builds_native_platformer_scene", prototype_instance != null and prototype_instance.get_child_count() == 3)
	if prototype_instance != null: prototype_instance.free()
	main.studio._preview_local_scene()
	await get_tree().process_frame
	var preview_window_found := false
	for child in main.studio.get_children():
		if child is Window and child.title == "Aoi local scene preview": preview_window_found = true; child.queue_free()
	_check("U37B_local_scene_preview_opens_without_pc", preview_window_found)
	_check("U37C_godot_api_explorer_indexes_live_engine", GodotSandbox.search_classes("CharacterBody2D", 5).size() == 1 and GodotSandbox.inspect_class("CharacterBody2D").get("ok", false))
	main.studio._show_api_explorer()
	await get_tree().process_frame
	var api_window: Window = null
	for child in main.studio.get_children():
		if child is Window and str(child.title).begins_with("Godot API Explorer"): api_window = child
	var api_tree: Tree = api_window.find_child("APIClassTree", true, false) as Tree if api_window != null else null
	var api_detail: Label = api_window.find_child("APISelectedMemberDetail", true, false) as Label if api_window != null else null
	var api_search: LineEdit = api_window.find_child("APIClassSearch", true, false) as LineEdit if api_window != null else null
	var change_class: Button = api_window.find_child("APIChangeClass", true, false) as Button if api_window != null else null
	if change_class != null: change_class.pressed.emit()
	if api_search != null: api_search.text = "CharacterBody2D"; api_search.text_changed.emit("CharacterBody2D")
	await get_tree().process_frame
	var api_item: TreeItem = api_tree.get_root().get_first_child() if api_tree != null and api_tree.get_root() != null else null
	if api_item != null: api_tree.set_selected(api_item, 0); api_tree.item_selected.emit()
	await get_tree().process_frame
	var api_member_search: LineEdit = api_window.find_child("APIMemberSearch", true, false) as LineEdit if api_window != null else null
	if api_member_search != null: api_member_search.text = "move_and_slide"; api_member_search.text_changed.emit("move_and_slide")
	await get_tree().process_frame
	_check("U37D_api_explorer_filters_and_displays_exact_method_signature", api_window != null and api_item != null and api_detail != null and api_detail.text.contains("move_and_slide"))
	var api_properties: Button = api_window.find_child("APICategory_Properties", true, false) as Button if api_window != null else null
	if api_properties != null: api_properties.pressed.emit()
	await get_tree().process_frame
	var api_results: Label = api_window.find_child("APIResults", true, false) as Label if api_window != null else null
	_check("U37E_api_explorer_switches_member_categories", api_properties != null and api_results != null and api_results.text.to_lower().contains("properties"))
	if api_window != null: api_window.queue_free()
	_check("U38_studio_chat_is_bound_to_project_build_mode", str(main.studio.embedded_chat.session.get("mode", "")) == "build" and str(main.studio.embedded_chat.session.get("project_id", "")) == studio_project_id)
	var stale_generic_session := Store.new_session("chat", "")
	stale_generic_session["messages"] = [{"role":"user", "content":"Build a game: test stale session binding"}]
	Store.save_session(stale_generic_session, true)
	var project_with_stale_session := Store.get_project(studio_project_id)
	project_with_stale_session["studio_session_id"] = str(stale_generic_session.get("id", ""))
	Store.save_project(project_with_stale_session)
	main.studio.select_project(project_with_stale_session, true)
	var rebound_session_id := str(main.studio.embedded_chat.session.get("id", ""))
	_check("U38A_studio_replaces_unbound_generic_session", rebound_session_id != str(stale_generic_session.get("id", "")) and str(main.studio.embedded_chat.session.get("mode", "")) == "build" and str(main.studio.embedded_chat.session.get("project_id", "")) == studio_project_id)
	var project_after_rebind := Store.get_project(studio_project_id)
	main.studio.select_project(project_after_rebind, true)
	_check("U38B_studio_reuses_persisted_project_session", str(main.studio.embedded_chat.session.get("id", "")) == rebound_session_id and str(Store.load_session(rebound_session_id).get("project_id", "")) == studio_project_id)
	var native_history: Array = main.studio.embedded_chat._history()
	var tool_names: Array[String] = []
	for definition in main.studio.embedded_chat._request_tool_definitions:
		tool_names.append(str(definition.get("function", {}).get("name", "")))
	_check("U38C_native_project_tools_are_advertised", tool_names.has("aoi_project__inspect") and tool_names.has("aoi_project__read_file"))
	var scoped_inspect: Dictionary = main.studio.embedded_chat._normalise_tool_request("aoi_project__inspect", {})
	var blocked_cross_project: Dictionary = main.studio.embedded_chat._normalise_tool_request("aoi_project__inspect", {"project_id":"another-project"})
	_check("U38D_project_tools_are_scoped_to_selected_project", bool(scoped_inspect.get("ok", false)) and str(scoped_inspect.get("data", {}).get("project_id", "")) == studio_project_id and not bool(blocked_cross_project.get("ok", true)))
	_check("U38E_studio_removes_duplicate_project_banner", not main.studio.embedded_chat._banner.visible and not main.studio.embedded_chat._project_banner_visible)
	var studio_preferences := Store.get_integration("studio")
	studio_preferences["include_logs"] = true
	studio_preferences["last_logs"] = "RESTORE_LOG_CONTEXT"
	Store.set_integration("studio", studio_preferences)
	main.studio._selected_project = {}
	main.studio.activate()
	_check("U38F_studio_restores_project_chat_after_reentry", str(main.studio.embedded_chat.session.get("id", "")) == rebound_session_id and str(main.studio.embedded_chat.session.get("project_id", "")) == studio_project_id and bool(Store.get_integration("studio").get("include_logs", false)))
	var chat_for_switch: ChatScreenForPolicy = main.studio.embedded_chat as ChatScreenForPolicy
	var switch_session_id := str(chat_for_switch.session.get("id", ""))
	(chat_for_switch.session["messages"] as Array).append({"role":"assistant", "content":null, "tool_calls":[{"id":"pending-approval-regression", "type":"function", "function":{"name":"aoi_project__write_file", "arguments":"{}"}}], "internal":true})
	Store.save_session(chat_for_switch.session, true)
	chat_for_switch._tool_session_id = switch_session_id
	chat_for_switch._tool_project_id = studio_project_id
	chat_for_switch._active_native_call_id = "pending-approval-regression"
	chat_for_switch._native_tool_cycle = true
	chat_for_switch._pending_tool_data = {"name":"project.write_file", "path":"unsafe.txt"}
	chat_for_switch._show_tool_approval({"name":"project.write_file", "path":"scripts/pending.gd", "content":"extends Node\n"})
	chat_for_switch._resolve_pending_tool_before_session_switch()
	var switched_owner := Store.load_session(switch_session_id)
	var saved_decision: Dictionary = switched_owner.get("pending_approval", {})
	var resolved_history: Array = switched_owner.get("messages", [])
	var approval_was_not_executed := not resolved_history.any(func(message): return str(message.get("role", "")) == "tool" and str(message.get("tool_call_id", "")) == "pending-approval-regression")
	_check("U38G_pending_approval_survives_leaving_its_conversation", str(saved_decision.get("tool_data", {}).get("path", "")) == "scripts/pending.gd" and approval_was_not_executed)
	chat_for_switch._restore_pending_approval()
	var messages_before_guard := (chat_for_switch.session.get("messages", []) as Array).size()
	chat_for_switch._tool_session_id = switch_session_id
	chat_for_switch._tool_project_id = studio_project_id
	chat_for_switch._pending_tool_data = {"name":"project.write_file"}
	# Simulate a provider key being removed while the approval remains open.
	var saved_key := Store.get_key("openrouter")
	Store.remove_key("openrouter")
	chat_for_switch.send_text("Continue the project while that permission is waiting")
	var deferred_messages: Array = chat_for_switch.session.get("deferred_user_messages", [])
	_check("U38H_chat_accepts_follow_up_while_approval_is_pending", (chat_for_switch.session.get("messages", []) as Array).size() == messages_before_guard and deferred_messages.size() == 1 and str(deferred_messages[0].get("content", "")).contains("Continue the project"))
	_check("U38I_approval_queue_survives_session_reload", Store.load_session(switch_session_id).get("deferred_user_messages", []).size() == 1)
	Store.set_key("openrouter", saved_key)
	chat_for_switch._pending_tool_data = {}
	chat_for_switch._tool_session_id = switch_session_id
	chat_for_switch._tool_project_id = studio_project_id
	chat_for_switch._active_native_call_id = "pending-restore-regression"
	chat_for_switch._native_tool_cycle = true
	chat_for_switch._native_tool_queue = []
	chat_for_switch._show_tool_approval({"name":"project.write_file", "path":"scripts/feature.gd", "content":"extends Node\n"})
	var saved_approval: Dictionary = Store.load_session(switch_session_id).get("pending_approval", {})
	_check("U38J_pending_action_is_persisted_with_its_originating_call", str(saved_approval.get("active_native_call_id", "")) == "pending-restore-regression" and str(saved_approval.get("tool_data", {}).get("path", "")) == "scripts/feature.gd")
	if chat_for_switch._pending_approval_card != null: chat_for_switch._pending_approval_card.queue_free()
	chat_for_switch._pending_approval_card = null
	await get_tree().process_frame
	chat_for_switch._pending_tool_data = {}
	chat_for_switch._active_native_call_id = ""
	chat_for_switch._restore_pending_approval()
	_check("U38K_pending_action_restores_into_the_chat", str(chat_for_switch._pending_tool_data.get("path", "")) == "scripts/feature.gd" and chat_for_switch.find_child("ApprovalDecisionCard", true, false) != null)
	chat_for_switch._resolve_pending_tool_before_session_switch()
	var approval_owner_copy := Store.load_session(switch_session_id)
	_check("U38P_switching_away_keeps_the_approval_available", str(approval_owner_copy.get("pending_approval", {}).get("tool_data", {}).get("path", "")) == "scripts/feature.gd")
	var approval_chat_key := Store.get_key("openrouter")
	var approval_prior_model := Store.model
	var approval_prior_provider := Store.provider
	Store.set_key("openrouter", "good-key")
	Store.provider = "openrouter"
	Store.model = "openrouter/aoi-ui-regression:free"
	chat_for_switch.new_session("chat", "")
	await _wait_idle()
	chat_for_switch.send_text("Can you explain what this project is doing while the other action waits?")
	var approval_other_chat_tools: Array = chat_for_switch._request_tool_definitions.duplicate(true)
	await _wait_idle()
	var approval_other_chat_text := _text(chat_for_switch._msgs)
	_check("U38Q_normal_chat_works_while_another_chat_has_pending_approval", approval_other_chat_text.contains("You said: Can you explain") and approval_other_chat_tools.is_empty())
	chat_for_switch.open_session(switch_session_id)
	_check("U38R_returning_restores_the_original_approval_card", str(chat_for_switch._pending_tool_data.get("path", "")) == "scripts/feature.gd" and chat_for_switch.find_child("ApprovalDecisionCard", true, false) != null)
	if approval_chat_key == "": Store.remove_key("openrouter")
	else: Store.set_key("openrouter", approval_chat_key)
	Store.model = approval_prior_model
	Store.provider = approval_prior_provider
	if chat_for_switch._pending_approval_card != null and is_instance_valid(chat_for_switch._pending_approval_card): chat_for_switch._pending_approval_card.queue_free()
	chat_for_switch._pending_approval_card = null
	chat_for_switch._pending_tool_data = {}
	chat_for_switch.session.erase("pending_approval")
	chat_for_switch.session.erase("resume_after_approval_dismissal")
	Store.save_session(chat_for_switch.session, true)
	chat_for_switch._pending_tool_data = {}
	chat_for_switch._tool_session_id = ""
	chat_for_switch._tool_project_id = ""
	chat_for_switch.session["deferred_user_messages"] = []
	Store.save_session(chat_for_switch.session, true)
	# A running project tool keeps ownership of its source conversation while a
	# separate chat remains usable and cannot steal the tool result.
	var prior_model: String = Store.model
	var prior_provider: String = Store.provider
	var prior_key: String = Store.get_key("openrouter")
	Store.set_key("openrouter", "good-key")
	Store.provider = "openrouter"
	Store.model = "openrouter/aoi-ui-regression:free"
	var background_origin_id := str(chat_for_switch.session.get("id", ""))
	chat_for_switch._tool_session_id = background_origin_id
	chat_for_switch._tool_project_id = studio_project_id
	chat_for_switch._active_native_call_id = "background-tool-regression"
	ToolRunner.busy = true
	chat_for_switch._input.text = "Also preserve the current project settings while you work"
	chat_for_switch._on_send_pressed()
	var queued_during_run: Array = chat_for_switch.session.get("deferred_user_messages", [])
	_check("U38L_composer_queues_follow_up_during_owning_tool_run", queued_during_run.size() == 1 and str(queued_during_run[0].get("content", "")).contains("preserve the current project") and chat_for_switch._input.text == "" and str(chat_for_switch._send.icon.resource_path).contains("stop_white"))
	chat_for_switch.new_session("chat", "")
	var independent_chat_id := str(chat_for_switch.session.get("id", ""))
	var independent_chat_has_send_icon := str(chat_for_switch._send.icon.resource_path).contains("send_white")
	chat_for_switch._input.text = "Can you explain what we are building?"
	var draft_switches_icon := str(chat_for_switch._send.icon.resource_path).contains("send_white")
	chat_for_switch._on_send_pressed()
	await _wait_idle()
	_check("U38M_independent_chat_keeps_send_affordance_during_other_tool", independent_chat_has_send_icon and draft_switches_icon and ToolRunner.busy and independent_chat_id != background_origin_id and _text(chat_for_switch._msgs).contains("You said: Can you explain"))
	chat_for_switch._on_tool_state_changed("running", "Original project is still building")
	_check("U38N_background_tool_activity_stays_out_of_the_unrelated_chat", chat_for_switch._activity_strip == null and str(chat_for_switch._tool_session_id) == background_origin_id)
	ToolRunner.busy = false
	chat_for_switch._on_tool_completed({"ok":true,"tool":"project.write_file","output":"Project file saved."})
	var background_origin := Store.load_session(background_origin_id)
	_check("U38O_background_result_and_queued_message_return_to_original_chat", (background_origin.get("deferred_user_messages", []) as Array).is_empty() and bool(background_origin.get("resume_after_approval_dismissal", false)) and (background_origin.get("messages", []) as Array).any(func(message): return str(message.get("content", "")).contains("preserve the current project")))
	if prior_key == "": Store.remove_key("openrouter")
	else: Store.set_key("openrouter", prior_key)
	Store.model = prior_model
	Store.provider = prior_provider
	chat_for_switch._tool_session_id = ""
	chat_for_switch._tool_project_id = ""
	chat_for_switch.new_session("build", studio_project_id)
	var studio_files: Array = main.studio._get_visible_files()
	_check("U39_studio_source_tree_scans_project_files", studio_files.any(func(x): return str(x.get("path", "")) == "project.godot"))
	var write_callback := func(ok: bool, error_text: String): results.append(["U40_studio_project_file_write", ok and error_text == ""])
	main.studio._write_project_file("scripts/aoi_generated.gd", "extends Node\n\nfunc _ready() -> void:\n\tprint(\"Aoi Studio\")\n", write_callback)
	await get_tree().process_frame
	_check("U41_studio_writes_inside_project_root", FileAccess.file_exists(studio_root.path_join("scripts/aoi_generated.gd")))
	main.studio._set_view_mode("sources")
	_check("U42_studio_sources_view_keeps_composer_visible", main.studio.embedded_chat.visible and main.studio.embedded_chat._scroll.visible and not main.studio.embedded_chat._msgs.visible and not main.studio.embedded_chat._banner.visible and main.studio.embedded_chat._input.placeholder_text.contains("sources") and _text(main.studio._content).contains("Project files"))
	main.studio._set_view_mode("chats")
	var studio_cfg := Store.get_integration("studio")
	studio_cfg["include_logs"] = true
	studio_cfg["last_logs"] = "GODOT_TEST_LOG_CONTEXT_42"
	Store.set_integration("studio", studio_cfg)
	main.studio._set_view_mode("chats")
	var studio_history: Array = main.studio.embedded_chat._history()
	var studio_system := str(studio_history[0].get("content", "")) if not studio_history.is_empty() else ""
	_check("U43_studio_prompt_includes_project_instructions", studio_system.contains("CURRENT PROJECT: Studio regression") and studio_system.contains("Goal: Build a small 2D platformer") and studio_system.contains("PROJECT-AGNOSTIC DEVELOPMENT CONTRACT"))
	_check("U44_studio_logs_are_attached_only_when_enabled", studio_system.contains("GODOT_TEST_LOG_CONTEXT_42"))
	_check("U45_studio_logs_toggle_is_visible", main.studio._logs_toggle != null and main.studio._logs_toggle.button_pressed)
	var addon_cfg := ConfigFile.new()
	_check("U46_godot_editor_addon_manifest_exists", FileAccess.file_exists("res://addons/aoi_studio/plugin.cfg") and FileAccess.file_exists("res://addons/aoi_studio/plugin.gd") and FileAccess.file_exists("res://addons/aoi_studio/dock.gd"))
	_check("U46A_studio_toolbox_exposes_api_and_validation", main.studio._tool_menu.get_item_count() >= 12 and main.studio._tool_menu.get_item_text(main.studio._tool_menu.get_item_index(6)) == "Godot API Explorer")
	main.studio.embedded_chat.build_stage_changed.emit("planning", "Reading source files and drafting the build plan.")
	_check("U47_studio_build_status_pill_appears", main.studio._activity_pill.visible and main.studio._activity_pill.text.contains("Planning"))
	main.studio._activity_pill.pressed.emit()
	_check("U48_studio_activity_panel_expands_from_composer_lane", main.studio._activity_panel.visible and _text(main.studio._activity_panel).contains("Plan") and _text(main.studio._activity_panel).contains("Review"))
	main.studio._set_view_mode("sources")
	_check("U49_studio_activity_overlay_hides_in_sources_view", not main.studio._activity_pill.visible and not main.studio._activity_panel.visible)
	var preview_image := Image.create(48, 32, false, Image.FORMAT_RGBA8)
	var preview_png := preview_image.save_png_to_buffer()
	main.go("studio")
	main.studio._show_capture_preview(preview_png)
	_check("U50_godot_capture_opens_fullscreen_review_surface", main.studio._fullscreen_preview != null and main.studio._fullscreen_preview.is_visible_in_tree() and is_equal_approx(main.studio._fullscreen_preview.anchor_right, 1.0) and is_equal_approx(main.studio._fullscreen_preview.anchor_bottom, 1.0))
	main.studio._close_fullscreen_preview()
	_check("U51_fullscreen_capture_can_be_closed", main.studio._fullscreen_preview == null)
	main.studio._set_view_mode("chats")
	var studio_empty_copy := _text(main.studio.embedded_chat)
	var studio_has_saved_review := studio_empty_copy.contains("One action needs review") or studio_empty_copy.contains("One detail needs you")
	var studio_context_is_correct := studio_empty_copy.contains("Project: Studio regression") and studio_empty_copy.contains("Continue work") if studio_has_saved_review else studio_empty_copy.contains("What are we working on?") and not studio_empty_copy.contains("Connect an AI provider")
	_check("U52_studio_empty_state_preserves_saved_project_review_context", studio_context_is_correct)
	main.studio.embedded_chat._tool_session_id = str(main.studio.embedded_chat.session.get("id", ""))
	ToolRunner.state_changed.emit("running", "Executing approved Godot command")
	_check("U53_studio_activity_tracks_tool_runner_state", main.studio._activity_stage == "running" and main.studio._activity_pill.text.contains("Running"))
	main.studio.embedded_chat._tool_session_id = ""
	# Studio must remain project-agnostic: no bundled domain-specific project or tools.
	main.studio._set_view_mode("runs")
	var runs_text := _text(main.studio._content)
	_check("U54_runs_workspace_is_domain_agnostic", runs_text.contains("Run & results") and runs_text.contains("Runnable project tasks"))
	var generic_info := JobRunner.inspect_project(studio_project_id)
	_check("U55_studio_inspects_selected_project_without_domain_assumptions", bool(generic_info.get("ok", false)) and str(generic_info.get("primary_type", "")) == "godot")
	var generic_root: String = main.studio._local_project_absolute_path()
	DirAccess.make_dir_recursive_absolute(generic_root.path_join(".aoi"))
	DirAccess.make_dir_recursive_absolute(generic_root.path_join("tasks"))
	var generic_manifest := {"schema_version": 1, "tasks": [{"id": "ui-check", "name": "UI project check", "description": "A generic headless task for this selected project.", "runtime": "gdscript_steps", "script": "tasks/ui_check.gd", "parameters": [], "limits": {"max_runtime_seconds": 30}}]}
	var manifest_file := FileAccess.open(generic_root.path_join(".aoi/tasks.json"), FileAccess.WRITE)
	manifest_file.store_string(JSON.stringify(generic_manifest, "\t"))
	manifest_file.close()
	var task_script := "extends RefCounted\n\nfunc start(_context: Dictionary, _parameters: Dictionary, checkpoint: Dictionary) -> Dictionary:\n\treturn {\"ok\": true, \"state\": checkpoint if not checkpoint.is_empty() else {\"count\": 0}, \"detail\": \"Initialised\"}\n\nfunc step(_context: Dictionary, state: Dictionary, budget_units: int) -> Dictionary:\n\tvar count := int(state.get(\"count\", 0)) + mini(budget_units, 20 - int(state.get(\"count\", 0)))\n\tvar next_state := {\"count\": count}\n\treturn {\"ok\": true, \"state\": next_state, \"progress\": float(count) / 20.0, \"detail\": \"Checked %d/20 items\" % count, \"done\": count >= 20, \"metrics\": {\"checked\": count}, \"artifacts\": {\"summary.txt\": \"Checked %d items\" % count}}\n"
	var task_file := FileAccess.open(generic_root.path_join("tasks/ui_check.gd"), FileAccess.WRITE)
	task_file.store_string(task_script)
	task_file.close()
	var task_list := JobRunner.list_project_tasks(studio_project_id)
	_check("U56_studio_reads_project_owned_task_manifest", bool(task_list.get("ok", false)) and task_list.get("tasks", []).size() == 1 and str(task_list.tasks[0].get("id", "")) == "ui-check")
	_check("U57_project_tools_follow_specialist_permissions", ChatScreenForPolicy._role_allows_tool("Researcher", "project.inspect") and ChatScreenForPolicy._role_allows_tool("Reviewer", "jobs.read_artifact") and not ChatScreenForPolicy._role_allows_tool("Researcher", "project.run_task"))
	_check("U58_project_mutations_follow_workspace_autonomy_and_task_guard", not _approval_required("project.write_file", "build", studio_project_id) and _approval_required("project.run_task", "build", studio_project_id) and not _approval_required("project.inspect", "build", studio_project_id))
	var generic_start := JobRunner.start_project_task(studio_project_id, "ui-check")
	var generic_job_id := str(generic_start.get("job_id", ""))
	var generic_frames := 0
	while generic_frames < 120 and str(JobRunner.get_job(generic_job_id).get("state", "")) == "running":
		await get_tree().process_frame
		generic_frames += 1
	var generic_job := JobRunner.get_job(generic_job_id)
	_check("U59_generic_project_task_runs_without_preview_or_pc", bool(generic_start.get("ok", false)) and str(generic_job.get("state", "")) == "completed")
	var generic_artifact := JobRunner.read_artifact(generic_job_id, "summary.txt")
	_check("U60_generic_project_task_returns_artifacts_and_metrics", bool(generic_artifact.get("ok", false)) and str(generic_artifact.get("content", "")).contains("Checked 20 items") and generic_job.get("metrics", {}).get("checked", 0) == 20)
	var paused_job_card: Control = main.studio._job_card({"id":"paused_ui_check","state":"paused","resumable":true,"summary":"Paused · checkpoint preserved"})
	_check("U60A_paused_run_keeps_resume_without_stop_action", _find_button_by_text(paused_job_card, "Resume") != null and _find_button_by_text(paused_job_card, "Stop") == null)
	paused_job_card.free()
	var failed_job_card: Control = main.studio._job_card({"id":"failed_ui_check","state":"failed","resumable":true,"summary":"Failed · retry available"})
	_check("U60B_failed_run_keeps_resume_without_stop_action", _find_button_by_text(failed_job_card, "Resume") != null and _find_button_by_text(failed_job_card, "Stop") == null)
	failed_job_card.free()
	_check("U61_aoi_core_has_no_bundled_example_project_modules", not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/samples")) and not FileAccess.file_exists("res://tests/fixtures/generic_task_project/project.godot"))
	# Import a completely unrelated external folder. It deliberately contains
	# multiple ecosystem markers and a hidden project-owned task manifest.
	var import_source := ProjectSettings.globalize_path("user://generic_external_project")
	DirAccess.make_dir_recursive_absolute(import_source.path_join(".aoi"))
	DirAccess.make_dir_recursive_absolute(import_source.path_join("src"))
	var import_readme := FileAccess.open(import_source.path_join("README.md"), FileAccess.WRITE)
	import_readme.store_string("# Generic external project\n")
	import_readme.close()
	var package_json := FileAccess.open(import_source.path_join("package.json"), FileAccess.WRITE)
	package_json.store_string("{\"name\":\"external-sample\",\"version\":\"1.0.0\"}")
	package_json.close()
	var source_script := FileAccess.open(import_source.path_join("src/main.js"), FileAccess.WRITE)
	source_script.store_string("console.log('external project');\n")
	source_script.close()
	var import_manifest := {"schema_version":1,"tasks":[{"id":"external-report","name":"External report","description":"A project-defined task retained during import.","runtime":"python_companion","script":"src/report.py","parameters":[],"limits":{"max_runtime_seconds":60}}]}
	var hidden_manifest := FileAccess.open(import_source.path_join(".aoi/tasks.json"), FileAccess.WRITE)
	hidden_manifest.store_string(JSON.stringify(import_manifest, "\t"))
	hidden_manifest.close()
	var secret_env := FileAccess.open(import_source.path_join(".env"), FileAccess.WRITE)
	secret_env.store_string("API_TOKEN=must_not_import\n")
	secret_env.close()
	var original_project_path := import_source.path_join("README.md")
	main.studio._import_local_project_folder(import_source)
	await get_tree().process_frame
	var imported_id := str(main.studio._selected_project.get("id", ""))
	var imported_root: String = main.studio._local_project_absolute_path()
	var imported_info := JobRunner.inspect_project(imported_id)
	_check("U62_arbitrary_folder_import_creates_new_workspace_copy", imported_id != "" and imported_root != import_source and FileAccess.file_exists(imported_root.path_join("README.md")) and FileAccess.file_exists(original_project_path))
	_check("U63_import_detects_project_type_without_domain_assumptions", bool(imported_info.get("ok", false)) and imported_info.get("detected_types", []).has("node") and str(imported_info.get("primary_type", "")) == "node")
	var imported_tasks := JobRunner.list_project_tasks(imported_id)
	_check("U64_import_preserves_hidden_project_task_manifest", bool(imported_tasks.get("ok", false)) and imported_tasks.get("tasks", []).size() == 1 and str(imported_tasks.tasks[0].get("id", "")) == "external-report")
	_check("U65_import_excludes_private_environment_files", not FileAccess.file_exists(imported_root.path_join(".env")) and FileAccess.file_exists(imported_root.path_join(".aoi/tasks.json")))
	# A restored or stale project record must not expose a ready result until both
	# its full plan is complete and a real preview artifact is present.
	var unverified_game := Store.new_project("Unverified game", "A complete playable game")
	unverified_game["project_kind"] = "game"
	unverified_game["aoi_work_completed_steps"] = 4
	unverified_game["aoi_work_total_steps"] = 4
	unverified_game["aoi_work_progress"] = 1.0
	var unverified_card := BuildCardForAcceptance.new()
	add_child(unverified_card)
	unverified_card.configure(unverified_game, "ready", "Test result")
	await get_tree().process_frame
	var unverified_headline := unverified_card.find_child("CreationHeadline", true, false) as Label
	_check("U66_workspace_without_real_preview_cannot_look_ready", not unverified_card._open_button.visible and unverified_headline != null and not unverified_headline.text.to_lower().contains("ready"))
	var preview_path := ProjectSettings.globalize_path("user://aoi_review_preview_gate.png")
	var preview_gate_image := Image.create(48, 27, false, Image.FORMAT_RGBA8)
	preview_gate_image.fill(Color("#192b3a"))
	var preview_saved := preview_gate_image.save_png(preview_path) == OK
	var verified_game := unverified_game.duplicate(true)
	verified_game["preview_path"] = preview_path
	verified_game["preview_kind"] = "paired_runtime_capture"
	# The result gate requires proof that this capture came from a running game.
	verified_game["runtime_verified_at"] = Time.get_unix_time_from_system()
	verified_game["preview_updated_at"] = verified_game["runtime_verified_at"]
	var verified_card := BuildCardForAcceptance.new()
	add_child(verified_card)
	verified_card.configure(verified_game, "ready", "Verified project")
	await get_tree().process_frame
	_check("U67_verified_plan_and_real_capture_enable_result_review", preview_saved and verified_card._open_button.visible and verified_card._preview_frame.visible and verified_card._progress_pill.visible == false)
	# The chosen creation card must stay visually focused: one signal field, one
	# status line and one compact percentage pill only when the project plan is known.
	var progress_game := Store.new_project("Signal field game", "A deliberately long goal that must not be repeated inside the compact creation card.")
	progress_game["project_kind"] = "game"
	progress_game["aoi_work_progress"] = 0.33
	progress_game["aoi_work_completed_steps"] = 1
	progress_game["aoi_work_total_steps"] = 3
	progress_game["aoi_work_updated_at"] = Time.get_unix_time_from_system()
	var progress_card := BuildCardForAcceptance.new()
	add_child(progress_card)
	progress_card.configure(progress_game, "building", "Creating the opening scene")
	await get_tree().process_frame
	var signal_field := progress_card.find_child("CreationSignalField", true, false)
	var status_line := progress_card.find_child("CreationStatus", true, false) as Label
	var percent_line := progress_card.find_child("CreationProgressValue", true, false) as Label
	_check("U68_card_uses_signal_field_and_one_short_status_line", signal_field != null and status_line != null and status_line.text == "Laying out the first world" and progress_card.find_child("CreationActivityFeed", true, false) == null)
	_check("U69_card_progress_is_a_compact_plan_derived_pill", progress_card._progress_pill.visible and percent_line != null and percent_line.text == "33%")
	var indeterminate_game := progress_game.duplicate(true)
	indeterminate_game["aoi_work_progress"] = -1.0
	indeterminate_game["aoi_work_total_steps"] = 0
	var indeterminate_card := BuildCardForAcceptance.new()
	add_child(indeterminate_card)
	indeterminate_card.configure(indeterminate_game, "building", "Preparing the first files")
	await get_tree().process_frame
	_check("U70_unknown_progress_uses_no_fake_percentage", not indeterminate_card._progress_pill.visible and float(indeterminate_card._progress_rail.get("progress")) < 0.0)
	var stale_game := progress_game.duplicate(true)
	stale_game["aoi_work_updated_at"] = Time.get_unix_time_from_system() - 500.0
	var stale_card := BuildCardForAcceptance.new()
	add_child(stale_card)
	stale_card.configure(stale_game, "building", "An old saved activity")
	stale_card._evaluate_freshness(Time.get_unix_time_from_system() + BuildCardForAcceptance.STALE_AFTER_SECONDS + 1.0)
	var continue_events: Array[String] = []
	stale_card.continue_work_requested.connect(func(requested_id: String): continue_events.append(requested_id))
	stale_card._on_continue_pressed()
	_check("U71_stale_work_offers_continue_without_creating_another_project", stale_card._stage == "stalled" and stale_card._continue_button.visible and continue_events.size() == 1 and continue_events[0] == str(stale_game.get("id", "")))
	# A short creation acknowledgement should not appear above the card; the card
	# owns the progress copy. Detailed assistant replies must remain visible.
	var intro_project := Store.new_project("Card-first creation", "Build the requested game")
	var saved_session: Dictionary = chat.session.duplicate(true)
	var saved_project: Dictionary = chat.project.duplicate(true)
	chat.session = Store.new_session("build", str(intro_project.get("id", "")))
	chat.project = intro_project
	(chat.session["messages"] as Array).append({"role":"user", "content":"Create a small game"})
	(chat.session["messages"] as Array).append({"role":"assistant", "content":"I’m shaping the first playable version now."})
	(chat.session["messages"] as Array).append({"role":"assistant", "content":"", "project_card":true, "project_id":str(intro_project.get("id", ""))})
	chat._render()
	_check("U72_creation_acknowledgement_lives_inside_the_card", not _text(chat._msgs).contains("I’m shaping the first playable version now") and chat._msgs.find_child("AoiCreationExperience", true, false) != null)
	chat.session = saved_session
	chat.project = saved_project
	chat._render()
	unverified_card.queue_free()
	verified_card.queue_free()
	progress_card.queue_free()
	indeterminate_card.queue_free()
	stale_card.queue_free()
	DirAccess.remove_absolute(preview_path)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var bad := 0
	for r in results: if not r[1]: bad += 1
	print("UI_SUMMARY ", results.size() - bad, "/", results.size(), " passed")
	get_tree().quit(1 if bad > 0 else 0)

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _wait_idle() -> void:
	await _wait(0.3)
	var t := 0.0
	while LLM.busy and t < 25.0:
		await _wait(0.1); t += 0.1
	await _wait(0.5)

func _find_button_by_text(root: Node, wanted: String) -> Button:
	if root is Button and (root as Button).text == wanted:
		return root as Button
	for child in root.get_children():
		var found := _find_button_by_text(child, wanted)
		if found != null:
			return found
	return null


func _text(n: Node) -> String:
	var t := ""
	if n is RichTextLabel: t += (n as RichTextLabel).get_parsed_text() + "|"
	elif n is Label: t += (n as Label).text + "|"
	elif n is Button: t += (n as Button).text + "|"
	for c in n.get_children(): t += _text(c)
	return t

func _log() -> Array:
	var req := HTTPRequest.new(); add_child(req)
	req.request("http://127.0.0.1:%s/__log" % OS.get_environment("MOCK_PORT"))
	var out = await req.request_completed
	req.queue_free()
	return JSON.parse_string((out[3] as PackedByteArray).get_string_from_utf8())

func _check(n: String, ok: bool, detail: String = "") -> void:
	results.append([n, ok]); print("UI_", n, " ", "PASS" if ok else "FAIL", " ", detail if not ok else "")
