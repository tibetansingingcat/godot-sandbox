@tool
extends Node3D
class_name SectorNode

# Store multiple variants of the same sector
var variants: Array[SectorVariant] = []
var active_variant := 0

signal variants_changed
signal active_variant_changed(index: int)

# Configuration
@export var sector_size_x: int
@export var sector_size_y: int
@export var resolution: float
@export var sector_coords: Vector2i
var freshly_created := true

var mesh_instance: MeshInstance3D
var terrain_material: ShaderMaterial

var _ready_called = false

func _ready():
  if _ready_called:
    return
  _ready_called = true
  
  if Engine.is_editor_hint():
    _initialize_sector.call_deferred()
    
func _initialize_sector():
    var scene_root := get_tree().edited_scene_root
    print("Initializing sector")
    
    # CRITICAL: Remove any MeshInstance3D that was saced with the scene
    for child in get_children():
      if child is MeshInstance3D:
        print("Removing stale MeshInstance3D from the scene tree")
        child.owner = null
        remove_child(child)
        child.queue_free()
        
    mesh_instance = MeshInstance3D.new()
    
    ## Check if mesh_instance already exists as a child (loaded from scene)
    #if not mesh_instance:
      #mesh_instance = MeshInstance3D.new()
      #add_child(mesh_instance)
      #if scene_root:
        #mesh_instance.owner = scene_root
          
    # Always ensure material is set up
    if not terrain_material:
      setup_terrain_material()
      
    if not self.owner and scene_root:
      self.owner = scene_root
      
    # Try to load saved variants
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
        
    if not variants.is_empty():
      set_variant(active_variant)
      freshly_created = false
    elif freshly_created:
      print("Creating first variant")
      create_variant()
      freshly_created = false

# Recursively set ownership for all children
func set_ownership_recursive(p_owner: Node, node: Node):
  if not node or not p_owner:
    return
  
  node.owner = p_owner
  for child in node.get_children():
    set_ownership_recursive(p_owner, child)

# Recursively move all children from source to target while preserving hierarchy
func move_children_recursive(source: Node, target: Node, scene_root: Node):
  while source.get_child_count() > 0:
    var child = source.get_child(0)
    if child is MeshInstance3D:
      print("This is probably where this is breaking.")
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
  var verts = PackedVector3Array()
  var nx := int(size_x / resolution)
  var ny := int(size_y / resolution)
  verts.resize((nx + 1) * (ny + 1))
  
  # Generate vertices
  for y in range(ny + 1):
    for x in range(nx + 1):
      var i = y * (nx + 1) + x
      verts[i] = Vector3(x * resolution, 0, y * resolution)
      
  # Generate quads
  var indices = PackedInt32Array()
  indices.resize(nx * ny * 6)
  var idx = 0
  for y in range(ny):
    for x in range(nx):
      var i0 = y * (nx + 1) + x
      var i1 = i0 + 1
      var i2 = i0 + (nx + 1)
      var i3 = i2 + 1
      # first tri (i0, i2, i1)
      indices[idx + 0] = i0
      indices[idx + 1] = i1
      indices[idx + 2] = i2
      
      # second tri (i1, i2, i3)
      indices[idx + 3] = i1
      indices[idx + 4] = i3
      indices[idx + 5] = i2
      idx += 6
      
  var uvs = PackedVector2Array()
  uvs.resize(verts.size())
  for y in range(ny + 1):
    for x in range(nx + 1):
      var i = y * (nx + 1) + x
      # Normalized UVs
      var u = float(x * resolution) / float(size_x)
      var v = float(y * resolution) / float(size_y)
      uvs[i] = Vector2(u, v)
      
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
  var mesh: ArrayMesh
  if mesh_instance and mesh_instance.mesh:
    # Clone the existing mesh
    mesh = mesh_instance.mesh.duplicate(true)
  else:
    # No mesh exists yet, build a fresh flat one
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
  if idx < 0 or idx >= variants.size():
    return
  var variant: SectorVariant = variants[idx]
  var scene_root := get_tree().edited_scene_root

  # --- 1. Save mesh as before
  var mesh_path = "res://terrain/sector_%d_%d_variant%d_mesh.tres" % [sector_coords.x, sector_coords.y, idx]
  ResourceSaver.save(variant.mesh, mesh_path)
  variant.mesh = load(mesh_path)

  # --- 2. Save children
  var ps := PackedScene.new()
  var temp_node = Node3D.new()
  temp_node.name = "VariantRoot"
  
  # Move all non-mesh children to temp node for saving
  var children_to_move = []
  for child in get_children():
    if child != mesh_instance:
      children_to_move.append(child)
  
  for child in children_to_move:
    child.owner = null
    child.reparent(temp_node, false)
    set_ownership_recursive(temp_node, child)
  
  # Pack the temp node with all children
  var pack_result = ps.pack(temp_node)
  if pack_result != OK:
    push_error("Failed to pack children scene for variant %d" % idx)
    return
  
  # Move children back to sector
  move_children_recursive(temp_node, self, scene_root)
  
  # Save the packed scene
  var children_path = "res://terrain/sector_%d_%d_variant%d_children.tscn" % [sector_coords.x, sector_coords.y, idx]
  var save_result = ResourceSaver.save(ps, children_path)
  if save_result != OK:
    push_error("Failed to save children scene at %s" % children_path)
  
  # --- 3. Save the SectorVariant resource itself
  var variant_path = "res://terrain/sector_%d_%d_variant%d.tres" % [sector_coords.x, sector_coords.y, idx]
  var err = ResourceSaver.save(variant, variant_path)
  if err != OK:
    push_error("Failed to save variant at %s" % variant_path)
            
func set_variant(index: int):
  if index < 0 or index >= variants.size():
    return
    
  active_variant = index
  var v: SectorVariant = variants[active_variant]
  var scene_root := get_tree().edited_scene_root

  # --- 1. Remove current non-mesh children
  var children_to_remove = []
  for child in get_children():
    if child != mesh_instance:
      children_to_remove.append(child)
  
  for child in children_to_remove:
    remove_child(child)
    child.queue_free()
  
  # --- 2. Ensure mesh_instance exists in tree
  if mesh_instance.get_parent() != self:
    add_child(mesh_instance)

  # --- 3. Apply mesh and material
  mesh_instance.mesh = v.mesh
  if terrain_material:
    mesh_instance.material_override = terrain_material

  # --- 4. Restore children from scene
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
    
    // Sand to grass transition (height 8-12)
    float rock_blend = smoothstep(8.0, 12.0, height);
    color = mix(color, rock, rock_blend);
    
    // Sand to grass transition (height 18-22)
    float snow_blend = smoothstep(18.0, 22.0, height);
    color = mix(color, snow, snow_blend);
    
    float cliff_blend = smoothstep(0.3, 0.6, slope);
    color = mix(color, rock, cliff_blend);
    
    ALBEDO = color;
}
"""
  terrain_material.shader = shader
