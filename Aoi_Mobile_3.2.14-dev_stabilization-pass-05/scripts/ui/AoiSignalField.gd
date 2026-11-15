extends Control
## Aoi's Spatial Prism: a stateful, light vector object over the familiar signal lattice.
## The prism's rotation, formation, orbit and frontier are presentation only; the
## percentage remains owned by the persisted task plan in BuildExperienceCard.

const Ui = preload("res://scripts/ui/Ui.gd")
const COLOR_BLUE := Color("#343434")
const COLOR_VIOLET := Color("#777777")
const COLOR_SKY := Color("#a5a5a5")
const EDGE_PAIRS := [
	Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
	Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
	Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7)
]
const FACE_IDS := [
	[4, 5, 6, 7], [0, 1, 2, 3],
	[0, 4, 7, 3], [1, 5, 6, 2],
	[3, 7, 6, 2], [0, 4, 5, 1]
]

var progress := -1.0
var stage := "building"
var _clock := 0.0
var _redraw_clock := 0.0
var _reduced_motion := false
var _app_suspended := false

func _ready() -> void:
	custom_minimum_size = Vector2(0, 328)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	visibility_changed.connect(_sync_processing)
	set_reduced_motion(Ui.reduced_motion_enabled())
	_sync_processing()

func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0) if value >= 0.0 else -1.0
	queue_redraw()

func set_stage(value: String) -> void:
	stage = value
	queue_redraw()

func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_redraw_clock = 0.0
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
	_clock = fmod(_clock + delta, 10000.0)
	_redraw_clock += delta
	# Bound custom drawing to 30 Hz on low/mid-range mobile hardware.
	if _redraw_clock >= (1.0 / 30.0):
		_redraw_clock = 0.0
		queue_redraw()

func _draw() -> void:
	if size.x < 100.0 or size.y < 120.0:
		return
	var bounds := Rect2(Vector2.ZERO, size)
	var card_bg := StyleBoxFlat.new()
	card_bg.bg_color = Color("#f7f7f7")
	card_bg.set_corner_radius_all(8)
	draw_style_box(card_bg, bounds)

	var t := 0.0 if _reduced_motion else _clock
	var progress_frontier := progress
	if progress_frontier < 0.0:
		progress_frontier = 0.5 + 0.5 * sin(t * 0.19)
	var center := Vector2(size.x * 0.5, size.y * 0.52)
	_draw_signal_lattice(t, progress_frontier)
	_draw_orbit_paths(center, t)
	_draw_spatial_prism(center, t, progress_frontier)
	_draw_frontier(center, t, progress_frontier)

func _draw_signal_lattice(t: float, frontier: float) -> void:
	var columns := clampi(int(size.x / 19.0), 22, 36)
	var rows := clampi(int(size.y / 20.0), 13, 20)
	var inset := Vector2(15.0, 14.0)
	var usable := size - inset * 2.0
	for row in range(rows):
		var ny := float(row) / float(maxi(1, rows - 1))
		for column in range(columns):
			var nx := float(column) / float(maxi(1, columns - 1))
			var point := inset + Vector2(nx * usable.x, ny * usable.y)
			var wave := 0.5 + 0.5 * sin(nx * 9.0 - ny * 1.7 + t * 0.62)
			var seam := exp(-absf(nx - frontier) * 19.0)
			var focus := 0.68 + 0.32 * sin(PI * ny)
			var alpha := (0.38 + wave * 0.14 + seam * 0.34) * focus
			if progress >= 0.0 and nx <= progress:
				alpha += 0.16
			var radius: float = 1.35 + wave * 0.34 + seam * 1.00
			var color := COLOR_SKY.lerp(COLOR_BLUE, nx * 0.78).lerp(COLOR_VIOLET, nx * 0.30)
			color.a = clampf(alpha, 0.26, 0.96)
			draw_circle(point, radius, color)

func _draw_orbit_paths(center: Vector2, t: float) -> void:
	var orbit_a := PackedVector2Array()
	var orbit_b := PackedVector2Array()
	for i in range(72):
		var u := float(i) / 71.0
		var x := lerpf(size.x * 0.07, size.x * 0.93, u)
		var y_a := center.y + sin(u * TAU * 0.74 + t * 0.075) * size.y * 0.19
		var y_b := center.y + cos(u * TAU * 0.58 - t * 0.055) * size.y * 0.125
		orbit_a.append(Vector2(x, y_a))
		orbit_b.append(Vector2(x, y_b))
	draw_polyline(orbit_a, Color(0.18, 0.18, 0.18, 0.34), 1.55, true)
	draw_polyline(orbit_b, Color(0.34, 0.34, 0.34, 0.24), 1.25, true)
	for i in range(3):
		var angle := t * 0.10 + float(i) * TAU / 3.0
		var orbit_point := center + Vector2(cos(angle) * size.x * 0.235, sin(angle) * size.y * 0.23)
		draw_circle(orbit_point, 4.0, Color(0.18, 0.18, 0.18, 0.46))
		draw_circle(orbit_point, 1.7, Color(1.0, 1.0, 1.0, 0.95))

func _draw_spatial_prism(center: Vector2, t: float, frontier: float) -> void:
	var pulse := 0.5 + 0.5 * sin(t * 0.54)
	var stage_scale := 1.0
	if stage == "planning":
		stage_scale = 0.82 + pulse * 0.06
	elif stage == "reviewing":
		stage_scale = 1.02
	elif stage in ["stalled", "waiting", "approval"]:
		stage_scale = 0.96
	var half_extent := minf(size.x * 0.13, size.y * 0.22) * stage_scale
	var angle := 0.0 if _reduced_motion else t
	var vertices_3d := [
		Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)
	]
	var projected := PackedVector2Array()
	var depths := PackedFloat32Array()
	for point in vertices_3d:
		var rotated := _rotate_prism_point(point * half_extent, angle)
		var perspective := 440.0 / maxf(260.0, 440.0 - rotated.z)
		projected.append(center + Vector2(rotated.x, -rotated.y) * perspective)
		depths.append(rotated.z)

	# Translucent face planes add volume without using a shader or texture.
	var face_colors := [
		Color(0.16, 0.16, 0.16, 0.055), Color(0.30, 0.30, 0.30, 0.035),
		Color(0.22, 0.22, 0.22, 0.040), Color(0.38, 0.38, 0.38, 0.045),
		Color(0.28, 0.28, 0.28, 0.040), Color(0.18, 0.18, 0.18, 0.035)
	]
	for face_index in range(FACE_IDS.size()):
		var face := PackedVector2Array()
		for vertex_id in FACE_IDS[face_index]:
			face.append(projected[vertex_id])
		draw_colored_polygon(face, face_colors[face_index])

	var edge_mix := clampf(frontier * 0.65 + 0.35, 0.0, 1.0)
	for edge_index in range(EDGE_PAIRS.size()):
		var edge: Vector2i = EDGE_PAIRS[edge_index]
		var depth := (depths[edge.x] + depths[edge.y]) * 0.5
		var edge_color := COLOR_BLUE.lerp(COLOR_VIOLET, float(edge_index) / float(EDGE_PAIRS.size() - 1))
		var alpha := 0.88 if depth > 0.0 else 0.48
		edge_color.a = alpha * edge_mix
		draw_line(projected[edge.x], projected[edge.y], edge_color, 2.35 if depth > 0.0 else 1.55, true)

	# Node highlights create a deliberate vertex rhythm; the bright node advances
	# only as a visual cue and never substitutes for the numeric task progress.
	for vertex_id in range(projected.size()):
		var vertex_color := COLOR_BLUE if vertex_id % 2 == 0 else COLOR_VIOLET
		var near := depths[vertex_id] > 0.0
		draw_circle(projected[vertex_id], 5.4 if near else 3.6, Color(1.0, 1.0, 1.0, 0.82))
		draw_circle(projected[vertex_id], 3.0 if near else 2.0, vertex_color)

	var core := center + Vector2(sin(t * 0.21) * 3.0, cos(t * 0.18) * 2.0)
	draw_circle(core, 14.0 + pulse * 3.0, Color(0.16, 0.16, 0.16, 0.12))
	draw_colored_polygon(PackedVector2Array([
		core + Vector2(0.0, -8.0), core + Vector2(8.0, 0.0),
		core + Vector2(0.0, 8.0), core + Vector2(-8.0, 0.0)
	]), Color(0.16, 0.16, 0.16, 0.92))
	draw_circle(core, 2.1, Color(1.0, 1.0, 1.0, 0.98))

func _rotate_prism_point(point: Vector3, angle: float) -> Vector3:
	var rx := 0.36 + sin(angle * 0.17) * 0.11
	var ry := angle * 0.20 + 0.55
	var rz := -0.20 + cos(angle * 0.13) * 0.08
	var p := Vector3(point.x, point.y * cos(rx) - point.z * sin(rx), point.y * sin(rx) + point.z * cos(rx))
	p = Vector3(p.x * cos(ry) + p.z * sin(ry), p.y, -p.x * sin(ry) + p.z * cos(ry))
	return Vector3(p.x * cos(rz) - p.y * sin(rz), p.x * sin(rz) + p.y * cos(rz), p.z)

func _draw_frontier(center: Vector2, t: float, frontier: float) -> void:
	var x := lerpf(size.x * 0.08, size.x * 0.92, frontier)
	var point := Vector2(x, center.y + sin(t * 0.41) * size.y * 0.075)
	draw_circle(point, 10.0, Color(0.16, 0.16, 0.16, 0.08))
	draw_circle(point, 3.0, Color(0.16, 0.16, 0.16, 0.70))
	draw_circle(point, 1.1, Color(1.0, 1.0, 1.0, 0.98))
