@tool
extends EditorPlugin

# Cursor-based GridMap placement.
#  - ray is marched through the GridMap cells: clicking a block face places next to it
#  - if the ray hits no block it lands on a work plane (the "layer"), so no scrolling floors
#  - ghost tile + cell outline + fading grid show exactly what will be placed and where
#  - Ctrl+drag selects a region, Ctrl+scroll changes its height, releasing Ctrl fills it
#    (releasing Ctrl while holding Shift erases the region instead)

const DEBUG := false # true = print why a click was ignored
const MAX_RAY_CELLS := 256
const MAX_PLANE_DIST := 1000.0
const PLANE_RADIUS := 10.0
const PLACE_COLOR := Color(0.2, 0.9, 1.0)
const ERASE_COLOR := Color(1.0, 0.25, 0.25)

const PLANE_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

uniform vec4 color : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform float radius = 10.0;

varying vec2 gpos;

void vertex() {
  gpos = VERTEX.xz;
}

void fragment() {
  vec2 d = abs(fract(gpos + 0.5) - 0.5);
  vec2 w = fwidth(gpos) * 1.5;
  vec2 a = smoothstep(vec2(0.0), w, d);
  float line = 1.0 - min(a.x, a.y);
  float fade = 1.0 - smoothstep(radius * 0.4, radius, length(gpos));
  ALBEDO = color.rgb;
  ALPHA = (line * 0.7 + 0.05) * fade;
}
"""

var grid: MergedGridMap
var lib: MeshLibrary
var ghost: MeshInstance3D
var outline: MeshInstance3D
var plane: MeshInstance3D

var cube_lines: ImmediateMesh
var plane_mesh: PlaneMesh
var ghost_mat: StandardMaterial3D
var place_line_mat: StandardMaterial3D
var erase_line_mat: StandardMaterial3D
var plane_mat: ShaderMaterial

var panel: VBoxContainer
var enabled_check: CheckBox
var layer_label: Label
var item_list: ItemList

var selected_item := MergedGridMap.INVALID_CELL_ITEM
var rotation_index := 0
var level := 0 # work-plane layer (cell y) used when the ray hits no block
var drag_y := 0 # layer locked while drag-painting

var target_cell := Vector3i.ZERO
var has_target := false
var erasing := false
var painting := false
var click_held := false # a left click we consumed is still down
var stroke := {} # cell -> [old_item, old_orientation] for the current drag
var last_mouse := Vector2.ZERO

# region (Ctrl+drag) state
var region_active := false # Ctrl is held and a region is being built
var region_dragging := false # left mouse is still down, footprint follows the cursor
var region_start := Vector3i.ZERO # first corner, y is the base layer
var region_end := Vector3i.ZERO # opposite footprint corner (y == region_start.y)
var region_h := 0 # extra layers above (+) or below (-) the base layer
var region_erasing := false # Shift currently held

func _enter_tree() -> void:
  set_process_input(true)
  cube_lines = _make_cube_lines()

  plane_mesh = PlaneMesh.new()
  plane_mesh.size = Vector2(PLANE_RADIUS * 2.0, PLANE_RADIUS * 2.0)

  var shader := Shader.new()
  shader.code = PLANE_SHADER
  plane_mat = ShaderMaterial.new()
  plane_mat.shader = shader
  plane_mat.set_shader_parameter("radius", PLANE_RADIUS)

  ghost_mat = _flat_mat(Color(PLACE_COLOR, 0.35), true)
  place_line_mat = _flat_mat(PLACE_COLOR, false)
  erase_line_mat = _flat_mat(ERASE_COLOR, false)

  _build_panel()
  add_control_to_container(CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT, panel)

func _exit_tree() -> void:
  _detach()
  remove_control_from_container(CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT, panel)
  panel.queue_free()

func _handles(object: Object) -> bool:
  return object is MergedGridMap and (object as MergedGridMap).mesh_library != null

func _make_visible(visible: bool) -> void:
  panel.visible = visible
  if not visible:
    _detach()

func _edit(object: Object) -> void:
  _detach()
  if object != null:
    _attach(object as MergedGridMap)

# ---------------------------------------------------------------- setup

func _attach(g: MergedGridMap) -> void:
  grid = g
  lib = grid.mesh_library

  ghost = MeshInstance3D.new()
  ghost.material_override = ghost_mat
  outline = MeshInstance3D.new()
  outline.mesh = cube_lines
  plane = MeshInstance3D.new()
  plane.mesh = plane_mesh
  plane.material_override = plane_mat

  # internal + no owner: never shows in the scene dock and never gets saved
  for n in [ghost, outline, plane]:
    n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    n.visible = false
    grid.add_child(n, false, Node.INTERNAL_MODE_FRONT)

  lib.changed.connect(_refresh_items)
  _refresh_items()
  _refresh_layer_label()

func _detach() -> void:
  if is_instance_valid(lib) and lib.changed.is_connected(_refresh_items):
    lib.changed.disconnect(_refresh_items)
  for n in [ghost, outline, plane]:
    if is_instance_valid(n):
      n.queue_free()
  ghost = null
  outline = null
  plane = null
  grid = null
  lib = null
  has_target = false
  painting = false
  click_held = false
  region_active = false
  region_dragging = false
  stroke.clear()

func _build_panel() -> void:
  panel = VBoxContainer.new()
  panel.add_theme_constant_override("separation", 2)
  panel.custom_minimum_size = Vector2(170, 0)
  panel.visible = false

  enabled_check = CheckBox.new()
  enabled_check.text = "Smart place"
  enabled_check.button_pressed = true
  enabled_check.toggled.connect(func(_on: bool) -> void: _update_visuals())
  panel.add_child(enabled_check)

  var help := Label.new()
  help.text = "LMB place    Shift+LMB erase\n[ ] tile    T rotate\nPgUp/PgDn layer\nCtrl+drag region\nCtrl+scroll height\nRelease Ctrl fill\n(+Shift = erase)\nEsc cancel region"
  help.add_theme_font_size_override("font_size", 11)
  help.modulate = Color(1, 1, 1, 0.6)
  panel.add_child(help)

  layer_label = Label.new()
  panel.add_child(layer_label)

  item_list = ItemList.new()
  item_list.custom_minimum_size = Vector2(0, 220)
  item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
  item_list.fixed_icon_size = Vector2i(32, 32)
  item_list.item_selected.connect(_on_item_selected)
  panel.add_child(item_list)

func _flat_mat(color: Color, transparent: bool) -> StandardMaterial3D:
  var m := StandardMaterial3D.new()
  m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
  m.albedo_color = color
  if transparent:
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
  else:
    m.no_depth_test = true # outline stays visible through blocks
  return m

func _make_cube_lines() -> ImmediateMesh:
  var m := ImmediateMesh.new()
  var c := [
    Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),
    Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1),
  ]
  var edges := [
    [0, 1], [1, 2], [2, 3], [3, 0],
    [4, 5], [5, 6], [6, 7], [7, 4],
    [0, 4], [1, 5], [2, 6], [3, 7],
  ]
  m.surface_begin(Mesh.PRIMITIVE_LINES)
  for e in edges:
    m.surface_add_vertex(c[e[0]])
    m.surface_add_vertex(c[e[1]])
  m.surface_end()
  return m

# ---------------------------------------------------------------- palette

func _refresh_items() -> void:
  var ids: Array = Array(lib.get_item_list())
  ids.sort()
  item_list.clear()
  for id in ids:
    var idx := item_list.add_item(lib.get_item_name(id), lib.get_item_preview(id))
    item_list.set_item_metadata(idx, id)
    if id == selected_item:
      item_list.select(idx)

  if ids.is_empty():
    selected_item = MergedGridMap.INVALID_CELL_ITEM
    _sync_ghost_mesh()
  elif not selected_item in ids:
    item_list.select(0)
    _on_item_selected(0)
  else:
    _sync_ghost_mesh()

func _on_item_selected(idx: int) -> void:
  selected_item = item_list.get_item_metadata(idx)
  _sync_ghost_mesh()
  _update_visuals()

func _sync_ghost_mesh() -> void:
  if selected_item == MergedGridMap.INVALID_CELL_ITEM:
    ghost.mesh = null
  else:
    ghost.mesh = lib.get_item_mesh(selected_item)

func _cycle_item(dir: int) -> void:
  var count := item_list.item_count
  assert(count > 0, "gridmap_placer: MeshLibrary has no items")
  var idx := posmod(item_list.get_selected_items()[0] + dir, count)
  item_list.select(idx)
  item_list.ensure_current_is_visible()
  _on_item_selected(idx)

func _refresh_layer_label() -> void:
  layer_label.text = "Layer: %d" % level

# ---------------------------------------------------------------- input

# The built-in GridMap editor is ahead of this plugin in the 3D input chain and stops the
# click first, so _forward_3d_gui_input never fires. _input runs before any GUI handling,
# so consuming the event here is what actually keeps the editor from seeing it.
# Needs Godot 4.3+ (Viewport.gui_get_hovered_control).

func _input(event: InputEvent) -> void:
  if grid == null or not enabled_check.button_pressed: return

  # a click we consumed must also have its release consumed, even outside the viewport
  if click_held and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
    click_held = false
    region_dragging = false # footprint is now fixed; Ctrl+scroll still adjusts height
    if painting:
      painting = false
      _commit_stroke()
    _consume()
    return

  if _region_input(event): return

  # note: during _input the main viewport's own mouse position is one event stale,
  # so mouse events use event.position directly
  var pos: Vector2 = event.position if event is InputEventMouse else get_viewport().get_mouse_position()
  var vp := _hovered_viewport(pos)
  if vp == null:
    if DEBUG and event is InputEventMouseButton and event.pressed:
      var h := get_viewport().gui_get_hovered_control()
      print("gridmap_placer: click not over a 3D viewport, hovered = ", str(h.get_path()) if h else "null", " pos = ", pos)
    if has_target:
      has_target = false
      _update_visuals()
    return
  var camera := vp.get_camera_3d()
  var container := vp.get_parent() as SubViewportContainer

  if event is InputEventMouseMotion:
    last_mouse = (event.position - container.global_position) / container.stretch_shrink
    if region_active:
      if region_dragging:
        _update_region_end(camera)
      return
    if not painting:
      erasing = event.shift_pressed
    _update_target(camera)
    if painting and has_target:
      _apply(target_cell)
    return # motion is never consumed, so orbit/pan keep working

  if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
    if event.alt_pressed: return
    last_mouse = (event.position - container.global_position) / container.stretch_shrink
    erasing = event.shift_pressed
    click_held = true
    _consume() # always, otherwise the built-in tool places its own block
    _update_target(camera)
    if not has_target: return
    if event.ctrl_pressed:
      region_active = true
      region_dragging = true
      region_start = target_cell
      region_end = target_cell
      region_h = 0
      region_erasing = event.shift_pressed
      _update_visuals()
      return
    if not erasing and selected_item == MergedGridMap.INVALID_CELL_ITEM:
      push_warning("gridmap_placer: no tile selected in the palette")
      return
    painting = true
    drag_y = target_cell.y
    if not erasing:
      level = target_cell.y
      _refresh_layer_label()
    _apply(target_cell)
    return

  if event is InputEventKey and event.pressed and not event.echo:
    if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
    var focus := get_viewport().gui_get_focus_owner()
    if focus is LineEdit or focus is TextEdit: return
    match event.keycode:
      KEY_BRACKETLEFT:
        _cycle_item(-1)
      KEY_BRACKETRIGHT:
        _cycle_item(1)
      KEY_T:
        rotation_index = (rotation_index + 1) % 4
      KEY_PAGEUP:
        level += 1
        _refresh_layer_label()
      KEY_PAGEDOWN:
        level -= 1
        _refresh_layer_label()
      _: return
    _update_target(camera)
    _consume()

# Events that only matter while a region is being built. Returns true when handled.
# These must not depend on the cursor being over the viewport (Ctrl can be released anywhere).
func _region_input(event: InputEvent) -> bool:
  if not region_active: return false

  if event is InputEventKey:
    if event.keycode == KEY_CTRL and not event.pressed:
      region_active = false
      region_dragging = false
      erasing = event.shift_pressed
      _fill_region()
      has_target = false
      _update_visuals()
      return true
    if event.keycode == KEY_SHIFT:
      region_erasing = event.pressed
      _update_visuals()
      return true
    if event.keycode == KEY_ESCAPE and event.pressed:
      region_active = false
      region_dragging = false
      has_target = false
      _update_visuals()
      _consume()
      return true
    return false

  if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
    if event.pressed:
      region_h += 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
      _update_visuals()
    _consume() # otherwise the editor zooms the camera
    return true

  return false

func _consume() -> void:
  get_viewport().set_input_as_handled()

# The 3D viewport under pos, or null. Geometry based: the editor draws a transparent overlay
# control on top of the SubViewportContainer, so the hovered control is never the container.
# Toolbar/menu widgets inside the viewport are deeper in the tree than that overlay, so they
# are excluded and keep working.
func _hovered_viewport(pos: Vector2) -> SubViewport:
  var hovered := get_viewport().gui_get_hovered_control()
  for i in 4:
    var vp := EditorInterface.get_editor_viewport_3d(i)
    var container := vp.get_parent() as Control
    if not container.is_visible_in_tree(): continue
    if not container.get_global_rect().has_point(pos): continue
    var root := container.get_parent()
    var over_widget := hovered != null and hovered != container \
        and hovered.get_parent() != root and hovered.get_parent() != container
    if over_widget: return null
    return vp
  return null

# ---------------------------------------------------------------- targeting

# Mouse ray in "grid space": GridMap-local coords divided by cell_size, so a cell is a unit cube.
# Returns [origin, direction].
func _grid_ray(camera: Camera3D) -> Array:
  var cs := grid.cell_size
  var o := grid.to_local(camera.project_ray_origin(last_mouse)) / cs
  var world_dir := camera.project_ray_normal(last_mouse)
  var d := ((grid.global_transform.basis.inverse() * world_dir) / cs).normalized()
  return [o, d]

func _update_target(camera: Camera3D) -> void:
  var ray := _grid_ray(camera)
  var o: Vector3 = ray[0]
  var d: Vector3 = ray[1]

  # while drag-placing, ignore blocks and stay on the layer the stroke started on
  var plane_locked := painting and not erasing
  var plane_y := drag_y if plane_locked else level

  var hit := {}
  if not plane_locked:
    hit = _march(o, d)

  var plane_t := INF
  var plane_cell := Vector3i.ZERO
  if not is_zero_approx(d.y):
    var t := (float(plane_y) - o.y) / d.y
    if t > 0.0 and t < MAX_PLANE_DIST:
      plane_t = t
      var p := o + d * t
      plane_cell = Vector3i(floori(p.x), plane_y, floori(p.z))

  has_target = true
  if erasing:
    if hit.is_empty():
      has_target = false
    else:
      target_cell = hit.cell
  elif not hit.is_empty() and hit.t <= plane_t:
    target_cell = hit.cell + hit.normal
  elif plane_t < INF:
    target_cell = plane_cell
  else:
    has_target = false

  _update_visuals()

# While dragging a region the footprint follows the cursor on the region's base layer.
# A ray parallel to the layer (or pointing away from it) leaves the corner where it was.
func _update_region_end(camera: Camera3D) -> void:
  var ray := _grid_ray(camera)
  var o: Vector3 = ray[0]
  var d: Vector3 = ray[1]
  if is_zero_approx(d.y): return
  var t := (float(region_start.y) - o.y) / d.y
  if t <= 0.0 or t >= MAX_PLANE_DIST: return
  var p := o + d * t
  region_end = Vector3i(floori(p.x), region_start.y, floori(p.z))
  _update_visuals()

# Amanatides-Woo voxel traversal. Returns {} or {t, cell, normal}.
func _march(o: Vector3, d: Vector3) -> Dictionary:
  var cell := Vector3i(floori(o.x), floori(o.y), floori(o.z))
  var step := Vector3i(int(signf(d.x)), int(signf(d.y)), int(signf(d.z)))
  var t_max := Vector3.INF
  var t_delta := Vector3.INF
  for a in 3:
    if d[a] > 0.0:
      t_max[a] = (cell[a] + 1 - o[a]) / d[a]
      t_delta[a] = 1.0 / d[a]
    elif d[a] < 0.0:
      t_max[a] = (cell[a] - o[a]) / d[a]
      t_delta[a] = -1.0 / d[a]

  for i in MAX_RAY_CELLS:
    var axis := 0
    if t_max.y < t_max[axis]:
      axis = 1
    if t_max.z < t_max[axis]:
      axis = 2
    var t := t_max[axis]
    cell[axis] += step[axis]
    t_max[axis] += t_delta[axis]
    if grid.get_cell_item(cell) != MergedGridMap.INVALID_CELL_ITEM:
      var normal := Vector3i.ZERO
      normal[axis] = - step[axis]
      return {"t": t, "cell": cell, "normal": normal}
  return {}

# ---------------------------------------------------------------- visuals

func _update_visuals() -> void:
  if region_active:
    _update_region_visuals()
    return

  var show := enabled_check.button_pressed and has_target
  ghost.visible = show and not erasing and selected_item != MergedGridMap.INVALID_CELL_ITEM
  outline.visible = show
  plane.visible = show
  if not show: return

  var cs := grid.cell_size
  outline.material_override = erase_line_mat if erasing else place_line_mat
  outline.transform = Transform3D(Basis.from_scale(cs), Vector3(target_cell) * cs)
  # plane sits on the bottom face of the target layer and follows the cursor
  plane.transform = Transform3D(Basis.from_scale(cs), (Vector3(target_cell) + Vector3(0, 0.01, 0)) * cs)
  plane_mat.set_shader_parameter("color", ERASE_COLOR if erasing else PLACE_COLOR)

  if ghost.visible:
    var rot := Basis(Vector3.UP, rotation_index * PI / 2.0)
    ghost.transform = Transform3D(rot, grid.map_to_local(target_cell)) * lib.get_item_mesh_transform(selected_item)

func _update_region_visuals() -> void:
  ghost.visible = false
  outline.visible = true
  plane.visible = true

  var cs := grid.cell_size
  var b := _region_bounds()
  var lo: Vector3i = b[0]
  var hi: Vector3i = b[1]
  var size := Vector3(hi - lo + Vector3i.ONE)
  outline.material_override = erase_line_mat if region_erasing else place_line_mat
  outline.transform = Transform3D(Basis.from_scale(size * cs), Vector3(lo) * cs)
  plane.transform = Transform3D(Basis.from_scale(cs), (Vector3(region_end) + Vector3(0, 0.01, 0)) * cs)
  plane_mat.set_shader_parameter("color", ERASE_COLOR if region_erasing else PLACE_COLOR)

# ---------------------------------------------------------------- editing

func _orientation() -> int:
  return rotation_index

# Inclusive cell bounds of the region: [min, max]
func _region_bounds() -> Array:
  var y2 := region_start.y + region_h
  var lo := Vector3i(mini(region_start.x, region_end.x), mini(region_start.y, y2), mini(region_start.z, region_end.z))
  var hi := Vector3i(maxi(region_start.x, region_end.x), maxi(region_start.y, y2), maxi(region_start.z, region_end.z))
  return [lo, hi]

# fills (or erases, per `erasing`) the whole region as one undo step
func _fill_region() -> void:
  if not erasing and selected_item == MergedGridMap.INVALID_CELL_ITEM:
    push_warning("gridmap_placer: no tile selected in the palette")
    return
  var b := _region_bounds()
  var lo: Vector3i = b[0]
  var hi: Vector3i = b[1]
  for x in range(lo.x, hi.x + 1):
    for y in range(lo.y, hi.y + 1):
      for z in range(lo.z, hi.z + 1):
        _apply(Vector3i(x, y, z))
  _commit_stroke()

func _apply(cell: Vector3i) -> void:
  var item := MergedGridMap.INVALID_CELL_ITEM if erasing else selected_item
  var orient := 0 if erasing else _orientation()
  var old_item := grid.get_cell_item(cell)
  var old_orient := grid.get_cell_item_orientation(cell)
  if old_item == item and (erasing or old_orient == orient): return
  if not stroke.has(cell):
    stroke[cell] = [old_item, old_orient]
  grid.set_cell_item(cell, item, orient)

# the stroke is already applied live; this only records one undo step for the whole drag
func _commit_stroke() -> void:
  if stroke.is_empty(): return
  var ur := get_undo_redo()
  ur.create_action("Erase tiles" if erasing else "Place tiles", UndoRedo.MERGE_DISABLE, grid)
  for cell in stroke:
    var old: Array = stroke[cell]
    ur.add_undo_method(grid, "set_cell_item", cell, old[0], old[1])
    ur.add_do_method(grid, "set_cell_item", cell, grid.get_cell_item(cell), grid.get_cell_item_orientation(cell))
  ur.commit_action(false)
  stroke.clear()
