extends Node

var _failures := 0

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Store.set_root("user://aoi_preferences_behavior_probe/")
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_fail("Main scene could not be loaded")
		_finish()
		return
	var main := packed.instantiate()
	add_child(main)
	for _frame in range(3): await get_tree().process_frame
	main.go("setup")
	await get_tree().process_frame

	var expected := FileAccess.get_file_as_string("res://data/global_working_preferences.md")
	var workspace := Store.get_integration("workspace")
	var saved := str(workspace.get("working_preferences", ""))
	_check("complete global standards loaded into Aoi preferences", saved == expected and saved.length() > 7000)
	var preview := main.setup.find_child("GlobalWorkingPreferencesPreview", true, false) as RichTextLabel
	_check("global standards are presented as readable content instead of raw Markdown", preview != null and not preview.text.contains("**") and not preview.text.begins_with("# "))
	var edit_button := main.setup.find_child("EditGlobalWorkingPreferences", true, false) as Button
	_check("global standards have a dedicated edit action", edit_button != null)
	if edit_button != null:
		edit_button.pressed.emit()
		await get_tree().process_frame
		var editor_window: Window = null
		for child in main.setup.get_children():
			if child is Window and str(child.title).contains("global working preferences"): editor_window = child
		var editor := editor_window.find_child("GlobalWorkingPreferencesEditor", true, false) as TextEdit if editor_window != null else null
		_check("the edit action opens the full global standards source", editor != null and editor.text == expected)
		if editor != null:
			editor.text = "Edited global standard survives saving."
			var save_button: Button = null
			for child in editor_window.find_children("*", "Button", true, false):
				if str((child as Button).text) == "Save standards": save_button = child
			_check("the dedicated editor exposes a save action", save_button != null)
			if save_button != null:
				save_button.pressed.emit()
				await get_tree().process_frame
				_check("the dedicated editor persists global standards", str(Store.get_integration("workspace").get("working_preferences", "")) == "Edited global standard survives saving.")

	workspace = Store.get_integration("workspace")
	workspace["working_preferences"] = expected
	Store.set_integration("workspace", workspace)
	var prompt_history: Array = main.chat._history()
	var system_text := str(prompt_history[0].get("content", "")) if not prompt_history.is_empty() else ""
	_check("full global standard reaches the actual chat system context", system_text.contains("User intent:") and system_text.contains("Unforgivable failure patterns") and system_text.length() > 7000)

	var vision_id := ""
	for item in Store.list_knowledge():
		if str(item.get("title", "")) == "Aoi workspace vision":
			vision_id = str(item.get("id", ""))
			_check("workspace vision is stored as a global Goals & ambitions reference", str(item.get("source", "")) == "workspace_reference" and str(item.get("category", "")) == "Goals & ambitions" and str(item.get("content", "")).contains("general-purpose AI workspace"))
			break
	_check("workspace vision reference is available", vision_id != "")
	var vision_record := Store.get_knowledge(vision_id)
	var vision_card_preview: String = str(main.knowledge._plain_preview(str(vision_record.get("content", "")), 240))
	_check("knowledge cards convert Markdown headings and emphasis into clean preview text", not vision_card_preview.begins_with("#") and not vision_card_preview.contains("**") and vision_card_preview.contains("general-purpose AI workspace"))

	var picker := main.setup.find_child("GlobalReferenceCategoryFilter", true, false) as OptionButton
	_check("global reference categories are available in Preferences", picker != null)
	if picker != null:
		var goals_index := -1
		for i in range(picker.item_count):
			if str(picker.get_item_metadata(i)) == "Goals & ambitions": goals_index = i
		_check("Goals & ambitions category is selectable", goals_index >= 0)
		if goals_index >= 0:
			picker.select(goals_index)
			picker.item_selected.emit(goals_index)
			await get_tree().process_frame
			_check("category filtering shows the workspace vision", _tree_contains_text(main.setup, "Aoi workspace vision"))

	# A custom preference saved by the user must survive subsequent Preferences renders.
	workspace = Store.get_integration("workspace")
	workspace["working_preferences"] = "Keep this custom global preference intact."
	Store.set_integration("workspace", workspace)
	main.setup.render()
	await get_tree().process_frame
	_check("user-edited global preferences are not overwritten by defaults", str(Store.get_integration("workspace").get("working_preferences", "")) == "Keep this custom global preference intact.")

	# Returning to the full standards proves the context and migration remain reusable.
	workspace = Store.get_integration("workspace")
	workspace["working_preferences"] = expected
	Store.set_integration("workspace", workspace)
	var after_repeat := Store.list_knowledge()
	var vision_count := 0
	for item in after_repeat:
		if str(item.get("title", "")) == "Aoi workspace vision": vision_count += 1
	_check("re-rendering Preferences does not duplicate built-in references", vision_count == 1)

	_finish()


func _tree_contains_text(node: Node, needle: String) -> bool:
	if node is Label and needle in str((node as Label).text): return true
	for child in node.get_children():
		if _tree_contains_text(child, needle): return true
	return false


func _check(label: String, condition: bool) -> void:
	if condition:
		print("PREF_BEHAVIOR_OK ", label)
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failures += 1
	push_error("PREF_BEHAVIOR_FAIL " + label)


func _finish() -> void:
	print("PREF_BEHAVIOR_RESULT ", "OK" if _failures == 0 else "FAILED", " failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
