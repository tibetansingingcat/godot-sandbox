@tool
extends EditorPlugin

var terrain_inspector
var sector_node_inspector
var sculpt_dock
var sculpting_handler
var sector_gizmo_plugin
var terrain_gizmo_plugin

func _enter_tree():
  terrain_inspector = preload("res://addons/loom/scripts/terrain_root_inspector.gd").new()
  add_inspector_plugin(terrain_inspector)
    
  sector_node_inspector = preload("res://addons/loom/scripts/sector_node_inspector.gd").new()
  add_inspector_plugin(sector_node_inspector)
    
  sculpt_dock = preload("res://addons/loom/scripts/sculpt_dock.gd").new()
  add_control_to_dock(DOCK_SLOT_LEFT_UL, sculpt_dock)
  
  sculpting_handler = preload("res://addons/loom/scripts/sculpting_handler.gd").new()
  sculpting_handler.set_dock_ui(sculpt_dock)
  sculpt_dock.sculpting_handler = sculpting_handler
  
  #sector_gizmo_plugin = preload("res://addons/loom/scripts/sector_gizmo_plugin.gd").new()
  #add_node_3d_gizmo_plugin(sector_gizmo_plugin)
    
  #terrain_gizmo_plugin = preload("res://addons/loom/scripts/terrain_root_gizmo_plugin.gd").new()
  #add_node_3d_gizmo_plugin(terrain_gizmo_plugin)
    
func _handles(object: Object) -> bool:
  return object is TerrainRoot or object is SectorNode
  
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
  return sculpting_handler.handle_3d_input(camera, event)
    
func _exit_tree():
    if terrain_inspector:
        remove_inspector_plugin(terrain_inspector)
        terrain_inspector = null

    if sector_node_inspector:
        remove_inspector_plugin(sector_node_inspector)
        sector_node_inspector = null
        
    if sculpt_dock:
      remove_control_from_docks(sculpt_dock)
      sculpt_dock = null
      
    if sculpting_handler:
      sculpting_handler = null
      
    if terrain_gizmo_plugin:
      remove_node_3d_gizmo_plugin(terrain_gizmo_plugin)
      terrain_gizmo_plugin = null
      
    if sector_gizmo_plugin:
      remove_node_3d_gizmo_plugin(sector_gizmo_plugin)
      sector_gizmo_plugin = null
