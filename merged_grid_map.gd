@tool
class_name MergedGridMap
extends Node3D

# Stores tiles as cell -> Vector2i(item_id, rotation 0..3) and renders them as the fewest
# MeshInstance3D boxes possible: runs of identical tiles are merged into one stretched mesh.
# Assumes merge-able items are cube meshes of size cell_size centered on the cell.

const INVALID_CELL_ITEM := -1

@export var mesh_library: MeshLibrary
@export var cell_size := Vector3(1, 1, 1)
@export var tiles := {} # Vector3i -> Vector2i(item, rotation)

var _boxes: Array[MeshInstance3D] = []
var _dirty := false

func _ready() -> void:
  rebuild()

# ---------------------------------------------------------------- GridMap-like api

func get_cell_item(cell: Vector3i) -> int:
  if not tiles.has(cell): return INVALID_CELL_ITEM
  return tiles[cell].x

func get_cell_item_orientation(cell: Vector3i) -> int:
  if not tiles.has(cell): return 0
  return tiles[cell].y

func set_cell_item(cell: Vector3i, item: int, orientation: int = 0) -> void:
  if item == INVALID_CELL_ITEM:
    tiles.erase(cell)
  else:
    tiles[cell] = Vector2i(item, orientation)
  _request_rebuild()

func map_to_local(cell: Vector3i) -> Vector3:
  return (Vector3(cell) + Vector3(0.5, 0.5, 0.5)) * cell_size

# ---------------------------------------------------------------- rebuild

func _request_rebuild() -> void:
  if _dirty: return
  _dirty = true
  rebuild.call_deferred()

func rebuild() -> void:
  _dirty = false
  for b in _boxes:
    b.free()
  _boxes.clear()

  for box in merge_boxes(tiles):
    var size: Vector3i = box.size
    var rot: int = box.rot
    var local_scale := Vector3(size)
    if rot % 2 == 1:
      local_scale = Vector3(size.z, size.y, size.x)
    var basis := Basis(Vector3.UP, rot * PI / 2.0) * Basis.from_scale(local_scale)
    var center := (Vector3(box.min) + Vector3(size) * 0.5) * cell_size

    var mi := MeshInstance3D.new()
    mi.mesh = mesh_library.get_item_mesh(box.item)
    mi.transform = Transform3D(basis, center) * mesh_library.get_item_mesh_transform(box.item)
    add_child(mi, false, Node.INTERNAL_MODE_BACK) # internal + no owner: never saved
    _boxes.append(mi)

# ---------------------------------------------------------------- merging

# Greedy box meshing. Returns [{min: Vector3i, size: Vector3i, item: int, rot: int}].
# Scans cells in y,z,x order; each unused cell grows along x, then z, then y while every
# newly covered cell holds the same (item, rotation) and is not already part of a box.
static func merge_boxes(tile_data: Dictionary) -> Array:
  var cells: Array = tile_data.keys()
  cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
    if a.y != b.y: return a.y < b.y
    if a.z != b.z: return a.z < b.z
    return a.x < b.x)

  var used := {}
  var boxes := []
  for c: Vector3i in cells:
    if used.has(c): continue
    var key: Vector2i = tile_data[c]
    var sx := 1
    var sz := 1
    var sy := 1
    while _free(tile_data, used, key, Vector3i(c.x + sx, c.y, c.z)):
      sx += 1
    while _slab_ok(tile_data, used, key, Vector3i(c.x, c.y, c.z + sz), Vector3i(sx, 1, 1)):
      sz += 1
    while _slab_ok(tile_data, used, key, Vector3i(c.x, c.y + sy, c.z), Vector3i(sx, 1, sz)):
      sy += 1

    for y in sy:
      for z in sz:
        for x in sx:
          used[Vector3i(c.x + x, c.y + y, c.z + z)] = true
    boxes.append({"min": c, "size": Vector3i(sx, sy, sz), "item": key.x, "rot": key.y})
  return boxes

static func _free(tile_data: Dictionary, used: Dictionary, key: Vector2i, cell: Vector3i) -> bool:
  return tile_data.has(cell) and not used.has(cell) and tile_data[cell] == key

# every cell in the block starting at `origin` with `extent` cells per axis must be free
static func _slab_ok(tile_data: Dictionary, used: Dictionary, key: Vector2i, origin: Vector3i, extent: Vector3i) -> bool:
  for y in extent.y:
    for z in extent.z:
      for x in extent.x:
        if not _free(tile_data, used, key, origin + Vector3i(x, y, z)):
          return false
  return true
