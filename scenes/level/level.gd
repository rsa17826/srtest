extends Node3D
class_name Level

@export var gridmap: GridMap
func _init() -> void:
  global.level = self

func _ready() -> void:
  for area in spawn_areas(gridmap, "goal"):
    area.body_entered.connect(func(body): if body is Player: body.win(area))
  # TODO
  # for area in spawn_areas(gridmap, "cp"):
  #   area.body_entered.connect(func(body): if body is Player: area.get_parent().collect())

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
  sun.light_color = Color("#fff1d6")
  sun.shadow_enabled = true
  sun.directional_shadow_max_distance = 60.0
  add_child(sun)
func spawn_areas(grid: GridMap, tile: String) -> Array[Area3D]:
  var id := grid.mesh_library.find_item_by_name(tile)
  assert(id != -1, "no tile named '%s' in the mesh library" % tile)

  var scene_root: Node = load("res://gridmap/%s/main.tscn" % tile).instantiate()
  var tile_root: Node3D = scene_root.get_child(0)
  var template: Area3D = tile_root.find_children("*", "Area3D", true, false)[0]
  var rel := _relative_transform(template, scene_root)

  var areas: Array[Area3D] = []
  for cell in grid.get_used_cells_by_item(id):
    var area: Area3D = template.duplicate()
    area.set_meta("cell", cell) # new line
    grid.add_child(area)
    var cell_xform := Transform3D(grid.get_cell_item_basis(cell), grid.map_to_local(cell))
    area.transform = cell_xform * rel
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
