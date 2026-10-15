# Questions

Open items an agent could not answer from the repo. Do not guess past these. Append a dated section. Do not delete an older question when a later one is added.

## 2026-10-14 — cubes per terrain block

`studio/ART-STYLE.md` proposes **8 cubes along one terrain block** for characters and creatures. The other candidate is **16**.

8 is proposed because ortho size 16 frames 32 world units top to bottom (16 blocks at `voxel_scale` 2). A cube at 8 per block is about 8 pixels on a 1080p frame and still reads as a cube. A cube at 16 per block is about 4 pixels and the stack stops reading as cubes at that camera.

Cole has not picked. Until this is answered, do not put either number into code as a locked constant, and do not author two grids.

## 2026-10-14 — `.vox` files or code grids

`studio/ART-STYLE.md` stores a character as a code-defined occupancy grid (one cell, one cube, material id, named parts). There is no `.vox` importer in this project.

Is a MagicaVoxel `.vox` file required later as the art source, with the grid generated from it, or is the code grid the authoring source for good?
