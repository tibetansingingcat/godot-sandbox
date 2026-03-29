## sculpting_enums.gd — Shared enum definitions for sculpting modes and tools
class_name SculptingEnums

enum SculptMode {
  BASE_SCULPTING,     ## Sculpt across all sectors (borders synchronized)
  GLOBAL_VARIANT,     ## (Planned) Sculpt variant with cross-sector awareness
  ISOLATED_VARIANT    ## (Planned) Sculpt only the active variant, borders protected
}

enum Tool {
  RAISE,    ## Push vertices up
  LOWER,    ## Push vertices down
  SMOOTH,   ## Average vertex heights with neighbors
  FLATTEN,  ## Lerp vertices toward the clicked height
  SELECT    ## Click to select a sector node (no sculpting)
}
