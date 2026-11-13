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
# items drawn tiled instead of as one stretched mesh per merged box, for meshes whose detail must not
# stretch. Only the exposed cell faces are drawn (a face touching any other tile is skipped), each as
# a subdivided plane instance in chunked MultiMeshes. Collision still merges.
@export var tiled_items: PackedStringArray = []
@export var tiled_subdivisions := 31 # face grid is (n+1)x(n+1) quads per cell face
@export var tiled_draw_bottom := false # bottom faces are rarely seen, so skipped by default
@export var tiled_chunk_size := 8 # cells per chunk side; chunks are frustum culled separately
@export var tiled_visibility_range := 0.0 # chunks hidden beyond this distance; 0 = never

var _boxes: Array[Node3D] = []
var _body: StaticBody3D # one body for the whole map, one stretched shape per merged box
var _dirty := false
var boxes: Array = [] # merged boxes from the last rebuild: {min, size, item, rot, xform}

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

func local_to_map(pos: Vector3) -> Vector3i:
  return Vector3i((pos / cell_size).floor())

# true if a collision's collider is this map's physics body (it is rebuilt, so don't cache it)
func owns_collider(collider: Object) -> bool:
  return collider == _body

# merged boxes of one item, each with xform = the transform its mesh/collision is stretched by
func get_boxes_by_item(item: int) -> Array:
  if _dirty: rebuild()
  return boxes.filter(func(b: Dictionary) -> bool: return b.item == item)

func erase_items(item: int) -> void:
  for cell in tiles.keys():
    if tiles[cell].x == item:
      tiles.erase(cell)
  _request_rebuild()

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
  if _body != null:
    _body.free()
  _body = StaticBody3D.new()
  add_child(_body, false, Node.INTERNAL_MODE_BACK)

  var tiled_ids := {}
  for item_name in tiled_items:
    var id := mesh_library.find_item_by_name(item_name)
    assert(id != -1, "tiled_items: no tile named '%s' in the mesh library" % item_name)
    tiled_ids[id] = true

  boxes = merge_boxes(tiles)
  for box in boxes:
    var size: Vector3i = box.size
    var rot: int = box.rot
    var local_scale := Vector3(size)
    if rot % 2 == 1:
      local_scale = Vector3(size.z, size.y, size.x)
    var basis := Basis(Vector3.UP, rot * PI / 2.0) * Basis.from_scale(local_scale)
    var center := (Vector3(box.min) + Vector3(size) * 0.5) * cell_size

    var box_xform := Transform3D(basis, center)
    box["xform"] = box_xform
    if not tiled_ids.has(box.item):
      var mi := MeshInstance3D.new()
      mi.mesh = mesh_library.get_item_mesh(box.item)
      mi.transform = box_xform * mesh_library.get_item_mesh_transform(box.item)
      add_child(mi, false, Node.INTERNAL_MODE_BACK) # internal + no owner: never saved
      _boxes.append(mi)

    # collision is stretched like the mesh by resizing a real BoxShape3D per merged box
    # (no node scale, so the physics shape and its debug view are exactly the merged box)
    var shapes := mesh_library.get_item_shapes(box.item) # [Shape3D, Transform3D, Shape3D, Transform3D, ...]
    var rot_xform := Transform3D(Basis(Vector3.UP, rot * PI / 2.0), center)
    for i in range(0, shapes.size(), 2):
      var src: BoxShape3D = shapes[i] # tiles that get merged must use box collision
      var src_xform: Transform3D = shapes[i + 1]
      assert(src_xform.basis.is_equal_approx(Basis.IDENTITY), "merged tile shape must not be rotated or scaled in the mesh library")
      var shape := BoxShape3D.new()
      shape.size = src.size * local_scale
      var cs := CollisionShape3D.new()
      cs.shape = shape
      cs.transform = rot_xform * Transform3D(Basis.IDENTITY, src_xform.origin * local_scale)
      _body.add_child(cs)

  # tiled items: one subdivided plane instance per exposed cell face, split into spatial chunks
  var planes := {} # item -> PlaneMesh
  var chunks := {} # Vector4i(item, chunk x, y, z) -> Array of Transform3D
  for cell: Vector3i in tiles:
    var item: int = tiles[cell].x
    if not tiled_ids.has(item): continue
    var cc := Vector3i((Vector3(cell) / tiled_chunk_size).floor())
    var key := Vector4i(item, cc.x, cc.y, cc.z)
    if not chunks.has(key):
      chunks[key] = []
    var cell_xform := Transform3D(Basis.IDENTITY, map_to_local(cell)) * mesh_library.get_item_mesh_transform(item)
    for d in FACE_DIRS:
      if tiles.has(cell + d): continue
      if d == Vector3i.DOWN and not tiled_draw_bottom: continue
      var face := Transform3D(_face_basis(d) * Basis.from_scale(_face_scale(d)), Vector3(d) * cell_size * 0.5)
      chunks[key].append(cell_xform * face)
    if not planes.has(item):
      var plane := PlaneMesh.new()
      plane.size = Vector2.ONE
      plane.subdivide_width = tiled_subdivisions
      plane.subdivide_depth = tiled_subdivisions
      var mat := mesh_library.get_item_mesh(item).surface_get_material(0)
      assert(mat != null, "tiled item needs a material on surface 0 of its mesh")
      plane.material = mat
      planes[item] = plane

  for key: Vector4i in chunks:
    var xforms: Array = chunks[key]
    if xforms.is_empty(): continue
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = planes[key.x]
    mm.instance_count = xforms.size()
    for i in xforms.size():
      mm.set_instance_transform(i, xforms[i])
    var mmi := MultiMeshInstance3D.new()
    mmi.multimesh = mm
    mmi.visibility_range_end = tiled_visibility_range
    add_child(mmi, false, Node.INTERNAL_MODE_BACK)
    _boxes.append(mmi)

# a PlaneMesh faces +Y; these orient it onto each cube face
const FACE_DIRS := [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.BACK, Vector3i.FORWARD]

func _face_basis(d: Vector3i) -> Basis:
  if d == Vector3i.UP: return Basis.IDENTITY
  if d == Vector3i.DOWN: return Basis(Vector3.RIGHT, PI)
  if d == Vector3i.RIGHT: return Basis(Vector3.BACK, -PI / 2.0)
  if d == Vector3i.LEFT: return Basis(Vector3.BACK, PI / 2.0)
  if d == Vector3i.BACK: return Basis(Vector3.RIGHT, PI / 2.0)
  assert(d == Vector3i.FORWARD, "not a face direction")
  return Basis(Vector3.RIGHT, -PI / 2.0)

# plane-local x/z extents (the plane's y is its normal)
func _face_scale(d: Vector3i) -> Vector3:
  if d.y != 0: return Vector3(cell_size.x, 1.0, cell_size.z)
  if d.x != 0: return Vector3(cell_size.y, 1.0, cell_size.z)
  return Vector3(cell_size.x, 1.0, cell_size.y)

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
