extends VBoxContainer
## Projects: a goal, a checklist and notes per project. AI answers can be saved here; Aoi can plan from them.
const Ui = preload("res://scripts/ui/Ui.gd")
const Md = preload("res://scripts/core/Md.gd")
const Sheet = preload("res://scripts/ui/Sheet.gd")

signal plan_with_aoi(project_id: String)
signal chat_about(project_id: String)
signal request_delete(project_id: String)
signal request_open_flow(project_id: String)
signal toast_requested(message: String)

const STARTERS := [
	{"title": "Sell a digital product", "goal": "Create and sell a simple digital product (template, guide or pack) using only my phone."},
	{"title": "Freelance service", "goal": "Offer one small paid service online and land my first customer."},
	{"title": "Small mobile game", "goal": "Build and publish a tiny game made in Godot, working on my phone."},
]

var _scroll: ScrollContainer
var _body: VBoxContainer
var _current := {}            # project being viewed (empty = list)
var _editing_notes := false
var _editing_details := false
var _show_work_details := false
var _project_menu: PopupMenu
var _project_card_rows: Array[Dictionary] = []
var _project_search: LineEdit
var _search_status: Label
var _no_results: Label


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]: pad.add_theme_constant_override("margin_" + side, 24)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 40)
	_scroll.add_child(pad)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 20)
	pad.add_child(_body)
	_project_menu = PopupMenu.new()
	_project_menu.add_item("Edit project details", 3)
	_project_menu.add_item("Copy project summary", 0)
	_project_menu.add_item("Open workflow", 2)
	_project_menu.add_separator()
	_project_menu.add_item("Delete project", 1)
	Ui.style_popup_menu(_project_menu)
	_project_menu.id_pressed.connect(_on_project_menu_action)
	add_child(_project_menu)
	render()


func show_list() -> void:
	_current = {}
	_editing_notes = false
	_editing_details = false
	_show_work_details = false
	render()


func open_project(id: String) -> void:
	_current = Store.get_project(id)
	_editing_notes = false
	_editing_details = false
	_show_work_details = false
	render()


func render() -> void:
	for c in _body.get_children(): c.queue_free()
	_project_card_rows.clear()
	_project_search = null
	_search_status = null
	_no_results = null
	if _current.is_empty(): _render_list()
	elif _editing_details: _render_detail_editor()
	elif _show_work_details: _render_work_details()
	else: _render_detail()


# --------------------------------------------------------------------- list
func _render_list() -> void:
	var projects := Store.list_projects()
	var open_tasks := 0
	var completed_tasks := 0
	for project_data in projects:
		for task in project_data.get("tasks", []):
			if bool(task.get("done", false)): completed_tasks += 1
			else: open_tasks += 1
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_body.add_child(head)
	var title := Ui.lbl("All projects", 19, Ui.MUTED, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var create := Ui.btn("New project", "primary", "plus")
	create.custom_minimum_size = Vector2(164, 54)
	create.add_theme_font_size_override("font_size", 18)
	create.pressed.connect(func(): _new_project("", ""))
	head.add_child(create)
	var project_word := "project" if projects.size() == 1 else "projects"
	var overview := Ui.lbl("%d %s   ·   %d open tasks   ·   %d done" % [projects.size(), project_word, open_tasks, completed_tasks], 16, Ui.MUTED, false, true)
	_body.add_child(overview)
	var search := Ui.line("Search projects")
	search.name = "ProjectSearchField"
	_project_search = search
	search.custom_minimum_size.y = 54
	_body.add_child(search)
	if projects.is_empty():
		_body.add_child(Ui.lbl("Start a project", 24, Ui.TEXT, true))
		_body.add_child(Ui.lbl("Keep the goal, work and useful decisions together. You can start from a conversation at any time; a project is optional.", 18, Ui.MUTED, false, true))
		var start := Ui.btn("Create your first project", "primary", "plus")
		start.pressed.connect(func(): _new_project("", ""))
		_body.add_child(start)
		for starter in STARTERS:
			var starter_button := Ui.btn(str(starter["title"]), "quiet")
			starter_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			starter_button.pressed.connect(func(): _new_project(str(starter["title"]), str(starter["goal"])))
			_body.add_child(starter_button)
		search.visible = false
		return
	var status := Ui.lbl("Your projects", 20, Ui.TEXT, true)
	status.name = "ProjectSearchStatus"
	_search_status = status
	_body.add_child(status)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 0)
	_body.add_child(list)
	var no_results := Ui.lbl("No projects match that search. Try another name or goal.", 17, Ui.MUTED, false, true)
	no_results.name = "ProjectNoResults"
	no_results.visible = false
	_no_results = no_results
	_body.add_child(no_results)
	for project_data in projects:
		var row := _project_card(project_data)
		list.add_child(row)
		var divider := ColorRect.new()
		divider.color = Ui.BORDER
		divider.custom_minimum_size.y = 1
		list.add_child(divider)
		_project_card_rows.append({"control":row, "search":(str(project_data.get("title", "")) + " " + str(project_data.get("goal", ""))).to_lower()})
	search.text_changed.connect(_filter_project_cards)


func _filter_project_cards(value: String) -> void:
	var query := value.strip_edges().to_lower()
	var visible_count := 0
	for row in _project_card_rows:
		var card: Control = row.get("control")
		var matches := query == "" or str(row.get("search", "")).contains(query)
		card.visible = matches
		if matches: visible_count += 1
	if _search_status != null: _search_status.text = "%d matching projects" % visible_count if query != "" else "Recently updated"
	if _no_results != null: _no_results.visible = query != "" and visible_count == 0


func _project_card(p: Dictionary) -> Control:
	var tasks: Array = p.get("tasks", [])
	var done := 0
	for task in tasks:
		if bool(task.get("done", false)): done += 1
	var button := Button.new()
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size.y = 104
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Color(0, 0, 0, 0), 12), 10, 8))
	button.add_theme_stylebox_override("hover", Ui.pad(Ui.box(Color("#f6f6f6"), 12), 10, 8))
	button.add_theme_stylebox_override("pressed", Ui.pad(Ui.box(Color("#eeeeee"), 12), 10, 8))
	button.add_theme_stylebox_override("focus", Ui.pad(Ui.box(Color(0, 0, 0, 0), 12, Ui.ACCENT, 1), 10, 8))
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 8
	content.offset_right = -8
	content.offset_top = 5
	content.offset_bottom = -5
	content.add_theme_constant_override("separation", 5)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	var title := Ui.lbl(str(p.get("title", "Untitled project")), 21, Ui.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_row.add_child(title)
	title_row.add_child(Ui.lbl("%d/%d" % [done, tasks.size()] if not tasks.is_empty() else "Open", 15, Ui.MUTED))
	var arrow := TextureRect.new()
	arrow.texture = Ui.icon("chevron_right")
	arrow.custom_minimum_size = Vector2(18, 18)
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	arrow.modulate = Ui.MUTED
	title_row.add_child(arrow)
	content.add_child(title_row)
	var goal := Ui.lbl(str(p.get("goal", "")), 16, Ui.MUTED, false, true)
	goal.max_lines_visible = 1
	goal.clip_text = true
	goal.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(goal)
	var status_text := "No tasks yet" if tasks.is_empty() else ("All tasks complete" if done == tasks.size() else "%d tasks remaining" % (tasks.size() - done))
	content.add_child(Ui.lbl(status_text + "   ·   Updated " + Ui.relative_time(float(p.get("updated", 0))), 14, Ui.MUTED))
	button.add_child(content)
	button.pressed.connect(func(): open_project(str(p["id"])))
	return button


func _new_project(title: String, goal: String) -> void:
	var p := Store.new_project(title, goal)
	if p.is_empty():
		toast_requested.emit("Aoi couldn't save the new project. Check available storage and try again.")
		return
	open_project(str(p["id"]))


# ------------------------------------------------------------------- detail
func _render_detail() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_body.add_child(top)
	var back := Ui.btn("‹", "quiet")
	back.tooltip_text = "All projects"
	back.custom_minimum_size = Vector2(46, 44)
	back.pressed.connect(show_list)
	top.add_child(back)
	var breadcrumb := Ui.lbl("Project", Ui.FS_SMALL, Ui.MUTED, true)
	breadcrumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	breadcrumb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(breadcrumb)
	var more := Ui.icon_btn("more_vertical", "quiet", 48)
	more.tooltip_text = "Project options"
	more.pressed.connect(func(): _project_menu.position = more.get_global_position() + Vector2(-210, more.size.y); _project_menu.popup())
	top.add_child(more)

	var title := Ui.lbl(str(_current.get("title", "Untitled project")), 31, Ui.TEXT, true, true)
	title.add_theme_font_override("font", Ui.display_font())
	_body.add_child(title)
	var goal_text := str(_current.get("goal", "")).strip_edges()
	_body.add_child(Ui.lbl(goal_text if goal_text != "" else "Your project goal has not been added yet.", 18, Ui.MUTED, false, true))

	var flow := AgentFlow.get_flow(str(_current.get("id", "")))
	var jobs: Array = JobRunner.list_jobs(str(_current.get("id", "")))
	var latest_job: Dictionary = jobs[0] if not jobs.is_empty() and jobs[0] is Dictionary else {}

	# Project Home is the result surface. Only show a preview/report when a real
	# persisted artifact exists; otherwise state plainly that there is nothing to inspect.
	_body.add_child(_latest_result_card(latest_job, flow))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	var continue_button := Ui.btn("Continue with Aoi", "primary")
	continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	continue_button.custom_minimum_size.y = 66
	continue_button.pressed.connect(func(): chat_about.emit(str(_current.get("id", ""))))
	actions.add_child(continue_button)
	var details := Ui.btn("Work details", "ghost", "layers")
	details.custom_minimum_size = Vector2(174, 66)
	details.pressed.connect(func(): _show_work_details = true; render())
	actions.add_child(details)
	_body.add_child(actions)


func _render_detail_editor() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	_body.add_child(top)
	var cancel := Ui.btn("Cancel", "quiet")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.alignment = HORIZONTAL_ALIGNMENT_LEFT
	cancel.pressed.connect(func(): _editing_details = false; render())
	top.add_child(cancel)
	var save := Ui.btn("Save", "primary", "check")
	save.pressed.connect(func(): _save_project_details())
	top.add_child(save)
	_body.add_child(Ui.lbl("Edit project", 28, Ui.TEXT, true))
	var title_input := Ui.line("Project name")
	title_input.name = "ProjectTitleEditor"
	title_input.text = str(_current.get("title", ""))
	title_input.custom_minimum_size.y = 56
	_body.add_child(title_input)
	_body.add_child(Ui.lbl("Goal", Ui.FS_SMALL, Ui.MUTED, true))
	var goal_input := TextEdit.new()
	goal_input.name = "ProjectGoalEditor"
	goal_input.placeholder_text = "What do you want this project to achieve?"
	goal_input.text = str(_current.get("goal", ""))
	goal_input.custom_minimum_size = Vector2(0, 150)
	goal_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	goal_input.add_theme_font_size_override("font_size", 18)
	goal_input.add_theme_color_override("font_color", Ui.TEXT)
	goal_input.add_theme_color_override("font_placeholder_color", Ui.MUTED)
	goal_input.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Color("#f6f6f6"), 12), 14, 10))
	goal_input.add_theme_stylebox_override("focus", Ui.pad(Ui.box(Color("#ffffff"), 12, Ui.ACCENT, 1), 14, 10))
	_body.add_child(goal_input)


func _render_work_details() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_body.add_child(top)
	var back := Ui.btn("‹", "quiet")
	back.custom_minimum_size = Vector2(46, 44)
	back.tooltip_text = "Back to project"
	back.pressed.connect(func(): _show_work_details = false; _editing_notes = false; render())
	top.add_child(back)
	var title := Ui.lbl("Work details", 25, Ui.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var more := Ui.btn("More", "quiet")
	more.pressed.connect(func(): _project_menu.position = more.get_global_position() + Vector2(0, more.size.y); _project_menu.popup())
	top.add_child(more)
	_body.add_child(Ui.lbl(str(_current.get("title", "Project")), 19, Ui.MUTED, false, true))

	var flow := AgentFlow.get_flow(str(_current.get("id", "")))
	var jobs: Array = JobRunner.list_jobs(str(_current.get("id", "")))
	var latest_job: Dictionary = jobs[0] if not jobs.is_empty() and jobs[0] is Dictionary else {}
	_body.add_child(_project_status_card(flow, latest_job))
	var activity := _recent_progress_card(flow)
	if activity != null:
		_body.add_child(activity)

	if not flow.is_empty() and not (flow.get("tasks", []) as Array).is_empty():
		var plan_card := Ui.card(18)
		var plan_body := Ui.card_body(plan_card)
		plan_body.add_theme_constant_override("separation", 7)
		plan_body.add_child(Ui.lbl("Project roadmap", 20, Ui.TEXT, true))
		plan_body.add_child(Ui.lbl(str(flow.get("summary", "Aoi has prepared a detailed plan for this project.")), 16, Ui.MUTED, false, true))
		var plan_button := Ui.btn("Open full roadmap", "ghost", "layers")
		plan_button.pressed.connect(func(): request_open_flow.emit(str(_current.get("id", ""))))
		plan_body.add_child(plan_button)
		_body.add_child(plan_card)
	_body.add_child(_tasks_card())
	if str(_current.get("notes", "")).strip_edges() != "" or _editing_notes:
		_body.add_child(_notes_card())
	else:
		var notes_prompt := Ui.btn("Add project notes", "quiet", "notebook")
		notes_prompt.alignment = HORIZONTAL_ALIGNMENT_LEFT
		notes_prompt.pressed.connect(func(): _editing_notes = true; render())
		_body.add_child(notes_prompt)


func _project_status_card(flow: Dictionary, latest_job: Dictionary) -> Control:
	var card := Ui.card(20)
	var body := Ui.card_body(card)
	body.add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	body.add_child(header)
	header.add_child(Ui.lbl("Work status", 12, Ui.MUTED, true))
	var state := "Ready"
	var tint := Ui.MUTED
	var headline := "Ready to continue"
	var description := "Your goal and project history stay together here."
	var flow_tasks: Array = flow.get("tasks", []) if flow.get("tasks", []) is Array else []
	var done_count := 0
	var review_count := 0
	var active_count := 0
	for task in flow_tasks:
		match str(task.get("status", "todo")):
			"done": done_count += 1
			"review": review_count += 1
			"in_progress": active_count += 1
	var job_state := str(latest_job.get("state", ""))
	match job_state:
		"running", "queued":
			state = "In progress"; tint = Ui.GREEN
			headline = "Aoi is working on this project"
			description = str(latest_job.get("task_name", "Working through the next step"))
		"paused", "interrupted", "cancelled":
			state = "Paused"; tint = Ui.AMBER
			headline = "Your work is safely paused"
			description = "The latest saved checkpoint is still part of this project."
		"failed":
			state = "Needs attention"; tint = Ui.AMBER
			headline = "One step needs attention"
			description = str(latest_job.get("error", latest_job.get("summary", "Aoi could not finish the last step.")))
		"completed":
			state = "Latest run complete"; tint = Ui.GREEN
			headline = "Aoi completed the latest run"
			description = str(latest_job.get("summary", "A result was saved to this project."))
		_:
			var phase := str(flow.get("phase", "brief"))
			if review_count > 0:
				state = "Review ready"; tint = Ui.ACCENT_SOFT
				headline = "Aoi has work ready for your review"
				description = "Review the latest milestone before the next part continues."
			elif active_count > 0 or phase == "building":
				state = "In progress"; tint = Ui.GREEN
				headline = "Work is moving forward"
				description = "Aoi is following the saved project roadmap."
			elif not flow_tasks.is_empty() and done_count == flow_tasks.size():
				state = "Plan complete"; tint = Ui.GREEN
				headline = "The planned milestones are approved"
				description = "The roadmap is complete. Review the actual results before calling the project finished."
			elif not flow_tasks.is_empty():
				state = "Planned"; tint = Ui.ACCENT_SOFT
				headline = "Your project has a clear plan"
				description = "The next milestone is ready when you are."
			else:
				state = "Ready"; tint = Ui.MUTED
				headline = "Ready to shape the work"
				description = "Continue with Aoi to plan the complete result, not just a workspace."
	header.add_child(Ui.chip(state, tint))
	body.add_child(Ui.lbl(headline, 23, Ui.TEXT, true, true))
	body.add_child(Ui.lbl(description, 16, Ui.MUTED, false, true))
	if not flow_tasks.is_empty():
		var progress_row := HBoxContainer.new()
		progress_row.add_theme_constant_override("separation", 10)
		var progress := ProgressBar.new()
		progress.min_value = 0
		progress.max_value = flow_tasks.size()
		progress.value = done_count
		progress.show_percentage = false
		progress.custom_minimum_size.y = 8
		progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		progress.add_theme_stylebox_override("background", Ui.box(Color("#e9edf3"), 8))
		progress.add_theme_stylebox_override("fill", Ui.box(Color("#202a3a"), 8))
		progress_row.add_child(progress)
		progress_row.add_child(Ui.lbl("%d/%d" % [done_count, flow_tasks.size()], 14, Ui.MUTED, true))
		body.add_child(progress_row)
		var next_task: Dictionary = {}
		for task in flow_tasks:
			if str(task.get("status", "todo")) != "done":
				next_task = task
				break
		if not next_task.is_empty():
			body.add_child(Ui.lbl("Next step", 14, Ui.MUTED, true))
			body.add_child(Ui.lbl(str(next_task.get("title", "Next step")), 16, Ui.TEXT, true, true))
	elif not latest_job.is_empty() and job_state in ["running", "queued", "completed"]:
		var progress_row := HBoxContainer.new()
		var progress := ProgressBar.new()
		progress.min_value = 0
		progress.max_value = 1
		progress.value = float(latest_job.get("progress", 0.0))
		progress.show_percentage = false
		progress.custom_minimum_size.y = 8
		progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		progress.add_theme_stylebox_override("background", Ui.box(Color("#e9edf3"), 8))
		progress.add_theme_stylebox_override("fill", Ui.box(Color("#202a3a"), 8))
		progress_row.add_child(progress)
		progress_row.add_child(Ui.lbl("%d%%" % roundi(float(latest_job.get("progress", 0.0)) * 100.0), 14, Ui.MUTED, true))
		body.add_child(progress_row)
	return card


func _latest_result_card(job: Dictionary, flow: Dictionary = {}) -> Control:
	var preview_path := str(_current.get("preview_path", "")).strip_edges()
	var has_game_capture := preview_path != "" and FileAccess.file_exists(preview_path) and str(_current.get("preview_kind", "")) == "paired_runtime_capture"
	var job_id := str(job.get("id", ""))
	var has_report := job_id != "" and JobRunner.has_artifact(job_id, "report.md")
	var job_state := str(job.get("state", ""))

	var card := Ui.card(22)
	var body := Ui.card_body(card)
	body.add_theme_constant_override("separation", 12)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	body.add_child(header)
	var eyebrow := Ui.lbl("Latest result", 12, Ui.MUTED, true)
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(eyebrow)
	if has_game_capture or has_report:
		header.add_child(Ui.chip("Ready to view", Ui.GREEN))
	elif job_state == "failed":
		header.add_child(Ui.chip("Needs attention", Ui.AMBER))
	elif job_state in ["running", "queued"]:
		header.add_child(Ui.chip("In progress", Ui.GREEN))

	var capture_loaded := false
	if has_game_capture:
		var image := Image.new()
		if image.load(preview_path) == OK:
			var texture := TextureRect.new()
			texture.texture = ImageTexture.create_from_image(image)
			texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			texture.custom_minimum_size = Vector2(0, 190)
			texture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			body.add_child(texture)
			body.add_child(Ui.lbl("Capture from the connected running game", 14, Ui.MUTED))
			var open_capture := Ui.btn("View game capture", "ghost", "image")
			open_capture.name = "OpenProjectCaptureButton"
			open_capture.pressed.connect(func(): _show_project_capture(preview_path))
			body.add_child(open_capture)
			capture_loaded = true

	if has_report:
		var summary := str(job.get("summary", "A project run report is ready.")).strip_edges()
		body.add_child(Ui.lbl(summary if summary != "" else "A project run report is ready to inspect.", 17, Ui.TEXT, true, true))
		var read := Ui.btn("Open run report", "ghost", "notebook")
		read.pressed.connect(func(): _show_job_report(job_id))
		body.add_child(read)

	if not capture_loaded and not has_report:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var symbol := TextureRect.new()
		symbol.texture = Ui.icon("clapperboard" if str(_current.get("project_kind", "")) == "game" else "notebook")
		symbol.custom_minimum_size = Vector2(25, 25)
		symbol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		symbol.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		symbol.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		symbol.modulate = Ui.MUTED
		row.add_child(symbol)
		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_theme_constant_override("separation", 5)
		var title := "Nothing to play yet" if str(_current.get("project_kind", "")) == "game" else "Nothing to review yet"
		var detail := "This project is saved. A playable build or run report will show up here when one is ready."
		if str(_current.get("project_kind", "")) == "game":
			detail = "This project is saved. A playable build or run report will show up here when one is ready."
		if job_state == "failed":
			title = "The last attempt needs attention"
			detail = str(job.get("error", job.get("summary", "Aoi could not finish the last attempt."))).strip_edges()
		elif job_state in ["running", "queued"]:
			title = "Aoi is working on this project"
			detail = str(job.get("task_name", "The current task is still running.")).strip_edges()
		elif job_state in ["paused", "interrupted", "cancelled"]:
			title = "Your latest work is paused"
			detail = "The saved checkpoint is still here. Continue with Aoi when you are ready."
		elif job_state == "completed":
			title = "The last run finished"
			detail = "The run completed, but no preview or report was attached to it. Continue with Aoi to produce a reviewable result."
		copy.add_child(Ui.lbl(title, 20, Ui.TEXT, true, true))
		copy.add_child(Ui.lbl(detail, 15, Ui.MUTED, false, true))
		row.add_child(copy)
		body.add_child(row)
		var next_task: Dictionary = {}
		for task in flow.get("tasks", []):
			if str(task.get("status", "todo")) != "done":
				next_task = task
				break
		if not next_task.is_empty() and job_state not in ["failed", "running", "queued", "paused", "interrupted", "cancelled"]:
			var next_copy := HBoxContainer.new()
			next_copy.add_theme_constant_override("separation", 7)
			next_copy.add_child(Ui.lbl("Next step", 14, Ui.MUTED, true))
			var next_title := Ui.lbl(str(next_task.get("title", "Continue the project.")), 14, Ui.TEXT, true, true)
			next_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			next_copy.add_child(next_title)
			body.add_child(next_copy)

	return card


func _show_project_capture(path: String) -> void:
	var image := Image.new()
	if image.load(path) != OK:
		return
	var sheet := Sheet.new()
	sheet.name = "ProjectCaptureSheet"
	add_child(sheet)
	sheet.open("Game capture", 0.88)
	var texture := TextureRect.new()
	texture.texture = ImageTexture.create_from_image(image)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.custom_minimum_size = Vector2(0, 420)
	texture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.body.add_child(texture)
	sheet.body.add_child(Ui.lbl("Saved from the connected runtime. This is a captured result, not a live game session.", 14, Ui.MUTED, false, true))


func _recent_progress_card(flow: Dictionary) -> Control:
	var events: Array = flow.get("activity", []) if flow.get("activity", []) is Array else []
	if events.is_empty(): return null
	var card := Ui.card(18)
	var body := Ui.card_body(card)
	body.add_theme_constant_override("separation", 8)
	body.add_child(Ui.lbl("Recent activity", 12, Ui.MUTED, true))
	var count := mini(3, events.size())
	for index in range(count):
		var event: Dictionary = events[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := ColorRect.new()
		dot.color = Ui.GREEN if str(event.get("action", "")).contains("approved") or str(event.get("action", "")).contains("created") else Ui.ACCENT_SOFT
		dot.custom_minimum_size = Vector2(7, 7)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_child(Ui.lbl(_humanize_project_event(event, flow), 15, Ui.TEXT, true, true))
		var detail := _project_event_context(event, flow)
		if detail != "": copy.add_child(Ui.lbl(detail, 14, Ui.MUTED, false, true))
		row.add_child(copy)
		body.add_child(row)
	return card


func _humanize_project_event(event: Dictionary, flow: Dictionary = {}) -> String:
	var action := str(event.get("action", ""))
	var task := _project_event_task(event, flow)
	if action == "Plan created": return "Project roadmap prepared"
	if action == "Task updated":
		if not task.is_empty():
			match str(task.get("status", "todo")):
				"done": return "Milestone completed"
				"in_progress": return "Milestone started"
				"review": return "Milestone ready for review"
		return "Milestone updated"
	if action == "Result approved": return "A result was approved"
	if action == "Revision requested": return "A revision was requested"
	if action.begins_with("project.write_file") or action.begins_with("project.create_scene"): return "Project files updated"
	if action.begins_with("godot."): return "Game project checked"
	if action.begins_with("github."): return "Repository work updated"
	if action.begins_with("linux."): return "Connected workspace updated"
	if action.contains("completed"): return "Aoi completed a project step"
	if action.contains("failed"): return "A project step needs attention"
	return action if action != "" else "Project activity"


func _project_event_task(event: Dictionary, flow: Dictionary) -> Dictionary:
	var detail := str(event.get("detail", "")).strip_edges()
	for task in flow.get("tasks", []):
		if str(task.get("id", "")) == detail:
			return task
	return {}


func _project_event_context(event: Dictionary, flow: Dictionary) -> String:
	var action := str(event.get("action", ""))
	var task := _project_event_task(event, flow)
	if not task.is_empty(): return str(task.get("title", "")).strip_edges()
	var detail := str(event.get("detail", "")).strip_edges()
	# Internal ids and opaque references are never useful in the consumer view.
	if detail.is_empty() or detail.is_valid_int() or detail.length() < 6 or detail.contains("_") and detail.length() < 24:
		return ""
	if action == "Plan created" or action == "Agent status: working":
		return detail.left(110)
	return detail.left(110)


func _show_job_report(job_id: String) -> void:
	var result := JobRunner.read_artifact(job_id, "report.md")
	if not bool(result.get("ok", false)):
		return
	var sheet := Sheet.new()
	add_child(sheet)
	sheet.open("Project result", 0.88)
	var content := TextEdit.new()
	content.editable = false
	content.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	content.text = str(result.get("content", ""))
	content.custom_minimum_size.y = 340
	content.add_theme_font_size_override("font_size", 17)
	content.add_theme_color_override("font_color", Ui.TEXT)
	content.add_theme_stylebox_override("normal", Ui.box(Color("#f7f8fb"), 14, Ui.BORDER, 1))
	sheet.body.add_child(content)


func _save_project_details() -> void:
	var title_input := find_child("ProjectTitleEditor", true, false) as LineEdit
	var goal_input := find_child("ProjectGoalEditor", true, false) as TextEdit
	if title_input == null or goal_input == null:
		return
	var title := title_input.text.strip_edges()
	if title == "":
		title_input.grab_focus()
		return
	var previous := _current.duplicate(true)
	_current["title"] = title
	_current["goal"] = goal_input.text.strip_edges()
	if not _save_project_change(previous):
		return
	_editing_details = false
	render()


func _save_project_change(previous: Dictionary) -> bool:
	if Store.save_project(_current):
		return true
	_current = previous
	toast_requested.emit("Aoi couldn't save this project change. Your previous saved data was preserved.")
	return false


func _on_project_menu_action(action_id: int) -> void:
	if _current.is_empty(): return
	if action_id == 0:
		var summary := str(_current.get("title", "Project")) + "\n\n" + str(_current.get("goal", "")) + "\n\n" + str(_current.get("notes", ""))
		DisplayServer.clipboard_set(summary.strip_edges())
		return
	if action_id == 2:
		request_open_flow.emit(str(_current.get("id", "")))
		return
	if action_id == 3:
		_editing_details = true
		render()
		return
	if action_id == 1:
		request_delete.emit(str(_current.get("id", "")))


func _tasks_card() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	var tasks: Array = _current["tasks"]
	var done := 0
	for task in tasks:
		if bool(task.get("done", false)): done += 1
	var heading := HBoxContainer.new()
	var heading_label := Ui.lbl("Tasks", 21, Ui.TEXT, true)
	heading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(heading_label)
	heading.add_child(Ui.lbl("%d of %d complete" % [done, tasks.size()], 15, Ui.MUTED))
	section.add_child(heading)
	if tasks.is_empty():
		section.add_child(Ui.lbl("No tasks yet. Ask Aoi to plan the work, or add one below.", 16, Ui.MUTED, false, true))
	for i in range(tasks.size()):
		var task: Dictionary = tasks[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var check := Ui.icon_btn("check_circle" if bool(task.get("done", false)) else "circle", "quiet", 42)
		check.pressed.connect(func():
			var previous := _current.duplicate(true)
			task["done"] = not bool(task.get("done", false))
			if _save_project_change(previous): render())
		row.add_child(check)
		var label := Ui.lbl(str(task.get("text", task.get("title", ""))), 18, Ui.MUTED if bool(task.get("done", false)) else Ui.TEXT, false, true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		var remove := Ui.icon_btn("trash", "quiet", 40)
		remove.tooltip_text = "Remove task"
		remove.pressed.connect(func():
			var previous := _current.duplicate(true)
			tasks.remove_at(i)
			if _save_project_change(previous): render())
		row.add_child(remove)
		section.add_child(row)
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	var add_edit := Ui.line("Add a task")
	add_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(add_edit)
	var add_btn := Ui.icon_btn("plus", "primary", 48)
	var do_add := func():
		if add_edit.text.strip_edges() == "":
			return
		var previous := _current.duplicate(true)
		var previous_tasks: Array = previous.get("tasks", [])
		Store.add_task(_current, add_edit.text)
		var updated_tasks: Array = _current.get("tasks", [])
		if previous_tasks.size() == updated_tasks.size():
			return
		if not _save_project_change(previous):
			return
		add_edit.clear()
		render()
	add_btn.pressed.connect(do_add)
	add_edit.text_submitted.connect(func(_t): do_add.call())
	add_row.add_child(add_btn)
	section.add_child(add_row)
	return section


func _notes_card() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	section.add_child(head)
	var title := Ui.lbl("Notes", 21, Ui.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var toggle := Ui.btn("Save" if _editing_notes else "Edit", "quiet", "" if _editing_notes else "edit")
	head.add_child(toggle)
	var notes := str(_current.get("notes", ""))
	if _editing_notes:
		var editor := TextEdit.new()
		editor.text = notes
		editor.custom_minimum_size = Vector2(0, 300)
		editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		editor.add_theme_font_size_override("font_size", 19)
		editor.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Color("#f6f6f6"), 14), 14, 12))
		editor.add_theme_stylebox_override("focus", Ui.pad(Ui.box(Color("#fafafa"), 14, Ui.ACCENT, 1), 14, 12))
		section.add_child(editor)
		toggle.pressed.connect(func():
			var previous := _current.duplicate(true)
			_current["notes"] = editor.text
			if not _save_project_change(previous):
				return
			_editing_notes = false
			render())
	else:
		if notes.strip_edges() == "":
			section.add_child(Ui.lbl("No notes yet. Save useful answers from chat or add project notes here.", 16, Ui.MUTED, false, true))
		else:
			var rich := RichTextLabel.new()
			rich.bbcode_enabled = true
			rich.fit_content = true
			rich.scroll_active = false
			rich.selection_enabled = false
			rich.mouse_filter = Control.MOUSE_FILTER_PASS
			rich.add_theme_font_size_override("normal_font_size", 19)
			rich.add_theme_font_size_override("bold_font_size", 19)
			rich.add_theme_constant_override("line_separation", 4)
			rich.add_theme_font_override("bold_font", Ui.bold_font())
			rich.add_theme_color_override("default_color", Ui.TEXT)
			rich.text = Md.to_bbcode(notes)
			section.add_child(rich)
		toggle.pressed.connect(func(): _editing_notes = true; render())
	return section

