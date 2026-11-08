@tool
extends EditorPlugin

const GRIDMAP_DIR := "res://gridmap/"
const OUTPUT_NAME := "mesh.tres"

func _apply_changes() -> void:
  var scene := get_editor_interface().get_edited_scene_root()
  if not scene or not scene.scene_file_path.begins_with(GRIDMAP_DIR): return

  var path := scene.scene_file_path.get_base_dir().path_join(OUTPUT_NAME)

  # reuse the loaded instance so open GridMaps pick up the changes
  var lib: MeshLibrary
  if ResourceLoader.exists(path):
    lib = load(path)
    lib.clear()
  else:
    lib = MeshLibrary.new()

  for i in scene.get_child_count():
    var child: Node3D = scene.get_child(i)
    lib.create_item(i)
    lib.set_item_name(i, child.name)

    if child.scene_file_path:
      var dir := child.scene_file_path.get_base_dir()
      var base := child.scene_file_path.get_file().get_basename()
      var preview_a := dir.path_join(base + "_preview.png")
      var preview_b := dir.path_join("previews").path_join(base + ".png")
      if FileAccess.file_exists(preview_a):
        lib.set_item_preview(i, load(preview_a))
      elif FileAccess.file_exists(preview_b):
        lib.set_item_preview(i, load(preview_b))

    var shapes: Array = []
    _collect(lib, i, child, Transform3D.IDENTITY, shapes)
    lib.set_item_shapes(i, shapes)

  var err := ResourceSaver.save(lib, path)
  if err != OK:
    push_error("MeshLibrary save failed (%s): %s" % [path, error_string(err)])
    return
  prints("Saved", lib.get_item_list().size(), "items to", path)

# xform = this node's transform relative to the item root
func _collect(lib: MeshLibrary, i: int, node: Node3D, xform: Transform3D, shapes: Array) -> void:
  if node is MeshInstance3D:
    lib.set_item_mesh(i, _bake_mesh(node))
  elif node is CollisionShape3D:
    shapes.append(node.shape)
    shapes.append(xform)

  for c in node.get_children():
    if c is Node3D:
      _collect(lib, i, c, xform * c.transform, shapes)

# copies the mesh and bakes in whatever material the node actually renders with
func _bake_mesh(node: MeshInstance3D) -> Mesh:
  var mesh: Mesh = node.mesh.duplicate()
  for s in mesh.get_surface_count():
    mesh.surface_set_material(s, node.get_active_material(s))
  return mesh
