@tool
extends RefCounted
class_name SculptingHandler

const Tool = SculptingEnums.Tool
const SculptMode = SculptingEnums.SculptMode

const SCULPT_SPEED = 0.05

var dock_ui: Control
var current_terrain_root: TerrainRoot
var current_sector_node: SectorNode
var is_sculpting := false

var brush_preview: MeshInstance3D
var brush_material: StandardMaterial3D
var brush_size: float = 2.0
var brush_strength: float = 1.0

var sculpt_mode: SculptMode
var tool: Tool

var editor_selection: EditorSelection
var last_affected_sectors: Array[SectorNode] = []

var undo_redo: EditorUndoRedoManager
var sculpt_start_meshes: Dictionary[SectorNode, ArrayMesh] = {} # Store meshes at start of stroke

var grid_lines_node: MeshInstance3D = null

func _init():
  if Engine.is_editor_hint():
    undo_redo = EditorInterface.get_editor_undo_redo()
    editor_selection = EditorInterface.get_selection()
    editor_selection.selection_changed.connect(_on_selection_changed)
    
func set_dock_ui(ui: Control):
  dock_ui = ui
    
func _on_selection_changed():
  # Check if selected object is a TerrainRoot or child of one
  var selected = editor_selection.get_selected_nodes()
  current_terrain_root = null
  current_sector_node = null  # Add this - clear it first
  
  for node in selected:
    if node is TerrainRoot:
      current_terrain_root = node
      print("Selected TerrainRoot: ", node.name)
      break
    if node is SectorNode:
      current_sector_node = node
      current_terrain_root = current_sector_node.get_parent()
      print("Selected SectorNode: ", node.name)
      break

    var parent = node.get_parent()
    while parent:
      if parent is TerrainRoot:
        current_terrain_root = parent
        print("Selected TerrainRoot: ", parent.name)
        break
      parent = parent.get_parent()
    if current_terrain_root:
      break
        
  # Clean up old grid
  if grid_lines_node and grid_lines_node.get_parent():
    grid_lines_node.get_parent().remove_child(grid_lines_node)
    grid_lines_node.queue_free()
    grid_lines_node = null
    
  if current_terrain_root and not current_sector_node:
    print("Create sector grid")
    create_sector_grid()
    
func create_sector_grid():
  if not current_terrain_root:
    return
  
  grid_lines_node = MeshInstance3D.new()
  var immediate_mesh = ImmediateMesh.new()
  grid_lines_node.mesh = immediate_mesh
  
  immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
  
  for x in range(current_terrain_root.sectors_x + 1):
    var x_pos = x * current_terrain_root.sector_size_x
    immediate_mesh.surface_add_vertex(Vector3(x_pos, 0.5, 0))
    immediate_mesh.surface_add_vertex(Vector3(x_pos, 0.5, current_terrain_root.sectors_y * current_terrain_root.sector_size_y))
    
  for y in range(current_terrain_root.sectors_y + 1):
    var z_pos = y * current_terrain_root.sector_size_y
    immediate_mesh.surface_add_vertex(Vector3(0, 0.5, z_pos))
    immediate_mesh.surface_add_vertex(Vector3(current_terrain_root.sectors_x * current_terrain_root.sector_size_x, 0.5, z_pos))
    
  immediate_mesh.surface_end()
  
  # Create unshaded material
  var mat = StandardMaterial3D.new()
  mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
  mat.albedo_color = Color.RED
  grid_lines_node.material_override = mat
  
  current_terrain_root.add_child(grid_lines_node)
  
  

func handles(object) -> bool:
  if object is TerrainRoot:
    current_terrain_root = object
    return true
  return false
  
func get_sector_at_postion(world_pos: Vector3) -> SectorNode:
  if not current_terrain_root or not current_terrain_root.is_inside_tree():
    return
  var local_pos = current_terrain_root.to_local(world_pos)
  
  var sector_x = int(local_pos.x / current_terrain_root.sector_size_x)
  var sector_y = int(local_pos.z / current_terrain_root.sector_size_y)
  
  if sector_x < 0 or sector_x >= current_terrain_root.sectors_x or \
    sector_y < 0 or sector_y >= current_terrain_root.sectors_y:
      return null
      
  return current_terrain_root.get_sector(sector_x, sector_y)

func handle_3d_input(camera: Camera3D, event: InputEvent) -> int:
  if not current_terrain_root:
    print("not current terrain root")
    return EditorPlugin.AFTER_GUI_INPUT_PASS
    
  if tool == Tool.SELECT:
    if event is InputEventMouseButton:
      if event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
        var hit_pos = get_terrain_hit_position(camera, event.position)
        if hit_pos != Vector3.INF:
          var clicked_sector = get_sector_at_postion(hit_pos)
          if clicked_sector:
            editor_selection.clear()
            editor_selection.add_node(clicked_sector)
            return EditorPlugin.AFTER_GUI_INPUT_STOP
    return EditorPlugin.AFTER_GUI_INPUT_PASS
  
  if event is InputEventMouseMotion:
    update_brush_preview(camera, event.position)
    
    if is_sculpting:
      var affected = get_sectors_in_brush(get_terrain_hit_position(camera, event.position))
      for sector in affected:
        if sculpt_start_meshes.has(sector): 
          continue
        sculpt_start_meshes[sector] = sector.variants[sector.active_variant].mesh.duplicate()
      sculpt_at_position(camera, event.position)
      print("sculpt_start_meshes size: ", sculpt_start_meshes.size())
      return EditorPlugin.AFTER_GUI_INPUT_STOP
  
  elif event is InputEventMouseButton:
    if event.button_index == MOUSE_BUTTON_LEFT:
      if event.pressed:
        is_sculpting = true
        var affected = get_sectors_in_brush(get_terrain_hit_position(camera, event.position))
        for sector in affected:
          sculpt_start_meshes[sector] = sector.variants[sector.active_variant].mesh.duplicate()
          
        sculpt_at_position(camera, event.position)
        return EditorPlugin.AFTER_GUI_INPUT_STOP
      else:
        is_sculpting = false
        update_collision_for_affected_sectors()
        finalize_sculpt_stroke()
        return EditorPlugin.AFTER_GUI_INPUT_STOP
    
  return EditorPlugin.AFTER_GUI_INPUT_PASS
  
func finalize_sculpt_stroke():
  if sculpt_start_meshes.is_empty():
    return
    
  print("Creating undo action for ", sculpt_start_meshes.size(), " sectors")
  undo_redo.create_action("Sculpt Terrain")
  
  for sector: SectorNode in sculpt_start_meshes.keys():
    var variant = sector.variants[sector.active_variant]
    var old_mesh = sculpt_start_meshes[sector]
    var new_mesh = variant.mesh.duplicate()
    
    # Verify sector is still valid
    if not is_instance_valid(sector) or not sector.is_inside_tree():
      continue
    
    if not new_mesh or not new_mesh.get_surface_count() > 0:
      push_error("Invalid mesh duplication!")
      continue
    
    undo_redo.add_do_property(variant, "mesh", new_mesh)
    undo_redo.add_undo_property(variant, "mesh", old_mesh)
    
    undo_redo.add_do_method(sector, "refresh_mesh_display")
    undo_redo.add_undo_method(sector, "refresh_mesh_display")
    
  undo_redo.commit_action()
  sculpt_start_meshes.clear()
  
func update_collision_for_affected_sectors():
  print("Updating collision...")
  for sector in last_affected_sectors:
    if not is_instance_valid(sector) or not sector.is_inside_tree():
      print("Skipping invalid sector")
      continue
      
    if not sector.mesh_instance:
      print("Skipping sector with no mesh_instance")
      continue
      
    # Clear old collision
    for child in sector.mesh_instance.get_children():
      sector.mesh_instance.remove_child(child)
      child.queue_free()
    
    sector.mesh_instance.create_trimesh_collision()
  last_affected_sectors.clear()
  
func get_terrain_hit_position(camera: Camera3D, mouse_pos: Vector2) -> Vector3:
  if not current_terrain_root or not current_terrain_root.is_inside_tree():
    return Vector3.INF
    
  var from = camera.project_ray_origin(mouse_pos)
  var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
  
  var space_state = current_terrain_root.get_world_3d().direct_space_state
  var query = PhysicsRayQueryParameters3D.create(from, to)
  var result = space_state.intersect_ray(query)
  
  if result:
    return result.position
  
  var plane = Plane(Vector3.UP, 0)
  var intersection = plane.intersects_ray(from, to - from)
  
  if intersection:
    return intersection
    
  return Vector3.INF

func update_brush_preview(camera: Camera3D, mouse_pos: Vector2):
  if not current_terrain_root or not current_terrain_root.is_inside_tree():
    if brush_preview:
      brush_preview.get_parent().remove_child(brush_preview)
      brush_preview.queue_free()
    return
    
  if current_terrain_root.get_child_count() == 0:
    return
    
  if tool == Tool.SELECT and brush_preview:
    brush_preview.visible = false
    
  var hit_pos = get_terrain_hit_position(camera, mouse_pos)
  if hit_pos != Vector3.INF:
    if not brush_preview:
      setup_brush_preview()
    if not brush_preview.get_parent() or brush_preview.get_parent() != current_terrain_root:
      if brush_preview.get_parent():
        brush_preview.get_parent().remove_child(brush_preview)
      current_terrain_root.add_child(brush_preview)
    if not brush_preview.owner:
      brush_preview.owner = current_terrain_root.owner
      
    brush_preview.global_position = hit_pos
    brush_preview.visible = true
  else:
    if brush_preview:
      brush_preview.visible = false
    
func setup_brush_preview():
  if brush_preview:
    return
    
  brush_preview = MeshInstance3D.new()
  brush_preview.name = "Brush Preview"
  
  # Create a sphere mesh
  var sphere_mesh = SphereMesh.new()
  sphere_mesh.radius = 1.0
  sphere_mesh.height = 2.0
  brush_preview.mesh = sphere_mesh
  
  brush_material = StandardMaterial3D.new()
  brush_material.albedo_color = Color.YELLOW
  brush_material.albedo_color.a = 0.3
  brush_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
  brush_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
  brush_preview.material_override = brush_material
  
  brush_preview.visible = false
  
func set_brush_size(size: float):
  if brush_preview and brush_preview.mesh:
    brush_size = size
    var sphere_mesh = brush_preview.mesh as SphereMesh
    sphere_mesh.radius = size
    sphere_mesh.height = size * 2.0
    
func set_brush_strength(strength: float):
  brush_strength = strength
  
func set_sculpt_mode(mode: SculptMode):
  sculpt_mode = mode
  
func set_tool(tool: Tool):
  self.tool = tool
  
func get_sectors_in_brush(world_pos: Vector3) -> Array[SectorNode]:
  var sectors: Array[SectorNode] = []
  var seen_coords = {}
  
  # Start with the sector we hit
  var center_sector = get_sector_at_postion(world_pos)
  if not center_sector:
    print("ERROR: No center sector for sculpting.")
    return sectors
  
  for dx in range(-1, 2):
    for dy in range(-1, 2):
      var check_coords = Vector2i(
        center_sector.sector_coords.x + dx,
        center_sector.sector_coords.y + dy,
      )
      if is_valid_sector(check_coords) and not seen_coords.has(check_coords):
        var sector = current_terrain_root.get_sector(check_coords.x, check_coords.y)
        
        if not is_instance_valid(sector) or not sector.is_inside_tree():
          continue
        
        if brush_overlaps_sector(world_pos, sector):
          sectors.append(sector)
          seen_coords[check_coords] = true
          
  return sectors
  
func brush_overlaps_sector(world_pos: Vector3, sector: SectorNode) -> bool:
  if not sector or not sector.is_inside_tree():
    return false
    
  var local_pos = sector.to_local(world_pos)
  var closest_x = clamp(local_pos.x, 0, current_terrain_root.sector_size_x)
  var closest_z = clamp(local_pos.z, 0, current_terrain_root.sector_size_y)
  var distance = Vector2(local_pos.x - closest_x, local_pos.z - closest_z).length()
  return distance <= brush_size
    
  
func sculpt_at_position(camera: Camera3D, mouse_pos: Vector2):
  var hit_pos = get_terrain_hit_position(camera, mouse_pos)
  if hit_pos == Vector3.INF:
    return
    
  var affected_sectors: Array[SectorNode] = []
  
  # Determine mode based on selection
  var selected = editor_selection.get_selected_nodes()
  var selected_sector: SectorNode = null
  
  for node in selected:
    if node is SectorNode:
      selected_sector = node
      break
  
  if selected_sector:
    affected_sectors = [selected_sector]
  else:
    affected_sectors = get_sectors_in_brush(hit_pos)
  
  for sector in affected_sectors:
    modify_sector_mesh(sector, hit_pos, selected_sector != null) # Pass Border Protection Flag
    
  if not selected_sector:
    synchronize_borders(affected_sectors)
    
  last_affected_sectors = affected_sectors

func modify_sector_mesh(sector: SectorNode, world_hit_pos: Vector3, protect_borders: bool):
  if sector.variants.is_empty():
    print("ERROR: No variants available!")
    return
    
  var array_mesh: ArrayMesh = sector.variants[sector.active_variant].mesh
  var arrays = array_mesh.surface_get_arrays(0)
  var vertices = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
  var local_pos = sector.to_local(world_hit_pos)
  
  var nx = int(sector.sector_size_x / sector.resolution)
  var ny = int(sector.sector_size_y / sector.resolution)
  
  # Calculate buffer zone - how many vertices to skip from each edge
  var buffer = 0
  if protect_borders:
    buffer = max(1, int(1.0 / sector.resolution)) # 0.25 res = 4 vertices
  
  for i in range(vertices.size()):
    var vertex = vertices[i]
    
    # Convert flat index to grid coordinates
    var x = i % (nx + 1) # We're finding the remainder after we divide by the length of x
    var y = i / (nx + 1) # We're finding the number of times the length of x fully goes into i
    
    var edge_falloff = 1.0
    if protect_borders and buffer > 0:
      var edge_distance_x = min(x, nx - x)
      var edge_distance_y = min(y, ny - y)
      var edge_distance = min(edge_distance_x, edge_distance_y)
      edge_falloff = clamp(float(edge_distance) / float(buffer), 0.0, 1.0)
    
    if protect_borders or tool == Tool.SMOOTH:
      if x < buffer or x > nx - buffer or y < buffer or y > ny - buffer: continue
      
    var distance = Vector2(vertex.x - local_pos.x, vertex.z - local_pos.z).length()
    var falloff = 1.0 - (distance / brush_size)
    falloff *= edge_falloff
    if falloff < 0: continue
    
    match tool:
      Tool.RAISE:
        vertex.y += brush_strength * falloff * SCULPT_SPEED
      Tool.LOWER:
        vertex.y -= brush_strength * falloff * SCULPT_SPEED
      Tool.FLATTEN:
        if not is_nan(local_pos.y):
          vertex.y = lerpf(vertex.y, local_pos.y, SCULPT_SPEED)
      Tool.SMOOTH:
        if x == 0 or x == nx or y == 0 or y == ny: continue
        var neighbor_sum = 0.0
        neighbor_sum += vertices[i - 1].y
        neighbor_sum += vertices[i + 1].y
        neighbor_sum += vertices[i - (nx + 1)].y
        neighbor_sum += vertices[i + (nx + 1)].y
        var average = neighbor_sum / 4
        vertex.y = lerpf(vertex.y, average, falloff * SCULPT_SPEED)
    vertices[i] = vertex
    
  update_mesh(sector, arrays, vertices)
  
func get_vertex_edges(local_pos: Vector3, sector: SectorNode) -> Array[String]:
  var edges: Array[String] = []
  var epsilon = 0.001   # Small tolerance for floating point comparison
  
  if abs(local_pos.x) < epsilon:
    edges.append("west")
  elif abs(local_pos.x - sector.sector_size_x) < epsilon:
    edges.append("east")
    
  if abs(local_pos.z) < epsilon:
    edges.append("north")
  elif abs(local_pos.z - sector.sector_size_y) < epsilon:
    edges.append("south")
  
  return edges
  
func get_neighbor_sector(current_coords: Vector2i, edge: String) -> Vector2i:
  match edge:
    "north":
      return Vector2i(current_coords.x, current_coords.y - 1)
    "south":
      return Vector2i(current_coords.x, current_coords.y + 1)
    "east":
      return Vector2i(current_coords.x + 1, current_coords.y)
    "west":
      return Vector2i(current_coords.x - 1, current_coords.y)
  return current_coords
  
func get_neighbor_direction(sector: SectorNode, other: SectorNode) -> String:
  var sector_x = sector.sector_coords.x
  var sector_y = sector.sector_coords.y
  var other_x = other.sector_coords.x
  var other_y = other.sector_coords.y
  if other_x == sector_x + 1:
    if other_y == sector_y:
      return "east"
    elif other_y == sector_y + 1:
      return "southeast"
    elif other_y == sector_y - 1:
      return "northeast"
  elif other_x == sector_x - 1:
    if other_y == sector_y:
      return "west"
    elif other_y == sector_y + 1:
      return "southwest"
    elif other_y == sector_y - 1:
      return "northwest"
  elif other_x == sector_x:
    if other_y == sector_y + 1:
      return "south"
    elif other_y == sector_y - 1:
      return "north"
  
  return "not_neighbor"
 
func synchronize_borders(affected_sectors: Array[SectorNode]):
  for sector in affected_sectors:
    for other in affected_sectors:
      if sector == other: continue
      var direction = get_neighbor_direction(sector, other)
      if direction in ["north", "south", "east", "west"]:
        synchronize_border_edge(sector, other, direction)
        
func synchronize_border_edge(sector: SectorNode, other: SectorNode, direction: String):
  var sector_arrays = sector.variants[sector.active_variant].mesh.surface_get_arrays(0)
  var sector_vertices = sector_arrays[ArrayMesh.ARRAY_VERTEX] as PackedVector3Array
  
  var other_arrays = other.variants[other.active_variant].mesh.surface_get_arrays(0)
  var other_vertices = other_arrays[ArrayMesh.ARRAY_VERTEX] as PackedVector3Array
  
  var nx = int(sector.sector_size_x / sector.resolution)
  var ny = int(sector.sector_size_y / sector.resolution)
  
  if direction == "east":
    for y in range (ny + 1):
      var sector_index = y * (nx + 1) + nx
      var other_index = y * (nx + 1) + 0
      synchronize_border_vertex(sector_index, other_index, sector_vertices, other_vertices)
      
  elif direction == "west":
    for y in range (ny + 1):
      var sector_index = y * (nx + 1) + 0
      var other_index = y * (nx + 1) + nx
      synchronize_border_vertex(sector_index, other_index, sector_vertices, other_vertices)
      
  elif direction == "south":
    for x in range (nx + 1):
      var sector_index = ny * (nx + 1) + x
      var other_index = 0 * (nx + 1) + x
      synchronize_border_vertex(sector_index, other_index, sector_vertices, other_vertices)
  
  elif direction == "north":
    for x in range (nx + 1):
      var sector_index = 0 * (nx + 1) + x
      var other_index = ny * (nx + 1) + x
      synchronize_border_vertex(sector_index, other_index, sector_vertices, other_vertices)
      
  update_mesh(sector, sector_arrays, sector_vertices)
  update_mesh(other, other_arrays, other_vertices)
  
# trying to be DRY here but stopped using it because i'm worried about gdscript possibly being pass by value
func synchronize_border_vertex(sector_index: int, other_index: int, sector_vertices: PackedVector3Array, other_vertices: PackedVector3Array):
  var sector_vert = sector_vertices.get(sector_index)
  var other_vert = other_vertices.get(other_index)
  var new_height = sector_vert.y
  var new_sector_vert = Vector3(sector_vert.x, new_height, sector_vert.z)
  var new_other_vert = Vector3(other_vert.x, new_height, other_vert.z)
  sector_vertices.set(sector_index, new_sector_vert)
  other_vertices.set(other_index, new_other_vert)
  
func update_mesh(sector: SectorNode, arrays: Array, vertices: PackedVector3Array):
  var indices = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
  var normals = calculate_normals(vertices, indices)
  arrays[ArrayMesh.ARRAY_VERTEX] = vertices
  arrays[ArrayMesh.ARRAY_NORMAL] = normals
  var new_mesh = ArrayMesh.new()
  new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
  sector.variants[sector.active_variant].mesh = new_mesh
  sector.mesh_instance.mesh = new_mesh
  
  if sector.terrain_material:
    sector.mesh_instance.material_override = sector.terrain_material
      
func is_valid_sector(sector_coords: Vector2i) -> bool:
  if sector_coords.x < 0 or sector_coords.x >= current_terrain_root.sectors_x or \
    sector_coords.y < 0 or sector_coords.y >= current_terrain_root.sectors_y:
      return false
  return true
  
  
func calculate_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
  var normals = PackedVector3Array()
  normals.resize(vertices.size())
  normals.fill(Vector3.ZERO)
  
  # Accumulate face normals
  for i in range(0, indices.size(), 3): # Process triangles (3 indices per triangle)
    var i0 = indices[i]
    var i1 = indices[i + 1]
    var i2 = indices[i + 2]
    
    var v0 = vertices[i0]
    var v1 = vertices[i1]
    var v2 = vertices[i2]
    
    var edge1 = v1 - v0
    var edge2 = v2 - v0
    var face_normal = edge1.cross(edge2)
    if face_normal.length_squared() > 0.0001:
      normals[i0] += face_normal
      normals[i1] += face_normal
      normals[i2] += face_normal
    
  # Normalize all vertex normals
  for i in range(normals.size()):
    normals[i] = normals[i].normalized()
    
  return normals
