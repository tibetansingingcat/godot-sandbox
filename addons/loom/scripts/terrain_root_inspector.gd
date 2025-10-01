@tool
extends EditorInspectorPlugin

func _can_handle(obj):
  return obj is TerrainRoot
  
func _parse_begin(obj):
  var terrain_root = obj as TerrainRoot
  var rebuild_grid_button = Button.new()
  rebuild_grid_button.text = "Rebuild Grid"
  rebuild_grid_button.pressed.connect(func():
    terrain_root.build_grid()
  )
  add_custom_control(rebuild_grid_button)
  
  var save_button = Button.new()
  save_button.text = "Save Grid"
  save_button.pressed.connect(func():
    terrain_root.save()
  )
  
  add_custom_control(save_button)
