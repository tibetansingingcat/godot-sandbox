@tool
extends Resource
class_name SectorVariant

@export var variant_name: String
@export var mesh: ArrayMesh

# what must exist for this variant to be selectable
@export var requires: Array[VariantRequirement] = []

# what this variant forces to exist elsewhere
@export var guarantees: Array[VariantGuarantee] = []
