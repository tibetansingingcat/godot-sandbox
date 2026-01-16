extends CharacterBody3D

enum MovementMode { GROUND, AIR, GLIDE }
var mode := MovementMode.GROUND
@onready var camera := $CameraRig/Camera3D
@onready var anim_player: AnimationPlayer = $Mesh/AnimationPlayer
@onready var anim_tree: AnimationTree = $AnimationTree
@export var speed: float = 5.0
var last_lean := 0.0
const JUMP_VELOCITY = 4.5

func handle_air(delta: float) -> void:
  velocity += get_gravity() * delta
#  handle_movement()

func _physics_process(delta: float) -> void:
  if not is_on_floor():
    velocity += get_gravity() * delta
  
  if Input.is_action_just_pressed("ui_accept") and is_on_floor():
    velocity.y = JUMP_VELOCITY
    #anim_player.play("jump_start")
    anim_tree.set("parameters/movement/transition_request", "jump")
    
  var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
  # camera basis makes it so the direction is based in the camera's angle
  var direction: Vector3 = (camera.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
  direction = Vector3(direction.x, 0, direction.z).normalized() * input_dir.length()
  if direction:
    velocity.x = direction.x * speed
    velocity.z = direction.z * speed
  else:
    velocity.x = move_toward(velocity.x, 0, speed)
    velocity.z = move_toward(velocity.z, 0, speed)
    
  move_and_slide()
  turn_to(direction)
  
  choose_anim()
  
func choose_anim() -> void:
  var current_speed := velocity.length()
  const RUN_SPEED = 3.5
  const BLEND_SPEED := 0.2
  if is_on_floor():
    print(anim_tree.get("parameters/movement/current_state"))
    if anim_tree.get("parameters/movement/current_state") == "fall":
      anim_tree.set("parameters/movement/transition_request", "soft_land")
    if current_speed > RUN_SPEED:
      anim_tree.set("parameters/movement/transition_request", "run")
      var lean := direction.dot(global_basis.x) * 2 # the delta between current direction and new movement direction
      last_lean = lerpf(last_lean, lean, 0.3)
      anim_tree.set("parameters/run_lean/add_amount", last_lean)
    elif current_speed > 0:
      anim_tree.set("parameters/movement/transition_request", "walk")
      var walk_speed := lerpf(0.5, 1.75, current_speed/RUN_SPEED)
      anim_tree.set("parameters/walk_speed/scale", walk_speed)
    else:
      anim_tree.set("parameters/movement/transition_request", "idle")
  else:
    if velocity.y < 0:
      anim_tree.set("parameters/movement/transition_request", "fall")

func turn_to(direction: Vector3) -> void:
  if direction:
    var yaw := atan2(-direction.x, -direction.z)  # turn character toward movement direction
    yaw = lerp_angle(rotation.y, yaw, 0.25)       # smooth rotation between directions
    rotation.y = yaw
