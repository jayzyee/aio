extends VBoxContainer
## Aoi Workbench: a project-agnostic development workspace with optional Godot tooling and paired runtimes.
## The project files live either in the app sandbox or in the cloud workspace.
const Ui = preload("res://scripts/ui/Ui.gd")
const ChatScreen = preload("res://scripts/ui/ChatScreen.gd")
const REMOTE_TEXT_FILE_LIMIT := 120000

signal toast(text: String)
signal request_linux_setup

var embedded_chat: VBoxContainer
var _header_status: Label
var _content: Control
var _chat_mode_btn: Button
var _sources_mode_btn: Button
var _runs_mode_btn: Button
var _logs_toggle: CheckButton
var _selected_project: Dictionary = {}
var _view_mode := "chats"
var _file_dialog: FileDialog
var _source_preview: Window
var _request_nodes: Array[HTTPRequest] = []
var _run_state := "stopped"
var _last_logs := ""
var _tool_menu: PopupMenu
var _run_fab: Button
var _run_poll_timer: Timer
var _activity_pill: Button
var _activity_panel: PanelContainer
var _activity_title: Label
var _activity_detail: Label
var _activity_progress: ProgressBar
var _activity_steps: Array[Label] = []
var _activity_stage := "idle"
var _activity_detail_text := ""
var _fullscreen_preview: Control


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()
	ToolRunner.completed.connect(_on_studio_tool_completed)
	JobRunner.jobs_changed.connect(_on_jobs_changed)
	JobRunner.job_progress.connect(_on_job_progress)
	_refresh_connection_label()


func _build() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.add_theme_constant_override("margin_top", 2)
	top.add_theme_constant_override("margin_bottom", 2)
	top.add_child(Ui.chip("Project workspace", Ui.ACCENT))
	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(top_spacer)
	var status_col := VBoxContainer.new()
	status_col.alignment = BoxContainer.ALIGNMENT_CENTER
	status_col.add_theme_constant_override("separation", 0)
	status_col.add_child(Ui.lbl("Cloud runtime", 14, Ui.MUTED, true))
	_header_status = Ui.lbl("Cloud not connected", 15, Ui.MUTED)
	_header_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_col.add_child(_header_status)
	top.add_child(status_col)
	var connect_btn := Ui.icon_btn("settings", "quiet", 46)
	connect_btn.tooltip_text = "Cloud workspace settings"
	connect_btn.pressed.connect(request_linux_setup.emit)
	top.add_child(connect_btn)
	add_child(top)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.add_theme_constant_override("margin_top", 16)
	_chat_mode_btn = Ui.btn("Chats", "quiet")
	_sources_mode_btn = Ui.btn("Sources", "quiet")
	_runs_mode_btn = Ui.btn("Runs", "quiet")
	for tab_button in [_chat_mode_btn, _sources_mode_btn, _runs_mode_btn]:
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_mode_btn.pressed.connect(func(): _set_view_mode("chats"))
	_sources_mode_btn.pressed.connect(func(): _set_view_mode("sources"))
	_runs_mode_btn.pressed.connect(func(): _set_view_mode("runs"))
	tabs.add_child(_chat_mode_btn)
	tabs.add_child(_sources_mode_btn)
	tabs.add_child(_runs_mode_btn)
	add_child(tabs)

	var divider := ColorRect.new()
	divider.color = Ui.BORDER
	divider.custom_minimum_size.y = 1
	add_child(divider)

	_content = Control.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.clip_contents = true
	add_child(_content)

	embedded_chat = ChatScreen.new()
	embedded_chat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.add_child(embedded_chat)
	embedded_chat.visible = false
	embedded_chat.build_stage_changed.connect(_on_build_stage_changed)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_file_dialog.use_native_dialog = true
	_file_dialog.files_selected.connect(_on_local_files_selected)
	add_child(_file_dialog)

	_tool_menu = PopupMenu.new()
	_tool_menu.add_item("Run project", 0)
	_tool_menu.add_item("Stop project", 1)
	_tool_menu.add_separator()
	_tool_menu.add_item("Run project verification", 2)
	_tool_menu.add_item("Capture desktop screenshot", 3)
	_tool_menu.add_item("Collect Godot logs", 4)
	_tool_menu.add_separator()
	_tool_menu.add_item("Open run monitor", 5)
	_tool_menu.add_separator()
	_tool_menu.add_item("Godot API Explorer", 6)
	_tool_menu.add_item("Create starter 2D scene", 7)
	_tool_menu.add_item("Validate a GDScript file", 8)
	_tool_menu.add_item("Preview local scene", 9)
	_tool_menu.add_item("Open Run & results", 10)
	_tool_menu.add_item("Project task manifest guide", 11)
	Ui.style_popup_menu(_tool_menu)
	_tool_menu.id_pressed.connect(_on_tool_menu)
	add_child(_tool_menu)

	_run_fab = Ui.btn("Running on PC", "primary", "play")
	_run_fab.custom_minimum_size = Vector2(172, 54)
	_run_fab.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_run_fab.offset_left = -194
	_run_fab.offset_right = -14
	_run_fab.offset_top = 66
	_run_fab.offset_bottom = 118
	_run_fab.visible = false
	_run_fab.z_index = 30
	_run_fab.pressed.connect(_on_running_fab_pressed)
	_content.add_child(_run_fab)
	_create_activity_overlay()

	_run_poll_timer = Timer.new()
	_run_poll_timer.wait_time = 2.5
	_run_poll_timer.timeout.connect(_poll_run_status)
	add_child(_run_poll_timer)


func activate() -> void:
	_refresh_connection_label()
	if _selected_project.is_empty():
		var last_id := str(Store.get_integration("studio").get("last_project_id", ""))
		if last_id != "":
			var saved := Store.get_project(last_id)
			if not saved.is_empty():
				select_project(saved, true)
				return # select_project already restored the project session and rendered the workspace.
		_render_landing()
	else:
		_render_workspace()


func open_project(project_id: String) -> void:
	var p := Store.get_project(project_id)
	if p.is_empty(): return
	select_project(p)


func new_chat() -> void:
	if _selected_project.is_empty():
		toast.emit("Create or import a project workspace first.")
		return
	embedded_chat.new_session("build", str(_selected_project.get("id", "")))
	Store.save_session(embedded_chat.session, true)
	_selected_project["studio_session_id"] = str(embedded_chat.session.get("id", ""))
	Store.save_project(_selected_project)
	_view_mode = "chats"
	_render_workspace()


func select_project(project: Dictionary, reset_chat: bool = true) -> void:
	_selected_project = project.duplicate(true)
	var studio_settings := Store.get_integration("studio")
	studio_settings["last_project_id"] = str(_selected_project.get("id", ""))
	Store.set_integration("studio", studio_settings)
	if reset_chat:
		var project_id := str(_selected_project.get("id", ""))
		var session_id := str(_selected_project.get("studio_session_id", ""))
		var old_session := Store.load_session(session_id) if session_id != "" else {}
		# A project workspace must never silently reuse a generic chat or another
		# project's session. Old releases could leave a mismatched session ID here.
		if old_session.is_empty() or str(old_session.get("project_id", "")) != project_id:
			embedded_chat.new_session("build", project_id)
			_selected_project["studio_session_id"] = str(embedded_chat.session.get("id", ""))
			Store.save_session(embedded_chat.session, true)
			Store.save_project(_selected_project)
		else:
			embedded_chat.open_session(session_id)
			if str(embedded_chat.session.get("mode", "")) != "build": embedded_chat.set_mode("build")
	_set_view_mode("chats")


func _set_view_mode(value: String) -> void:
	_view_mode = value
	var active := Ui.box(Color("#f1f1f1"), 8)
	var quiet := Ui.box(Color(0, 0, 0, 0), 8)
	var focus := Ui.box(Color("#ffffff"), 8, Ui.ACCENT, 1)
	for pair in [[_chat_mode_btn, "chats"], [_sources_mode_btn, "sources"], [_runs_mode_btn, "runs"]]:
		var tab: Button = pair[0]
		var selected := value == str(pair[1])
		tab.add_theme_stylebox_override("normal", active if selected else quiet)
		tab.add_theme_stylebox_override("focus", focus)
		tab.add_theme_stylebox_override("hover", active if selected else Ui.box(Color("#f1f1f1"), 8))
		tab.add_theme_stylebox_override("pressed", active)
	_render_workspace() if not _selected_project.is_empty() else _render_landing()


func _render_landing() -> void:
	for child in _content.get_children():
		if child != embedded_chat and child != _run_fab and child != _activity_pill and child != _activity_panel: child.queue_free()
	embedded_chat.visible = false
	_run_fab.visible = _run_state == "running"
	_update_activity_overlay()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var pad := MarginContainer.new()
	for side in ["left", "right"]: pad.add_theme_constant_override("margin_" + side, 22)
	pad.add_theme_constant_override("margin_top", 30)
	pad.add_theme_constant_override("margin_bottom", 36)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	pad.add_child(body)
	var hero := Ui.card(28)
	var hv := Ui.card_body(hero)
	hv.add_child(Ui.lbl("Your development workspace.", Ui.FS_TITLE, Ui.TEXT, true, true))
	hv.add_child(Ui.lbl("Create a workspace or import an existing project. Aoi can inspect its structure, plan work, edit files with approval, run supported tasks and review results. Godot projects also unlock engine-specific tools and live API documentation.", Ui.FS, Ui.MUTED, false, true))
	var pc_note := Ui.chip("Connect a cloud workspace when a project needs a full Godot runtime", Ui.ACCENT)
	hv.add_child(pc_note)
	body.add_child(hero)
	var create := Ui.btn("Create a workspace", "primary", "plus")
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.pressed.connect(_open_create_project)
	body.add_child(create)
	var import_pc := Ui.btn("Import from cloud workspace", "ghost", "folder")
	import_pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_pc.pressed.connect(_import_pc_project)
	body.add_child(import_pc)
	var import_local := Ui.btn("Import a project or folder on this device", "ghost", "layers")
	import_local.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_local.pressed.connect(_open_local_project_picker)
	body.add_child(import_local)
	var sources := Ui.card(22)
	var sv := Ui.card_body(sources)
	sv.add_child(Ui.lbl("What happens next", Ui.FS + 2, Ui.TEXT, true))
	for step in ["1  Import your source files and identify the project structure", "2  Describe the outcome you want in the workspace chat", "3  Review the plan, proposed changes and approvals", "4  Run supported tasks and inspect results and logs"]:
		sv.add_child(Ui.lbl(step, Ui.FS_SMALL + 1, Ui.MUTED, false, true))
	body.add_child(sources)
	var connect := Ui.btn("Connect cloud workspace", "quiet", "terminal")
	connect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connect.pressed.connect(request_linux_setup.emit)
	body.add_child(connect)
	_update_tab_styles()


func _render_workspace() -> void:
	for child in _content.get_children():
		if child != embedded_chat and child != _run_fab and child != _activity_pill and child != _activity_panel: child.queue_free()
	var p := _selected_project
	_run_fab.visible = _run_state == "running"
	if _view_mode == "runs":
		embedded_chat.visible = false
		embedded_chat.set_history_visible(false)
		_render_runs_workspace()
		_update_tab_styles()
		_update_activity_overlay()
		return
	if _view_mode == "chats":
		embedded_chat.visible = true
		embedded_chat.set_history_visible(true, false)
		embedded_chat.set_composer_placeholder("Tell Aoi what to build…")
		# The small project context strip keeps the conversation visually light.
		var context := PanelContainer.new()
		context.set_anchors_preset(Control.PRESET_TOP_WIDE)
		context.offset_bottom = 54
		context.add_theme_stylebox_override("panel", Ui.box(Color("#f7f8fb"), 16))
		var context_margin := MarginContainer.new()
		for side in ["left", "right"]: context_margin.add_theme_constant_override("margin_" + side, 14)
		context.add_child(context_margin)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		context_margin.add_child(row)
		var folder_mark := TextureRect.new()
		folder_mark.texture = Ui.icon("folder")
		folder_mark.custom_minimum_size = Vector2(22, 22)
		folder_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		folder_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		folder_mark.modulate = Ui.MUTED
		row.add_child(folder_mark)
		var label := Ui.lbl(str(p.get("title", "Godot project")), Ui.FS_SMALL, Ui.TEXT, true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		row.add_child(Ui.chip("Build mode", Ui.ACCENT))
		_logs_toggle = CheckButton.new()
		_logs_toggle.text = "Logs"
		_logs_toggle.tooltip_text = "Include the latest Godot logs as context in the next message"
		_logs_toggle.add_theme_font_size_override("font_size", 15)
		_logs_toggle.button_pressed = bool(Store.get_integration("studio").get("include_logs", false))
		_logs_toggle.toggled.connect(func(enabled: bool):
			var cfg := Store.get_integration("studio")
			cfg["include_logs"] = enabled
			Store.set_integration("studio", cfg))
		row.add_child(_logs_toggle)
		_content.add_child(context)
		embedded_chat.offset_top = 60
		embedded_chat.offset_bottom = 0
		_update_activity_overlay()
		return
	embedded_chat.visible = true
	embedded_chat.set_history_visible(false)
	embedded_chat.set_composer_placeholder("Ask Aoi about these sources…")
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_bottom = -112
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var margin := MarginContainer.new()
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 26)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	margin.add_child(body)
	var title_row := HBoxContainer.new()
	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_child(Ui.lbl("Sources", Ui.FS_TITLE, Ui.TEXT, true))
	title_col.add_child(Ui.lbl("Files Aoi can inspect and work with", Ui.FS_SMALL, Ui.MUTED))
	title_row.add_child(title_col)
	var toolbox := Ui.icon_btn("layers", "quiet", 50)
	toolbox.tooltip_text = "Studio toolbox"
	toolbox.pressed.connect(func(): _tool_menu.position = toolbox.get_global_position() + Vector2(0, toolbox.size.y); _tool_menu.popup())
	title_row.add_child(toolbox)
	body.add_child(title_row)
	var meta := Ui.card(18)
	var mv := Ui.card_body(meta)
	mv.add_theme_constant_override("separation", 8)
	mv.add_child(Ui.lbl(str(p.get("title", "Untitled project")), Ui.FS + 2, Ui.TEXT, true, true))
	mv.add_child(Ui.lbl(str(p.get("studio_remote_path", p.get("studio_local_path", "Local workspace"))), 16, Ui.MUTED, false, true))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var add := Ui.btn("Add sources", "ghost", "plus")
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.pressed.connect(_open_source_picker)
	actions.add_child(add)
	var new_script := Ui.btn("New script", "ghost", "code")
	new_script.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_script.pressed.connect(_open_new_script)
	actions.add_child(new_script)
	mv.add_child(actions)
	var pc_path := str(p.get("studio_remote_path", ""))
	if pc_path != "":
		var run_row := HBoxContainer.new()
		run_row.add_theme_constant_override("separation", 8)
		var run := Ui.btn("Run", "primary", "play")
		run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		run.pressed.connect(func(): _pc_project_action("run"))
		run_row.add_child(run)
		var stop := Ui.btn("Stop", "quiet", "stop")
		stop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stop.pressed.connect(func(): _pc_project_action("stop"))
		run_row.add_child(stop)
		mv.add_child(run_row)
		var test := Ui.btn("Run project verification", "quiet", "check")
		test.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		test.pressed.connect(func(): _pc_project_action("test"))
		mv.add_child(test)
	else:
		mv.add_child(Ui.lbl("On-device workspace · inspect files, validate supported scripts and run project-declared headless tasks. Other runtimes can use an optional companion.", Ui.FS_SMALL, Ui.MUTED, false, true))
		var open_runs := Ui.btn("Open Run & results", "quiet", "chart")
		open_runs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open_runs.pressed.connect(func(): _set_view_mode("runs"))
		mv.add_child(open_runs)
	body.add_child(meta)
	var status_row := HBoxContainer.new()
	status_row.add_child(Ui.lbl("Project files", Ui.FS + 1, Ui.TEXT, true))
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; status_row.add_child(spacer)
	var refresh := Ui.icon_btn("regenerate", "quiet", 40)
	refresh.tooltip_text = "Refresh files"
	refresh.pressed.connect(_refresh_sources)
	status_row.add_child(refresh)
	body.add_child(status_row)
	var files := _get_visible_files()
	if files.is_empty():
		var empty := Ui.card(24)
		var ev := Ui.card_body(empty)
		ev.add_child(Ui.lbl("No source files yet", Ui.FS + 1, Ui.TEXT, true))
		ev.add_child(Ui.lbl("Add scripts, scenes, images, notes or source documents. Aoi will use these as project context.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
		var empty_add := Ui.btn("Add your first sources", "primary", "plus")
		empty_add.pressed.connect(_open_source_picker)
		ev.add_child(empty_add)
		body.add_child(empty)
	else:
		for item in files:
			body.add_child(_file_row(item))
	var tool_hint := Ui.lbl("Toolbox: run · stop · verification · screenshot · Godot logs", 15, Ui.MUTED, false, true)
	body.add_child(tool_hint)
	var next_step := Ui.card(16)
	var next_body := Ui.card_body(next_step)
	next_body.add_child(Ui.lbl("Ready for the next instruction", Ui.FS_SMALL, Ui.TEXT, true))
	next_body.add_child(Ui.lbl("Tell Aoi what to add or change. New scripts, scenes and resources will appear in this project tree after the workspace refreshes.", 15, Ui.MUTED, false, true))
	var continue_chat := Ui.btn("Continue in Chats", "quiet", "new_chat")
	continue_chat.pressed.connect(func(): _set_view_mode("chats"))
	next_body.add_child(continue_chat)
	body.add_child(next_step)
	_update_tab_styles()
	_update_activity_overlay()


func _render_runs_workspace() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_bottom = -4
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var margin := MarginContainer.new()
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 28)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	margin.add_child(body)
	var title_row := HBoxContainer.new()
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(Ui.lbl("Run & results", Ui.FS_TITLE, Ui.TEXT, true))
	heading.add_child(Ui.lbl("Headless tasks · output files · logs · checkpoints", Ui.FS_SMALL, Ui.MUTED))
	title_row.add_child(heading)
	var refresh := Ui.icon_btn("regenerate", "quiet", 44)
	refresh.tooltip_text = "Refresh project task state"
	refresh.pressed.connect(_render_workspace)
	title_row.add_child(refresh)
	body.add_child(title_row)

	var project_id := str(_selected_project.get("id", ""))
	var info := JobRunner.inspect_project(project_id)
	if bool(info.get("ok", false)):
		var profile := Ui.card(16)
		var profile_body := Ui.card_body(profile)
		var types: Array = info.get("detected_types", ["generic"])
		var pretty: Array[String] = []
		for kind in types: pretty.append(str(kind).capitalize())
		profile_body.add_child(Ui.lbl(str(info.get("name", "Project")), Ui.FS + 1, Ui.TEXT, true))
		profile_body.add_child(Ui.lbl("Detected: %s · %d declared tasks" % [", ".join(pretty), int(info.get("task_count", 0))], Ui.FS_SMALL, Ui.MUTED, false, true))
		body.add_child(profile)

	var tasks_result := JobRunner.list_project_tasks(project_id)
	body.add_child(Ui.lbl("Runnable project tasks", Ui.FS + 1, Ui.TEXT, true))
	if bool(tasks_result.get("ok", false)):
		var tasks: Array = tasks_result.get("tasks", [])
		if tasks.is_empty():
			body.add_child(_empty_tasks_card("No tasks are declared yet", "Aoi can inspect this project's actual files and prepare a generic task manifest for training, tests, data processing, simulations or other headless work."))
		else:
			for task in tasks:
				body.add_child(_project_task_card(task))
	else:
		var message := str(tasks_result.get("error", "No task manifest is available."))
		body.add_child(_empty_tasks_card("No runnable task manifest", message + " Aoi does not assume what this project does. It must inspect the project and define a task that matches its own entry points."))
	var prepare := Ui.btn("Ask Aoi to prepare a task for this project", "primary", "sparkles")
	prepare.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prepare.pressed.connect(_prepare_project_task_with_aoi)
	body.add_child(prepare)
	body.add_child(Ui.lbl("Recent runs", Ui.FS + 1, Ui.TEXT, true))
	var jobs := JobRunner.list_jobs(project_id)
	if jobs.is_empty():
		body.add_child(_empty_tasks_card("No runs yet", "When a project task is declared and approved, Aoi will show its progress, output, metrics, logs and checkpoints here. A screen preview is not required for headless work."))
	else:
		for job in jobs:
			body.add_child(_job_card(job))
	var back := Ui.btn("Back to project sources", "quiet", "folder")
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func(): _set_view_mode("sources"))
	body.add_child(back)


func _empty_tasks_card(title: String, description: String) -> Control:
	var card := Ui.card(18)
	var body := Ui.card_body(card)
	body.add_child(Ui.lbl(title, Ui.FS, Ui.TEXT, true))
	body.add_child(Ui.lbl(description, Ui.FS_SMALL, Ui.MUTED, false, true))
	return card


func _project_task_card(task: Dictionary) -> Control:
	var card := Ui.card(16)
	var body := Ui.card_body(card)
	var row := HBoxContainer.new()
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_child(Ui.lbl(str(task.get("name", task.get("id", "Task"))), Ui.FS, Ui.TEXT, true, true))
	text_col.add_child(Ui.lbl(str(task.get("description", "No description provided.")), Ui.FS_SMALL, Ui.MUTED, false, true))
	text_col.add_child(Ui.lbl("%s · %s" % [str(task.get("runtime", "unknown")), str(task.get("script", ""))], 13, Ui.MUTED, false, true))
	row.add_child(text_col)
	var runtime := str(task.get("runtime", ""))
	var can_run := runtime == "gdscript_steps"
	var run := Ui.btn("Run", "primary" if can_run else "quiet", "play")
	run.disabled = not can_run
	run.custom_minimum_size.x = 84
	run.pressed.connect(func(): _confirm_run_project_task(task))
	row.add_child(run)
	body.add_child(row)
	if not can_run:
		body.add_child(Ui.lbl("Requires a connected %s runtime; it cannot run on this phone yet." % runtime, 13, Ui.AMBER, false, true))
	return card


func _confirm_run_project_task(task: Dictionary) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Run project task?"
	dialog.dialog_text = "Run '%s' from %s?

The declared GDScript task executes as trusted code inside Aoi's process with the app's permissions. It is not isolated by an operating-system sandbox. Inspect the script first if you did not create it." % [str(task.get("name", task.get("id", "Task"))), str(task.get("script", ""))]
	dialog.ok_button_text = "Run task"
	dialog.confirmed.connect(func():
		var result := JobRunner.start_project_task(str(_selected_project.get("id", "")), str(task.get("id", "")), {})
		if not bool(result.get("ok", false)):
			toast.emit(str(result.get("error", "Could not start project task.")))
		else:
			toast.emit("Task started. Progress and artifacts will appear below.")
		_render_workspace())
	add_child(dialog)
	dialog.popup_centered(Vector2i(560, 340))


func _prepare_project_task_with_aoi() -> void:
	_set_view_mode("chats")
	var chat_input := embedded_chat.get("_input") as TextEdit
	if chat_input != null:
		chat_input.text = "Inspect this project without assuming its domain. Identify its language, main entry points, supported runtimes and any existing test/training/evaluation commands. If a useful headless task can run on this phone, propose a generic .aoi/tasks.json manifest and a project-owned GDScript step task that calls the project's existing code rather than reimplementing its logic. Keep it project-agnostic in Aoi core. Explain the trusted-code execution boundary, use bounded steps and checkpoints, and ask before creating files. If the needed runtime is unavailable on this device, report that clearly and do not fabricate a successful run."
		chat_input.grab_focus()
	toast.emit("Aoi is ready to inspect this project and prepare a generic task contract.")


func _job_card(job: Dictionary) -> Control:
	var card := Ui.card(18)
	var v := Ui.card_body(card)
	var title_row := HBoxContainer.new()
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.add_child(Ui.lbl(str(job.get("task_name", job.get("task_id", "Project task"))), Ui.FS, Ui.TEXT, true, true))
	name_col.add_child(Ui.lbl(str(job.get("id", "")), 13, Ui.MUTED))
	title_row.add_child(name_col)
	var state := str(job.get("state", "queued")).capitalize()
	var tint := Ui.GREEN if state == "Completed" else (Ui.AMBER if state in ["Running", "Paused", "Interrupted"] else Ui.MUTED)
	title_row.add_child(Ui.chip(state, tint))
	v.add_child(title_row)
	v.add_child(Ui.lbl(str(job.get("summary", "Queued")), Ui.FS_SMALL, Ui.MUTED, false, true))
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 1
	bar.value = float(job.get("progress", 0.0))
	bar.custom_minimum_size.y = 7
	bar.show_percentage = false
	v.add_child(bar)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	var job_id := str(job.get("id", ""))
	if state == "Running":
		var pause := Ui.btn("Pause", "ghost", "pause")
		pause.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pause.pressed.connect(func(): JobRunner.pause_job(job_id); _render_workspace())
		actions.add_child(pause)
		var cancel := Ui.btn("Stop", "quiet", "stop")
		cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cancel.pressed.connect(func(): JobRunner.cancel_job(job_id); _render_workspace())
		actions.add_child(cancel)
	elif state in ["Paused", "Interrupted", "Failed"] and bool(job.get("resumable", false)):
		var resume := Ui.btn("Resume", "primary", "play")
		resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		resume.pressed.connect(func(): _confirm_resume_project_task(job_id))
		actions.add_child(resume)
	if state in ["Completed", "Failed", "Interrupted", "Cancelled"]:
		for artifact in ["report.md", "metrics.json", "result.json", "run.log"]:
			var label := str(artifact).get_basename().capitalize()
			var button := Ui.btn(label, "quiet" if artifact != "report.md" else "ghost", "notebook" if artifact == "report.md" else "chart")
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.pressed.connect(func(): _show_job_artifact(job_id, artifact))
			actions.add_child(button)
	v.add_child(actions)
	return card


func _confirm_resume_project_task(job_id: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Resume project task?"
	dialog.dialog_text = "Resume this task from its last checkpoint? Its GDScript will execute again inside Aoi with the app's permissions."
	dialog.ok_button_text = "Resume"
	dialog.confirmed.connect(func():
		var result := JobRunner.resume_job(job_id)
		if not bool(result.get("ok", false)): toast.emit(str(result.get("error", "Could not resume task.")))
		_render_workspace())
	add_child(dialog)
	dialog.popup_centered(Vector2i(520, 280))


func _show_job_artifact(job_id: String, artifact: String) -> void:
	var result := JobRunner.read_artifact(job_id, artifact)
	if not bool(result.get("ok", false)):
		toast.emit(str(result.get("error", "Could not read artifact.")))
		return
	var win := Window.new()
	win.title = "%s · %s" % [job_id, artifact]
	win.size = Vector2i(680, 900)
	win.min_size = Vector2i(420, 600)
	win.transient = true
	var shell := VBoxContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: shell.add_theme_constant_override("margin_" + side, 16)
	shell.add_theme_constant_override("margin_top", 16)
	shell.add_theme_constant_override("margin_bottom", 16)
	shell.add_theme_constant_override("separation", 10)
	win.add_child(shell)
	shell.add_child(Ui.lbl(artifact, Ui.FS_TITLE, Ui.TEXT, true))
	var content := TextEdit.new()
	content.editable = false
	content.text = str(result.get("content", ""))
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_color_override("font_color", Ui.TEXT)
	content.add_theme_stylebox_override("normal", Ui.box(Color("#f7f8fb"), 12, Ui.BORDER, 1))
	shell.add_child(content)
	var close := Ui.btn("Close", "quiet")
	close.pressed.connect(win.queue_free)
	shell.add_child(close)
	add_child(win)
	win.popup_centered()


func _on_jobs_changed() -> void:
	if not is_inside_tree() or _selected_project.is_empty(): return
	if _view_mode == "runs": _render_workspace()


func _on_job_progress(job_id: String, progress: float, detail: String) -> void:
	if not is_inside_tree() or _view_mode != "runs": return
	# JobRunner emits jobs_changed at every saved batch; this signal keeps the
	# update path explicit and avoids polling an unrelated desktop runtime.
	if JobRunner.get_job(job_id).get("project_id", "") == str(_selected_project.get("id", "")):
		_update_activity_overlay()


func _create_activity_overlay() -> void:
	_activity_pill = Ui.btn("Planning · 1 of 4", "quiet", "chevron_down")
	_activity_pill.add_theme_stylebox_override("normal", Ui.box(Color("#f7f7f7"), 8))
	_activity_pill.add_theme_stylebox_override("hover", Ui.box(Color("#f1f1f1"), 8))
	_activity_pill.add_theme_color_override("font_color", Ui.TEXT)
	_activity_pill.custom_minimum_size = Vector2(220, 50)
	_activity_pill.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_activity_pill.offset_left = 16
	_activity_pill.offset_right = 248
	_activity_pill.offset_top = -166
	_activity_pill.offset_bottom = -112
	_activity_pill.z_index = 36
	_activity_pill.visible = false
	_activity_pill.pressed.connect(_toggle_activity_panel)
	_content.add_child(_activity_pill)

	_activity_panel = PanelContainer.new()
	_activity_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_activity_panel.offset_left = 16
	_activity_panel.offset_right = 356
	_activity_panel.offset_top = -430
	_activity_panel.offset_bottom = -176
	_activity_panel.z_index = 35
	_activity_panel.visible = false
	_activity_panel.add_theme_stylebox_override("panel", Ui.pad(Ui.box(Ui.SURFACE, 22, Ui.BORDER, 1), 20, 16))
	_content.add_child(_activity_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	_activity_panel.add_child(body)
	var header := HBoxContainer.new()
	_activity_title = Ui.lbl("Aoi is planning", Ui.FS, Ui.TEXT, true)
	_activity_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_activity_title)
	var close := Ui.icon_btn("close", "quiet", 34)
	close.pressed.connect(func(): _activity_panel.visible = false)
	header.add_child(close)
	body.add_child(header)
	_activity_detail = Ui.lbl("Preparing your project workspace.", Ui.FS_SMALL, Ui.MUTED, false, true)
	body.add_child(_activity_detail)
	_activity_progress = ProgressBar.new()
	_activity_progress.min_value = 0
	_activity_progress.max_value = 4
	_activity_progress.value = 0
	_activity_progress.custom_minimum_size.y = 8
	_activity_progress.show_percentage = false
	body.add_child(_activity_progress)
	var step_row := HBoxContainer.new()
	step_row.add_theme_constant_override("separation", 6)
	for title in ["Plan", "Build", "Run", "Review"]:
		var step := Ui.lbl(str(title), 14, Ui.MUTED, true)
		step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		step_row.add_child(step)
		_activity_steps.append(step)
	body.add_child(step_row)
	var hint := Ui.lbl("Aoi keeps working inside this project. Higher-risk actions pause for your review.", 14, Ui.MUTED, false, true)
	body.add_child(hint)


func _toggle_activity_panel() -> void:
	_activity_panel.visible = not _activity_panel.visible
	if _activity_panel.visible:
		_activity_panel.move_to_front()
		_activity_pill.move_to_front()


func _on_build_stage_changed(stage: String, detail: String) -> void:
	_activity_stage = stage
	_activity_detail_text = detail
	_update_activity_overlay()
	if stage == "complete":
		_activity_panel.visible = false


func _update_activity_overlay() -> void:
	if _activity_pill == null or _activity_panel == null:
		return
	var show_activity := _selected_project.size() > 0 and _view_mode == "chats" and _activity_stage not in ["idle", "complete"]
	_activity_pill.visible = show_activity or (_selected_project.size() > 0 and _view_mode == "chats" and _activity_stage == "complete")
	if _view_mode != "chats":
		_activity_panel.visible = false
	if not _activity_pill.visible:
		_activity_panel.visible = false
		return
	var stage_index := 0
	var label := "Planning"
	match _activity_stage:
		"planning": stage_index = 0; label = "Planning"
		"building": stage_index = 1; label = "Building"
		"approval": stage_index = 1; label = "Needs approval"
		"running": stage_index = 2; label = "Running tool"
		"reviewing": stage_index = 3; label = "Reviewing"
		"complete": stage_index = 4; label = "Step complete"
		"error": stage_index = 1; label = "Needs attention"
		"paused": stage_index = 1; label = "Paused"
	_activity_pill.text = label + "  ·  " + str(min(stage_index + 1, 4)) + "/4"
	_activity_title.text = "Aoi · " + label.to_lower()
	_activity_detail.text = _activity_detail_text
	_activity_progress.value = stage_index
	for i in range(_activity_steps.size()):
		_activity_steps[i].add_theme_color_override("font_color", Ui.ACCENT if i <= min(stage_index, 3) else Ui.MUTED)


func _update_tab_styles() -> void:
	var on := Ui.box(Color("#f1f1f1"), 8)
	var off := Ui.box(Color(0, 0, 0, 0), 8)
	_chat_mode_btn.add_theme_stylebox_override("normal", on if _view_mode == "chats" else off)
	_chat_mode_btn.add_theme_stylebox_override("focus", on if _view_mode == "chats" else off)
	_sources_mode_btn.add_theme_stylebox_override("normal", on if _view_mode == "sources" else off)
	_sources_mode_btn.add_theme_stylebox_override("focus", on if _view_mode == "sources" else off)
	_runs_mode_btn.add_theme_stylebox_override("normal", on if _view_mode == "runs" else off)
	_runs_mode_btn.add_theme_stylebox_override("focus", on if _view_mode == "runs" else off)


func _file_row(item: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", Ui.box(Ui.SURFACE, 14, Ui.BORDER, 1))
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	inner.add_theme_constant_override("margin_left", 12)
	inner.add_theme_constant_override("margin_right", 12)
	inner.add_theme_constant_override("margin_top", 9)
	inner.add_theme_constant_override("margin_bottom", 9)
	row.add_child(inner)
	var is_dir := str(item.get("type", "file")) in ["directory", "dir"]
	var icon := TextureRect.new()
	icon.texture = Ui.icon("folder" if is_dir else ("code" if str(item.get("name", "")).ends_with(".gd") else "notebook"))
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	inner.add_child(icon)
	var label_col := VBoxContainer.new()
	label_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_col.add_child(Ui.lbl(str(item.get("name", "")), Ui.FS_SMALL + 1, Ui.TEXT, true))
	label_col.add_child(Ui.lbl(str(item.get("path", "")), 14, Ui.MUTED))
	inner.add_child(label_col)
	var open := Ui.icon_btn("chevron_right", "quiet", 36)
	open.pressed.connect(func(): _open_source_preview(item))
	inner.add_child(open)
	return row


func _get_visible_files() -> Array:
	if _selected_project.has("studio_remote_files"):
		var remote: Variant = _selected_project.get("studio_remote_files", [])
		if remote is Array: return remote
	var local_path := _local_project_absolute_path()
	if local_path == "": return []
	var out: Array = []
	_scan_local_directory(local_path, "", out, 0)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_dir := str(a.get("type", "")) == "directory"
		var b_dir := str(b.get("type", "")) == "directory"
		if a_dir != b_dir: return a_dir
		return str(a.get("path", "")).to_lower() < str(b.get("path", "")).to_lower())
	return out


func _scan_local_directory(root_path: String, relative: String, out: Array, depth: int) -> void:
	if depth > 5 or out.size() >= 250: return
	var absolute := root_path.path_join(relative) if relative != "" else root_path
	var dir := DirAccess.open(absolute)
	if dir == null: return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "" and out.size() < 250:
		if name in [".git", ".godot", "node_modules", "__pycache__", ".venv", ".env"] or (name.begins_with(".") and name not in [".aoi", ".gitignore", ".editorconfig", ".gitattributes"]):
			name = dir.get_next(); continue
		var rel := relative.path_join(name) if relative != "" else name
		var is_dir := dir.current_is_dir()
		out.append({"name":name,"path":rel,"type":"directory" if is_dir else "file"})
		if is_dir: _scan_local_directory(root_path, rel, out, depth + 1)
		name = dir.get_next()
	dir.list_dir_end()


func _local_project_absolute_path() -> String:
	var external := str(_selected_project.get("studio_local_external_path", ""))
	if external != "": return external
	var rel := str(_selected_project.get("studio_local_path", ""))
	if rel == "": return ""
	return ProjectSettings.globalize_path(Store.root.path_join(rel))


func _create_local_workspace(title: String, goal: String) -> void:
	var clean_title := _normalize_workspace_title(title)
	var clean_goal := _normalize_workspace_goal(goal)
	if clean_title == "" or clean_goal == "":
		toast.emit("Enter a project name and a short project goal.")
		return
	var project := Store.new_project(clean_title, clean_goal)
	if project.is_empty():
		toast.emit("Aoi couldn't save the project record. Check available storage and try again.")
		return
	var relative := "studio/projects/" + str(project.get("id", ""))
	var absolute := ProjectSettings.globalize_path(Store.root.path_join(relative))
	for folder in ["scenes", "scripts", "sources", ".aoi"]:
		var folder_path := absolute.path_join(folder)
		var folder_error := DirAccess.make_dir_recursive_absolute(folder_path)
		if folder_error != OK and not DirAccess.dir_exists_absolute(folder_path):
			_remove_tree(absolute)
			Store.delete_project(str(project.get("id", "")))
			toast.emit("Couldn't create the project folder. Check available storage and try again.")
			return
	var project_config := "; Created by Aoi Studio\nconfig_version=5\n\n[application]\nconfig/name=%s\nrun/main_scene=\"res://scenes/main.tscn\"\nconfig/features=PackedStringArray(\"4.0\", \"GL Compatibility\")\n\n[display]\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=720\n\n[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\n" % JSON.stringify(clean_title)
	var files := {
		"project.godot":project_config,
		"scenes/main.tscn":"[gd_scene format=3]\n\n[node name=\"Main\" type=\"Node2D\"]\n",
		"README.md":"# %s\n\nCreated with Aoi Studio.\n\n## Goal\n%s\n" % [clean_title, clean_goal],
		".aoi_studio/project.json":JSON.stringify({"created_by":"Aoi Studio","version":1,"goal":clean_goal}, "\t")
	}
	for path in files:
		if not _write_local_text(absolute.path_join(str(path)), str(files[path])):
			_remove_tree(absolute)
			Store.delete_project(str(project.get("id", "")))
			toast.emit("Couldn't finish creating the project files. Check available storage and try again.")
			return
	project["studio_local_path"] = relative
	project["studio_origin"] = "phone"
	if not Store.save_project(project):
		_remove_tree(absolute)
		Store.delete_project(str(project.get("id", "")))
		toast.emit("Aoi couldn't save the project location. The incomplete workspace was removed.")
		return
	select_project(project)
	toast.emit("Project workspace created on this phone. Pair a PC to run it in Godot.")


func _create_generic_local_workspace(title: String, goal: String) -> void:
	var clean_title := _normalize_workspace_title(title)
	var clean_goal := _normalize_workspace_goal(goal)
	if clean_title == "" or clean_goal == "":
		toast.emit("Enter a project name and a short project goal.")
		return
	var project := Store.new_project(clean_title, clean_goal)
	if project.is_empty():
		toast.emit("Aoi couldn't save the project record. Check available storage and try again.")
		return
	var relative := "studio/projects/" + str(project.get("id", ""))
	var absolute := ProjectSettings.globalize_path(Store.root.path_join(relative))
	for folder in ["sources", "data", "outputs", ".aoi"]:
		var folder_path := absolute.path_join(folder)
		var folder_error := DirAccess.make_dir_recursive_absolute(folder_path)
		if folder_error != OK and not DirAccess.dir_exists_absolute(folder_path):
			_remove_tree(absolute)
			Store.delete_project(str(project.get("id", "")))
			toast.emit("Couldn't create the project folder. Check available storage and try again.")
			return
	var files := {
		"README.md":"# %s\n\nCreated with Aoi Studio as a general-purpose project workspace.\n\n## Goal\n%s\n" % [clean_title, clean_goal],
		".aoi/project.json":JSON.stringify({"created_by":"Aoi Studio","schema_version":1,"project_goal":clean_goal}, "\t")
	}
	for path in files:
		if not _write_local_text(absolute.path_join(str(path)), str(files[path])):
			_remove_tree(absolute)
			Store.delete_project(str(project.get("id", "")))
			toast.emit("Couldn't finish creating the project files. Check available storage and try again.")
			return
	project["studio_local_path"] = relative
	project["studio_origin"] = "phone-general-workspace"
	if not Store.save_project(project):
		_remove_tree(absolute)
		Store.delete_project(str(project.get("id", "")))
		toast.emit("Aoi couldn't save the project location. The incomplete workspace was removed.")
		return
	select_project(project)
	toast.emit("General project workspace created. Aoi will detect the appropriate runtime from your files.")


func _normalize_workspace_title(title: String) -> String:
	return title.strip_edges().replace("\r", " ").replace("\n", " ").left(80)


func _normalize_workspace_goal(goal: String) -> String:
	return goal.strip_edges().left(2400)


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while name != "":
		if name not in [".", ".."]:
			var child := path.path_join(name)
			if directory.current_is_dir(): _remove_tree(child)
			else: DirAccess.remove_absolute(child)
		name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _write_local_text(path: String, content: String) -> bool:
	return Store.write_text_atomic(path, content)


func _open_create_project() -> void:
	var win := Window.new()
	win.title = "Create a project workspace"
	win.size = Vector2i(560, 460)
	win.transient = true
	win.exclusive = true
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.add_theme_constant_override("margin_left", 22)
	box.add_theme_constant_override("margin_right", 22)
	box.add_theme_constant_override("margin_top", 22)
	box.add_theme_constant_override("margin_bottom", 22)
	win.add_child(box)
	box.add_child(Ui.lbl("Start with a clear project brief", Ui.FS + 2, Ui.TEXT, true))
	var name := Ui.line("Project name")
	name.text = "My Project"
	box.add_child(name)
	var goal := TextEdit.new()
	goal.placeholder_text = "Tell Aoi what you want to build…"
	goal.custom_minimum_size.y = 130
	goal.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	goal.add_theme_color_override("font_color", Ui.TEXT)
	goal.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Ui.CARD_HI, 16, Ui.BORDER, 1), 16, 12))
	box.add_child(goal)
	box.add_child(Ui.lbl("Create a project on this device, or in your connected cloud workspace when you need the full Godot runtime. Choose the Godot workspace for a game or Godot app.", Ui.FS_SMALL, Ui.MUTED, false, true))
	var create_on_pc := CheckButton.new()
	create_on_pc.text = "Create in cloud workspace"
	create_on_pc.button_pressed = _pc_configured()
	create_on_pc.disabled = not _pc_configured()
	box.add_child(create_on_pc)
	var general_workspace := CheckButton.new()
	general_workspace.text = "General-purpose workspace (no project.godot starter)"
	box.add_child(general_workspace)
	var buttons := HBoxContainer.new()
	var cancel := Ui.btn("Cancel", "quiet")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(win.queue_free)
	buttons.add_child(cancel)
	var create := Ui.btn("Create workspace", "primary", "plus")
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.pressed.connect(func():
		var clean := _normalize_workspace_title(name.text)
		if clean == "": toast.emit("Enter a project name."); return
		var brief := _normalize_workspace_goal(goal.text)
		if brief == "":
			toast.emit("Add a short project goal so Aoi can understand what you want to build.")
			return
		win.queue_free()
		if create_on_pc.button_pressed: _create_pc_workspace(clean, brief)
		elif general_workspace.button_pressed: _create_generic_local_workspace(clean, brief)
		else: _create_local_workspace(clean, brief))
	buttons.add_child(create)
	box.add_child(buttons)
	add_child(win)
	win.popup_centered()
	name.grab_focus.call_deferred()


func _open_local_project_picker() -> void:
	var dialog := FileDialog.new()
	dialog.title = "Choose any project folder"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.use_native_dialog = true
	dialog.dir_selected.connect(_import_local_project_folder)
	add_child(dialog)
	dialog.popup_centered_ratio(0.9)


func _import_local_project_folder(source_root: String) -> void:
	if source_root.strip_edges() == "" or not DirAccess.dir_exists_absolute(source_root):
		toast.emit("Choose an accessible project folder.")
		return
	var project := Store.new_project(source_root.get_file(), "Imported local project")
	if project.is_empty():
		toast.emit("Aoi couldn't save the import record. Check available storage and try again.")
		return
	var relative := "studio/projects/" + str(project.get("id", ""))
	var destination := ProjectSettings.globalize_path(Store.root.path_join(relative))
	DirAccess.make_dir_recursive_absolute(destination)
	var stats := {"files": 0, "bytes": 0}
	var copy_result := _copy_project_directory(source_root, destination, "", 0, stats)
	if not bool(copy_result.get("ok", false)) or int(stats.files) == 0:
		_remove_tree(destination)
		Store.delete_project(str(project.get("id", "")))
		toast.emit(str(copy_result.get("error", "The selected folder did not contain importable files.")))
		return
	project["studio_local_path"] = relative
	project["studio_origin"] = "local-folder-import"
	project["studio_source_path"] = source_root
	project["studio_import_files"] = int(stats.files)
	project["studio_import_bytes"] = int(stats.bytes)
	if not Store.save_project(project):
		_remove_tree(destination)
		Store.delete_project(str(project.get("id", "")))
		toast.emit("Aoi couldn't save the imported project location. The incomplete import was removed.")
		return
	select_project(project)
	var info := JobRunner.inspect_project(str(project.get("id", "")))
	toast.emit("Imported %d files · detected %s project · ready for inspection." % [int(stats.files), str(info.get("primary_type", "generic")).capitalize()])


func _copy_project_directory(source_root: String, destination_root: String, relative: String, depth: int, stats: Dictionary) -> Dictionary:
	if depth > 16: return {"ok": false, "error": "Project import exceeded the folder depth limit (16)."}
	var source_dir := DirAccess.open(source_root.path_join(relative) if relative != "" else source_root)
	if source_dir == null: return {"ok": false, "error": "Could not read folder: " + relative}
	# Godot hides dotfiles/directories by default. Explicitly include them so
	# portable project metadata such as .aoi/tasks.json is preserved; the
	# allow/deny filter below still excludes credentials and private caches.
	source_dir.include_hidden = true
	source_dir.list_dir_begin()
	var entry := source_dir.get_next()
	while entry != "":
		# Keep Aoi's task manifest and common project dotfiles, but never import
		# private environment files or arbitrary hidden caches into the workspace.
		if entry in [".", "..", ".git", ".godot", "node_modules", ".venv", "__pycache__", "build", "dist", ".env"] or (entry.begins_with(".") and entry not in [".aoi", ".gitignore", ".editorconfig", ".gitattributes"]):
			entry = source_dir.get_next()
			continue
		var child_relative := relative.path_join(entry) if relative != "" else entry
		if not GodotSandbox.is_safe_project_path(child_relative):
			source_dir.list_dir_end()
			return {"ok": false, "error": "Unsafe path rejected during import: " + child_relative}
		var is_dir := source_dir.current_is_dir()
		if is_dir:
			DirAccess.make_dir_recursive_absolute(destination_root.path_join(child_relative))
			var nested := _copy_project_directory(source_root, destination_root, child_relative, depth + 1, stats)
			if not bool(nested.get("ok", false)):
				source_dir.list_dir_end()
				return nested
		else:
			if int(stats.files) >= 4000:
				source_dir.list_dir_end()
				return {"ok": false, "error": "Project has more than 4,000 files. Import a smaller source set or use the Cloud runtime later."}
			var source_path := source_root.path_join(child_relative)
			var size := FileAccess.get_size(source_path)
			if size > 64 * 1024 * 1024:
				source_dir.list_dir_end()
				return {"ok": false, "error": "File exceeds the 64 MiB per-file import limit: " + child_relative}
			if int(stats.bytes) + size > 256 * 1024 * 1024:
				source_dir.list_dir_end()
				return {"ok": false, "error": "Project exceeds the 256 MiB mobile import budget. Use a smaller source selection or the optional Cloud runtime."}
			var source := FileAccess.open(source_path, FileAccess.READ)
			if source == null:
				source_dir.list_dir_end()
				return {"ok": false, "error": "Could not read project file: " + child_relative}
			var bytes := source.get_buffer(size)
			source.close()
			if bytes.size() != size:
				source_dir.list_dir_end()
				return {"ok": false, "error": "Could not read the complete project file: " + child_relative}
			var target_path := destination_root.path_join(child_relative)
			if not Store.write_bytes_atomic(target_path, bytes):
				source_dir.list_dir_end()
				return {"ok": false, "error": "Could not safely write imported file: " + child_relative}
			stats.files = int(stats.files) + 1
			stats.bytes = int(stats.bytes) + bytes.size()
		entry = source_dir.get_next()
	source_dir.list_dir_end()
	return {"ok": true}


func _import_pc_project() -> void:
	if not _pc_configured():
		request_linux_setup.emit()
		return
	_pc_request("POST", "/v1/godot/projects", {}, func(ok: bool, data: Dictionary):
			if not ok:
				toast.emit("Couldn't read projects from the cloud workspace: " + str(data.get("error", "connection failed")))
				return
			var projects: Array = data.get("projects", [])
			if projects.is_empty(): toast.emit("No project.godot files were found in the cloud workspace."); return
			_show_pc_project_picker(projects))


func _show_pc_project_picker(projects: Array) -> void:
	var win := Window.new()
	win.title = "Import a Godot project from cloud workspace"
	win.size = Vector2i(620, 740)
	win.transient = true
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.add_theme_constant_override("margin_left", 18)
	body.add_theme_constant_override("margin_right", 18)
	body.add_theme_constant_override("margin_top", 18)
	body.add_theme_constant_override("margin_bottom", 18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	win.add_child(scroll)
	body.add_child(Ui.lbl("Projects found in your cloud workspace", Ui.FS, Ui.TEXT, true, true))
	for item in projects:
		var entry: Dictionary = item
		var button := Ui.btn(str(entry.get("name", "Godot project")) + "\n" + str(entry.get("path", "")), "ghost", "folder")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 76
		button.pressed.connect(func():
			var project := Store.new_project(str(entry.get("name", "Imported Godot project")), "Imported from the connected cloud workspace.")
			if project.is_empty():
				toast.emit("Aoi couldn't save the cloud project record. Check available storage and try again.")
				return
			project["studio_remote_path"] = str(entry.get("path", ""))
			project["studio_origin"] = "cloud"
			project["studio_runtime"] = "godot"
			project["runtime_device"] = "cloud_linux"
			project["project_kind"] = "game"
			if not Store.save_project(project):
				Store.delete_project(str(project.get("id", "")))
				toast.emit("Aoi couldn't save the cloud project connection. Try importing it again.")
				return
			win.queue_free()
			select_project(project))
		body.add_child(button)
	add_child(win)
	win.popup_centered()


func _open_source_picker() -> void:
	if _selected_project.is_empty(): return
	_file_dialog.title = "Add source files to Aoi Workbench"
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_file_dialog.popup_centered_ratio(0.9)


static func _source_upload_request(file_name: String, destination_path: String, bytes: PackedByteArray) -> Dictionary:
	var text_extensions := ["gd", "tscn", "tres", "gdshader", "cfg", "ini", "json", "md", "txt", "py", "sh", "cs", "xml", "csv"]
	if bytes.is_empty():
		return {"route":"/v1/write", "payload":{"path":destination_path,"content":""}}
	if file_name.get_extension().to_lower() in text_extensions and bytes.size() <= REMOTE_TEXT_FILE_LIMIT:
		var text_content := bytes.get_string_from_utf8()
		if text_content.to_utf8_buffer() == bytes:
			return {"route":"/v1/write", "payload":{"path":destination_path,"content":text_content}}
	return {"route":"/v1/upload", "payload":{"path":destination_path,"data":Marshalls.raw_to_base64(bytes)}}


func _on_local_files_selected(paths: PackedStringArray) -> void:
	if _selected_project.is_empty(): return
	var local_root := _local_project_absolute_path()
	var remote := str(_selected_project.get("studio_remote_path", ""))
	if remote == "" and local_root == "":
		toast.emit("This project has no local workspace folder to receive source files.")
		return
	for source_path in paths:
		var file_name := source_path.get_file().validate_filename()
		if file_name == "": continue
		if remote != "":
			var file := FileAccess.open(source_path, FileAccess.READ)
			if file == null:
				toast.emit("Couldn't read source file: " + file_name)
				continue
			var source_size := file.get_length()
			if source_size > 2 * 1024 * 1024:
				file.close()
				toast.emit("Skipped %s: source files are limited to 2 MB per file." % file_name)
				continue
			var bytes := file.get_buffer(source_size)
			file.close()
			if bytes.size() != source_size:
				toast.emit("Couldn't read the complete source file: " + file_name)
				continue
			var dest_path := remote.path_join("sources").path_join(file_name)
			var upload := _source_upload_request(file_name, dest_path, bytes)
			_pc_request("POST", str(upload.get("route", "")), upload.get("payload", {}), func(ok: bool, data: Dictionary):
				if not ok: toast.emit("Source upload failed: " + str(data.get("error", "unknown error")))
				else: toast.emit("Added source: " + file_name); _refresh_sources())
		else:
			var dest := local_root.path_join("sources").path_join(file_name)
			if FileAccess.file_exists(dest):
				toast.emit("Skipped %s: a source file with that name already exists." % file_name)
				continue
			var source := FileAccess.open(source_path, FileAccess.READ)
			if source == null:
				toast.emit("Couldn't read source file: " + file_name)
				continue
			var source_size := source.get_length()
			if source_size > 64 * 1024 * 1024:
				source.close()
				toast.emit("Skipped %s: local source files are limited to 64 MB per file." % file_name)
				continue
			var bytes := source.get_buffer(source_size)
			source.close()
			if bytes.size() != source_size:
				toast.emit("Couldn't read the complete source file: " + file_name)
				continue
			if not Store.write_bytes_atomic(dest, bytes):
				toast.emit("Couldn't safely save source file: " + file_name)
	_refresh_sources()


func _open_new_script() -> void:
	var win := Window.new()
	win.title = "Create a script"
	win.size = Vector2i(620, 720)
	win.transient = true
	var body := VBoxContainer.new()
	for side in ["left", "right"]: body.add_theme_constant_override("margin_" + side, 18)
	body.add_theme_constant_override("margin_top", 18)
	body.add_theme_constant_override("margin_bottom", 18)
	body.add_theme_constant_override("separation", 10)
	win.add_child(body)
	var path := Ui.line("scripts/player.gd")
	path.text = "scripts/player.gd"
	body.add_child(path)
	var code := TextEdit.new()
	code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code.placeholder_text = "extends CharacterBody2D\n\nfunc _physics_process(delta: float) -> void:\n\tpass"
	code.text = code.placeholder_text
	code.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	code.add_theme_font_size_override("font_size", 17)
	code.add_theme_color_override("font_color", Ui.TEXT)
	code.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Color("#f7f8fa"), 14, Ui.BORDER, 1), 14, 12))
	body.add_child(code)
	var save := Ui.btn("Save script", "primary", "check")
	save.pressed.connect(func():
		var relative := path.text.strip_edges().trim_prefix("/")
		if relative == "" or relative.contains("..") or relative.contains("\\") or not relative.ends_with(".gd"):
			toast.emit("Enter a safe .gd path inside the project."); return
		var validation := GodotSandbox.validate_gdscript(code.text)
		if not bool(validation.get("ok", false)):
			toast.emit("Godot compiler rejected this script. Fix the syntax before saving.")
			return
		_write_project_file(relative, code.text, func(ok: bool, error_text: String):
			if ok: win.queue_free(); toast.emit("Script compiled and saved: " + relative); _refresh_sources()
			else: toast.emit("Couldn't create script: " + error_text)))
	body.add_child(save)
	add_child(win)
	win.popup_centered()


func _write_project_file(relative: String, content: String, callback: Callable) -> void:
	var remote := str(_selected_project.get("studio_remote_path", ""))
	if remote != "":
		_pc_request("POST", "/v1/write", {"path":remote.path_join(relative),"content":content}, func(ok: bool, data: Dictionary): callback.call(ok, str(data.get("error", ""))))
		return
	var root := _local_project_absolute_path()
	if root == "": callback.call(false, "No local project folder."); return
	var file_path := root.path_join(relative)
	DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	var ok := _write_local_text(file_path, content)
	callback.call(ok, "FileAccess could not write the file." if not ok else "")


func _on_studio_tool_completed(result: Dictionary) -> void:
	if _selected_project.is_empty() or not bool(result.get("ok", false)):
		return
	var tool_name := str(result.get("tool", ""))
	if tool_name == "Project task" or tool_name == "Resume project task":
		_view_mode = "runs"
		_render_workspace()
		return
	if str(_selected_project.get("studio_remote_path", "")) == "":
		return
	if tool_name in ["linux.write_file", "linux.exec", "github.write_file"]:
		_refresh_sources()
	elif tool_name == "Godot run":
		_run_state = "running"
		_run_fab.visible = true
		_run_poll_timer.start()
	elif tool_name == "Godot stop":
		_run_state = "stopped"
		_run_fab.visible = false
		_run_poll_timer.stop()
	elif tool_name == "Godot test":
		_last_logs = str(result.get("output", ""))
		var test_cfg := Store.get_integration("studio")
		test_cfg["last_logs"] = _last_logs
		Store.set_integration("studio", test_cfg)
		_refresh_sources()
	elif tool_name == "Godot logs":
		_last_logs = str(result.get("output", ""))
		var log_cfg := Store.get_integration("studio")
		log_cfg["last_logs"] = _last_logs
		Store.set_integration("studio", log_cfg)


func _refresh_sources() -> void:
	if _selected_project.is_empty(): return
	var remote := str(_selected_project.get("studio_remote_path", ""))
	if remote == "":
		_render_workspace()
		return
	_pc_request("POST", "/v1/godot/scan", {"path":remote}, func(ok: bool, data: Dictionary):
			if not ok:
				toast.emit("Could not refresh project files: " + str(data.get("error", "unknown error")))
				return
			_selected_project["studio_remote_files"] = data.get("items", [])
			Store.save_project(_selected_project)
			_render_workspace())


func _open_source_preview(item: Dictionary) -> void:
	if str(item.get("type", "file")) in ["directory", "dir"]:
		toast.emit("Folder: " + str(item.get("path", "")))
		return
	var relative := str(item.get("path", ""))
	var remote := str(_selected_project.get("studio_remote_path", ""))
	if remote != "":
		_pc_request("POST", "/v1/read", {"path":remote.path_join(relative)}, func(ok: bool, data: Dictionary):
			if ok: _show_source_text(relative, str(data.get("content", "")))
			else: toast.emit("Couldn't read source: " + str(data.get("error", ""))))
		return
	var local := _local_project_absolute_path().path_join(relative)
	if not FileAccess.file_exists(local): toast.emit("This file is not stored in the local workspace."); return
	if FileAccess.get_file_as_bytes(local).size() > 120000: toast.emit("File is too large to preview here."); return
	_show_source_text(relative, FileAccess.get_file_as_string(local))


func _show_source_text(title: String, content: String) -> void:
	if _source_preview != null and is_instance_valid(_source_preview): _source_preview.queue_free()
	_source_preview = Window.new()
	_source_preview.title = title
	_source_preview.size = Vector2i(680, 900)
	_source_preview.transient = true
	var body := VBoxContainer.new()
	for side in ["left", "right"]: body.add_theme_constant_override("margin_" + side, 18)
	body.add_theme_constant_override("margin_top", 18)
	body.add_theme_constant_override("margin_bottom", 18)
	body.add_theme_constant_override("separation", 10)
	_source_preview.add_child(body)
	var label := Ui.lbl(title, Ui.FS_SMALL, Ui.MUTED, true)
	body.add_child(label)
	var code := TextEdit.new()
	code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code.editable = false
	code.text = content
	code.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	code.add_theme_font_size_override("font_size", 16)
	code.add_theme_color_override("font_color", Ui.TEXT)
	code.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Color("#f7f8fa"), 14, Ui.BORDER, 1), 14, 12))
	body.add_child(code)
	var close := Ui.btn("Close", "quiet")
	close.pressed.connect(_source_preview.queue_free)
	body.add_child(close)
	add_child(_source_preview)
	_source_preview.popup_centered()


func _pc_configured() -> bool:
	return ToolRunner.is_linux_connected()


func _refresh_connection_label() -> void:
	if _pc_configured():
		_header_status.text = "Cloud workspace · checking…"
		_check_pc_health()
	else:
		_header_status.text = "Cloud workspace not connected"


func _check_pc_health() -> void:
	_pc_request("GET", "/health", {}, func(ok: bool, data: Dictionary):
		if ok: _header_status.text = "Cloud connected · %s" % str(data.get("bridge", "Aoi runtime"))
		else: _header_status.text = "Cloud workspace unavailable · open Connections to reconnect")


func _pc_request(method: String, route: String, payload: Dictionary, callback: Callable) -> void:
	var cfg := Store.get_integration("linux_bridge")
	var base := str(cfg.get("url", "")).strip_edges().trim_suffix("/")
	var token := Store.get_secret("linux_bridge")
	if not ToolRunner.is_linux_connected():
		callback.call(false, {"error":"Test and connect a cloud Linux workspace in Connections first."})
		return
	var request := HTTPRequest.new()
	request.timeout = 185.0
	request.body_size_limit = 4 * 1024 * 1024
	add_child(request)
	_request_nodes.append(request)
	var headers := PackedStringArray(["Accept: application/json", "Content-Type: application/json", "X-Aoi-Token: " + token])
	request.request_completed.connect(func(result: int, code: int, _head: PackedStringArray, body: PackedByteArray):
		var current_cfg := Store.get_integration("linux_bridge")
		if str(current_cfg.get("url", "")).strip_edges().trim_suffix("/") != base or Store.get_secret("linux_bridge") != token:
			callback.call(false, {"error":"The cloud connection changed while this request was running. Test the new workspace and retry."})
			_request_nodes.erase(request)
			request.queue_free()
			return
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		var data: Dictionary = parsed if parsed is Dictionary else {}
		var success := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300 and bool(data.get("ok", true))
		if not success and (result != HTTPRequest.RESULT_SUCCESS or code in [401, 404, 502, 503, 504]):
			var failure := str(data.get("error", "Cloud workspace request failed (HTTP %d)." % code))
			ToolRunner._mark_linux_disconnected(base, token, failure)
		callback.call(success, data if not data.is_empty() else {"error":"HTTP %d" % code})
		_request_nodes.erase(request)
		request.queue_free())
	var url := base + route
	var error := request.request(url, headers, HTTPClient.METHOD_GET if method == "GET" else HTTPClient.METHOD_POST, "" if method == "GET" else JSON.stringify(payload))
	if error != OK:
		_request_nodes.erase(request)
		request.queue_free()
		callback.call(false, {"error":"Could not start Cloud workspace request (error %d)." % error})


func _pc_project_action(action: String) -> void:
	var path := str(_selected_project.get("studio_remote_path", ""))
	if path == "":
		toast.emit("This project is stored on this device. Create or import it in the cloud workspace to run it there.")
		return
	var endpoint := "/v1/godot/" + action
	if action == "run":
		_run_state = "starting"
	_pc_request("POST", endpoint, {"path":path}, func(ok: bool, data: Dictionary):
		if not ok:
			_run_state = "stopped"
			_run_fab.visible = false
			toast.emit(str(data.get("error", "Godot action failed.")))
			return
		match action:
			"run":
				_run_state = "running"
				_run_fab.visible = true
				_run_poll_timer.start()
				toast.emit("Godot project launched in the cloud workspace.")
			"stop":
				_run_state = "stopped"
				_run_fab.visible = false
				_run_poll_timer.stop()
				toast.emit("Godot project stopped.")
			"test":
				var output := str(data.get("output", ""))
				_last_logs = output
				var cfg := Store.get_integration("studio")
				cfg["last_logs"] = _last_logs
				Store.set_integration("studio", cfg)
				var kind := str(data.get("test_kind", "Godot verification"))
				toast.emit("%s %s · exit %s" % [kind, "passed" if bool(data.get("ok", false)) else "failed", str(data.get("exit_code", "?"))])
				_show_source_text(kind, output)
			"capture":
				toast.emit("Screenshot saved in cloud workspace: " + str(data.get("path", "")))
				var encoded := str(data.get("image_base64", ""))
				if encoded != "":
					_show_capture_preview(Marshalls.base64_to_raw(encoded))
			"logs":
				_last_logs = str(data.get("logs", ""))
				var cfg := Store.get_integration("studio")
				cfg["last_logs"] = _last_logs
				Store.set_integration("studio", cfg)
				_show_source_text("Godot logs", _last_logs)
	)


func _on_tool_menu(id: int) -> void:
	match id:
		0: _pc_project_action("run")
		1: _pc_project_action("stop")
		2: _pc_project_action("test")
		3: _pc_project_action("capture")
		4: _pc_project_action("logs")
		5: _show_running_panel()
		6: _show_api_explorer()
		7: _create_starter_2d_scene()
		8: _validate_selected_script()
		9: _preview_local_scene()
		10: _set_view_mode("runs")
		11: _show_task_manifest_guide()


func _show_task_manifest_guide() -> void:
	var win := Window.new()
	win.title = "Project task contract"
	win.size = Vector2i(680, 860)
	win.transient = true
	var shell := VBoxContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: shell.add_theme_constant_override("margin_" + side, 18)
	shell.add_theme_constant_override("margin_top", 18)
	shell.add_theme_constant_override("margin_bottom", 18)
	shell.add_theme_constant_override("separation", 10)
	win.add_child(shell)
	shell.add_child(Ui.lbl("Generic headless task manifest", Ui.FS_TITLE, Ui.TEXT, true))
	var text := TextEdit.new()
	text.editable = false
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.text = """Every project may declare its own headless tasks in .aoi/tasks.json. Aoi does not hardcode project-specific logic.

Schema version 1:
{
  \"schema_version\": 1,
  \"project_name\": \"My project\",
  \"tasks\": [
    {
      \"id\": \"train\",
      \"name\": \"Run training\",
      \"description\": \"Project-owned training loop\",
      \"runtime\": \"gdscript_steps\",
      \"script\": \"aoi_tasks/train.gd\",
      \"parameters\": [{\"name\": \"steps\", \"type\": \"int\", \"default\": 1000, \"min\": 1, \"max\": 100000}],
      \"limits\": {\"max_runtime_seconds\": 600}
    }
  ]
}

The task script extends RefCounted and implements:
- start(context, parameters, checkpoint) -> Dictionary
- step(context, state, budget_units) -> Dictionary

Each step must be bounded and return: ok, state, progress, detail and done. On completion it may return result, metrics, summary and artifacts. Use context.log(), context.progress(), context.read_file(), context.write_artifact(), context.is_cancelled() and context.list_files().

Task scripts execute inside Aoi's process with the app's permissions. This is trusted project code, not an OS-isolated security sandbox. Starting and resuming always require approval. Arbitrary Python/Node/native tasks need a matching companion runtime; they are never reported as having run when that runtime is unavailable."""
	text.add_theme_color_override("font_color", Ui.TEXT)
	text.add_theme_stylebox_override("normal", Ui.box(Color("#f7f8fa"), 12, Ui.BORDER, 1))
	shell.add_child(text)
	var close := Ui.btn("Close", "quiet")
	close.pressed.connect(win.queue_free)
	shell.add_child(close)
	add_child(win)
	win.popup_centered()


func _show_api_explorer(initial_class: String = "Node") -> void:
	var summary := GodotSandbox.ensure_index()
	var viewport_size := get_viewport_rect().size
	var target_size := Vector2i(maxi(320, mini(680, int(viewport_size.x * 0.95))), maxi(480, mini(1120, int(viewport_size.y * 0.91))))
	var win := Window.new()
	win.title = "Godot API Explorer"
	win.size = target_size
	win.min_size = Vector2i(mini(320, target_size.x), mini(480, target_size.y))
	win.transient = true
	win.borderless = true
	win.theme = Ui.make_theme()
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", Ui.box(Ui.BG, 18, Ui.BORDER, 1))
	win.add_child(panel)
	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: outer.add_theme_constant_override("margin_" + side, 14)
	outer.add_theme_constant_override("margin_top", 12)
	outer.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(outer)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 8)
	outer.add_child(shell)

	# Compact product header: engine version and source provenance remain visible.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var heading := Ui.lbl("Godot reference", 23, Ui.TEXT, true)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	header.add_child(Ui.chip("Godot " + str(summary.get("engine", "4.x")), Ui.ACCENT))
	var close_top := Ui.icon_btn("close", "quiet", 42)
	close_top.tooltip_text = "Close reference"
	close_top.pressed.connect(win.queue_free)
	header.add_child(close_top)
	shell.add_child(header)
	var provenance := "Bundled engine export data" if str(summary.get("source", "")) == "bundled_snapshot" else "Live ClassDB · %d classes" % int(summary.get("count", 0))
	shell.add_child(Ui.lbl(provenance, 14, Ui.MUTED, false, true))

	# Class selection collapses after selection so API members receive the screen space.
	var class_row := HBoxContainer.new()
	class_row.add_theme_constant_override("separation", 8)
	var class_heading := Ui.lbl("CLASS", 13, Ui.MUTED, true)
	class_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	class_row.add_child(class_heading)
	var change_class := Ui.btn("Change class", "quiet", "chevron_down")
	change_class.name = "APIChangeClass"
	change_class.custom_minimum_size = Vector2(150, 46)
	class_row.add_child(change_class)
	shell.add_child(class_row)
	var class_summary := PanelContainer.new()
	class_summary.add_theme_stylebox_override("panel", Ui.pad(Ui.box(Ui.SURFACE, 13, Ui.BORDER, 1), 14, 9))
	var class_summary_label := Ui.lbl("Choose a class to inspect its engine API.", 17, Ui.TEXT, true, true)
	class_summary_label.name = "APIClassSummary"
	class_summary.add_child(class_summary_label)
	shell.add_child(class_summary)
	var class_search := Ui.line("Search classes, e.g. CharacterBody2D")
	class_search.name = "APIClassSearch"
	class_search.visible = false
	shell.add_child(class_search)
	var class_tree := Tree.new()
	class_tree.name = "APIClassTree"
	class_tree.hide_root = true
	class_tree.custom_minimum_size = Vector2(0, 150)
	class_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	class_tree.visible = false
	class_tree.add_theme_stylebox_override("panel", Ui.box(Ui.SURFACE, 12, Ui.BORDER, 1))
	class_tree.add_theme_color_override("font_color", Ui.TEXT)
	shell.add_child(class_tree)

	# Five explicit member categories replace the old unbounded mixed text dump.
	var category_grid := GridContainer.new()
	category_grid.columns = 3
	category_grid.add_theme_constant_override("h_separation", 6)
	category_grid.add_theme_constant_override("v_separation", 6)
	shell.add_child(category_grid)
	var categories := ["Methods", "Properties", "Signals", "Enums", "Constants"]
	var category_buttons: Dictionary = {}
	var active_category := {"value": "Methods"}
	var selected_state := {"class_info": {}, "member": {}, "kind": ""}
	var member_toolbar := HBoxContainer.new()
	member_toolbar.add_theme_constant_override("separation", 8)
	var result_count := Ui.lbl("Select a class to browse its members", 14, Ui.MUTED)
	result_count.name = "APIResults"
	result_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	member_toolbar.add_child(result_count)
	var inherited_toggle := CheckButton.new()
	inherited_toggle.name = "APIIncludeInherited"
	inherited_toggle.text = "Inherited"
	inherited_toggle.button_pressed = false
	inherited_toggle.focus_mode = Control.FOCUS_ALL
	inherited_toggle.add_theme_font_size_override("font_size", 14)
	inherited_toggle.tooltip_text = "Include members declared by parent classes"
	member_toolbar.add_child(inherited_toggle)
	shell.add_child(member_toolbar)
	var include_inherited := {"value": false}
	var member_search := Ui.line("Filter this class's members…")
	member_search.name = "APIMemberSearch"
	member_search.custom_minimum_size.y = 52
	shell.add_child(member_search)
	var member_scroll := ScrollContainer.new()
	member_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	member_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	member_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	member_scroll.custom_minimum_size.y = 210
	shell.add_child(member_scroll)
	var member_list := VBoxContainer.new()
	member_list.name = "APIMemberList"
	member_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	member_list.add_theme_constant_override("separation", 5)
	member_scroll.add_child(member_list)
	var detail_card := PanelContainer.new()
	detail_card.add_theme_stylebox_override("panel", Ui.pad(Ui.box(Ui.SURFACE, 13, Ui.BORDER, 1), 14, 10))
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 5)
	detail_card.add_child(detail_box)
	var detail_title := Ui.lbl("Member details", 17, Ui.TEXT, true)
	detail_title.name = "APISelectedMemberTitle"
	var detail_body := Ui.lbl("Choose a method, property, signal, enum or constant to inspect its exact engine signature.", 14, Ui.MUTED, false, true)
	detail_body.name = "APISelectedMemberDetail"
	detail_box.add_child(detail_title)
	detail_box.add_child(detail_body)
	shell.add_child(detail_card)

	var docs := Ui.btn("Open official class documentation", "ghost", "forward")
	docs.custom_minimum_size.y = 48
	docs.disabled = true
	docs.pressed.connect(func():
		var class_id := str(selected_state.get("class_info", {}).get("name", ""))
		if class_id != "": OS.shell_open("https://docs.godotengine.org/en/4.8/classes/class_%s.html" % class_id.to_lower()))
	shell.add_child(docs)

	var format_type := func(value: Variant) -> String:
		if value is Dictionary:
			var api_class_type := str(value.get("class_name", ""))
			if api_class_type != "": return api_class_type
			return str(value.get("type_name", type_string(int(value.get("type", TYPE_NIL)))))
		return str(value) if str(value) != "" else "Variant"
	var method_signature := func(item: Dictionary) -> String:
		var args: Array[String] = []
		var raw_args: Array = item.get("args", [])
		var defaults: Array = item.get("default_args", [])
		var default_start := raw_args.size() - defaults.size()
		for index in range(raw_args.size()):
			var argument: Variant = raw_args[index]
			var arg_name := str(argument.get("name", "arg")) if argument is Dictionary else str(argument)
			var arg_type: String = str(format_type.call(argument)) if argument is Dictionary else "Variant"
			var value: String = arg_name + ": " + arg_type
			if index >= default_start and not defaults.is_empty(): value += " = " + str(defaults[index - default_start])
			args.append(value)
		var return_type := str(format_type.call(item.get("return", {})))
		if return_type.to_lower() == "nil": return_type = "void"
		return "%s(%s) -> %s" % [str(item.get("name", "method")), ", ".join(args), return_type]
	var select_member := func(kind: String, item: Dictionary) -> void:
		selected_state["member"] = item.duplicate(true)
		selected_state["kind"] = kind
		var name := str(item.get("name", "Member"))
		detail_title.text = name
		var lines: Array[String] = []
		match kind:
			"Methods":
				lines.append(method_signature.call(item))
			"Properties":
				lines.append("Type: " + format_type.call(item))
				if bool(item.get("read_only", false)): lines.append("Read-only property")
				if str(item.get("hint_string", "")) != "": lines.append("Hint: " + str(item.get("hint_string", "")))
			"Signals":
				var args: Array[String] = []
				for argument in item.get("args", []):
					args.append(str(argument.get("name", "arg")) + ": " + format_type.call(argument))
				lines.append("%s(%s)" % [name, ", ".join(args)])
			"Enums":
				for enum_value in item.get("values", []): lines.append("%s = %s" % [str(enum_value.get("name", "")), str(enum_value.get("value", ""))])
				if bool(item.get("bitfield", false)): lines.append("Bitfield enum")
			"Constants": lines.append("Value: " + str(item.get("value", "")))
		var owner := str(item.get("declared_in", ""))
		if owner != "": lines.append("Declared in: " + owner)
		detail_body.text = "\n".join(lines)
	var render_members := func() -> void:
		for child in member_list.get_children(): child.queue_free()
		var info: Dictionary = selected_state.get("class_info", {})
		if info.is_empty(): return
		var key := str(active_category.get("value", "Methods")).to_lower()
		var records: Array = info.get(key, [])
		var query := member_search.text.strip_edges().to_lower()
		var shown := 0
		var first_match: Dictionary = {}
		for record in records:
			var item: Dictionary = record if record is Dictionary else {"name":str(record)}
			var origin_class := str(item.get("declared_in", ""))
			if not bool(include_inherited.get("value", false)) and origin_class != "" and origin_class != str(info.get("name", "")): continue
			var member_name := str(item.get("name", ""))
			if query != "" and not member_name.to_lower().contains(query): continue
			shown += 1
			if shown == 1: first_match = item
			var button := Button.new()
			button.flat = true
			button.focus_mode = Control.FOCUS_ALL
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.custom_minimum_size.y = 58
			button.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Ui.SURFACE, 10, Ui.BORDER, 1), 12, 6))
			button.add_theme_stylebox_override("hover", Ui.pad(Ui.box(Color("#f1f1f1"), 10, Ui.ACCENT_SOFT, 1), 12, 6))
			button.add_theme_stylebox_override("focus", Ui.pad(Ui.box(Color("#f1f1f1"), 10, Ui.ACCENT, 1), 12, 6))
			var row := HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_theme_constant_override("separation", 8)
			var copy := VBoxContainer.new()
			copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var primary := Ui.lbl(member_name, 15, Ui.TEXT, true)
			primary.mouse_filter = Control.MOUSE_FILTER_IGNORE
			copy.add_child(primary)
			var secondary := ""
			var category_name := str(active_category.get("value", ""))
			if category_name == "Methods":
				secondary = method_signature.call(item)
			elif category_name == "Properties":
				secondary = format_type.call(item) + (" · read-only" if bool(item.get("read_only", false)) else "")
			elif category_name == "Signals":
				secondary = "Signal · %d arguments" % (item.get("args", []) as Array).size()
			elif category_name == "Enums":
				secondary = "%d values" % (item.get("values", []) as Array).size()
			elif category_name == "Constants":
				secondary = "Value: " + str(item.get("value", ""))
			var sub := Ui.lbl(secondary, 12, Ui.MUTED)
			sub.clip_text = true
			sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
			copy.add_child(sub)
			row.add_child(copy)
			var origin := str(item.get("declared_in", ""))
			if origin != "" and origin != str(info.get("name", "")): row.add_child(Ui.chip("Inherited", Ui.MUTED))
			button.add_child(row)
			button.pressed.connect(func(): select_member.call(str(active_category.get("value", "")), item))
			member_list.add_child(button)
		result_count.text = "%d shown · %d total %s" % [shown, records.size(), key]
		if shown > 0:
			select_member.call(str(active_category.get("value", "")), first_match)
		if shown == 0:
			member_list.add_child(Ui.lbl("No matching %s. Try a shorter search." % key, 14, Ui.MUTED, false, true))
	var select_category := func(category_name: String) -> void:
		active_category["value"] = category_name
		for name in category_buttons:
			var button: Button = category_buttons[name]
			button.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Ui.ACCENT if name == category_name else Ui.SURFACE, 10, Ui.ACCENT if name == category_name else Ui.BORDER, 1), 8, 6))
			button.add_theme_color_override("font_color", Color.WHITE if name == category_name else Ui.TEXT)
		member_search.text = ""
		render_members.call()
	for category_name in categories:
		var category_button := Ui.btn(category_name, "ghost")
		category_button.name = "APICategory_" + category_name
		category_button.custom_minimum_size.y = 46
		category_button.add_theme_font_size_override("font_size", 14)
		category_button.pressed.connect(func(): select_category.call(category_name))
		category_grid.add_child(category_button)
		category_buttons[category_name] = category_button

	var show_class := func(class_id: String) -> void:
		var info := GodotSandbox.inspect_class(class_id)
		if not bool(info.get("ok", false)):
			class_summary_label.text = str(info.get("error", "Class metadata unavailable."))
			return
		selected_state["class_info"] = info
		class_summary_label.text = "%s  ·  inherits %s  ·  %s" % [class_id, str(info.get("parent", "Object")), "Instantiable" if bool(info.get("instantiable", false)) else "Abstract / static"]
		class_search.visible = false
		class_tree.visible = false
		change_class.visible = true
		docs.disabled = false
		select_category.call("Methods")
	change_class.pressed.connect(func():
		class_search.visible = true
		class_tree.visible = true
		change_class.visible = false
		class_search.grab_focus())
	var populate_classes := func(query: String) -> void:
		class_tree.clear()
		var root := class_tree.create_item()
		for row in GodotSandbox.search_classes(query, 50):
			var item := class_tree.create_item(root)
			item.set_text(0, str(row.get("name", "")) + ("  ·  abstract" if not bool(row.get("instantiable", false)) else ""))
			item.set_metadata(0, str(row.get("name", "")))
	class_search.text_changed.connect(func(value: String): populate_classes.call(value))
	class_tree.item_selected.connect(func():
		var item := class_tree.get_selected()
		if item != null: show_class.call(str(item.get_metadata(0))))
	member_search.text_changed.connect(func(_value: String): render_members.call())
	inherited_toggle.toggled.connect(func(value: bool): include_inherited["value"] = value; render_members.call())
	inherited_toggle.toggled.connect(func(value: bool): include_inherited["value"] = value; render_members.call())
	populate_classes.call("")
	show_class.call(initial_class if initial_class != "" else "Node")
	var footer := HBoxContainer.new()
	var footer_note := Ui.lbl("Read-only engine metadata · data exported with this Godot runtime", 12, Ui.MUTED, false, true)
	footer_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_note)
	var done := Ui.btn("Done", "quiet")
	done.custom_minimum_size = Vector2(86, 44)
	done.pressed.connect(win.queue_free)
	footer.add_child(done)
	shell.add_child(footer)
	add_child(win)
	win.popup_centered()

func _create_starter_2d_scene() -> void:
	if _selected_project.is_empty():
		toast.emit("Create or import a project first.")
		return
	var root := _local_project_absolute_path()
	if root == "":
		toast.emit("The embedded scene builder currently writes to phone-local projects. Cloud projects need the remote scene endpoint.")
		return
	var blueprint := {
		"root_type": "Node2D", "root_name": "PlatformerPrototype",
		"nodes": [
			{"name":"Backdrop", "type":"ColorRect", "parent":"root", "properties":{"position":[0,0],"size":[720,480],"color":[0.12,0.16,0.22,1.0]}},
			{"name":"Ground", "type":"StaticBody2D", "parent":"root", "properties":{"position":[360,430]}},
			{"name":"GroundCollision", "type":"CollisionShape2D", "parent":"Ground", "shape_kind":"rectangle", "shape_size":[720,48]},
			{"name":"GroundVisual", "type":"ColorRect", "parent":"Ground", "properties":{"position":[-360,-24],"size":[720,48],"color":[0.20,0.35,0.31,1.0]}},
			{"name":"Player", "type":"CharacterBody2D", "parent":"root", "properties":{"position":[180,350]}},
			{"name":"PlayerCollision", "type":"CollisionShape2D", "parent":"Player", "shape_kind":"capsule", "shape_radius":12.0, "shape_height":40.0},
			{"name":"PlayerVisual", "type":"ColorRect", "parent":"Player", "properties":{"position":[-12,-20],"size":[24,40],"color":[0.88,0.30,0.27,1.0]}},
			{"name":"Camera", "type":"Camera2D", "parent":"Player", "properties":{"position":[0,-40],"enabled":true}}
		]
	}
	var result := GodotSandbox.create_scene(root, "scenes/platformer_prototype.tscn", blueprint)
	if not bool(result.get("ok", false)):
		toast.emit("Scene creation failed: " + str(result.get("error", "unknown error")))
		return
	_refresh_sources()
	toast.emit("Created a native Godot scene with %d nodes. It is a visual/physics scaffold; movement logic is not attached yet." % int(result.get("nodes", 0)))


func _preview_local_scene() -> void:
	if _selected_project.is_empty(): return
	var root := _local_project_absolute_path()
	if root == "":
		toast.emit("Local preview is available for phone-local projects. Cloud preview requires a connected workspace.")
		return
	var scene_path := root.path_join("scenes/platformer_prototype.tscn")
	if not FileAccess.file_exists(scene_path):
		toast.emit("Create the starter 2D scene first.")
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		toast.emit("Godot could not load this scene.")
		return
	var win := Window.new()
	win.title = "Aoi local scene preview"
	win.size = Vector2i(760, 620)
	win.min_size = Vector2i(480, 420)
	win.transient = true
	var body := VBoxContainer.new()
	for side in ["left", "right"]: body.add_theme_constant_override("margin_" + side, 14)
	body.add_theme_constant_override("margin_top", 14)
	body.add_theme_constant_override("margin_bottom", 14)
	body.add_theme_constant_override("separation", 10)
	win.add_child(body)
	body.add_child(Ui.lbl("Godot scene preview", Ui.FS, Ui.TEXT, true))
	body.add_child(Ui.lbl("This preview instantiates the saved native scene. GDScript attached to imported scenes is not executed by this restricted preview.", 13, Ui.MUTED, false, true))
	var preview := SubViewportContainer.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.stretch = true
	preview.custom_minimum_size = Vector2(320, 300)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 480)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview.add_child(viewport)
	var instance := packed.instantiate()
	viewport.add_child(instance)
	body.add_child(preview)
	var close := Ui.btn("Close preview", "quiet")
	close.pressed.connect(win.queue_free)
	body.add_child(close)
	add_child(win)
	win.popup_centered()


func _validate_selected_script() -> void:
	if _selected_project.is_empty(): return
	var root := _local_project_absolute_path()
	if root == "":
		toast.emit("GDScript validation is currently available for phone-local projects.")
		return
	var scripts: Array = []
	for item in _get_visible_files():
		if str(item.get("type", "")) == "file" and str(item.get("path", "")).ends_with(".gd"):
			scripts.append(item)
	if scripts.is_empty():
		toast.emit("No .gd scripts found in this project.")
		return
	var script_path := root.path_join(str(scripts[0].path))
	var result := GodotSandbox.validate_gdscript(FileAccess.get_file_as_string(script_path))
	toast.emit("Godot compiler: " + str(result.get("message", result.get("error", "Unknown result"))))


func _create_pc_workspace(title: String, goal: String) -> void:
	var project := Store.new_project(title, goal)
	var project_id := str(project.get("id", ""))
	if project_id == "":
		toast.emit("Aoi could not create this project. Try again.")
		return
	_pc_request("POST", "/v1/godot/create", {"name":title,"path":"aoi_projects".path_join(project_id),"goal":goal}, func(ok: bool, data: Dictionary):
		if not ok:
			Store.delete_project(project_id)
			toast.emit("Cloud project creation failed: " + str(data.get("error", "unknown error")))
			return
		project["studio_remote_path"] = str(data.get("path", ""))
		project["studio_origin"] = "cloud"
		project["studio_runtime"] = "godot"
		project["runtime_device"] = "cloud_linux"
		project["project_kind"] = "game"
		if not Store.save_project(project):
			toast.emit("The cloud project was created, but Aoi couldn't save its connection on this device.")
			return
		select_project(project)
		_refresh_sources()
		toast.emit("Godot project created in the cloud workspace."))


func _poll_run_status() -> void:
	if _selected_project.is_empty(): _run_poll_timer.stop(); return
	var remote := str(_selected_project.get("studio_remote_path", ""))
	if remote == "": _run_poll_timer.stop(); return
	_pc_request("POST", "/v1/godot/status", {"path":remote}, func(ok: bool, data: Dictionary):
		if not ok: return
		_run_state = "running" if bool(data.get("running", false)) else "stopped"
		_run_fab.visible = _run_state == "running"
		if _run_state != "running": _run_poll_timer.stop())


func _on_running_fab_pressed() -> void:
	if _run_state == "running":
		_pc_project_action("capture")
	else:
		_show_running_panel()


func _show_running_panel() -> void:
	var win := Window.new()
	win.title = "Godot run monitor"
	win.size = Vector2i(560, 540)
	win.transient = true
	var body := VBoxContainer.new()
	for side in ["left", "right"]: body.add_theme_constant_override("margin_" + side, 20)
	body.add_theme_constant_override("margin_top", 20)
	body.add_theme_constant_override("margin_bottom", 20)
	body.add_theme_constant_override("separation", 12)
	win.add_child(body)
	body.add_child(Ui.lbl("Project runtime", Ui.FS_TITLE, Ui.TEXT, true))
	body.add_child(Ui.lbl("The game runs on the cloud workspace. Aoi Mobile is monitoring its process; this is not a live video stream.", Ui.FS_SMALL, Ui.MUTED, false, true))
	body.add_child(Ui.chip("RUNNING IN CLOUD" if _run_state == "running" else "NOT RUNNING", Ui.GREEN if _run_state == "running" else Ui.MUTED))
	var run := Ui.btn("Run project", "primary", "play"); run.pressed.connect(func(): _pc_project_action("run"))
	body.add_child(run)
	var stop := Ui.btn("Stop project", "danger", "stop"); stop.pressed.connect(func(): _pc_project_action("stop"))
	body.add_child(stop)
	var preview := Ui.btn("Open full-screen preview", "primary", "image"); preview.pressed.connect(func(): win.queue_free(); _pc_project_action("capture"))
	body.add_child(preview)
	var capture := Ui.btn("Capture screenshot", "ghost", "image"); capture.pressed.connect(func(): _pc_project_action("capture"))
	body.add_child(capture)
	var logs := Ui.btn("Inspect Godot logs", "ghost", "terminal"); logs.pressed.connect(func(): _pc_project_action("logs"))
	body.add_child(logs)
	var close := Ui.btn("Close", "quiet"); close.pressed.connect(win.queue_free)
	body.add_child(close)
	add_child(win); win.popup_centered()


func _show_capture_preview(bytes: PackedByteArray) -> void:
	var image := Image.new()
	var err := image.load_png_from_buffer(bytes)
	if err != OK:
		toast.emit("The cloud screenshot could not be decoded.")
		return
	if _fullscreen_preview != null and is_instance_valid(_fullscreen_preview):
		_fullscreen_preview.queue_free()
	_fullscreen_preview = Control.new()
	_fullscreen_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fullscreen_preview.z_index = 90
	_content.add_child(_fullscreen_preview)
	var backdrop := ColorRect.new()
	backdrop.color = Color("#101114")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fullscreen_preview.add_child(backdrop)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: layout.add_theme_constant_override("margin_" + side, 14)
	layout.add_theme_constant_override("margin_top", 14)
	layout.add_theme_constant_override("margin_bottom", 18)
	layout.add_theme_constant_override("separation", 10)
	_fullscreen_preview.add_child(layout)
	var header := HBoxContainer.new()
	var title := Ui.lbl("Cloud capture · %d × %d" % [image.get_width(), image.get_height()], Ui.FS_SMALL, Color.WHITE, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var stop := Ui.btn("Stop", "danger", "stop")
	stop.custom_minimum_size = Vector2(78, 46)
	stop.add_theme_color_override("font_color", Color("#ff969c"))
	stop.pressed.connect(func(): _close_fullscreen_preview(); _pc_project_action("stop"))
	header.add_child(stop)
	var close := Ui.icon_btn("close", "quiet", 46)
	close.add_theme_color_override("icon_normal_color", Color.WHITE)
	close.pressed.connect(_close_fullscreen_preview)
	header.add_child(close)
	layout.add_child(header)
	var preview := TextureRect.new()
	preview.texture = ImageTexture.create_from_image(image)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(preview)
	var footer := HBoxContainer.new()
	var note := Ui.lbl("Captured from the cloud workspace. This is a screenshot, not a live video stream.", 14, Color("#c1c5ce"), false, true)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(note)
	var again := Ui.btn("Capture again", "quiet")
	again.custom_minimum_size = Vector2(120, 48)
	again.pressed.connect(func(): _close_fullscreen_preview(); _pc_project_action("capture"))
	footer.add_child(again)
	var close_btn := Ui.btn("Done", "primary")
	close_btn.custom_minimum_size = Vector2(82, 48)
	close_btn.pressed.connect(_close_fullscreen_preview)
	footer.add_child(close_btn)
	layout.add_child(footer)


func _close_fullscreen_preview() -> void:
	if _fullscreen_preview != null and is_instance_valid(_fullscreen_preview):
		_fullscreen_preview.queue_free()
	_fullscreen_preview = null


func _open_local_import_filesystem() -> void:
	# Convenience for desktop builds; on Android use PC pairing to import a project folder.
	toast.emit("On Android, import an existing project from your cloud workspace.")


func _logs_context() -> String:
	return _last_logs
