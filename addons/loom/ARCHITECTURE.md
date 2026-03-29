# Loom — Architecture Overview

Loom is a Godot 4 editor plugin for sector-based terrain sculpting with variant
support. It lets you divide a large terrain into a grid of sectors, sculpt each
sector independently, and maintain multiple variants (alternative versions) of
each sector that you can switch between without losing work.

## Core Concept

```
TerrainRoot (128x128 world units, 8x8 grid)
 ├─ Sector 0-0  ← each sector is 16x16 units
 │   ├─ variant 0: flat grassland (mesh + children)
 │   └─ variant 1: river canyon   (mesh + children)
 ├─ Sector 1-0
 │   └─ variant 0: default
 ├─ ...
 └─ Sector 7-7
     └─ variant 0: default
```

Each variant stores:
- An **ArrayMesh** with the sculpted vertex data
- A **PackedScene** of non-mesh children (trees, rocks, props)
- A **SectorVariant** resource with metadata (name, requirements, guarantees)

## File Layout

```
addons/loom/
├── loom.gd                        # EditorPlugin entry point — wires everything together
├── plugin.cfg                     # Plugin metadata
├── ARCHITECTURE.md                # This file
└── scripts/
    ├── sculpting_enums.gd         # Shared enums: Tool, SculptMode
    ├── terrain_root.gd            # TerrainRoot node — owns the sector grid
    ├── sector_node.gd             # SectorNode node — one terrain tile with variants
    ├── sector_variant.gd          # SectorVariant resource — data for one variant
    ├── variant_requirement.gd     # VariantRequirement — cross-sector constraint
    ├── variant_guarantee.gd       # VariantGuarantee — cross-sector constraint
    ├── sculpting_handler.gd       # Core sculpting logic (input, raycasting, mesh editing)
    ├── sculpt_dock.gd             # Persistent dock panel (tool/brush UI)
    ├── sector_node_inspector.gd   # Inspector plugin for SectorNode
    ├── terrain_root_inspector.gd  # Inspector plugin for TerrainRoot
    ├── sector_gizmo_plugin.gd     # (Disabled) Gizmo for sector bounds
    └── terrain_root_gizmo_plugin.gd  # (Disabled) Gizmo for terrain grid
```

Terrain data is saved to:
```
res://terrain/
├── sector_0_0_variant0.tres             # SectorVariant resource
├── sector_0_0_variant0_mesh.tres        # ArrayMesh
├── sector_0_0_variant0_children.tscn    # PackedScene of props/children
├── sector_0_0_variant1.tres             # Second variant
├── sector_0_0_variant1_mesh.tres
├── sector_0_0_variant1_children.tscn
├── sector_1_0_variant0.tres
└── ...
```

## Component Relationships

```
                    ┌──────────────┐
                    │   loom.gd    │  (EditorPlugin — entry point)
                    │              │
                    │ _enter_tree  │──creates──┐
                    │ _handles     │           │
                    │ _forward_3d  │           │
                    └──────┬───────┘           │
                           │                   │
            ┌──────────────┼───────────────────┼────────────────┐
            │              │                   │                │
            v              v                   v                v
   ┌─────────────┐  ┌────────────┐  ┌───────────────┐  ┌──────────────┐
   │ TerrainRoot │  │ SectorNode │  │  SculptDock   │  │  Sculpting   │
   │  Inspector  │  │  Inspector │  │  (dock panel) │  │   Handler    │
   └──────┬──────┘  └──────┬─────┘  └───────┬───────┘  └──────┬───────┘
          │                │                 │                 │
          │ buttons call   │ listens to      │ sliders/buttons │ receives 3D
          │ TerrainRoot    │ SectorNode      │ call handler    │ viewport input
          │ methods        │ signals         │ methods         │
          v                v                 v                 v
   ┌─────────────┐  ┌────────────┐  ┌───────────────────────────────┐
   │ TerrainRoot │  │ SectorNode │  │  Modifies sector mesh data    │
   │  (node)     │  │  (node)    │  │  via modify_sector_mesh()     │
   │             │  │            │  │  Manages undo/redo             │
   │ build_grid  │  │ variants   │  │  Synchronizes borders         │
   │ save        │  │ set_variant│  │  Draws brush preview + grid   │
   └─────────────┘  │ save/load  │  └───────────────────────────────┘
                    └────────────┘
```

## Signal Flow

Only two custom signals exist, both on SectorNode:

| Signal | Emitted by | Listened by | Triggers |
|--------|-----------|-------------|----------|
| `variants_changed` | `create_variant()`, `remove_variant()` | SectorNodeInspector | Rebuild variant list + relationships UI |
| `active_variant_changed(idx)` | `set_variant()` | SectorNodeInspector | Rebuild variant list UI (update [Active] label) |

All other communication uses Godot built-in signals (button.pressed, spinbox.value_changed, editor_selection.selection_changed).

## Sculpting Flow

```
1. User clicks in 3D viewport
   └─ loom.gd._forward_3d_gui_input()
      └─ sculpting_handler.handle_3d_input()

2. Mouse down (stroke start):
   ├─ Snapshot mesh of each sector under the brush (for undo)
   └─ sculpt_at_position()

3. Mouse drag (each frame):
   ├─ update_brush_preview() — move the yellow sphere
   ├─ Snapshot any NEW sectors the brush enters
   └─ sculpt_at_position()
       ├─ get_terrain_hit_position() — raycast to find hit point
       ├─ For each affected sector:
       │   └─ modify_sector_mesh() — iterate vertices, apply tool
       └─ synchronize_borders() — match edge vertices between neighbors

4. Mouse up (stroke end):
   ├─ update_collision_for_affected_sectors() — rebuild trimesh collision
   └─ finalize_sculpt_stroke() — create undo/redo action from snapshots
```

## Mesh Data Model

Each sector's mesh is a flat grid of vertices:

```
Resolution = 1.0, Sector size = 16x16
→ 17x17 = 289 vertices, 16x16x2 = 512 triangles

Vertex index = y * (nx + 1) + x
where nx = sector_size_x / resolution

Grid coordinates from flat index:
  x = index % (nx + 1)
  y = index / (nx + 1)
```

The vertex Y coordinate is the terrain height — sculpting modifies this value.
Normals are recalculated from triangle geometry after each edit.

## Variant System

Variants let you create multiple versions of a sector and switch between them:

- **Create variant**: duplicates the current mesh so you start from where you are
- **Set variant**: swaps the mesh, rebuilds collision, restores saved children
- **Save variant**: persists mesh + children + metadata to disk as 3 files
- **Remove variant**: deletes files and renames higher-indexed files down

### Requirements and Guarantees

Variants can declare cross-sector constraints (not yet enforced in code):

- **Requirement**: "this variant can only be used if sector (X,Y) has variant Z"
- **Guarantee**: "when this variant is active, sector (X,Y) must use variant Z"

These are stored on the SectorVariant resource and edited via the inspector dialog.

## Border Synchronization

When sculpting across sector boundaries, shared edge vertices must match or
visible seams appear. Two mechanisms prevent this:

1. **Multi-sector sculpting** (TerrainRoot selected): the brush affects all
   sectors it overlaps, then `synchronize_borders()` copies edge heights from
   each sector to its neighbors.

2. **Border protection** (SectorNode selected): a buffer zone near edges
   prevents sculpting, so you can't create mismatches with neighbors.

## Terrain Shader

A procedural shader colors the terrain by height:
- 0-4: sand → grass
- 8-12: grass → rock
- 18-22: rock → snow
- Steep slopes blend toward rock regardless of height

The shader runs in the fragment stage using world-space position passed from the vertex stage.
