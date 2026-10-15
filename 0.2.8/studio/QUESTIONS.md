# Questions

Open items an agent could not answer from the repo. Do not guess past these. Append a dated section. Do not delete an older question when a later one is added.

## 2026-10-14 — cubes per terrain block

`studio/ART-STYLE.md` proposes **8 cubes along one terrain block** for characters and creatures. The other candidate is **16**.

8 is proposed because ortho size 16 frames 32 world units top to bottom (16 blocks at `voxel_scale` 2). A cube at 8 per block is about 8 pixels on a 1080p frame and still reads as a cube. A cube at 16 per block is about 4 pixels and the stack stops reading as cubes at that camera.

Cole has not picked. Until this is answered, do not put either number into code as a locked constant, and do not author two grids.

## 2026-10-14 — `.vox` files or code grids

`studio/ART-STYLE.md` stores a character as a code-defined occupancy grid (one cell, one cube, material id, named parts). There is no `.vox` importer in this project.

Is a MagicaVoxel `.vox` file required later as the art source, with the grid generated from it, or is the code grid the authoring source for good?

## 2026-10-15 — player trial cube size

The player rig now builds from `VoxelModelBuilder` on the existing bones. The grid is 8×17×4 cubes and the cube edge is `player_height / 17`, so the feet, crown, and width stay on the current capsule. That is not `voxel_scale / 8` and not `voxel_scale / 16`.

`voxel_scale / 8` does not divide the 1.6-block body into a whole number of cubes, and the solid-body check still requires the silhouette to meet the capsule. Cole has not picked 8 or 16 cubes per block. This grid is a trial fit, not that choice.

## 2026-10-15 — boar and deer use the player trial cube

Boar and deer are voxel grids on that same trial edge (`player_height / 17` from `VoxelModelBuilder.player_grid_size().y`). They are not a second resolution and they are not `voxel_scale / 8` or `voxel_scale / 16`. The 8-versus-16 choice above is still open. A shorter boar is fewer cubes, not a smaller cube.

## 2026-10-15 — crystal creatures use the same trial cube

Crystal mite, crystal stag, crystal wisp, and corrupted beast use that same trial edge. A mite is fewer cubes, not a smaller cube. This is not a lock of 8 or 16 cubes per terrain block.

## 2026-10-15 — remaining creatures use the same trial cube

Bird, rabbit, town militia, farm bomber, thornling, and shard guard use that same trial edge. A bird is fewer cubes, not a smaller cube. Town villager, origin warden, and spawn elite were not in this pass. This is not a lock of 8 or 16 cubes per terrain block.
