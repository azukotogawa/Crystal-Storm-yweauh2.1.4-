# Water flow

Rivers are sources. Digging a trench or breaking the block between water and an existing hole floods the whole connected gap to one surface height over the next ticks; dry digs stay dry and filling the hole dries the flood.

## Sub-features

- `water-flood` breaking into a river floods from the source surface.
- `water-level` propagated cells share one surface_y.
- `water-gap-fill` a long gap keeps filling on follow-up ticks (backlog #8).
- `water-dry` dry digs and blocked trenches stay dry; filling dries the flood.

## How to get to it (user POV)

- Dig next to a river with the pickaxe, or break the wall between a river and a hole.

## Driving it with cs-verify.sh

Preconditions:

- `doctor` OK, `quick` OK.

- **Flood.** Run `bash $S feature water`. `OK flood from river source surface_y=…`, `OK propagation same surface_y`.
- **Gap fill.** Same run: `OK water spread through the opened link`, `OK continued spread past the first empty cells`, `OK full gap filled across follow-up ticks cells=N`.
- **Stays dry.** `OK dry dig stays dry`, `OK blocked trench stays dry`, `OK fill dries flood; river still source`.
- **Proof.** Marker `All water body tests OK`; log `feature-water.log`.

## Gotchas

- Abrupt-exit suite: exit 137/134 after the marker is a pass.
- Swimming (`helpers/water_locomotion.gd`, backlog #11a) is not covered here yet.
