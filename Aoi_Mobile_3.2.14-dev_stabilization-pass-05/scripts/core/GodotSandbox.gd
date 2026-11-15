extends Node
## On-device Godot development services. API explorer + constrained scene builder.
## This is not a replacement for the full editor or an arbitrary-script execution sandbox.

const MAX_CLASSES := 1200
const API_SNAPSHOT_PATH := "res://data/godot_api_snapshot.json"
const MAX_SCENE_NODES := 80
const MAX_SCRIPT_BYTES := 256 * 1024
const ALLOWED_NODE_TYPES := [
	"Node", "Node2D", "Control", "CanvasLayer", "Camera2D", "Sprite2D",
	"CharacterBody2D", "StaticBody2D", "RigidBody2D", "Area2D", "CollisionShape2D",
	"CollisionPolygon2D", "Marker2D", "Polygon2D", "ColorRect", "Label", "Button",
	"Panel", "PanelContainer", "VBoxContainer", "HBoxContainer", "MarginContainer",
	"Timer", "AudioStreamPlayer", "AnimationPlayer"
]
const SAFE_PROPERTIES := {
	"Node": {"process_mode": true, "process_priority": true},
	"Node2D": {"position": true, "rotation": true, "scale": true, "z_index": true, "visible": true},
	"Control": {"position": true, "size": true, "visible": true, "rotation": true, "scale": true},
	"CharacterBody2D": {"position": true, "rotation": true, "scale": true, "velocity": true, "motion_mode": true},
	"StaticBody2D": {"position": true, "rotation": true, "scale": true},
	"Area2D": {"position": true, "rotation": true, "scale": true, "monitoring": true, "monitorable": true},
	"Camera2D": {"position": true, "zoom": true, "enabled": true, "position_smoothing_enabled": true},
	"Sprite2D": {"position": true, "scale": true, "rotation": true, "visible": true, "centered": true},
	"ColorRect": {"position": true, "size": true, "color": true, "visible": true},
	"Label": {"position": true, "size": true, "text": true, "visible": true, "horizontal_alignment": true, "vertical_alignment": true},
	"Button": {"position": true, "size": true, "text": true, "disabled": true, "visible": true},
	"Timer": {"wait_time": true, "one_shot": true, "autostart": true}
}

var _class_ids: Array[String] = []
var _details_cache: Dictionary = {}
var _index_ready := false
var _api_snapshot: Dictionary = {}


func ensure_index() -> Dictionary:
	if _index_ready:
		return {"ok": true, "count": _class_ids.size(), "engine": Engine.get_version_info().get("string", "unknown"), "source": "bundled_snapshot" if not _api_snapshot.is_empty() else "live_classdb"}
	_load_api_snapshot()
	if not _api_snapshot.is_empty():
		for class_key in (_api_snapshot.get("classes", {}) as Dictionary).keys():
			_class_ids.append(str(class_key))
		_class_ids.sort()
		_index_ready = true
		return {"ok": true, "count": _class_ids.size(), "engine": str(_api_snapshot.get("engine_version", {}).get("string", Engine.get_version_info().get("string", "unknown"))), "source": "bundled_snapshot"}
	for value in ClassDB.get_class_list():
		var name := str(value)
		if name != "" and not _class_ids.has(name):
			_class_ids.append(name)
	_class_ids.sort()
	if _class_ids.size() > MAX_CLASSES:
		_class_ids.resize(MAX_CLASSES)
	_index_ready = true
	return {"ok": true, "count": _class_ids.size(), "engine": Engine.get_version_info().get("string", "unknown"), "source": "live_classdb"}


func _load_api_snapshot() -> void:
	if not _api_snapshot.is_empty() or not FileAccess.file_exists(API_SNAPSHOT_PATH):
		return
	var json := JSON.new()
	var error := json.parse(FileAccess.get_file_as_string(API_SNAPSHOT_PATH))
	if error != OK or not json.data is Dictionary:
		push_warning("Aoi could not parse the bundled Godot API snapshot; falling back to live ClassDB metadata.")
		return
	var parsed: Dictionary = json.data
	if int(parsed.get("schema_version", 0)) != 1 or not parsed.get("classes", {}) is Dictionary:
		push_warning("Aoi found an unsupported Godot API snapshot schema; falling back to live ClassDB metadata.")
		return
	var snapshot_version: Dictionary = parsed.get("engine_version", {})
	var runtime_version := Engine.get_version_info()
	var version_matches := int(snapshot_version.get("major", -1)) == int(runtime_version.get("major", -2)) and int(snapshot_version.get("minor", -1)) == int(runtime_version.get("minor", -2)) and int(snapshot_version.get("patch", -1)) == int(runtime_version.get("patch", -2)) and str(snapshot_version.get("status", "")) == str(runtime_version.get("status", ""))
	if not version_matches:
		push_warning("Aoi's bundled Godot API snapshot targets %s, but this runtime is %s. Falling back to live ClassDB metadata." % [str(snapshot_version.get("string", "unknown")), str(runtime_version.get("string", "unknown"))])
		return
	_api_snapshot = parsed


func search_classes(query: String, limit: int = 40) -> Array:
	ensure_index()
	var q := query.strip_edges().to_lower()
	var matches: Array[Dictionary] = []
	var snapshot_classes: Dictionary = _api_snapshot.get("classes", {})
	for class_id in _class_ids:
		var normalized := class_id.to_lower()
		var rank := 0
		if q != "":
			if normalized == q:
				rank = 0
			elif normalized.begins_with(q):
				rank = 1
			elif normalized.contains(q):
				rank = 2
			else:
				continue
		var class_record: Dictionary = snapshot_classes.get(class_id, {})
		var parent := str(class_record.get("parent", ClassDB.get_parent_class(class_id) if ClassDB.class_exists(class_id) else ""))
		var instantiable := bool(class_record.get("instantiable", ClassDB.can_instantiate(class_id) if ClassDB.class_exists(class_id) else false))
		matches.append({"rank": rank, "name": class_id, "parent": parent, "instantiable": instantiable})
	matches.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.rank) != int(b.rank): return int(a.rank) < int(b.rank)
		return str(a.name) < str(b.name))
	var out: Array = []
	for row in matches.slice(0, mini(matches.size(), clampi(limit, 1, 100))):
		row.erase("rank")
		out.append(row)
	return out


func inspect_class(class_id: String) -> Dictionary:
	ensure_index()
	var snapshot_classes: Dictionary = _api_snapshot.get("classes", {})
	if not snapshot_classes.has(class_id) and not ClassDB.class_exists(class_id):
		return {"ok": false, "error": "Godot class not found: " + class_id}
	if _details_cache.has(class_id):
		return _details_cache[class_id].duplicate(true)
	if snapshot_classes.has(class_id):
		var snapshot_info := _inspect_snapshot_class(class_id)
		_details_cache[class_id] = snapshot_info
		return snapshot_info.duplicate(true)
	var methods: Array = []
	for method in ClassDB.class_get_method_list(class_id, true):
		var args: Array[String] = []
		for arg in method.get("args", []):
			args.append("%s: %s" % [str(arg.get("name", "arg")), type_string(int(arg.get("type", TYPE_NIL)))])
		methods.append({"name": str(method.get("name", "")), "args": args, "flags": int(method.get("flags", 0))})
	var properties: Array = []
	for property in ClassDB.class_get_property_list(class_id, true):
		properties.append({"name": str(property.get("name", "")), "type": int(property.get("type", TYPE_NIL)), "usage": int(property.get("usage", 0))})
	var signals: Array[String] = []
	for signal_info in ClassDB.class_get_signal_list(class_id, true):
		signals.append(str(signal_info.get("name", "")))
	var result := {"ok": true, "name": class_id, "parent": ClassDB.get_parent_class(class_id), "instantiable": ClassDB.can_instantiate(class_id), "methods": methods, "properties": properties, "signals": signals}
	_details_cache[class_id] = result
	return result.duplicate(true)


func _inspect_snapshot_class(class_id: String) -> Dictionary:
	var classes: Dictionary = _api_snapshot.get("classes", {})
	var base: Dictionary = classes.get(class_id, {})
	var method_map: Dictionary = {}
	var property_map: Dictionary = {}
	var signal_map: Dictionary = {}
	var enum_map: Dictionary = {}
	var constant_map: Dictionary = {}
	var lineage: Array[String] = []
	var cursor := class_id
	var guard := 0
	while cursor != "" and classes.has(cursor) and guard < 64:
		lineage.append(cursor)
		cursor = str(classes[cursor].get("parent", ""))
		guard += 1
	for owner in lineage:
		var record: Dictionary = classes[owner]
		for method in record.get("methods", []):
			var key := str(method.get("name", ""))
			if not method_map.has(key):
				var item: Dictionary = method.duplicate(true)
				item["declared_in"] = owner
				method_map[key] = item
		for property in record.get("properties", []):
			var key := str(property.get("name", ""))
			if not property_map.has(key):
				var item: Dictionary = property.duplicate(true)
				item["declared_in"] = owner
				property_map[key] = item
		for signal_info in record.get("signals", []):
			var key := str(signal_info.get("name", ""))
			if not signal_map.has(key):
				var item: Dictionary = signal_info.duplicate(true)
				item["declared_in"] = owner
				signal_map[key] = item
		for enum_info in record.get("enums", []):
			var key := str(enum_info.get("name", ""))
			if not enum_map.has(key):
				var item: Dictionary = enum_info.duplicate(true)
				item["declared_in"] = owner
				enum_map[key] = item
		for constant in record.get("constants", []):
			var key := str(constant.get("name", ""))
			if not constant_map.has(key):
				var item: Dictionary = constant.duplicate(true)
				item["declared_in"] = owner
				constant_map[key] = item
	var methods: Array = method_map.values()
	var properties: Array = property_map.values()
	var signals: Array = signal_map.values()
	var enums: Array = enum_map.values()
	var constants: Array = constant_map.values()
	methods.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.get("name", "")) < str(b.get("name", "")))
	properties.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.get("name", "")) < str(b.get("name", "")))
	signals.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.get("name", "")) < str(b.get("name", "")))
	return {
		"ok": true,
		"name": class_id,
		"parent": str(base.get("parent", "")),
		"instantiable": bool(base.get("instantiable", false)),
		"exposed": bool(base.get("exposed", true)),
		"api_type": str(base.get("api_type", "")),
		"methods": methods,
		"properties": properties,
		"signals": signals,
		"enums": enums,
		"constants": constants,
		"lineage": lineage,
		"source": "bundled_snapshot"
	}


func search_members(query: String, limit: int = 50) -> Array:
	var q := query.strip_edges().to_lower()
	if q == "":
		return []
	ensure_index()
	var out: Array = []
	for class_id in _class_ids:
		var details := inspect_class(class_id)
		for method in details.get("methods", []):
			if str(method.get("name", "")).to_lower().contains(q):
				out.append({"class": class_id, "kind": "method", "name": method.name})
				if out.size() >= clampi(limit, 1, 100): return out
		for property in details.get("properties", []):
			if str(property.get("name", "")).to_lower().contains(q):
				out.append({"class": class_id, "kind": "property", "name": property.name})
				if out.size() >= clampi(limit, 1, 100): return out
	return out


func validate_gdscript(source: String) -> Dictionary:
	if source.to_utf8_buffer().size() > MAX_SCRIPT_BYTES:
		return {"ok": false, "error": "Script exceeds the 256 KB validation limit.", "stage": "size"}
	var script := GDScript.new()
	script.source_code = source
	var error_code := script.reload(false)
	var result := {"ok": error_code == OK, "error_code": error_code, "stage": "compiler" if error_code != OK else "complete", "message": "Godot accepted the script syntax." if error_code == OK else "Godot could not compile this script. Check engine output for parser diagnostics."}
	script = null
	return result


func is_safe_project_path(relative_path: String) -> bool:
	var clean := relative_path.strip_edges()
	if clean == "" or clean.begins_with("/") or clean.contains("\\") or clean.contains(":"):
		return false
	for part in clean.split("/"):
		if part in ["..", ".", ""]:
			return false
	return true


func write_project_text(project_root: String, relative_path: String, content: String) -> Dictionary:
	if not is_safe_project_path(relative_path):
		return {"ok": false, "error": "Unsafe project-relative path."}
	if content.to_utf8_buffer().size() > MAX_SCRIPT_BYTES:
		return {"ok": false, "error": "Text file exceeds the 256 KB write limit."}
	var absolute_root := ProjectSettings.globalize_path(project_root) if project_root.begins_with("user://") else project_root
	var root := absolute_root.simplify_path().trim_suffix("/")
	var target := root.path_join(relative_path).simplify_path()
	if not target.begins_with(root + "/"):
		return {"ok": false, "error": "Path escaped the project root."}
	var parent_error := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if parent_error != OK and not DirAccess.dir_exists_absolute(target.get_base_dir()):
		return {"ok": false, "error": "Could not create the destination folder."}
	if not Store.write_text_atomic(target, content):
		return {"ok": false, "error": "Could not safely save the project file. The previous copy was preserved where possible."}
	return {"ok": true, "path": relative_path, "bytes": content.to_utf8_buffer().size()}


func create_scene(project_root: String, relative_path: String, blueprint: Dictionary) -> Dictionary:
	if not is_safe_project_path(relative_path) or not relative_path.ends_with(".tscn"):
		return {"ok": false, "error": "Scene path must be a safe project-relative .tscn path."}
	var nodes: Variant = blueprint.get("nodes", [])
	if not nodes is Array or nodes.is_empty() or nodes.size() > MAX_SCENE_NODES:
		return {"ok": false, "error": "Scene must contain between 1 and 80 child nodes."}
	var root_type := str(blueprint.get("root_type", "Node2D"))
	if root_type not in ALLOWED_NODE_TYPES:
		return {"ok": false, "error": "Root node type is not permitted: " + root_type}
	var root := ClassDB.instantiate(root_type) as Node
	if root == null:
		return {"ok": false, "error": "Godot could not instantiate root node."}
	root.name = str(blueprint.get("root_name", "Main")).validate_node_name()
	var created: Array[Node] = [root]
	var name_map := {"root": root}
	for item in nodes:
		if not item is Dictionary:
			root.free(); return {"ok": false, "error": "Invalid node blueprint entry."}
		var node_type := str(item.get("type", "Node2D"))
		if node_type not in ALLOWED_NODE_TYPES:
			root.free(); return {"ok": false, "error": "Node type is not permitted: " + node_type}
		var parent_key := str(item.get("parent", "root"))
		if not name_map.has(parent_key):
			root.free(); return {"ok": false, "error": "Unknown parent node: " + parent_key}
		var node := ClassDB.instantiate(node_type) as Node
		if node == null:
			root.free(); return {"ok": false, "error": "Could not instantiate node type: " + node_type}
		var node_name := str(item.get("name", node_type)).validate_node_name()
		if name_map.has(node_name):
			node.free(); root.free(); return {"ok": false, "error": "Duplicate node name: " + node_name}
		node.name = node_name
		var parent: Node = name_map[parent_key]
		parent.add_child(node)
		node.owner = root
		if node is CollisionShape2D and item.has("shape_kind"):
			var shape_kind := str(item.get("shape_kind", "rectangle"))
			match shape_kind:
				"rectangle":
					var rectangle := RectangleShape2D.new()
					rectangle.size = Vector2(48, 24)
					node.shape = rectangle
				"circle":
					var circle := CircleShape2D.new()
					circle.radius = 16.0
					node.shape = circle
				"capsule":
					var capsule := CapsuleShape2D.new()
					capsule.radius = 12.0
					capsule.height = 40.0
					node.shape = capsule
				_:
					root.free(); return {"ok": false, "error": "Unsupported collision shape: " + shape_kind}
		var props: Variant = item.get("properties", {})
		if not props is Dictionary:
			root.free(); return {"ok": false, "error": "Node properties must be an object."}
		for property_name in props:
			if not _is_property_allowed(node_type, str(property_name)):
				root.free(); return {"ok": false, "error": "Property is not permitted: %s.%s" % [node_type, property_name]}
			if not _set_safe_property(node, str(property_name), props[property_name]):
				root.free(); return {"ok": false, "error": "Invalid value for property: %s.%s" % [node_type, property_name]}
		name_map[node_name] = node
		created.append(node)
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		root.free(); return {"ok": false, "error": "Godot could not pack the scene. Error %d" % pack_error}
	var root_path := ProjectSettings.globalize_path(project_root) if project_root.begins_with("user://") else project_root
	var destination := root_path.path_join(relative_path)
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	var save_error := ResourceSaver.save(packed, destination)
	root.free()
	if save_error != OK:
		return {"ok": false, "error": "Godot could not save the scene. Error %d" % save_error}
	return {"ok": true, "path": relative_path, "nodes": created.size(), "root_type": root_type}


func _is_property_allowed(node_type: String, property_name: String) -> bool:
	return SAFE_PROPERTIES.has(node_type) and SAFE_PROPERTIES[node_type].has(property_name)


func _set_safe_property(node: Node, property_name: String, value: Variant) -> bool:
	var current: Variant = node.get(property_name)
	if current is Vector2 and value is Array and value.size() == 2:
		node.set(property_name, Vector2(float(value[0]), float(value[1])))
	elif current is Color and value is Array and value.size() in [3, 4]:
		node.set(property_name, Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]) if value.size() == 4 else 1.0))
	elif typeof(current) == typeof(value):
		node.set(property_name, value)
	else:
		return false
	return true
