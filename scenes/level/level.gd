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
var explosions: Array = [] # [{"pos": Vector3, "radius": float}] in order, for the current run

# Breaks breakable walls near a grenade explosion. Rebuilds immediately (not deferred) so the new
# collision exists for the rest of this physics tick, which the resimulation relies on.
func explode(world_pos: Vector3, radius: float) -> void:
  explosions.append({"pos": world_pos, "radius": radius})
  if _break_walls(world_pos, radius):
    gridmap.rebuild()

# true if any wall was erased. Does not rebuild.
func _break_walls(world_pos: Vector3, radius: float) -> bool:
  const BREAKABLE_TILE := "cracked wall"
  var id := gridmap.mesh_library.find_item_by_name(BREAKABLE_TILE)
  assert(id != -1, "no tile named '%s' in the mesh library" % BREAKABLE_TILE)
  return gridmap.erase_item_in_radius(id, gridmap.to_local(world_pos), 2)

# walls as they are after the first `count` explosions of `list`
func set_walls(list: Array, count: int) -> void:
  for i in count:
    _break_walls(list[i].pos, list[i].radius)

func removeDoors() -> void:
  log.pp("asdasdasd")
  var id := gridmap.mesh_library.find_item_by_name("door")
  for cell in gridmap.tiles.keys():
    if gridmap.tiles[cell].x == id:
      gridmap.tiles.erase(cell)

# restores every broken wall (full restart). Before any explosion there is nothing to restore.
func reset_walls() -> void:
  if explosions.is_empty(): return
  explosions.clear()
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
  for area in spawn_areas(gridmap, "lever"):
    area.body_entered.connect(func(body): if body is Player:
      removeDoors()
      gridmap.rebuild()
      )
  # for area in spawn_areas(gridmap, "cracked wall"):
  #   add_trigger(area, func(body): if body is Player: body.onTick.append(body.die))
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
