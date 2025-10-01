@tool
extends RefCounted
class_name SculptingHandler

const Tool = SculptingEnums.Tool
const SculptMode = SculptingEnums.SculptMode

const SCULPT_SPEED = 0.05

var dock_ui: Control
var current_terrain_root: TerrainRoot
var is_sculpting := false

var brush_preview: MeshInstance3D
var brush_material: StandardMaterial3D
var brush_size: float = 2.0
var brush_strength: float = 1.0

var sculpt_mode: SculptMode
var tool: Tool

var editor_selection: EditorSelection
var last_affected_sectors: Array[SectorNode] = []


func _init():
  if Engine.is_editor_hint():
    editor_selection = EditorInterface.get_selection()
    editor_selection.selection_changed.connect(_on_selection_changed)
    
func set_dock_ui(ui: Control):
  dock_ui = ui
    
func _on_selection_changed():
  # Check if selected object is a TerrainRoot or child of one
  var selected = editor_selection.get_selected_nodes()
  current_terrain_root = null
  
  for node in selected:
    if node is TerrainRoot:
      current_terrain_root = node
      print("Selected TerrainRoot: ", node.name)
      break
    var parent = node.get_parent()
    while parent:
      if parent is TerrainRoot:
        current_terrain_root = parent
        print("Selected TerrainRoot: ", parent.name)
        break
      if current_terrain_root:
        break
  if not current_terrain_root:
    print("No TerrainRoot selected")

func handles(object) -> bool:
  if object is TerrainRoot:
    current_terrain_root = object
    return true
  return false
  
func get_sector_at_postion(world_pos: Vector3) -> SectorNode:
  var local_pos = current_terrain_root.to_local(world_pos)
  
  var sector_x = int(local_pos.x / current_terrain_root.sector_size_x)
  var sector_y = int(local_pos.z / current_terrain_root.sector_size_y)
  
  if sector_x < 0 or sector_x >= current_terrain_root.sectors_x or \
    sector_y < 0 or sector_y >= current_terrain_root.sectors_y:
      return null
      
  return current_terrain_root.get_sector(sector_x, sector_y)

func handle_3d_input(camera: Camera3D, event: InputEvent) -> int:
  if not current_terrain_root:
    return EditorPlugin.AFTER_GUI_INPUT_PASS
  
  if event is InputEventMouseMotion:
    update_brush_preview(camera, event.position)
    
    if is_sculpting:
      sculpt_at_position(camera, event.position)
      return EditorPlugin.AFTER_GUI_INPUT_STOP
  
  elif event is InputEventMouseButton:
    if event.button_index == MOUSE_BUTTON_LEFT:
      if event.pressed:
        is_sculpting = true
        sculpt_at_position(camera, event.position)
        return EditorPlugin.AFTER_GUI_INPUT_STOP
      else:
        is_sculpting = false
        update_collision_for_affected_sectors()
        return EditorPlugin.AFTER_GUI_INPUT_STOP
    
  return EditorPlugin.AFTER_GUI_INPUT_PASS
  
func update_collision_for_affected_sectors():
  print("Updating collision...")
  for sector in last_affected_sectors:
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
    print("No terrain root or not in tree")
    return
    
  var hit_pos = get_terrain_hit_position(camera, mouse_pos)
  print("Hit pos: ", hit_pos)
  if hit_pos != Vector3.INF:
    if not brush_preview:
      print("Creating brush preview")
      setup_brush_preview()
    if not brush_preview.get_parent():
      print("Adding brush preview to terrain root")
      current_terrain_root.add_child(brush_preview)
      
    print("Setting brush preview global position to: ", hit_pos)
    brush_preview.global_position = hit_pos
    brush_preview.visible = true
    print("Brush preview visible: ", brush_preview.visible)
  else:
    print("hit pos is INF, hiding brush")
    if brush_preview:
      brush_preview.visible = false
    
func setup_brush_preview():
  if brush_preview:
    return
    
  brush_preview = MeshInstance3D.new()
  
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
    return sectors
  
  for dx in range(-1, 2):
    for dy in range(-1, 2):
      var check_coords = Vector2i(
        center_sector.sector_coords.x + dx,
        center_sector.sector_coords.y + dy,
      )
      if is_valid_sector(check_coords) and not seen_coords.has(check_coords):
        var sector = current_terrain_root.get_sector(check_coords.x, check_coords.y)
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
    
  var affected_sectors = get_sectors_in_brush(hit_pos)
  
  for sector in affected_sectors:
    modify_sector_mesh(sector, hit_pos)
    
  synchronize_borders(affected_sectors)
  last_affected_sectors = affected_sectors

func modify_sector_mesh(sector: SectorNode, world_hit_pos: Vector3):
  var array_mesh: ArrayMesh = sector.variants[sector.active_variant].mesh
  var arrays = array_mesh.surface_get_arrays(0)
  
  var vertices = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
  var local_pos = sector.to_local(world_hit_pos)
  for i in range(vertices.size()):
    var vertex = vertices[i]
    var distance = Vector2(vertex.x - local_pos.x, vertex.z - local_pos.z).length()
    var falloff = 1.0 - (distance / brush_size)
    if falloff < 0: continue
    match tool:
      Tool.RAISE:
        vertex.y += brush_strength * falloff * SCULPT_SPEED
      Tool.LOWER:
        vertex.y -= brush_strength * falloff * SCULPT_SPEED
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
    var face_normal = edge2.cross(edge1)
    if face_normal.length_squared() > 0.0001:
      normals[i0] += face_normal
      normals[i1] += face_normal
      normals[i2] += face_normal
    
  # Normalize all vertex normals
  for i in range(normals.size()):
    normals[i] = normals[i].normalized()
    
  return normals
