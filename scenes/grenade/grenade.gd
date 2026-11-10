extends CharacterBody3D
class_name Grenade
# Scene res://scenes/grenade/main.tscn: root CharacterBody3D with this script and a child
# MeshInstance3D (sphere with grenade.gdshader) plus a CollisionShape3D.
# It has NO _process / _physics_process: Player.step() calls tick() once per player tick.

const THROW_SPEED := 25.0
const GRAVITY := 25.0
const BOUNCE := 0.5
const MAX_FUSE_TICKS := 600 # a throw that never lands (falls out of the world) gets this long
const BLAST_RADIUS := 6.0
const BLAST_FORCE := 10.0

var ticks := 0
var fuse_ticks := 1 # set by predict_fuse_ticks() at spawn: ticks until the first surface is hit
var stopTicking = false
@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
  # nothing may collide *with* a grenade (the player would stand on it / be pushed by it, and that
  # can't be reproduced by the resimulation); it still collides with the world through its mask
  collision_layer = 0

# Dry-runs the flight with the same gravity / step as tick() and stores how many ticks pass until the
# first collision. Call once after position + velocity are set and the grenade is in the tree.
# `exclude` = bodies the grenade must fly through (the thrower).
func predict_fuse_ticks(delta: float, exclude: Array[RID]) -> void:
  var params := PhysicsTestMotionParameters3D.new()
  params.exclude_bodies = exclude
  var result := PhysicsTestMotionResult3D.new()
  var xf := global_transform
  var v := velocity
  for n in MAX_FUSE_TICKS:
    v.y -= GRAVITY * delta
    params.from = xf
    params.motion = v * delta
    if PhysicsServer3D.body_test_motion(get_rid(), params, result):
      fuse_ticks = n + 1
      return
    xf.origin += v * delta
  fuse_ticks = MAX_FUSE_TICKS

# 0 at the throw, 1 on the tick it hits its first surface
func fuse() -> float:
  return clampf(float(ticks) / fuse_ticks, 0.0, 1.0)

func tick(delta: float):
  if ticks < fuse_ticks:
    ticks += 1
  mesh.set_instance_shader_parameter("fuse", fuse())
  if stopTicking: return
  velocity.y -= GRAVITY * delta
  var col := move_and_collide(velocity * delta) # explicit motion: no engine delta involved
  if col:
    velocity = Vector3.ZERO
    stopTicking = true
