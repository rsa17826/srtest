extends Node3D

func _ready() -> void:
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
