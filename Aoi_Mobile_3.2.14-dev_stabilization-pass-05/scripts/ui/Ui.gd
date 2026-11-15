extends RefCounted
## Shared look for the phone UI. Canvas is 720 px wide, so sizes here are logical px:
## body text 30, controls 84 tall (comfortable thumb targets on a ~400 dp phone).

const BG := Color("#ffffff")
const SURFACE := Color("#ffffff")
const CARD := Color("#ffffff")
const CARD_HI := Color("#f5f5f5")
const BORDER := Color("#e7e7e7")
const TEXT := Color("#111111")
const MUTED := Color("#686868")
static var ACCENT: Color = Color("#171717")
static var ACCENT_SOFT: Color = Color("#d8d8d8")
const USER_BUBBLE := Color("#f1f1f1")
const GREEN := Color("#19845b")
const RED := Color("#c84f5b")
const AMBER := Color("#a76a16")

const FS := 25
const FS_SMALL := 19
const FS_TITLE := 35
const BTN_H := 62
const ICON_DIR := "res://assets/icons/"

static func set_accent_color(_value: String = "") -> void:
	# Aoi uses a fixed neutral ink system. Semantic colours are reserved for
	# success, warning and error states rather than user-selected decoration.
	ACCENT = Color("#171717")
	ACCENT_SOFT = Color("#d8d8d8")


static var _font: Font
static var _regular: FontVariation
static var _medium: FontVariation
static var _semibold: FontVariation
static var _display: FontVariation
static var _mono: SystemFont


static func font() -> Font:
	if _font == null:
		_font = load("res://assets/fonts/InterVariable.ttf")
	return _font


static func _variation(weight: float, optical_size: float) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = font()
	variation.variation_opentype = {"wght": weight, "opsz": optical_size}
	return variation


static func regular_font() -> FontVariation:
	if _regular == null: _regular = _variation(400.0, 22.0)
	return _regular


static func medium_font() -> FontVariation:
	if _medium == null: _medium = _variation(520.0, 22.0)
	return _medium


static func semibold_font() -> FontVariation:
	if _semibold == null: _semibold = _variation(640.0, 22.0)
	return _semibold


static func bold_font() -> FontVariation:
	if _display == null: _display = _variation(720.0, 32.0)
	return _display


static func display_font() -> FontVariation:
	return bold_font()


static func mono_font() -> Font:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(["monospace", "Noto Sans Mono"])
	return _mono


static func reduced_motion_enabled() -> bool:
	var accessibility := Store.get_integration("accessibility")
	return bool(accessibility.get("reduce_motion", false))


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = regular_font()
	t.default_font_size = FS
	return t


static func box(bg: Color, radius: int = 12, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(mini(radius, 12))
	if bw > 0:
		b.border_color = border
		b.set_border_width_all(bw)
	return b


static func style_popup_menu(menu: PopupMenu) -> void:
	menu.add_theme_stylebox_override("panel", box(SURFACE, 12, BORDER, 1))
	menu.add_theme_stylebox_override("hover", box(Color("#f1f1f1"), 7))
	menu.add_theme_stylebox_override("separator", box(BORDER, 0))
	menu.add_theme_font_override("font", regular_font())
	menu.add_theme_font_size_override("font_size", 20)
	menu.add_theme_color_override("font_color", TEXT)
	menu.add_theme_color_override("font_hover_color", TEXT)
	menu.add_theme_color_override("font_accelerator_color", MUTED)
	menu.add_theme_color_override("font_disabled_color", Color(MUTED.r, MUTED.g, MUTED.b, 0.42))
	menu.add_theme_constant_override("v_separation", 7)
	menu.add_theme_constant_override("h_separation", 14)
	menu.add_theme_constant_override("item_start_padding", 18)
	menu.add_theme_constant_override("item_end_padding", 18)


static func pad(b: StyleBoxFlat, h: float = 28, v: float = 14) -> StyleBoxFlat:
	b.content_margin_left = h
	b.content_margin_right = h
	b.content_margin_top = v
	b.content_margin_bottom = v
	return b


static func icon(name: String) -> Texture2D:
	var path := ICON_DIR + name + ".svg"
	if not ResourceLoader.exists(path):
		push_warning("Aoi icon is unavailable: " + name)
		return null
	return load(path) as Texture2D


static func lbl(text: String, size: int = FS, color: Color = TEXT, bold: bool = false, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold: l.add_theme_font_override("font", semibold_font())
	else: l.add_theme_font_override("font", regular_font())
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 120
	return l


## Rounded button. kind: "primary" (accent), "ghost" (outlined), "quiet" (no border), "danger".
static func btn(text: String, kind: String = "ghost", icon_name: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, BTN_H)
	b.add_theme_font_override("font", medium_font())
	b.add_theme_font_size_override("font_size", FS)
	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	var fcol := TEXT
	match kind:
		"primary":
			normal = pad(box(ACCENT, 10)); hover = pad(box(Color("#292929"), 10)); fcol = Color("#ffffff")
		"danger":
			normal = pad(box(Color(0, 0, 0, 0), 8)); hover = pad(box(Color("#f7eeee"), 8)); fcol = RED
		"quiet":
			normal = pad(box(Color(0, 0, 0, 0), 8)); hover = pad(box(CARD_HI, 8)); fcol = MUTED
		_:
			normal = pad(box(Color(0, 0, 0, 0), 8)); hover = pad(box(CARD_HI, 8))
	var focus_style := pad(box(SURFACE, 8, ACCENT, 1))
	for st in ["normal"]: b.add_theme_stylebox_override(st, normal)
	b.add_theme_stylebox_override("focus", focus_style)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", pad(box(Color(0, 0, 0, 0), 22, BORDER, 1)))
	b.add_theme_color_override("font_color", fcol)
	b.add_theme_color_override("font_hover_color", fcol)
	b.add_theme_color_override("font_pressed_color", fcol)
	b.add_theme_color_override("font_disabled_color", Color(MUTED.r, MUTED.g, MUTED.b, 0.5))
	if icon_name != "":
		var white_icon_path := "res://assets/icons/white/%s.svg" % icon_name
		b.icon = load(white_icon_path) as Texture2D if kind == "primary" and ResourceLoader.exists(white_icon_path) else icon(icon_name)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 36)
		b.add_theme_constant_override("h_separation", 14)
		b.add_theme_color_override("icon_normal_color", fcol)
		b.add_theme_color_override("icon_hover_color", fcol)
	_wire_button_motion(b)
	return b


static func _wire_button_motion(button: Button) -> void:
	button.resized.connect(func(): button.pivot_offset = button.size * 0.5)
	button.button_down.connect(func():
		if not reduced_motion_enabled(): _animate_button_scale(button, Vector2(0.985, 0.985), 0.07, Tween.TRANS_QUAD, Tween.EASE_OUT))
	button.button_up.connect(func():
		if not reduced_motion_enabled(): _animate_button_scale(button, Vector2.ONE, 0.12, Tween.TRANS_CUBIC, Tween.EASE_OUT))


static func _animate_button_scale(button: Control, target: Vector2, duration: float, transition: Tween.TransitionType, easing: Tween.EaseType) -> void:
	var previous: Variant = null
	if button.has_meta("aoi_motion_tween"):
		previous = button.get_meta("aoi_motion_tween")
	if previous is Tween and previous.is_valid():
		previous.kill()
	var tween := button.create_tween()
	button.set_meta("aoi_motion_tween", tween)
	tween.tween_property(button, "scale", target, duration).set_trans(transition).set_ease(easing)


static func icon_btn(icon_name: String, kind: String = "quiet", size: int = BTN_H) -> Button:
	var b := btn("", kind, icon_name)
	b.custom_minimum_size = Vector2(size, size)
	for st in ["normal", "focus", "hover", "pressed", "disabled"]:
		var sb := b.get_theme_stylebox(st).duplicate() as StyleBoxFlat
		sb.content_margin_left = 0
		sb.content_margin_right = 0
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		b.add_theme_stylebox_override(st, sb)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 40)
	return b


static func chip(text: String, _color: Color = MUTED) -> Control:
	var label := lbl(text, FS_SMALL - 2, MUTED, true)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


static func line(placeholder: String, secret: bool = false) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.custom_minimum_size = Vector2(0, BTN_H)
	e.add_theme_font_size_override("font_size", FS)
	e.add_theme_color_override("font_color", TEXT)
	e.add_theme_color_override("font_placeholder_color", Color(MUTED.r, MUTED.g, MUTED.b, 0.7))
	var s := pad(box(Color("#f6f6f6"), 8), 18, 8)
	e.add_theme_stylebox_override("normal", s)
	e.add_theme_stylebox_override("read_only", s)
	e.add_theme_stylebox_override("focus", pad(box(CARD, 8, ACCENT, 1), 18, 8))
	return e


static func card(pad_px: int = 0) -> PanelContainer:
	# Content groups are not boxed cards. Their hierarchy comes from type,
	# alignment and spacing; separators are added only where they clarify flow.
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", box(Color(0, 0, 0, 0), 0))
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + side, pad_px)
	c.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	return c


static func card_body(c: PanelContainer) -> VBoxContainer:
	return c.get_child(0).get_child(0) as VBoxContainer


static func relative_time(unix: float) -> String:
	var d := int(Time.get_unix_time_from_system() - unix)
	if d < 60: return "just now"
	if d < 3600: return "%d min ago" % (d / 60)
	if d < 86400: return "%d h ago" % (d / 3600)
	return "%d d ago" % (d / 86400)
