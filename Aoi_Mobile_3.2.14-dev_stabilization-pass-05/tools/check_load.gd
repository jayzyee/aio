extends SceneTree
func _initialize() -> void:
	print("StudioScript=", load("res://scripts/ui/StudioScreen.gd"))
	print("SetupScript=", load("res://scripts/ui/SetupScreen.gd"))
	print("SandboxScript=", load("res://scripts/core/GodotSandbox.gd"))
	quit()
