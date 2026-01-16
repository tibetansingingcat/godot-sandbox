@tool
extends EditorNode3DGizmoPlugin

func _get_gizmo_name() -> String:
  return "SectorGizmo"
  
func _has_gizmo(node: Node3D) -> bool:
  return node is SectorNode
  
func _redraw(gizmo: EditorNode3DGizmo):
  gizmo.clear()
  
  var sector = gizmo.get_node_3d() as SectorNode
  if not sector:
    return
    
  var lines = PackedVector3Array()
  var size_x = sector.sector_size_x
  var size_y = sector.sector_size_y
  
  # Bottom rectangle
  lines.append(Vector3(0, 0, 0))
  lines.append(Vector3(size_x, 0, 0))
  lines.append(Vector3(0, 0, size_y))
  lines.append(Vector3(size_x, 0, size_y))
  
  var material = get_material("lines", gizmo)
  gizmo.add_lines(lines, material, false)
