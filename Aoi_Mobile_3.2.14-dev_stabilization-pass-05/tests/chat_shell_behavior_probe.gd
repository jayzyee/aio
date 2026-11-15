extends Node

var _failures := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	Store.set_root("user://aoi_chat_shell_behavior_probe/")
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_fail("Main scene is available")
		_finish()
		return
	var main := packed.instantiate()
	add_child(main)
	for _frame in range(3): await get_tree().process_frame
	main.go("chat")
	main._update_chrome()
	_check("chat header contains the two floating pills without a model shortcut", main._menu_btn != null and main._new_chat_btn != null and main._more_btn != null and main._search_btn == null)
	_check("first-run chat keeps its new-conversation action available", main._new_chat_btn.visible)

	main.chat._input.text = "Draft should survive provider setup"
	main.chat._on_send_pressed()
	await get_tree().process_frame
	_check("an unsent draft is preserved when the user is redirected to provider setup", main.tab == "setup" and main.chat._input.text == "Draft should survive provider setup")

	main.go("chat")
	Store.set_key("google_ai", "probe-key")
	Store.model = "google_ai/gemini-2.5-flash"
	main._update_chrome()
	_check("connecting a provider does not add redundant header chrome", main._menu_btn.visible and main._new_chat_btn.visible and main._more_btn.visible)
	Store.remove_key("google_ai")
	main._update_chrome()
	_check("removing the active provider key leaves the clean header intact", main._menu_btn.visible and main._more_btn.visible)
	_finish()

func _check(label: String, condition: bool) -> void:
	if condition: print("CHAT_BEHAVIOR_OK ", label)
	else: _fail(label)

func _fail(label: String) -> void:
	_failures += 1
	push_error("CHAT_BEHAVIOR_FAIL " + label)

func _finish() -> void:
	print("CHAT_BEHAVIOR_RESULT ", "OK" if _failures == 0 else "FAILED", " failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
