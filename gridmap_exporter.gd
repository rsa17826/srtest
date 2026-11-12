@tool
extends EditorScript

# INSTRUCTIONS:
# 1. Select your GridMap node in the Scene dock.
# 2. Go to File -> Run (or press Ctrl+Shift+X).
# 3. A new MergedGridMap will replace your standard GridMap.

func _run() -> void:
  var root := EditorInterface.get_edited_scene_root()
  if not root:
    printerr("No active scene open.")
    return

  var selection := EditorInterface.get_selection().get_selected_nodes()
  if selection.is_empty() or not (selection[0] is GridMap):
    printerr("Please select a GridMap node in the Scene tree first.")
    return

  var grid_map: GridMap = selection[0]
  var parent := grid_map.get_parent()

  # 1. Create the MergedGridMap instance
  var merged_map := MergedGridMap.new()
  merged_map.name = grid_map.name + "_Merged"
  merged_map.transform = grid_map.transform
  merged_map.mesh_library = grid_map.mesh_library
  merged_map.cell_size = grid_map.cell_size

  # 2. Copy all cell items and orientations from GridMap
  var used_cells := grid_map.get_used_cells()
  for cell in used_cells:
    var item := grid_map.get_cell_item(cell)
    var orientation := grid_map.get_cell_item_orientation(cell)
    merged_map.set_cell_item(cell, item, orientation)

  # 3. Insert into the scene tree and assign owner for saving
  parent.add_child(merged_map)
  merged_map.owner = root

  # 4. Clean up old GridMap
  #grid_map.queue_free()

  print("Successfully converted GridMap '%s' to MergedGridMap!" % grid_map.name)
