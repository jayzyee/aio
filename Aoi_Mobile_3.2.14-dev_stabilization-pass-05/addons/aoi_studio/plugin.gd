@tool
extends EditorPlugin

const DockScript = preload("res://addons/aoi_studio/dock.gd")
const ApiExportPlugin = preload("res://addons/aoi_studio/godot_api_export_plugin.gd")
var _dock: Control
var _api_export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_dock = DockScript.new()
	_dock.name = "Aoi Studio"
	_dock.plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_api_export_plugin = ApiExportPlugin.new()
	add_export_plugin(_api_export_plugin)


func _exit_tree() -> void:
	if _dock != null and is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.queue_free()
	_dock = null
	if _api_export_plugin != null:
		remove_export_plugin(_api_export_plugin)
		_api_export_plugin = null


func run_main_scene() -> void:
	EditorInterface.play_main_scene()


func stop_scene() -> void:
	EditorInterface.stop_playing_scene()


func capture_viewport(kind: String) -> String:
	var viewport: SubViewport
	if kind == "3d":
		viewport = EditorInterface.get_editor_viewport_3d()
	else:
		viewport = EditorInterface.get_editor_viewport_2d()
	if viewport == null:
		return "The requested editor viewport is unavailable."
	var texture := viewport.get_texture()
	if texture == null:
		return "The editor viewport has no render texture yet."
	var image := texture.get_image()
	if image == null or image.is_empty():
		return "The editor viewport has not rendered a frame yet."
	var folder := "res://.aoi_studio/screenshots"
	var absolute := ProjectSettings.globalize_path(folder)
	DirAccess.make_dir_recursive_absolute(absolute)
	var file_name := "%s_%d.png" % [kind, int(Time.get_unix_time_from_system())]
	var output := folder.path_join(file_name)
	var error := image.save_png(output)
	if error != OK:
		return "Could not save screenshot (error %d)." % error
	return output


func add_source_files(paths: PackedStringArray) -> Array[String]:
	var destination := "res://aoi_sources"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
	var copied: Array[String] = []
	for source_path in paths:
		var source := FileAccess.open(source_path, FileAccess.READ)
		if source == null:
			continue
		var bytes := source.get_buffer(source.get_length())
		source.close()
		var base := source_path.get_file().validate_filename()
		var target := destination.path_join(base)
		var stem := target.get_basename()
		var ext := target.get_extension()
		var suffix := 2
		while FileAccess.file_exists(target):
			target = "%s_%d.%s" % [stem, suffix, ext]
			suffix += 1
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			continue
		out.store_buffer(bytes)
		out.close()
		copied.append(target)
	EditorInterface.get_resource_filesystem().scan()
	return copied
