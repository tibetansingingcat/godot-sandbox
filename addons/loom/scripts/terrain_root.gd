## terrain_root.gd — Top-level container for the entire terrain
##
## TerrainRoot is a Node3D that owns a flat grid of SectorNode children.
## It defines the overall terrain dimensions (size_x × size_y in world units),
## how many sectors to divide that into (sectors_x × sectors_y), and the mesh
## resolution. Each sector is positioned at its grid cell and manages its own
## mesh and variants independently.
##
## The inspector adds two buttons via TerrainRootInspector:
##   - "Rebuild Grid" → build_grid()  (destroys and recreates all sectors)
##   - "Save Grid"    → save()        (saves every sector's variants to disk)
@tool
extends Node3D
class_name TerrainRoot

var sectors: Array[SectorNode] = []

# --- Exported configuration (visible in Inspector) ---
@export var size_x: int = 128       ## Total terrain width in world units
@export var size_y: int = 128       ## Total terrain depth in world units
@export var sectors_x: int = 8      ## Number of sectors along X axis
@export var sectors_y: int = 8      ## Number of sectors along Z axis
@export var resolution: float = 1.0 ## Vertex spacing — smaller = more detail

# Derived from size / sectors. Stored so sectors can read them after reload.
@export_storage var sector_size_x: int
@export_storage var sector_size_y: int

var locked := false

func _ready():
  if Engine.is_editor_hint():
    # On editor load, rebuild the in-memory sectors array from existing children.
    # We don't recompute sector_size here — that only happens in build_grid() —
    # so the stored values stay consistent with the meshes on disk.
    sectors.clear()
    for child in get_children():
      if child is SectorNode:
        sectors.append(child)


func build_grid():
  ## Destroy all existing sectors and create a fresh grid.
  ## Called from the "Rebuild Grid" inspector button.
  print("Building grid...")
  clear_sectors()
  sector_size_x = size_x / sectors_x
  sector_size_y = size_y / sectors_y
  for y in range(sectors_y):
    for x in range(sectors_x):
      var sector = SectorNode.new()
      sector.sector_size_x = sector_size_x
      sector.sector_size_y = sector_size_y
      sector.resolution = resolution
      sector.sector_coords = Vector2i(x, y)
      sector.position = Vector3(x * sector_size_x, 0, y * sector_size_y)
      sector.name = "Sector %d-%d" % [x, y]
      add_child(sector)
      sector.owner = self.owner  # Required for the editor to persist the node in the scene
      sectors.append(sector)

func clear_sectors():
  for s in sectors:
    s.queue_free()
  sectors.clear()

func save():
  ## Save every sector's variants (mesh + children + resource) to res://terrain/.
  for s in sectors:
    s.save_all()

func index(x: int, y: int) -> int:
  ## Convert 2D grid coordinates to a flat array index (row-major order).
  return y * sectors_x + x

func get_sector(x: int, y: int) -> SectorNode:
  return sectors[index(x, y)]
