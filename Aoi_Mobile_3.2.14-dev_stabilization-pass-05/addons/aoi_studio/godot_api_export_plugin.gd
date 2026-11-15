@tool
extends EditorExportPlugin
## Rebuilds and injects the complete ClassDB snapshot into every exported Aoi build.
const Builder = preload("res://scripts/core/GodotApiSnapshotBuilder.gd")
const SNAPSHOT_PATH := "res://data/godot_api_snapshot.json"

func _get_name() -> String:
	return "AoiGodotApiSnapshot"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var snapshot := Builder.build_snapshot()
	if snapshot.is_empty() or (snapshot.get("classes", {}) as Dictionary).is_empty():
		push_error("Aoi export stopped: Godot API snapshot generation returned no classes.")
		return
	var bytes := JSON.stringify(snapshot).to_utf8_buffer()
	if bytes.is_empty():
		push_error("Aoi export stopped: Godot API snapshot serialization returned no data.")
		return
	add_file(SNAPSHOT_PATH, bytes, false)
	print("AOI_EXPORT_API_SNAPSHOT engine=%s classes=%d bytes=%d" % [str(snapshot.get("engine_version", {}).get("string", "unknown")), int(snapshot.get("class_count", 0)), bytes.size()])


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path == SNAPSHOT_PATH:
		skip()
