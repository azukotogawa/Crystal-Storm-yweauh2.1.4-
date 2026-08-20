# Deferred world bake — implementation report

**Date:** 2026-08-15  
**Architecture:** `startup_bake_architecture.md` (implemented as specified; no redesign)

---

## Files changed

| File | Role |
|---|---|
| `world/world_bake_service.gd` | `_bake_one_chunk`, `package_ready`, prime/fill/on-demand, index commit only at completion, atomic `.chk` write |
| `chunks/chunk_data.gd` | `capture_base_only_snapshot`, `set_worker_feature_tile` (no live WorldState) |
| `chunks/chunk_manager.gd` | Ensure package before stream; 1/frame background fill |
| `world/world_state.gd` | Block `replace_active` while `forbid_session_replace` |
| `systems/frame_budget_scheduler.gd` | `world_bake_fill` (1 unit/frame) |
| `ui/loading_screen.gd` | After fade, keep remaining-bake label |
| `AGENTS.md` | Deferred-fill contract |
| `scripts/verify_deferred_world_bake.gd` | Prime / valid=false / on-demand / rollback env |
| `scripts/verify_bake_one_chunk_parity.gd` | Package byte identity |
| `scripts/display_deferred_bake_boot.gd` | Windowed main-scene boot probe |
| `scripts/run_all_verify.sh` | Register new verifies |

Unchanged: save schema, package binary layout, world size, generation rules, terrain/crystal/water/combat gameplay.

Rollback: `CRYSTALSTORM_BAKE_DEFER_FILL=0` uses the previous `await bake_world_async` path.

---

## Lifecycle before / after

**Before:** `create_chunk_manager_with_services` awaited a full 16,384-chunk `bake_world_async` (and `world.index`) before stream. Cold playable **2,211.6 s**.

**After:**

```
load index → if valid: warm (unchanged)
else:
  inventory existing .chk
  veg scatter (in-memory)
  _bake_one_chunk for start ring + origin 3×3
  start background fill (do not await)
  stream
  INITIAL_STREAM_READY
  1 package/frame until 16384
  then write world.index and set valid=true
```

`valid` stays **false** until every expected package exists.

---

## Measured results

### Cold display (production full map, no index)

Windowed `scenes/main.tscn` via `display_deferred_bake_boot.gd`, D3D12.

| Marker | Result |
|---|---|
| `INITIAL_STREAM_READY` | **33.7 s** (was 2,211.6 s) |
| `valid` at playable | **false** |
| `bake_in_progress` | **true** |
| Packages at playable | **226 / 16,384** |
| Resident chunks | **1** (origin; stream apply) |
| `world.index` | **absent** |
| Starting terrain | Origin surface applied; `column_source` bake/package |
| Dig | **true** |
| On-demand `(40,40)` | **wrote package, valid still false** |
| Files after process exit | **229 `.chk`, no index** |

### Resume after kill (same incomplete dir)

| Marker | Result |
|---|---|
| Playable | **12.3 s** |
| `valid` | **false** |
| Packages | 231 → 233 (no wipe) |
| Index | still absent |

### Warm display (existing complete `world.index`)

| Marker | Result |
|---|---|
| Mode | `loaded` (unchanged path) |
| Playable | **13.0 s** |
| `valid` | **true** |
| Fill | not started |
| Dig | **true** |

### Rollback (`CRYSTALSTORM_BAKE_DEFER_FILL=0`, radius-2)

Composition boot: `bootstrap_for_world_async EXIT mode=baked` then `INITIAL_STREAM_READY`. Full-await path restored for that session.

### Determinism

`verify_bake_one_chunk_parity.gd`: `bake_world` package for `(0,0)` **identical** (22,156 bytes) to `_bake_one_chunk` of the same coord, twice.

### Background completion time

Not waited to 16,384 in this session (would be ~36 min at ~133 ms/chunk). Fill rate is 1 chunk/frame after playable. Completion still writes `world.index` only when `_packages_known.size() == expected`.

### Save / session

- Dig during fill succeeded (WorldState overlay).
- `WorldState.replace_active` during fill is **blocked** (`verify_deferred_world_bake`).
- `SaveGameService` payload unchanged; load still applies overlays then rebuilds. Rebuild uses `package_ready` / on-demand, not a fake valid index.

---

## Invariants

| Requirement | Status |
|---|---|
| A. Cold playable before full bake, no void start | **Pass** (33.7 s, 226 packages, origin meshed, dig ok) |
| B. Move/dig/crystal/water; no WorldState replace | **Pass** (dig, crystal init, replace blocked). Water engine unchanged. |
| C. Far unbaked → `_bake_one_chunk` | **Pass** (`(40,40)` on-demand) |
| D. Kill/restart distinguishable, no wipe | **Pass** (no index, 229–233 files retained) |
| E. Index only at 16,384 | **Pass** (not written at 226/231) |
| F. Warm unchanged | **Pass** (`mode=loaded`, 13 s) |
| G. Rollback env | **Pass** (`mode=baked` on DEFER=0) |
| H. Package byte parity | **Pass** |

---

## Notes

- Prime set is origin 3×3 plus stream rings around the same spawn-column offsets as `Player._resolve_spawn_column` (not only the pre-teleport origin). Cold prime wrote **226** packages (~23 s of the 33.7 s to ready).
- Background fill is main-thread, one chunk per frame, paused when the mesh apply queue is deep or a save transaction is active.
- Full-map fill to `world.index` still takes on the order of the old bake; it no longer blocks play.
