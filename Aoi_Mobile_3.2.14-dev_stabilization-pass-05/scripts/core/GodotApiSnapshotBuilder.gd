extends RefCounted
## Builds a self-contained Godot ClassDB snapshot from the active editor engine.
## Called by Aoi's EditorExportPlugin so exported builds retain full member metadata.

static func build_snapshot() -> Dictionary:
	var class_labels := ClassDB.get_class_list()
	class_labels.sort()
	var classes: Dictionary = {}
	for class_label in class_labels:
		var class_id := str(class_label)
		if class_id.is_empty():
			continue
		classes[class_id] = {
			"name": class_id,
			"parent": str(ClassDB.get_parent_class(class_id)),
			"instantiable": ClassDB.can_instantiate(class_id),
			"exposed": ClassDB.is_class_exposed(class_id),
			"api_type": str(ClassDB.class_get_api_type(class_id)),
			"methods": _method_records(class_id),
			"properties": _property_records(class_id),
			"signals": _signal_records(class_id),
			"enums": _enum_records(class_id),
			"constants": _constant_records(class_id)
		}
	return {
		"schema_version": 1,
		"engine_version": Engine.get_version_info(),
		"generated_at": Time.get_datetime_string_from_system(true),
		"class_count": classes.size(),
		"member_scope": "declared_only; inherited members are resolved from parent classes at runtime",
		"classes": classes
	}


static func _method_records(class_id: String) -> Array:
	var output: Array = []
	for method in ClassDB.class_get_method_list(class_id, true):
		var args: Array = []
		for argument in method.get("args", []):
			args.append(_argument_record(argument))
		output.append({
			"name": str(method.get("name", "")),
			"args": args,
			"default_args": _string_values(method.get("default_args", [])),
			"return": _argument_record(method.get("return", {})),
			"flags": int(method.get("flags", 0)),
			"id": int(method.get("id", -1))
		})
	return output


static func _property_records(class_id: String) -> Array:
	var output: Array = []
	for property in ClassDB.class_get_property_list(class_id, true):
		var property_type := int(property.get("type", TYPE_NIL))
		output.append({
			"name": str(property.get("name", "")),
			"type": property_type,
			"type_name": type_string(property_type),
			"class_name": str(property.get("class_name", "")),
			"hint": int(property.get("hint", 0)),
			"hint_string": str(property.get("hint_string", "")),
			"usage": int(property.get("usage", 0)),
			"read_only": (int(property.get("usage", 0)) & PROPERTY_USAGE_READ_ONLY) != 0
		})
	return output


static func _signal_records(class_id: String) -> Array:
	var output: Array = []
	for signal_info in ClassDB.class_get_signal_list(class_id, true):
		var args: Array = []
		for argument in signal_info.get("args", []):
			args.append(_argument_record(argument))
		output.append({"name": str(signal_info.get("name", "")), "args": args})
	return output


static func _enum_records(class_id: String) -> Array:
	var output: Array = []
	for enum_name in ClassDB.class_get_enum_list(class_id, true):
		var values: Array = []
		for constant_name in ClassDB.class_get_enum_constants(class_id, str(enum_name), true):
			values.append({"name": str(constant_name), "value": ClassDB.class_get_integer_constant(class_id, str(constant_name))})
		output.append({"name": str(enum_name), "values": values, "bitfield": ClassDB.is_class_enum_bitfield(class_id, str(enum_name), true)})
	return output


static func _constant_records(class_id: String) -> Array:
	var output: Array = []
	for constant_name in ClassDB.class_get_integer_constant_list(class_id, true):
		output.append({"name": str(constant_name), "value": ClassDB.class_get_integer_constant(class_id, str(constant_name))})
	return output


static func _argument_record(argument: Dictionary) -> Dictionary:
	var type_id := int(argument.get("type", TYPE_NIL))
	return {
		"name": str(argument.get("name", "")),
		"type": type_id,
		"type_name": type_string(type_id),
		"class_name": str(argument.get("class_name", "")),
		"hint": int(argument.get("hint", 0)),
		"hint_string": str(argument.get("hint_string", "")),
		"usage": int(argument.get("usage", 0))
	}


static func _string_values(values: Variant) -> Array:
	var output: Array = []
	if values is Array:
		for value in values:
			output.append(str(value))
	return output
