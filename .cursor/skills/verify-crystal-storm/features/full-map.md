# Full map toggle

Pressing M opens a fullscreen topographical map covering more of the world than the minimap; while it is open the player cannot dig or move. Pressing M again, opening pause or dev chat, or a loading screen closes it.

## Sub-features

- `map-binding` `toggle_map` is M, not U; Space stays `jump`.
- `map-open` M opens the panel and sets `map_open`, blocking gameplay actions.
- `map-close` second M closes it.
- `map-auto-close` pause, dev chat, loading and safe mode close it.
- `map-coverage` full map samples more columns than the minimap.

## How to get to it (user POV)

- In world, press M (`toggle_map`).

## Driving it with cs-verify.sh

Preconditions:

- `doctor` OK, `quick` OK.

- **Binding.** Run `bash $S feature full-map`. Lines `OK M is toggle_map`, `OK toggle_map is not U`, `OK jump stays Space`.
- **Open and block.** Same run: `OK map starts closed`, `OK M opens the full map and blocks actions`.
- **Close paths.** `OK second toggle closes the map`, `OK pause closes the map`, `OK dev chat closes the map`, `OK loading closes the map`, `OK safe mode closes the full map`.
- **Proof.** `FEATURE full-map OK rc=0 marker='All full map toggle tests OK'`; log `feature-full-map.log`.

## Gotchas

- Suite drives `ui/topographical_map.gd` with `helpers/gameplay_input.gd` state, not inside a live `main.tscn`; how the map looks is unverified headless.
- Proven 2026-10-13 (run `proof-20261013`): all 14 OK lines, exit 0.
