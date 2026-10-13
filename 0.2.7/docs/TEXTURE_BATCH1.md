# Texture batch 1

Pixel-art stand-ins for the item, vegetation, and mob slots under `assets/art/`. Sizes come from `docs/texture_manifest.json`. The native grid is one texel per art pixel (32, 40, 48, or 64). Nothing under `assets/art/` is overwritten except the three crystal icons that were missing.

## Regenerate

From the game directory:

```
godot --headless --path . -s res://tools/gen_texture_batch.gd
```

The tool reads the manifest, writes `assets/art_batch1/` (same relative paths as `assets/art/`), writes `assets/art_batch1/vegetation/corrupted_*.png`, and writes `assets/art/crystal/amethyst.png`, `void_shard.png`, and `solar_crystal.png`. Seeds are fixed. A contact sheet is optional:

```
godot --headless --path . -s res://tools/gen_texture_batch.gd -- --contact /path/contact_sheet.png
```

`CRYSTALSTORM_CONTACT_OUT` is the same option. The sheet is not part of the project. After new PNGs exist, import the project and run `tools/export_texture_manifest.gd` so each slot records `batch1`.

## Switch sets

Settings > Graphics > **Texture set**: Original or Batch 1. The value is `texture_set` in `user://player_settings.json` (`original` or `batch1`). The default is Original.

`helpers/texture_set.gd` `resolve(path)` returns the batch file when Batch 1 is active and that file exists, otherwise the original path. Results are cached until the set changes. Changing the option reloads the visual registry, entity sprites, plant anchors, and the hotbar and inventory icons. F6 (texture blueprint) still replaces the textures of whichever set is active.

## What the batch covers

| Group | Files | Size |
| --- | --- | --- |
| Item icons | 7 | 32×32 |
| Building sprites | 6 | 48×48 |
| Mobs | 12 | 48×48, wisp 32×32 |
| Vegetation | 22 | 40×40, crystal plants 32×32 |
| Corrupted vegetation | 22 | same as the healthy plant |
| Crystal icons | 3 | 64×64, written under `assets/art/crystal/` |

`player.png` and the structure albedo plates and photo sources are not remapped. Terrain, UI, and particles stay on their original files. `facet.png` has no batch mirror.

## Corruption

The crystal sim still replaces an absorbed plant with a crystal plant id. Original textures keep that swap. Batch 1, on a cell with `corrupt`, draws `corrupted_<original_plant>_s<original_stage>` as a billboard even when voxel vegetation is enabled. Healthy plants stay on the voxel props.

## Palette

Each subject uses a few flat colours, a 1px dark outline, and top-left light. No anti-aliasing. Opaque pixels are fully opaque. Corners stay clear.

- Wood and leaves: warm brown, sap green.
- Stone and metal: cool grey.
- Crystals: violet with magenta glow pixels.
- Corrupted plants and the corrupted beast: purple-black with magenta glow (`255, 40, 180`).
- Animals: fur, deer brown, boar brown, bird blue.
- People: skin plus a blue tunic.
- Solar crystal: gold. Void shard: near-black purple.

A sprite stays at or under 24 colours.
