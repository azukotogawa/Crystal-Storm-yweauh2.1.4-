# Living World Report — Production Phase 1

**Date:** 2026-07-17  
**Milestone:** Living World (steppe, temperate forest, ruins, towns, wildlife, villagers)  
**Goal:** A believable world worth defending  
**Engine:** Engine 1.0 frozen (no WorldState / Chunk Pipeline / Save / Composition Root / Spatial Query / Crystal Sim redesign)

## What the player experiences

| Content | In-run presence |
|---|---|
| **Steppe** | Distinct biome regions; HUD phase line shows `Biome: Steppe` while exploring |
| **Temperate forest** | Forest / dense forest / pine variants; wildlife lean deer/boar |
| **Ruins** | 6 deterministic ruins (48–280 columns from origin); discovery toast + crystal power stir |
| **Towns** | 3 settlements + port; site tests use voxel-scale surface heights; plaza villagers + standing militia |
| **Wildlife** | ~150 animal spawn entries (steppe rabbits/birds, forest deer/boar) |
| **Villagers** | `town_villager` agents in towns; militia reinforce on ALERT/BESIEGED |

## Surprise beat

**“I discovered a forgotten ruin — and the crystal stirred.”**  
Approaching a ruin triggers `LivingWorldDirector` discovery: overlay toast, console beat, and **+6 crystal power** (forbidden lore feeds the crystal). Exploring ruins is a double-edged decision, not pure loot.

Secondary beat: **“The town called militia!”** when crystal pressure raises town ALERT/BESIEGED.

## Slice checklist

| Pillar | Status |
|---|---|
| Exploration | Steppe + forest legible via biome HUD; denser ruins/towns |
| Combat | Standing militia + wildlife; existing weapons/relics |
| Crystal interaction | Ruin discovery feeds crystal; towns react under pressure |
| Loot / progression | Crystal power tier continues; militia/villager feed on death |
| UI | Biome on phase line; living-world toasts |
| Verification | `scripts/verify_living_world.gd` in suite |
| Placeholders | Procedural biome/agents; villager uses passive herbivore brain |
| Balance | Towns prefer steppe/forest/plains; ruin power bonus = 6 |

## Engine hooks (content only)

| System | Use |
|---|---|
| FeatureRegistry / WorldState | Towns, ruins, wildlife spawns |
| Composition Root | Unchanged boot; `LivingWorldDirector` under WorldFeatures |
| Crystal | `grant_feed_power` on ruin discovery; town defense depth queries |
| Spatial Query | Entities index via existing spawn path |
| Save | Town defense export/import; features via WorldState |

## Files

- `world/town_manager.gd` — scale-correct site tests; prefer steppe/forest/plains  
- `world/ruin_manager.gd` — denser ruins; named stamps  
- `world/living_world_director.gd` — biome poll, ruin discovery, militia signals  
- `entities/entity_manager.gd` — wildlife density; villagers + standing militia  
- `entities/entity_brain_registry.gd` — `town_villager`  
- `ui/game_overlay.gd` — biome HUD + living-world toasts  
- `scenes/main.tscn` — LivingWorldDirector node  
- `scripts/verify_living_world.gd`  
- `scripts/run_display_session.sh` — 150s timeout for denser boot  

## Verification

```
All living world tests OK
# Display probe (with Living World density):
DISPLAY SESSION OK
```

Run:

```bash
godot --headless -s scripts/verify_living_world.gd
bash scripts/run_all_verify.sh
godot scenes/main.tscn   # human: walk biomes, find ruin, visit town
```

## Stream reliability (Living World fix)

- Town villagers/militia re-seed on `chunk_ready` via `ensure_town_population`.  
- `_defenders_by_town` decrements on despawn/death and reconciles from live agents.  
- Ruin discovery uses shared `discover_ruin_at` / `try_discover_at_player_column`; harness warps player and drives the real proximity path.

## Residual content debt

- Villagers use passive herbivore brain (placeholder AI), not dialogue NPCs.  
- Biome art still procedural/placeholder.  
- Forest can be far from spawn depending on seed Voronoi layout.  
- Town fall narrative could be richer (evacuation events).  
- Display probe disables crystal DoT so QA dig path stays reliable near origin.

## Design question (≤2 min)

**When crystal first touches a town’s outskirts, should the surprise priority be:**

**A)** Militia rush (more fighters, loud toast)  
**B)** Villagers flee toward the player’s maze (evacuation path)  
**C)** Town roots/fields briefly slow crystal (living defense)  
**D)** Something else (specify)
