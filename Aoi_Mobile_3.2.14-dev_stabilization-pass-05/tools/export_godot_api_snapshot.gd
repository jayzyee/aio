extends SceneTree
## Manually refresh the development snapshot; the EditorExportPlugin regenerates it during actual exports.
const Builder = preload("res://scripts/core/GodotApiSnapshotBuilder.gd")
const OUTPUT_PATH := "res://data/godot_api_snapshot.json"

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot := Builder.build_snapshot()
	if snapshot.is_empty() or (snapshot.get("classes", {}) as Dictionary).is_empty():
		push_error("Godot API snapshot generation returned no classes.")
		quit(1)
		return
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write Godot API snapshot: %s" % OUTPUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(snapshot))
	file.close()
	var written_bytes := FileAccess.get_file_as_bytes(OUTPUT_PATH).size()
	print("AOI_GODOT_API_SNAPSHOT_WRITTEN engine=%s classes=%d bytes=%d path=%s" % [str(snapshot.get("engine_version", {}).get("string", "unknown")), int(snapshot.get("class_count", 0)), written_bytes, OUTPUT_PATH])
	quit(0)
