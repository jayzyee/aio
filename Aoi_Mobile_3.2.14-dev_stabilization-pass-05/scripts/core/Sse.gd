extends RefCounted
## Server-sent-events line parser. Feed raw bytes as they arrive; get back complete `data:` payloads.
## Bytes are only decoded once a whole line is present, so multi-byte characters (emoji, Japanese)
## split across network packets are never corrupted.

var _buf := PackedByteArray()


func feed(chunk: PackedByteArray) -> Array:
	_buf.append_array(chunk)
	var out: Array = []
	while true:
		var nl := _buf.find(10)
		if nl < 0: break
		var line := _buf.slice(0, nl).get_string_from_utf8()
		_buf = _buf.slice(nl + 1)
		var p := _payload(line)
		if p != "": out.append(p)
	return out


## Call when the connection closes: a final line without a trailing newline still counts.
func flush() -> Array:
	var out: Array = []
	if _buf.size() > 0:
		var p := _payload(_buf.get_string_from_utf8())
		if p != "": out.append(p)
	_buf = PackedByteArray()
	return out


func _payload(line: String) -> String:
	line = line.trim_suffix("\r")
	if not line.begins_with("data:"): return ""   # comments (":") and other fields are ignored
	return line.substr(5).strip_edges()
