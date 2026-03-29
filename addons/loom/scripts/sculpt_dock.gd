## sculpt_dock.gd — Persistent dock panel for sculpting controls
##
## Lives in the top-left dock slot of the editor. Contains:
##   - Tool selection buttons (Select, Raise, Lower, Smooth, Flatten)
##   - Brush size and strength sliders
##
## When a button/slider changes, the dock calls the corresponding method
## on sculpting_handler (set_tool, set_brush_size, etc). The handler
## reference is set by loom.gd after both are created.
@tool
extends Control

const Tool = SculptingEnums.Tool
const SculptMode = SculptingEnums.SculptMode

var current_mode := SculptMode.BASE_SCULPTING
var current_tool := Tool.RAISE
var brush_size := 2.0
var brush_strength := 1.0

var mode_buttons: Array[Button] = []
var tool_buttons: Array[Button] = []
var vbox: VBoxContainer

var sculpting_handler: SculptingHandler  ## Set by loom.gd after construction

func _init():
  name = "Terrain Sculpting"
  set_custom_minimum_size(Vector2(200, 400))
  setup_ui()
  
func setup_ui():
  vbox = VBoxContainer.new()
  add_child(vbox)
  
  var title = Label.new()
  title.text = "Terrain Sculpting"
  title.add_theme_font_size_override("font_size", 16)
  vbox.add_child(title)
  
  setup_tool_buttons()
  setup_brush_settings()
  
func setup_brush_settings():
  var brush_size_label = Label.new()
  brush_size_label.text = "Brush Size"
  vbox.add_child(brush_size_label)
  
  var brush_size_input = SpinBox.new()
  brush_size_input.min_value = 0.5
  brush_size_input.max_value = 10.0
  brush_size_input.step = 0.1
  brush_size_input.value = brush_size
  brush_size_input.value_changed.connect(_on_brush_size_changed)
  vbox.add_child(brush_size_input)
  
  var brush_strength_label = Label.new()
  brush_strength_label.text = "Brush Strength"
  vbox.add_child(brush_strength_label)
  
  var brush_strength_input = SpinBox.new()
  brush_strength_input.min_value = 0.1
  brush_strength_input.max_value = 5.0
  brush_strength_input.step = 0.1
  brush_strength_input.value = brush_strength
  brush_strength_input.value_changed.connect(_on_brush_strength_changed)
  vbox.add_child(brush_strength_input)
  
func _on_brush_size_changed(value: float):
  brush_size = value
  if sculpting_handler:
    sculpting_handler.set_brush_size(brush_size)
  print("Brush size changed to ", value)
  
func _on_brush_strength_changed(value: float):
  brush_strength = value
  print("Brush strength changed to ", value)
  if sculpting_handler:
    sculpting_handler.set_brush_strength(value)
  
func setup_mode_buttons():
  var mode_group = ButtonGroup.new()
  
  var modes_label = Label.new()
  modes_label.text = "Sculpting Mode:"
  vbox.add_child(modes_label)
  
  var mode_names = ["Base Sculpting", "Global Variant", "Isolated Variant"]
  var mode_values = [SculptMode.BASE_SCULPTING, SculptMode.GLOBAL_VARIANT, SculptMode.ISOLATED_VARIANT]
  
  for i in range(mode_names.size()):
    var btn = Button.new()
    btn.text = mode_names[i]
    btn.toggle_mode = true
    btn.button_group = mode_group
    btn.button_pressed = (i == 0)
    btn.toggled.connect(_on_mode_changed.bind(mode_values[i]))
    vbox.add_child(btn)
    mode_buttons.append(btn)
    
func setup_tool_buttons():
  var tool_group = ButtonGroup.new()
  
  var tools_label = Label.new()
  tools_label.text = "Tool:"
  vbox.add_child(tools_label)
  
  var tool_names = ["Select", "Raise", "Lower", "Smooth", "Flatten"]
  var tool_values = [Tool.SELECT, Tool.RAISE, Tool.LOWER, Tool.SMOOTH, Tool.FLATTEN]
  
  for i in range(tool_names.size()):
    var btn = Button.new()
    btn.text = tool_names[i]
    btn.toggle_mode = true
    btn.button_group = tool_group
    btn.button_pressed = (i == 0)
    btn.toggled.connect(_on_tool_changed.bind(tool_values[i]))
    vbox.add_child(btn)
    tool_buttons.append(btn)

func _on_mode_changed(pressed: bool, mode: SculptMode):
  if pressed and sculpting_handler:
    current_mode = mode
    sculpting_handler.set_sculpt_mode(mode)
    print("Mode changed to ", mode)
    
func _on_tool_changed(pressed: bool, tool: Tool):
  if pressed and sculpting_handler:
    current_tool = tool
    sculpting_handler.set_tool(tool)
    print("Tool changed to ", tool)

func _ready():
  print("Sculpting dock ready!")
