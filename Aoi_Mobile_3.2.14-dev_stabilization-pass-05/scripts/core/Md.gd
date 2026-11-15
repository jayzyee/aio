extends RefCounted
## Markdown -> BBCode for the conversation's Inter-based typographic system.
## Headings, emphasis, links and code have deliberate hierarchy without introducing
## another display font or changing the source Markdown stored in the conversation.
## A literal "[" is written as [lb] (Godot's escape), never "[[".

static var _bold: RegEx
static var _ital: RegEx
static var _code: RegEx
static var _link: RegEx
static var _ready := false

static func _init_regex() -> void:
	if _ready:
		return
	_bold = RegEx.new()
	_bold.compile("\\*\\*(.+?)\\*\\*")
	_ital = RegEx.new()
	_ital.compile("(?<![\\w*])[*_]([^*_\\n]+?)[*_](?![\\w*])")
	_code = RegEx.new()
	_code.compile("`([^`\\n]+)`")
	_link = RegEx.new()
	_link.compile("\\[lb\\]([^\\]]+)\\]\\((https?://[^)\\s]+)\\)")
	_ready = true

static func escape(text: String) -> String:
	return text.replace("[", "[lb]")

static func inline(text: String) -> String:
	_init_regex()
	var value := escape(text)
	value = _link.sub(value, "[url=$2][color=#242424][u]$1[/u][/color][/url]", true)
	value = _code.sub(value, "[bgcolor=#f2f2f2][color=#343434][code]$1[/code][/color][/bgcolor]", true)
	value = _bold.sub(value, "[b][color=#171717]$1[/color][/b]", true)
	value = _ital.sub(value, "[i][color=#555555]$1[/color][/i]", true)
	return value

static func to_bbcode(markdown: String) -> String:
	var output: Array[String] = []
	var lines := markdown.replace("\r", "").split("\n")
	var in_fence := false
	var i := 0
	while i < lines.size():
		var line: String = lines[i]
		var trimmed := line.strip_edges()
		if trimmed.begins_with("```"):
			in_fence = not in_fence
			if in_fence:
				output.append("[color=#343434][font_size=21][code]")
			else:
				output.append("[/code][/font_size][/color]")
			i += 1
			continue
		if in_fence:
			output.append(escape(line))
			i += 1
			continue
		# Render GFM tables as compact, vertically stacked labelled records.
		# This deliberately avoids a tiny horizontally clipped grid on phones.
		if i + 1 < lines.size() and "|" in line and _is_table_separator(str(lines[i + 1])):
			var headers := _split_table_row(line)
			var records: Array[String] = []
			i += 2
			while i < lines.size() and "|" in str(lines[i]) and str(lines[i]).strip_edges() != "":
				var values := _split_table_row(str(lines[i]))
				while values.size() < headers.size(): values.append("")
				if not values.is_empty():
					var record := "[b][color=#171717]" + inline(values[0]) + "[/color][/b]"
					if headers.size() == 2:
						if str(values[1]).strip_edges() != "": record += "\n" + inline(values[1])
					else:
						for column in range(1, headers.size()):
							var value := str(values[column]).strip_edges()
							if value == "": continue
							record += "\n[color=#777777]" + inline(str(headers[column])) + ":[/color] " + inline(value)
					records.append(record)
				i += 1
			if not records.is_empty(): output.append("\n\n".join(records))
			continue
		if trimmed.begins_with("### "):
			output.append("[font_size=25][b][color=#171717]" + inline(trimmed.substr(4)) + "[/color][/b][/font_size]")
		elif trimmed.begins_with("## "):
			output.append("[font_size=29][b][color=#171717]" + inline(trimmed.substr(3)) + "[/color][/b][/font_size]")
		elif trimmed.begins_with("# "):
			output.append("[font_size=34][b][color=#111111]" + inline(trimmed.substr(2)) + "[/color][/b][/font_size]")
		elif trimmed.begins_with("- [ ] ") or trimmed.begins_with("* [ ] "):
			output.append("[color=#888888]◯[/color]  " + inline(trimmed.substr(6)))
		elif trimmed.begins_with("- [x] ") or trimmed.begins_with("- [X] "):
			output.append("[color=#548b79]✓[/color]  " + inline(trimmed.substr(6)))
		elif trimmed.begins_with("- ") or trimmed.begins_with("* "):
			output.append("[color=#888888]•[/color]  " + inline(trimmed.substr(2)))
		elif trimmed.begins_with("> "):
			output.append("[color=#888888]▏[/color]  [i][color=#555555]" + inline(trimmed.substr(2)) + "[/color][/i]")
		elif trimmed == "---":
			output.append("[color=#e5e5e5]────────────────────────[/color]")
		else:
			output.append(inline(trimmed))
		i += 1
	if in_fence:
		output.append("[/code][/font_size][/color]")
	return "\n".join(output)

static func to_plain_text(markdown: String) -> String:
	var output: Array[String] = []
	var in_fence := false
	_init_regex()
	for raw_line in markdown.replace("\r", "").split("\n"):
		var line := str(raw_line).strip_edges()
		if line.begins_with("```"):
			if not in_fence:
				output.append("Code block omitted.")
			in_fence = not in_fence
			continue
		if in_fence or line == "" or line == "---":
			continue
		for heading in ["### ", "## ", "# "]:
			if line.begins_with(heading):
				line = line.substr(heading.length())
				break
		if _is_table_separator(line):
			continue
		if "|" in line:
			line = ", ".join(_split_table_row(line))
		line = line.trim_prefix("- [ ] ").trim_prefix("- [x] ").trim_prefix("- [X] ")
		line = line.trim_prefix("* [ ] ").trim_prefix("* [x] ").trim_prefix("* [X] ")
		line = line.trim_prefix("- ").trim_prefix("* ").trim_prefix("> ")
		var link := RegEx.new()
		link.compile("!?\\[([^\\]]+)\\]\\([^)]+\\)")
		line = link.sub(line, "$1", true)
		line = _bold.sub(line, "$1", true)
		line = _ital.sub(line, "$1", true)
		line = _code.sub(line, "$1", true)
		output.append(line)
	return "\n".join(output).strip_edges()

static func _split_table_row(line: String) -> Array[String]:
	var source := line.strip_edges()
	if source.begins_with("|"): source = source.substr(1)
	if source.ends_with("|"): source = source.left(source.length() - 1)
	var cells: Array[String] = []
	var cell := ""
	var i := 0
	while i < source.length():
		var ch := source.substr(i, 1)
		if ch == "\\" and i + 1 < source.length() and source.substr(i + 1, 1) == "|":
			cell += "|"
			i += 2
			continue
		if ch == "|":
			cells.append(cell.strip_edges())
			cell = ""
		else:
			cell += ch
		i += 1
	cells.append(cell.strip_edges())
	return cells


static func _is_table_separator(line: String) -> bool:
	if "|" not in line: return false
	var cells := _split_table_row(line)
	if cells.is_empty(): return false
	for cell in cells:
		var marks := cell.replace(":", "").strip_edges()
		if marks.length() < 3 or marks.replace("-", "") != "":
			return false
	return true

## Checklist items ("- [ ] text") found in Markdown, for turning an AI plan into project tasks.
static func checklist_items(markdown: String) -> Array:
	var items: Array = []
	for raw in markdown.replace("\r", "").split("\n"):
		var value: String = (raw as String).strip_edges()
		if value.begins_with("- [ ] ") or value.begins_with("* [ ] "):
			items.append(value.substr(6).strip_edges())
	return items
