extends Control
## Compact progress rail. Determinate values come from the saved project plan;
## negative values render a travelling segment without a fabricated percentage.

const Ui = preload("res://scripts/ui/Ui.gd")
const INK := Color("#242424")

var progress := -1.0
var _clock := 0.0
var _reduced_motion := false
var _app_suspended := false

func _ready() -> void:
	custom_minimum_size = Vector2(0, 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(_sync_processing)
	set_reduced_motion(Ui.reduced_motion_enabled())
	_sync_processing()

func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0) if value >= 0.0 else -1.0
	queue_redraw()

func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_sync_processing()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_app_suspended = true
		_sync_processing()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_app_suspended = false
		_sync_processing()

func _sync_processing() -> void:
	if not is_inside_tree():
		return
	set_process(not _reduced_motion and not _app_suspended and is_visible_in_tree())

func _process(delta: float) -> void:
	if _reduced_motion or _app_suspended or not is_visible_in_tree():
		set_process(false)
		return
	_clock = fmod(_clock + delta * 0.72, 1.0)
	queue_redraw()

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var height := minf(size.y, 7.0)
	var y := (size.y - height) * 0.5
	draw_rect(Rect2(0.0, y, size.x, height), Color("#e5e5e5"))
	var filled_width := size.x * progress if progress >= 0.0 else size.x * 0.22
	if progress < 0.0:
		var travel := maxf(0.0, size.x - filled_width)
		var x := 0.0 if _reduced_motion else travel * (0.5 - 0.5 * cos(TAU * _clock))
		_draw_gradient_segment(x, filled_width, y, height)
	else:
		_draw_gradient_segment(0.0, filled_width, y, height)
		if filled_width > 24.0:
			var gleam_width := minf(38.0, filled_width * 0.24)
			var max_x := maxf(0.0, filled_width - gleam_width)
			var gleam_x := 0.0 if _reduced_motion else max_x * _clock
			draw_rect(Rect2(gleam_x, y + 1.0, gleam_width, maxf(1.0, height - 2.0)), Color(1.0, 1.0, 1.0, 0.26))

func _draw_gradient_segment(x: float, width: float, y: float, height: float) -> void:
	if width <= 0.0:
		return
	draw_rect(Rect2(x, y, width, height), INK)


func _round_box(color: Color, height: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = int(height * 0.5)
	style.corner_radius_top_right = int(height * 0.5)
	style.corner_radius_bottom_left = int(height * 0.5)
	style.corner_radius_bottom_right = int(height * 0.5)
	return style
