extends Node

func _ready() -> void:
	var tab := OS.get_environment("AOI_MOBILE_TAB")
	if tab == "": tab = "chat"
	Store.set_root("user://aoi_release_review/" + tab + "_%d/" % Time.get_ticks_msec())
	var project: Dictionary = {}
	if tab == "projects" or tab == "workflow":
		project = Store.new_project("Sky Hop", "Build a complete original arcade game with a welcoming title screen, responsive one-touch play, a pause menu, saved high scores and a reliable restart flow.")
		project["project_kind"] = "game"
		project["notes"] = "## Creative direction\nA bright, readable arcade game with quick restarts, expressive feedback and a clear first-time welcome.\n\n## Player experience\nThe player should understand how to start, pause, recover from a collision and beat a saved personal best."
		Store.add_task(project, "Design the welcome and first-play experience")
		Store.add_task(project, "Build responsive tap-to-play gameplay")
		Store.add_task(project, "Add pause, restart and saved scores")
		(project["tasks"] as Array)[0]["done"] = true
		Store.save_project(project)
		if tab == "projects":
			AgentFlow.apply_plan(str(project.id), {"summary":"Deliver the complete playable arcade experience from first launch through a repeatable game round, saved high scores and final playability review.", "tasks":[
				{"title":"Define the complete arcade experience", "detail":"Inspect the current game project and define its first-launch experience, primary loop, scoring rules, difficulty progression, pause behavior, restart behavior and the precise point at which a round is complete.", "deliverables":["Complete game-flow specification", "Interaction and screen map"], "role":"Planner", "priority":"high", "acceptance":"Every player-facing screen and transition from opening the game to starting, pausing, restarting and finishing a round is specified.", "verification":"Walk through the flow map and compare every transition against the original game request.", "file_scope":["Game entry scene and navigation", "Game state and scoring systems"], "depends_on":[]},
				{"title":"Create the welcome screen and onboarding", "detail":"Build a polished welcome screen with the game title, a clear start action, concise first-play guidance and accessible touch targets that lead directly into gameplay.", "deliverables":["Welcome screen", "First-play guidance and start transition"], "role":"Engineer", "priority":"high", "acceptance":"A new player can understand the objective and enter a first round without encountering placeholder controls or dead ends.", "verification":"Launch from a fresh state and complete the first-time entry flow on a phone-sized viewport.", "file_scope":["Welcome screen scene and script", "Game navigation"], "depends_on":["Define the complete arcade experience"]},
				{"title":"Implement the core gameplay and scoring loop", "detail":"Implement responsive one-touch input, player movement, obstacle timing, collision handling, score updates and a clear game-over transition. Keep simulation delta-time aware and gameplay speed independent from frame rate.", "deliverables":["Playable gameplay loop", "Collision and score system", "Game-over state"], "role":"Engineer", "priority":"high", "acceptance":"The player can start a round, play using touch, gain score only through valid gameplay events and reach a stable game-over state.", "verification":"Run repeated rounds, exercise touch input and collisions, and inspect score changes and runtime logs.", "file_scope":["Gameplay scene", "Player controller", "Scoring and collision logic"], "depends_on":["Create the welcome screen and onboarding"]},
				{"title":"Add pause, restart and persistent high scores", "detail":"Implement a readable pause overlay, resume action, restart action and durable high-score storage. Restart must reset only the active round while preserving saved personal-best data.", "deliverables":["Pause menu", "Restart flow", "Persistent high-score storage"], "role":"Engineer", "priority":"high", "acceptance":"Pause and resume preserve the active round; restart creates a clean round; saved high scores survive application restarts.", "verification":"Pause during play, resume, restart, close and relaunch the app, then confirm the saved high score remains intact.", "file_scope":["Pause menu UI", "Game state transitions", "High-score persistence"], "depends_on":["Implement the core gameplay and scoring loop"]},
				{"title":"Polish and verify the complete playable game", "detail":"Tune animation, audio feedback, touch responsiveness, layout and game pacing. Exercise the full welcome-to-game-over journey, correct discovered defects and prepare a genuine playable result rather than a static preview.", "deliverables":["Polished playable game", "Playability review record", "Real game capture"], "role":"Reviewer", "priority":"high", "acceptance":"The complete requested experience can be launched and played, including welcome, scoring, pause, restart and saved high scores, with no known blocking defects.", "verification":"Perform a complete playthrough, relaunch to verify persistence, inspect a real runtime capture and review logs.", "file_scope":["Complete game project", "Runtime evidence and output"], "depends_on":["Add pause, restart and persistent high scores"]}
			]})
			var project_flow := AgentFlow.get_flow(str(project.id))
			if project_flow.get("tasks", []) is Array and (project_flow["tasks"] as Array).size() >= 3:
				var flow_tasks: Array = project_flow["tasks"]
				AgentFlow.update_task(str(project.id), str(flow_tasks[0].get("id", "")), {"status":"done"})
				AgentFlow.update_task(str(project.id), str(flow_tasks[1].get("id", "")), {"status":"in_progress"})
	if tab == "workflow":
		AgentFlow.apply_plan(str(project.id), {"summary":"Deliver the complete playable arcade experience from its welcome screen through responsive play, pause, saved high scores and reliable restarts.","tasks":[
			{"title":"Research the integration architecture","detail":"Inspect provider APIs, the local bridge, GitHub permissions and existing app structure before writing the full integration and security plan.","deliverables":["Integration architecture and security brief"],"role":"Researcher","priority":"high","acceptance":"The integration map records API assumptions, scopes, data boundaries and failure behavior for every connected service.","verification":"Compare documented scopes against provider APIs and inspect the existing bridge implementation.","file_scope":["integration architecture"],"depends_on":[]},
			{"title":"Implement the developer workspace","detail":"Connect GitHub and the local Linux bridge through project-scoped tools while preserving explicit approval for external or elevated-risk operations.","deliverables":["Scoped GitHub integration", "Authenticated Linux workspace tools"],"role":"Engineer","priority":"high","acceptance":"Read tools work, project-scoped edits remain inside the selected workspace and elevated operations require review.","verification":"Exercise read and write paths against the isolated bridge test fixture and inspect approval decisions.","file_scope":["bridge", "workspace tools"],"depends_on":["Research the integration architecture"]},
			{"title":"Build the consumer chat and project experience","detail":"Create the full-screen conversation flow and project result presentation so ordinary users see their goals, meaningful progress and real outcomes rather than developer machinery.","deliverables":["Consumer-first chat and project screens"],"role":"Engineer","priority":"high","acceptance":"The primary chat and project flows present clear user outcomes without exposing raw bridge or test configuration by default.","verification":"Capture and inspect fresh phone-sized chat and project screenshots against the approved reference.","file_scope":["chat UI", "projects UI"],"depends_on":["Implement the developer workspace"]},
			{"title":"Persist sessions and recover interrupted work","detail":"Persist conversation identity, pending approvals, task checkpoints, progress events and continuation instructions so the user can leave and return without losing control.","deliverables":["Durable session state", "Approval and task recovery flow"],"role":"Engineer","priority":"normal","acceptance":"A pending decision and its originating chat restore after navigation or restart without silently executing the action.","verification":"Reload the session from storage and inspect the pending action and queued follow-up behavior.","file_scope":["session storage", "workflow state"],"depends_on":["Build the consumer chat and project experience"]},
			{"title":"Verify behavior and review the complete result","detail":"Run focused end-to-end checks for chat, integrations, recovery and touch behavior, then inspect fresh 720 by 1520 captures and correct defects.","deliverables":["Release review record", "Verified mobile experience"],"role":"Reviewer","priority":"high","acceptance":"User-facing flows work and every remaining risk or unavailable physical-device check is recorded honestly.","verification":"Run the release suites, inspect screenshots and perform a clean project import before packaging.","file_scope":["whole project"],"depends_on":["Persist sessions and recover interrupted work"]}
		]})
		var flow := AgentFlow.get_flow(str(project.id))
		AgentFlow.update_task(str(project.id), str(flow.tasks[0].id), {"status":"in_progress","role":"Researcher","title":"Research the integration architecture"})
		AgentFlow.update_task(str(project.id), str(flow.tasks[0].id), {"status":"review","role":"Researcher","title":"Research the integration architecture","review_summary":"Compared provider APIs and local bridge boundaries. Confirmed the repository scopes and credential handling that the implementation must preserve."})
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	match tab:
		"setup":
			main.go("setup")
			var setup_capture := OS.get_environment("AOI_SETUP_SCROLL")
			if setup_capture != "":
				Store.add_knowledge("Global engineering standards", "Use actual runtime evidence, review fresh captures, keep reusable standards independent of project data.", ["workspace", "reference", "global", "work-standards"], "workspace_reference")
				Store.add_knowledge("Godot API conventions", "Use the installed engine ClassDB and matching official documentation. Never invent methods, signals or properties.", ["workspace", "reference", "global", "api-documentation"], "workspace_reference")
				main.setup.render()
				await get_tree().process_frame
				await get_tree().process_frame
				var bar: VScrollBar = main.setup.get_v_scroll_bar()
				var offset := 0.82
				if setup_capture == "providers": offset = 0.22
				elif setup_capture == "workspace": offset = 0.43
				elif setup_capture == "references": offset = 0.68
				main.setup.scroll_vertical = int(bar.max_value * offset)
		"knowledge":
			Store.add_knowledge("Godot safe-area reference", "Keep the top bar below the camera cutout. Respect left and right grip insets. Keep the composer above the gesture area and keyboard.", ["mobile", "Godot"], "manual")
			Store.add_knowledge("Aoi project principles", "Keep project goals, decisions, task acceptance criteria and review evidence together.", ["workflow", "quality"], "manual")
			main.go("knowledge")
		"projects":
			if OS.get_environment("AOI_PROJECT_LIST") != "1": main.projects.open_project(str(project.id))
			main.go("projects")
			if OS.get_environment("AOI_PROJECT_WORK_DETAILS") == "1":
				main.projects._show_work_details = true
				main.projects.render()
			if OS.get_environment("AOI_PROJECT_EDIT") == "1": main.projects._on_project_menu_action(3)
		"workflow":
			main.workflow.open_project(str(project.id))
			main.go("workflow")
			if OS.get_environment("AOI_WORKFLOW_REVIEW_FOCUS") == "1":
				await get_tree().process_frame
				var bar: VScrollBar = main.workflow.get_v_scroll_bar()
				main.workflow.scroll_vertical = int(bar.max_value * 0.9)
		"explore":
			main.go("explore")
			if OS.get_environment("AOI_LINUX_HEALTH_TEST") == "1":
				var linux_cfg := Store.get_integration("linux_bridge")
				linux_cfg["url"] = "http://127.0.0.1:8765"
				linux_cfg["target"] = "pc"
				Store.set_integration("linux_bridge", linux_cfg)
				Store.set_secret("linux_bridge", "aoi-local-bridge-test-token-1234567890")
				main.explore.render()
			var detail_id := OS.get_environment("AOI_EXPLORE_DETAIL_ID")
			if detail_id != "" or OS.get_environment("AOI_LINUX_HEALTH_TEST") == "1":
				var wanted_id := detail_id if detail_id != "" else "linux_bridge"
				for service in main.explore.INTEGRATIONS:
					if str(service.get("id", "")) == wanted_id:
						main.explore._show_integration_details(service)
						break
			if OS.get_environment("AOI_LINUX_HEALTH_TEST") == "1":
				await get_tree().process_frame
				var bridge_test := main.explore.find_child("LinuxBridgeTestButton", true, false) as Button
				if bridge_test != null: bridge_test.pressed.emit()
			if OS.get_environment("AOI_SETUP_DIALOG") == "github": main._configure_github()
			elif OS.get_environment("AOI_SETUP_DIALOG") == "linux": main._configure_linux()
		"knowledge": main.go("knowledge")
		"studio_api":
			main.go("studio")
			main.studio._show_api_explorer()
			var api_window: Window = null
			for child in main.studio.get_children():
				if child is Window and str(child.title).begins_with("Godot API Explorer"): api_window = child
			if api_window != null and OS.get_environment("AOI_API_MEMBER") != "":
				var member_search: LineEdit = api_window.find_child("APIMemberSearch", true, false) as LineEdit
				if member_search != null:
					member_search.text = OS.get_environment("AOI_API_MEMBER")
					member_search.text_changed.emit(member_search.text)
		"pc_companion":
			main.go("explore")
			main.explore._show_pc_companion_plan()
		"studio":
			main.go("studio")
			if OS.get_environment("AOI_STUDIO_VIEW") == "landing":
				main.studio._selected_project = {}
				main.studio._render_landing()
			else:
				main.studio._create_local_workspace("Aoi project workspace", "Inspect, plan, implement and verify a project with traceable changes and approval gates.")
				main.studio._write_project_file("scripts/player_controller.gd", "extends CharacterBody2D\n\n@export var speed := 280.0\n\nfunc _physics_process(_delta: float) -> void:\n\tvar direction := Input.get_vector(\"ui_left\", \"ui_right\", \"ui_up\", \"ui_down\")\n\tvelocity = direction * speed\n\tmove_and_slide()\n", func(_ok: bool, _error: String): pass)
				main.studio._write_project_file("scenes/level_01.tscn", "[gd_scene format=3]\n\n[node name=\"Level01\" type=\"Node2D\"]\n", func(_ok: bool, _error: String): pass)
				main.studio._refresh_sources()
				if OS.get_environment("AOI_STUDIO_VIEW") == "sources":
					main.studio._set_view_mode("sources")
				else:
					main.studio._on_build_stage_changed("building", "Aoi is creating the first project slice.")
					if OS.get_environment("AOI_STUDIO_ACTIVITY") == "expanded": main.studio._activity_pill.pressed.emit()
		"runs":
			main.go("studio")
			main.studio._create_generic_local_workspace("Field research project", "Process imported records, validate results and produce a reproducible report.")
			var project_id := str(main.studio._selected_project.get("id", ""))
			var project_root: String = main.studio._local_project_absolute_path()
			DirAccess.make_dir_recursive_absolute(project_root.path_join(".aoi"))
			DirAccess.make_dir_recursive_absolute(project_root.path_join("tasks"))
			var manifest := {"schema_version":1,"tasks":[{"id":"analyze-records","name":"Analyze records","description":"A project-owned, resumable headless task that emits metrics and a report.","runtime":"gdscript_steps","script":"tasks/analyze.gd","parameters":[],"limits":{"max_runtime_seconds":30}}]}
			var manifest_file := FileAccess.open(project_root.path_join(".aoi/tasks.json"), FileAccess.WRITE)
			manifest_file.store_string(JSON.stringify(manifest, "\t")); manifest_file.close()
			var task_source := "extends RefCounted\n\nfunc start(_context: Dictionary, _parameters: Dictionary, checkpoint: Dictionary) -> Dictionary:\n\treturn {\"ok\":true,\"state\":checkpoint if not checkpoint.is_empty() else {\"processed\":0},\"detail\":\"Task initialized\"}\n\nfunc step(_context: Dictionary, state: Dictionary, budget_units: int) -> Dictionary:\n\tvar processed := mini(int(state.get(\"processed\", 0)) + budget_units, 128)\n\tvar next_state := {\"processed\":processed}\n\tvar metrics := {\"records_processed\":processed,\"records_total\":128,\"completion_ratio\":float(processed) / 128.0}\n\tvar done := processed >= 128\n\treturn {\"ok\":true,\"state\":next_state,\"progress\":float(processed) / 128.0,\"detail\":\"Processed %d / 128 records\" % processed,\"done\":done,\"metrics\":metrics,\"artifacts\":{\"summary.txt\":\"Processed %d records\" % processed},\"summary\":\"Completed record analysis\" if done else \"Processing records\"}\n"
			var task_file := FileAccess.open(project_root.path_join("tasks/analyze.gd"), FileAccess.WRITE)
			task_file.store_string(task_source); task_file.close()
			var start := JobRunner.start_project_task(project_id, "analyze-records")
			var job_id := str(start.get("job_id", ""))
			for _frame in range(120):
				await get_tree().process_frame
				if str(JobRunner.get_job(job_id).get("state", "")) == "completed": break
			main.studio._set_view_mode("runs")
		"_": main.go("chat")
	if OS.get_environment("AOI_CHAT_PROJECT_CREATE_TEST") == "1":
		main.go("chat")
		main.chat.new_session("chat")
		(main.chat.session["messages"] as Array).append({"role":"user", "content":"Make a small arcade game called Neon Collector with a simple playable loop."})
		main.chat._history()
		var create_definition_found: bool = false
		for definition in main.chat._request_tool_definitions:
			var function_data: Dictionary = definition.get("function", {})
			if str(function_data.get("name", "")) == "aoi_workspace__create_project": create_definition_found = true
		var normalized: Dictionary = main.chat._normalise_tool_request("aoi_workspace__create_project", {"title":"Neon Collector", "goal":"A small arcade game with a playable collection loop, scoring and restart.", "kind":"game"})
		var captured: Array[Dictionary] = []
		var capture_callback := func(result: Dictionary) -> void: captured.append(result)
		ToolRunner.completed.connect(capture_callback, CONNECT_ONE_SHOT)
		if bool(normalized.get("ok", false)): ToolRunner.execute_tool(normalized.get("data", {}))
		await get_tree().process_frame
		var created_result: Dictionary = captured[0] if not captured.is_empty() else {}
		var attached: bool = main.chat._attach_created_project_to_chat(created_result) if bool(created_result.get("ok", false)) else false
		var created_id := str(created_result.get("project_id", ""))
		var inspect_result: Dictionary = JobRunner.inspect_project(created_id) if created_id != "" else {}
		main.chat._history()
		var write_tool_available: bool = false
		for definition in main.chat._request_tool_definitions:
			var function_data: Dictionary = definition.get("function", {})
			if str(function_data.get("name", "")) == "aoi_project__write_file": write_tool_available = true
		var write_normalized: Dictionary = main.chat._normalise_tool_request("aoi_project__write_file", {"path":"game/main.gd", "content":"extends Node\n\nfunc _ready() -> void:\n\tprint(\"Neon Collector ready\")\n"})
		captured.clear()
		ToolRunner.completed.connect(capture_callback, CONNECT_ONE_SHOT)
		if bool(write_normalized.get("ok", false)): ToolRunner.execute_tool(write_normalized.get("data", {}))
		await get_tree().process_frame
		var project_write_result: Dictionary = captured[0] if not captured.is_empty() else {}
		var read_result: Dictionary = JobRunner.read_project_file(created_id, "game/main.gd") if created_id != "" else {"ok":false}
		Store.save_session(main.chat.session, true)
		var persisted_session := Store.load_session(str(main.chat.session.get("id", "")))
		var card_persisted: bool = false
		for message in persisted_session.get("messages", []):
			if bool(message.get("project_card", false)) and str(message.get("project_id", "")) == created_id: card_persisted = true
		var history_has_project_context: bool = str(main.chat.session.get("mode", "")) == "build" and str(main.chat.session.get("project_id", "")) == created_id
		var project_kind_preserved: bool = str(inspect_result.get("project_kind", "")) == "game"
		var result_ok: bool = create_definition_found and bool(normalized.get("ok", false)) and bool(created_result.get("ok", false)) and attached and bool(inspect_result.get("ok", false)) and project_kind_preserved and write_tool_available and bool(write_normalized.get("ok", false)) and bool(project_write_result.get("ok", false)) and bool(read_result.get("ok", false)) and history_has_project_context and card_persisted
		print("CHAT_PROJECT_CREATE advertised=", create_definition_found, " created=", created_result.get("ok", false), " attached_to_same_chat=", attached and history_has_project_context, " project_intent=", inspect_result.get("project_kind", "none"), " detected_runtime=", inspect_result.get("primary_type", "none"), " file_write=", project_write_result.get("ok", false), " file_readback=", read_result.get("ok", false), " card_persisted=", card_persisted, " result=", "PASS" if result_ok else "FAIL")
		main.chat._update_activity("running", "project.write_file")
		main.chat._render()
	if OS.get_environment("AOI_TYPE_DEMO") == "1":
		main.go("chat")
		main.chat.new_session("chat")
		var demo_markdown := "# Aoi's new type system\n\nA single visual language for **important ideas**, *secondary emphasis* and `res://scripts/ui/AoiPresence.gd`.\n\n## What changed\n- Headings now have a deliberate hierarchy.\n- Inline code has a quiet inset treatment.\n- Links stay understated and readable: [Godot documentation](https://docs.godotengine.org).\n\n> The interface stays calm even when the work gets complex.\n\n```gdscript\nfunc set_state(value: String) -> void:\n    state = value\n```"
		(main.chat.session["messages"] as Array).append({"role":"user", "content":"Show me the typography update."})
		(main.chat.session["messages"] as Array).append({"role":"assistant", "content":demo_markdown})
		Store.save_session(main.chat.session, true)
		main.chat._render()
	if OS.get_environment("AOI_ACTIVITY_DEMO") == "1":
		# Presentation-only fixture: exercise the same activity UI with a controlled
		# sequence. Production events still come exclusively from ToolRunner.
		main.chat._update_activity("planning", "Understanding the request and active project")
		main.chat._update_activity("running", "project.inspect")
		main.chat._update_activity("running", "project.write_file")
		main.chat._update_activity("success", "godot.test")
		var requested_state := OS.get_environment("AOI_ACTIVITY_STATE")
		if requested_state != "":
			var requested_detail := OS.get_environment("AOI_ACTIVITY_DETAIL")
			if requested_detail == "": requested_detail = requested_state
			main.chat._update_activity(requested_state, requested_detail)
		if OS.get_environment("AOI_ACTIVITY_EXPAND") == "1":
			var disclosure := main.chat.find_child("ActivityDisclosure", true, false) as Button
			if disclosure != null: disclosure.pressed.emit()
	if OS.get_environment("AOI_OTHER_CHAT_RUNNING_DEMO") == "1":
		main.go("chat")
		var background_project := Store.new_project("Sky Hop", "Build and verify a complete original mobile arcade game.")
		var background_session := Store.new_session("build", str(background_project.get("id", "")))
		(background_session["messages"] as Array).append({"role":"user", "content":"Build the complete arcade game and verify its pause and restart flow."})
		(background_session["messages"] as Array).append({"role":"assistant", "content":"I’m implementing the game and checking the complete play loop."})
		Store.save_session(background_session, true)
		main.chat._tool_session_id = str(background_session.get("id", ""))
		main.chat._tool_project_id = str(background_project.get("id", ""))
		ToolRunner.busy = true
		main.chat.new_session("chat", "")
		(main.chat.session["messages"] as Array).append({"role":"user", "content":"Can you explain how the scoring and restart flow should work?"})
		(main.chat.session["messages"] as Array).append({"role":"assistant", "content":"The score should increase only when the player collects an item. Restart should reset the round state while preserving the saved high score."})
		Store.save_session(main.chat.session, true)
		main.chat._render()
		main.chat._refresh_composer_icon()
	if OS.get_environment("AOI_APPROVAL_DEMO") == "1":
		var approval_project := Store.new_project("Sky Hop", "Build a complete original mobile arcade game with a title screen, responsive play, pause menu, saved high scores and a finished result flow.")
		approval_project["project_kind"] = "game"
		Store.save_project(approval_project)
		main.chat.new_session("build", str(approval_project.get("id", "")))
		(main.chat.session["messages"] as Array).append({"role":"user", "content":"Build a complete original arcade game with a welcome screen, pause menu, saved high scores and a restart flow."})
		(main.chat.session["messages"] as Array).append({"role":"assistant", "content":"I’m building the complete arcade experience, including its screens and saved results."})
		(main.chat.session["messages"] as Array).append({"role":"assistant", "content":"", "project_card":true, "project_id":str(approval_project.get("id", ""))})
		Store.save_session(main.chat.session, true)
		main.chat.project = Store.get_project(str(approval_project.get("id", "")))
		main.chat._render()
		main.chat._tool_session_id = str(main.chat.session.get("id", ""))
		main.chat._tool_project_id = str(approval_project.get("id", ""))
		main.chat._show_tool_approval({"name":"linux.exec", "command":"npm run build && git status --short", "cwd":"/workspace/sky-hop"})
		main.chat._queue_message_during_approval("Please make sure the pause menu and restart button are polished too.")
		if OS.get_environment("AOI_APPROVAL_EXPAND") == "1":
			var review_details: Node = main.chat.find_child("ApprovalDecisionCard", true, false)
			if review_details != null:
				var detail_button := review_details.find_child("ApprovalDetailsDisclosure", true, false) as Button
				if detail_button != null: detail_button.pressed.emit()
	if OS.get_environment("AOI_AUTONOMY_POLICY_TEST") == "1":
		var test_project := Store.new_project("Autonomy policy fixture", "Temporary runtime policy check")
		test_project["studio_remote_path"] = "/home/demo/projects/neon-collector"
		Store.save_project(test_project)
		main.chat.session = Store.new_session("build", str(test_project.get("id", "")))
		var checks := [
			{"label":"project build command", "data":{"name":"linux.exec", "command":"godot --headless --path . --quit", "cwd":"/home/demo/projects/neon-collector"}, "expected":false},
			{"label":"project git status", "data":{"name":"linux.exec", "command":"git status --short", "cwd":"/home/demo/projects/neon-collector"}, "expected":false},
			{"label":"destructive delete", "data":{"name":"linux.exec", "command":"rm -rf .", "cwd":"/home/demo/projects/neon-collector"}, "expected":true},
			{"label":"system package install", "data":{"name":"linux.exec", "command":"sudo apt install nodejs", "cwd":"/home/demo/projects/neon-collector"}, "expected":true},
			{"label":"git push", "data":{"name":"linux.exec", "command":"git push origin main", "cwd":"/home/demo/projects/neon-collector"}, "expected":true},
			{"label":"outside workspace", "data":{"name":"linux.exec", "command":"git status", "cwd":"/home/demo"}, "expected":true}
		]
		for check in checks:
			var actual: bool = main.chat._tool_requires_approval(check.data)
			print("AUTONOMY_POLICY ", check.label, " expected_approval=", check.expected, " actual_approval=", actual, " result=", "PASS" if actual == check.expected else "FAIL")
	if OS.get_environment("AOI_CREATION_CARD_DEMO") == "1":
		main.go("chat")
		var creation_project := Store.new_project("Moonlit Valley", "Create a polished original pixel-art adventure with a village, forest trail, creek crossing and ancient shrine.")
		creation_project["project_kind"] = "game"
		creation_project["aoi_work_updated_at"] = Time.get_unix_time_from_system()
		Store.save_project(creation_project)
		AgentFlow.apply_plan(str(creation_project.get("id", "")), {"summary":"Deliver a complete playable opening region from authored design through implementation, content and runtime verification.", "tasks":[
			{"title":"Design the village and opening journey","detail":"Map the village hub, route landmarks, player guidance, creek crossing and shrine approach so the opening area is readable and connected.","deliverables":["Opening region layout and traversal brief"],"role":"Planner","priority":"high","acceptance":"The player route, landmarks, optional discovery and shrine destination are described and connected.","verification":"Inspect the authored map layout and walk the route against the approved region brief.","file_scope":["world layout"],"depends_on":[]},
			{"title":"Create the player and movement systems","detail":"Implement player movement, collision, animation and touch controls with responsive input and safe cleanup when scenes change.","deliverables":["Playable player controller", "Touch control behavior"],"role":"Engineer","priority":"high","acceptance":"The player moves reliably, collides with the world and responds consistently to touch and keyboard input.","verification":"Run a movement session and check collisions, input cancellation and scene transitions.","file_scope":["player", "input"],"depends_on":["Design the village and opening journey"]},
			{"title":"Build the village and forest environments","detail":"Create the village hub, winding forest trail, creek crossing, bridge and shrine approach using the approved visual language and readable navigation cues.","deliverables":["Village scene", "Forest and creek route", "Shrine approach"],"role":"Engineer","priority":"high","acceptance":"All planned environments are connected and the player can traverse the complete opening journey.","verification":"Launch the region and inspect every route segment in a fresh runtime capture.","file_scope":["region scenes", "environment assets"],"depends_on":["Create the player and movement systems"]},
			{"title":"Add interactions and opening progression","detail":"Implement interactable objects, dialogue cues, secrets and the progression state needed to make the route feel like a complete opening chapter.","deliverables":["Interaction system", "Opening progression and optional discovery"],"role":"Engineer","priority":"normal","acceptance":"The user can interact with relevant objects and complete the intended opening journey with optional discoveries available.","verification":"Play through the route and confirm interaction feedback and saved progression state.","file_scope":["interactions", "progression"],"depends_on":["Build the village and forest environments"]},
			{"title":"Verify and polish the playable opening region","detail":"Test the full playable route, correct movement and collision defects, tune mobile presentation and confirm the region opens without runtime errors.","deliverables":["Verified playable opening region", "Visual review captures"],"role":"Reviewer","priority":"high","acceptance":"The complete opening route is playable and its controls, interactions and visuals meet the region acceptance brief.","verification":"Run a complete playthrough, inspect fresh screenshots and review the runtime log.","file_scope":["whole opening region"],"depends_on":["Add interactions and opening progression"]}
		]})
		var creation_flow := AgentFlow.get_flow(str(creation_project.get("id", "")))
		if creation_flow.get("tasks", []) is Array and not (creation_flow.get("tasks", []) as Array).is_empty():
			var first_task: Dictionary = (creation_flow.get("tasks", []) as Array)[0]
			AgentFlow.update_task(str(creation_project.get("id", "")), str(first_task.get("id", "")), {"status":"done"})
		main.chat.new_session("build", str(creation_project.get("id", "")))
		(main.chat.session["messages"] as Array).append({"role":"user", "content":"Create an original pixel-art adventure with a village, forest trail and ancient shrine."})
		(main.chat.session["messages"] as Array).append({"role":"assistant", "content":"I’m shaping the first playable region now."})
		(main.chat.session["messages"] as Array).append({"role":"assistant", "content":"", "project_card":true, "project_id":str(creation_project.get("id", ""))})
		Store.save_session(main.chat.session, true)
		main.chat.project = Store.get_project(str(creation_project.get("id", "")))
		main.chat._render()
		main.chat._update_project_experience("running", "Creating the opening scene")
		if OS.get_environment("AOI_CREATION_CARD_STALE") == "1":
			main.chat.project["aoi_work_updated_at"] = Time.get_unix_time_from_system() - 500.0
			Store.save_project(main.chat.project)
			if main.chat._project_experience_card != null:
				main.chat._project_experience_card.call("_evaluate_freshness", Time.get_unix_time_from_system() + 500.0)
	if OS.get_environment("AOI_CAPTURE_DRAWER") == "1": main.open_navigation_drawer()
	if OS.get_environment("AOI_CAPTURE_HEADER_MENU") == "1": main._open_header_menu()
	if OS.get_environment("AOI_CAPTURE_PROJECT_MENU") == "1":
		main.go("projects")
		await get_tree().process_frame
		main.projects._project_menu.position = Vector2(420, 180)
		main.projects._project_menu.popup()
	if OS.get_environment("AOI_CAPTURE_MODELS") == "1": main.open_models()
	if OS.get_environment("AOI_CAPTURE_GITHUB_CONNECTION") == "1": main._configure_github()
	if OS.get_environment("AOI_CAPTURE_LINUX_CONNECTION") == "1": main._configure_linux()
	await get_tree().create_timer(2.4).timeout
	var image := get_viewport().get_texture().get_image()
	var output := OS.get_environment("AOI_CAPTURE_PATH")
	if output == "": output = "user://review_capture.png"
	image.save_png(output)
	print("CAPTURED ", output, " ", image.get_width(), "x", image.get_height())
	get_tree().quit()
