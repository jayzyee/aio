extends Control

const STORY_PATH := "res://stories/demo.json"
const SAVE_PATH := "user://savegame.json"

var story_nodes: Dictionary = {}
var current_node_id := ""
var background: TextureRect
var portrait: TextureRect
var character_name: Label
var dialogue_text: Label
var continue_button: Button
var choices_box: VBoxContainer
var status_label: Label


func _ready() -> void:
	_build_interface()
	_load_story(STORY_PATH)


func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	background = TextureRect.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.025, 0.055, 0.28)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.anchor_left = 0.12
	portrait.anchor_top = 0.035
	portrait.anchor_right = 0.88
	portrait.anchor_bottom = 0.72
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait)

	var panel := PanelContainer.new()
	panel.name = "DialoguePanel"
	panel.anchor_left = 0.035
	panel.anchor_top = 0.69
	panel.anchor_right = 0.965
	panel.anchor_bottom = 0.975
	add_child(panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.045, 0.085, 0.96)
	panel_style.border_color = Color(0.48, 0.74, 0.94, 0.72)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(20)
	panel_style.content_margin_left = 22
	panel_style.content_margin_right = 22
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", panel_style)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	panel.add_child(layout)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	layout.add_child(heading)

	character_name = Label.new()
	character_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_name.add_theme_font_size_override("font_size", 24)
	character_name.add_theme_color_override("font_color", Color(0.62, 0.84, 1.0))
	heading.add_child(character_name)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override("font_color", Color(0.72, 0.83, 0.9))
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(status_label)

	var save_button := _make_button("Save")
	save_button.custom_minimum_size = Vector2(84, 46)
	save_button.pressed.connect(_save_game)
	heading.add_child(save_button)

	var load_button := _make_button("Load")
	load_button.custom_minimum_size = Vector2(84, 46)
	load_button.pressed.connect(_load_game)
	heading.add_child(load_button)

	dialogue_text = Label.new()
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue_text.add_theme_font_size_override("font_size", 22)
	dialogue_text.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	layout.add_child(dialogue_text)

	choices_box = VBoxContainer.new()
	choices_box.add_theme_constant_override("separation", 8)
	layout.add_child(choices_box)

	continue_button = _make_button("Continue  ›")
	continue_button.custom_minimum_size = Vector2(0, 52)
	continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	continue_button.pressed.connect(_advance)
	layout.add_child(continue_button)


func _make_button(caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.22, 0.36, 0.98)
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.34, 0.52, 1.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button


func _load_story(path: String) -> void:
	if not FileAccess.file_exists(path):
		_show_error("Story file not found: " + path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_show_error("Could not open story: " + error_string(FileAccess.get_open_error()))
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_show_error("Story must contain a JSON object.")
		return
	if not parsed.get("nodes", null) is Array:
		_show_error("Story is missing its nodes array.")
		return

	var candidate_nodes: Dictionary = {}
	for item in parsed["nodes"]:
		if not item is Dictionary or not item.get("id", null) is String:
			_show_error("Every story node must have a string id.")
			return
		var node_id := str(item["id"])
		if node_id.is_empty() or candidate_nodes.has(node_id):
			_show_error("Story node ids must be non-empty and unique.")
			return
		candidate_nodes[node_id] = item

	var start_id: Variant = parsed.get("start", null)
	if not start_id is String or not candidate_nodes.has(start_id):
		_show_error("Story start must reference an existing node.")
		return
	var start_node_id := str(start_id)

	for node_id in candidate_nodes:
		var node: Dictionary = candidate_nodes[node_id]
		if not node.get("text", null) is String:
			_show_error("Every story node needs dialogue text: " + node_id)
			return
		if not node.get("choices", []) is Array:
			_show_error("Choices must be an array in node: " + node_id)
			return
		var next_id: Variant = node.get("next", "")
		if next_id != "" and (not next_id is String or not candidate_nodes.has(next_id)):
			_show_error("Node has an invalid next target: " + node_id)
			return
		for choice in node.get("choices", []):
			if not choice is Dictionary or not choice.get("next", null) is String:
				_show_error("Every choice needs a label and next target in node: " + node_id)
				return
			if not candidate_nodes.has(choice["next"]) or not choice.get("text", null) is String:
				_show_error("Choice has an invalid label or target in node: " + node_id)
				return

	story_nodes = candidate_nodes
	current_node_id = start_node_id
	_show_node(current_node_id)


func _show_node(node_id: String) -> void:
	if not story_nodes.has(node_id):
		_show_error("Story node not found: " + node_id)
		return
	current_node_id = node_id
	var node: Dictionary = story_nodes[node_id]
	character_name.text = str(node.get("character", ""))
	dialogue_text.text = str(node.get("text", ""))
	status_label.text = ""
	_set_texture(background, str(node.get("background", "")))
	_set_texture(portrait, str(node.get("portrait", "")))

	for child in choices_box.get_children():
		child.queue_free()

	var choices: Array = node.get("choices", [])
	continue_button.visible = choices.is_empty()
	continue_button.disabled = str(node.get("next", "")).is_empty()
	continue_button.text = "Continue  ›" if not continue_button.disabled else "The End"
	for choice in choices:
		var button := _make_button(str(choice.get("text", "Continue")))
		button.custom_minimum_size = Vector2(0, 50)
		var target_id := str(choice["next"])
		button.pressed.connect(_show_node.bind(target_id))
		choices_box.add_child(button)


func _set_texture(target: TextureRect, resource_path: String) -> void:
	if resource_path.is_empty():
		target.texture = null
		return
	var loaded: Resource = load(resource_path)
	if loaded is Texture2D:
		target.texture = loaded
	else:
		target.texture = null
		status_label.text = "Image not found: " + resource_path


func _advance() -> void:
	var node: Dictionary = story_nodes.get(current_node_id, {})
	var next_id: String = str(node.get("next", ""))
	if not next_id.is_empty():
		_show_node(next_id)
	else:
		status_label.text = "End of story."


func _save_game() -> void:
	if current_node_id.is_empty():
		status_label.text = "No story progress to save."
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		status_label.text = "Save failed: " + error_string(FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify({"version": 1, "story": STORY_PATH, "node": current_node_id}))
	status_label.text = "Game saved."


func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		status_label.text = "No save found yet."
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		status_label.text = "Load failed: " + error_string(FileAccess.get_open_error())
		return
	var saved: Variant = JSON.parse_string(file.get_as_text())
	if not saved is Dictionary or saved.get("version", null) != 1:
		status_label.text = "Save file is invalid or from an unsupported version."
		return
	var saved_node: Variant = saved.get("node", null)
	if not saved_node is String or not story_nodes.has(saved_node):
		status_label.text = "Save does not match the loaded story."
		return
	_show_node(str(saved_node))
	status_label.text = "Game loaded."


func _show_error(message: String) -> void:
	status_label.text = message
	push_error(message)
