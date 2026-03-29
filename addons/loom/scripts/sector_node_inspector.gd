@tool
extends EditorInspectorPlugin

var sector: SectorNode
var variants_box: VBoxContainer
var relationships_box: VBoxContainer

var variant_list = []
var dialog = ConfirmationDialog.new()

func _init() -> void:
  EditorInterface.get_base_control().add_child(dialog)

func _can_handle(obj):
  return obj is SectorNode
  
func _parse_begin(obj):
  sector = obj as SectorNode
  add_controls()

func add_controls():
  var button = Button.new()
  button.text = "Create variant"
  button.pressed.connect(func():
    sector.create_variant()
  )
  add_custom_control(button)

  var save_current_button = Button.new()
  save_current_button.text = "Save Node (Current Variant Only)"
  save_current_button.pressed.connect(func():
    sector.save_current()
  )
  
  add_custom_control(save_current_button)
  
  var save_all_button = Button.new()
  save_all_button.text = "Save Node (All Variants)"
  save_all_button.pressed.connect(func():
    sector.save_all()
  )
  
  add_custom_control(save_all_button)
  
  # -- Variant list
  variants_box = VBoxContainer.new()
  add_custom_control(variants_box)
  _rebuild_variants_ui()
  
  # Add relationships UI here, after variants box
  relationships_box = VBoxContainer.new()
  add_custom_control(relationships_box)
  _rebuild_relationships_ui()
  #add_custom_control(create_relationships_ui(sector_node))
  
  # -- Listen for changes to refresh our UI
  if not sector.is_connected("variants_changed", _on_variants_changed):
      sector.variants_changed.connect(_on_variants_changed)
  if not sector.is_connected("active_variant_changed", _on_active_variant_changed):
      sector.active_variant_changed.connect(_on_active_variant_changed)
      
func _on_variants_changed():
    _rebuild_variants_ui()
    _rebuild_relationships_ui()

func _on_active_variant_changed(_idx: int):
    _rebuild_variants_ui()
    
func _rebuild_variants_ui():
    if not variants_box: return
    # Clear previous rows
    for c in variants_box.get_children():
        c.queue_free()

    var header := Label.new()
    header.text = "Variants:"
    variants_box.add_child(header)

    for i in range(sector.variants.size()):
        var variant = sector.variants[i]
        var row := HBoxContainer.new()

        var name_edit = LineEdit.new()
        name_edit.text = variant.variant_name if variant.variant_name != "" else "Variant %d" % i
        name_edit.placeholder_text = "Variant %d" % i
        name_edit.text_submitted.connect(func(new_name): 
          variant.variant_name = new_name
          # Save the variant resource to persist the name
          var variant_path = "res://terrain/sector_%d_%d_variant%d.tres" % [sector.sector_coords.x, sector.sector_coords.y, i]
          ResourceSaver.save(variant, variant_path)
        )
        name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(name_edit)

        if i == sector.active_variant:
            var active_lbl := Label.new()
            active_lbl.text = "  [Active]"
            row.add_child(active_lbl)
        else:
            var set_btn := Button.new()
            set_btn.text = "Set Active"
            set_btn.pressed.connect(func(idx := i):
                sector.set_variant(idx) # will emit signal; we rebuild on signal
            )
            row.add_child(set_btn)

        # Optional: remove button
        if i != sector.active_variant:
          var del_btn := Button.new()
          del_btn.text = "Remove"
          del_btn.pressed.connect(func(idx := i):
              sector.remove_variant(idx)
          )
          row.add_child(del_btn)

        variants_box.add_child(row)

func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: int, wide: bool):
  if object is SectorNode and name == "variants":
    return true
  return false
  
func _rebuild_relationships_ui():
    if not relationships_box: return
    # Clear previous rows
    for c in relationships_box.get_children():
        c.queue_free()

    var header = Label.new()
    header.text = "Variant Relationships"
    relationships_box.add_child(header)
    
    for i in range(sector.variants.size()):
      var variant = sector.variants[i]
      var variant_box = VBoxContainer.new()
      
      var variant_label = Label.new()
      variant_label.text = variant.variant_name if variant.variant_name else "Variant %d" % i
      variant_box.add_child(variant_label)
      
      var add_req_btn = Button.new()
      add_req_btn.text = "Add Requirement"
      add_req_btn.pressed.connect(func(): show_requirement_dialog(variant))
      variant_box.add_child(add_req_btn)
      
      for req in variant.requires:
        var row = HBoxContainer.new()
        var req_label = Label.new()
        req_label.text = "  Requires: Sector %s has %s" % [req.sector_coords, req.variant_names]
        req_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(req_label)
        
        var del_btn := Button.new()
        del_btn.text = "Remove"
        del_btn.pressed.connect(func(idx := i):
            var index = variant.requires.find(req)
            variant.requires.remove_at(index)
            
            # Save the variant to persist the requirement
            var variant_path = "res://terrain/sector_%d_%d_variant%d.tres" % [sector.sector_coords.x, sector.sector_coords.y, sector.variants.find(variant)]
            ResourceSaver.save(variant, variant_path)
            _rebuild_relationships_ui()
        )
        row.add_child(del_btn)
        variant_box.add_child(row)
        
      var add_gua_btn = Button.new()
      add_gua_btn.text = "Add Guarantee"
      add_gua_btn.pressed.connect(func(): show_guarantee_dialog(variant))
      variant_box.add_child(add_gua_btn)
      
      for guarantee in variant.guarantees:
        var row = HBoxContainer.new()
        var guarantee_label = Label.new()
        guarantee_label.text = "  Guarantees: Sector %s has %s" % [guarantee.sector_coords, guarantee.variant_name]
        guarantee_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(guarantee_label)
        
        var del_btn := Button.new()
        del_btn.text = "Remove"
        del_btn.pressed.connect(func(idx := i):
            var index = variant.guarantees.find(guarantee)
            variant.guarantees.remove_at(index)
            
            # Save the variant to persist the requirement
            var variant_path = "res://terrain/sector_%d_%d_variant%d.tres" % [sector.sector_coords.x, sector.sector_coords.y, sector.variants.find(variant)]
            ResourceSaver.save(variant, variant_path)
            _rebuild_relationships_ui()
        )
        row.add_child(del_btn)
        variant_box.add_child(row)
      
      relationships_box.add_child(variant_box)
      
func populate_variant_list(x: int, y: int):
  if not sector or sector.get_parent() is not TerrainRoot:
    return
  variant_list.clear()
  
  var terrain_root = sector.get_parent() as TerrainRoot
  var variants = terrain_root.get_sector(x, y).variants
  for i in range(variants.size()):
    var v = variants[i]
    if v.variant_name:
      variant_list.append(v.variant_name)
    else:
      variant_list.append("Variant %d" % i)
  print(variant_list)
  
enum DialogType {
  REQUIREMENT,
  GUARANTEE
}
func show_requirement_dialog(variant: SectorVariant):
  _show_relationship_dialog(variant, DialogType.REQUIREMENT)
  
func show_guarantee_dialog(variant: SectorVariant):
  _show_relationship_dialog(variant, DialogType.GUARANTEE)

func _show_relationship_dialog(variant: SectorVariant, type: DialogType):
  # Clear old content
  for c in dialog.get_children():
    dialog.remove_child(c)
    c.queue_free()
  
  dialog.title = "Add Requirement" if type == DialogType.REQUIREMENT else "Add Guarantee"
  
  var vbox = VBoxContainer.new()
  
  # Sector coordinate inputs
  var coords_hbox = HBoxContainer.new()
  var x_spin = SpinBox.new()
  var y_spin = SpinBox.new()
  
  var x_label = Label.new()
  x_label.text = "Sector X:"
  var y_label = Label.new()
  y_label.text = "Y:"
  
  var options = OptionButton.new()
  
  # Function to update options based on current spinbox values
  var update_options = func():
    options.clear()
    populate_variant_list(int(x_spin.value), int(y_spin.value))
    for vname in variant_list:
      options.add_item(vname)
  
  # Initial populate
  update_options.call()
  
  # Connect spinboxes to update options (NOT rebuild dialog)
  x_spin.value_changed.connect(func(_v): update_options.call())
  y_spin.value_changed.connect(func(_v): update_options.call())
  
  coords_hbox.add_child(x_label)
  coords_hbox.add_child(x_spin)
  coords_hbox.add_child(y_label)
  coords_hbox.add_child(y_spin)
  vbox.add_child(coords_hbox)
  vbox.add_child(options)
  
  dialog.add_child(vbox)

  # Disconnect any stale confirmed handlers from previous cancel/close
  for conn in dialog.confirmed.get_connections():
    dialog.confirmed.disconnect(conn.callable)

  # Connect confirmed
  dialog.confirmed.connect(func():
    if type == DialogType.REQUIREMENT:
      var req = VariantRequirement.new()
      req.sector_coords = Vector2i(x_spin.value, y_spin.value)
      req.variant_names.append(variant_list[options.selected])
      variant.requires.append(req)
    else:
      var guarantee = VariantGuarantee.new()
      guarantee.sector_coords = Vector2i(x_spin.value, y_spin.value)
      guarantee.variant_name = variant_list[options.selected]
      variant.guarantees.append(guarantee)
    
    # Save
    var idx = sector.variants.find(variant)
    var variant_path = "res://terrain/sector_%d_%d_variant%d.tres" % [sector.sector_coords.x, sector.sector_coords.y, idx]
    ResourceSaver.save(variant, variant_path)
    _rebuild_relationships_ui()
  , CONNECT_ONE_SHOT)
  
  dialog.popup_centered()
