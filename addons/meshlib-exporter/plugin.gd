@tool
extends EditorPlugin

const GRIDMAP_DIR := "res://gridmap/"
const SCENE_NAME := "main.tscn"
const LIB_PATH := "res://gridmap/mesh.tres"

func _apply_changes() -> void:
  var edited := get_editor_interface().get_edited_scene_root()
  if not edited: return
  var edited_path := edited.scene_file_path
  if not edited_path.begins_with(GRIDMAP_DIR) or edited_path.get_file() != SCENE_NAME: return

  # reuse the loaded instance so open GridMaps update live and IDs persist
  var lib: MeshLibrary = load(LIB_PATH) if ResourceLoader.exists(LIB_PATH) else MeshLibrary.new()

  for folder in DirAccess.get_directories_at(GRIDMAP_DIR):
    var scene_path := GRIDMAP_DIR.path_join(folder).path_join(SCENE_NAME)
    if not ResourceLoader.exists(scene_path): continue

    if scene_path == edited_path:
      # the open scene holds the unsaved changes, so read it directly
      _sync_scene(lib, folder, edited)
    else:
      var root: Node = (load(scene_path) as PackedScene).instantiate()
      _sync_scene(lib, folder, root)
      root.free()

  var err := ResourceSaver.save(lib, LIB_PATH)
  if err != OK:
    push_error("MeshLibrary save failed (%s): %s" % [LIB_PATH, error_string(err)])
    return
  prints("Saved", lib.get_item_list().size(), "items to", LIB_PATH)

func _sync_scene(lib: MeshLibrary, folder: String, root: Node) -> void:
  var count := root.get_child_count()
  for c in root.get_children():
    var child: Node3D = c
    var item_name := folder if count == 1 else folder + "/" + child.name

    var id := lib.find_item_by_name(item_name)
    if id == -1:
      id = lib.get_last_unused_item_id()
      lib.create_item(id)
      lib.set_item_name(id, item_name)

    var result := {"mesh": null, "mesh_transform": Transform3D.IDENTITY, "cast_shadow": 0, "shapes": []}
    _collect(child, child.transform, result)
    lib.set_item_mesh(id, result.mesh)
    lib.set_item_mesh_transform(id, result.mesh_transform)
    lib.set_item_navigation_mesh_transform(id, result.mesh_transform)
    lib.set_item_mesh_cast_shadow(id, result.cast_shadow)
    lib.set_item_shapes(id, result.shapes)

func _collect(node: Node3D, xform: Transform3D, result: Dictionary, in_area:=false) -> void:
  in_area = in_area or node is Area3D

  if node is MeshInstance3D:
    result.mesh = _bake_mesh(node)
    result.mesh_transform = xform
    result.cast_shadow = node.cast_shadow
  elif node is CollisionShape3D and not in_area:
    result.shapes.append(node.shape)
    result.shapes.append(xform)

  for c in node.get_children():
    if c is Node3D:
      _collect(c, xform * c.transform, result, in_area)

# copy the mesh and bake in the material it actually renders with
func _bake_mesh(node: MeshInstance3D) -> Mesh:
  var mesh: Mesh = node.mesh.duplicate()
  for s in mesh.get_surface_count():
    mesh.surface_set_material(s, node.get_active_material(s))
  return mesh
