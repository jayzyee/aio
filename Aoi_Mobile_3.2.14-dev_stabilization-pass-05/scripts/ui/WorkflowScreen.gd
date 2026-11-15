extends ScrollContainer
## Project orchestration: brief, specialist roles, task graph, decisions and auditable runs.
const Ui = preload("res://scripts/ui/Ui.gd")

signal plan_requested(project_id: String)
signal run_task_requested(project_id: String, task: Dictionary)
signal open_task_chat_requested(session_id: String)
signal toast(text: String)

var _body: VBoxContainer
var _project_id := ""
var _project: Dictionary = {}
var _flow: Dictionary = {}

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]: pad.add_theme_constant_override("margin_" + side, 20)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 32)
	add_child(pad)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 18)
	pad.add_child(_body)
	AgentFlow.changed.connect(func(id: String):
		if id == _project_id: _reload())
	render()

func open_project(project_id: String) -> void:
	_project_id = project_id
	_reload()

func render() -> void:
	if _project_id == "":
		_render_project_list()
	else:
		_reload()

func _reload() -> void:
	_project = Store.get_project(_project_id)
	if _project.is_empty():
		_project_id = ""
		_render_project_list()
		return
	_flow = AgentFlow.ensure_flow(_project)
	_render_detail()

func _clear() -> void:
	for child in _body.get_children(): child.queue_free()

func _render_project_list() -> void:
	_clear()
	_body.add_child(Ui.lbl("Agent workflow", Ui.FS_TITLE, Ui.TEXT, true))
	_body.add_child(Ui.lbl("Turn project goals into coordinated, reviewable work. Choose a project to open its task flow.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
	var projects := Store.list_projects()
	if projects.is_empty():
		var card := Ui.card(22)
		var v := Ui.card_body(card)
		v.add_child(Ui.lbl("Start with a project", Ui.FS + 2, Ui.TEXT, true))
		v.add_child(Ui.lbl("Create a project first. Its brief, tasks, decisions and tool history will become shared context for the agent team.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
		_body.add_child(card)
		return
	for project in projects:
		var flow := AgentFlow.get_flow(str(project.get("id", "")))
		var card := Ui.card(18)
		var v := Ui.card_body(card)
		var top := HBoxContainer.new()
		var name := Ui.lbl(str(project.get("title", "Project")), Ui.FS + 1, Ui.TEXT, true, true)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name)
		top.add_child(Ui.chip(str(flow.get("phase", "brief")).capitalize(), Ui.ACCENT))
		v.add_child(top)
		var goal := str(project.get("goal", "")).strip_edges()
		if goal != "": v.add_child(Ui.lbl(goal, Ui.FS_SMALL, Ui.MUTED, false, true))
		var tasks: Array = flow.get("tasks", [])
		v.add_child(Ui.lbl("%d workflow tasks · %d decisions" % [tasks.size(), (flow.get("decisions", []) as Array).size()], Ui.FS_SMALL - 1, Ui.MUTED))
		var open := Ui.btn("Open workflow", "ghost", "forward")
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id := str(project.get("id", ""))
		open.pressed.connect(func(): open_project(id))
		v.add_child(open)
		_body.add_child(card)

func _render_detail() -> void:
	_clear()
	var back := Ui.btn("All workflows", "quiet", "chevron_right")
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func(): _project_id = ""; _render_project_list())
	_body.add_child(back)
	var header := HBoxContainer.new()
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(Ui.lbl("Agent workflow", Ui.FS_TITLE, Ui.TEXT, true))
	titles.add_child(Ui.lbl(str(_project.get("title", "Project")), Ui.FS_SMALL, Ui.MUTED, false, true))
	header.add_child(titles)
	header.add_child(Ui.chip(str(_flow.get("phase", "brief")).capitalize(), Ui.ACCENT))
	_body.add_child(header)
	var brief := Ui.card(20)
	var bv := Ui.card_body(brief)
	bv.add_child(Ui.lbl("Project brief", Ui.FS + 1, Ui.TEXT, true))
	bv.add_child(Ui.lbl(str(_project.get("goal", "Add a clear project goal in Projects.")), Ui.FS_SMALL + 1, Ui.MUTED, false, true))
	var summary := str(_flow.get("summary", "No agent plan yet. Start by asking the team to turn the brief into a sequenced plan."))
	bv.add_child(Ui.lbl(summary, Ui.FS_SMALL, Ui.TEXT, false, true))
	_body.add_child(brief)
	_body.add_child(_pipeline_card())
	_body.add_child(_research_card())
	_body.add_child(_agents_card())
	var plan_row := HBoxContainer.new()
	var plan := Ui.btn("Generate agent plan", "primary", "spark")
	plan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plan.pressed.connect(func(): plan_requested.emit(_project_id))
	plan_row.add_child(plan)
	var decision := Ui.btn("Capture decision", "ghost", "plus")
	decision.pressed.connect(_capture_decision)
	plan_row.add_child(decision)
	_body.add_child(plan_row)
	_body.add_child(_tasks_board())
	_body.add_child(_knowledge_card())
	_body.add_child(_decisions_card())
	_body.add_child(_activity_card())
	_body.add_child(Ui.lbl("Agent roles are specialist work modes routed through your selected model in this build. They share one project record and tool ledger; separate independent model instances and unattended agents are not claimed.", Ui.FS_SMALL - 2, Ui.MUTED, false, true))

func _pipeline_card() -> Control:
	var card := Ui.card(18)
	var v := Ui.card_body(card)
	v.add_child(Ui.lbl("Workflow stages", Ui.FS, Ui.TEXT, true))
	v.add_child(Ui.lbl("Research → plan → prototype → implement → test and inspect → refine → approve. Findings and task evidence are saved before the next stage can begin.", Ui.FS_SMALL - 1, Ui.MUTED, false, true))
	var graph: Array = _flow.get("workflow_graph", [])
	var tasks: Array = _flow.get("tasks", [])
	var has_plan := not tasks.is_empty()
	var any_active := false
	var any_review := false
	var all_done := has_plan
	for task in tasks:
		var state := str(task.get("status", "todo"))
		if state == "in_progress": any_active = true
		if state == "review": any_review = true
		if state != "done": all_done = false
	var research: Dictionary = _flow.get("research", {})
	var research_state := str(research.get("status", "legacy"))
	var research_display := "complete" if research_state in ["ready", "legacy"] else ("skipped" if research_state == "unavailable" else ("active" if research_state == "collecting" else "pending"))
	var statuses := {"research":research_display,"plan":"pending" if not has_plan else "complete","implement":"pending" if not has_plan else ("active" if any_active else "ready"),"verify":"pending" if not has_plan else ("review" if any_review else ("complete" if all_done else "ready")),"approve":"complete" if all_done else ("active" if any_review else "pending")}
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	for stage in graph:
		var id := str(stage.get("id", ""))
		var state := str(statuses.get(id, stage.get("status", "pending")))
		var tile := PanelContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tile_color := Color("#f0f0f0") if state in ["complete", "active", "review"] else Color("#f7f7f7")
		if state == "skipped": tile_color = Color("#f1eee8")
		tile.add_theme_stylebox_override("panel", Ui.box(tile_color, 12))
		var label := Ui.lbl(str(stage.get("title", id)), 12, Ui.GREEN if state == "complete" else (Ui.ACCENT if state in ["active", "review"] else (Ui.AMBER if state == "skipped" else Ui.MUTED)), true)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.add_child(label)
		row.add_child(tile)
	v.add_child(row)
	return card


func _research_card() -> Control:
	var research: Dictionary = _flow.get("research", {})
	var required := bool(research.get("required", false))
	var status := str(research.get("status", "legacy"))
	var queries: Array = research.get("queries", []) if research.get("queries", []) is Array else []
	var sources: Array = research.get("sources", []) if research.get("sources", []) is Array else []
	var domains: Dictionary = {}
	for source in sources:
		if source is Dictionary:
			var domain := str(source.get("hostname", ""))
			if domain != "": domains[domain] = true
	var card := Ui.card(18)
	var v := Ui.card_body(card)
	var heading := HBoxContainer.new()
	heading.add_child(Ui.lbl("Research foundation", Ui.FS, Ui.TEXT, true))
	heading.add_spacer(false)
	var unavailable := status == "unavailable"
	var badge_text := "Live search unavailable · planning continues" if unavailable else ("Research not required for this existing project" if not required else ("Evidence saved" if status == "ready" else ("Gathering evidence" if status == "collecting" else "Required before planning")))
	heading.add_child(Ui.chip(badge_text, Ui.AMBER if unavailable else (Ui.GREEN if (not required or status == "ready") else (Ui.ACCENT if status == "collecting" else Ui.AMBER))))
	v.add_child(heading)
	if required:
		v.add_child(Ui.lbl("Aoi studies references, real user feedback, official documentation, production assets and risks before creating the build roadmap.", Ui.FS_SMALL - 1, Ui.MUTED, false, true))
		v.add_child(Ui.lbl("%d distinct searches · %d saved sources · %d domains" % [queries.size(), sources.size(), domains.size()], Ui.FS_SMALL, Ui.TEXT, true))
		if status == "ready":
			var brief: Dictionary = research.get("brief", {})
			v.add_child(Ui.lbl(str(brief.get("executive_summary", "Research brief saved.")), Ui.FS_SMALL, Ui.MUTED, false, true))
		else:
			v.add_child(Ui.lbl("The roadmap remains locked until source-backed findings and citations meet the research standard. Connect Brave Search in Plugins & tools → Research if it is not configured.", Ui.FS_SMALL - 1, Ui.MUTED, false, true))
	elif unavailable:
		v.add_child(Ui.lbl("Live web search is not connected. Aoi can still plan and build from your brief, saved decisions and project files, and may use Wikipedia for stable background facts. It will not claim current web research or invent source citations. Connect a research provider later to add source-backed findings.", Ui.FS_SMALL - 1, Ui.MUTED, false, true))
	else:
		v.add_child(Ui.lbl("This project predates the research gate. You can keep working normally; new substantial projects use source-backed research when a provider is configured.", Ui.FS_SMALL - 1, Ui.MUTED, false, true))
	return card


func _agents_card() -> Control:
	var card := Ui.card(18)
	var v := Ui.card_body(card)
	v.add_child(Ui.lbl("The project team", Ui.FS, Ui.TEXT, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var role_data := [
		["Planner", "Breaks the brief into milestones and dependencies.", "chart"],
		["Researcher", "Studies references, user feedback, official documentation, assets, risks and constraints with source evidence.", "search"],
		["Engineer", "Implements changes using connected tools.", "code"],
		["Reviewer", "Checks results, tests and acceptance criteria.", "check_circle"]
	]
	var agent_status: Dictionary = {}
	for agent in _flow.get("agents", []): agent_status[str(agent.get("role", ""))] = agent
	for role in role_data:
		var tile := PanelContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_theme_stylebox_override("panel", Ui.box(Color("#f7f8fa"), 14, Ui.BORDER, 1))
		var inner := MarginContainer.new()
		for side in ["left", "right"]: inner.add_theme_constant_override("margin_" + side, 12)
		for side in ["top", "bottom"]: inner.add_theme_constant_override("margin_" + side, 10)
		tile.add_child(inner)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 5)
		inner.add_child(col)
		var title := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = Ui.icon(str(role[2]))
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Ui.ACCENT
		title.add_child(icon)
		title.add_child(Ui.lbl(str(role[0]), Ui.FS_SMALL, Ui.TEXT, true))
		col.add_child(title)
		col.add_child(Ui.lbl(str(role[1]), Ui.FS_SMALL - 3, Ui.MUTED, false, true))
		var status: Dictionary = agent_status.get(str(role[0]), {})
		var status_text := str(status.get("status", "ready")).capitalize()
		if str(status.get("current_task", "")) != "": status_text += " · " + str(status.get("current_task", "")).left(36)
		col.add_child(Ui.lbl(status_text, Ui.FS_SMALL - 3, Ui.ACCENT if str(status.get("status", "ready")) != "ready" else Ui.MUTED, true, true))
		grid.add_child(tile)
	return card

func _tasks_board() -> Control:
	var card := Ui.card(18)
	var v := Ui.card_body(card)
	var tasks: Array = _flow.get("tasks", [])
	var counts := {"todo":0,"in_progress":0,"review":0,"done":0}
	for task in tasks:
		var state := str(task.get("status", "todo"))
		if counts.has(state): counts[state] += 1
	v.add_child(Ui.lbl("Execution board  ·  %d tasks" % tasks.size(), Ui.FS, Ui.TEXT, true))
	var prog := ProgressBar.new()
	prog.show_percentage = false
	prog.custom_minimum_size.y = 9
	prog.max_value = max(1, tasks.size())
	prog.value = counts["done"]
	prog.add_theme_stylebox_override("background", Ui.box(Ui.BORDER, 5))
	prog.add_theme_stylebox_override("fill", Ui.box(Ui.ACCENT, 5))
	v.add_child(prog)
	if tasks.is_empty():
		v.add_child(Ui.lbl("Your plan will appear here as tasks with owners, priorities and review criteria.", Ui.FS_SMALL, Ui.MUTED, false, true))
	else:
		for group in [["To do", "todo"], ["In progress", "in_progress"], ["Ready for review", "review"], ["Done", "done"]]:
			var section_tasks: Array = []
			for task in tasks:
				if str(task.get("status", "todo")) == str(group[1]): section_tasks.append(task)
			if section_tasks.is_empty(): continue
			var heading := HBoxContainer.new()
			heading.add_child(Ui.lbl(str(group[0]), Ui.FS_SMALL, Ui.TEXT, true))
			heading.add_child(Ui.lbl("%d" % section_tasks.size(), Ui.FS_SMALL - 2, Ui.MUTED))
			v.add_child(heading)
			for task in section_tasks: v.add_child(_task_row(task))
	return card

func _task_row(task: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Ui.box(Color("#fafbfc"), 14, Ui.BORDER, 1))
	var m := MarginContainer.new()
	for side in ["left", "right"]: m.add_theme_constant_override("margin_" + side, 12)
	for side in ["top", "bottom"]: m.add_theme_constant_override("margin_" + side, 11)
	panel.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	m.add_child(col)
	var heading := HBoxContainer.new()
	var title := Ui.lbl(str(task.get("title", "Task")), Ui.FS_SMALL, Ui.TEXT, true, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(Ui.chip(str(task.get("priority", "normal")).capitalize(), Ui.AMBER if str(task.get("priority", "normal")) == "high" else Ui.MUTED))
	col.add_child(heading)
	var detail := str(task.get("detail", ""))
	if detail != "": col.add_child(Ui.lbl(detail, Ui.FS_SMALL - 2, Ui.MUTED, false, true))
	var acceptance := str(task.get("acceptance", ""))
	if acceptance != "": col.add_child(Ui.lbl("Done when: " + acceptance, Ui.FS_SMALL - 2, Ui.TEXT, false, true))
	var deliverables: Variant = task.get("deliverables", [])
	if deliverables is Array and not deliverables.is_empty():
		var deliverable_labels := PackedStringArray()
		for deliverable in deliverables: deliverable_labels.append(str(deliverable))
		col.add_child(Ui.lbl("Deliverables: " + " · ".join(deliverable_labels), Ui.FS_SMALL - 3, Ui.MUTED, false, true))
	var verification := str(task.get("verification", "")).strip_edges()
	if verification != "": col.add_child(Ui.lbl("Verify: " + verification, Ui.FS_SMALL - 3, Ui.MUTED, false, true))
	var state := str(task.get("status", "todo"))
	var review_summary := str(task.get("review_summary", "")).strip_edges()
	var last_error := str(task.get("last_error", "")).strip_edges()
	if state == "review" and review_summary != "":
		col.add_child(Ui.lbl("Result preview", Ui.FS_SMALL - 2, Ui.TEXT, true))
		var preview := Ui.lbl(review_summary, Ui.FS_SMALL - 2, Ui.MUTED, false, true)
		preview.name = "WorkflowTaskResultPreview"
		col.add_child(preview)
		col.add_child(Ui.lbl("Open the task chat for the full response and evidence.", Ui.FS_SMALL - 3, Ui.MUTED, false, true))
	if state == "todo" and last_error != "":
		col.add_child(Ui.lbl("Last attempt stopped: " + last_error.left(260), Ui.FS_SMALL - 2, Ui.AMBER, false, true))
	var meta := "%s  ·  %s  ·  attempt %d" % [str(task.get("role", "Engineer")), str(task.get("status", "todo")).replace("_", " ").capitalize(), int(task.get("attempts", 0)) + 1]
	col.add_child(Ui.lbl(meta, Ui.FS_SMALL - 3, Ui.ACCENT))
	var id := str(task.get("id", ""))
	var actions := HBoxContainer.new()
	if state == "review":
		var session_id := str(task.get("session_id", ""))
		if session_id != "":
			var open_chat := Ui.btn("Review task chat", "quiet")
			open_chat.name = "OpenWorkflowTaskChat"
			open_chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			open_chat.pressed.connect(func(): open_task_chat_requested.emit(session_id))
			actions.add_child(open_chat)
		var revise := Ui.btn("Request changes", "ghost", "regenerate")
		revise.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		revise.pressed.connect(func():
			var dialog := AcceptDialog.new()
			dialog.title = "Request a revision"
			dialog.dialog_text = "Optional feedback for the next attempt."
			var feedback := LineEdit.new()
			feedback.placeholder_text = "What needs to change?"
			dialog.add_child(feedback)
			dialog.confirmed.connect(func():
				AgentFlow.request_task_revision(_project_id, id, feedback.text)
				_reload())
			add_child(dialog); dialog.popup_centered(Vector2i(520, 220)))
		actions.add_child(revise)
		var approve := Ui.btn("Approve result", "primary", "check")
		approve.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		approve.pressed.connect(func():
			if AgentFlow.approve_task(_project_id, id): _reload())
		actions.add_child(approve)
	elif state == "done":
		var reopen := Ui.btn("Reopen task", "ghost", "regenerate")
		reopen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reopen.pressed.connect(func(): AgentFlow.update_task(_project_id, id, {"status":"todo", "title":str(task.get("title", "")), "role":str(task.get("role", "Engineer"))}))
		actions.add_child(reopen)
	else:
		var runnable := AgentFlow.can_run_task(_project_id, id)
		var session_id := str(task.get("session_id", ""))
		if state == "in_progress" and session_id != "":
			var return_to_chat := Ui.btn("Return to task chat", "ghost")
			return_to_chat.name = "OpenWorkflowTaskChat"
			return_to_chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			return_to_chat.pressed.connect(func(): open_task_chat_requested.emit(session_id))
			actions.add_child(return_to_chat)
		else:
			if state == "todo" and session_id != "":
				var previous_chat := Ui.btn("Previous attempt chat", "quiet")
				previous_chat.name = "OpenWorkflowTaskChat"
				previous_chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				previous_chat.pressed.connect(func(): open_task_chat_requested.emit(session_id))
				actions.add_child(previous_chat)
			var run_label := "Retry task" if last_error != "" else ("Work on this" if runnable else ("In progress" if state == "in_progress" else "Waiting on dependencies"))
			var run := Ui.btn(run_label, "primary", "play")
			run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			run.disabled = not runnable
			run.pressed.connect(func(): run_task_requested.emit(_project_id, task))
			actions.add_child(run)
	col.add_child(actions)
	return panel


func _knowledge_card() -> Control:
	var card := Ui.card(18)
	var v := Ui.card_body(card)
	var title_row := HBoxContainer.new()
	var title := Ui.lbl("Project knowledge", Ui.FS, Ui.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var add := Ui.btn("Add note", "quiet", "plus")
	add.pressed.connect(_add_knowledge)
	title_row.add_child(add)
	var add_playbook := Ui.btn("Add SOP", "ghost", "notebook")
	add_playbook.pressed.connect(_add_playbook)
	title_row.add_child(add_playbook)
	v.add_child(title_row)
	var books: Array = _flow.get("playbooks", [])
	if not books.is_empty():
		v.add_child(Ui.lbl("REUSABLE PLAYBOOKS", Ui.FS_SMALL - 3, Ui.ACCENT, true))
		for book in books.slice(0, 5):
			var playbook_item := VBoxContainer.new()
			playbook_item.add_theme_constant_override("separation", 2)
			playbook_item.add_child(Ui.lbl(str(book.get("title", "Playbook")), Ui.FS_SMALL, Ui.TEXT, true, true))
			var trigger := str(book.get("trigger", ""))
			playbook_item.add_child(Ui.lbl(("Use when: " + trigger + "\n" if trigger != "" else "") + str(book.get("steps", "")).left(360), Ui.FS_SMALL - 2, Ui.MUTED, false, true))
			v.add_child(playbook_item)
	var articles: Array = _flow.get("knowledge", [])
	if articles.is_empty():
		v.add_child(Ui.lbl("Save architecture notes, research findings, decisions and reusable instructions here. Aoi can search these notes when working on this project.", Ui.FS_SMALL, Ui.MUTED, false, true))
	else:
		for article in articles.slice(0, 8):
			var item := VBoxContainer.new()
			item.add_theme_constant_override("separation", 3)
			item.add_child(Ui.lbl(str(article.get("title", "Knowledge note")), Ui.FS_SMALL, Ui.TEXT, true, true))
			item.add_child(Ui.lbl(str(article.get("content", "")).left(320), Ui.FS_SMALL - 2, Ui.MUTED, false, true))
			v.add_child(item)
	return card


func _add_knowledge() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Add project knowledge"
	dialog.dialog_text = "Save a note that future project work should retrieve."
	var fields := VBoxContainer.new()
	var title := LineEdit.new(); title.placeholder_text = "Title"
	var body := TextEdit.new(); body.placeholder_text = "Architecture, constraints, research, decisions…"; body.custom_minimum_size = Vector2(0, 180)
	fields.add_child(title); fields.add_child(body); dialog.add_child(fields)
	dialog.confirmed.connect(func():
		if AgentFlow.add_knowledge(_project_id, title.text, body.text): _reload()
		else: toast.emit("Add a title and some knowledge first."))
	add_child(dialog); dialog.popup_centered(Vector2i(590, 390))

func _add_playbook() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Add reusable playbook / SOP"
	dialog.dialog_text = "Capture a repeatable procedure for future project tasks."
	var fields := VBoxContainer.new()
	var title := LineEdit.new(); title.placeholder_text = "Playbook title"
	var trigger := LineEdit.new(); trigger.placeholder_text = "Use when… (optional)"
	var steps := TextEdit.new(); steps.placeholder_text = "1. First step\n2. Second step\n3. Verification"; steps.custom_minimum_size = Vector2(0, 180)
	fields.add_child(title); fields.add_child(trigger); fields.add_child(steps); dialog.add_child(fields)
	dialog.confirmed.connect(func():
		if AgentFlow.add_playbook(_project_id, title.text, trigger.text, steps.text): _reload()
		else: toast.emit("Add a title and procedure steps first."))
	add_child(dialog); dialog.popup_centered(Vector2i(590, 430))


func _capture_decision() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Capture project decision"
	dialog.dialog_text = "Record a decision that future agents should respect."
	var edit := LineEdit.new()
	edit.placeholder_text = "What did we decide?"
	edit.custom_minimum_size = Vector2(480, 58)
	dialog.add_child(edit)
	dialog.confirmed.connect(func():
		if edit.text.strip_edges() != "": AgentFlow.add_decision(_project_id, edit.text))
	add_child(dialog)
	dialog.popup_centered(Vector2i(560, 220))

func _decisions_card() -> Control:
	var card := Ui.card(18)
	var v := Ui.card_body(card)
	v.add_child(Ui.lbl("Project memory & decisions", Ui.FS, Ui.TEXT, true))
	var decisions: Array = _flow.get("decisions", [])
	if decisions.is_empty(): v.add_child(Ui.lbl("No decisions captured yet. Record choices, constraints and accepted trade-offs so future work follows them.", Ui.FS_SMALL, Ui.MUTED, false, true))
	for decision in decisions.slice(0, 12):
		v.add_child(Ui.lbl("• " + str(decision.get("text", "")), Ui.FS_SMALL, Ui.TEXT, false, true))
	return card

func _activity_card() -> Control:
	var card := Ui.card(18)
	var v := Ui.card_body(card)
	v.add_child(Ui.lbl("Activity & tool audit", Ui.FS, Ui.TEXT, true))
	var events: Array = _flow.get("activity", [])
	if events.is_empty(): v.add_child(Ui.lbl("Workflow activity will be recorded here.", Ui.FS_SMALL, Ui.MUTED, false, true))
	for event in events.slice(0, 10):
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		row.add_child(Ui.lbl(str(event.get("actor", "Aoi")) + "  ·  " + str(event.get("action", "Activity")), Ui.FS_SMALL, Ui.TEXT, true))
		row.add_child(Ui.lbl(str(event.get("detail", "")), Ui.FS_SMALL - 2, Ui.MUTED, false, true))
		v.add_child(row)
	return card
