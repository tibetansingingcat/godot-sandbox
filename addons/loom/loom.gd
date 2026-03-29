## loom.gd — Main plugin entry point
##
## This is the EditorPlugin that Godot loads when Loom is enabled. It wires
## together the four main subsystems:
##
##   1. TerrainRootInspector — adds "Rebuild Grid" / "Save" buttons when a
##      TerrainRoot is selected in the inspector.
##   2. SectorNodeInspector — adds variant management UI (create, switch,
##      delete, name, relationships) when a SectorNode is selected.
##   3. SculptDock — a persistent dock panel (top-left) with tool and brush
##      controls.
##   4. SculptingHandler — the core logic: receives 3D viewport input,
##      performs raycasts, modifies mesh vertices, manages undo/redo.
##
## The plugin also tells Godot it "handles" TerrainRoot and SectorNode so
## that _forward_3d_gui_input is called, allowing the sculpting handler to
## intercept mouse events in the 3D viewport.
@tool
extends EditorPlugin

var terrain_inspector
var sector_node_inspector
var sculpt_dock
var sculpting_handler
var sector_gizmo_plugin
var terrain_gizmo_plugin

func _enter_tree():
  # --- Inspector plugins: add custom UI to the Inspector panel ---
  terrain_inspector = preload("res://addons/loom/scripts/terrain_root_inspector.gd").new()
  add_inspector_plugin(terrain_inspector)

  sector_node_inspector = preload("res://addons/loom/scripts/sector_node_inspector.gd").new()
  add_inspector_plugin(sector_node_inspector)

  # --- Sculpt dock: persistent UI panel for brush/tool settings ---
  sculpt_dock = preload("res://addons/loom/scripts/sculpt_dock.gd").new()
  add_control_to_dock(DOCK_SLOT_LEFT_UL, sculpt_dock)

  # --- Sculpting handler: core sculpting logic, wired to the dock ---
  # The handler and dock hold references to each other so the dock's
  # sliders/buttons can call handler methods, and the handler can read
  # dock state.
  sculpting_handler = preload("res://addons/loom/scripts/sculpting_handler.gd").new()
  sculpting_handler.set_dock_ui(sculpt_dock)
  sculpt_dock.sculpting_handler = sculpting_handler

  # Gizmo plugins (disabled for now — grid is drawn by sculpting_handler instead)
  #sector_gizmo_plugin = preload("res://addons/loom/scripts/sector_gizmo_plugin.gd").new()
  #add_node_3d_gizmo_plugin(sector_gizmo_plugin)
  #terrain_gizmo_plugin = preload("res://addons/loom/scripts/terrain_root_gizmo_plugin.gd").new()
  #add_node_3d_gizmo_plugin(terrain_gizmo_plugin)

func _handles(object: Object) -> bool:
  # Tell Godot we want 3D input forwarding when a terrain node is selected
  return object is TerrainRoot or object is SectorNode

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
  # Delegate all 3D viewport input to the sculpting handler
  return sculpting_handler.handle_3d_input(camera, event)

func _exit_tree():
    # Clean up everything we registered in _enter_tree
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
