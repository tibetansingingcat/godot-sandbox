## sector_variant.gd — Data class for one variant of a sector
##
## Stored as a .tres resource at res://terrain/sector_X_Y_variantN.tres.
## The mesh is saved separately as _mesh.tres and referenced here.
##
## Requirements and guarantees define constraints between variants across
## different sectors — e.g. "this river variant requires the adjacent sector
## to also have a river variant" or "this cliff variant guarantees the sector
## below has a matching cliff base variant."
@tool
extends Resource
class_name SectorVariant

@export var variant_name: String
@export var mesh: ArrayMesh

## What must exist elsewhere for this variant to be selectable.
## Example: "sector (3,2) must have variant 'river_mouth'"
@export var requires: Array[VariantRequirement] = []

## What this variant forces to exist elsewhere when it is active.
## Example: "sector (3,4) must be set to 'cliff_base'"
@export var guarantees: Array[VariantGuarantee] = []
