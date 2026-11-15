extends Control
## Mobile bottom sheet with a bounded scroll viewport and draggable snap points.
const Ui = preload("res://scripts/ui/Ui.gd")

signal closed

var body: VBoxContainer
var _panel: PanelContainer
var _title: Label
var _scroll: ScrollContainer
var _resting_ratio := 0.88
var _ratio := 0.88
var _dragging := false
var _drag_distance := 0.0
var _drag_start_ratio := 0.88
var _snap_tween: Tween

const MIN_RATIO := 0.48
const MAX_RATIO := 0.94
# Fixed vertical chrome: 12 top + 48 grip + 2×12 gaps + 56 header + 28 bottom.
const SHEET_CHROME_HEIGHT := 180.0
const MIN_SCROLL_HEIGHT := 132.0
const DISMISS_DRAG_RATIO := 0.20
const EXPAND_DRAG_RATIO := 0.075
const MIN_DRAG_DISTANCE := 14.0


func open(title: String, max_height_ratio: float = 0.88) -> void:
	_resting_ratio = clampf(max_height_ratio, 0.55, 0.92)
	_ratio = _resting_ratio
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	set_meta("keep_stop", true)

	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.12, 0.20, 0.34)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_backdrop_input)
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.name = "SheetPanel"
	var sb := Ui.box(Ui.SURFACE, 22, Ui.BORDER, 1)
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	_panel.add_theme_stylebox_override("panel", sb)
	# Anchor both vertical edges to the viewport bottom, then give the panel an
	# explicit negative top offset. The old PRESET_BOTTOM_WIDE offsets could retain
	# a large positive bottom offset after the panel's minimum height changed,
	# placing most of the sheet below the screen on tall phone viewports.
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0
	_panel.offset_top = -MIN_SCROLL_HEIGHT - SHEET_CHROME_HEIGHT
	_panel.offset_bottom = 0.0
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)

	var outer := MarginContainer.new()
	for side in ["left", "right"]:
		outer.add_theme_constant_override("margin_" + side, 28)
	outer.add_theme_constant_override("margin_top", 12)
	outer.add_theme_constant_override("margin_bottom", 28)
	_panel.add_child(outer)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	outer.add_child(v)

	# The visual grip sits inside a generous touch target. Dragging it expands,
	# collapses, or dismisses the sheet without stealing scroll gestures.
	var drag_zone := Control.new()
	drag_zone.name = "SheetDragHandle"
	drag_zone.custom_minimum_size = Vector2(0, 48)
	drag_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drag_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_zone.tooltip_text = "Drag up to expand · drag down to close"
	v.add_child(drag_zone)
	var grip := ColorRect.new()
	grip.color = Ui.BORDER.darkened(0.12)
	grip.custom_minimum_size = Vector2(46, 5)
	grip.size = Vector2(46, 5)
	grip.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_zone.add_child(grip)
	drag_zone.gui_input.connect(_on_drag_handle_input)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.custom_minimum_size.y = 56
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	v.add_child(head)
	head.gui_input.connect(_on_drag_handle_input)
	_title = Ui.lbl(title, 27, Ui.TEXT, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_title)
	var x := Ui.icon_btn("close", "quiet", 64)
	x.tooltip_text = "Close"
	x.set_meta("keep_stop", true)
	x.mouse_filter = Control.MOUSE_FILTER_STOP
	x.pressed.connect(close)
	head.add_child(x)
	x.mouse_filter = Control.MOUSE_FILTER_STOP

	_scroll = ScrollContainer.new()
	_scroll.name = "SheetScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus = true
	_scroll.custom_minimum_size.y = MIN_SCROLL_HEIGHT
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)

	body = VBoxContainer.new()
	body.name = "SheetContent"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	_scroll.add_child(body)
	body.minimum_size_changed.connect(_fit)
	body.child_order_changed.connect(_queue_fit)
	get_viewport().size_changed.connect(_fit)
	_fit()
	call_deferred("_fit")

	# Initial entrance is intentionally short and restrained. Avoid animating the
	# panel offsets: content can be added immediately after open(), changing the
	# required height while the entrance tween is still running.
	_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.18)


func _queue_fit() -> void:
	call_deferred("_fit")


func _fit() -> void:
	if body == null or not is_instance_valid(body):
		return
	if _scroll == null or not is_instance_valid(_scroll):
		return
	var viewport_height := maxf(get_viewport_rect().size.y, 320.0)
	var max_body_height := maxf(MIN_SCROLL_HEIGHT, viewport_height * _ratio - SHEET_CHROME_HEIGHT)
	var content_height := body.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(content_height, MIN_SCROLL_HEIGHT, max_body_height)
	if _panel != null and is_instance_valid(_panel):
		# Keep the whole panel inside the visible viewport. Recalculate after each
		# body child is added; a sheet is usually populated immediately after open().
		var panel_height := minf(_scroll.custom_minimum_size.y + SHEET_CHROME_HEIGHT, viewport_height * _ratio)
		_panel.offset_top = -panel_height
		_panel.offset_bottom = 0.0


func _on_backdrop_input(event: InputEvent) -> void:
	if not ((event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)):
		return
	# gui_input coordinates are local to the full-screen backdrop. Convert them to
	# canvas coordinates before comparing with the sheet's global rectangle.
	var canvas_position: Vector2 = get_global_transform_with_canvas() * event.position
	if _panel == null or not _panel.get_global_rect().has_point(canvas_position):
		close()


func _on_drag_handle_input(event: InputEvent) -> void:
	# Start only from the intended sheet grip/header. Once started, _input keeps
	# receiving movement and release outside the handle, so a drag cannot leave
	# the sheet stuck in its half-dragged state.
	if event is InputEventScreenTouch and event.pressed:
		_begin_drag()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_begin_drag()


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventScreenDrag:
		_update_drag(event.relative.y)
	elif event is InputEventScreenTouch and not event.pressed:
		_finish_drag()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_update_drag(event.relative.y)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_drag()


func _begin_drag() -> void:
	if _snap_tween != null and _snap_tween.is_valid():
		_snap_tween.kill()
	_dragging = true
	_drag_distance = 0.0
	_drag_start_ratio = _ratio


func _update_drag(delta_y: float) -> void:
	if not _dragging:
		return
	_drag_distance += delta_y
	var viewport_height := maxf(get_viewport_rect().size.y, 320.0)
	_ratio = clampf(_drag_start_ratio - _drag_distance / viewport_height, MIN_RATIO, MAX_RATIO)
	_fit()


func _finish_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	# A tap on the grip/header is not a drag and must not collapse an expanded sheet.
	if absf(_drag_distance) < MIN_DRAG_DISTANCE:
		return
	var viewport_height := maxf(get_viewport_rect().size.y, 320.0)
	if _drag_distance >= viewport_height * DISMISS_DRAG_RATIO or _ratio <= MIN_RATIO + 0.02:
		close()
		return
	if _drag_distance <= -viewport_height * EXPAND_DRAG_RATIO:
		_settle_ratio(MAX_RATIO)
	else:
		_settle_ratio(_resting_ratio)


func _settle_ratio(target: float) -> void:
	if Ui.reduced_motion_enabled():
		_ratio = target
		_fit()
		return
	if _snap_tween != null and _snap_tween.is_valid():
		_snap_tween.kill()
	_snap_tween = create_tween()
	_snap_tween.tween_method(_set_ratio, _ratio, target, 0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_ratio(value: float) -> void:
	_ratio = value
	_fit()


func close() -> void:
	if not is_queued_for_deletion():
		closed.emit()
		queue_free()
