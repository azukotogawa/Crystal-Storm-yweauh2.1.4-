# Crystal Storm Multiplayer Plan

Status: **plan only**. No networking code exists. The sole hook is `SaveSchema.future_extension_stubs()` in `systems/save_schema.gd`: `authority.mode = local_singleplayer`. This document is grounded in the 0.2.7 tree (`cs/m7-cleanup` snapshot). Godot 4.7 / GDScript. Steam is the ship target (`export_presets.cfg` currently Windows Desktop only).

## Assumptions

- **Co-op size:** 2 players for the first ship, hard cap 4. The loop is one shared run against one crystal, not PvP or MMO.
- **Session model:** friends join one host’s world for a run. Drop-in late join is required; host migration is not in v1.
- **Sim budget:** the host already spends a 16.6 ms frame on chunks, crystal, entities, and bake (`FrameBudgetScheduler`, `PerfProfiler`). Extra peers buy more stream rings, not a second sim.
- **World size:** playable half is 1024 columns (`WorldBorder.PLAYABLE_HALF_X/Z`) → 128×128 chunks at `ChunkData.SIZE = 16`. Full bake is ~16384 `.chk` packages (`WorldBakeService`). Do not ship bake files over the wire.
- **Edits are sparse heightfield overlays**, not 3D voxel volumes. `ChunkData.set_voxel` is a no-op. Dig/build is `TerrainEdits.dig` / `build_wall` (±1 layer, floor −6 / cap +8). That keeps bandwidth tractable.

---

## 1. Godot 4 high-level multiplayer

Use the built-in `MultiplayerAPI` / `SceneMultiplayer` on the scene tree. Do not invent a second RPC layer.

| Piece | Role here |
| --- | --- |
| `ENetMultiplayerPeer` | LAN / two-local-instance development. First transport. |
| `WebRTCMultiplayerPeer` | Skip for Steam desktop. Useful later only if a web build appears. |
| Steam Networking Sockets via `SteamMultiplayerPeer` (GodotSteam) | Production transport: lobbies, invites, NAT traversal. Same `SceneMultiplayer` on top. |
| `@rpc` | Discrete events: dig/build, combat hits, relic picks, spawn/despawn, crystal depth deltas, inventory grants. |
| `MultiplayerSpawner` | Player pawns, `WorldEntity`, `CrystalEnemy`, `Projectile` visual nodes, `WorldObject` structures. Spawn path must be a packed scene; several of these are currently `new()`’d in code (`CrystalEnemySpawner`, `EntityManager._spawn_from_save`, `Projectile.launch`). |
| `MultiplayerSynchronizer` | High-rate pose: local player `voxel_position` / yaw, enemy/wildlife interpolation. **Do not** put `WorldState.height_delta`, crystal `depth`, or inventory on a synchronizer. |
| Authority | `multiplayer.is_server()` owns world, crystal, fluids, AI, combat resolution, save. Each peer has authority on its own pawn **input**; the host confirms position and all world mutations. |

Replication rule of thumb: **RPC a delta that already has a revision** (`WorldState.revision`, `terrain_revision`, …). Full dictionaries (`height_delta`, crystal `depth`) go only on join / checksum mismatch.

---

## 2. Topology

### Options

**Listen-server (host plays, host simulates).** One Steam lobby. Host’s process is the authority. Clients send input and edit requests. Matches the current single-process boot (`CompositionRoot` → `scenes/main.tscn`).

**Dedicated headless server.** The tree already boots `--headless` for `scripts/run_all_verify.gd` / `scripts/profile_gameplay.gd`. A dedicated process would run `CompositionRoot` without a local `Player` camera/UI, same `WorldState` + `CrystalSimulation`. Steam would still need a lobby or a relay.

### Recommendation: listen-server first, dedicated as a probe and a later SKU

Reasons:

- Crystal + chunk + entity cost is one sim, not N. A dedicated box still runs that sim and must stream a union of player rings; it does not remove the hard part.
- Host-owned save already exists (`SaveGameService.save_world_id` → `user://saves/world_{id}.json`).
- Steam P2P / lobbies are built for this shape. Paying for dedicated servers is a later product choice.
- Headless dedicated remains the **test** for “does the sim run with zero local pawn?” and a future dedicated SKU.

Tradeoffs of listen-server: host lag is ~0; host disconnect ends the session (v1); host hardware caps player count when two scouts split the map.

### Authority vs prediction

| Domain | Policy |
| --- | --- |
| Movement | **Client predicted, host reconciled.** `Player` already integrates custom voxel motion (`voxel_position`, `VoxelFloorProbe`), not `move_and_slide`. Local peer applies input immediately; host simulates the same step from input; snap if error exceeds one column. Remote pawns interpolate. |
| Dig / build / plant / channel | **Host authoritative, optional speculative apply.** `TerrainEditor` already validates then writes `WorldState`. Client may apply locally and roll back with `WorldState.restore_overlay_snapshot` if the host rejects (range, materials, floor −6 / +8). Hold-repeat is already 0.16 s (`WeaponController.TERRAIN_HOLD_REPEAT_START_SEC`); waiting on an RPC is acceptable. |
| Combat | **Host resolves.** `CombatHitResolver` + `WeaponStrike` + `CrystalManager.damage_crystal_at`. Client plays swing VFX immediately; damage numbers and breaks wait on host. |
| Crystal / water / AI / towns / win-loss | **Host only.** Clients receive events (`CrystalSimEvents`, depth rows, entity pose, `GameManager` phase). |

---

## 3. What must change in this architecture

### World generation (already mostly OK)

`InfiniteNoiseWorld` is seed-deterministic: FastNoiseLite from `world_seed`, temperature roll `world_seed + temperature_roll_seed_offset`, `BiomeLayout.ensure_generated(world_seed, …)`, river mask, caves. `TerrainRamps.should_place_ramp` is a position hash, not `randf`. Clients **regenerate terrain from the shared seed**. They do not download `user://world_bakes/v4_s{seed}_*/chunks/*.chk`.

`WorldBakeService` is a local cache (index + per-chunk packages, vegetation payloads). Each peer bakes/loads its own packages. Overlay mutations never live in the bake; `WorldState` is the authority (`AGENTS.md`). Micro bricks are **not** saved (`derive_micro_from_terrain_edits` on rebuild) — clients re-derive.

Must-sync at session start: `world_seed`, `WorldGenConfig` fields that affect height/caves, `WorldSettings.voxel_scale`, quality-independent sim config (`GameConfig` / `CrystalSimConfig`). Quality presets (`PerformanceQualityConfig`, `PlayerSettings`) stay **local** and must not change sim: today `render_distance` changes `ChunkManager.RENDER_DISTANCE`, which changes which cells `CrystalManager._is_cell_sim_active` considers live. **On the host, sim-active chunks must be the union of all player rings plus origin extras, independent of any client’s graphics distance.**

### Voxel world state and per-player streaming

`ChunkManager.update_stream(cx, cz)` and `_player_chunk_coord()` follow **one** `player: Node3D` (`get_first_node_in_group("player")`). Crystal keeps origin ±1 resident (`_start_threat_chunk_coords`) because sim is loaded-chunks-only.

Change:

- Host stream set = union of every pawn’s Chebyshev ring + origin extras. Caps (`max_inflight`, `streaming_budget_us`) need a 2–4 player budget pass.
- Each **client** streams visually around **its** pawn only. Host still simulates cells a client has unloaded.
- `chunk_ready` / `chunk_unloaded` currently wake `EntityManager`, `CrystalManager`, vegetation. Those wakes must not despawn host-sim entities just because the host’s local camera walked away.

Late join: send `world_seed` + `WorldState.export_persistence_bundle()` + crystal `export_state()` + entity/enemy export + `game` phase. Client `import_persistence_bundle`, then streams its ring. Do not send GPU meshes.

### Digging / building / block-edit sync

Pipeline today: `WeaponController` → `TerrainEditor.try_*` → `TerrainEdits` / `FeatureRegistry` / `ChannelRegistry` / `BuildingRegistry` → `WorldState.bump(domain)` → chunk remesh + `terrain_edited` (crystal height cache) + water dirty.

Net version:

1. Client RPC `edit_request(kind, wx, wz, extra)` with predicted `WorldState.revision`.
2. Host runs the existing `TerrainEditor` path (materials from **that peer’s** inventory).
3. Host RPC `edit_commit(revision, domain, cell, payload)` to all. Payload is one column: height_delta, build_tile, feature cell, or channel dict — not the whole overlay.
4. Clients apply and remesh. If `revision` skipped, request a snapshot for that domain.
5. `WorldObject` instances (`scenes/world_object.tscn`) spawn via `MultiplayerSpawner` or a visual-id RPC (`visual_id` / `build_id` / yaw already persist on the feature overlay).

Bandwidth: a dig is a few ints. A late-join overlay is the save blob the game already writes (sparse `height_delta` / `build_tile`). Keep a host-side **edit log** (the save stub already names `replay.mutation_log`) for catch-up between snapshots.

### Crystal spread / corruption

Split is already the right shape: `CrystalSimulation` is pure (`RefCounted`, no `get_tree()`), consumes `CrystalSimSnapshot`, emits `CrystalSimEvents`. `CrystalManager` is the façade; `CrystalPresentation` rebuilds meshes.

- **Host** ticks `CrystalSimulation` (flow budget, `max_new_cells_per_tick`, loaded-union mask).
- Broadcast **events / dirty cells**, not the full `depth` dict, every tick. Full `export_state()` (`depth` rows, spawns, absorption, evolution) on join and on checksum fail.
- `CrystalCorruption` keeps **process-global static** `_scars`. Move scars onto session state (or `WorldState`) so two processes do not diverge and so save/load stays the overlay path.
- `_rng.seed = world.world_seed + 9001` in `CrystalManager._ready` — host owns this RNG. Clients do not roll spawn placement.
- `CrystalEnemySpawner` and assault DPS (`GameManager._apply_crystal_damage`) currently target one player. Contact, field burn, and mite spawn radii must consider **every** pawn. `GameManager._update_phase` (MAZE/ASSAULT hysteresis vs nearest crystal) should use min distance across peers, or per-player HUD phase with a shared assault flag — pick one and document it. Recommendation: **shared phase** from the nearest pawn so the run clock stays one clock.

### Fluids

`VoxelFluidService` + `VoxelFluidEngine` is a dirty-set gravity channel on `WorldState.channels`. Sleeps when `_dirty_cells` is empty. Crystal does **not** share this map (`CrystalTerrainQuery` only reads wetness for conductivity).

Host ticks water. Persist `water_level` / `flow_dir` through the same overlay delta channel as terrain. Passive level changes currently have no gameplay listeners (`channel_fluid_changed`); visuals can stay local-from-overlay. Do not run a second water sim on clients.

### Entities, AI, projectiles

| Class | Today | Net |
| --- | --- | --- |
| `EntityManager` | Wildlife/villagers/militia; `max_entities` 128; spawn on `chunk_ready` | Host spawns; replicate pose; do not despawn because one peer unloaded a chunk |
| `WorldEntity` + `EntityBrain.tick(..., player_pos, ...)` | One `get_first_node_in_group("player")` | Pass nearest (or aggro) pawn |
| `CrystalEnemySpawner` / `CrystalEnemy` / `BossBrain` | Same one-player bind; guardians leash to hearts | Host AI; clients interpolate; Origin Warden / Shard Tyrant stay unique (existing `_guarded_spawn_ids`) |
| `Projectile` | Static pool, 32 live, no physics body | Host simulates segment tests; clients spawn a visual-only copy or receive impact RPC. Pool is process-local — fine. |
| `SpatialQueryLayer` | Host combat discovery | Host only. Clients do not need the index for hits. |
| `CombatRewards.grant_player_kill` | Grants to the one player | Grant to the killing peer (or shared pool — product call; default **killer’s inventory**) |

`MultiplayerSpawner` needs real scenes for enemies/wildlife. Today many are built in script via `VoxelPropBuilder`.

### Player state, inventory, relics

One `Player` node is registered as `CompositionRoot.ID_PLAYER`. `export_save_state` is a single dict: voxel_position, health, `StatComponent` bases, `Inventory.to_dict()` (hotbar 8 + bag 24 + `armor_id`), `RelicManager.export_equipped()` (3 slots), hotbar index.

Change:

- Spawn one pawn per peer. Local camera (`player/camera.gd`) and `TargetHighlight` exist only on the local pawn. `WeaponController` reads **that** pawn’s inventory.
- Inventories are **per player**, not shared (assumption: co-op gatherers keep their own bags; world edits consume the acting player’s stone/wood).
- Relic offers (`RelicChoice.roll(seed)` + `RelicChoicePanel`) currently freeze the whole run (`Engine.time_scale = 0.05`, `GameplayInput.pause_open`). In co-op the **host** rolls, the **acting player** (or a vote) chooses, time does **not** scale. Headless already auto-equips the first relic — keep that for dedicated probes.
- `GameManager` win/loss stays session-wide. Player death: v1 **wipe that pawn and spectate or respawn at spawn column**; do not end the run until all pawns are down or coverage/contact rules fire. (Mark: product can instead keep current “any death = loss”; default to **all-down = loss** so co-op is playable.)

### Autoloads and global “one player” state

Autoloads in `project.godot`: `MainThreadFrameProbe`, `CrystalTextureGenerator`, `PerfProfiler`, `FrameBudgetScheduler`, `AudioManager`. Those can stay process-local.

The real one-player assumption is **groups + statics**, not autoloads:

- `get_first_node_in_group("player")` in `ChunkManager`, `GameManager`, `CrystalManager`, `CrystalEnemySpawner`, `WorldEntity`, `BossBrain`, `TerrainEditor`, `SaveGameService`, `LivingWorldDirector`, `game_overlay.gd`, `hotbar.gd`, `inventory_panel.gd`, `camera.gd`, `CombatVisualFeedback`, `VfxPool`, `CombatRewards`, `TopographicalMap`, …
- `WorldState._active`, `WorldBakeService._active`, `WorldSettings._active` — one session per process. OK if each process is one peer.
- `GameplayInput.pause_open` / `world_loading` — process-global action gate.
- `Juice.request_hit_stop` writes `Engine.time_scale`.
- `CrystalCorruption._scars`, `RelicChoicePanel` statics, `FeatureRegistry` derived caches (OK if rebuilt from `WorldState`).
- `PlayerSettings` (`user://player_settings.json`) stays **local** (keybinds, shake, volumes, UI scale).

Add a `PeerSession` (or similar) service: peer_id → pawn, local peer id, host world id. Replace `get_first_node_in_group("player")` with “local pawn” vs “all pawns” vs “nearest pawn” at each call site. `CompositionRoot` already has a typed `ServiceRegistry`; register session there rather than a new autoload if possible.

### Save / load

Host-owned. `SaveGameService.collect_snapshot()` already bundles seed, `world_state`, one `player`, `crystal`, `game` phase/run_state, `town_defense`, `entities`, `crystal_enemies`, optional config. Load pauses stream/sim, applies, single rebuild, resume.

v1: only the host writes `user://saves/world_{id}.json`. Snapshot grows `players: [{ peer_key, steam_id?, export_save_state… }]` and `extensions.authority.mode = "listen_server"`. Clients do not write world files. Steam Cloud is host-only later. Leave World (`main.gd.return_to_world_select`) is a **session teardown** (save then disconnect), not a client-local pause.

### Camera / UI per peer

`Camera3D` (ortho size 24, Q/E yaw) must parent to the **local** pawn. HUD (`ui/game_overlay.gd`, hotbar, inventory, map, objective arrow) binds the local pawn; boss bar / coverage / phase can stay session-wide. `FrontendRoot` / world select: host creates or loads a catalog world (`WorldManager`); clients see a lobby screen, not the single-player catalog.

### Pause, time scale, hit-stop

Cannot pause shared time.

- ESC pause (`ui/pause_menu.gd`: `get_tree().paused = true`) becomes **local UI only** (settings, leave). Optionally host “pause session” later.
- Relic modal must not set `Engine.time_scale = 0.05`.
- Hit-stop (`Juice`: dip to 0.02 for 40–80 ms) becomes a **local** camera/animation freeze. Headless already skips it.
- Tutorial overlay (`TutorialOverlay.should_show`) is local.

### RNG

Host owns gameplay RNG: `CrystalManager._rng`, `TownManager` (`world_seed + 44001`), `RelicChoice.roll`, enemy wander, `EntityManager` wildlife attempts. Visual/content hashes stay as they are (`TerrainRamps`, `CrystalCorruption.ground_variant`). Do not call `randf()` on clients for sim. Seed the host RNG from `world_seed` plus a session salt so two runs of the same world save stay replayable.

---

## 4. Steam

**GodotSteam via GDExtension**, not a custom module build. Official Godot 4.7.1 binaries stay the editor; the extension provides `Steam` and `SteamMultiplayerPeer`. A module rebuild of 4.7.1 is extra CI and blocks editor updates — only consider it if a required Steamworks API is missing from the extension.

Stack:

1. Dev/LAN: `ENetMultiplayerPeer` (two local instances).
2. Steam: same RPCs, swap peer to `SteamMultiplayerPeer`.
3. Lobbies: create/join/invite/overlay. `steam_appid.txt` in the executable directory for dev (Spacewar **480** until the real App ID exists). Never ship a wrong App ID in the Steam build.
4. NAT: Steam Networking Sockets / relays. Do not roll STUN.
5. Testing: Steamworks partner account, two Steam clients (or a second test account), Overlay invite, then a friend across NAT. `godot --headless` dedicated probe stays ENet until a headless Steam client is worth it.

Packaging / licensing (mark for legal review):

- Godot MIT; GodotSteam has its own license; Steamworks requires a partner agreement and the redistributable (`steam_api64.dll` / `libsteam_api.so`).
- Add Linux (and later macOS) export presets; Steam is not Windows-only. Current preset is Windows x86_64, embed_pck.
- Do not put App ID, keys, or `auth.json` in git. Dev `steam_appid.txt` is a known local file.

---

## 5. Phased work

| Phase | Milestone | How to test | Rough effort |
| --- | --- | --- | --- |
| **0 Contract** | `PeerSession`; replace one-player group lookups with local/all/nearest; `authority.mode` in save stub; no sockets yet | Existing `verify_*` suite still green; a unit test that two fake peer ids resolve two pawns | 1–2 weeks |
| **1 Listen hello** | ENet host/client; two instances of `frontend` → lobby → `main`; spawn second pawn; no world sync | Two local Godot instances, `127.0.0.1`; connect, see two bodies, disconnect | 1–2 weeks |
| **2 Movement** | Input RPC + host reconcile + remote interpolation | Two instances walk ramps/caves; desync probe: compare `voxel_position` after 30 s | 2 weeks |
| **3 Overlay edits** | Dig/build/plant/channel/WorldObject deltas + late-join snapshot | Host digs, client sees layer; client digs, host remeshes; third instance late-joins a carved column | 3 weeks |
| **4 Crystal + water** | Host sim, event stream, corruption session-owned | Split players across the map; crystal still grows on host-loaded union; client depth matches host checksum | 3–4 weeks |
| **5 Entities / combat** | Spawner scenes, host AI, projectile RPC, per-peer inventory grants | Two players kite mites; only one Warden; kill credit to the hitter | 3 weeks |
| **6 Run / UI / save** | Shared phase; local pause; relic without time_scale; host save `players[]`; leave = disconnect | Pause on client does not freeze host; host F5 save, both reload | 2 weeks |
| **7 Steam** | GodotSteam, lobby, invite, swap peer | Two Steam clients, invite, play 10 min across NAT | 2–3 weeks |
| **8 Cap & budget** | 3–4 player stream union, frame budget, disconnect | Three local instances; profiler `streaming_budget_us` / crystal tick | 2 weeks |

**Dedicated probe (parallel after phase 1):** `godot --headless` host with no camera, one GUI client. Proves sim-without-local-pawn. Not a ship SKU in v1.

### Main risks

1. **Loaded-chunk crystal policy vs split party.** If the host only sims around its own camera, the remote scout’s front freezes. Union-of-rings is mandatory and can blow the crystal tick budget (`max_new_cells_per_tick`, `flow_budget_us`).
2. **`Engine.time_scale` / `get_tree().paused`.** One leftover hit-stop or relic modal stalls every peer.
3. **One-player group lookups.** Missing a `get_first_node_in_group("player")` site (HUD, VFX cull, vegetation, map) will look like a desync.
4. **Bake / quality divergence.** If a client’s `caves_enabled` or voxel scale differs, floor probes disagree. Pin sim config in the lobby handshake.
5. **Spawner scene debt.** Enemies and wildlife are not packed scenes; `MultiplayerSpawner` will force a spawn-path refactor.
6. **Host disconnect.** v1 session ends. Communicate it in the lobby UI.
7. **Steam overlay + Godot input.** Pause/leave bindings may fight Overlay; test before ship.
8. **Save identity.** `players[]` keyed only by peer_id breaks on reconnect; store Steam ID when Steam is on.

### Effort (rough)

Playable **2-player LAN co-op** (phases 0–6): on the order of **a quarter** for one engineer who already knows this tree, after the single-player slice is stable. **Steam lobby ship** (phase 7–8, 2–4 cap): another **4–8 weeks** including partner testing. This is larger than a feature; it is a networking vertical slice. Do not start it while P0 targeting/collision/crystal-readability work is still open (`QUARTERLY_ROADMAP.md`).

---

## Out of scope (v1)

Host migration, dedicated production servers, rollback netcode for melee, shared inventory, PvP, cross-play with non-Steam, replicating micro grids or GPU meshes, pausing shared simulation for relics.
