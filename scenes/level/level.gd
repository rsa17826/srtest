@tool
extends Node3D
class_name Level

@export var gridmap: MergedGridMap
func _init() -> void:
  global.level = self
var checkpoints: Array = []
var triggers: Array = [] # [{"area": Area3D, "on_enter": Callable}], used by ReplayViewer
var tweens: Array[Tween] = []

var base_tiles: Dictionary = {} # gridmap.tiles as the level starts, set at the end of _ready
# Everything that changes the gridmap during a run, in order. ReplayViewer replays this list to show the
# walls and doors as they were at any frame:
# [{"type": "explode", "pos": Vector3, "radius": float} | {"type": "lever"}]
var events: Array = []

# Breaks breakable walls near a grenade explosion. Rebuilds immediately (not deferred) so the new
# collision exists for the rest of this physics tick, which the resimulation relies on.
func explode(world_pos: Vector3, radius: float) -> void:
  events.append({"type": "explode", "pos": world_pos, "radius": radius})
  var changed := _break_walls(world_pos, radius)
  var local := gridmap.to_local(world_pos)
  for i in levers.size():
    var closest := local.clamp(levers[i].aabb.position, levers[i].aabb.end)
    if closest.distance_to(local) <= LEVER_HIT_RADIUS:
      changed = _pull(i) or changed
  if changed:
    gridmap.rebuild()

# ---------------------------------------------------------------- levers

const LEVER_COLOR := Color("9c0038") # shader_parameter/color of both surfaces once pulled
const LEVER_HIT_RADIUS := 2.0 # a grenade exploding this close to a lever pulls it
# one per lever box: {"aabb": AABB (gridmap space), "mats": [surface 0 / 1 materials, private copies],
# "orig": [their original color], "lit": bool}
var levers: Array = []

# swaps the lever tiles for standalone meshes with their own materials (so one lever can change color)
# and hooks up walking into them. A grenade blast pulls them from explode().
func setup_levers() -> void:
  var lib := gridmap.mesh_library
  var id := lib.find_item_by_name("lever")
  assert(id != -1, "no tile named 'lever' in the mesh library")
  var mesh := lib.get_item_mesh(id)
  assert(mesh.get_surface_count() >= 2, "lever mesh needs surfaces 0 and 1")
  var boxes := gridmap.get_boxes_by_item(id)
  var areas := spawn_areas(gridmap, "lever") # same box order as `boxes`
  var nodes := replace_with_nodes(gridmap, "lever")
  for i in areas.size():
    var mi: MeshInstance3D = nodes[areas[i].get_meta("cell")]
    var mats := []
    var orig := []
    for s in 2:
      var mat: ShaderMaterial = mesh.surface_get_material(s).duplicate()
      mi.set_surface_override_material(s, mat)
      mats.append(mat)
      orig.append(mat.get_shader_parameter("color"))
    var box: Dictionary = boxes[i]
    var aabb := AABB(Vector3(box.min) * gridmap.cell_size, Vector3(box.size) * gridmap.cell_size)
    levers.append({"aabb": aabb, "mats": mats, "orig": orig, "lit": false})
    add_trigger(areas[i], func(body): if body is Player: body.onTick.append(pull_lever.bind(i)))

func _set_lever_lit(i: int, lit: bool) -> void:
  levers[i].lit = lit
  for s in 2:
    levers[i].mats[s].set_shader_parameter("color", LEVER_COLOR if lit else levers[i].orig[s])

# pulls lever i: records it, opens the doors, colors it. No rebuild. false if it was already pulled.
func _pull(i: int) -> bool:
  if levers[i].lit: return false
  events.append({"type": "lever", "id": i})
  removeDoors()
  _set_lever_lit(i, true)
  return true

# walking into a lever. Runs from Player.onTick so the live game and the resimulation apply it at the
# same point of a tick.
func pull_lever(i: int) -> void:
  if _pull(i):
    gridmap.rebuild()

# true if any wall was erased. Does not rebuild.
func _break_walls(world_pos: Vector3, radius: float) -> bool:
  const BREAKABLE_TILE := "cracked wall"
  var id := gridmap.mesh_library.find_item_by_name(BREAKABLE_TILE)
  assert(id != -1, "no tile named '%s' in the mesh library" % BREAKABLE_TILE)
  return gridmap.erase_item_in_radius(id, gridmap.to_local(world_pos), 2)

# applies one recorded event to the tiles, without recording it again or rebuilding
func _apply_event(e: Dictionary) -> void:
  if e.type == "explode":
    _break_walls(e.pos, e.radius)
  else:
    assert(e.type == "lever", "unknown world event type '%s'" % e.type)
    removeDoors()
    _set_lever_lit(e.id, true)

# walls, doors and levers as they are after the first `count` events of `list`, starting from the level's start
func set_walls(list: Array, count: int) -> void:
  gridmap.tiles = base_tiles.duplicate()
  for i in levers.size():
    _set_lever_lit(i, false)
  for i in count:
    _apply_event(list[i])
  gridmap.rebuild()

func removeDoors() -> void:
  var id := gridmap.mesh_library.find_item_by_name("door")
  for cell in gridmap.tiles.keys():
    if gridmap.tiles[cell].x == id:
      gridmap.tiles.erase(cell)

# restores every broken wall and door (full restart). With no events nothing has changed.
func reset_walls() -> void:
  if events.is_empty(): return
  events.clear()
  set_walls([], 0)

func add_trigger(area: Area3D, on_enter: Callable) -> void:
  triggers.append({"area": area, "on_enter": on_enter})
  area.body_entered.connect(on_enter)

func _ready() -> void:
  if Engine.is_editor_hint():
    gridmap.tiled_subdivisions = 15
    gridmap.tiled_visibility_range = 100
    gridmap.tiled_lod_distance = 50
    gridmap.tiled_far_subdivisions = 0
    gridmap.tiled_items = PackedStringArray(["spiky floor", "spiky box"])
    return
  for area in spawn_areas(gridmap, "goal"):
    area.body_entered.connect(func(body): if body is Player: body.win(area))
  setup_levers()
  for area in spawn_areas(gridmap, "key"):
    add_trigger(area, func(body): if body is Player:
      body.keysCollected += 1
      area.visible=false
      area.disabled=true
      )
  for area in spawn_areas(gridmap, "spiky ball"):
    add_trigger(area, func(body): if body is Player: body.onTick.append(body.die))
  # for area in spawn_areas(gridmap, "speed zone"):
  #   add_trigger(area, func(body): if body is Player: body.onTick.append(func(): if body.currentUserMoveSpeed < 20: body.currentUserMoveSpeed=20))

  var cp_areas := spawn_areas(gridmap, "cp")
  var cp_panes := replace_with_nodes(gridmap, "cp")
  for area in cp_areas:
    var pane: MeshInstance3D = cp_panes[area.get_meta("cell")]
    checkpoints.append({"area": area, "pane": pane})
    area.body_entered.connect(func(body): if body is Player: collect_checkpoint(pane))

  gridmap.rebuild() # apply the cp erase above now, so base_tiles is final
  base_tiles = gridmap.tiles.duplicate()

  var sky_mat := ProceduralSkyMaterial.new()
  sky_mat.sky_top_color = Color("#3d6fb5")
  sky_mat.sky_horizon_color = Color("#c4a0f0")
  sky_mat.ground_horizon_color = Color("#c4a0f0")
  sky_mat.ground_bottom_color = Color("#2a2f4a")

  var sky := Sky.new()
  sky.sky_material = sky_mat

  var env := Environment.new()
  env.background_mode = Environment.BG_SKY
  env.sky = sky
  env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
  env.ambient_light_energy = 0.8

  env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
  env.ssao_enabled = true
  env.ssao_radius = 1.5
  env.ssao_intensity = 2.0
  env.glow_enabled = true
  env.glow_intensity = 0.6
  env.glow_bloom = 0.1

  env.fog_enabled = true
  env.fog_light_color = Color("#c4a0f0")
  env.fog_density = 0.003
  env.fog_sky_affect = 0.3

  env.adjustment_enabled = true
  env.adjustment_saturation = 1.15
  env.adjustment_contrast = 1.05
  var world_env := WorldEnvironment.new()
  world_env.environment = env
  add_child(world_env)

  var sun := DirectionalLight3D.new()
  sun.rotation_degrees = Vector3(-50, -30, 0)
  sun.light_bake_mode = DirectionalLight3D.BAKE_STATIC
  sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
  sun.light_color = Color("#fff1d6")
  sun.shadow_enabled = true
  sun.directional_shadow_max_distance = 60.0
  add_child(sun)
  global.player.levelLoaded()
func spawn_areas(grid: MergedGridMap, tile: String) -> Array[Area3D]:
  var id := grid.mesh_library.find_item_by_name(tile)
  assert(id != -1, "no tile named '%s' in the mesh library" % tile)

  var scene_root: Node = load("res://gridmap/%s/main.tscn" % tile).instantiate()
  var tile_root: Node3D = scene_root.get_child(0)
  var template: Area3D = tile_root.find_children("*", "Area3D", true, false)[0]
  var rel := _relative_transform(template, scene_root)

  var areas: Array[Area3D] = []
  for box in grid.get_boxes_by_item(id):
    var area: Area3D = template.duplicate()
    area.set_meta("cell", box.min) # key shared with replace_with_nodes
    grid.add_child(area)
    area.transform = box.xform * rel # stretched over the whole merged box, like its mesh
    areas.append(area)

  scene_root.free()
  return areas

# transform of node relative to root, same as the plugin uses for shapes
func _relative_transform(node: Node3D, root: Node) -> Transform3D:
  var x := Transform3D.IDENTITY
  while node != root:
    x = node.transform * x
    node = node.get_parent()
  return x
# swaps every merged box of a tile for a standalone MeshInstance3D, returns box min cell -> node
func replace_with_nodes(grid: MergedGridMap, tile: String) -> Dictionary:
  var lib := grid.mesh_library
  var id := lib.find_item_by_name(tile)
  assert(id != -1, "no tile named '%s' in the mesh library" % tile)
  var mesh := lib.get_item_mesh(id)
  var mesh_xform := lib.get_item_mesh_transform(id)

  var nodes := {}
  for box in grid.get_boxes_by_item(id):
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    grid.add_child(mi)
    mi.transform = box.xform * mesh_xform
    nodes[box.min] = mi
  grid.erase_items(id)
  return nodes

func collect_checkpoint(pane: MeshInstance3D) -> void:
  if pane.has_meta("collected"): return
  pane.set_meta("collected", true)
  var t = create_tween()
  t.tween_method(
    func(v: float) -> void: pane.set_instance_shader_parameter("collected", v),
    0.0, 1.0, 0.8)
  t.tween_callback(func(): tweens.erase(t))
  tweens.append(t)
  global.player.setCheckpoint(pane.global_position)
