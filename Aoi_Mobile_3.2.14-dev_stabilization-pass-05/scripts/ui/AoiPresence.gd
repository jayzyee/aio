extends Control
## Aoi's state-driven vector presence.
## One geometric language adapts its formation, orbit and energy to real work states.
## No face, emoji, shader or external animation asset is used.

const Ui = preload("res://scripts/ui/Ui.gd")

const ACTIVE_STATES := [
	"idle", "thinking", "researching", "planning", "writing",
	"creating", "checking", "finishing", "retrying"
]
const STATIC_STATES := ["paused", "waiting", "error", "complete"]

var _state := "idle"
var _previous_state := "idle"
var _detail := ""
var _clock := 0.0
var _state_clock := 0.0
var _transition := 1.0
var _redraw_clock := 0.0
var _reduced_motion := false
var _app_suspended := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(76, 76)
	visibility_changed.connect(_sync_processing)
	set_reduced_motion(Ui.reduced_motion_enabled())
	_sync_processing()

func set_state(value: String, detail: String = "") -> void:
	var next_state := resolve_state(value, detail)
	_detail = detail
	if next_state == _state:
		return
	_previous_state = _state
	_state = next_state
	_state_clock = 0.0
	_transition = 0.0
	_redraw_clock = 0.0
	_sync_processing()
	queue_redraw()

func get_state() -> String:
	return _state

func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_redraw_clock = 0.0
	if enabled:
		_transition = 1.0
	_sync_processing()
	queue_redraw()

static func resolve_state(raw_state: String, detail: String = "") -> String:
	var state := raw_state.to_lower().strip_edges()
	var context := detail.to_lower()
	if state in ["cancelled", "cancelling", "paused", "stalled"]:
		return "paused"
	if state in ["waiting", "approval", "needs_approval"]:
		return "waiting"
	if state in ["error", "failed", "failure"]:
		return "error"
	if state in ["retrying", "recovering", "interrupted"]:
		return "retrying"
	if state in ["ready", "complete", "completed", "finished"]:
		return "complete"
	if state in ["reviewing", "checking", "verifying", "success"]:
		return "checking"
	if "research" in context or "search" in context or "lookup" in context or "source" in context:
		return "researching"
	if "inspect" in context or "read" in context or "understand" in context:
		return "thinking"
	if "test" in context or "verify" in context or "capture" in context or "review" in context:
		return "checking"
	if "write" in context or "file" in context or "script" in context or "code" in context or "implement" in context:
		return "writing"
	if "finish" in context or "polish" in context or "final touch" in context:
		return "finishing"
	if "render" in context or "image" in context or "design" in context or "asset" in context or "craft" in context:
		return "creating"
	if state in ["planning", "plan", "imagining"] or "plan" in context:
		return "planning"
	if state in ["thinking", "understanding", "inspecting", "reading"]:
		return "thinking"
	if state in ["writing"]:
		return "writing"
	if state in ["researching", "searching"]:
		return "researching"
	if state in ["creating", "building", "running", "processing", "downloading"]:
		return "creating"
	if state in ["idle", ""]:
		return "idle"
	return "thinking"

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_app_suspended = true
		set_process(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_app_suspended = false
		_sync_processing()

func _sync_processing() -> void:
	if not is_inside_tree():
		return
	var should_process := not _reduced_motion and not _app_suspended and is_visible_in_tree()
	if _state in STATIC_STATES and _transition >= 1.0:
		should_process = false
	set_process(should_process)

func _process(delta: float) -> void:
	if not is_visible_in_tree() or _app_suspended or _reduced_motion:
		set_process(false)
		return
	_clock = fmod(_clock + delta, TAU * 12.0)
	_state_clock += delta
	_transition = minf(1.0, _transition + delta / 0.46)
	_redraw_clock += delta
	if _redraw_clock >= (1.0 / 30.0):
		_redraw_clock = 0.0
		queue_redraw()
	if _state in STATIC_STATES and _transition >= 1.0:
		set_process(false)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var center := size * 0.5
	var scale_factor := minf(size.x, size.y) / 104.0
	var t := 0.0 if _reduced_motion or _app_suspended else _clock
	var transition := 1.0 if _reduced_motion else _ease_out_cubic(_transition)
	var active := _state in ACTIVE_STATES and not _reduced_motion and not _app_suspended
	var speed := _motion_speed(_state)
	var phase := t * speed
	var base := Ui.ACCENT
	var secondary := Color("#777777")
	var primary := base.lerp(secondary, 0.22)

	_draw_orbits(center, scale_factor, phase, primary, transition)
	_draw_connections(center, scale_factor, phase, primary, transition)
	_draw_particles(center, scale_factor, phase, primary, transition)
	_draw_core(center, scale_factor, phase, primary, transition)
	_draw_state_accent(center, scale_factor, phase, primary, transition)

func _draw_orbits(center: Vector2, s: float, phase: float, ink: Color, blend: float) -> void:
	var radii := [23.0, 32.0, 41.0]
	for ring_index in range(radii.size()):
		var radius: float = radii[ring_index] * s
		var direction := -1.0 if ring_index == 1 else 1.0
		var drift := phase * 0.12 * direction
		var arc_start := 0.34 + float(ring_index) * 1.82 + drift
		var arc_end := arc_start + TAU * (0.72 if _state not in ["paused", "waiting"] else 0.58)
		var alpha: float = float([0.17, 0.23, 0.13][ring_index]) * blend
		var line := Color(ink.r, ink.g, ink.b, alpha)
		draw_arc(center, radius, arc_start, arc_end, 72, line, maxf(0.8, s), true)

	# A faint orbit is allowed to open at the bottom for paused/approval states.
	if _state in ["paused", "waiting"]:
		draw_arc(center, 35.0 * s, -PI * 0.86, PI * 0.48, 54, Color(ink.r, ink.g, ink.b, 0.24), 1.2 * s, true)

func _draw_connections(center: Vector2, s: float, phase: float, ink: Color, blend: float) -> void:
	var points := PackedVector2Array()
	var count := 8
	for i in range(count):
		var angle := TAU * float(i) / float(count) - PI * 0.5
		var radius := 31.0
		match _state:
			"planning":
				radius = 27.0 if i % 2 == 0 else 38.0
			"writing":
				radius = 30.0 + (4.0 if i % 2 == 0 else -2.0)
			"creating":
				radius = 33.0 + sin(phase * 0.42 + float(i)) * 3.0
			"researching":
				radius = 35.0 + cos(phase * 0.25 + float(i)) * 2.0
			"checking":
				radius = 32.0
			"finishing", "complete":
				radius = lerpf(37.0, 30.0, blend)
			"retrying":
				radius = lerpf(46.0, 31.0, blend)
			"paused", "waiting":
				radius = 32.0
		var point := center + Vector2(cos(angle), sin(angle)) * radius * s
		points.append(point)

	if _state in ["planning", "writing", "creating", "finishing", "complete"]:
		var edge_alpha := 0.12 if _state == "writing" else 0.19
		for i in range(points.size()):
			var next := (i + 2) % points.size() if _state == "planning" else (i + 1) % points.size()
			draw_line(points[i], points[next], Color(ink.r, ink.g, ink.b, edge_alpha * blend), 1.0 * s, true)
	elif _state == "checking":
		for i in [0, 2, 4, 6]:
			draw_line(center, points[i], Color(ink.r, ink.g, ink.b, 0.13 * blend), 0.9 * s, true)

func _draw_particles(center: Vector2, s: float, phase: float, ink: Color, blend: float) -> void:
	for i in range(12):
		var base_angle := TAU * float(i) / 12.0 - PI * 0.5
		var direction := 1.0 if i % 2 == 0 else -1.0
		var angle := base_angle
		var radius := 35.0
		var pulse := 0.5 + 0.5 * sin(phase * 0.9 + float(i) * 0.8)
		var dot_scale := 1.0
		match _state:
			"thinking":
				radius = lerpf(46.0, 30.0, 0.5 + 0.5 * sin(phase * 0.32))
				angle += phase * 0.08 * direction
			"researching":
				angle += phase * 0.21 * direction
				radius = 38.0 + sin(phase * 0.45 + float(i)) * 2.5
			"planning":
				radius = 27.0 if i % 2 == 0 else 39.0
				angle += phase * 0.035
			"writing":
				angle += phase * 0.075
				pulse = 0.5 + 0.5 * sin(phase * 1.8 - float(i) * 0.82)
				radius = 31.0 + pulse * 4.0
			"creating":
				angle += phase * 0.17 * direction
				radius = 34.0 + pulse * 5.0
			"checking":
				angle += phase * 0.055
				pulse = 0.5 + 0.5 * sin(phase * 1.2 - float(i) * 0.52)
				radius = 33.0
			"finishing":
				radius = lerpf(44.0, 31.0, blend)
				angle += (1.0 - blend) * float(i) * 0.08
			"retrying":
				radius = lerpf(48.0, 34.0, blend)
				angle -= phase * 0.07
			"paused", "waiting", "error":
				radius = 33.0
				pulse = 0.45
			"complete":
				radius = 30.0
				dot_scale = 0.82 + pulse * 0.18
			"idle":
				angle += phase * 0.035 * direction
				radius = 33.0 + pulse * 2.0

		var point := center + Vector2(cos(angle), sin(angle)) * radius * s
		var alpha := (0.34 + pulse * 0.52) * blend
		var dot := Color(ink.r, ink.g, ink.b, alpha)
		var dot_radius := (1.45 + pulse * 1.15) * s * dot_scale
		draw_circle(point, dot_radius * 2.05, Color(ink.r, ink.g, ink.b, alpha * 0.10))
		draw_circle(point, dot_radius, dot)

func _draw_core(center: Vector2, s: float, phase: float, ink: Color, blend: float) -> void:
	var pulse := 0.5 + 0.5 * sin(phase * (0.50 if _state == "idle" else 0.82))
	if _state in ["paused", "waiting", "error", "complete"]:
		pulse = 0.42
	var breathe := (2.0 + pulse * 1.25) * s
	var halo := Color(ink.r, ink.g, ink.b, 0.055 + pulse * 0.045)
	draw_circle(center, 12.0 * s + breathe, halo)
	var diamond_size := 6.6 * s
	var diamond := PackedVector2Array([
		center + Vector2(0.0, -diamond_size),
		center + Vector2(diamond_size, 0.0),
		center + Vector2(0.0, diamond_size),
		center + Vector2(-diamond_size, 0.0)
	])
	draw_colored_polygon(diamond, Color(ink.r, ink.g, ink.b, 0.92 * blend))
	draw_circle(center, 2.1 * s, Color(1.0, 1.0, 1.0, 0.96 * blend))

func _draw_state_accent(center: Vector2, s: float, phase: float, ink: Color, blend: float) -> void:
	if _state == "researching":
		var scan_angle := -PI * 0.5 + fposmod(phase * 0.52, TAU)
		var endpoint := center + Vector2(cos(scan_angle), sin(scan_angle)) * 43.0 * s
		draw_line(center, endpoint, Color(ink.r, ink.g, ink.b, 0.32 * blend), 1.15 * s, true)
		draw_circle(endpoint, 3.4 * s, Color(ink.r, ink.g, ink.b, 0.74 * blend))
	elif _state == "checking":
		var scan_angle := -PI * 0.5 + fposmod(phase * 0.62, TAU)
		var start := center + Vector2(cos(scan_angle), sin(scan_angle)) * 20.0 * s
		var finish := center + Vector2(cos(scan_angle), sin(scan_angle)) * 44.0 * s
		draw_line(start, finish, Color(ink.r, ink.g, ink.b, 0.38 * blend), 1.3 * s, true)
	elif _state in ["paused", "waiting"]:
		var anchor := center + Vector2(0.0, -35.0) * s
		draw_circle(anchor, 4.5 * s, Color(ink.r, ink.g, ink.b, 0.14))
		draw_circle(anchor, 2.2 * s, Color(ink.r, ink.g, ink.b, 0.82))
	elif _state == "error":
		var anchor := center + Vector2(32.0, -20.0) * s
		draw_circle(anchor, 4.5 * s, Color(ink.r, ink.g, ink.b, 0.12))
		draw_circle(anchor, 2.0 * s, Color(ink.r, ink.g, ink.b, 0.82))
	elif _state in ["finishing", "complete"]:
		var glint_angle := -PI * 0.5 + (0.0 if _state == "complete" else phase * 0.08)
		var glint := center + Vector2(cos(glint_angle), sin(glint_angle)) * 41.0 * s
		draw_circle(glint, 4.2 * s, Color(ink.r, ink.g, ink.b, 0.16 * blend))
		draw_circle(glint, 1.8 * s, Color(1.0, 1.0, 1.0, 0.90 * blend))
	elif _state == "creating":
		var orbit_angle := phase * 0.30
		var orbit_point := center + Vector2(cos(orbit_angle) * 44.0, sin(orbit_angle) * 23.0) * s
		draw_circle(orbit_point, 4.0 * s, Color(ink.r, ink.g, ink.b, 0.12))
		draw_circle(orbit_point, 1.9 * s, ink)

func _motion_speed(state: String) -> float:
	match state:
		"thinking": return 0.56
		"researching": return 0.88
		"planning": return 0.36
		"writing": return 0.76
		"creating": return 1.12
		"checking": return 0.92
		"finishing": return 0.38
		"retrying": return 0.54
		_: return 0.22

func _ease_out_cubic(value: float) -> float:
	return 1.0 - pow(1.0 - clampf(value, 0.0, 1.0), 3.0)
