@tool
extends EditorScript

func _rel(n: Node3D, root: Node) -> Transform3D:
  var t := Transform3D.IDENTITY
  while n != root:
    t = n.transform * t
    n = n.get_parent()
  return t

func _run() -> void:
  var root: Node = load("res://gridmap/lever/main.tscn").instantiate()
  var combined := ArrayMesh.new()
  for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
    var xf := _rel(mi, root)
    var arrays := mi.mesh.surface_get_arrays(0)
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
    var nb := xf.basis.inverse().transposed()
    for i in verts.size():
      verts[i] = xf * verts[i]
      norms[i] = (nb * norms[i]).normalized()
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_NORMAL] = norms
    arrays[Mesh.ARRAY_TANGENT] = null
    combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    combined.surface_set_material(combined.get_surface_count() - 1, mi.mesh.surface_get_material(0))
  root.free()
  ResourceSaver.save(combined, "res://lever_combined.res")
