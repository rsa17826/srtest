extends CharacterBody3D
class_name Grenade
# Scene res://scenes/grenade/main.tscn: root CharacterBody3D with this script and a child
# MeshInstance3D (sphere with grenade.gdshader) plus a CollisionShape3D.
# It has NO _process / _physics_process: Player.step() calls tick() once per player tick.

const THROW_SPEED := 14.0
const GRAVITY := 25.0
const BOUNCE := 0.5
const FUSE_TICKS := 200
const BLAST_RADIUS := 6.0
const BLAST_FORCE := 25.0

var ticks := 0
@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
  # nothing may collide *with* a grenade (the player would stand on it / be pushed by it, and that
  # can't be reproduced by the resimulation); it still collides with the world through its mask
  collision_layer = 0

# returns true on the tick it should explode
func tick(delta: float) -> bool:
  velocity.y -= GRAVITY * delta
  var col := move_and_collide(velocity * delta) # explicit motion: no engine delta involved
  if col:
    velocity = Vector3.ZERO
  ticks += 1
  mesh.set_instance_shader_parameter("fuse", float(ticks) / FUSE_TICKS)
  return ticks >= FUSE_TICKS
