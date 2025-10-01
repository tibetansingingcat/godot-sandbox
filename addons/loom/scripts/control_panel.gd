@tool
extends VBoxContainer

@onready var global_x: SpinBox = %GlobalX
@onready var global_y: SpinBox = %GlobalY
@onready var sectors_x: SpinBox = %SectorsX
@onready var sectors_y: SpinBox = %SectorsY

var current_terrain: TerrainRoot

func _on_create_terrain_button_pressed() -> void:
    print("button pressed")
    if global_x.value == 0 or global_y.value == 0:
        print("Need terrain size values to be greater than 0")
        return

    var root = get_tree().edited_scene_root
    if not root:
        print("No root scene open!")
        return

    # Create terrain
    current_terrain = TerrainRoot.new()
    current_terrain.name = "TerrainRoot"

    # Configure from UI
    current_terrain.size_x = int(global_x.value)
    current_terrain.size_y = int(global_y.value)
    current_terrain.sectors_x = int(sectors_x.value)
    current_terrain.sectors_y = int(sectors_y.value)
    current_terrain.resolution = 1.0
    print("Terrain parameters set.")

    # Generate the grid
    current_terrain.build_grid()

    # Add to scene
    root.add_child(current_terrain)
    current_terrain.owner = root

    print("Terrain added to scene")
