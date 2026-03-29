extends SpringArm3D

@onready var camera: Camera3D = $Camera3D
@onready var player := get_parent()
@onready var camera_rig_height := position.y

@export var turn_rate := 200
@export var mouse_sensitivity := 0.25

var mouse_input := Vector2()

func _ready() -> void:
  spring_length = camera.position.z
  Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
  
func _process(delta: float) -> void:
  var look_input := Input.get_vector("view_right", "view_left", "view_down", "view_up")
  look_input *= turn_rate * delta
  look_input += mouse_input
  mouse_input = Vector2()
  
  rotation_degrees.x += look_input.y
  rotation_degrees.y += look_input.x
  rotation_degrees.x = clampf(rotation_degrees.x, -60.0, 45.0)
  
func _physics_process(delta: float) -> void:
  position = player.position + Vector3(0, camera_rig_height, 0)
  
func _input(event: InputEvent) -> void:
  if event is InputEventMouseMotion: 
    mouse_input = event.relative * -mouse_sensitivity
  elif event is InputEventKey and event.keycode == KEY_ESCAPE and event.is_pressed():
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
  elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
