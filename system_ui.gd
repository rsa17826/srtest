class_name SystemUI
# Shared "system window" look (LitRPG status window / sci-fi HUD): dark translucent
# panels, thin cyan borders with a soft glow, corner brackets, monospace text.

const CYAN := Color(0.25, 0.85, 1.0)
const TEXT := Color(0.75, 0.95, 1.0)
const DIM := Color(0.4, 0.65, 0.75)
const BG := Color(0.02, 0.07, 0.12, 0.9)
const DANGER := Color(1.0, 0.4, 0.4)

static var _theme: Theme

static func _box(bg: Color, border: Color, glow := 0.0, mx := 8, my := 4) -> StyleBoxFlat:
  var s := StyleBoxFlat.new()
  s.bg_color = bg
  s.border_color = border
  s.set_border_width_all(1)
  s.content_margin_left = mx
  s.content_margin_right = mx
  s.content_margin_top = my
  s.content_margin_bottom = my
  if glow > 0.0:
    s.shadow_color = Color(border, glow)
    s.shadow_size = 6
  return s

static func theme() -> Theme:
  if _theme != null:
    return _theme
  var t := Theme.new()
  var font := SystemFont.new()
  font.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "Courier New", "monospace"])
  t.default_font = font
  t.default_font_size = 15

  t.set_color("font_color", "Label", TEXT)

  t.set_stylebox("panel", "PanelContainer", _box(BG, Color(CYAN, 0.7), 0.25, 6, 6))

  t.set_stylebox("normal", "Button", _box(Color(CYAN, 0.06), Color(CYAN, 0.45)))
  t.set_stylebox("hover", "Button", _box(Color(CYAN, 0.18), CYAN, 0.3))
  t.set_stylebox("pressed", "Button", _box(Color(CYAN, 0.32), CYAN))
  t.set_stylebox("disabled", "Button", _box(Color(0, 0, 0, 0), Color(CYAN, 0.15)))
  t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
  t.set_color("font_color", "Button", TEXT)
  t.set_color("font_hover_color", "Button", Color.WHITE)
  t.set_color("font_pressed_color", "Button", Color.WHITE)
  t.set_color("font_disabled_color", "Button", Color(DIM, 0.4))

  # slider: thin track, filled progress, small bar grabber
  var track := _box(Color(CYAN, 0.1), Color(CYAN, 0.3), 0.0, 0, 3)
  t.set_stylebox("slider", "HSlider", track)
  t.set_stylebox("grabber_area", "HSlider", _box(Color(CYAN, 0.55), Color(CYAN, 0.55), 0.0, 0, 3))
  t.set_stylebox("grabber_area_highlight", "HSlider", _box(CYAN, CYAN, 0.0, 0, 3))
  var img := Image.create(4, 14, false, Image.FORMAT_RGBA8)
  img.fill(CYAN)
  var tex := ImageTexture.create_from_image(img)
  for icon in ["grabber", "grabber_highlight", "grabber_disabled"]:
    t.set_icon(icon, "HSlider", tex)

  # scrollbar
  t.set_stylebox("scroll", "VScrollBar", _box(Color(CYAN, 0.06), Color(CYAN, 0.0), 0.0, 2, 0))
  t.set_stylebox("grabber", "VScrollBar", _box(Color(CYAN, 0.4), Color(CYAN, 0.0), 0.0, 2, 0))
  t.set_stylebox("grabber_highlight", "VScrollBar", _box(Color(CYAN, 0.7), Color(CYAN, 0.0), 0.0, 2, 0))
  t.set_stylebox("grabber_pressed", "VScrollBar", _box(CYAN, Color(CYAN, 0.0), 0.0, 2, 0))

  _theme = t
  return t

# "[ TITLE ]" with a thin rule under it. Change later with set_title().
static func header(text: String) -> VBoxContainer:
  var box := VBoxContainer.new()
  box.add_theme_constant_override("separation", 2)
  var l := Label.new()
  l.add_theme_color_override("font_color", CYAN)
  l.add_theme_font_size_override("font_size", 19)
  box.add_child(l)
  var line := ColorRect.new()
  line.color = Color(CYAN, 0.5)
  line.custom_minimum_size.y = 1
  box.add_child(line)
  set_title(box, text)
  return box

static func set_title(header_box: VBoxContainer, text: String) -> void:
  (header_box.get_child(0) as Label).text = "[ %s ]" % text.to_upper()

static func dim_label(text: String) -> Label:
  var l := Label.new()
  l.text = text
  l.add_theme_color_override("font_color", DIM)
  l.add_theme_font_size_override("font_size", 12)
  return l

static func make_danger(b: Button) -> void:
  b.add_theme_color_override("font_color", DANGER)
  b.add_theme_color_override("font_hover_color", Color(1.0, 0.7, 0.7))

# corner brackets drawn over a panel
static func add_brackets(host: Control, length := 10.0) -> void:
  var o := Control.new()
  o.mouse_filter = Control.MOUSE_FILTER_IGNORE
  host.add_child(o)
  o.draw.connect(_draw_brackets.bind(o, length))

static func _draw_brackets(o: Control, length: float) -> void:
  var r := Rect2(Vector2(1, 1), o.size - Vector2(2, 2))
  var corners := [
    [r.position, Vector2(1, 1)],
    [Vector2(r.end.x, r.position.y), Vector2(-1, 1)],
    [Vector2(r.position.x, r.end.y), Vector2(1, -1)],
    [r.end, Vector2(-1, -1)],
  ]
  for c in corners:
    o.draw_line(c[0], c[0] + Vector2(c[1].x * length, 0), CYAN, 2.0)
    o.draw_line(c[0], c[0] + Vector2(0, c[1].y * length), CYAN, 2.0)

static func fade_in(c: Control) -> void:
  c.modulate.a = 0.0
  c.create_tween().tween_property(c, "modulate:a", 1.0, 0.25)
