class_name LaserEnemy
extends Node3D
# Turret that tracks the player, charges (thin telegraph line), fires a deadly beam, then rests.
# Fully driven by player.tickCount, so replays/resimulation see exactly the same cycle.
# Scene: LaserEnemy (this script), no children required. Set `player` to the Player node.

@export var player: Node3D
@export var track_speed := 2.5          # rad/s while tracking
@export var cycle_ticks := 240          # full cycle length
@export var track_ticks := 120          # 0..track: aim at player
@export var charge_ticks := 50          # track..track+charge: locked aim, telegraph
@export var fire_ticks := 40            # then beam is lethal; remainder is cooldown
@export var kill_radius := 0.45
@export var color := Color(1.0, 0.1, 0.15)

var head: Node3D
var beam: LaserBeam
var body_mat: ShaderMaterial
var phase_ticks := 0

func _ready() -> void:
  assert(player, "LaserEnemy needs player")
  # body: hologram-ish dark sphere with a bright eye
  var m := StandardMaterial3D.new()
  m.albedo_color = Color(0.08, 0.08, 0.1)
  m.emission_enabled = true
  m.emission = color
  m.emission_energy_multiplier = 0.4
  var base := MeshInstance3D.new()
  var sph := SphereMesh.new()
  sph.radius = 0.5
  sph.height = 1.0
  sph.material = m
  base.mesh = sph
  add_child(base)

  head = Node3D.new()
  add_child(head)
  beam = LaserBeam.new()
  beam.position = Vector3(0, 0, -0.5)
  head.add_child(beam)

  var eye := MeshInstance3D.new()
  var es := SphereMesh.new()
  es.radius = 0.14
  es.height = 0.28
  var em := StandardMaterial3D.new()
  em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
  em.albedo_color = color
  es.material = em
  eye.mesh = es
  eye.position = Vector3(0, 0, -0.45)
  head.add_child(eye)
  beam.mat.set_shader_parameter("color", color)

func _physics_process(delta: float) -> void:
  phase_ticks = player.tickCount % cycle_ticks
  var target: Vector3 = player.global_position + Vector3.UP * 0.5

  var power := 0.0
  var thickness := 0.3
  var lethal := false
  if phase_ticks < track_ticks:
    _aim(target, track_speed * delta)
    power = 0.12            # faint sight line while tracking
    thickness = 0.15
  elif phase_ticks < track_ticks + charge_ticks:
    var t := float(phase_ticks - track_ticks) / charge_ticks
    power = lerpf(0.15, 0.8, t * t)
    thickness = lerpf(0.15, 0.4, t)
  elif phase_ticks < track_ticks + charge_ticks + fire_ticks:
    var t := float(phase_ticks - track_ticks - charge_ticks) / fire_ticks
    power = 1.0
    thickness = 1.0 + 0.3 * sin(t * PI) # slight swell
    lethal = true
  else:
    power = 0.0

  beam.visible = power > 0.0
  beam.update_beam(power, thickness, [player.get_rid()])
  if lethal and beam.distance_to_point(target) < kill_radius + 0.0:
    player.onTick.append(player.die)

func _aim(target: Vector3, max_step: float) -> void:
  var want := head.global_transform.looking_at(target, Vector3.UP).basis.get_rotation_quaternion()
  var cur := head.global_transform.basis.get_rotation_quaternion()
  var angle := cur.angle_to(want)
  var q := cur if angle < 0.0001 else cur.slerp(want, minf(1.0, max_step / angle))
  head.global_transform.basis = Basis(q)
