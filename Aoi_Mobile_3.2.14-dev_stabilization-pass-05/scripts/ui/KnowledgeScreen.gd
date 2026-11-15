extends VBoxContainer
## Personal knowledge library. Notes are stored locally and can be searched across title, content and tags.
const Ui = preload("res://scripts/ui/Ui.gd")

signal toast(text: String)

var _search: LineEdit
var _results: VBoxContainer
var _count_label: Label
var _filter := "all"
var _editor_window: Window
var _filter_buttons: Array[Button] = []


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)
	_build()
	if not Store.changed.is_connected(_on_store_changed):
		Store.changed.connect(_on_store_changed)
	_render_results()


func _build() -> void:
	var shell := MarginContainer.new()
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]: shell.add_theme_constant_override("margin_" + side, 22)
	shell.add_theme_constant_override("margin_top", 18)
	shell.add_theme_constant_override("margin_bottom", 24)
	add_child(shell)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	shell.add_child(layout)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	layout.add_child(heading)
	var title_group := VBoxContainer.new()
	title_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_group.add_child(Ui.lbl("Notes and answers you want to keep.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
	heading.add_child(title_group)
	var add := Ui.btn("New note", "primary", "plus")
	add.custom_minimum_size = Vector2(142, 58)
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.add_theme_font_size_override("font_size", 19)
	add.pressed.connect(func(): _open_editor())
	heading.add_child(add)

	var summary_row := HBoxContainer.new()
	summary_row.add_theme_constant_override("separation", 8)
	var book := TextureRect.new()
	book.texture = Ui.icon("notebook")
	book.custom_minimum_size = Vector2(26, 26)
	book.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	book.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	book.modulate = Ui.ACCENT
	summary_row.add_child(book)
	_count_label = Ui.lbl("0 saved notes", Ui.FS_SMALL, Ui.MUTED, true)
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_row.add_child(_count_label)
	summary_row.add_child(Ui.lbl("Stored on this device", 15, Ui.MUTED))
	layout.add_child(summary_row)

	_search = Ui.line("Search your knowledge…")
	_search.custom_minimum_size.y = 58
	_search.text_changed.connect(func(_value: String): _render_results())
	layout.add_child(_search)

	var filters := GridContainer.new()
	filters.columns = 4
	filters.add_theme_constant_override("h_separation", 6)
	filters.add_theme_constant_override("v_separation", 6)
	for row in [["all", "All notes"], ["pinned", "Pinned"], ["chat", "From chat"], ["global", "Global refs"]]:
		var filter_button := Button.new()
		filter_button.text = str(row[1])
		filter_button.focus_mode = Control.FOCUS_NONE
		filter_button.custom_minimum_size = Vector2(0, 46)
		filter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filter_button.add_theme_font_size_override("font_size", 17)
		filter_button.pressed.connect(func(): _filter = str(row[0]); _render_results())
		filters.add_child(filter_button)
		filter_button.set_meta("filter_id", str(row[0]))
		_filter_buttons.append(filter_button)
		_style_filter(filter_button, str(row[0]) == _filter)
	layout.add_child(filters)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(sc)
	_results = VBoxContainer.new()
	_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results.add_theme_constant_override("separation", 12)
	sc.add_child(_results)


func _style_filter(button: Button, active: bool) -> void:
	var style := Ui.pad(Ui.box(Color("#e9e9e9") if active else Color(0, 0, 0, 0), 8), 16, 7)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("focus", Ui.box(Color(0, 0, 0, 0), 8, Ui.ACCENT, 1))
	button.add_theme_stylebox_override("hover", Ui.pad(Ui.box(Color("#f1f1f1"), 8), 16, 7))
	button.add_theme_color_override("font_color", Ui.TEXT if active else Ui.MUTED)
	button.add_theme_color_override("font_hover_color", Ui.TEXT)


func _on_store_changed() -> void:
	if is_inside_tree(): _render_results()


func _render_results() -> void:
	if _results == null or not is_instance_valid(_results): return
	for child in _results.get_children(): child.queue_free()
	var all: Array = Store.list_knowledge()
	_count_label.text = "%d saved note%s" % [all.size(), "" if all.size() == 1 else "s"]
	for filter_button in _filter_buttons:
		if is_instance_valid(filter_button):
			_style_filter(filter_button, str(filter_button.get_meta("filter_id", "")) == _filter)
	var q := _search.text.strip_edges().to_lower()
	var shown := 0
	for item in Store.search_knowledge(q, 120):
		if _filter == "pinned" and not bool(item.get("pinned", false)): continue
		if _filter == "chat" and str(item.get("source", "")) != "chat": continue
		if _filter == "global" and str(item.get("source", "")) != "workspace_reference": continue
		_results.add_child(_note_card(item))
		shown += 1
	if shown == 0:
		var empty := VBoxContainer.new()
		empty.add_theme_constant_override("separation", 10)
		empty.add_child(Ui.lbl("Your library is ready.", Ui.FS + 2, Ui.TEXT, true))
		empty.add_child(Ui.lbl("Save strong answers from chat, keep project decisions, or write notes you want Aoi to remember. Search will find words in titles, notes and tags.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
		var first := Ui.btn("Create your first note", "ghost", "plus")
		first.pressed.connect(func(): _open_editor())
		empty.add_child(first)
		_results.add_child(empty)


func show_global_references() -> void:
	_filter = "global"
	_render_results()


func _note_card(item: Dictionary) -> Control:
	var card := Ui.card(18)
	var body := Ui.card_body(card)
	body.add_theme_constant_override("separation", 9)
	var top := HBoxContainer.new()
	body.add_child(top)
	var title := Ui.lbl(str(item.get("title", "Untitled note")), Ui.FS, Ui.TEXT, true, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	if bool(item.get("pinned", false)): top.add_child(Ui.chip("Pinned", Ui.ACCENT))
	var preview := Ui.lbl(_plain_preview(str(item.get("content", "")), 240), Ui.FS_SMALL + 1, Ui.MUTED, false, true)
	preview.custom_minimum_size.y = 42
	body.add_child(preview)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	body.add_child(meta)
	var tags: Array = item.get("tags", [])
	for tag in tags.slice(0, 3): meta.add_child(Ui.chip(str(tag), Ui.MUTED))
	var stamp := Ui.lbl(Ui.relative_time(float(item.get("updated", item.get("created", 0)))), 15, Ui.MUTED)
	stamp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.add_child(stamp)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	body.add_child(actions)
	var open := Ui.btn("Open", "quiet", "forward")
	open.custom_minimum_size = Vector2(112, 48)
	open.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	open.add_theme_font_size_override("font_size", 18)
	open.pressed.connect(func(): _open_editor(item))
	actions.add_child(open)
	var pin := Ui.icon_btn("bookmark", "quiet", 48)
	pin.tooltip_text = "Pin or unpin"
	pin.pressed.connect(func():
		var updated: Dictionary = Store.get_knowledge(str(item.id))
		updated["pinned"] = not bool(updated.get("pinned", false))
		Store.update_knowledge(updated)
	)
	actions.add_child(pin)
	var copy := Ui.icon_btn("copy", "quiet", 48)
	copy.tooltip_text = "Copy note"
	copy.pressed.connect(func(): DisplayServer.clipboard_set(str(item.get("title", "")) + "\n\n" + str(item.get("content", ""))); toast.emit("Knowledge copied"))
	actions.add_child(copy)
	return card


func _plain_preview(markdown: String, max_chars: int = 240) -> String:
	# Cards are scan surfaces, not Markdown editors. Remove lightweight syntax while
	# retaining headings, list meaning and paragraph boundaries as readable prose.
	var parts: Array[String] = []
	for raw_line in markdown.replace("\r", "").split("\n"):
		var line := str(raw_line).strip_edges()
		if line == "" or line == "---": continue
		while line.begins_with("#"): line = line.trim_prefix("#").strip_edges()
		if line.begins_with("- [ ] ") or line.begins_with("- [x] ") or line.begins_with("- [X] "):
			line = line.substr(6).strip_edges()
		elif line.begins_with("- ") or line.begins_with("* "):
			line = line.substr(2).strip_edges()
		line = line.replace("**", "").replace("__", "").replace("`", "").replace("*", "").replace("_", "")
		parts.append(line)
	var result := " ".join(parts).strip_edges()
	if result.length() <= max_chars: return result
	var cutoff := result.rfind(" ", max_chars)
	if cutoff < max_chars / 2: cutoff = max_chars
	return result.left(cutoff).strip_edges() + "…"


func _open_editor(existing: Dictionary = {}, source: String = "manual") -> void:
	if _editor_window != null and is_instance_valid(_editor_window): _editor_window.queue_free()
	var is_edit := existing.has("id")
	_editor_window = Window.new()
	_editor_window.title = "Edit knowledge" if is_edit else "New knowledge"
	_editor_window.size = Vector2i(650, 920)
	_editor_window.min_size = Vector2i(420, 620)
	_editor_window.transient = true
	_editor_window.exclusive = true
	_editor_window.close_requested.connect(func(): _editor_window.queue_free())
	add_child(_editor_window)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: pad.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]: pad.add_theme_constant_override("margin_" + side, 18)
	_editor_window.add_child(pad)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 12)
	pad.add_child(form)
	form.add_child(Ui.lbl("Keep important information easy to find.", Ui.FS_SMALL, Ui.MUTED, false, true))
	form.add_child(Ui.lbl("Title", 17, Ui.MUTED, true))
	var title := Ui.line("A clear, searchable title")
	if not existing.is_empty(): title.text = str(existing.get("title", ""))
	form.add_child(title)
	form.add_child(Ui.lbl("Note", 17, Ui.MUTED, true))
	var content := TextEdit.new()
	content.placeholder_text = "Write the useful detail, decision, reference or procedure…"
	content.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.custom_minimum_size.y = 340
	content.add_theme_font_size_override("font_size", Ui.FS_SMALL + 2)
	content.add_theme_color_override("font_color", Ui.TEXT)
	content.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Ui.CARD_HI, 16, Ui.BORDER, 1), 16, 12))
	content.add_theme_stylebox_override("focus", Ui.pad(Ui.box(Ui.CARD, 16, Ui.ACCENT, 1), 16, 12))
	if not existing.is_empty(): content.text = str(existing.get("content", ""))
	form.add_child(content)
	form.add_child(Ui.lbl("Tags · comma separated", 17, Ui.MUTED, true))
	var tags := Ui.line("e.g. Godot, architecture, decisions")
	if not existing.is_empty():
		var existing_tags := PackedStringArray()
		for tag in existing.get("tags", []): existing_tags.append(str(tag))
		tags.text = ", ".join(existing_tags)
	form.add_child(tags)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var cancel := Ui.btn("Cancel", "ghost")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func(): _editor_window.queue_free())
	buttons.add_child(cancel)
	var save := Ui.btn("Save note", "primary", "check")
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(func():
		var parsed_tags: Array[String] = []
		for tag in tags.text.split(","):
			var clean := tag.strip_edges()
			if clean != "": parsed_tags.append(clean)
		var ok := false
		if not is_edit:
			ok = not Store.add_knowledge(title.text, content.text, parsed_tags, source).is_empty()
		else:
			var updated := Store.get_knowledge(str(existing.id))
			updated["title"] = title.text
			updated["content"] = content.text
			updated["tags"] = parsed_tags
			ok = Store.update_knowledge(updated)
		if not ok:
			toast.emit("Add a title and some note content first.")
			return
		_editor_window.queue_free()
		toast.emit("Knowledge saved")
	)
	buttons.add_child(save)
	form.add_child(buttons)
	if is_edit:
		var delete := Ui.btn("Delete note", "danger", "trash")
		delete.pressed.connect(func():
			var id := str(existing.id)
			Store.delete_knowledge(id)
			_editor_window.queue_free()
			toast.emit("Note deleted")
		)
		form.add_child(delete)
	_editor_window.popup_centered(Vector2i(650, 920))


func add_from_chat(content: String) -> void:
	var clean := content.strip_edges()
	var title := clean.split("\n", false)[0].strip_edges().trim_prefix("#").strip_edges()
	if title == "": title = "Saved chat answer"
	_open_editor({"title": title.left(120), "content": clean, "tags": ["conversation"]}, "chat")
