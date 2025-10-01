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
var sector_size_x: int
var sector_size_y: int
var locked := false

func build_grid():
  print("Building grid...")
  clear_sectors()
  for y in range(sectors_y):
    for x in range(sectors_x):
      sector_size_x = size_x / sectors_x
      sector_size_y = size_y / sectors_y
      var position = Vector3(x * sector_size_x, 0, y * sector_size_y)
      var sector = SectorNode.new(sector_size_x, sector_size_y, resolution, Vector2i(x, y), position)

      sector.name = "Sector %d-%d" % [x, y]
      print("Created sector " + sector.name)
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
