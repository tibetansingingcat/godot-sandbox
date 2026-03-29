## sculpting_handler.gd — Core sculpting logic
##
## This is the brain of the terrain editor. It:
##   - Listens to editor selection changes to track the active TerrainRoot/SectorNode
##   - Intercepts 3D viewport mouse input (via the plugin's _forward_3d_gui_input)
##   - Raycasts to find where the mouse hits the terrain
##   - Modifies mesh vertices within a brush radius using the selected tool
##   - Synchronizes border vertices between adjacent sectors so seams don't appear
##   - Manages undo/redo by snapshotting meshes at the start of each stroke
##   - Draws a brush preview sphere and sector grid overlay
##
## Sculpting flow:
##   Mouse down → snapshot current meshes → sculpt_at_position()
##   Mouse drag → sculpt_at_position() each frame
##   Mouse up   → rebuild collision → commit undo action (finalize_sculpt_stroke)
##
## Border synchronization:
##   When sculpting across sector boundaries, vertices on shared edges are averaged
##   so the terrain stays seamless. When a single sector is selected, "border
##   protection" kicks in — a buffer zone near edges prevents sculpting too close
##   to the border, avoiding mismatches with neighbors.
@tool
extends RefCounted
class_name SculptingHandler

const Tool = SculptingEnums.Tool
const SculptMode = SculptingEnums.SculptMode

const SCULPT_SPEED = 0.05

var dock_ui: Control
var current_terrain_root: TerrainRoot  ## The TerrainRoot we're editing (set by selection)
var current_sector_node: SectorNode    ## Set when a specific sector is selected (enables border protection)
var is_sculpting := false              ## True while left mouse is held down

var brush_preview: MeshInstance3D
var brush_material: StandardMaterial3D
var brush_size: float = 2.0
var brush_strength: float = 1.0

var sculpt_mode: SculptMode
var tool: Tool

var editor_selection: EditorSelection
var last_affected_sectors: Array[SectorNode] = []  ## Sectors modified in the current stroke (for collision rebuild)

var undo_redo: EditorUndoRedoManager
var sculpt_start_meshes: Dictionary[SectorNode, ArrayMesh] = {}  ## Mesh snapshots from stroke start (for undo)

var grid_lines_node: MeshInstance3D = null  ## The red sector grid overlay

func _init():
  if Engine.is_editor_hint():
    undo_redo = EditorInterface.get_editor_undo_redo()
    editor_selection = EditorInterface.get_selection()
    # Listen for selection changes to update current_terrain_root / current_sector_node
    editor_selection.selection_changed.connect(_on_selection_changed)
    
func set_dock_ui(ui: Control):
  dock_ui = ui
    
func _on_selection_changed():
  ## Called when the user clicks a node in the scene tree or viewport.
  ## Walks the selection to find the relevant TerrainRoot and/or SectorNode.
  ## If a TerrainRoot is active (but no specific sector), draws the grid overlay.
  var selected = editor_selection.get_selected_nodes()
  current_terrain_root = null
  current_sector_node = null

  for node in selected:
    # Direct selection of a TerrainRoot
    if node is TerrainRoot:
      current_terrain_root = node
      print("Selected TerrainRoot: ", node.name)
      break
    # Direct selection of a SectorNode — its parent is the TerrainRoot
    if node is SectorNode:
      current_sector_node = node
      current_terrain_root = current_sector_node.get_parent()
      print("Selected SectorNode: ", node.name)
      break
    # Selected something else — walk up the tree looking for a TerrainRoot
    var parent = node.get_parent()
    while parent:
      if parent is TerrainRoot:
        current_terrain_root = parent
        print("Selected TerrainRoot: ", parent.name)
        break
      parent = parent.get_parent()
    if current_terrain_root:
      break

  # Remove the old grid overlay (we'll recreate it if needed)
  if grid_lines_node and grid_lines_node.get_parent():
    grid_lines_node.get_parent().remove_child(grid_lines_node)
    grid_lines_node.queue_free()
    grid_lines_node = null

  # Show the sector grid when a TerrainRoot is selected (but not a specific sector)
  if current_terrain_root and not current_sector_node:
    print("Create sector grid")
    create_sector_grid()
    
func create_sector_grid():
  ## Draw a red wireframe grid over the terrain showing sector boundaries.
  ## Uses ImmediateMesh with PRIMITIVE_LINES — each pair of vertices is one line segment.
  ## The grid floats 0.5 units above y=0 so it's visible above the flat terrain.
  if not current_terrain_root:
    return

  grid_lines_node = MeshInstance3D.new()
  var immediate_mesh = ImmediateMesh.new()
  grid_lines_node.mesh = immediate_mesh

  immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

  # Vertical lines (along Z axis)
  for x in range(current_terrain_root.sectors_x + 1):
    var x_pos = x * current_terrain_root.sector_size_x
    immediate_mesh.surface_add_vertex(Vector3(x_pos, 0.5, 0))
    immediate_mesh.surface_add_vertex(Vector3(x_pos, 0.5, current_terrain_root.sectors_y * current_terrain_root.sector_size_y))

  # Horizontal lines (along X axis)
  for y in range(current_terrain_root.sectors_y + 1):
    var z_pos = y * current_terrain_root.sector_size_y
    immediate_mesh.surface_add_vertex(Vector3(0, 0.5, z_pos))
    immediate_mesh.surface_add_vertex(Vector3(current_terrain_root.sectors_x * current_terrain_root.sector_size_x, 0.5, z_pos))

  immediate_mesh.surface_end()

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
  ## Convert a world position to the sector grid cell it falls within.
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
  ## Main input handler, called by the plugin's _forward_3d_gui_input.
  ## Returns AFTER_GUI_INPUT_STOP to consume the event, or _PASS to let Godot handle it.
  if not current_terrain_root:
    print("not current terrain root")
    return EditorPlugin.AFTER_GUI_INPUT_PASS

  # SELECT tool: click a sector to select it in the scene tree
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

  # SCULPTING tools (raise, lower, smooth, flatten):
  if event is InputEventMouseMotion:
    update_brush_preview(camera, event.position)

    if is_sculpting:
      # As the brush moves over new sectors, snapshot their meshes for undo
      var affected = get_sectors_in_brush(get_terrain_hit_position(camera, event.position))
      for sector in affected:
        if sculpt_start_meshes.has(sector):
          continue
        sculpt_start_meshes[sector] = sector.variants[sector.active_variant].mesh.duplicate()
      sculpt_at_position(camera, event.position)
      return EditorPlugin.AFTER_GUI_INPUT_STOP

  elif event is InputEventMouseButton:
    if event.button_index == MOUSE_BUTTON_LEFT:
      if event.pressed:
        # Stroke start: snapshot meshes and begin sculpting
        is_sculpting = true
        var affected = get_sectors_in_brush(get_terrain_hit_position(camera, event.position))
        for sector in affected:
          sculpt_start_meshes[sector] = sector.variants[sector.active_variant].mesh.duplicate()
        sculpt_at_position(camera, event.position)
        return EditorPlugin.AFTER_GUI_INPUT_STOP
      else:
        # Stroke end: rebuild collision and commit undo action
        is_sculpting = false
        update_collision_for_affected_sectors()
        finalize_sculpt_stroke()
        return EditorPlugin.AFTER_GUI_INPUT_STOP

  return EditorPlugin.AFTER_GUI_INPUT_PASS
  
func finalize_sculpt_stroke():
  ## Create an undo/redo action for the completed sculpt stroke.
  ## For each affected sector, we store:
  ##   - do:   the modified mesh (current state)
  ##   - undo: the snapshot taken at stroke start
  ## Both call refresh_mesh_display() to update the viewport.
  if sculpt_start_meshes.is_empty():
    return

  print("Creating undo action for ", sculpt_start_meshes.size(), " sectors")
  undo_redo.create_action("Sculpt Terrain")

  for sector: SectorNode in sculpt_start_meshes.keys():
    var variant = sector.variants[sector.active_variant]
    var old_mesh = sculpt_start_meshes[sector]
    var new_mesh = variant.mesh.duplicate()

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
  ## Raycast from the camera through the mouse position to find where it hits
  ## the terrain. First tries physics raycast (hits collision shapes). If that
  ## misses (e.g. flat terrain with no sculpting yet), falls back to intersecting
  ## with the y=0 horizontal plane. Returns Vector3.INF if nothing is hit.
  if not current_terrain_root or not current_terrain_root.is_inside_tree():
    return Vector3.INF

  var from = camera.project_ray_origin(mouse_pos)
  var to = from + camera.project_ray_normal(mouse_pos) * 1000.0

  var space_state = current_terrain_root.get_world_3d().direct_space_state
  var query = PhysicsRayQueryParameters3D.create(from, to)
  var result = space_state.intersect_ray(query)

  if result:
    return result.position

  # Fallback: intersect with the ground plane
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
  ## Apply one frame of sculpting at the mouse position.
  ##
  ## Two modes depending on what's selected:
  ##   - SectorNode selected: sculpt ONLY that sector, with border protection
  ##     (a buffer zone near edges prevents sculpting close to borders)
  ##   - TerrainRoot selected: sculpt all sectors under the brush, then
  ##     synchronize shared border vertices so seams don't appear
  var hit_pos = get_terrain_hit_position(camera, mouse_pos)
  if hit_pos == Vector3.INF:
    return

  var affected_sectors: Array[SectorNode] = []

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
    modify_sector_mesh(sector, hit_pos, selected_sector != null)

  if not selected_sector:
    var synced_neighbors = synchronize_borders(affected_sectors)
    # Include synced neighbors so their collision gets rebuilt on mouse-up
    for neighbor in synced_neighbors:
      if neighbor not in affected_sectors:
        affected_sectors.append(neighbor)

  last_affected_sectors = affected_sectors

func modify_sector_mesh(sector: SectorNode, world_hit_pos: Vector3, protect_borders: bool):
  ## The core sculpting function. Iterates over every vertex in the sector mesh,
  ## checks if it's within brush radius, and applies the active tool.
  ##
  ## protect_borders: when true (single sector selected), vertices near the edge
  ## are skipped or faded out so they don't create seams with neighbors.
  if sector.variants.is_empty():
    print("ERROR: No variants available!")
    return

  var array_mesh: ArrayMesh = sector.variants[sector.active_variant].mesh
  var arrays = array_mesh.surface_get_arrays(0)
  var vertices = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
  var local_pos = sector.to_local(world_hit_pos)

  var nx = int(sector.sector_size_x / sector.resolution)  # Vertices per row (minus 1)
  var ny = int(sector.sector_size_y / sector.resolution)   # Vertices per column (minus 1)

  # Buffer zone: how many vertices from each edge to protect
  var buffer = 0
  if protect_borders:
    buffer = max(1, int(1.0 / sector.resolution))

  for i in range(vertices.size()):
    var vertex = vertices[i]

    # Convert flat array index back to 2D grid coordinates
    var x = i % (nx + 1)
    var y = i / (nx + 1)

    # Edge falloff: smoothly reduces sculpt strength near borders
    var edge_falloff = 1.0
    if protect_borders and buffer > 0:
      var edge_distance_x = min(x, nx - x)
      var edge_distance_y = min(y, ny - y)
      var edge_distance = min(edge_distance_x, edge_distance_y)
      edge_falloff = clamp(float(edge_distance) / float(buffer), 0.0, 1.0)

    # Skip vertices in the buffer zone entirely
    if protect_borders or tool == Tool.SMOOTH:
      if x < buffer or x > nx - buffer or y < buffer or y > ny - buffer: continue

    # Brush falloff: linear falloff from center (1.0) to edge (0.0) of brush
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
        # Lerp toward the hit point's height (the surface you clicked on)
        if not is_nan(local_pos.y):
          vertex.y = lerpf(vertex.y, local_pos.y, SCULPT_SPEED)
      Tool.SMOOTH:
        # Average with 4 cardinal neighbors (skip edges to avoid out-of-bounds)
        if x == 0 or x == nx or y == 0 or y == ny: continue
        var neighbor_sum = 0.0
        neighbor_sum += vertices[i - 1].y          # left
        neighbor_sum += vertices[i + 1].y          # right
        neighbor_sum += vertices[i - (nx + 1)].y   # up
        neighbor_sum += vertices[i + (nx + 1)].y   # down
        var average = neighbor_sum / 4
        vertex.y = lerpf(vertex.y, average, falloff * SCULPT_SPEED)
    vertices[i] = vertex

  update_mesh(sector, arrays, vertices)
  
# --- Border synchronization ---
# When sculpting across multiple sectors, the vertices on shared edges must match
# or visible seams appear. After sculpting, we find pairs of adjacent sectors and
# copy the sculpted sector's edge heights to the neighbor's matching edge.
#
# Grid coordinate system for edges:
#   - "east" edge of sector A = rightmost column (x=nx) of A's vertices
#     lines up with "west" edge (x=0) of the sector to A's right
#   - "south" edge = bottom row (y=ny), lines up with "north" edge (y=0) below

func get_vertex_edges(local_pos: Vector3, sector: SectorNode) -> Array[String]:
  ## Determine which edges (if any) a local-space position lies on.
  var edges: Array[String] = []
  var epsilon = 0.001
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
  ## Get the grid coordinates of the sector adjacent in the given direction.
  match edge:
    "north": return Vector2i(current_coords.x, current_coords.y - 1)
    "south": return Vector2i(current_coords.x, current_coords.y + 1)
    "east":  return Vector2i(current_coords.x + 1, current_coords.y)
    "west":  return Vector2i(current_coords.x - 1, current_coords.y)
  return current_coords

func get_neighbor_direction(sector: SectorNode, other: SectorNode) -> String:
  ## Determine the compass direction from sector to other (including diagonals).
  var sector_x = sector.sector_coords.x
  var sector_y = sector.sector_coords.y
  var other_x = other.sector_coords.x
  var other_y = other.sector_coords.y
  if other_x == sector_x + 1:
    if other_y == sector_y:     return "east"
    elif other_y == sector_y + 1: return "southeast"
    elif other_y == sector_y - 1: return "northeast"
  elif other_x == sector_x - 1:
    if other_y == sector_y:     return "west"
    elif other_y == sector_y + 1: return "southwest"
    elif other_y == sector_y - 1: return "northwest"
  elif other_x == sector_x:
    if other_y == sector_y + 1: return "south"
    elif other_y == sector_y - 1: return "north"
  return "not_neighbor"

func synchronize_borders(affected_sectors: Array[SectorNode]) -> Array[SectorNode]:
  ## Synchronize border vertices so seams don't appear after sculpting.
  ## Returns any non-affected neighbors that were synced (so their collision
  ## can be rebuilt too).
  ##
  ## Two passes:
  ##   1. Sync borders between pairs of affected sectors (both were sculpted,
  ##      so the sculpted sector's edge heights are copied to its neighbor).
  ##   2. Sync each affected sector's edges with NON-affected neighbors.
  ##      Without this, sectors just outside the brush keep their old border
  ##      heights while the sculpted side was raised/lowered, creating spikes.
  var synced_neighbors: Array[SectorNode] = []

  # Pass 1: sync between affected sectors
  for sector in affected_sectors:
    for other in affected_sectors:
      if sector == other: continue
      var direction = get_neighbor_direction(sector, other)
      if direction in ["north", "south", "east", "west"]:
        synchronize_border_edge(sector, other, direction)

  # Pass 2: sync affected sectors with their non-affected cardinal neighbors
  for sector in affected_sectors:
    for dir in ["north", "south", "east", "west"]:
      var neighbor_coords = get_neighbor_sector(sector.sector_coords, dir)
      if not is_valid_sector(neighbor_coords):
        continue
      var neighbor = current_terrain_root.get_sector(neighbor_coords.x, neighbor_coords.y)
      if neighbor in affected_sectors:
        continue  # Already handled in pass 1
      # Sculpted sector pushes its edge heights to the untouched neighbor
      synchronize_border_edge(sector, neighbor, dir)
      if neighbor not in synced_neighbors:
        synced_neighbors.append(neighbor)

  return synced_neighbors

func synchronize_border_edge(sector: SectorNode, other: SectorNode, direction: String):
  ## Copy the sculpted sector's edge vertex heights to the neighbor's matching edge.
  ## For example, if direction="east", sector's rightmost column (x=nx) is copied
  ## to other's leftmost column (x=0).
  var sector_arrays = sector.variants[sector.active_variant].mesh.surface_get_arrays(0)
  var sector_vertices = sector_arrays[ArrayMesh.ARRAY_VERTEX] as PackedVector3Array

  var other_arrays = other.variants[other.active_variant].mesh.surface_get_arrays(0)
  var other_vertices = other_arrays[ArrayMesh.ARRAY_VERTEX] as PackedVector3Array

  var nx = int(sector.sector_size_x / sector.resolution)
  var ny = int(sector.sector_size_y / sector.resolution)

  if direction == "east":
    for y in range (ny + 1):
      var sector_index = y * (nx + 1) + nx     # rightmost column
      var other_index = y * (nx + 1) + 0       # leftmost column
      synchronize_border_vertex(sector_index, other_index, sector_vertices, other_vertices)

  elif direction == "west":
    for y in range (ny + 1):
      var sector_index = y * (nx + 1) + 0
      var other_index = y * (nx + 1) + nx
      synchronize_border_vertex(sector_index, other_index, sector_vertices, other_vertices)

  elif direction == "south":
    for x in range (nx + 1):
      var sector_index = ny * (nx + 1) + x     # bottom row
      var other_index = 0 * (nx + 1) + x       # top row
      synchronize_border_vertex(sector_index, other_index, sector_vertices, other_vertices)

  elif direction == "north":
    for x in range (nx + 1):
      var sector_index = 0 * (nx + 1) + x
      var other_index = ny * (nx + 1) + x
      synchronize_border_vertex(sector_index, other_index, sector_vertices, other_vertices)

  update_mesh(sector, sector_arrays, sector_vertices)
  update_mesh(other, other_arrays, other_vertices)

func synchronize_border_vertex(sector_index: int, other_index: int, sector_vertices: PackedVector3Array, other_vertices: PackedVector3Array):
  ## Set both border vertices to the same height (uses sector's height as source).
  ## Note: PackedVector3Array is passed by reference in GDScript, so .set() modifies
  ## the original array — this helper works correctly despite Vector3 being a value type.
  var sector_vert = sector_vertices.get(sector_index)
  var other_vert = other_vertices.get(other_index)
  var new_height = sector_vert.y
  var new_sector_vert = Vector3(sector_vert.x, new_height, sector_vert.z)
  var new_other_vert = Vector3(other_vert.x, new_height, other_vert.z)
  sector_vertices.set(sector_index, new_sector_vert)
  other_vertices.set(other_index, new_other_vert)
  
func update_mesh(sector: SectorNode, arrays: Array, vertices: PackedVector3Array):
  ## Rebuild the sector's ArrayMesh from modified vertices. Recalculates normals
  ## from the triangle geometry and replaces the mesh on both the variant resource
  ## and the visible MeshInstance3D.
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
  ## Recalculate smooth vertex normals from triangle geometry.
  ## Each triangle's face normal is accumulated into its three vertices, then
  ## all normals are normalized. This produces smooth shading across the mesh.
  var normals = PackedVector3Array()
  normals.resize(vertices.size())
  normals.fill(Vector3.ZERO)

  # Accumulate face normals into each vertex
  for i in range(0, indices.size(), 3):
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

  # Normalize: each vertex normal becomes the average of its surrounding faces
  for i in range(normals.size()):
    normals[i] = normals[i].normalized()

  return normals
