@tool
extends Node3D
class_name TerrainRoot

var sectors: Array[SectorNode] = []

# Configuration
@export var size_x: int = 128
@export var size_y: int = 128
@export var sectors_x: int = 8
@export var sectors_y: int = 8
@export var resolution: float = 1.0
@export_storage var sector_size_x: int
@export_storage var sector_size_y: int
var locked := false

func _ready():
  if Engine.is_editor_hint():
    #sector_size_x = size_x / sectors_x
    #sector_size_y = size_y / sectors_y

    sectors.clear()
    for child in get_children():
      if child is SectorNode:
        sectors.append(child)



func build_grid():
  print("Building grid...")
  clear_sectors()
  sector_size_x = size_x / sectors_x
  sector_size_y = size_y / sectors_y
  for y in range(sectors_y):
    for x in range(sectors_x):
      var position = Vector3(x * sector_size_x, 0, y * sector_size_y)
      var sector = SectorNode.new()
      sector.sector_size_x = sector_size_x
      sector.sector_size_y = sector_size_y
      sector.resolution = resolution
      sector.sector_coords = Vector2i(x, y)
      sector.position = Vector3(x * sector_size_x, 0, y * sector_size_y)
      sector.name = "Sector %d-%d" % [x, y]
      add_child(sector)
      sector.owner = self.owner
      sectors.append(sector)

func clear_sectors():
  for s in sectors:
    s.queue_free()
  sectors.clear()

func save():
  for s in sectors:
    s.save_all()

func index(x: int, y: int) -> int:
  return y * sectors_x + x

func get_sector(x: int, y: int) -> SectorNode:
  return sectors[index(x, y)]
