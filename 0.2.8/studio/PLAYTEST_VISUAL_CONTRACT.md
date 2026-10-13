# Crystal Storm — Playtest Visual Contract

This supplements VISION/GAMEPLAY. It is the short visual language for agents.

## Coordinate language
For voxel/ramp discussions, state:
- world cell `(x,z)`
- world direction: **east** `+X`, **west** `−X`, **south** `+Z`, **north** `−Z`
- height of the **landing** cell (the higher column)
- height of the **approach** cell (the lower column, one cell toward the step-down)
- intended travel direction in those world-cell terms

Never use only "top", "bottom", "left", or "right" for world geometry. Camera yaw does not rename east/west.

## Ramp geometry contract

### Normal (cardinal) ramp
- Occupies **exactly one voxel column** — the **landing** (higher) cell.
- The **approach** cell is the neighbor one cell toward the step-down. It remains a **normal floor** (FACE_TOP). It must not disappear.
- The ramp is that landing column: one cell **back** from the approach (i.e. one cell toward the higher plateau).
- Exposed surface is a **slope** from landing voxel-top down to approach voxel-top. It is **not** a full square cap.
- Collision `walkable_height` on the landing interpolates that same slope. Approach collision is the approach column top.
- Direction is the world-cell step-down: `dir = approach - landing` (`Vector2i`).

### Corner ramp
- Used when a **low** cell has two perpendicular **plateau** neighbors one layer higher.
- It is a **diagonal half-block**: slope from the low column's FACE_TOP up to the two neighboring full-height tops, plus a **high support triangle** that meets those plateau tops.
- Isolated wedges (two pillars without the inner diagonal plateau) are not generated.
- The occupied column keeps its FACE_TOP floor; there is no hole through the voxel.

### Topology
- A cardinal ramp is a one-layer transition from landing to approach. Two landings must not point into the same approach (no V-shaped opposing ramps).
- Exposed ramp-cut sides are the neighboring terrain faces. Internal faces of the cut are not emitted.

### Render pipeline
Cardinal and corner ramps are **triangles in the terrain ArrayMesh** (same mesh as FACE_TOP), drawn with `ChunkSurfaceMesh.gdshader` (`cull_disabled`, ground-biased lighting, no alpha-hole discard). `FACE_RAMP` in `mesh_data.quads` is not proof the player can see a slope — F4 `column_surface_geometry` must report a sloped triangle set (`y_span` ≈ layer, corner `unique_xz` = 3) and the camera must show that slope. Concave L-fillers may still use a separate MultiMesh.

## Terrain editing
- `TerrainEdits.dig` / `try_dig` invalidates the edited cell plus the **shared-face neighbor cells** required for side lips and ramps (`DIRTY_HALO = 1`, edge band 1).
- Incremental remesh **rebuilds the merged keep+patch quad list**. It must not drop greedy remainder faces because clip changed `dim_x`/`dim_z`.
- It must never clear unrelated resident terrain. Chunk boundaries stay intact.
- After the edit and after remesh, the **rendered** column must agree with F4 (`column_mesh_covered`, face codes, walk/surf).

Ordinary terrain placement must not infer a wall, bridge, gate, or other authored structure.

Place tools (Tab cycle): Fill, Ramp, Corner ramp, Wall, Gate, Bridge. RMB places the selected tool. LMB removes using the subtract contract.

## Scale
The voxel is the primary world unit. Vegetation, props, enemies, structures, ramps, and effects need intentional readable scale relative to it.

## Material direction
Current generated terrain textures are placeholders.

Desired direction:
- pixel-art interpretation of real materials
- recognizable stone, dirt, grass, sand, snow, bark, etc.
- material structure instead of flat color plus random dots
- consistent readability at the isometric camera distance

Do not spend large engineering cycles perfecting placeholder art before the gameplay surface is stable.

## What needs visual confirmation
High-value live checks:
1. terrain shape / ramps / holes
2. player movement + camera relation
3. building/removal
4. water behavior
5. crystal presentation
6. enemies/combat
7. vegetation/world density
8. macro/micro terrain scale

Other internal systems can primarily use state/contract tests unless they affect what the player sees.

## Screenshot rule
When a visual bug is ambiguous, use a screenshot plus cell coordinates and intended geometry. The screenshot is evidence, not the complete specification. Headless FACE_RAMP / F4 AGREE is not sufficient if the camera shows a hole or a square cap.
