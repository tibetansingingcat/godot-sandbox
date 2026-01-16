@tool
extends EditorNode3DGizmoPlugin

func _init():
  print("Creating grid_line color")
  create_material("grid_line", Color(0.984, 0.0, 0.0, 1.0))
  print("Material created")

func _get_gizmo_name() -> String:
  return "TerrainRootGizmo"
  
func _get_priority() -> int:
  return 0

func _has_gizmo(node: Node3D) -> bool:
  var has_it = node is TerrainRoot
  print("Checking gizmo for: ", node.get_class(), " Result: ", has_it)
  return has_it

func _redraw(gizmo: EditorNode3DGizmo):
  print("Drawing grid")
  gizmo.clear()
  
  var terrain = gizmo.get_node_3d() as TerrainRoot
  if not terrain:
    return
  
  var lines = PackedVector3Array()
  var height = 0.5
  
  # Draw vertical lines (along Z axis)
  for x in range(terrain.sectors_x + 1):
    var x_pos = x * terrain.sector_size_x
    lines.append(Vector3(x_pos, height, 0))
    lines.append(Vector3(x_pos, height, terrain.sectors_y * terrain.sector_size_y))
  
  # Draw horizontal lines (along X axis)
  for y in range(terrain.sectors_y + 1):
    var z_pos = y * terrain.sector_size_y
    lines.append(Vector3(0, height, z_pos))
    lines.append(Vector3(terrain.sectors_x * terrain.sector_size_x, height, z_pos))
  
  var material = get_material("grid_line")
  gizmo.add_lines(lines, material, false)
