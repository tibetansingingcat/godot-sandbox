extends RigidBody3D

@export var float_force := 1.0
@export var water_drag := 0.05
@export var water_angular_drag := 0.05

@onready var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

const water_height := 0.0

var submerged := false

func _physics_process(delta: float) -> void:
  submerged = false
  var depth: float = water_height - global_position.y
  if depth > 0:
    submerged = true
    apply_central_force(Vector3.UP * float_force * gravity * depth)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
  if submerged:
    state.linear_velocity *= 1 - water_drag
    state.angular_velocity *= 1 - water_angular_drag
