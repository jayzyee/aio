extends Control
## App shell: chat, projects, Explore and settings, with an animated navigation drawer and phone-safe layout.
const Ui = preload("res://scripts/ui/Ui.gd")
const Md = preload("res://scripts/core/Md.gd")
const Catalog = preload("res://scripts/core/Catalog.gd")
const MG = preload("res://scripts/core/ModelGroups.gd")
const ChatScreen = preload("res://scripts/ui/ChatScreen.gd")
const SetupScreen = preload("res://scripts/ui/SetupScreen.gd")
const ProjectsScreen = preload("res://scripts/ui/ProjectsScreen.gd")
const ToolsScreen = preload("res://scripts/ui/ToolsScreen.gd")
const WorkflowScreen = preload("res://scripts/ui/WorkflowScreen.gd")
const KnowledgeScreen = preload("res://scripts/ui/KnowledgeScreen.gd")
const StudioScreen = preload("res://scripts/ui/StudioScreen.gd")
const Sheet = preload("res://scripts/ui/Sheet.gd")

var chat: VBoxContainer
var setup: ScrollContainer
var projects: VBoxContainer
var explore: ToolsScreen
var workflow: ScrollContainer
var knowledge: VBoxContainer
var studio: VBoxContainer
var tab := "chat"

var _frame: MarginContainer
var _title: Label
var _search_btn: Button
var _menu_btn: Button
var _new_chat_btn: Button
var _more_btn: Button
var _header_menu: PopupMenu
var _stack: Control
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _kb_last := -1.0
var _last_applied_frame_margins := Vector4i(-1, -1, -1, -1)
var _chat_follow_bottom_before_ime := true
var _drawer: Control


func _on_node_added(n: Node) -> void:
	# Phone scrolling: controls that STOP the mouse swallow finger drags. Panels, rich text and bars must let
	# drags through to the ScrollContainer (the sheet backdrop and root keep STOP via meta).
	if (n is PanelContainer or n is RichTextLabel or n is ProgressBar or n is Button) and not n.has_meta("keep_stop"):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	theme = Ui.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Ui.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_frame = MarginContainer.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	get_viewport().size_changed.connect(_apply_display_safe_area)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_frame.add_child(col)
	col.add_child(_top_bar())
	_stack = Control.new()
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.clip_contents = true
	col.add_child(_stack)
	chat = ChatScreen.new()
	setup = SetupScreen.new()
	projects = ProjectsScreen.new()
	explore = ToolsScreen.new()
	workflow = WorkflowScreen.new()
	knowledge = KnowledgeScreen.new()
	studio = StudioScreen.new()
	for s in [chat, setup, projects, explore, workflow, knowledge, studio]:
		s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_stack.add_child(s)
	_build_toast()
	_wire()
	_build_header_menu()
	_seed_demo_if_requested()
	go(OS.get_environment("AOI_MOBILE_TAB") if OS.get_environment("AOI_MOBILE_TAB") != "" else "chat")
	_refresh_models_silently()
	call_deferred("_apply_display_safe_area")
	match OS.get_environment("AOI_MOBILE_SHEET"):
		"models": open_models.call_deferred()
		"sessions": open_sessions.call_deferred()
		"save": open_project_picker.call_deferred("- [ ] Example task\n\nSome plan text.")


# ------------------------------------------------------------------ chrome
func _top_bar() -> Control:
	# The chat surface follows the supplied phone reference: two floating control
	# groups, no persistent title bar and no decorative navigation rail.
	var host := Control.new()
	host.name = "FloatingHeader"
	host.custom_minimum_size.y = 120
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 28)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	host.add_child(margin)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	_menu_btn = Ui.icon_btn("menu", "quiet", 60)
	_menu_btn.tooltip_text = "Open navigation"
	_menu_btn.add_theme_constant_override("icon_max_width", 34)
	_menu_btn.pressed.connect(open_navigation_drawer)
	row.add_child(_menu_btn)

	_title = Ui.lbl("", 25, Ui.TEXT, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_title)

	var action_pill := PanelContainer.new()
	action_pill.name = "HeaderActionsPill"
	action_pill.add_theme_stylebox_override("panel", Ui.box(Color(0, 0, 0, 0), 0))
	var action_margin := MarginContainer.new()
	for side in ["left", "right"]: action_margin.add_theme_constant_override("margin_" + side, 8)
	for side in ["top", "bottom"]: action_margin.add_theme_constant_override("margin_" + side, 6)
	action_pill.add_child(action_margin)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 2)
	action_margin.add_child(actions)
	_new_chat_btn = Ui.icon_btn("compose", "quiet", 60)
	_new_chat_btn.tooltip_text = "New chat"
	_new_chat_btn.add_theme_constant_override("icon_max_width", 36)
	_new_chat_btn.pressed.connect(_new_current_chat)
	actions.add_child(_new_chat_btn)
	_more_btn = Ui.icon_btn("more_vertical", "quiet", 60)
	_more_btn.tooltip_text = "More options"
	_more_btn.add_theme_constant_override("icon_max_width", 34)
	_more_btn.pressed.connect(_open_header_menu)
	actions.add_child(_more_btn)
	row.add_child(action_pill)
	return host


func _build_header_menu() -> void:
	_header_menu = PopupMenu.new()
	_header_menu.add_item("Find a chat", 0)
	_header_menu.add_item("Copy conversation", 1)
	_header_menu.add_item("AI model", 2)
	_header_menu.add_separator()
	_header_menu.add_item("Projects", 3)
	_header_menu.add_item("Library", 4)
	_header_menu.add_item("Connections", 5)
	_header_menu.add_item("Preferences", 6)
	Ui.style_popup_menu(_header_menu)
	_header_menu.id_pressed.connect(_on_header_menu_pressed)
	add_child(_header_menu)


func _on_header_menu_pressed(id: int) -> void:
	match id:
		0: open_sessions.call_deferred()
		1: _copy_current_conversation()
		2: open_models.call_deferred()
		3: go("projects")
		4: go("knowledge")
		5: go("explore")
		6: go("setup")


func _open_header_menu() -> void:
	if _header_menu == null: return
	_header_menu.set_item_disabled(_header_menu.get_item_index(1), _conversation_transcript().is_empty())
	_header_menu.position = Vector2(maxf(12.0, size.x - 340.0), 140.0)
	_header_menu.popup()


func _copy_current_conversation() -> void:
	var transcript := _conversation_transcript()
	if transcript == "":
		toast("This chat has no messages to copy.")
		return
	DisplayServer.clipboard_set(transcript)
	toast("Conversation copied")


func _conversation_transcript() -> String:
	var messages: Variant = chat.session.get("messages", [])
	if not messages is Array: return ""
	var blocks: Array[String] = []
	for message in messages:
		if not message is Dictionary or bool(message.get("internal", false)): continue
		var role := str(message.get("role", ""))
		if role not in ["user", "assistant"]: continue
		var content := str(message.get("content", "")).strip_edges()
		if content == "":
			if bool(message.get("project_card", false)):
				var artifact_project := Store.get_project(str(message.get("project_id", "")))
				content = "[Project artifact: %s]" % str(artifact_project.get("title", "project"))
			elif str(message.get("image_path", "")) != "":
				content = "[Generated image attached]"
			elif str(message.get("video_path", "")) != "":
				content = "[Generated video attached]"
			else:
				continue
		blocks.append(("You" if role == "user" else "Aoi") + "\n" + content)
	return "\n\n---\n\n".join(blocks)


func _apply_display_safe_area() -> void:
	if _frame == null or not is_instance_valid(_frame): return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0: return
	var left := 0.0
	var top := 0.0
	var right := 0.0
	var bottom := 0.0
	# Review captures can emulate the Android status/navigation bars exactly.
	# These variables are ignored in the shipped app unless a test explicitly sets them.
	var review_top := OS.get_environment("AOI_REVIEW_SAFE_TOP")
	var review_bottom := OS.get_environment("AOI_REVIEW_SAFE_BOTTOM")
	if review_top != "" or review_bottom != "":
		top = float(review_top) if review_top != "" else 0.0
		bottom = float(review_bottom) if review_bottom != "" else 0.0
	else:
		var physical_size := Vector2(DisplayServer.screen_get_size())
		var safe_rect: Rect2i = DisplayServer.get_display_safe_area()
		if physical_size.x > 0.0 and physical_size.y > 0.0 and safe_rect.size.x > 0 and safe_rect.size.y > 0:
			var scale_x := viewport_size.x / physical_size.x
			var scale_y := viewport_size.y / physical_size.y
			left = maxf(0.0, float(safe_rect.position.x) * scale_x)
			top = maxf(0.0, float(safe_rect.position.y) * scale_y)
			right = maxf(0.0, float(physical_size.x - safe_rect.end.x) * scale_x)
			bottom = maxf(0.0, float(physical_size.y - safe_rect.end.y) * scale_y)
	_frame.offset_left = left
	_frame.offset_top = top
	_frame.offset_right = -right
	_frame.offset_bottom = -bottom

func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", Ui.pad(Ui.box(Ui.SURFACE, 26, Ui.BORDER, 1), 30, 16))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.z_index = 200
	_toast.modulate.a = 0.0
	_toast_label = Ui.lbl("", Ui.FS_SMALL + 2, Ui.TEXT)
	_toast.add_child(_toast_label)
	add_child(_toast)


func toast(text: String) -> void:
	_toast_label.text = text
	_toast.reset_size()
	_toast.position = Vector2((size.x - _toast.size.x) / 2.0, size.y - 260.0)
	if _toast_tween != null: _toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.5)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3)


func _wire() -> void:
	chat.request_setup.connect(func(): go("setup"))
	chat.request_models.connect(open_models)
	chat.request_save_to_project.connect(open_project_picker)
	chat.request_save_to_library.connect(func(markdown: String): go("knowledge"); knowledge.add_from_chat(markdown))
	knowledge.toast.connect(toast)
	chat.request_open_project.connect(func(id: String): go("projects"); projects.open_project(id))
	chat.session_changed.connect(_update_chrome)
	chat.flow_plan_received.connect(func(id: String): workflow.open_project(id); go("workflow"))
	chat.assistant_answer_finished.connect(_workflow_answer_finished)
	chat.assistant_answer_failed.connect(_workflow_answer_failed)
	chat.toast.connect(toast)
	chat.request_select_text.connect(open_select_text)
	chat.request_tools.connect(func(): go("explore"))
	chat.request_new_project.connect(func(): go("projects"); projects._new_project("", ""))
	explore.request_setup.connect(func(): go("setup"))
	explore.request_linux_config.connect(_configure_linux)
	workflow.plan_requested.connect(_plan_workflow)
	workflow.run_task_requested.connect(_run_workflow_task)
	workflow.open_task_chat_requested.connect(_open_workflow_task_chat)
	workflow.toast.connect(toast)
	projects.request_open_flow.connect(func(id: String): workflow.open_project(id); go("workflow"))
	explore.request_github_connect.connect(_configure_github)
	explore.request_huggingface_connect.connect(_configure_huggingface)
	explore.request_piston_config.connect(_configure_piston)
	explore.toast.connect(toast)
	setup.changed.connect(func(): _update_chrome(); if (chat.session.get("messages", []) as Array).is_empty(): chat._render())
	setup.request_godot_api.connect(func():
		go("studio")
		studio._show_api_explorer.call_deferred())
	setup.request_models.connect(open_models)
	setup.request_open_library.connect(func(): knowledge.show_global_references(); go("knowledge"))
	setup.request_wipe.connect(func(): confirm("Delete everything?", "This removes your key, chats and projects from this phone. It cannot be undone.", "Delete", _wipe))
	projects.plan_with_aoi.connect(_plan_with_aoi)
	projects.chat_about.connect(_continue_project_chat)
	projects.toast_requested.connect(toast)
	projects.request_delete.connect(func(id: String): confirm("Delete this project?", "Its tasks and notes will be removed.", "Delete", func(): Store.delete_project(id); projects.show_list()))
	studio.toast.connect(toast)
	studio.request_linux_setup.connect(_configure_linux)
	studio.embedded_chat.request_setup.connect(func(): go("setup"))
	studio.embedded_chat.request_models.connect(open_models)
	studio.embedded_chat.request_save_to_project.connect(open_project_picker)
	studio.embedded_chat.request_save_to_library.connect(func(markdown: String): go("knowledge"); knowledge.add_from_chat(markdown))
	studio.embedded_chat.request_open_project.connect(func(id: String): go("projects"); projects.open_project(id))
	studio.embedded_chat.request_select_text.connect(open_select_text)
	studio.embedded_chat.request_tools.connect(func(): go("explore"))
	studio.embedded_chat.request_new_project.connect(func(): go("projects"); projects._new_project("", ""))
	studio.embedded_chat.session_changed.connect(_update_chrome)
	studio.embedded_chat.flow_plan_received.connect(func(id: String): workflow.open_project(id); go("workflow"))
	studio.embedded_chat.assistant_answer_finished.connect(_workflow_answer_finished)
	studio.embedded_chat.assistant_answer_failed.connect(_workflow_answer_failed)
	studio.embedded_chat.toast.connect(toast)
	LLM.models_loaded.connect(func(_pid, ok, _p): if ok: _update_chrome())


func go(name: String) -> void:
	tab = name
	chat.visible = name == "chat"
	setup.visible = name == "setup"
	projects.visible = name == "projects"
	explore.visible = name == "explore"
	workflow.visible = name == "workflow"
	knowledge.visible = name == "knowledge"
	studio.visible = name == "studio"
	if name == "studio": studio.activate()
	if name == "setup": setup.render()
	if name == "projects": projects.render()
	if name == "explore": explore.render()
	if name == "knowledge": knowledge._render_results()
	_update_chrome()


func _new_current_chat() -> void:
	if tab == "studio":
		studio.new_chat()
	else:
		chat.new_session()
		go("chat")


func _update_chrome() -> void:
	# Chat has no title text: the two floating pills frame the conversation.
	# Secondary destinations retain a small title between the same controls.
	match tab:
		"chat": _title.text = ""
		"projects": _title.text = "Projects"
		"knowledge": _title.text = "Library"
		"studio": _title.text = "Workbench"
		"explore": _title.text = "Connections"
		"workflow": _title.text = "Workbench"
		"setup": _title.text = "Preferences"
		_: _title.text = "Aoi"
	_new_chat_btn.visible = tab in ["chat", "studio"]
	_more_btn.visible = tab == "chat"
	_menu_btn.visible = true

# ----------------------------------------------------------- navigation drawer
func open_navigation_drawer() -> void:
	if _drawer != null and is_instance_valid(_drawer): return
	var width := minf(size.x * 0.84, 560.0)
	var overlay := Control.new()
	overlay.name = "NavigationDrawer"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 180
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_drawer = overlay
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.06, 0.08, 0.34)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.modulate.a = 0.0
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed: _close_navigation_drawer()
		elif event is InputEventScreenTouch and event.pressed: _close_navigation_drawer())
	overlay.add_child(shade)
	var panel := PanelContainer.new()
	panel.name = "DrawerPanel"
	panel.set_meta("keep_stop", true)
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -width
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	var panel_style := Ui.box(Ui.SURFACE, 0)
	panel_style.border_width_right = 1
	panel_style.border_color = Ui.BORDER
	panel.add_theme_stylebox_override("panel", panel_style)
	overlay.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 22)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)
	var drawer_scroll := ScrollContainer.new()
	drawer_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drawer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(drawer_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	drawer_scroll.add_child(column)
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 12)
	column.add_child(brand)
	var brand_title := Ui.lbl("Aoi", 30, Ui.TEXT, true)
	brand_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_child(brand_title)
	var close := Ui.icon_btn("close", "quiet", 52)
	close.pressed.connect(_close_navigation_drawer)
	brand.add_child(close)
	var rule := ColorRect.new()
	rule.color = Ui.BORDER
	rule.custom_minimum_size.y = 1
	column.add_child(rule)

	# One flat destination list, like the supplied ChatGPT drawer reference.
	# New chat and global search remain in the conversation header, so the
	# drawer does not duplicate those primary actions.
	column.add_child(_drawer_nav_item("Projects", "", "folder", "projects"))
	column.add_child(_drawer_nav_item("Library", "", "notebook", "knowledge"))
	column.add_child(_drawer_nav_item("Workbench", "", "code", "studio"))
	column.add_child(_drawer_nav_item("Connections", "", "layers", "explore"))
	column.add_child(_drawer_nav_item("Settings", "", "settings", "setup"))

	var section_rule := ColorRect.new()
	section_rule.color = Ui.BORDER
	section_rule.custom_minimum_size.y = 1
	column.add_child(section_rule)
	var recent_head := HBoxContainer.new()
	var sessions := Store.list_sessions()
	var recent_title := Ui.lbl("Chats", 20, Ui.TEXT, true)
	recent_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recent_head.add_child(recent_title)
	if sessions.size() > 6:
		var see_all := Ui.btn("See all", "quiet")
		see_all.custom_minimum_size = Vector2(94, 42)
		see_all.pressed.connect(func(): _close_navigation_drawer(); open_sessions())
		recent_head.add_child(see_all)
	column.add_child(recent_head)
	var session_list := VBoxContainer.new()
	session_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_list.add_theme_constant_override("separation", 2)
	column.add_child(session_list)
	_render_drawer_sessions(session_list, "")

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(shade, "modulate:a", 1.0, 0.18)
	tween.tween_property(panel, "offset_left", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "offset_right", width, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _drawer_section(text: String) -> Control:
	var label := Ui.lbl(text, 13, Ui.MUTED, true)
	label.add_theme_color_override("font_color", Color("#81899a"))
	label.custom_minimum_size.y = 26
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return label


func _drawer_nav_item(title: String, subtitle: String, icon_name: String, target: String) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size.y = 58
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var active := tab == target or (target == "studio" and tab == "workflow")
	button.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Color("#f1f1f1") if active else Color(0, 0, 0, 0), 13), 10, 5))
	button.add_theme_stylebox_override("focus", Ui.pad(Ui.box(Color("#f1f1f1"), 13, Ui.ACCENT, 1), 10, 5))
	button.add_theme_stylebox_override("hover", Ui.pad(Ui.box(Color("#f6f6f6"), 13), 10, 5))
	button.add_theme_stylebox_override("pressed", Ui.pad(Ui.box(Color("#ededed"), 13), 10, 5))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glyph := TextureRect.new()
	glyph.texture = Ui.icon(icon_name)
	glyph.custom_minimum_size = Vector2(25, 25)
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.modulate = Ui.TEXT if active else Ui.MUTED
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(glyph)
	var label := Ui.lbl(title, 20, Ui.TEXT if active else Ui.TEXT, active)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	button.add_child(row)
	button.pressed.connect(func(): _close_navigation_drawer(); go(target))
	return button


func _render_drawer_sessions(container: VBoxContainer, query: String) -> void:
	for child in container.get_children(): child.queue_free()
	var normalized := query.strip_edges().to_lower()
	var shown := 0
	for session_data in Store.list_sessions():
		var title := str(session_data.get("title", "New chat"))
		if normalized != "" and not title.to_lower().contains(normalized): continue
		if shown >= 6: break
		shown += 1
		var button := Ui.btn("", "quiet")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 66
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var copy := VBoxContainer.new()
		copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		copy.offset_left = 18
		copy.offset_right = -14
		copy.alignment = BoxContainer.ALIGNMENT_CENTER
		var title_row := HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 6)
		copy.add_child(title_row)
		var label := Ui.lbl(title, 19, Ui.TEXT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_row.add_child(label)
		var pinned := bool(session_data.get("pinned", false))
		if pinned:
			var pin_glyph := TextureRect.new()
			pin_glyph.texture = Ui.icon("pin")
			pin_glyph.custom_minimum_size = Vector2(18, 18)
			pin_glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pin_glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pin_glyph.modulate = Ui.MUTED
			pin_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			title_row.add_child(pin_glyph)
		var detail_text := "Pinned · " if pinned else ""
		detail_text += Ui.relative_time(float(session_data.get("updated", 0)))
		var detail := Ui.lbl(detail_text, 15, Ui.MUTED)
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.add_child(detail)
		button.add_child(copy)
		var session_id := str(session_data.get("id", ""))
		button.pressed.connect(func(): _close_navigation_drawer(); chat.open_session(session_id); go("chat"))
		container.add_child(button)
	if shown == 0:
		container.add_child(Ui.lbl("Your conversations will appear here.", 17, Ui.MUTED, false, true))


func _close_navigation_drawer() -> void:
	if _drawer != null and is_instance_valid(_drawer):
		_drawer.queue_free()
	_drawer = null


func _configure_github() -> void:
	var sh := _sheet("Manage GitHub" if Store.has_secret("github") else "Connect GitHub")
	var tools: ToolsScreen = explore
	sh.body.add_child(Ui.lbl("GitHub uses a Personal Access Token (PAT), not your GitHub password or a separate paid API key. Aoi verifies the token against GitHub before saving it. Public repository search can also work without a token, but private repositories and higher authenticated limits need one.", Ui.FS_SMALL + 1, Ui.TEXT, false, true))
	sh.body.add_child(Ui.lbl("Create a fine-grained token", Ui.FS, Ui.TEXT, true))
	var steps := "1. Open GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens.\n2. Create a token for your GitHub account and select only the repositories Aoi should use.\n3. Set these repository permissions:\n   • Codespaces — Read and write (create and use cloud workspaces)\n   • Codespaces metadata — Read (choose a compatible Linux machine)\n   • Metadata — Read-only (private repository browsing)\n   • Contents — Read-only for private repository browsing; use Read and write only when Aoi must edit repository files.\n4. Optional: Codespaces lifecycle admin — Read and write lets Aoi start a stopped workspace. Without it, start the workspace in GitHub first.\n5. Generate the token, copy it once and paste it below. Aoi verifies it before saving. Public repository browsing does not need a token."
	sh.body.add_child(Ui.lbl(steps, Ui.FS_SMALL, Ui.MUTED, false, true))
	var link := Ui.btn("Open GitHub fine-grained token settings", "ghost", "forward")
	link.pressed.connect(func(): OS.shell_open("https://github.com/settings/personal-access-tokens/new"))
	sh.body.add_child(link)
	var existing_account := str(Store.get_integration("github").get("login", ""))
	var verified_account := ToolRunner.is_github_connected()
	var initial_status := "Your saved token stays unchanged unless GitHub verifies the replacement."
	if verified_account and existing_account != "":
		initial_status = "Currently connected as @%s. Paste a replacement token to update this connection." % existing_account
	elif Store.has_secret("github"):
		initial_status = "A token is saved from an earlier version, but this account has not been verified yet. Paste it below to verify without losing the saved token."
	var feedback := Ui.lbl(initial_status, Ui.FS_SMALL, Ui.MUTED, false, true)
	feedback.name = "GitHubConnectionStatus"
	sh.body.add_child(feedback)
	var token := Ui.line("Paste a replacement GitHub token" if Store.has_secret("github") else "Paste GitHub fine-grained token", true)
	sh.body.add_child(token)
	var save := Ui.btn("Verify and connect", "primary", "check")
	save.disabled = token.text.strip_edges().is_empty()
	token.text_changed.connect(func(value: String): save.disabled = value.strip_edges().is_empty())
	var result_handler := func(success: bool, account: String, message: String) -> void:
		if not is_instance_valid(sh): return
		feedback.text = message
		save.disabled = false
		save.text = ("Connected · @" + account) if success else "Verify and connect"
		if success:
			feedback.text += "\nRepository tools are authenticated. Every remote write still requires its own approval."
	tools.github_connection_finished.connect(result_handler)
	sh.closed.connect(func():
		if tools.github_connection_finished.is_connected(result_handler):
			tools.github_connection_finished.disconnect(result_handler)
	)
	save.pressed.connect(func():
		if token.text.strip_edges() == "":
			feedback.text = "Paste a token first. Your current connection has not been changed."
			return
		save.disabled = true
		save.text = "Verifying…"
		feedback.text = "Contacting GitHub and checking the token…"
		tools.connect_github(token.text)
	)
	sh.body.add_child(save)
	if Store.has_secret("github"):
		var disconnect := Ui.btn("Disconnect GitHub", "danger", "trash")
		disconnect.pressed.connect(func():
			tools._disconnect_github()
			sh.close()
		)
		sh.body.add_child(disconnect)
	sh.body.add_child(Ui.lbl("Aoi stores the token in its encrypted local key file. Use the smallest permission set that supports your work. GitHub branch, file, issue and pull-request changes remain separately approval-gated; ordinary edits inside your active local project do not require a GitHub token.", Ui.FS_SMALL - 1, Ui.MUTED, false, true))


func _configure_huggingface() -> void:
	var sh := _sheet("Manage AI media generation" if Store.has_secret("huggingface") else "Connect AI media generation")
	sh.body.add_child(Ui.lbl("Aoi can generate images and short videos directly from chat, then save the files on this phone. Create a fine-grained token and enable the Inference Providers permission. Video generation uses the Fal AI Wan 2.2 route. Provider credits, billing, model availability and queue times vary; generation is not guaranteed to be free.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
	var link := Ui.btn("Create a Hugging Face token", "ghost", "forward")
	link.pressed.connect(func(): OS.shell_open("https://huggingface.co/settings/tokens/new?tokenType=fineGrained"))
	sh.body.add_child(link)
	var token := Ui.line("Paste a new token to replace the current one" if Store.has_secret("huggingface") else "Paste Hugging Face token", true)
	sh.body.add_child(token)
	var save := Ui.btn("Verify and connect", "primary", "check")
	save.pressed.connect(func():
		if token.text.strip_edges() == "":
			toast("Paste a token first.")
			return
		explore.connect_huggingface(token.text)
		sh.close())
	sh.body.add_child(save)
	if Store.has_secret("huggingface"):
		var disconnect := Ui.btn("Disconnect Hugging Face", "danger", "trash")
		disconnect.pressed.connect(func():
			explore._disconnect_huggingface()
			sh.close())
		sh.body.add_child(disconnect)
	sh.body.add_child(Ui.lbl("Aoi stores the token in its encrypted local key file. The token is sent to Hugging Face when you request image or video generation. Do not paste a token with repository write permissions; Aoi only needs the Inference Providers permission.", 18, Ui.MUTED, false, true))


func _configure_piston() -> void:
	var sh := _sheet("Configure code runner")
	sh.body.add_child(Ui.lbl("Connect a Piston API server that you own or are authorised to use. Aoi sends your code to that server's runtime and returns its output. Use HTTPS for remote servers; plain HTTP is suitable only for a trusted local development network. The public hosted Piston API is not generally available for new free users.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
	var url := Ui.line("Server base URL · https://runner.example.com")
	url.text = str(Store.get_integration("piston").get("url", ""))
	sh.body.add_child(url)
	var token := Ui.line("Optional bearer token", true)
	token.text = Store.get_secret("piston")
	sh.body.add_child(token)
	var link := Ui.btn("Piston setup guide", "quiet", "forward")
	link.pressed.connect(func(): OS.shell_open("https://github.com/engineer-man/piston"))
	sh.body.add_child(link)
	var save := Ui.btn("Save runner", "primary", "check")
	save.pressed.connect(func():
		var clean_url := url.text.strip_edges().trim_suffix("/")
		if not ToolRunner._is_valid_http_base(clean_url):
			toast("Enter a valid http(s) base URL without credentials, query parameters or a fragment.")
			return
		Store.set_integration("piston", {"url": clean_url})
		Store.set_secret("piston", token.text)
		sh.close()
		explore.render()
		toast("Code runner configured. Test it before using AI tool calls."))
	sh.body.add_child(save)
	var remove := Ui.btn("Disconnect runner", "danger", "trash")
	remove.pressed.connect(func():
		Store.integrations.erase("piston")
		Store.remove_secret("piston")
		Store.save_settings()
		sh.close()
		explore.render()
		toast("Runner disconnected"))
	if str(Store.get_integration("piston").get("url", "")) != "": sh.body.add_child(remove)


func _configure_linux() -> void:
	var sh := _sheet("Connect a cloud Linux workspace")
	sh.body.add_child(Ui.lbl("Aoi's build machine runs in GitHub's cloud—not on your phone or personal computer. It can build Godot projects and return the real files, logs and screenshots.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
	var repository := Ui.line("GitHub repository · owner/name", false)
	var codespace_settings := Store.get_integration("github_codespaces")
	repository.text = str(codespace_settings.get("repository", ""))
	var open_codespaces := Ui.btn("Open GitHub Codespaces", "ghost", "external_link")
	open_codespaces.pressed.connect(func():
		var selected_repository := ToolRunner._normalize_repository(repository.text)
		var destination := "https://github.com/codespaces" if selected_repository == "" else "https://github.com/%s/settings/codespaces" % selected_repository
		OS.shell_open(destination))
	sh.body.add_child(open_codespaces)

	sh.body.add_child(Ui.lbl("Create or reconnect a workspace", Ui.FS_SMALL, Ui.TEXT, true))
	sh.body.add_child(Ui.lbl("Connect GitHub first. The token needs Codespaces = Read and write and Codespaces metadata = Read. Add Codespaces lifecycle admin = Read and write only if you want Aoi to restart stopped workspaces.", Ui.FS_SMALL, Ui.MUTED, false, true))
	sh.body.add_child(Ui.lbl("Generate the cloud key below and add the same value to your repository's Settings → Secrets and variables → Codespaces as AOI_BRIDGE_TOKEN. GitHub's free compute and storage are limited; Aoi selects the smallest eligible machine and applies a 30-minute idle timeout. Stop the workspace when finished.", Ui.FS_SMALL - 1, Ui.MUTED, false, true))
	sh.body.add_child(repository)
	var branch := Ui.line("Branch · leave blank for the repository default", false)
	branch.text = str(codespace_settings.get("ref", ""))
	sh.body.add_child(branch)
	var codespace_select := OptionButton.new()
	codespace_select.custom_minimum_size = Vector2(0, 54)
	codespace_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	codespace_select.focus_mode = Control.FOCUS_ALL
	codespace_select.add_theme_font_size_override("font_size", Ui.FS_SMALL)
	codespace_select.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Ui.CARD, 12, Ui.BORDER, 1), 13, 7))
	codespace_select.add_theme_stylebox_override("hover", Ui.pad(Ui.box(Ui.CARD_HI, 12, Ui.BORDER, 1), 13, 7))
	codespace_select.add_theme_stylebox_override("pressed", Ui.pad(Ui.box(Ui.CARD_HI, 12, Ui.BORDER, 1), 13, 7))
	codespace_select.add_theme_color_override("font_color", Ui.TEXT)
	codespace_select.add_theme_color_override("font_hover_color", Ui.TEXT)
	codespace_select.add_theme_color_override("font_pressed_color", Ui.TEXT)
	sh.body.add_child(codespace_select)
	var populate_codespaces := func(items: Array) -> void:
		codespace_select.clear()
		codespace_select.add_item("Choose an existing Codespace")
		codespace_select.set_item_metadata(0, {})
		for item in items:
			if not item is Dictionary: continue
			var name := str(item.get("name", ""))
			if name == "": continue
			var repo_name := str(item.get("repository", "Repository unavailable"))
			var state := str(item.get("state", "Unknown"))
			codespace_select.add_item("%s · %s · %s" % [repo_name, state, name])
			codespace_select.set_item_metadata(codespace_select.item_count - 1, item.duplicate(true))
		var last_created: Variant = Store.get_integration("github_codespaces").get("last_created", {})
		if last_created is Dictionary and str(last_created.get("name", "")) != "":
			var already_added := false
			for index in range(codespace_select.item_count):
				var item_data: Variant = codespace_select.get_item_metadata(index)
				if item_data is Dictionary and str(item_data.get("name", "")) == str(last_created.get("name", "")):
					already_added = true
					break
			if not already_added:
				codespace_select.add_item("%s · %s · %s" % [str(last_created.get("repository", "Repository")), str(last_created.get("state", "Unknown")), str(last_created.get("name", ""))])
				codespace_select.set_item_metadata(codespace_select.item_count - 1, last_created.duplicate(true))
		codespace_select.select(0)
	var cached_codespaces: Variant = Store.get_integration("github_codespaces").get("items", [])
	populate_codespaces.call(cached_codespaces if cached_codespaces is Array else [])

	var feedback := Ui.lbl("Connect GitHub and save the cloud key before creating a workspace.", Ui.FS_SMALL, Ui.MUTED, false, true)
	feedback.name = "CloudLinuxConnectionFeedback"
	sh.body.add_child(feedback)
	var open_workspace_url := str(Store.get_integration("linux_bridge").get("codespace_web_url", ""))
	var token := Ui.line("Cloud connection key", true)
	token.text = Store.get_secret("linux_bridge")
	var url := Ui.line("Secure workspace URL (HTTPS)", false)
	url.placeholder_text = "https://codespace-name-8765.app.github.dev"
	url.text = str(Store.get_integration("linux_bridge").get("url", ""))
	var codespace_create_in_flight := false
	var codespace_use_in_flight := false
	var codespace_list_in_flight := false
	var create_codespace := Ui.btn("Create GitHub Codespace", "primary", "terminal")
	var creation_uncertain: Variant = Store.get_integration("github_codespaces").get("creation_uncertain", {})
	var sync_codespace_create := func() -> void:
		var pending: Variant = Store.get_integration("github_codespaces").get("creation_uncertain", {})
		var bridge_key := token.text.strip_edges()
		var repository_valid := ToolRunner._normalize_repository(repository.text) != ""
		var key_valid := bridge_key.length() == 64 and bridge_key.is_valid_hex_number(false)
		create_codespace.disabled = codespace_create_in_flight or not ToolRunner.is_github_connected() or not repository_valid or not key_valid or (pending is Dictionary and not pending.is_empty())
	create_codespace.disabled = not ToolRunner.is_github_connected() or (creation_uncertain is Dictionary and not creation_uncertain.is_empty())
	repository.text_changed.connect(func(_value: String): sync_codespace_create.call())
	token.text_changed.connect(func(_value: String): sync_codespace_create.call())
	sync_codespace_create.call()
	if creation_uncertain is Dictionary and not creation_uncertain.is_empty():
		feedback.text = "A previous creation request had no confirmed response. Refresh existing Codespaces before trying again to avoid a duplicate workspace."
	create_codespace.pressed.connect(func():
		var repo_value := repository.text.strip_edges()
		if repo_value == "":
			feedback.text = "Enter the GitHub repository that contains this Aoi project's .devcontainer folder."
			return
		if not ToolRunner.is_github_connected():
			feedback.text = "Connect and verify GitHub first. The token needs Codespaces = Read and write plus Codespaces metadata = Read. Add Codespaces lifecycle admin = Read and write to let Aoi start stopped workspaces."
			return
		var key_value := token.text.strip_edges()
		if key_value.length() != 64 or not key_value.is_valid_hex_number(false):
			feedback.text = "Generate or enter the 64-character cloud key, then add the same value to the repository's AOI_BRIDGE_TOKEN Codespaces secret."
			return
		Store.set_secret("linux_bridge", key_value)
		var codespace_config := Store.get_integration("github_codespaces")
		var uncertain_request: Variant = codespace_config.get("creation_uncertain", {})
		if uncertain_request is Dictionary and not uncertain_request.is_empty():
			feedback.text = "Refresh existing Codespaces first. The previous create request may have succeeded even though its response was lost."
			return
		codespace_config["repository"] = repo_value
		codespace_config["ref"] = branch.text.strip_edges()
		Store.set_integration("github_codespaces", codespace_config)
		codespace_create_in_flight = true
		create_codespace.disabled = true
		create_codespace.text = "Creating workspace…"
		feedback.text = "Checking available Linux machine sizes before asking GitHub to provision the smallest eligible workspace. Creation will not be automatically repeated."
		ToolRunner.create_github_codespace(repo_value, branch.text.strip_edges()))
	sh.body.add_child(create_codespace)
	var refresh_codespaces := Ui.btn("Refresh existing workspaces", "quiet", "refresh")
	refresh_codespaces.disabled = not ToolRunner.is_github_connected()
	refresh_codespaces.pressed.connect(func():
		codespace_list_in_flight = true
		refresh_codespaces.disabled = true
		feedback.text = "Loading your Codespaces from GitHub…"
		ToolRunner.list_github_codespaces())
	sh.body.add_child(refresh_codespaces)
	var open_workspace := Ui.btn("Open selected Codespace", "ghost", "external_link")
	open_workspace.disabled = true
	open_workspace.pressed.connect(func():
		var chosen: Variant = codespace_select.get_item_metadata(codespace_select.selected) if codespace_select.item_count > 0 else {}
		var selected_url := str(chosen.get("web_url", "")) if chosen is Dictionary else ""
		if selected_url.begins_with("https://"):
			OS.shell_open(selected_url))
	var sync_selected_codespace := func() -> void:
		var chosen: Variant = codespace_select.get_item_metadata(codespace_select.selected) if codespace_select.item_count > 0 else {}
		var selected_web_url := str(chosen.get("web_url", "")) if chosen is Dictionary else ""
		open_workspace_url = selected_web_url
		open_workspace.disabled = not selected_web_url.begins_with("https://")
	codespace_select.item_selected.connect(func(_index: int):
		sync_selected_codespace.call())
	sync_selected_codespace.call()
	sh.body.add_child(open_workspace)
	var use_codespace := Ui.btn("Use selected workspace", "quiet", "check")
	var sync_codespace_use := func() -> void:
		var selected: Variant = codespace_select.get_item_metadata(codespace_select.selected) if codespace_select.item_count > 0 else {}
		var selected_valid := selected is Dictionary and str(selected.get("name", "")) != ""
		use_codespace.disabled = codespace_use_in_flight or not selected_valid
	codespace_select.item_selected.connect(func(_index: int): sync_codespace_use.call())
	sync_codespace_use.call()
	use_codespace.pressed.connect(func():
		var chosen: Variant = codespace_select.get_item_metadata(codespace_select.selected) if codespace_select.item_count > 0 else {}
		if not chosen is Dictionary or str(chosen.get("name", "")) == "":
			feedback.text = "Choose an existing Codespace first."
			return
		codespace_use_in_flight = true
		use_codespace.disabled = true
		use_codespace.text = "Starting workspace…"
		feedback.text = "Checking whether the selected Codespace is already running. Aoi will start it if GitHub has stopped it."
		ToolRunner.use_github_codespace(chosen))
	sh.body.add_child(use_codespace)


	sh.body.add_child(Ui.lbl("Cloud connection key", Ui.FS_SMALL, Ui.TEXT, true))
	sh.body.add_child(Ui.lbl("This key protects Aoi's forwarded Linux bridge. It is different from the GitHub token. Keep it private and store the same value in the repository's Codespaces secret named AOI_BRIDGE_TOKEN.", Ui.FS_SMALL, Ui.MUTED, false, true))
	sh.body.add_child(token)
	var generate := Ui.btn("Generate and copy connection key", "quiet", "copy")
	generate.pressed.connect(func():
		token.text = Crypto.new().generate_random_bytes(32).hex_encode()
		Store.set_secret("linux_bridge", token.text)
		var cloud_cfg := Store.get_integration("linux_bridge")
		cloud_cfg["last_test_ok"] = false
		cloud_cfg["tested_url"] = ""
		cloud_cfg["tested_token_sha256"] = ""
		cloud_cfg["godot_available"] = false
		cloud_cfg["last_test_error"] = "The cloud key was regenerated. Update AOI_BRIDGE_TOKEN in GitHub, then rebuild or restart the Codespace."
		Store.set_integration("linux_bridge", cloud_cfg)
		sync_codespace_create.call()
		DisplayServer.clipboard_set(token.text)
		feedback.text = "Key saved and copied. Add it to the selected repository's Codespaces secret named AOI_BRIDGE_TOKEN before creating the workspace."
		toast("Cloud connection key copied. Add it to AOI_BRIDGE_TOKEN in GitHub."))
	sh.body.add_child(generate)

	sh.body.add_child(Ui.lbl("Bridge address", Ui.FS_SMALL, Ui.TEXT, true))
	sh.body.add_child(url)
	var save := Ui.btn("Save and test connection", "primary", "check")
	var sync_linux_test_button := func() -> void:
		var candidate_url := url.text.strip_edges().trim_suffix("/")
		var candidate_key := token.text.strip_edges()
		save.disabled = not candidate_url.begins_with("https://") or not ToolRunner._is_valid_http_base(candidate_url) or candidate_key.length() != 64 or not candidate_key.is_valid_hex_number(false)
	url.text_changed.connect(func(_value: String): sync_linux_test_button.call())
	token.text_changed.connect(func(_value: String): sync_linux_test_button.call())
	sync_linux_test_button.call()
	var result_handler := func(result: Dictionary) -> void:
		if not is_instance_valid(sh): return
		var tool_name := str(result.get("tool", ""))
		if tool_name == "Linux connection test":
			sync_linux_test_button.call()
			if bool(result.get("ok", false)):
				feedback.text = str(result.get("output", "Connected to the cloud workspace."))
				save.text = "Connected · test again"
			else:
				feedback.text = str(result.get("error", "The cloud workspace could not be reached."))
				save.text = "Try connection again"
		elif tool_name == "GitHub Codespaces create":
			codespace_create_in_flight = false
			var pending_creation: Variant = Store.get_integration("github_codespaces").get("creation_uncertain", {})
			create_codespace.text = "Create GitHub Codespace"
			sync_codespace_create.call()
			if bool(result.get("ok", false)):
				var codespace_data: Dictionary = result.get("codespace", {}) if result.get("codespace", {}) is Dictionary else {}
				url.text = str(codespace_data.get("bridge_url", ""))
				var new_codespace_name := str(codespace_data.get("name", ""))
				if new_codespace_name != "":
					var list_index := -1
					for index in range(codespace_select.item_count):
						var existing: Variant = codespace_select.get_item_metadata(index)
						if existing is Dictionary and str(existing.get("name", "")) == new_codespace_name:
							list_index = index
							break
					if list_index < 0:
						codespace_select.add_item("%s · %s · %s" % [str(codespace_data.get("repository", "Repository")), str(codespace_data.get("state", "Starting")), new_codespace_name])
						list_index = codespace_select.item_count - 1
					codespace_select.set_item_metadata(list_index, codespace_data.duplicate(true))
					codespace_select.select(list_index)
					open_workspace_url = str(codespace_data.get("web_url", ""))
					open_workspace.disabled = not open_workspace_url.begins_with("https://")
				repository.text = str(codespace_data.get("repository", repository.text))
				feedback.text = str(result.get("output", "GitHub accepted the workspace request.")) + "\n\nBefore testing, confirm AOI_BRIDGE_TOKEN is saved in the repository and let the dev-container setup finish."
			else:
				feedback.text = str(result.get("error", "GitHub could not create the Codespace."))
		elif tool_name == "Request cancelled" and codespace_create_in_flight:
			codespace_create_in_flight = false
			create_codespace.text = "Refresh workspaces first"
			sync_codespace_create.call()
			refresh_codespaces.disabled = not ToolRunner.is_github_connected()
			feedback.text = "The create request was stopped after it was sent. GitHub may still have provisioned the workspace. Refresh existing Codespaces before creating anything else."
		elif tool_name == "Request cancelled" and codespace_use_in_flight:
			codespace_use_in_flight = false
			use_codespace.text = "Use selected workspace"
			sync_codespace_use.call()
			feedback.text = "The start request was stopped. Refresh Codespaces to check its current state before trying again."
		elif tool_name == "Request cancelled" and codespace_list_in_flight:
			codespace_list_in_flight = false
			refresh_codespaces.disabled = not ToolRunner.is_github_connected()
			feedback.text = "Workspace refresh was stopped. Your saved list has not been changed."
		elif tool_name == "GitHub Codespaces use":
			codespace_use_in_flight = false
			use_codespace.text = "Use selected workspace"
			sync_codespace_use.call()
			if bool(result.get("ok", false)):
				var selected_data: Dictionary = result.get("codespace", {}) if result.get("codespace", {}) is Dictionary else {}
				var selected_name := str(selected_data.get("name", ""))
				for index in range(codespace_select.item_count):
					var current_data: Variant = codespace_select.get_item_metadata(index)
					if current_data is Dictionary and str(current_data.get("name", "")) == selected_name:
						codespace_select.set_item_metadata(index, selected_data.duplicate(true))
						codespace_select.select(index)
						break
				var linux_config := Store.get_integration("linux_bridge")
				url.text = str(linux_config.get("url", ""))
				repository.text = str(selected_data.get("repository", repository.text))
				branch.text = str(selected_data.get("ref", branch.text))
				open_workspace_url = str(selected_data.get("web_url", open_workspace_url))
				open_workspace.disabled = not open_workspace_url.begins_with("https://")
				feedback.text = str(result.get("output", "The Codespace is selected. Test the bridge when it is available."))
			else:
				feedback.text = str(result.get("error", "GitHub could not use this Codespace."))
		elif tool_name == "GitHub Codespaces list":
			codespace_list_in_flight = false
			refresh_codespaces.disabled = not ToolRunner.is_github_connected()
			if bool(result.get("ok", false)):
				var listed: Variant = result.get("codespaces", [])
				populate_codespaces.call(listed if listed is Array else [])
				sync_selected_codespace.call()
				var pending_creation_after_refresh: Variant = Store.get_integration("github_codespaces").get("creation_uncertain", {})
				create_codespace.text = "Refresh workspaces first" if (pending_creation_after_refresh is Dictionary and not pending_creation_after_refresh.is_empty()) else "Create GitHub Codespace"
				sync_codespace_create.call()
				sync_codespace_use.call()
				feedback.text = str(result.get("output", "Codespaces refreshed."))
			else:
				feedback.text = str(result.get("error", "Could not load Codespaces."))
	ToolRunner.manual_completed.connect(result_handler)
	sh.closed.connect(func():
		if ToolRunner.manual_completed.is_connected(result_handler):
			ToolRunner.manual_completed.disconnect(result_handler))
	save.pressed.connect(func():
		var clean := url.text.strip_edges().trim_suffix("/")
		if not ToolRunner._is_valid_http_base(clean) or not clean.begins_with("https://"):
			feedback.text = "Enter the HTTPS address for forwarded port 8765."
			return
		var key := token.text.strip_edges()
		if key.length() != 64 or not key.is_valid_hex_number(false):
			feedback.text = "Use the same 64-character hexadecimal key saved as AOI_BRIDGE_TOKEN in GitHub."
			return
		Store.set_integration("linux_bridge", {"url":clean,"target":"codespaces","provider":"github_codespaces","last_test_ok":false,"last_test_at":0,"last_test_error":"Connection check in progress.","bridge_name":"GitHub Codespaces","workspace":"","codespace_name":str(Store.get_integration("linux_bridge").get("codespace_name", "")),"codespace_web_url":open_workspace_url,"repository":repository.text.strip_edges(),"ref":branch.text.strip_edges()})
		Store.set_secret("linux_bridge", key)
		explore.render()
		save.disabled = true
		save.text = "Checking workspace…"
		feedback.text = "Aoi is contacting the cloud workspace and checking that Godot is available."
		ToolRunner.test_linux_bridge())
	sh.body.add_child(save)
	sh.body.add_child(Ui.lbl("Security: the forwarded port is internet-reachable when Public. The bridge keeps its key separate from the low-privilege project runner. Project code still has network access and workspace access, so this is defense in depth rather than a full OS sandbox. Keep the repository private and never commit either secret.", Ui.FS_SMALL - 2, Ui.MUTED, false, true))
	if Store.has_secret("linux_bridge"):
		var disconnect := Ui.btn("Disconnect cloud workspace", "danger", "trash")
		disconnect.pressed.connect(func():
			Store.remove_secret("linux_bridge")
			Store.integrations.erase("linux_bridge")
			Store.integrations.erase("github_codespaces")
			Store.save_settings()
			explore.render()
			sh.close()
			toast("Cloud workspace disconnected"))
		sh.body.add_child(disconnect)

func _wipe() -> void:
	Store.wipe_all()
	var workflow_dir := Store.root + "workflows"
	var wd := DirAccess.open(workflow_dir)
	if wd != null:
		for filename in wd.get_files(): DirAccess.remove_absolute(workflow_dir + "/" + filename)
	LLM.models_cache.clear()
	chat.new_session()
	setup.render()
	projects.show_list()
	_update_chrome()
	toast("All data deleted")


func _continue_project_chat(project_id: String) -> void:
	if project_id.strip_edges() == "":
		return
	# Keep the current conversation when it already belongs to this project.
	if str(chat.session.get("project_id", "")) == project_id and str(chat.session.get("mode", "")) == "build":
		go("chat")
		return
	# Reopen the most recently updated build conversation for this project.
	# A single project may have several purposeful conversations; the newest one
	# is the safest continuation target and avoids duplicating the project thread.
	for saved in Store.list_sessions():
		if str(saved.get("project_id", "")) == project_id and str(saved.get("mode", "")) == "build":
			var saved_id := str(saved.get("id", ""))
			if saved_id != "":
				chat.open_session(saved_id)
				go("chat")
				return
	chat.new_session("build", project_id)
	go("chat")


func _plan_with_aoi(project_id: String) -> void:
	chat.new_session("money", project_id)
	go("chat")
	chat.send_text("Make a concrete 7-day plan for this project. Start with the single most important first step. Give every task as a '- [ ] ' checklist item.")


func _plan_workflow(project_id: String) -> void:
	var project := Store.get_project(project_id)
	if project.is_empty(): return
	var live_research_available := Store.has_secret("brave_search")
	if live_research_available:
		project["research_required"] = true
		Store.save_project(project)
		var flow := AgentFlow.ensure_flow(project)
		var research: Dictionary = flow.get("research", {})
		if not bool(research.get("required", false)):
			research["required"] = true
			research["status"] = "pending"
			flow["research"] = research
			AgentFlow.save_flow(flow)
		AgentFlow.begin_research(project_id)
		chat.new_session("build", project_id)
		chat.session["agent_role"] = "Researcher"
		Store.save_session(chat.session)
		go("chat")
		chat.send_text("""Start the mandatory discovery and research phase for this project. Do not create an implementation roadmap yet. First inspect the existing project brief, saved decisions, project notes, structure and target runtime. Then research the actual product/genre/problem using four distinct angles: reference_landscape, player_feedback (games) or user_needs (other work), technical_docs, and production_assets. Compare 2–4 references, read multiple actual reviews/community discussions, identify praise and recurring complaints, inspect official technical documentation, platform limits, all required art/UI/audio/animation/content inputs, licensing/provenance and production risks. Run at least four distinct targeted queries and gather at least six source pages across four independent registrable domains. Challenge the first plausible idea: identify the riskiest assumption and design the cheapest falsification experiment before expensive implementation. The final research brief must quote short supporting excerpts from retrieved passages for every citation. Distinguish evidence, inference and unknowns. Cite retrieved source IDs. After the research is sufficiently complete, return the structured research brief so Aoi can validate it and then generate the detailed roadmap automatically. Do not write files, execute project code or claim a research finding that was not supported by retrieved sources.""")
	else:
		AgentFlow.continue_without_external_research(project_id)
		chat.new_session("build", project_id)
		chat.session["agent_role"] = "Planner"
		Store.save_session(chat.session)
		go("chat")
		chat.send_text("""Create the implementation roadmap for this project now. First inspect the project brief, saved decisions, existing files and the connected runtime. Live multi-source web search is not configured, so do not stop or ask for an API key. Use the supplied requirements, existing project evidence and stable background knowledge; use Wikipedia only for stable background facts when it materially helps. Do not claim current web research, fabricate citations or present unverified details as facts. Mark assumptions, high-risk unknowns and any technical point that must be checked against current official documentation when live search becomes available. Then produce a detailed, testable roadmap with meaningful milestones, concrete deliverables, acceptance criteria and verification steps.""")


func _run_workflow_task(project_id: String, task: Dictionary) -> void:
	var project := Store.get_project(project_id)
	if project.is_empty(): return
	if not AgentFlow.can_run_task(project_id, str(task.get("id", ""))):
		toast("This task is blocked by dependencies or is already active.")
		return
	var provider_id := str(Catalog.split_visible(Store.model)[0]) if Store.model != "" else ""
	if provider_id == "" or not Store.has_key(provider_id):
		toast("Connect an AI provider before starting a workflow task.")
		go("setup")
		return
	var role := str(task.get("role", "Engineer"))
	var task_id := str(task.get("id", ""))
	chat.new_session("build", project_id)
	chat.session["agent_role"] = role
	chat.session["workflow_task_id"] = task_id
	Store.save_session(chat.session)
	AgentFlow.update_task(project_id, task_id, {"status":"in_progress", "title":str(task.get("title", "")), "role":role, "session_id":str(chat.session.get("id", ""))})
	AgentFlow.update_agent(project_id, role, "working", str(task.get("title", "")))
	go("chat")
	var revision_feedback := str(task.get("review_feedback", ""))
	var previous_issue := str(task.get("last_error", ""))
	var task_prompt := "Work on this approved project task as the %s specialist. Task: %s. Detailed implementation brief: %s. Required deliverables: %s. Acceptance criteria: %s. Verification method: %s. File scope: %s." % [role, str(task.get("title", "")), str(task.get("detail", "")), ", ".join(task.get("deliverables", [])), str(task.get("acceptance", "")), str(task.get("verification", "")), ", ".join(task.get("file_scope", []))]
	if revision_feedback != "":
		task_prompt += "\n\nReviewer feedback from the previous attempt: " + revision_feedback
	if previous_issue != "":
		task_prompt += "\nPrevious attempt issue: " + previous_issue
	task_prompt += "\n\nFirst inspect relevant context and files. Use connected GitHub and Linux tools when they materially help. Read-only inspection may proceed. Apply Workspace autonomy inside the explicitly selected project: routine project-scoped file edits, reads, checks and checkpoints proceed without asking for approval per file. Pause only for actions outside the project boundary, arbitrary shell or package installation, destructive/unrelated changes, credential access, publishing, and GitHub mutations. Keep changes scoped to this task, verify every listed deliverable, and do not claim success without real tool output. When done, summarise changed files, commands, evidence and unresolved items."
	chat.send_text(task_prompt)


func _open_workflow_task_chat(session_id: String) -> void:
	if session_id.strip_edges() == "":
		toast("This task has no saved conversation yet.")
		return
	if Store.load_session(session_id).is_empty():
		toast("This task conversation is no longer available. You can request changes or reopen the task.")
		return
	chat.open_session(session_id)
	go("chat")


func _workflow_answer_finished(project_id: String, workflow_task_id: String, session_id: String, answer: String) -> void:
	if workflow_task_id == "" or session_id == "":
		return
	var flow := AgentFlow.get_flow(project_id)
	if flow.is_empty(): return
	var owned_task: Dictionary = {}
	for task in flow.get("tasks", []):
		if str(task.get("id", "")) == workflow_task_id:
			owned_task = task.duplicate(true)
			break
	if str(owned_task.get("status", "")) != "in_progress" or str(owned_task.get("session_id", "")) != session_id:
		return
	var role := str(owned_task.get("role", "Engineer"))
	var title := str(owned_task.get("title", ""))
	AgentFlow.update_task(project_id, workflow_task_id, {"status":"review", "title":title, "role":role, "review_summary":_workflow_review_summary(answer)})
	AgentFlow.update_agent(project_id, role, "review", title)
	AgentFlow.record_tool(project_id, "Agent result awaiting review", true, answer.left(240))


func _workflow_answer_failed(project_id: String, workflow_task_id: String, session_id: String, reason: String) -> void:
	if workflow_task_id == "" or session_id == "":
		return
	var flow := AgentFlow.get_flow(project_id)
	if flow.is_empty(): return
	var owned_task: Dictionary = {}
	for task in flow.get("tasks", []):
		if str(task.get("id", "")) == workflow_task_id:
			owned_task = task.duplicate(true)
			break
	if str(owned_task.get("status", "")) != "in_progress" or str(owned_task.get("session_id", "")) != session_id:
		return
	var role := str(owned_task.get("role", "Engineer"))
	var title := str(owned_task.get("title", ""))
	var failure_reason := reason.strip_edges()
	if failure_reason == "": failure_reason = "This attempt stopped before a complete response was received."
	AgentFlow.update_task(project_id, workflow_task_id, {"status":"todo", "title":title, "role":role, "last_error":failure_reason.left(700)})
	AgentFlow.update_agent(project_id, role, "ready", "")
	AgentFlow.record_tool(project_id, "Workflow task paused", false, failure_reason)


func _workflow_review_summary(answer: String) -> String:
	var summary := answer.strip_edges()
	if summary == "":
		return "Aoi finished this response. Open the task chat for the full result."
	var paragraphs := summary.split("\n\n", false)
	if not paragraphs.is_empty():
		summary = str(paragraphs[0]).strip_edges().replace("\n", " ")
	while summary.begins_with("#"):
		summary = summary.substr(1).strip_edges()
	return summary.left(420) + ("..." if summary.length() > 420 else "")


# ------------------------------------------------------------------ models
func _refresh_models_silently() -> void:
	for pid in Store.connected_providers(): LLM.list_models(str(pid))


func _model_rows() -> Array:
	var rows: Array = []
	for pid in Store.connected_providers(): rows.append_array(LLM.models_cache.get(pid, []))
	return rows


func open_models() -> void:
	var sh := _sheet("Choose a model")
	var search := Ui.line("Search models")
	sh.body.add_child(search)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	sh.body.add_child(list)
	var fill := func(query: String):
		for c in list.get_children(): c.queue_free()
		var rows := _model_rows()
		if Store.connected_providers().is_empty():
			list.add_child(Ui.lbl("Connect a provider in Setup first.", Ui.FS, Ui.MUTED, false, true))
			var b := Ui.btn("Open Setup", "primary")
			b.pressed.connect(func(): sh.close(); go("setup"))
			list.add_child(b)
			return
		if rows.is_empty():
			list.add_child(Ui.lbl("Loading models…", Ui.FS, Ui.MUTED))
			_refresh_models_silently()
			return
		var ids: Array = []
		var meta := {}
		for r in rows:
			var q := query.strip_edges().to_lower()
			if q != "" and not q in str(r["label"]).to_lower(): continue
			ids.append(str(r["id"]))
			meta[str(r["id"])] = {"provider": str(r["provider"]), "free": bool(r["free"]), "label": str(r["label"]), "cost_label": str(r.get("cost_label", ""))}
		var groups: Array = MG.group(ids, meta, false, Store.model)
		if groups.is_empty(): list.add_child(Ui.lbl("No model matches “%s”." % query, Ui.FS, Ui.MUTED))
		for g in groups:
			list.add_child(Ui.lbl(str(g["name"]).to_upper(), Ui.FS_SMALL - 2, Ui.MUTED, true))
			var shown := 0
			for it in g["items"]:
				if shown >= 80: break
				shown += 1
				var on: bool = str(it["id"]) == Store.model
				var b := Ui.btn(("★  " if it["free"] else "") + str(it["label"]), "ghost")
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.clip_text = true
				b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				if on:
					b.add_theme_color_override("font_color", Ui.ACCENT_SOFT)
					b.icon = Ui.icon("check")
					b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				var mid := str(it["id"])
				b.pressed.connect(func(): _choose_model(mid, str(it["label"])); sh.close())
				list.add_child(b)
				if str(it.get("cost_label", "")) != "":
					var price := Ui.lbl(str(it["cost_label"]), 13, Ui.MUTED, false, true)
					price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					list.add_child(price)
			if (g["items"] as Array).size() > shown: list.add_child(Ui.lbl("+ %d more. Use search." % ((g["items"] as Array).size() - shown), Ui.FS_SMALL, Ui.MUTED))
	search.text_changed.connect(func(t: String): fill.call(t))
	fill.call("")
	var on_loaded := func(_pid, ok, _p): if ok and is_instance_valid(list): fill.call(search.text)
	LLM.models_loaded.connect(on_loaded)
	sh.closed.connect(func(): LLM.models_loaded.disconnect(on_loaded))


func _choose_model(visible_id: String, label: String) -> void:
	Store.model = visible_id
	Store.provider = str(Catalog.split_visible(visible_id)[0])
	Store.save_settings()
	_update_chrome()
	toast("Model: " + label.get_file().trim_suffix(":free"))


# ------------------------------------------------------------------ sheets
func _sheet(title: String) -> Control:
	var s := Sheet.new()
	add_child(s)
	s.open(title)
	return s


func open_sessions() -> void:
	var sh := _sheet("Chats")
	var nb := Ui.btn("New chat", "primary", "new_chat")
	nb.pressed.connect(func(): sh.close(); chat.new_session(); go("chat"))
	sh.body.add_child(nb)
	var search := Ui.line("Search chat titles and messages")
	search.name = "ConversationSearchField"
	search.clear_button_enabled = true
	sh.body.add_child(search)
	var results := VBoxContainer.new()
	results.name = "ConversationSearchResults"
	results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results.add_theme_constant_override("separation", 8)
	sh.body.add_child(results)
	var search_debounce := Timer.new()
	search_debounce.name = "ConversationSearchDebounce"
	search_debounce.one_shot = true
	search_debounce.wait_time = 0.18
	sh.add_child(search_debounce)
	search_debounce.timeout.connect(func():
		if is_instance_valid(sh) and sh.visible:
			_render_session_search_results(results, search.text, sh, search))
	search.text_changed.connect(func(value: String):
		if value.strip_edges() == "":
			search_debounce.stop()
			_render_session_search_results(results, value, sh, search)
		else:
			search_debounce.start())
	_render_session_search_results(results, "", sh, search)


func _render_session_search_results(results: VBoxContainer, query: String, sh: Control, search: LineEdit) -> void:
	for child in results.get_children(): child.queue_free()
	var sessions := Store.list_sessions()
	var normalized := query.strip_edges().to_lower()
	var shown := 0
	var matching := 0
	for session_data in sessions:
		var match_data := _session_search_match(session_data, normalized)
		if not bool(match_data.get("matched", false)): continue
		matching += 1
		if shown >= 80: continue
		shown += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		results.add_child(row)
		var button := Ui.btn("", "ghost")
		button.name = "ConversationResult"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 96 if str(match_data.get("snippet", "")) == "" else 124
		var copy := VBoxContainer.new()
		copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		copy.alignment = BoxContainer.ALIGNMENT_CENTER
		copy.offset_left = 28
		copy.offset_right = -20
		var title := Ui.lbl(str(session_data.get("title", "Chat")), Ui.FS, Ui.TEXT)
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.add_child(title)
		var mode := str(Catalog.MODES.get(str(session_data.get("mode", "chat")), {"name":"Chat"}).get("name", "Chat"))
		var pinned := bool(session_data.get("pinned", false))
		var subtitle_text := "%s%s · %s" % ["Pinned · " if pinned else "", mode, Ui.relative_time(float(session_data.get("updated", 0)))]
		var subtitle := Ui.lbl(subtitle_text, Ui.FS_SMALL - 2, Ui.MUTED)
		subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.add_child(subtitle)
		var snippet := str(match_data.get("snippet", ""))
		if snippet != "":
			var preview := Ui.lbl(snippet, Ui.FS_SMALL - 2, Ui.MUTED, false, true)
			preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
			copy.add_child(preview)
		button.add_child(copy)
		var session_id := str(session_data.get("id", ""))
		button.pressed.connect(func(): sh.close(); chat.open_session(session_id); go("chat"))
		row.add_child(button)
		var pin := Ui.icon_btn("pin", "quiet", 64)
		pin.tooltip_text = "Unpin conversation" if pinned else "Pin conversation"
		pin.name = "PinConversationButton"
		pin.pressed.connect(func():
			if not Store.set_session_pinned(session_id, not pinned):
				toast("Couldn't update this conversation.")
				return
			_render_session_search_results(results, search.text, sh, search))
		row.add_child(pin)
		var rename := Ui.icon_btn("edit", "quiet", 64)
		rename.tooltip_text = "Rename conversation"
		rename.name = "RenameConversationButton"
		rename.pressed.connect(func():
			var dialog := AcceptDialog.new()
			dialog.title = "Rename conversation"
			dialog.dialog_text = "Choose a clear name for this chat."
			dialog.ok_button_text = "Save"
			var title_input := Ui.line("Conversation name")
			title_input.name = "ConversationRenameField"
			title_input.max_length = 80
			title_input.text = str(session_data.get("title", ""))
			var save_button := dialog.get_ok_button()
			save_button.disabled = title_input.text.strip_edges() == ""
			title_input.text_changed.connect(func(value: String): save_button.disabled = value.strip_edges() == "")
			dialog.add_child(title_input)
			dialog.confirmed.connect(func():
				var new_title := title_input.text.strip_edges()
				if new_title == "": return
				if not Store.rename_session(session_id, new_title):
					toast("Couldn't rename this conversation.")
					return
				if str(chat.session.get("id", "")) == session_id:
					chat.session["title"] = new_title
				_render_session_search_results(results, search.text, sh, search))
			add_child(dialog)
			dialog.popup_centered(Vector2i(520, 200))
			title_input.call_deferred("grab_focus"))
		row.add_child(rename)
		var delete := Ui.icon_btn("trash", "quiet", 64)
		delete.tooltip_text = "Delete conversation"
		delete.name = "DeleteConversationButton"
		delete.pressed.connect(func():
			confirm("Delete conversation?", "This permanently deletes “%s” and its saved messages from this device." % str(session_data.get("title", "Chat")), "Delete", func():
				Store.delete_session(session_id)
				if str(chat.session.get("id", "")) == session_id: chat.new_session()
				_render_session_search_results(results, search.text, sh, search)))
		row.add_child(delete)
	if matching == 0:
		var empty_message := "No saved chats yet." if sessions.is_empty() else "No conversations match that search."
		results.add_child(Ui.lbl(empty_message, Ui.FS_SMALL, Ui.MUTED, false, true))
	elif matching > 80:
		results.add_child(Ui.lbl("Showing the 80 most recent matches. Add a word to narrow your search.", Ui.FS_SMALL - 2, Ui.MUTED, false, true))


func _session_search_match(session_data: Dictionary, query: String) -> Dictionary:
	if query == "":
		return {"matched":true, "snippet":""}
	var title := str(session_data.get("title", "")).to_lower()
	var visible_messages: Array[String] = []
	var messages: Variant = session_data.get("messages", [])
	if messages is Array:
		for message in messages:
			if not message is Dictionary or bool(message.get("internal", false)): continue
			if str(message.get("role", "")) not in ["user", "assistant"]: continue
			var content := str(message.get("content", "")).strip_edges()
			if content != "": visible_messages.append(content)
	for term in query.split(" ", false):
		if term == "" or title.contains(term): continue
		var content_found := false
		for content in visible_messages:
			if content.to_lower().contains(term):
				content_found = true
				break
		if not content_found:
			return {"matched":false, "snippet":""}
	var snippet := ""
	for content in visible_messages:
		var lower_content := content.to_lower()
		var match_index := -1
		for term in query.split(" ", false):
			match_index = lower_content.find(term)
			if match_index >= 0: break
		if match_index < 0: continue
		var start := maxi(0, match_index - 48)
		var snippet_end := mini(content.length(), start + 150)
		snippet = content.substr(start, snippet_end - start).replace("\n", " ")
		if start > 0: snippet = "..." + snippet
		if snippet_end < content.length(): snippet += "..."
		break
	return {"matched":true, "snippet":snippet}


func open_project_picker(markdown: String) -> void:
	var sh := _sheet("Save to a project")
	var plist := Store.list_projects()
	if plist.is_empty(): sh.body.add_child(Ui.lbl("No projects yet. Create one:", Ui.FS, Ui.MUTED))
	for p in plist:
		var b := Ui.btn(str(p.get("title", "")), "ghost", "folder")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var pid := str(p["id"])
		b.pressed.connect(func(): _save_into(pid, markdown); sh.close())
		sh.body.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	sh.body.add_child(row)
	var e := Ui.line("New project name")
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	var add := Ui.btn("Create", "primary")
	add.pressed.connect(func():
		if e.text.strip_edges() == "": return
		var np := Store.new_project(e.text, "")
		if np.is_empty():
			toast("Aoi couldn't save the new project. Check available storage and try again.")
			return
		_save_into(str(np["id"]), markdown)
		sh.close())
	row.add_child(add)


func _save_into(project_id: String, markdown: String) -> void:
	var p := Store.get_project(project_id)
	if p.is_empty(): return
	var n := Store.save_to_project(p, "Aoi", markdown, Md)
	if n < 0:
		toast("Aoi couldn't save this answer to the project. Your previous project data was preserved.")
		return
	toast("Saved to “%s”%s" % [str(p["title"]), (" · +%d tasks" % n) if n > 0 else ""])


func open_select_text(text: String) -> void:
	var sh := _sheet("Select text")
	var te := TextEdit.new()
	te.text = text
	te.editable = false
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.custom_minimum_size = Vector2(0, 520)
	te.add_theme_font_size_override("font_size", Ui.FS - 2)
	te.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Ui.CARD_HI, 20, Ui.BORDER, 2), 22, 16))
	te.add_theme_stylebox_override("read_only", Ui.pad(Ui.box(Ui.CARD_HI, 20, Ui.BORDER, 2), 22, 16))
	sh.body.add_child(te)
	var all := Ui.btn("Copy all", "primary", "copy")
	all.pressed.connect(func(): DisplayServer.clipboard_set(text); toast("Copied"))
	sh.body.add_child(all)


func confirm(title: String, text: String, ok_text: String, on_ok: Callable) -> void:
	var sh := _sheet(title)
	sh.body.add_child(Ui.lbl(text, Ui.FS, Ui.MUTED, false, true))
	var ok := Ui.btn(ok_text, "danger")
	ok.name = "ConfirmActionButton"
	ok.pressed.connect(func(): sh.close(); on_ok.call())
	sh.body.add_child(ok)
	var no := Ui.btn("Cancel", "ghost")
	no.pressed.connect(sh.close)
	sh.body.add_child(no)


# ------------------------------------------------------- phone integration
func _compute_safe_insets(
	safe_area: Rect2i,
	screen_size: Vector2i,
	window_position: Vector2i,
	window_size: Vector2i,
	viewport_size: Vector2,
	cutouts: Array = []
) -> Dictionary:
	# DisplayServer reports physical-screen pixels. Convert X and Y independently:
	# phones with tall aspect ratios do not necessarily share the same stretch factor.
	var sx := maxf(0.01, float(window_size.x) / maxf(1.0, viewport_size.x))
	var sy := maxf(0.01, float(window_size.y) / maxf(1.0, viewport_size.y))
	var window_rect := Rect2(Vector2(window_position), Vector2(window_size))
	var display_rect := Rect2(Vector2.ZERO, Vector2(screen_size))
	var safe_rect := Rect2(Vector2(safe_area.position), Vector2(safe_area.size)).intersection(display_rect).intersection(window_rect)
	var left_px := 0.0
	var top_px := 0.0
	var right_px := 0.0
	var bottom_px := 0.0
	if safe_rect.has_area():
		left_px = maxf(0.0, safe_rect.position.x - window_rect.position.x)
		top_px = maxf(0.0, safe_rect.position.y - window_rect.position.y)
		right_px = maxf(0.0, window_rect.end.x - safe_rect.end.x)
		bottom_px = maxf(0.0, window_rect.end.y - safe_rect.end.y)
	# A centred camera hole can sit inside an otherwise full-width top inset on
	# some Android builds. Ensure the app chrome starts below every top-edge cutout.
	for item in cutouts:
		if item is Rect2:
			var cutout: Rect2 = item
			var global_cutout := Rect2(cutout.position, cutout.size)
			if global_cutout.intersects(window_rect) and global_cutout.position.y <= window_rect.position.y + 120.0 * sy:
				top_px = maxf(top_px, global_cutout.end.y - window_rect.position.y + 10.0 * sy)
	return {
		"left": int(ceil(left_px / sx)),
		"top": int(ceil(top_px / sy)),
		"right": int(ceil(right_px / sx)),
		"bottom": int(ceil(bottom_px / sy))
	}


func _process(_d: float) -> void:
	var kb := 0.0
	var insets := {"left": 0, "top": 0, "right": 0, "bottom": 0}
	if OS.has_feature("mobile"):
		var window_size := DisplayServer.window_get_size()
		var screen_size := DisplayServer.screen_get_size()
		var viewport_size := get_viewport_rect().size
		var scale_y := maxf(0.01, float(window_size.y) / maxf(1.0, viewport_size.y))
		var keyboard_height_px := DisplayServer.virtual_keyboard_get_height()
		# Android may either overlay the IME over a full-height window or resize
		# the app window to the visible area. Only add a bottom inset in overlay
		# mode; doing so after a resize subtracts the keyboard twice and pushes the
		# empty state/composer out of the remaining viewport.
		var window_was_resized_for_ime := keyboard_height_px > 0 and screen_size.y > 0 and window_size.y < screen_size.y - int(keyboard_height_px * 0.55)
		kb = 0.0 if window_was_resized_for_ime else float(keyboard_height_px) / scale_y
		insets = _compute_safe_insets(
			DisplayServer.get_display_safe_area(),
			screen_size,
			DisplayServer.window_get_position(),
			window_size,
			viewport_size,
			DisplayServer.get_display_cutouts()
		)
	# A 12 logical-pixel buffer keeps the composer away from the gesture handle;
	# do not add it above the keyboard, where every pixel of vertical room matters.
	var bottom_inset := maxi(int(insets.bottom), int(ceil(kb)))
	if kb <= 1.0 and insets.bottom > 0:
		bottom_inset += 8
	var requested_margins := Vector4i(int(insets.left), int(insets.top), int(insets.right), bottom_inset)
	# Safe areas and keyboard height are polled because Android IMEs may not emit
	# a viewport resize on every device. Avoid forcing a full container relayout
	# every frame when the effective visible area has not changed.
	if requested_margins != _last_applied_frame_margins:
		_frame.add_theme_constant_override("margin_left", requested_margins.x)
		_frame.add_theme_constant_override("margin_top", requested_margins.y)
		_frame.add_theme_constant_override("margin_right", requested_margins.z)
		_frame.add_theme_constant_override("margin_bottom", requested_margins.w)
		_last_applied_frame_margins = requested_margins
	# Cache the reader's intent while the keyboard is closed. When the IME
	# opens, only follow the newest message if the reader was already at the
	# bottom; never yank someone away from older messages they were reading.
	if kb <= 1.0 and is_instance_valid(chat):
		_chat_follow_bottom_before_ime = chat.should_follow_bottom()
	if absf(kb - _kb_last) > 1.0:
		var keyboard_just_opened := kb > 1.0 and _kb_last <= 1.0
		_kb_last = kb
		if keyboard_just_opened and tab == "chat" and _chat_follow_bottom_before_ime:
			chat._scroll_bottom()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_request()


func _handle_back_request() -> void:
	if _drawer != null and is_instance_valid(_drawer):
		_close_navigation_drawer()
		return
	for c in get_children():
		if c is Control and c.get_script() == Sheet:
			(c as Control).call("close")
			return
	if tab == "chat" and is_instance_valid(chat) and chat.stop_active_work():
		toast("Stopping active work. The last completed response or task checkpoint will be preserved.")
		return
	if tab != "chat":
		go("chat")


# -------------------------------------------------------------- demo data
func _seed_demo_if_requested() -> void:
	if OS.get_environment("AOI_MOBILE_DEMO") != "1": return
	Store.set_root("user://demo_%d/" % Time.get_ticks_msec())
	Store.set_key("google_ai", "demo"); Store.set_key("openrouter", "demo")
	Store.status = {"google_ai": {"models_count": 9}, "openrouter": {"models_count": 31}}
	LLM.models_cache["google_ai"] = Catalog.normalize_models("google_ai", {"data": [{"id": "models/gemini-2.5-flash", "inputTokenLimit": 1048576}, {"id": "models/gemini-2.5-pro", "inputTokenLimit": 1048576}]})
	var or_rows := [{"id": "meta-llama/llama-3.3-70b-instruct:free", "context_length": 131072, "pricing": {"prompt": "0", "completion": "0"}}, {"id": "google/gemma-3-27b-it:free", "context_length": 96000, "pricing": {"prompt": "0", "completion": "0"}}, {"id": "cohere/north-mini-code:free", "context_length": 65536, "pricing": {"prompt": "0", "completion": "0"}}]
	LLM.models_cache["openrouter"] = Catalog.normalize_models("openrouter", {"data": or_rows})
	Store.model = "google_ai/gemini-2.5-flash"; Store.provider = "google_ai"; Store.save_settings()
	var p := Store.new_project("Sticker shop", "Sell custom sticker packs online and get 5 paying customers.")
	if p.is_empty():
		push_error("Aoi could not save the requested demo project.")
		return
	p["tasks"] = [{"text": "Pick 3 sticker themes", "done": true}, {"text": "Make 10 designs on my phone", "done": false}, {"text": "Open a shop page", "done": false}]
	p["notes"] = "## Aoi · 2026-10-30 12:40\nStart small: **one theme**, ten designs, one listing.\n- [ ] Pick 3 sticker themes"
	if not Store.save_project(p):
		Store.delete_project(str(p.get("id", "")))
		push_error("Aoi could not save the requested demo project details.")
		return
	var s := Store.new_session("money", str(p["id"]))
	s["title"] = "First paying customer"
	s["messages"] = [
		{"role": "user", "content": "I only have my phone. What can I sell this week?"},
		{"role": "assistant", "content": "Start with **one small digital product** you can finish in a day.\n\n- Sticker or wallpaper packs\n- A short guide from something you know well\n- Simple templates (checklists, planners)\n\n**This week**\n- [ ] Pick one idea and one buyer\n- [ ] Make a first version in 2 hours\n- [ ] Post it where your buyer already hangs out\n\nTell me your skills and I'll narrow it down."},
		{"role": "user", "content": "I can draw and I know Godot."},
	]
	Store.save_session(s)
	var s2 := Store.new_session("build"); s2["title"] = "Tiny Godot game idea"; s2["messages"] = [{"role": "user", "content": "x"}, {"role": "assistant", "content": "y"}]
	Store.save_session(s2)
	chat.open_session(str(s["id"]))
