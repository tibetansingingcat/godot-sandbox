## sector_node.gd — One tile of the terrain grid
##
## A SectorNode represents a single rectangular patch of terrain. It is a
## child of TerrainRoot and is positioned at its grid cell in world space.
##
## Each sector supports multiple VARIANTS — alternative versions of the same
## tile with different sculpted geometry and scene children (trees, props, etc).
## Only one variant is visible at a time. This lets you create multiple versions
## of an area and switch between them without losing work.
##
## Persistence:
##   Each variant saves 3 files to res://terrain/:
##     sector_X_Y_variantN.tres         — SectorVariant resource (name, requirements, guarantees)
##     sector_X_Y_variantN_mesh.tres    — ArrayMesh with the sculpted vertex data
##     sector_X_Y_variantN_children.tscn — PackedScene of non-mesh children (props, etc)
##
## Signals:
##   variants_changed        — emitted when a variant is created or removed.
##                              The SectorNodeInspector listens to rebuild its UI.
##   active_variant_changed  — emitted when set_variant() switches which variant is displayed.
##                              The SectorNodeInspector listens to update the [Active] label.
@tool
extends Node3D
class_name SectorNode

var variants: Array[SectorVariant] = []
var active_variant := 0

signal variants_changed
signal active_variant_changed(index: int)

# --- Configuration (set by TerrainRoot.build_grid()) ---
@export var sector_size_x: int
@export var sector_size_y: int
@export var resolution: float
@export var sector_coords: Vector2i   ## Grid position (e.g. 3,5 = column 3, row 5)
var freshly_created := true           ## True until the first variant is created or loaded

var mesh_instance: MeshInstance3D
var terrain_material: ShaderMaterial

var _ready_called = false

func _ready():
  if _ready_called:
    return
  _ready_called = true
  # Defer initialization so the scene tree is fully built before we
  # query children, load resources, and create mesh instances.
  _initialize_sector.call_deferred()

func _initialize_sector():
    var scene_root := get_tree().edited_scene_root if Engine.is_editor_hint() else null
    print("Initializing sector")

    # Remove any MeshInstance3D that was saved with the scene file.
    # We manage mesh_instance ourselves at runtime — stale ones from a previous
    # session would cause duplicates.
    if Engine.is_editor_hint():
      for child in get_children():
        if child is MeshInstance3D:
          print("Removing stale MeshInstance3D from the scene tree")
          child.owner = null
          remove_child(child)
          child.queue_free()

    if not mesh_instance:
      mesh_instance = MeshInstance3D.new()

    if not terrain_material:
      setup_terrain_material()

    if Engine.is_editor_hint() and not self.owner and scene_root:
      self.owner = scene_root

    # Load any previously saved variants from disk (variant0, variant1, ...).
    # We probe files sequentially and stop at the first missing index.
    var variant_index = 0
    while true:
      var variant_path = "res://terrain/sector_%d_%d_variant%d.tres" % [sector_coords.x, sector_coords.y, variant_index]
      if FileAccess.file_exists(variant_path):
        var saved_variant = load(variant_path) as SectorVariant
        if saved_variant:
          variants.append(saved_variant)
          print("Loaded variant %d for sector %s" % [variant_index, sector_coords])
          variant_index += 1
        else:
          break
      else:
        break

    # If we loaded variants, display the first one. Otherwise, create a default
    # flat variant so there's always something to sculpt.
    if not variants.is_empty():
      set_variant(active_variant)
      freshly_created = false
    elif Engine.is_editor_hint() and freshly_created:
      print("Creating first variant")
      create_variant()
      freshly_created = false

func set_ownership_recursive(p_owner: Node, node: Node):
  ## Set owner on a node and all its descendants. Required for the editor to
  ## persist nodes that were added at runtime (not part of the original scene).
  if not node or not p_owner:
    return
  node.owner = p_owner
  for child in node.get_children():
    set_ownership_recursive(p_owner, child)

func move_children_recursive(source: Node, target: Node, scene_root: Node):
  ## Move all children from source into target, preserving their subtrees.
  ## Used when saving (sector → temp node for packing) and restoring
  ## (packed scene instance → sector) variant children.
  while source.get_child_count() > 0:
    var child = source.get_child(0)
    child.owner = null
    child.reparent(target, false)
    if scene_root:
      set_ownership_recursive(scene_root, child)

func save_current():
  save_variant(active_variant)

func save_all():
  for i in range(variants.size()):
    save_variant(i)

func build_terrain(size_x: int, size_y: int, resolution: float = 1.0) -> ArrayMesh:
  ## Generate a flat grid mesh for a new sector. The mesh is a regular grid of
  ## quads, each split into two triangles. All vertices start at y=0 (flat).
  ##
  ## Grid layout (nx=3, ny=2 example):
  ##   Row 0:  v0 — v1 — v2 — v3       nx = size_x / resolution (verts per row)
  ##           |  / |  / |  / |         ny = size_y / resolution (verts per column)
  ##   Row 1:  v4 — v5 — v6 — v7       Total vertices: (nx+1) * (ny+1)
  ##           |  / |  / |  / |         Total triangles: nx * ny * 2
  ##   Row 2:  v8 — v9 — v10— v11
  ##
  ## Vertex index formula: i = y * (nx + 1) + x
  var verts = PackedVector3Array()
  var nx := int(size_x / resolution)
  var ny := int(size_y / resolution)
  verts.resize((nx + 1) * (ny + 1))

  for y in range(ny + 1):
    for x in range(nx + 1):
      var i = y * (nx + 1) + x
      verts[i] = Vector3(x * resolution, 0, y * resolution)

  # Triangulate each quad into two triangles.
  # For quad at grid cell (x, y):
  #   i0=top-left  i1=top-right  i2=bottom-left  i3=bottom-right
  #   Tri 1: i0, i1, i2    Tri 2: i1, i3, i2
  var indices = PackedInt32Array()
  indices.resize(nx * ny * 6)
  var idx = 0
  for y in range(ny):
    for x in range(nx):
      var i0 = y * (nx + 1) + x
      var i1 = i0 + 1
      var i2 = i0 + (nx + 1)
      var i3 = i2 + 1
      indices[idx + 0] = i0
      indices[idx + 1] = i1
      indices[idx + 2] = i2
      indices[idx + 3] = i1
      indices[idx + 4] = i3
      indices[idx + 5] = i2
      idx += 6

  # UVs normalized to [0, 1] across the sector
  var uvs = PackedVector2Array()
  uvs.resize(verts.size())
  for y in range(ny + 1):
    for x in range(nx + 1):
      var i = y * (nx + 1) + x
      var u = float(x * resolution) / float(size_x)
      var v = float(y * resolution) / float(size_y)
      uvs[i] = Vector2(u, v)

  # All normals point up on a flat mesh; recalculated after sculpting
  var normals = PackedVector3Array()
  normals.resize(verts.size())
  for i in range (verts.size()):
    normals[i] = Vector3.UP

  var arrays = []
  arrays.resize(Mesh.ARRAY_MAX)
  arrays[Mesh.ARRAY_VERTEX] = verts
  arrays[Mesh.ARRAY_INDEX] = indices
  arrays[Mesh.ARRAY_TEX_UV] = uvs
  arrays[Mesh.ARRAY_NORMAL] = normals

  var mesh = ArrayMesh.new()
  mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
  return mesh
  
func create_variant():
  ## Create a new variant by duplicating the current mesh (so you start from
  ## the current sculpt state) or building a fresh flat mesh if none exists.
  var mesh: ArrayMesh
  if mesh_instance and mesh_instance.mesh:
    mesh = mesh_instance.mesh.duplicate(true)
  else:
    mesh_instance = MeshInstance3D.new()
    add_child(mesh_instance)
    mesh = build_terrain(sector_size_x, sector_size_y, resolution)
    mesh_instance.mesh = mesh
  add_variant(mesh)
  emit_signal("variants_changed")
    
func add_variant(mesh: ArrayMesh):
  var new_variant = SectorVariant.new()
  new_variant.mesh = mesh
  variants.append(new_variant)
  if variants.size() == 1:
    set_variant(0)
    
func save_variant(idx: int):
  ## Persist a variant to disk as 3 files:
  ##   1. The mesh geometry (_mesh.tres)
  ##   2. The non-mesh children as a packed scene (_children.tscn)
  ##   3. The SectorVariant resource itself (.tres) — holds name, requires, guarantees
  ##
  ## Children saving works by temporarily reparenting all non-mesh children into
  ## a temp Node3D, packing that into a PackedScene, saving it, then moving the
  ## children back. This is necessary because PackedScene.pack() needs a root node
  ## that owns all the children.
  if idx < 0 or idx >= variants.size():
    return
  var variant: SectorVariant = variants[idx]
  var scene_root := get_tree().edited_scene_root

  # 1. Save mesh
  var mesh_path = "res://terrain/sector_%d_%d_variant%d_mesh.tres" % [sector_coords.x, sector_coords.y, idx]
  ResourceSaver.save(variant.mesh, mesh_path)
  variant.mesh = load(mesh_path)  # Reload so the resource path is set

  # 2. Save children — move to temp node, pack, save, move back
  var ps := PackedScene.new()
  var temp_node = Node3D.new()
  temp_node.name = "VariantRoot"

  var children_to_move = []
  for child in get_children():
    if child != mesh_instance:
      children_to_move.append(child)

  for child in children_to_move:
    child.owner = null
    child.reparent(temp_node, false)
    set_ownership_recursive(temp_node, child)

  var pack_result = ps.pack(temp_node)
  if pack_result != OK:
    push_error("Failed to pack children scene for variant %d" % idx)
    return

  move_children_recursive(temp_node, self, scene_root)  # Move children back

  var children_path = "res://terrain/sector_%d_%d_variant%d_children.tscn" % [sector_coords.x, sector_coords.y, idx]
  var save_result = ResourceSaver.save(ps, children_path)
  if save_result != OK:
    push_error("Failed to save children scene at %s" % children_path)

  # 3. Save the variant resource (name, requirements, guarantees, mesh reference)
  var variant_path = "res://terrain/sector_%d_%d_variant%d.tres" % [sector_coords.x, sector_coords.y, idx]
  var err = ResourceSaver.save(variant, variant_path)
  if err != OK:
    push_error("Failed to save variant at %s" % variant_path)
            
func set_variant(index: int):
  ## Switch the displayed variant. This:
  ##   1. Removes all current non-mesh children (props, etc.)
  ##   2. Swaps the mesh to the new variant's mesh
  ##   3. Rebuilds collision from the new mesh
  ##   4. Restores the new variant's children from its saved .tscn file
  ##   5. Emits active_variant_changed so the inspector updates
  if index < 0 or index >= variants.size():
    return

  active_variant = index
  var v: SectorVariant = variants[active_variant]
  var scene_root := get_tree().edited_scene_root

  # 1. Remove current children (except the mesh instance)
  var children_to_remove = []
  for child in get_children():
    if child != mesh_instance:
      children_to_remove.append(child)
  for child in children_to_remove:
    remove_child(child)
    child.queue_free()

  # 2. Ensure mesh_instance is in the tree
  if mesh_instance.get_parent() != self:
    add_child(mesh_instance)

  # 3. Apply mesh and material
  mesh_instance.mesh = v.mesh
  if terrain_material:
    mesh_instance.material_override = terrain_material

  # 4. Rebuild trimesh collision from the new mesh
  if mesh_instance.mesh:
    for child in mesh_instance.get_children():
      mesh_instance.remove_child(child)
      child.queue_free()
    mesh_instance.create_trimesh_collision()

  # 5. Restore saved children (props, trees, etc.) from the packed scene
  var children_path = "res://terrain/sector_%d_%d_variant%d_children.tscn" % [sector_coords.x, sector_coords.y, active_variant]
  if FileAccess.file_exists(children_path):
    var ps: PackedScene = load(children_path)
    if ps:
      var inst = ps.instantiate()
      if inst:
        move_children_recursive(inst, self, scene_root)
        inst.queue_free()

  emit_signal("active_variant_changed", active_variant)
  
func cycle_variant():
  set_variant((active_variant + 1) % variants.size())
  
func remove_variant(idx: int):
  ## Delete a variant and its files from disk. After deletion, files for
  ## higher-indexed variants are renamed down by one to keep indices contiguous
  ## (e.g. if variant1 is deleted, variant2 becomes variant1 on disk).
  if idx < 0 or idx >= variants.size():
    push_error("Invalid variant index for deletion: %d" % idx)
    return

  if variants.size() <= 1:
    push_error("Can't remove last variant.")
    return
    
  var mesh_path = "res://terrain/sector_%d_%d_variant%d_mesh.tres" % [sector_coords.x, sector_coords.y, idx]
  var children_path = "res://terrain/sector_%d_%d_variant%d_children.tscn" % [sector_coords.x, sector_coords.y, idx]
  var variant_path = "res://terrain/sector_%d_%d_variant%d.tres" % [sector_coords.x, sector_coords.y, idx]

  if FileAccess.file_exists(mesh_path):
    DirAccess.remove_absolute(mesh_path)
  if FileAccess.file_exists(children_path):
    DirAccess.remove_absolute(children_path)
  if FileAccess.file_exists(variant_path):
    DirAccess.remove_absolute(variant_path)

  # Rename files above the deleted index down by one so indices stay contiguous
  for i in range(idx + 1, variants.size()):
    var sx = sector_coords.x
    var sy = sector_coords.y
    for suffix in ["_mesh.tres", "_children.tscn", ".tres"]:
      var old_path = "res://terrain/sector_%d_%d_variant%d%s" % [sx, sy, i, suffix]
      var new_path = "res://terrain/sector_%d_%d_variant%d%s" % [sx, sy, i - 1, suffix]
      if FileAccess.file_exists(old_path):
        DirAccess.rename_absolute(old_path, new_path)

  variants.remove_at(idx)
  
  if active_variant >= variants.size():
    active_variant = variants.size() - 1
    
  set_variant(active_variant)
  
  emit_signal("variants_changed")
  
  
func refresh_mesh_display():
  print("Refreshing mesh display")
  if mesh_instance and variants and active_variant < variants.size():
    mesh_instance.mesh = variants[active_variant].mesh

func setup_terrain_material():
  terrain_material = ShaderMaterial.new()
  var shader = Shader.new()
  shader.code = """
shader_type spatial;

varying vec3 world_position;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float height = world_position.y;
    
    // Calculate slope (0 = flat, 1 = vertical)
    float slope = 1.0 - NORMAL.y;
    
    // Define colors
    vec3 sand = vec3(0.76, 0.70, 0.50);
    vec3 grass = vec3(0.3, 0.6, 0.3); 
    vec3 rock = vec3(0.5, 0.5, 0.5); 
    vec3 snow = vec3(0.9, 0.9, 1.0); 
    
    // Blend smoothly between height zones
    vec3 color = sand;
    
    // Sand to grass transition (height 0-4)
    float grass_blend = smoothstep(0.0, 4.0, height);
    color = mix(sand, grass, grass_blend);
    
    // Grass to rock transition (height 8-12)
    float rock_blend = smoothstep(8.0, 12.0, height);
    color = mix(color, rock, rock_blend);

    // Rock to snow transition (height 18-22)
    float snow_blend = smoothstep(18.0, 22.0, height);
    color = mix(color, snow, snow_blend);
    
    float cliff_blend = smoothstep(0.3, 0.6, slope);
    color = mix(color, rock, cliff_blend);
    
    ALBEDO = color;
}
"""
  terrain_material.shader = shader
