@tool
extends VBoxContainer

var plugin: EditorPlugin
var _status: Label
var _file_dialog: EditorFileDialog
var _run_started := false


func _ready() -> void:
	custom_minimum_size.x = 280
	add_theme_constant_override("separation", 9)
	_build()


func _build() -> void:
	var heading := Label.new()
	heading.text = "AOI STUDIO"
	heading.add_theme_font_size_override("font_size", 19)
	heading.add_theme_color_override("font_color", Color("#dce5ff"))
	add_child(heading)
	var subtitle := Label.new()
	subtitle.text = "Godot project companion"
	subtitle.add_theme_color_override("font_color", Color("#9da9bf"))
	add_child(subtitle)
	var rule := HSeparator.new()
	add_child(rule)
	var project_label := Label.new()
	project_label.text = "CURRENT PROJECT"
	project_label.add_theme_font_size_override("font_size", 11)
	project_label.add_theme_color_override("font_color", Color("#91a0bc"))
	add_child(project_label)
	var root := Label.new()
	root.text = ProjectSettings.globalize_path("res://")
	root.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_theme_font_size_override("font_size", 12)
	add_child(root)
	_status = Label.new()
	_status.text = "Editor ready · project not running"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color("#a9b7ce"))
	add_child(_status)
	var run := Button.new()
	run.text = "▶  Run main scene"
	run.pressed.connect(_run_project)
	add_child(run)
	var stop := Button.new()
	stop.text = "■  Stop running scene"
	stop.pressed.connect(_stop_project)
	add_child(stop)
	var files := Button.new()
	files.text = "+  Add source files"
	files.pressed.connect(_choose_sources)
	add_child(files)
	var capture_2d := Button.new()
	capture_2d.text = "Capture 2D editor viewport"
	capture_2d.pressed.connect(func(): _capture("2d"))
	add_child(capture_2d)
	var capture_3d := Button.new()
	capture_3d.text = "Capture 3D editor viewport"
	capture_3d.pressed.connect(func(): _capture("3d"))
	add_child(capture_3d)
	var refresh := Button.new()
	refresh.text = "Refresh project filesystem"
	refresh.pressed.connect(func():
		EditorInterface.get_resource_filesystem().scan()
		_status.text = "Filesystem scan requested.")
	add_child(refresh)
	var note := Label.new()
	note.text = "Aoi Mobile can pair with the PC companion to inspect files, send approved edits, run verification and collect Godot logs. This dock controls the local editor directly."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color("#9da9bf"))
	add_child(note)
	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILES
	_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_file_dialog.files_selected.connect(_on_sources_selected)
	add_child(_file_dialog)


func _run_project() -> void:
	if plugin == null:
		_status.text = "Editor plugin reference is unavailable."
		return
	plugin.run_main_scene()
	_run_started = true
	_status.text = "Run requested · game is running in the editor debug session."


func _stop_project() -> void:
	if plugin == null:
		return
	plugin.stop_scene()
	_run_started = false
	_status.text = "Stop requested · editor debug session stopped."


func _choose_sources() -> void:
	_file_dialog.popup_file_dialog()


func _on_sources_selected(paths: PackedStringArray) -> void:
	var copied: Array[String] = plugin.add_source_files(paths) if plugin != null else []
	_status.text = "%d source file(s) copied to res://aoi_sources." % copied.size()


func _capture(kind: String) -> void:
	if plugin == null:
		return
	var result: String = plugin.capture_viewport(kind)
	_status.text = "Screenshot saved: " + result if result.begins_with("res://") else result
