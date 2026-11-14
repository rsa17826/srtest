class_name LaserBeam
extends Node3D
# Beam from this node's origin along -Z. Call update_beam() every physics tick.
# Length = distance to first solid surface (or max_length); returns the hit collider.

const SHADER := preload("res://shaders/laser.gdshader")

@export var max_length := 60.0
@export var radius := 0.12
@export var mask := 1

var mesh_inst: MeshInstance3D
var mat: ShaderMaterial
var impact: MeshInstance3D
var length := 0.0

func _ready() -> void:
  mat = ShaderMaterial.new()
  mat.shader = SHADER
  var cyl := CylinderMesh.new()
  cyl.top_radius = radius
  cyl.bottom_radius = radius
  cyl.height = 1.0
  cyl.radial_segments = 12
  cyl.rings = 1
  cyl.material = mat
  mesh_inst = MeshInstance3D.new()
  mesh_inst.mesh = cyl
  mesh_inst.rotation_degrees.x = 90 # cylinder Y axis -> beam along -Z
  mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  add_child(mesh_inst)

  var sphere := SphereMesh.new()
  sphere.radius = radius * 2.5
  sphere.height = radius * 5.0
  sphere.material = mat
  impact = MeshInstance3D.new()
  impact.mesh = sphere
  impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  add_child(impact)

# power 0..1 (telegraph->fire). thickness scales the beam radius. Returns the collider hit, or null.
func update_beam(power: float, thickness: float, exclude: Array[RID] = []) -> Object:
  var space := get_world_3d().direct_space_state
  var from := global_position
  var to := from + (-global_transform.basis.z) * max_length
  var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
  var hit := space.intersect_ray(q)
  var hit_pos: Vector3 = hit.position if hit else to
  length = from.distance_to(hit_pos)

  mesh_inst.scale = Vector3(thickness, length, thickness)
  mesh_inst.position = Vector3(0, 0, -length * 0.5)
  impact.position = Vector3(0, 0, -length)
  impact.scale = Vector3.ONE * thickness
  impact.visible = true
  mat.set_shader_parameter("length_units", length)
  mat.set_shader_parameter("power", power)
  return hit.collider if hit else null

# Does the beam segment pass within `r` of the point? (used for the kill check on the player)
func distance_to_point(p: Vector3) -> float:
  var a := global_position
  var b := a + (-global_transform.basis.z) * length
  var ab := b - a
  var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
  return p.distance_to(a + ab * t)
