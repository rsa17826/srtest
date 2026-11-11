class_name SystemUI
# Shared "system window" look, modelled on the LitRPG / hacker-HUD panels: glassy blue gradient
# panels with cut corners, a bright double outline that glows, a faint grid, a light that runs
# along the top edge, "===" and dot-line ornaments on the borders, skewed buttons.

const CYAN := Color(0.25, 0.85, 1.0)
const GOLD := Color(1.0, 0.78, 0.25) # accent for special panels (add_frame(host, SystemUI.GOLD))
const TEXT := Color(0.85, 0.97, 1.0)
const DIM := Color(0.45, 0.7, 0.85)
const BG := Color(0.02, 0.07, 0.12, 0.9)
const DANGER := Color(1.0, 0.4, 0.4)

static var _theme: Theme

static func _box(bg: Color, border: Color, glow := 0.0, mx := 8, my := 4, glow_size := 10) -> StyleBoxFlat:
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
    s.shadow_size = glow_size
  return s

# a button face: same as _box but sheared so it reads as a slanted HUD tab
static func _tab(bg: Color, border: Color, glow := 0.0, glow_size := 8) -> StyleBoxFlat:
  var s := _box(bg, border, glow, 12, 4, glow_size)
  s.skew = Vector2(0.12, 0.0)
  return s

static func theme() -> Theme:
  if _theme != null:
    return _theme
  var t := Theme.new()
  var font := SystemFont.new()
  font.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "Courier New", "monospace"])
  font.font_weight = 600
  t.default_font = font
  t.default_font_size = 15

  t.set_color("font_color", "Label", TEXT)
  t.set_color("font_shadow_color", "Label", Color(CYAN, 0.5))
  t.set_constant("shadow_outline_size", "Label", 3)
  t.set_color("font_shadow_color", "Button", Color(CYAN, 0.4))
  t.set_constant("shadow_outline_size", "Button", 4)

  # the window look itself is drawn by SystemFrame; the panel only reserves room for it
  t.set_stylebox("panel", "PanelContainer", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0.0, 16, 12))

  t.set_stylebox("normal", "Button", _tab(Color(0.1, 0.5, 0.95, 0.16), Color(0.45, 0.88, 1.0, 0.7), 0.2, 6))
  t.set_stylebox("hover", "Button", _tab(Color(0.15, 0.6, 1.0, 0.34), Color(0.85, 0.98, 1.0, 0.95), 0.6, 12))
  t.set_stylebox("pressed", "Button", _tab(Color(0.2, 0.65, 1.0, 0.55), Color.WHITE, 0.8, 14))
  t.set_stylebox("disabled", "Button", _tab(Color(0, 0, 0, 0), Color(CYAN, 0.15)))
  t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
  t.set_color("font_color", "Button", TEXT)
  t.set_color("font_hover_color", "Button", Color.WHITE)
  t.set_color("font_pressed_color", "Button", Color.WHITE)
  t.set_color("font_disabled_color", "Button", Color(DIM, 0.4))

  # slider: thin track, filled progress, small bar grabber
  t.set_stylebox("slider", "HSlider", _box(Color(CYAN, 0.1), Color(CYAN, 0.3), 0.0, 0, 3))
  t.set_stylebox("grabber_area", "HSlider", _box(Color(CYAN, 0.6), Color(CYAN, 0.6), 0.5, 0, 3, 6))
  t.set_stylebox("grabber_area_highlight", "HSlider", _box(CYAN, CYAN, 0.7, 0, 3, 8))
  var img := Image.create(4, 14, false, Image.FORMAT_RGBA8)
  img.fill(Color.WHITE)
  var tex := ImageTexture.create_from_image(img)
  for icon in ["grabber", "grabber_highlight", "grabber_disabled"]:
    t.set_icon(icon, "HSlider", tex)

  # scrollbar
  t.set_stylebox("scroll", "VScrollBar", _box(Color(CYAN, 0.06), Color(CYAN, 0.0), 0.0, 2, 0))
  t.set_stylebox("grabber", "VScrollBar", _box(Color(CYAN, 0.4), Color(CYAN, 0.0), 0.0, 2, 0))
  t.set_stylebox("grabber_highlight", "VScrollBar", _box(Color(CYAN, 0.7), Color(CYAN, 0.0), 0.0, 2, 0))
  t.set_stylebox("grabber_pressed", "VScrollBar", _box(CYAN, Color(CYAN, 0.0), 0.0, 2, 0))

  # text fields
  t.set_stylebox("normal", "LineEdit", _box(Color(0, 0, 0, 0.3), Color(CYAN, 0.4)))
  t.set_stylebox("focus", "LineEdit", _box(Color(CYAN, 0.08), CYAN, 0.4, 8, 4, 8))
  t.set_stylebox("read_only", "LineEdit", _box(Color(0, 0, 0, 0.2), Color(CYAN, 0.2)))
  t.set_color("font_color", "LineEdit", TEXT)
  t.set_color("font_placeholder_color", "LineEdit", Color(DIM, 0.6))
  t.set_color("caret_color", "LineEdit", CYAN)
  t.set_color("selection_color", "LineEdit", Color(CYAN, 0.3))

  _theme = t
  return t

# ---------------------------------------------------------------- window frame

# Draws the whole panel look onto its parent, behind the parent's content. A Control child of a
# PanelContainer would be squeezed inside the content margins (so the frame would sit on top of the
# content); a plain Node that paints through the parent's draw signal covers the full rect.
class SystemFrame extends Node:
  var host: Control
  var accent := SystemUI.CYAN
  var t := 0.0

  func _ready() -> void:
    host = get_parent() as Control
    host.draw.connect(_paint)

  func _process(delta: float) -> void:
    t += delta
    if host.is_visible_in_tree():
      host.queue_redraw()

  # octagon with big cuts at top-left and bottom-right, small ones at the other corners
  func _outline(inset: float, cut: float, small: float) -> PackedVector2Array:
    var x0 := inset
    var y0 := inset
    var x1 := host.size.x - inset
    var y1 := host.size.y - inset
    return PackedVector2Array([
      Vector2(x0 + cut, y0), Vector2(x1 - small, y0), Vector2(x1, y0 + small), Vector2(x1, y1 - cut),
      Vector2(x1 - cut, y1), Vector2(x0 + small, y1), Vector2(x0, y1 - small), Vector2(x0, y0 + cut),
    ])

  func _closed(points: PackedVector2Array) -> PackedVector2Array:
    var loop := points.duplicate()
    loop.append(points[0])
    return loop

  func _paint() -> void:
    var size := host.size
    var breathe := 0.5 + 0.5 * sin(t * 2.0)
    var white := Color(0.85, 0.98, 1.0)
    var outer := _outline(1.0, 12.0, 4.0)

    # glass: lighter blue at the top fading to deep blue
    var colors := PackedColorArray()
    for p in outer:
      var k := clampf(p.y / maxf(size.y, 1.0), 0.0, 1.0)
      colors.append(Color(0.05, 0.32, 0.68, 0.55).lerp(Color(0.0, 0.1, 0.3, 0.82), k))
    host.draw_polygon(outer, colors)

    # faint grid
    var grid := Color(accent, 0.07)
    var x := 24.0
    while x < size.x - 6.0:
      host.draw_line(Vector2(x, 4), Vector2(x, size.y - 4), grid)
      x += 24.0
    var y := 24.0
    while y < size.y - 6.0:
      host.draw_line(Vector2(6, y), Vector2(size.x - 6, y), grid)
      y += 24.0

    # outer outline: soft glow layers + bright core
    var loop := _closed(outer)
    host.draw_polyline(loop, Color(accent, 0.10 + 0.08 * breathe), 8.0)
    host.draw_polyline(loop, Color(accent, 0.28 + 0.12 * breathe), 4.0)
    host.draw_polyline(loop, Color(white, 0.95), 1.5)
    # inner outline, the double-line look
    host.draw_polyline(_closed(_outline(6.0, 8.0, 2.0)), Color(accent, 0.4), 1.0)
    # the two big cuts get a heavier edge
    host.draw_line(outer[7], outer[0], white, 3.0)
    host.draw_line(outer[3], outer[4], white, 3.0)

    # ornaments sitting on the borders: "===" bottom left, dot-line top right
    for i in 3:
      host.draw_rect(Rect2(18.0 + i * 16.0, size.y - 3.0, 11.0, 3.0), Color(white, 0.9))
    var ty := 1.0
    var tx := size.x - 56.0
    host.draw_circle(Vector2(tx, ty), 2.5, white)
    host.draw_line(Vector2(tx, ty), Vector2(tx + 36.0, ty), Color(white, 0.9), 2.0)
    host.draw_circle(Vector2(tx + 36.0, ty), 2.5, white)

    # a light running along the top edge
    var head := fposmod(t * 140.0, size.x + 100.0) - 50.0
    host.draw_line(Vector2(maxf(head, 14.0), 1.0), Vector2(clampf(head + 70.0, 14.0, size.x - 4.0), 1.0), Color(1, 1, 1, 0.85), 2.0)

# Frame a PanelContainer (or any Control) in the system look; the panel's content margins keep the content clear of it.
static func add_frame(host: Control, accent := CYAN) -> SystemFrame:
  var frame := SystemFrame.new()
  frame.accent = accent
  host.add_child(frame)
  return frame

# kept for the existing callers
static func add_brackets(host: Control, _length := 10.0) -> void:
  add_frame(host)

# ---------------------------------------------------------------- header / small pieces

# a horizontal rule with a diamond in the middle and bright ends
class Rule extends Control:
  func _init() -> void:
    custom_minimum_size = Vector2(0, 9)
    mouse_filter = Control.MOUSE_FILTER_IGNORE

  func _draw() -> void:
    var y := size.y * 0.5
    var cx := size.x * 0.5
    draw_line(Vector2(0, y), Vector2(size.x, y), Color(SystemUI.CYAN, 0.45), 1.0)
    draw_line(Vector2(0, y), Vector2(40, y), Color(0.85, 0.98, 1.0, 0.95), 2.0)
    draw_line(Vector2(size.x - 40, y), Vector2(size.x, y), Color(0.85, 0.98, 1.0, 0.95), 2.0)
    var d := 4.0
    draw_colored_polygon(PackedVector2Array([
      Vector2(cx - d * 1.6, y), Vector2(cx, y - d), Vector2(cx + d * 1.6, y), Vector2(cx, y + d)]), Color(0.85, 0.98, 1.0))

# "[ TITLE ]", centred, with a rule under it. Change later with set_title().
static func header(text: String) -> VBoxContainer:
  var box := VBoxContainer.new()
  box.add_theme_constant_override("separation", 3)
  var l := Label.new()
  l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  l.add_theme_color_override("font_color", Color(0.9, 0.99, 1.0))
  l.add_theme_font_size_override("font_size", 20)
  l.add_theme_color_override("font_shadow_color", Color(CYAN, 0.75))
  l.add_theme_constant_override("shadow_outline_size", 10)
  box.add_child(l)
  box.add_child(Rule.new())
  set_title(box, text)
  return box

static func set_title(header_box: VBoxContainer, text: String) -> void:
  (header_box.get_child(0) as Label).text = "[ %s ]" % text.to_upper()

static func dim_label(text: String) -> Label:
  var l := Label.new()
  l.text = text
  l.add_theme_color_override("font_color", DIM)
  l.add_theme_font_size_override("font_size", 12)
  l.add_theme_constant_override("shadow_outline_size", 0) # small text blurs with a halo
  return l

static func make_danger(b: Button) -> void:
  b.add_theme_color_override("font_color", DANGER)
  b.add_theme_color_override("font_hover_color", Color(1.0, 0.7, 0.7))

static func fade_in(c: Control) -> void:
  c.modulate.a = 0.0
  c.create_tween().tween_property(c, "modulate:a", 1.0, 0.25)

# Put `content` into a ScrollContainer with room around it. A ScrollContainer clips everything it draws,
# so without this the glow and slanted edges of buttons at its borders get cut off and the buttons look
# too wide for their space.
static func scroll_pad(scroll: ScrollContainer, content: Control, pad := 8) -> void:
  var m := MarginContainer.new()
  m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  for side in ["left", "right", "top", "bottom"]:
    m.add_theme_constant_override("margin_" + side, pad)
  scroll.add_child(m)
  m.add_child(content)

# the frame breathes by itself now, this stays so older calls still compile
static func pulse(_c: Control) -> void: pass
