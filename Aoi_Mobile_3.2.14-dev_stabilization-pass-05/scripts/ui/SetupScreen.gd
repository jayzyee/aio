extends ScrollContainer
## Connect a free provider in three steps: get a key, paste it, done. Everything stays on the phone.
const Ui = preload("res://scripts/ui/Ui.gd")
const Catalog = preload("res://scripts/core/Catalog.gd")
const MG = preload("res://scripts/core/ModelGroups.gd")

signal changed
signal request_models
signal request_wipe
signal request_godot_api
signal request_open_library

var _box: VBoxContainer
var _msg: Dictionary = {}          # provider id -> {text, color}
var _pending := ""                 # provider being tested
var _pending_key := ""            # candidate key; committed only after verification
var _pending_base_url := ""
var _pending_provider_name := ""
var _custom_name_draft := ""
var _custom_url_draft := ""
var _key_edits: Dictionary = {}
var _reference_category_filter := "All categories"


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]: pad.add_theme_constant_override("margin_" + side, 24)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 40)
	add_child(pad)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 22)
	pad.add_child(_box)
	LLM.models_loaded.connect(_on_models_loaded)
	render()


func render() -> void:
	_ensure_builtin_workspace_references()
	for c in _box.get_children(): c.queue_free()
	# 1. Establish a working AI connection before secondary customization.
	_box.add_child(_section_heading("AI connection", "Providers, credentials and the model used for new chats."))
	var intro := Ui.card(24)
	var iv := Ui.card_body(intro)
	iv.add_child(Ui.lbl("Connect an AI provider", Ui.FS + 2, Ui.TEXT, true, true))
	iv.add_child(Ui.lbl("Choose a provider, add its credential and use Save & test. Credentials are encrypted on this device; usage and plan requirements vary by provider.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
	iv.add_child(Ui.lbl("Google AI Studio has a free tier.", Ui.FS_SMALL, Ui.ACCENT, false, true))
	_box.add_child(intro)
	for p in Catalog.all_providers(): _box.add_child(_provider_card(p))
	_box.add_child(_custom_provider_card())
	var mc := Ui.card(24)
	var mv := Ui.card_body(mc)
	mv.add_child(Ui.lbl("Default model", Ui.FS + 1, Ui.TEXT, true))
	var cur := _model_label()
	var pick := Ui.btn(cur if cur != "" else "Choose a model", "ghost", "chevron_down")
	pick.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.disabled = Store.connected_providers().is_empty()
	pick.pressed.connect(func(): request_models.emit())
	mv.add_child(pick)
	if Store.connected_providers().is_empty(): mv.add_child(Ui.lbl("Connect and verify a provider before choosing a model.", Ui.FS_SMALL, Ui.MUTED))
	_box.add_child(mc)

	# 2. Persistent user-level behavior and references, independent of projects.
	_box.add_child(_section_heading("Workspace defaults", "Reusable instructions and source material applied across projects."))
	_box.add_child(_workspace_preferences_card())
	_box.add_child(_appearance_card())
	_box.add_child(_autonomy_card())
	_box.add_child(_reference_library_card())

	# 3. Engine documentation is an optional developer reference, not onboarding.
	_box.add_child(_section_heading("Developer references", "Live metadata and official documentation for the installed Godot version."))
	_box.add_child(_godot_reference_card())

	# 4. Destructive and privacy controls stay last and visually separate.
	_box.add_child(_section_heading("Data & privacy", "Understand where local data lives and manage it deliberately."))
	var pc := Ui.card(24)
	var pv := Ui.card_body(pc)
	pv.add_child(Ui.lbl("Your data stays on this device", Ui.FS + 1, Ui.TEXT, true))
	pv.add_child(Ui.lbl("Chats, projects and references are stored locally. API keys are encrypted and only sent to the provider you select. Messages are sent to that provider when you request a response.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
	var wipe := Ui.btn("Delete all data on this phone", "danger", "trash")
	wipe.pressed.connect(func(): request_wipe.emit())
	pv.add_child(wipe)
	_box.add_child(pc)


func _section_heading(kicker: String, description: String) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	var line := ColorRect.new()
	line.color = Ui.BORDER
	line.custom_minimum_size.y = 1
	section.add_child(line)
	var label := Ui.lbl(kicker, 17, Ui.TEXT, true)
	label.custom_minimum_size.y = 24
	section.add_child(label)
	section.add_child(Ui.lbl(description, Ui.FS_SMALL, Ui.MUTED, false, true))
	return section

func _appearance_card() -> Control:
	var accessibility := Store.get_integration("accessibility")
	var card := Ui.card(0)
	var body := Ui.card_body(card)
	body.add_child(Ui.lbl("Appearance", Ui.FS + 1, Ui.TEXT, true))
	body.add_child(Ui.lbl("Aoi uses a neutral ink palette throughout. Colour is reserved for status and meaning, not decoration.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
	var motion_toggle := Ui.btn("Reduce motion · ON" if bool(accessibility.get("reduce_motion", false)) else "Reduce motion · OFF", "ghost", "spark")
	motion_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	motion_toggle.pressed.connect(func():
		var prefs := Store.get_integration("accessibility")
		prefs["reduce_motion"] = not bool(prefs.get("reduce_motion", false))
		Store.set_integration("accessibility", prefs)
		render())
	body.add_child(motion_toggle)
	body.add_child(Ui.lbl("Motion follows real activity. Reduce motion keeps the same information without continuous animation.", Ui.FS_SMALL, Ui.MUTED, false, true))
	return card


func _on_accent_choice(_button: Button) -> void:
	# Kept as a compatibility entry point for older saved preferences.
	Ui.set_accent_color()


func _autonomy_card() -> Control:
	var mode := Store.workspace_autonomy_mode()
	var card := Ui.card(24)
	var body := Ui.card_body(card)
	body.add_child(Ui.lbl("How Aoi works while you are away", Ui.FS + 1, Ui.TEXT, true))
	body.add_child(Ui.lbl("Workspace autonomy lets Aoi complete ordinary edits and routine verification inside the active project without interrupting you for every file. Actions that leave the workspace, run arbitrary shell commands, change GitHub, access credentials, install software or delete data still stop for review.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
	var toggle := Ui.btn("Workspace autonomy · ON" if mode == "workspace" else "Confirm every change", "primary" if mode == "workspace" else "ghost", "check" if mode == "workspace" else "shield")
	toggle.pressed.connect(func():
		Store.set_workspace_autonomy_mode("confirm" if Store.workspace_autonomy_mode() == "workspace" else "workspace")
		render())
	body.add_child(toggle)
	body.add_child(Ui.lbl("Default is workspace autonomy. Aoi remains bounded to the active project; this is not unrestricted device access.", Ui.FS_SMALL - 1, Ui.MUTED, false, true))
	return card


func _workspace_preferences_card() -> Control:
	var workspace := Store.get_integration("workspace")
	var default_preferences := _read_text_resource("res://data/global_working_preferences.md")
	var legacy_preferences := _read_text_resource("res://data/legacy_working_preferences_v2.md")
	var existing_preferences := str(workspace.get("working_preferences", ""))
	var preferences_version := int(workspace.get("working_preferences_version", 0))
	# Import the user's complete global standard once. Preserve custom edits.
	if existing_preferences == "" or (existing_preferences == legacy_preferences and preferences_version < 3):
		workspace["working_preferences"] = default_preferences
		workspace["working_preferences_version"] = 3
		Store.set_integration("workspace", workspace)
	elif preferences_version < 3:
		workspace["working_preferences_version"] = 3
		Store.set_integration("workspace", workspace)

	var preferences := str(workspace.get("working_preferences", default_preferences))
	var card := Ui.card(24)
	var body := Ui.card_body(card)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	body.add_child(heading)
	var title := Ui.lbl("Global working preferences", Ui.FS + 2, Ui.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(Ui.chip("Applies everywhere", Ui.ACCENT))
	body.add_child(Ui.lbl("Your saved engineering, UI/UX, research and validation standards guide new Aoi work across every project. Project-specific instructions can add constraints without replacing these global defaults.", Ui.FS_SMALL, Ui.MUTED, false, true))

	var preview := RichTextLabel.new()
	preview.name = "GlobalWorkingPreferencesPreview"
	preview.bbcode_enabled = true
	preview.fit_content = false
	preview.scroll_active = true
	preview.selection_enabled = true
	preview.context_menu_enabled = true
	preview.custom_minimum_size = Vector2(0, 260)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.add_theme_font_size_override("normal_font_size", 16)
	preview.add_theme_font_size_override("bold_font_size", 17)
	preview.add_theme_color_override("default_color", Ui.TEXT)
	preview.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Color("#f7f8fa"), 16, Ui.BORDER, 1), 16, 12))
	preview.add_theme_stylebox_override("focus", Ui.pad(Ui.box(Color("#f7f8fa"), 16, Ui.ACCENT, 1), 16, 12))
	preview.text = _preferences_preview_bbcode(preferences)
	body.add_child(preview)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	var status := Ui.lbl("%s characters · included in new requests" % preferences.length(), 14, Ui.MUTED, false, true)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(status)
	var edit := Ui.btn("Edit standards", "primary", "edit")
	edit.name = "EditGlobalWorkingPreferences"
	edit.pressed.connect(_open_workspace_preferences_editor)
	footer.add_child(edit)
	body.add_child(footer)
	return card


func _preferences_preview_bbcode(source: String) -> String:
	var output := ""
	var in_code := false
	var bold_pattern := RegEx.new()
	bold_pattern.compile("\\*\\*(.+?)\\*\\*")
	for raw_line in source.split("\n"):
		var line := str(raw_line).strip_edges()
		if line.begins_with("```"):
			in_code = not in_code
			continue
		var safe := line.replace("[", "[lb]").replace("]", "[rb]")
		if in_code:
			output += "[color=#526278]%s[/color]\n" % safe
		elif safe.begins_with("### "):
			output += "\n[b][color=#34445d]%s[/color][/b]\n" % safe.trim_prefix("### ")
		elif safe.begins_with("## "):
			output += "\n[b][color=#26364e]%s[/color][/b]\n" % safe.trim_prefix("## ")
		elif safe.begins_with("# "):
			output += "[b][color=#1f2a3b]%s[/color][/b]\n" % safe.trim_prefix("# ")
		elif safe.begins_with("- ") or safe.begins_with("* "):
			output += "  • %s\n" % safe.substr(2)
		elif safe == "---":
			output += "[color=#9aa6b7]────────────────────────[/color]\n"
		elif safe != "":
			output += bold_pattern.sub(safe, "[b]$1[/b]", true) + "\n"
		else:
			output += "\n"
	return output


func _open_workspace_preferences_editor() -> void:
	var workspace := Store.get_integration("workspace")
	var editor_window := Window.new()
	editor_window.title = "Edit global working preferences"
	editor_window.size = Vector2i(660, 1060)
	editor_window.min_size = Vector2i(420, 620)
	editor_window.transient = true
	editor_window.theme = Ui.make_theme()
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", Ui.box(Color.WHITE, 20, Ui.BORDER, 1))
	editor_window.add_child(panel)
	var body := VBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: body.add_theme_constant_override("margin_" + side, 20)
	body.add_theme_constant_override("margin_top", 20)
	body.add_theme_constant_override("margin_bottom", 20)
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)
	body.add_child(Ui.lbl("Global working preferences", Ui.FS_TITLE, Ui.TEXT, true))
	body.add_child(Ui.lbl("These standards guide Aoi across all projects. Keep project-specific directions in that project's own instructions.", Ui.FS_SMALL, Ui.MUTED, false, true))
	var editor := TextEdit.new()
	editor.name = "GlobalWorkingPreferencesEditor"
	editor.text = str(workspace.get("working_preferences", ""))
	editor.placeholder_text = "Describe how Aoi should research, plan, build and verify work…"
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.custom_minimum_size.y = 560
	editor.add_theme_font_size_override("font_size", 16)
	editor.add_theme_color_override("font_color", Ui.TEXT)
	editor.add_theme_color_override("caret_color", Ui.ACCENT)
	editor.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Color("#f7f8fa"), 16, Ui.BORDER, 1), 14, 12))
	body.add_child(editor)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	var count := Ui.lbl("%d / 16000 characters" % editor.text.length(), 14, Ui.MUTED)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.text_changed.connect(func():
		count.text = "%d / 16000 characters" % editor.text.length()
		count.add_theme_color_override("font_color", Ui.MUTED if editor.text.length() <= 16000 else Ui.AMBER)
	)
	footer.add_child(count)
	var cancel := Ui.btn("Cancel", "quiet")
	cancel.pressed.connect(editor_window.queue_free)
	footer.add_child(cancel)
	var save := Ui.btn("Save standards", "primary", "check")
	save.pressed.connect(func():
		var cleaned := editor.text.strip_edges()
		if cleaned == "":
			count.text = "Global standards cannot be empty."
			count.add_theme_color_override("font_color", Ui.AMBER)
			return
		if cleaned.length() > 16000:
			count.text = "Reduce the content to 16000 characters before saving."
			count.add_theme_color_override("font_color", Ui.AMBER)
			return
		var updated := Store.get_integration("workspace")
		updated["working_preferences"] = cleaned
		updated["working_preferences_version"] = 3
		Store.set_integration("workspace", updated)
		editor_window.queue_free()
		changed.emit()
		render()
	)
	footer.add_child(save)
	body.add_child(footer)
	add_child(editor_window)
	editor_window.popup_centered()


func _read_text_resource(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Aoi could not load workspace reference: " + path)
		return ""
	return file.get_as_text()


func _ensure_builtin_workspace_references() -> void:
	const VISION_TITLE := "Aoi workspace vision"
	for item in Store.list_knowledge():
		if str(item.get("title", "")) == VISION_TITLE and str(item.get("source", "")) == "workspace_reference":
			# The title already names this reference; remove only the duplicated first
			# Markdown heading from earlier generated copies, preserving all other edits.
			var content := str(item.get("content", ""))
			var duplicate_heading := "# Aoi workspace vision and working ambitions"
			if content.begins_with(duplicate_heading):
				item["content"] = content.substr(duplicate_heading.length()).strip_edges()
				Store.update_knowledge(item)
			return # Preserve user edits to the built-in reference.
	var content := _read_text_resource("res://data/aoi_workspace_vision.md")
	if content.strip_edges() == "": return
	var created := Store.add_knowledge(VISION_TITLE, content, ["workspace", "reference", "global", "goals-ambitions", "product-vision"], "workspace_reference")
	if not created.is_empty():
		created["category"] = "Goals & ambitions"
		created["reference_origin"] = "Created from the user's stated Aoi workspace direction"
		Store.update_knowledge(created)


func _reference_category(item: Dictionary) -> String:
	var category := str(item.get("category", "")).strip_edges()
	if category != "": return category
	var tags: Array = item.get("tags", [])
	for tag in tags:
		match str(tag):
			"work-standards": return "Work standards"
			"architecture": return "Architecture"
			"api-documentation": return "API & documentation"
			"design-ui": return "Design & UI"
			"project-patterns": return "Project patterns"
			"goals-ambitions", "product-vision": return "Goals & ambitions"
			"learning-research": return "Learning & research"
	return "Other"


func _reference_library_card() -> Control:
	var card := Ui.card(24)
	var body := Ui.card_body(card)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	body.add_child(head)
	var title := Ui.lbl("Global reference library", Ui.FS + 2, Ui.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var manage := Ui.btn("Manage all", "quiet", "forward")
	manage.custom_minimum_size = Vector2(116, 48)
	manage.pressed.connect(func(): request_open_library.emit())
	head.add_child(manage)
	var add := Ui.btn("Add", "ghost", "plus")
	add.custom_minimum_size = Vector2(92, 48)
	add.pressed.connect(_open_reference_editor)
	head.add_child(add)
	body.add_child(Ui.lbl("Keep reusable design references, architecture decisions, research notes, API examples and ambitions here. Aoi can retrieve them across projects without mixing project-specific files or instructions.", Ui.FS_SMALL, Ui.MUTED, false, true))
	var all_references: Array = []
	var category_counts: Dictionary = {}
	for item in Store.list_knowledge():
		if str(item.get("source", "")) != "workspace_reference": continue
		all_references.append(item)
		var category_name := _reference_category(item)
		category_counts[category_name] = int(category_counts.get(category_name, 0)) + 1
	var categories := ["All categories", "Work standards", "Goals & ambitions", "Architecture", "Design & UI", "API & documentation", "Learning & research", "Project patterns", "Other"]
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 8)
	filter_row.add_child(Ui.lbl("CATEGORY", 13, Ui.MUTED, true))
	var category_picker := OptionButton.new()
	category_picker.name = "GlobalReferenceCategoryFilter"
	category_picker.custom_minimum_size = Vector2(0, 46)
	category_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_picker.add_theme_font_size_override("font_size", 16)
	category_picker.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Color("#f7f8fa"), 14, Ui.BORDER, 1), 14, 7))
	category_picker.add_theme_stylebox_override("hover", Ui.pad(Ui.box(Color("#f2f2f2"), 14, Ui.ACCENT_SOFT, 1), 14, 7))
	category_picker.add_theme_stylebox_override("pressed", Ui.pad(Ui.box(Color("#f2f2f2"), 14, Ui.ACCENT, 1), 14, 7))
	category_picker.add_theme_stylebox_override("focus", Ui.pad(Ui.box(Color.WHITE, 14, Ui.ACCENT, 2), 14, 7))
	category_picker.add_theme_color_override("font_color", Ui.TEXT)
	category_picker.add_theme_color_override("font_hover_color", Ui.TEXT)
	category_picker.add_theme_color_override("font_pressed_color", Ui.TEXT)
	category_picker.add_theme_color_override("font_focus_color", Ui.TEXT)
	category_picker.add_theme_color_override("icon_normal_color", Ui.MUTED)
	category_picker.add_theme_color_override("icon_hover_color", Ui.ACCENT)
	for category_name in categories:
		var suffix := ""
		if category_name != "All categories": suffix = " · %d" % int(category_counts.get(category_name, 0))
		category_picker.add_item(category_name + suffix)
		category_picker.set_item_metadata(category_picker.item_count - 1, category_name)
	var selected_index := 0
	for i in range(category_picker.item_count):
		if str(category_picker.get_item_metadata(i)) == _reference_category_filter: selected_index = i
	category_picker.select(selected_index)
	category_picker.item_selected.connect(func(index: int):
		_reference_category_filter = str(category_picker.get_item_metadata(index))
		render())
	filter_row.add_child(category_picker)
	body.add_child(filter_row)
	var references: Array = []
	for item in all_references:
		if _reference_category_filter != "All categories" and _reference_category(item) != _reference_category_filter: continue
		references.append(item)
	if references.is_empty():
		var empty := PanelContainer.new()
		empty.add_theme_stylebox_override("panel", Ui.pad(Ui.box(Color("#f7f8fa"), 16), 16, 14))
		var empty_body := VBoxContainer.new()
		empty_body.add_theme_constant_override("separation", 8)
		empty.add_child(empty_body)
		if all_references.is_empty():
			empty_body.add_child(Ui.lbl("Your global reference library is ready.", Ui.FS_SMALL + 1, Ui.TEXT, true))
			empty_body.add_child(Ui.lbl("Add a reusable reference once; Aoi can use it when relevant in any project.", 15, Ui.MUTED, false, true))
		else:
			empty_body.add_child(Ui.lbl("No references in this category yet.", Ui.FS_SMALL + 1, Ui.TEXT, true))
			empty_body.add_child(Ui.lbl("Choose another category or add a new reference.", 15, Ui.MUTED, false, true))
		var create := Ui.btn("Add a global reference", "ghost", "plus")
		create.pressed.connect(_open_reference_editor)
		empty_body.add_child(create)
		body.add_child(empty)
	else:
		for item in references.slice(0, mini(6, references.size())):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var copy := VBoxContainer.new()
			copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			copy.add_theme_constant_override("separation", 3)
			copy.add_child(Ui.lbl(str(item.get("title", "Reference")), Ui.FS_SMALL + 1, Ui.TEXT, true, true))
			var preview_text := str(item.get("content", "")).strip_edges().replace("\n", " ")
			preview_text = preview_text.replace("#", "").replace("**", "").replace("- ", "")
			copy.add_child(Ui.lbl(preview_text.left(118), 14, Ui.MUTED, false, true))
			row.add_child(copy)
			row.add_child(Ui.chip(_reference_category(item), Ui.ACCENT))
			var edit := Ui.icon_btn("edit", "quiet", 48)
			edit.tooltip_text = "Edit reference"
			edit.pressed.connect(func(): _open_reference_editor(str(item.get("id", ""))))
			row.add_child(edit)
			var remove := Ui.icon_btn("trash", "quiet", 48)
			remove.tooltip_text = "Delete reference"
			remove.pressed.connect(func():
				Store.delete_knowledge(str(item.get("id", "")))
				render())
			row.add_child(remove)
			body.add_child(row)
		if references.size() > 6:
			body.add_child(Ui.lbl("Showing 6 of %d references in this category. Manage all to search and edit the full library." % references.size(), 14, Ui.MUTED, false, true))
	return card


func _open_reference_editor(item_id: String = "") -> void:
	var existing := Store.get_knowledge(item_id) if item_id != "" else {}
	var win := Window.new()
	win.title = "Edit global reference" if not existing.is_empty() else "Add global reference"
	win.size = Vector2i(620, 920)
	win.min_size = Vector2i(420, 600)
	win.transient = true
	win.theme = Ui.make_theme()
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", Ui.box(Color.WHITE, 20, Ui.BORDER, 1))
	win.add_child(panel)
	var body := VBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: body.add_theme_constant_override("margin_" + side, 20)
	body.add_theme_constant_override("margin_top", 20)
	body.add_theme_constant_override("margin_bottom", 20)
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)
	body.add_child(Ui.lbl("Reference details", Ui.FS_TITLE, Ui.TEXT, true))
	var title := Ui.line("Reference title")
	title.text = str(existing.get("title", ""))
	body.add_child(title)
	body.add_child(Ui.lbl("Reference category", Ui.FS_SMALL, Ui.MUTED, true))
	var category := OptionButton.new()
	category.custom_minimum_size.y = Ui.BTN_H
	category.add_theme_font_size_override("font_size", Ui.FS_SMALL)
	category.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Ui.CARD_HI, 16, Ui.BORDER, 1), 16, 8))
	category.add_theme_stylebox_override("hover", Ui.pad(Ui.box(Color("#f2f2f2"), 16, Ui.ACCENT_SOFT, 1), 16, 8))
	category.add_theme_stylebox_override("focus", Ui.pad(Ui.box(Ui.SURFACE, 16, Ui.ACCENT, 1), 16, 8))
	var categories := ["Work standards", "Goals & ambitions", "Architecture", "Design & UI", "API & documentation", "Learning & research", "Project patterns", "Other"]
	for label in categories: category.add_item(label)
	var existing_category := str(existing.get("category", "Other"))
	var category_index := categories.find(existing_category)
	category.select(category_index if category_index >= 0 else 5)
	body.add_child(category)
	var content := TextEdit.new()
	content.placeholder_text = "Paste notes, architecture decisions, API examples or source extracts…"
	content.text = str(existing.get("content", ""))
	content.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.custom_minimum_size.y = 420
	content.add_theme_font_size_override("font_size", 18)
	content.add_theme_color_override("font_color", Ui.TEXT)
	content.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Color("#f7f8fa"), 16, Ui.BORDER, 1), 14, 12))
	body.add_child(content)
	var note := Ui.lbl("References are stored locally and may be retrieved when relevant to future chats. Do not save API keys or passwords here.", 14, Ui.MUTED, false, true)
	body.add_child(note)
	var actions := HBoxContainer.new()
	var cancel := Ui.btn("Cancel", "quiet")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(win.queue_free)
	actions.add_child(cancel)
	var save := Ui.btn("Save reference", "primary", "check")
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(func():
		if title.text.strip_edges() == "" or content.text.strip_edges() == "":
			note.text = "Enter both a title and reference content before saving."
			note.add_theme_color_override("font_color", Ui.AMBER)
			return
		var category_name: String = str(categories[category.selected])
		var category_tag: String = category_name.to_lower().replace(" & ", "-").replace(" ", "-")
		if existing.is_empty():
			var created := Store.add_knowledge(title.text, content.text, ["workspace", "reference", "global", category_tag], "workspace_reference")
			if not created.is_empty():
				created["category"] = category_name
				Store.update_knowledge(created)
		else:
			existing["title"] = title.text
			existing["content"] = content.text
			existing["category"] = category_name
			existing["tags"] = ["workspace", "reference", "global", category_tag]
			Store.update_knowledge(existing)
		win.queue_free()
		render())
	actions.add_child(save)
	body.add_child(actions)
	add_child(win)
	win.popup_centered()


func _godot_reference_card() -> Control:
	var summary := GodotSandbox.ensure_index()
	var card := Ui.card(24)
	var body := Ui.card_body(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var title := Ui.lbl("Godot engine reference", Ui.FS + 2, Ui.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(Ui.chip(str(summary.get("engine", "Godot")), Ui.ACCENT))
	body.add_child(row)
	body.add_child(Ui.lbl("Browse the classes exposed by this running engine, including methods, properties and signals. The reference index is generated from Godot's ClassDB rather than a manually maintained list.", Ui.FS_SMALL, Ui.MUTED, false, true))
	body.add_child(Ui.lbl("%d engine classes currently available" % int(summary.get("count", 0)), 14, Ui.GREEN))
	var open := Ui.btn("Browse live Godot API", "primary", "code")
	open.pressed.connect(func(): request_godot_api.emit())
	body.add_child(open)
	var docs := Ui.btn("Open official Godot 4.8 documentation", "quiet", "forward")
	docs.pressed.connect(func(): OS.shell_open("https://docs.godotengine.org/en/4.8/classes/index.html"))
	body.add_child(docs)
	return card


func _model_label() -> String:
	if Store.model == "": return ""
	var parts := Catalog.split_visible(Store.model)
	return "%s · %s" % [str(Catalog.by_id(str(parts[0])).get("name", parts[0])), str(parts[1])]


func _provider_card(p: Dictionary) -> Control:
	var pid := str(p["id"])
	var connected := Store.has_key(pid) and int((Store.status.get(pid, {}) as Dictionary).get("models_count", 0)) > 0
	var saved_status: Dictionary = Store.status.get(pid, {}) if Store.status.get(pid, {}) is Dictionary else {}
	var first_use_verification := bool(p.get("verify_on_first_use", false))
	var c := Ui.card(28)
	var v := Ui.card_body(c)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	var name := Ui.lbl(str(p["name"]), Ui.FS + 2, Ui.TEXT, true)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	if connected:
		var verified := bool(saved_status.get("credential_verified", false))
		var status_text := "Connected · %d models" % int(saved_status.get("models_count", 0))
		var status_color := Ui.GREEN
		if first_use_verification and not verified:
			status_text = "Token saved · first chat checks it"
			status_color = Ui.AMBER
		top.add_child(Ui.chip(status_text, status_color))
	else:
		var plan_label := str(p.get("plan_label", "Free" if bool(p.get("free", false)) else "Optional"))
		top.add_child(Ui.chip(plan_label, Ui.GREEN if bool(p.get("free", false)) else Ui.AMBER))
	v.add_child(Ui.lbl(str(p["tagline"]), Ui.FS_SMALL + 2, Ui.MUTED, false, true))
	var setup_note := str(p.get("setup_note", "")).strip_edges()
	if setup_note != "":
		v.add_child(Ui.lbl(setup_note, Ui.FS_SMALL, Ui.MUTED, false, true))
	if not connected:
		var get := Ui.btn(str(p.get("get_label", "Get free key" if bool(p.get("free", false)) else "Open provider account")), "ghost", "forward")
		get.pressed.connect(func(): OS.shell_open(str(p["signup_url"])))
		v.add_child(get)
	var edit := Ui.line("Paste %s" % str(p["key_hint"]) if not connected else "Paste a replacement credential", true)
	_key_edits[pid] = edit
	v.add_child(edit)
	var button_label := "Save credential & load models" if first_use_verification else "Save & test"
	var save := Ui.btn("Saving…" if _pending == pid else button_label, "primary")
	save.disabled = _pending != "" or edit.text.strip_edges().is_empty()
	edit.text_changed.connect(func(value: String):
		save.disabled = _pending != "" or value.strip_edges().is_empty())
	save.pressed.connect(func(): connect_provider(pid, edit.text))
	v.add_child(save)
	if connected:
		var off := Ui.btn("Disconnect", "quiet")
		off.pressed.connect(func(): disconnect_provider(pid))
		v.add_child(off)
	var m: Dictionary = _msg.get(pid, {})
	if not m.is_empty(): v.add_child(Ui.lbl(str(m["text"]), Ui.FS_SMALL + 2, m["color"], false, true))
	elif not connected: v.add_child(Ui.lbl(str(p["free_note"]), Ui.FS_SMALL, Ui.MUTED, false, true))
	return c


func _custom_provider_card() -> Control:
	var config := Store.get_integration("custom_provider")
	var connected := Store.has_key("custom") and int(Store.status.get("custom", {}).get("models_count", 0)) > 0
	var card := Ui.card(28)
	var body := Ui.card_body(card)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	body.add_child(heading)
	var title := Ui.lbl("Custom OpenAI-compatible endpoint", Ui.FS + 2, Ui.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(Ui.chip("Connected · %d models" % int(Store.status["custom"]["models_count"]), Ui.GREEN) if connected else Ui.chip("Optional", Ui.MUTED))
	body.add_child(Ui.lbl("Connect compatible APIs directly. Aoi checks your key and discovers chat models before saving the connection.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
	var name_edit := Ui.line("Provider name")
	name_edit.text = _custom_name_draft if _custom_name_draft != "" else str(config.get("name", ""))
	body.add_child(name_edit)
	var url_edit := Ui.line("https://api.example.com/v1")
	url_edit.text = _custom_url_draft if _custom_url_draft != "" else str(config.get("base_url", ""))
	body.add_child(url_edit)
	var key_edit := Ui.line("API key (blank keeps the saved key)", true)
	body.add_child(key_edit)
	body.add_child(Ui.lbl("Remote endpoints must use HTTPS. HTTP is allowed only for localhost testing. Your key and chat messages go to this endpoint.", Ui.FS_SMALL, Ui.MUTED, false, true))
	var save := Ui.btn("Testing endpoint…" if _pending == "custom" else "Save & discover models", "primary", "spark")
	save.disabled = _pending != "" or (key_edit.text.strip_edges().is_empty() and not Store.has_key("custom"))
	save.pressed.connect(func(): connect_custom_provider(name_edit.text, url_edit.text, key_edit.text))
	body.add_child(save)
	var message: Dictionary = _msg.get("custom", {})
	if not message.is_empty():
		body.add_child(Ui.lbl(str(message["text"]), Ui.FS_SMALL + 2, message["color"], false, true))
	elif not connected:
		body.add_child(Ui.lbl("Compatible with providers that expose /models and /chat/completions.", Ui.FS_SMALL, Ui.MUTED, false, true))
	if not config.is_empty() or Store.has_key("custom"):
		var disconnect := Ui.btn("Disconnect custom endpoint", "quiet", "unlink")
		disconnect.disabled = _pending != ""
		disconnect.pressed.connect(func(): disconnect_provider("custom"))
		body.add_child(disconnect)
	return card


func connect_provider(pid: String, key: String) -> void:
	key = key.strip_edges()
	if key == "":
		_msg[pid] = {"text": "Paste your key first.", "color": Ui.AMBER}
		render()
		return
	if _pending != "": return
	_pending = pid
	_pending_key = key
	_pending_base_url = ""
	_pending_provider_name = ""
	_msg[pid] = {"text": "Loading the public model list. This does not spend Puter credits." if bool(Catalog.by_id(pid).get("verify_on_first_use", false)) else "Testing the key…", "color": Ui.ACCENT_SOFT}
	render()
	LLM.list_models(pid, key)


func connect_custom_provider(provider_name: String, base_url: String, key: String) -> void:
	provider_name = provider_name.strip_edges()
	base_url = base_url.strip_edges().trim_suffix("/")
	key = key.strip_edges()
	_custom_name_draft = provider_name
	_custom_url_draft = base_url
	if provider_name == "":
		_msg["custom"] = {"text":"Enter a name for this provider.", "color":Ui.AMBER}
		render()
		return
	if not Catalog.is_safe_custom_base_url(base_url):
		_msg["custom"] = {"text":"Use a valid HTTPS API base URL. HTTP is allowed only for localhost.", "color":Ui.AMBER}
		render()
		return
	if key == "":
		key = Store.get_key("custom")
	if key == "":
		_msg["custom"] = {"text":"Paste an API key to test this endpoint.", "color":Ui.AMBER}
		render()
		return
	if _pending != "": return
	_pending = "custom"
	_pending_key = key
	_pending_base_url = base_url
	_pending_provider_name = provider_name
	_msg["custom"] = {"text":"Testing the endpoint and discovering models…", "color":Ui.ACCENT_SOFT}
	render()
	LLM.list_models("custom", key, base_url)


func _on_models_loaded(pid: String, ok: bool, payload: Variant) -> void:
	if pid != _pending: return
	_pending = ""
	if not ok:
		_pending_key = ""
		_pending_base_url = ""
		_pending_provider_name = ""
		var retained := Store.has_key(pid)
		var message := str(payload)
		if retained:
			message = ("The new endpoint could not be verified. Your existing connection was kept. " if pid == "custom" else "The new key could not be verified. Your existing connection was kept. ") + message
		_msg[pid] = {"text": message, "color": Ui.RED}
		render()
		return
	if pid == "custom":
		Store.integrations["custom_provider"] = {"name":_pending_provider_name, "base_url":_pending_base_url}
		_custom_name_draft = _pending_provider_name
		_custom_url_draft = _pending_base_url
	var credential_unchanged := Store.get_key(pid) == _pending_key
	var previously_verified := bool((Store.status.get(pid, {}) as Dictionary).get("credential_verified", false))
	Store.set_key(pid, _pending_key)
	_pending_key = ""
	_pending_base_url = ""
	_pending_provider_name = ""
	var rows: Array = payload
	Store.status[pid] = {"models_count": rows.size(), "checked_at": Time.get_unix_time_from_system()}
	if bool(Catalog.by_id(pid).get("verify_on_first_use", false)):
		Store.status[pid]["credential_verified"] = credential_unchanged and previously_verified
	var cur := Catalog.split_visible(Store.model)
	if Store.model == "" or not Store.has_key(str(cur[0])):
		Store.model = Catalog.default_model(pid, rows)
		Store.provider = pid
	Store.save_settings()
	var ready_message := "Connected. You're ready to chat."
	if bool(Catalog.by_id(pid).get("verify_on_first_use", false)):
		ready_message = "Model list loaded. Puter checks your token and paid-plan status on the first chat request; that request may use your account credit."
	var requires_first_use_check := bool(Catalog.by_id(pid).get("verify_on_first_use", false))
	_msg[pid] = {"text": ready_message, "color": Ui.AMBER if requires_first_use_check else Ui.GREEN}
	render()
	changed.emit()


func disconnect_provider(pid: String) -> void:
	LLM.invalidate_model_list(pid)
	if _pending == pid:
		_pending = ""
		_pending_key = ""
		_pending_base_url = ""
		_pending_provider_name = ""
	if pid == "custom":
		Store.integrations.erase("custom_provider")
		_custom_name_draft = ""
		_custom_url_draft = ""
	Store.remove_key(pid)
	LLM.models_cache.erase(pid)
	_msg.erase(pid)
	if str(Catalog.split_visible(Store.model)[0]) == pid:
		Store.model = ""
		for other in Store.connected_providers():
			Store.model = Catalog.default_model(str(other), LLM.models_cache.get(other, []))
			Store.provider = str(other)
			break
		Store.save_settings()
	render()
	changed.emit()
