# Crystal Storm — Questions (gap log)

Agents: when a task needs a design answer you cannot find in `studio/DECISIONS.md`, the code or `studio/NOW.md`, append one line here and carry on with the safest reading. Do not guess a decision into the code.

Format: `- Q-NNN | YYYY-MM-DD | task | [topic] question | answer: (blank until Cole answers)`

Cole answers inline. Once answered, the decision moves to `studio/DECISIONS.md` with a new D-ID, and the question line gets `-> D-NNN`.

## Open

- Q-001 | 2026-10-14 | ledger import | [crystal] Which crystal behaviors should be implemented first: surface growth, cavity invasion, material conversion, gap bridging, climbing, branching, or pressure accumulation? | answer:
- Q-002 | 2026-10-14 | ledger import | [crystal] What exact materials resist, slow, redirect, or accelerate crystal? | answer:
- Q-003 | 2026-10-14 | ledger import | [crystal] Does crystal permanently convert terrain, temporarily coat it, or support both behaviors? | answer:
- Q-004 | 2026-10-14 | ledger import | [crystal] How should crystal propagation interact with chunk boundaries and unloaded regions? | answer:
- Q-005 | 2026-10-14 | ledger import | [voxels] Is the current macro-heightfield plus sparse micro-brick architecture sufficient for the long-term 3D voxel vision? | answer: macro/micro rejected 2026-10-14 -> D-222
- Q-006 | 2026-10-14 | ledger import | [voxels] What is the final macro-to-micro voxel size ratio? | answer: macro/micro rejected 2026-10-14 -> D-222
- Q-007 | 2026-10-14 | ledger import | [voxels] Which construction types are essential for the next playable milestone? | answer:
- Q-008 | 2026-10-14 | ledger import | [voxels] Should structural collapse be a core mechanic or remain out of scope? | answer:
- Q-009 | 2026-10-14 | ledger import | [water] Is free-flowing water visibly simulated throughout the world, or are some areas still represented only by atlas terrain tiles? | answer:
- Q-010 | 2026-10-14 | ledger import | [water] What is the intended rule for water level, cavity fill, overflow, and flow around obstacles? | answer:
- Q-011 | 2026-10-14 | ledger import | [combat] What is the final intended combat reward loop? | answer:
- Q-012 | 2026-10-14 | ledger import | [combat] What boss phases, attack patterns, and arena changes are required? | answer:
- Q-013 | 2026-10-14 | ledger import | [enemies] Should animals be huntable, tameable, harvestable, or remain environmental actors? | answer:
- Q-014 | 2026-10-14 | ledger import | [enemies] What should drive enemy composition and escalation after all absorption unlocks have been reached? | answer:
- Q-015 | 2026-10-14 | ledger import | [world] What are the final map dimensions, biome count, and terrain-feature frequencies? | answer:
- Q-016 | 2026-10-14 | ledger import | [world] Are caves/dungeons required in the current milestone, given that `MESH_CAVES` was recorded as off in an earlier inspection? | answer:
- Q-017 | 2026-10-14 | ledger import | [towns] Are town counts fixed at two small towns and one large port? | answer:
- Q-018 | 2026-10-14 | ledger import | [towns] Should towns provide trade, repairs, quests, crafting, relics, or other player rewards? | answer:
- Q-019 | 2026-10-14 | ledger import | [progression] Does the explicit no-meta-progression decision from July remain final? | answer:
- Q-020 | 2026-10-14 | ledger import | [progression] Should relics be earned through spawn destruction, exploration, combat, or another system? | answer:
- Q-021 | 2026-10-14 | ledger import | [progression] Should tools and weapons have upgrade tiers? | answer:
- Q-022 | 2026-10-14 | ledger import | [progression] Should the maze/assault loop include explicit waves, intermissions, rewards, and rebuilding windows? | answer:
- Q-023 | 2026-10-14 | ledger import | [art] What exact art direction and crystal silhouette/palette should be signed off for M4? | answer:
- Q-024 | 2026-10-14 | ledger import | [UI] Which diagnostic overlays belong in normal gameplay? | answer:
- Q-025 | 2026-10-14 | ledger import | [tech] What are the current live results of the full verification suite and the remaining manual camera/player checks? | answer:
- Q-026 | 2026-10-14 | ledger import | [tech] Which items in this historical ledger have been superseded by changes after their recorded dates? | answer:
- Q-027 | 2026-10-14 | design pivot | [progression] Loss conditions with one crystal: which apply? Options: (a) player death (permadeath roguelike run end, or team wipe in co-op); (b) crystal coverage passes a threshold (current max_crystal_coverage 0.72) and the world is overrun; (c) the crystal reaches/consumes a protected place (base camp, town or the treasure site); (d) a storm timer: the crystal finishes charging after N days/phases | answer: death only (option A), Cole 2026-10-14 -> D-232
- Q-028 | 2026-10-14 | design pivot | [combat] At what crystal health does the boss mob spawn (e.g. 25 % left), is it one boss or a wave with it, and can the crystal still be damaged while the boss lives? | answer: 25% (BOSS_SPAWN_HEALTH_RATIO), one boss spawned once near the crystal, crystal stays damageable. Boss death is a stat/reward, not the win. Pivot step 5, 2026-10-15.
- Q-029 | 2026-10-14 | design pivot | [crystal] Where does the single crystal start (map center, the treasure site, a seeded corner like the old origin) and does it move, grow or relocate? | answer:
- Q-030 | 2026-10-14 | design pivot | [art] Voxel model resolution for characters and creatures (voxels per world block, e.g. 8 or 16 per block) and whether models are authored in a tool (MagicaVoxel .vox) or generated from code | answer:
- Q-031 | 2026-10-14 | design pivot | [progression] XP sources (kills, crystal damage, mining, building, exploring) and whether levels persist between runs (D-158 said no meta-progression) | answer:
- Q-032 | 2026-10-14 | design pivot | [voxels] Which multi-block break shapes per tool tier, and which large structures come first (wall segments, gates, towers, stairs)? | answer:
