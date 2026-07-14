# Gameplay: implemented surface and intended loop

## Implemented prototype interactions

The production scene (`scenes/main.tscn`) contains a controllable player, chunk-streamed terrain, camera rotation/zoom, mouse-aware action targeting, inventory/hotbar, terrain dig/build paths, basic melee/ranged/tool weapons, entities, crystal simulation and spawn points, world features, a topographical map, save/load, visual feedback, and developer tools.

Current item definitions include a wooden sword, stone pick, shortbow, and material stacks. The player uses WASD/arrow movement, `M` jump, `Q`/`E` camera rotation, wheel zoom, attack, interaction/build actions, hotbar selection, and map/inventory/dev/debug bindings defined in `project.godot`. Target highlights communicate dig (orange), build (green), and attack (red) modes.

Terrain edits are column-based. `TerrainEdits` records height deltas and build tiles; `TerrainEditor` applies edits through the chunk manager so affected chunks rebuild. This is not arbitrary full-volume block placement or destruction.

## Run and phase model

`GameManager` defines `MAZE` and `ASSAULT` phases and run states. Its configured distances make maze play the default strategic period, with assault pressure nearer the crystal. `CrystalManager` owns pressure-flow simulation, absorption/evolution hooks, spawn placement/control, and optional player-contact defeat. Spawn destruction gates the origin/boss goal through `SpawnPointController`.

This establishes the intended two-phase loop, but it is still prototype-grade: balance, final enemy variety, full relic progression, complete loss/win presentation, and content tuning require design ownership.

## World features

`WorldFeatures` seeds towns, vegetation, ruins, and entity spawn data. Vegetation can grow and supply crystal-flow/absorption modifiers. Town defense state reacts to nearby crystal and can request militia. The `VoxelFluidService` provides player-made water channels; the generic `VoxelFluidEngine` is shared infrastructure, with crystal using a pressure-pool model.

## What not to claim

Do not describe the game as feature-complete, a finished roguelike, or as having a finalized economy, boss encounter, progression, or art direction. Automated verification demonstrates contracts and regression coverage, while `manual_verification.md` explicitly reserves final interactive and visual sign-off for a human.
