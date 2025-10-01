@tool
extends EditorInspectorPlugin

var sector_node: SectorNode
var variants_box: VBoxContainer

func _can_handle(obj):
  return obj is SectorNode
  
func _parse_begin(obj):
  sector_node = obj as SectorNode
  print(sector_node, sector_node.get_class(), sector_node.get_script())
  sector_node.variants
  var button = Button.new()
  button.text = "Create variant"
  button.pressed.connect(func():
    sector_node.create_variant()
  )
  add_custom_control(button)

  var save_current_button = Button.new()
  save_current_button.text = "Save Node (Current Variant Only)"
  save_current_button.pressed.connect(func():
    sector_node.save_current()
  )
  
  add_custom_control(save_current_button)
  
  var save_all_button = Button.new()
  save_all_button.text = "Save Node (All Variants)"
  save_all_button.pressed.connect(func():
    sector_node.save_all()
  )
  
  add_custom_control(save_all_button)
  
  # -- Variant list
  variants_box = VBoxContainer.new()
  add_custom_control(variants_box)
  _rebuild_variants_ui()
  
  # -- Listen for changes to refresh our UI
  if not sector_node.is_connected("variants_changed", _on_variants_changed):
      sector_node.variants_changed.connect(_on_variants_changed)
  if not sector_node.is_connected("active_variant_changed", _on_active_variant_changed):
      sector_node.active_variant_changed.connect(_on_active_variant_changed)


func _on_variants_changed():
    _rebuild_variants_ui()

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

    for i in range(sector_node.variants.size()):
        var row := HBoxContainer.new()

        # Name field (uses variant_name if present)
        var name := "Variant %d" % i
        if sector_node.variants[i] and sector_node.variants[i].variant_name != "":
            name = sector_node.variants[i].variant_name

        var name_edit := LineEdit.new()
        name_edit.text = name
        name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        name_edit.text_submitted.connect(func(t, idx := i):
            var m := sector_node.variants[idx]
            if m:
                m.resource_name = t
                sector_node.emit_signal("variants_changed") # refresh list label
        )
        row.add_child(name_edit)

        if i == sector_node.active_variant:
            var active_lbl := Label.new()
            active_lbl.text = "  [Active]"
            row.add_child(active_lbl)
        else:
            var set_btn := Button.new()
            set_btn.text = "Set Active"
            set_btn.pressed.connect(func(idx := i):
                sector_node.set_variant(idx) # will emit signal; we rebuild on signal
            )
            row.add_child(set_btn)

        # Optional: remove button
        # var del_btn := Button.new()
        # del_btn.text = "Remove"
        # del_btn.pressed.connect(func(idx := i):
        #     sector_node.remove_variant(idx)
        # )
        # row.add_child(del_btn)

        variants_box.add_child(row)
