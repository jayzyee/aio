extends Node
# A finger swipe that STARTS on different widgets must scroll the page (regression: swipes selected text / were swallowed).
var results: Array = []
var main: Control

func _ready() -> void:
	main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await _wait(1.2)
	var chat = main.chat
	# long chat so it can scroll
	for i in range(6):
		(chat.session["messages"] as Array).append({"role": "user", "content": "question %d" % i})
		(chat.session["messages"] as Array).append({"role": "assistant", "content": "Answer %d. " % i + "This is a fairly long answer that wraps over several lines so the page is tall enough to scroll. ".repeat(3)})
	chat._render()
	await _wait(0.8)
	var sc: ScrollContainer = chat._scroll
	var chat_bar := sc.get_v_scroll_bar()
	sc.scroll_vertical = int(chat_bar.max_value)
	await _wait(0.2)
	_check("S0_chat_follows_when_reader_is_at_bottom", chat.should_follow_bottom())
	sc.scroll_vertical = 0
	await _wait(0.2)
	_check("S0A_chat_preserves_position_when_reader_is_older", not chat.should_follow_bottom())
	await _wait(0.2)
	# swipe starting on an assistant message (RichTextLabel)
	var target := _find_rich(chat._msgs)
	var start := target.get_global_rect().get_center() if target != null else Vector2(300, 600)
	var moved := await _swipe(sc, Vector2(clampf(start.x, 60, 660), 700.0))
	_check("S1_swipe_on_reply_text_scrolls_chat", moved > 150, moved)
	_check("S2_no_text_gets_selected", target == null or target.get_selected_text() == "", target.get_selected_text() if target != null else "")
	# swipe starting on a user bubble
	sc.scroll_vertical = 0
	await _wait(0.2)
	var ub := _find_user_bubble(chat._msgs)
	var m2 := await _swipe(sc, ub.get_global_rect().get_center() if ub != null else Vector2(500, 300))
	_check("S3_swipe_on_user_bubble_scrolls_chat", m2 > 150, m2)
	# Setup: swipe starting on a card background and on a button
	main.go("setup")
	await _wait(0.6)
	var ss: ScrollContainer = main.setup
	var m3 := await _swipe(ss, Vector2(360, 250))
	_check("S4_swipe_on_card_scrolls_setup", m3 > 150, m3)
	ss.scroll_vertical = 0
	await _wait(0.2)
	var btn := _find_button(ss, "Save & test")
	var m4 := await _swipe(ss, btn.get_global_rect().get_center() if btn != null else Vector2(360, 700))
	_check("S5_swipe_starting_on_a_button_scrolls_setup", m4 > 150, m4)
	# Projects: swipe on a card / the notes text
	var p := Store.new_project("Long project", "goal")
	for i in range(24): Store.add_task(p, "Task number %d with some words" % i)
	p["notes"] = "## Notes\n" + "A line of notes that is long enough to wrap around the screen a bit.\n".repeat(10)
	Store.save_project(p)
	main.go("projects")
	main.projects.open_project(str(p["id"]))
	# Project Home is intentionally compact when no deliverable exists. Exercise
	# finger scrolling on the expanded, genuinely long Work details view instead.
	main.projects._show_work_details = true
	main.projects.render()
	await _wait(0.8)
	var ps: ScrollContainer = main.projects._scroll
	var notes := _find_rich(main.projects)
	var m5 := await _swipe(ps, notes.get_global_rect().get_center() if notes != null and notes.is_visible_in_tree() and notes.get_global_rect().get_center().y < 1100 else Vector2(360, 800))
	_check("S6_swipe_on_project_page_scrolls", m5 > 150, m5)
	var bad := 0
	for r in results: if not r[1]: bad += 1
	print("SCROLL_SUMMARY ", results.size() - bad, "/", results.size(), " passed")
	get_tree().quit(1 if bad > 0 else 0)

func _swipe(sc: ScrollContainer, from: Vector2) -> int:
	# A real finger: touch down, drag events, touch up (what Android delivers). parse_input_event also applies
	# the same touch->mouse emulation the phone has, so buttons/labels see exactly what they would on device.
	var before := sc.scroll_vertical
	var down := InputEventScreenTouch.new()
	down.device = 0; down.index = 0; down.pressed = true; down.position = from
	Input.parse_input_event(down)
	await get_tree().process_frame
	var pos := from
	for i in range(20):
		var d := InputEventScreenDrag.new()
		d.device = 0; d.index = 0
		var nxt := pos + Vector2(0, -24)
		d.position = nxt; d.relative = nxt - pos; d.velocity = Vector2(0, -900)
		Input.parse_input_event(d)
		pos = nxt
		await get_tree().process_frame
	var up := InputEventScreenTouch.new()
	up.device = 0; up.index = 0; up.pressed = false; up.position = pos
	Input.parse_input_event(up)
	await _wait(0.5)
	return sc.scroll_vertical - before

func _find_rich(n: Node) -> RichTextLabel:
	if n is RichTextLabel and (n as Control).is_visible_in_tree() and (n as RichTextLabel).get_parsed_text().length() > 40: return n
	for c in n.get_children():
		var r := _find_rich(c)
		if r != null: return r
	return null

func _find_user_bubble(n: Node) -> Control:
	# a user bubble that is actually on screen (center between the chips and the composer)
	if n is PanelContainer and n.get_child_count() > 0 and n.get_child(0) is Label and (n as Control).is_visible_in_tree():
		var y := (n as Control).get_global_rect().get_center().y
		if y > 330 and y < 1000: return n
	for c in n.get_children():
		var r := _find_user_bubble(c)
		if r != null: return r
	return null

func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text and (n as Control).is_visible_in_tree(): return n
	for c in n.get_children():
		var r := _find_button(c, text)
		if r != null: return r
	return null

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _check(n: String, ok: bool, detail: Variant = null) -> void:
	results.append([n, ok]); print("SCROLL_", n, " ", "PASS" if ok else "FAIL", "" if ok else " :: moved=" + str(detail))
