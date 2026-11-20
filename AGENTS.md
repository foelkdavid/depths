# AGENTS.md — DEPTHS

Notes for coding agents. Humans: see README.md. The engine is `engine/` (vpt-engine submodule, its own
AGENTS.md: read it for engine rules, layout and verification). Working copy of the engine repo: ~/Repos/vpt-engine.

## Repos / remotes

- `engine` submodule url = `git@github.com:foelkdavid/vpt-engine.git` (2026-11-20; engine history restarted at a
  fresh root commit, old local commits are on the engine's local `pre-split-history` branch).
- Depths itself has no remote yet: REMIND the user until they give one (`git remote add origin <url>`).
- Engine change needed? Make it in the engine (generic, via hooks: see engine AGENTS "Rule: engine vs game"),
  commit AND push in ~/Repos/vpt-engine, then here: `git -C engine pull origin main` and commit the submodule
  bump. Never commit a submodule pointer that isn't pushed to the engine remote.
- Reusable mechanics written here (debris, projectiles, hit feedback, third-person camera, minimap/fog, skill tree,
  profiles/bestiary, progression/rifts, generators, creature behaviours) are candidates to promote into the engine.

## Layout

| Path | Role |
|---|---|
| `src/` | game, module `depths`: game.c3 (play loop, combat, creatures), weapons/skills/bestiary/loot/shop, cavegen + surfacegen + surface_caves (generators), depths_world.c3 (scene data + engine hooks + galaxy sky), audio.c3 (sound table on `vpt::audio`) |
| `app/` | game binary (target `depths`): main menu diorama, settings (`~/.config/vpt-game.json`), bestiary UI |
| `dev/editor/main.c3` | target `depths-dev`: `editor::run` with the Depths GamePlugin, New World buttons, CLI tools (tests, `--generate`, `--robot`, `--bench-views`) |
| `dev/tests/` | Depths suites (`--game-test-*`), output to `dev/output/` (gitignored) |
| `dev/generators/` | node asset generators (guarded: `generated-guard.js`, manifests are the hidden `.build-*.manifest.json` in `assets/library/BLACK_START`); `archive/` = old python/js generators, reference only |
| `dev/tools/` | prepare-sounds.py (from `dev/sounds-source`), generate-icons.py, generate-surface-sky.py |
| `dev/notes/` | sounds.md (sound table + provenance), library notes |
| `assets/library/BLACK_START/` | everything the game loads: mechs, creatures (rigs + `parts-*`), `wastes/`, rift, crates, door, console, shop machinery |
| `archive/` | old BLACK_START world (facility kit, corridors, mega structures, rocks, dead trees), style kits, demo scenes (paths rewritten to archive/) |

Runtime paths are relative to the repo root (`assets/...`); the release packs `assets/` only.

## Build & verify

```sh
c3c build depths && c3c build depths-dev
python3 engine/dev/tools/qualify.py depths-dev     # after moving code between modules
./build/depths-dev --game-test-mechs               # also: -bestiary, -layers surface:42 (~8 min), -habitat surface:42,
                                                   # -sounds surface:42, -ai gen:9:detailed, -aim SCENE, -boss-v gen:42:detailed
HOME=$PWD/dev/output/home ./build/depths --run-test   # clean HOME: the user's config has pixelated lighting ON
./build/depths --shot dev/output/menu [--robot K] [--panel start|settings|bestiary] [--slot N --bestiary-entry K] [--shot-orbit DEG D H]
```

Run tests in the foreground with `WAYLAND_DISPLAY=wayland-1 DISPLAY=:0` (hidden-window hang otherwise; see engine AGENTS).
Screenshots for the user go to pCloud `/mnt/Cloud/Transfer/VPT_ENGINE/NNN-topic/` (numbered folders).

## History (pre-split notes, paths as they were then: src/ = now src/ or engine lib; tools/ = dev/tools;
## assets/sounds/source = dev/sounds-source; generators were in assets/library/BLACK_START)

### Status (2026-11-18, Depths game)

- `src/game.c3` (module main): twin-stick shooter inside play mode. Starts when a *hexapod* rig is possessed
  (toggle_play), stops on P/Esc and RESTORES the scene with undo_edit (start took begin_undo). R restarts.
  Editor never runs game code otherwise. Creatures (skitter/crawler/nest by def name) hunt, attack on contact;
  shots are swept pick_scene rays; hits knock back + chip debris; death = `burst_instance` of every rig part
  (real voxel colours, away from the shot); props (non-kit, not flat) have size-based HP and get `hidden[]`.
  Nests release skitters (spawn_rig quick) and burst into 4 on death.
- `src/dynamic.c3` (engine): dyn objects appended after rig parts (GPU order instances, rig parts, dyn), per-object
  colour override (record 7.w = rgb+1, shader `tint`), `pinned_assets` (always in the atlas), `hidden[]` instances,
  `game_lights` (omni, appended in configure_emitters), `blockers` + `blocking_on` (rig wall/gate collision).
  NEVER spawn/remove rigs or edit instances mid-game without `quick`/hidden: scene_revision = full atlas re-upload.
- Scene JSON optional `game` block (rooms kind 0 normal/1 start/2 treasure/3 boss, doors axis+a/b, items).
  `assets/scenes/build-depths.py [--seed N]` writes depths-1 (Isaac-style plan, carved rock rooms, pitch dark).
- `--game-test SCENE`: headless autopilot (20 s) printing kills/debris/stage timings; no pathfinding, so in
  depths it stalls on walls (use open scenes like black-start/alien-swarm to exercise combat).
- Audio (`src/audio.c3`): own mixer in a raylib AudioStream callback (audio thread; main thread only writes voice
  targets). Equal-power pan vs camera facing, distance falloff, head-shadow + terrain-occlusion low-pass, Freeverb
  (8 combs + 4 allpasses, pre-delay) driven by `measure_room()` (24 pick rays every 10 frames). Only real files in
  `assets/sounds/` play (user wants NO synthesized placeholders: `SYNTH_PLACEHOLDERS=false`); originals live in
  `assets/sounds/source/` (renamed by use), splices in `tools/prepare-sounds.py`; table in `assets/sounds/README.md`. Servo voices: max 2 at once, rest between strokes, `reach()` = per-sound falloff. Headless modes never open the device (`audio_allowed`);
  `--game-test-audio` runs the mixer muted. C3 arrays: `float[1800][8]` = 8 buffers of 1800 (reverse of C).
- Modifiers (game.c3 MOD_*, on/off `mods[]`, auto aim cheat): spread, rocket (explode()), vision (draw_vision: projected part
  AABBs + jitter, LOS pick every 4th frame), overclock, pierce, ricochet, nanites, servo (Rig.speed_mul). Pickups list is
  game-side (scene items kind = MOD+1; boss + 25% of cleared rooms drop). F2 cheat menu (cheat_rect blocks firing).
  `--game-test-mods SCENE` = autopilot with every modifier at 2.
- MAX_RIGS 48. Debris: 330 pieces, chips live 3 s, splatter 25 s, crowded 4 m cells fade oldest.

### Status (2026-11-19, procedural caves)

- `src/cavegen.c3`: in-engine port of `build-depths.py` (`generate_depths(seed, detailed)`). Open with
  `--generate [--seed N] [--detailed]` (straight into play), `--scene gen:SEED[:detailed]` / `gen:random`, or the
  New World dialog buttons. In game, R on a generated layer = a NEW layer (`gen_active`). `--game-test gen:42:detailed` works.
- Detailed mode (`bake_cave_detail`): per 4 m block a unique asset - floor slab (0.05 m, 3 layers, -0.03..+0.07),
  rock (0.125 m, 0..4.5 m, terrain rock grown by >= 0.09 m so the 1 m terrain is never visible), or cap over
  untouched rock (4.0..4.5 m). `rock_top()` is shared so blocks join seamlessly; all patterns are world-space.
  The 1 m terrain stays as the collision world. Floors/caps have `Asset.no_pick` (CPU picking skips them).
  ~1200 instances, ~12-13M of the 16.8M atlas. MAX_INSTANCES 2048 / MAX_ASSETS 4096 are CPU-only limits.
- Saved generated scenes skip `gen:` assets and store `generator {seed, detailed}`; load re-bakes the detail.
- `--daylight` (inspection captures) and `--save-to PATH` (headless save + exit) CLI flags.
- Perf: rock blocks are split into 2 m quarters cropped to their rock (rays in rooms skip empty voxel boxes);
  `pick_asset` takes the Asset by pointer (a copy is KBs) and static instance bounds are cached (`cached_bounds`,
  also used by upload_instances). ~1500-1700 instances per detailed layer; MAX_INSTANCES 3072.
- `ground_at` ignores probes that start inside solid (distance <= 0.02) and generated detail (`pick_detail=false`):
  creatures used to ratchet up walls 1.5 m per step onto the rock.
- Destruction (detailed caves only, `blast_terrain` in cavegen.c3): floors (0.0625 m, 7 layers, -0.3..+0.14) get
  craters (bowl + soot + lip), rock parts get gouged and re-skinned (`rock_color`); rock > WALL_DEPTH (0.9 m) from
  open space is bedrock. Collision terrain is never changed. Changed assets go up alone: `refresh_asset_voxels`
  (CPU atlas mirror `atlas_cpu`, `update_rec` on the rows). `terrain_hidden`: detailed caves don't upload the 1 m
  terrain at all (terrainCount 0) - it is only the CPU collision world. Generated assets are never `destructible()`.
- Robot hits: `robot_hit()` (metal strike sounds, sparks, fine chips via burst_instance max_size, vignette, damage numbers).
- Third person: `src/thirdperson.c3`, V in game. Mouse captured (`tp_update_capture` every frame). Rotation is exact
  (never smooth the camera position around the orbit: the robot swims on screen = dizzy); only the follow point is
  smoothed (x/z faster than y), no shake. Spring arm: pull-in instant, growing back smooth. Aim ray from screen centre.
- Props on generated levels get private voxel copies (`make_props_unique`, `Asset.prop_clone`, same path so saves
  are unchanged) and are carved by `blast_terrain` (`carve_prop`); HP-based breaking (damage_prop) still applies.
- Crawlers: `Rig.wall_grip` (set in classify): body-sized collision (0.32 m) to squeeze, `foot_spot` plants steps on
  walls in reach, hunting wall-runner lane ~0.6 m off the nearest wall; game: LOS -> roar + `rush` (speed_mul 1.9).
- Rooms no longer lock and there are no room gates: creatures idle/wander until `aware[]` (LOS within 22 m, < 4 m,
  or shot); crawlers then rush. Killing the big crawler clears the layer.
- Shop (`src/shop.c3`): generator room kind 4 (a dead end) with control-console at the centre + machinery. Its single
  door (bulkhead-door dyn object + blocker) has red/green LEDs; E with a key unlocks (keys: pickup kind KEY_KIND,
  dropped by crawler kills, the last crawler guarantees one), then it auto-opens within 4.5 m. E at the console =
  paused menu (game_dt 0, update_rigs 0) with 3 random unowned mods (or field repair); one choice, then spent.
- Layout is ORGANIC now (`gen_organic` in cavegen.c3): 8-10 blob chambers (stretched/rotated, wobbly rim, pillars),
  spanning tree + <=2 loop tunnels (winding, varying width, squeezes >= 2.1 m), boss = deepest leaf, shop = another
  leaf turned into a square room with a straight axis-aligned corridor + door (the only door). `build-depths.py`
  is the OLD grid layout (depths-1 only). Atlas order in bake: floors+walls, carvable prop copies (smallest first,
  budgeted), roof (0.25/0.5 m), rock tops (graded). MAX_INSTANCES 4096, MAX_ASSETS 6144.
- Cave roof (`Asset.roof`, `bake_roof`, `set_roof_visible` each frame from main): only in third person; domed,
  stalactites, faint glow growths; pickable (camera spring arm), never ground. TP mode adds a lantern game light.
- Ground probes (`ground_at`) include floor slabs (`pick_floor`): rigs walk down into craters. Walls still collide
  on the 1 m terrain. The robot has wall_grip + grip_radius 0.45 (squeezes, braces feet on walls/props).
- Wall gouge radius = 1.2x the blast radius (crater radius); blasts 1-2 m from a wall now bite into it.
- Surface walking (rig.c3): `Rig.oriented/orient/up` (set_surface); rig_to_world/world_to_rig/rig_dir apply it; oriented
  parts send rotation 0 + q=orient*yaw*model. `surface_locomotion` (climbers = crawlers in roofed caves): climb the
  wall in the way, cross the ceiling to the target, drop within 2.5 m; corners/plane via `fitted_normal` (several
  probes - single voxel faces are ledges). Picking returns real face normals now. `world_pick` sees the hidden roof.
  Nests: `attach_nests` after the bake (floor / wall / roof); saved as rigs[].up.
- Roof v2: `roof_under` (domes, lumps, stalactite cones), thin cropped shells per block at 0.125 m (0.25 fallback).
  Atlas order: floors+walls, roof, rock tops, prop copies. Rock tops are hidden while the roof shows (culled).
- UI: Tab = hide editor (`hide_editor`); minimap (`src/minimap.c3`, fog of war, LOS reveal); V swoosh (`swoosh()`,
  cam_blend); V view pitch -0.75..0.85. Caves have sun_power 0 (no sun/moon, no sun shadow rays).
- Roof pieces are 2 m, each cropped to its own height range (`roof_block`, mode 0 all 0.125 / 1 coarse only over
  rock / 2 all 0.25); the status line reports any roof fallback. Lights: at most ONE casting light per rig
  (`configure_emitters` rig_lit) - glowing crawlers had a dozen and every light costs every pixel.
- Skitters are climbers too (wander up walls/roof for climb_stay s, walk back down or drop; hunters drop on you).
  Nests: floor / wall / corner (`corner_nest`, bisector normal) / ceiling.
- CPU picking uses a 4 m instance grid (`pick_grid_refresh`, CSR lists, stamps; objects > 16 cells in pg_big),
  rebuilt on scene_revision / instance_count change. Rays walk cells front to back and stop past the best hit.
- `--detailed` must ALWAYS be detailed: floors + walls bake first (always), rock-top caps last at graded quality
  (`gen_cap_quality`: far caps 0.25 m, then all caps 0.25 m) to fit the measured atlas left. Don't estimate wall
  blocks at full size (they are cropped): that rejected layouts that fit.
- Floor slabs: 0.08 m voxels, 10 layers (-0.63..+0.17): craters up to 0.56 m.
- Bloater (kamikaze): `build-bloater.js` (own guard manifest; never run build-crawlers.js for it). game.c3 kind
  BLOATER: hunts slowly, lights a 0.75 s fuse within 1.9 m (swells, strobes red), dies -> queued `blasts[]` ->
  `bloater_blast` (explode level 3 + up to 38 robot damage within 3.8 m). Chains. Generator wave 4 + some mixed rooms.

### Status (2026-11-19, colony ecology / cave-wings)

- `game.c3` BroodMind (mirrored on swap-removal): position-based nest homes, ambient clustered scuttling,
  pauses, suspicion, initial retreat, nest alarm, pounce cooldown. Distant passive sight does NOT aggro skitters.
  About 80% of initial skitters are probed onto walls/roof; calm residents stay attached 35–75 s.
- Nests hatch independently of awareness, about every 4–6 s (2–4 alarmed), up to five home residents;
  ordinary hatches reserve seven of the 48 rig slots. Destruction frees the nest slot first and releases 5–7
  smaller skitters; damage / visible close danger alarms every skitter. Surface hatches inherit attachment.
- Skitter hops are ballistic (`Rig.airborne/jump_velocity`, gravity, swept collision), RARE (0.08/s while
  eligible, initial 8–20 s delay, 10–20 s cooldown), <=2 m in 3D with <=1.2 m vertical gap. No high-ceiling
  dives or predictive homing. Alerted skitters keep scuttling on surfaces; climb_stay is extended to avoid
  automatic timeout drops. Bites require vertical proximity (no damage through a ceiling).
- Vision class labels come from `vision_class`: flutter and bloater are distinct from crawlers.
- `alien-flutter`: separate guarded generator `build-flutter.js`, 0.78 m wingspan, six legs/four animated wings,
  glow-only eyes. Generated in pairs in alternate non-start/shop/boss rooms. Perches, scuttles, clicks,
  takes short flights, initially flees disturbances, then defends itself; independent of skitter nest alarms.
  `Rig.flying` handles swept flight and tucked feet; anim `wings[]` folds/flaps around model Z.
- Real flutter recordings copied from Downloads to sounds/source; three idle clicks, death, airborne-only
  flapping loop. `prepare-sounds.py --only EVENT...` avoids rebuilding unrelated sounds. Game-over gain 4,
  flat, so death is audible in either camera mode.
- ALL placed static assets (including flat/large/building-kit pieces) have HP and break; only in-memory
  generated cave assets are excluded (carved instead). No old size or kit-role immunity.
- Acceleration cell capacity is now 256 (`COLUMN_OBJECTS`, shader loop must match); rig placement validation
  uses actual 4 m object cells, NOT the obsolete 16 m terrain grid that prevented nest hatching.
- Regression: `--game-test-ai gen:9:detailed` (also seeds 42/58): unaware elevated nest hatches, burst brood,
  colony alarm, calm vs retreat, no ceiling dives, short-hop bounds/landing/cooldown, vision classes,
  idle flight, wing config/audio, placed-prop destruction.
  Ordinary game tests also print hatches, bursts, leaps, surface-skitter frames and cave-wing flights.

### Status (2026-11-19, expedition layers)

- `--generate [--seed N] [--layer 0|-1]` now starts a detailed layer-0 expedition by default; `--coarse` opts out.
  New World buttons: surface expedition / caves only. R = new surface expedition. `surface:SEED` is an editor,
  capture and test scene spec; legacy `gen:SEED[:detailed]` stays the existing cave generator (layer -1).
- Layer 0 is a DIFFERENT field/layout: sunlit ash/salt badlands, striated winding ridges, fine wind ripples,
  fossils/hoodoo/dead scrub/field equipment. Seven jittered stops joined by a guaranteed clear trail. Boundary
  bluffs; three localized roofed side caves, no room gates. Fine 4 m blocks use 0.125 m near flats/routes, graded distant rock.
  `Asset.ground` makes ground probes include surface terrain at any voxel size; coarse terrain stays collision.
- New species: `ash-scavenger` (six-legged plated forager, small local packs, initial retreat, retaliation);
  `dune-stalker` (tall four-legged ridge hunter, visible brace then locked-direction charge; elder scale 1.7
  was the original 75-HP surface boss; NEW surfaces use an alien crawler in one of the side caves instead).
  Independent guarded `build-surface.js` also writes `rift-monument`; never run other generators.
  Existing wastes assets reused; no new fake sound synthesis (existing dry recordings reused).
- `gen_layer` 0/-1. Generator save record `{seed,detailed,version:1,layer}`; missing version = legacy cave.
  Load re-bakes only the appropriate fine terrain; instances/rigs are already saved (never regenerate contents).
- `progression_init` finds the boss/exit and pins rift assets before rendering. `is_layer_boss` handles elder
  stalkers AND cave crawlers. Killing it calls `unlock_layer_exit`, not an immediate win-screen teleport.
  Walk out of activation radius then into the charged rift; fade -> `layer_pending`; apply generation between
  game_update and update_rigs (also in test loop), NEVER inside kill/iteration. Carry hull/mods/keys/aim/god/view.
  Cave rift ends at explicit -2 COMING SOON without generating a nonexistent map. R works from there.
- Rift: dormant basalt monument; manifested arch, counter-rotating ring, three vortex arms, ion motes, floor
  halo, ONE local light. Glow-only `rift-ion` cubes (0.2 glow, not weapon glow 7). Previous particle transforms
  kept by stable index for temporal motion vectors. Spawn inward motes/fade; minimap exit marker/HUD guidance.
  MAX_DYN 640 gives room for the rift + debris + bolts, instead of silently dropping the portal/projectiles.
- Auto-aim now uses four largest posed parts, verifies actual voxel hits/LOS FROM THE NEXT MUZZLE, targets
  their centres, leads by weapon speed (45/22) including ballistic gravity/landing. Re-checks from fired barrel;
  no assisted firing when no valid lock. Geometry tests cover ceilings, walls, nests, flyers and new species.
- Checks: `--game-test-layers surface:42` covers distinct biomes, trail connectivity, save/load, non-boss gate,
  portal geometry, equipment carry, 0 -> -1 -> -2 endpoint and fresh-run restart. Writes `tests/output/rift-{surface,cave}.png`.
  `--game-test-aim SCENE` verifies posed geometry and actual muzzle locks then runs assisted combat.
- `--bench-views gen:42:detailed`: measured 1280x720 top-down 9.3 ms / low-camera no roof 12.4 / roof 19.7,
  at three bounces. V exposes more geometry and closed-ceiling secondary paths; not a CPU AI bottleneck.
  Quality has NOT been silently lowered to hide the difference.

### Status (2026-11-19, surface sky / roofed dens / scarcity)

- Galaxy sky: `assets/skies/ash-waste-galaxy.png`, deterministic 4K equirectangular authoring script
  `tools/generate-surface-sky.py` (numpy/Pillow, no downloaded art). World-direction lookup: no cube seams,
  camera translation/parallax or per-frame noise. Purple/silver dust clouds, stars and ringed moon; layer 0
  ONLY (`galaxySky`, renderer texture lifetime). Diffuse sky fill stays smooth; distance haze keeps direct/
  indirect split consistent. Surface boundary is now irregular/radial instead of four straight walls.
- `surface_caves.c3`: three deterministic roofed side caves, each about 10 m outward from trail stops 2/4/6.
  Rounded chamber + 3.3 m entrance, coarse collision carve under actual solid roofs, fine floor/wall/ceiling
  shells. One salvage, one surface-wildlife, one alien/boss den (seed selects it). Boss = crawler 1.6, two
  nests, skitters and one flutter. Normal outdoor stalkers remain; no elder spawns on new surfaces. Boss
  waits for the player to enter its cave unless shot from outside. Portal manifests inside that chamber.
- Surface detail now replaces GPU coarse terrain too (`terrain_hidden=true`); CPU collision stays. `Asset`
  roof_group 1..3 distinguishes side-cave lids. Outer lids are split/cropped EXACTLY over hollow areas:
  fading whole hillside blocks would expose void/sky around the cave. Floors/walls never fade.
- `set_roof_visible`: special surface branch always retains roofs outside; only the occupied cave fades in
  top-down. Inside requires a root below the ceiling, not just matching x/z (walking ON the roof is outside).
  V restores full roof coverage. `roof_cutaway` travels in metadata record 8.w, stable screen-door primary
  coverage only: shadow/secondary rays stay opaque, so caves don't become sunny courtyards. CPU gameplay
  picking skips a cutaway lid AND the corresponding CPU coarse roof voxels (`surface_cutaway_cave`);
  `shot_pick`/world_pick/camera/audio/creature sight retain real solid roofs. Ordinary layer -1 policy unchanged.
- `loot.c3`, `GameItemFile.contained`: position/path binding to a service crate, no transient IDs in saves.
  Surface has 1 upgrade crate, plus a second on ~22% of seeds, selected among outside/cave containers.
  No loose surface freebies. Damage releases contents once, including rockets; empty crates never roll loot.
  Boss bonus 50%, cave treasure 60%, random room bonus 8% (disabled on surface). Shop unchanged.
- Surface personality: deterministic individual temperament; rest, feeding at fossils/crates, grooming,
  buddy-following, patrol/watch, spacing, initial retreat, cautious flanking, local pack retaliation. Stalkers
  patrol/look out, telegraph a locked charge, then sidestep/recover; alert memory expires after escaping.
- Flutter root cause: every airborne replan used to add 0.8 m. Lift now only happens on take-off. Validated
  perches, 12 m home tether, engine flight bounds/ceiling volume checks, blocked-route feedback and recovery
  of already-escaped states. No silent upward ratchet. Home for flutters is their own spawn, not a distant nest.
- Tests: `--game-test-habitat surface:42` (also 1/2), and `--game-test-habitat gen:58:detailed`: entrances,
  solid ceilings, outside/inside/on-roof/V cutaway policy, loot scarcity/once-only drops, idle activities,
  100 airborne replans + 20 s flight + escaped-state recovery. Screenshots `surface-galaxy.png`,
  `side-cave-{outside,inside-top,v}.png`. Full layer/progression/aim/ecology checks still required.
- Static bounds cache now keys on scene_revision as well as transform values, so recycled asset IDs after
  layer generation/load cannot reuse bounds from an unrelated model.

### Status (2026-11-19, wind / rift / gravel recordings)

- User Downloads copied (not moved) into sounds/source: `surface-wind.mp3`, `portal-idle.mp3`, `teleport.mp3`,
  `gravel.mp3`; provenance in sounds/README. `prepare-sounds.py --only ...` builds crossfaded 38.6 s wind,
  21.2 s rift hum, 1.202 s teleport and six individual gravel contacts, without rewriting other sounds.
- `environment_audio.c3`: one owned flat wind loop on surface, gain 0.26 outside / 0.04 + low-pass inside
  a side cave; no wind reverb, no outdoor wind on -1. Awake rifts have a positional drone (one owned loop),
  ramped with opening, fading beyond 36 m. Negative ownership IDs keep slot reuse safe; reset on stop/restart.
  Fades call spatialize themselves so they still finish after death removes the tracked listener.
- Crossing uses the real teleport cue, not the pickup placeholder. Its actual sample cursor is saved before
  generation and resumed on arrival (short gain ramp), never restarted from the beginning or silently cut.
- Actual robot foot landings layer gravel under existing metal clinks. Natural ground only; no wall/metal
  contacts. 65 ms tripod gate, six non-repeating takes; nearby stalkers also crunch on landings, stronger when
  charging, 160 ms global NPC gate. Phase masks mirror rig swap-removal; variation uses the audio RNG.
- Fixed play_sound's saturated-pool path forgetting `loop=loop` (important when creating ambience in combat).
- `--game-test-sounds surface:42` runs the mixer muted: checks all real files, shelter attenuation, unique
  loop ownership, gravel gait gate, positional portal, crossing/arrival tail, layer cleanup and stop cleanup.

### Status (2026-11-19, open side caves / voxel prop destruction)

- Side-cave mouths were sealed: the fine hill shell (`bake_surface_detail`) was baked over the entrance cut and hung
  below the den roof, although the coarse collision was open. The shell now skips everything below roof+0.3 m in
  any open cave column (whole column over the open cut; flat ground <= 0.45 m stays, the den floor starts there).
  Random props avoid entrance cuts (`surface_cave_open > -2.5`); stop landmarks sit on the side away from caves.
- Generator version 2 (`SURFACE_GEN_VERSION`, saved in generator.version): den mouths turn toward the fixed play
  camera (orbit 0.68) when `surface_cave_spot_ok` allows it (exact hill-height test along the trail with width,
  rim, other stops/dens), otherwise swing up to 180 deg; nothing valid = old outward den. v1 saves keep outward
  dens (`surface_cave_version`). Habitat check: unobstructed rays from the stop at robot height into each den;
  `tests/output/side-cave-mouth.png`, `side-cave-top-{0,1,2}.png` (play camera at each cave stop).
- Props break voxel by voxel, no hit points: bullets `blast_terrain(..., props_only)` a 0.16-0.24 m bite, rockets
  also bite props over 0.55x their blast radius. `settle_props()` (game_post) runs `detach_loose`: voxels with no
  6-connected path to the prop's footing (`Asset.foot`, two lowest placed layers) fall as debris; crates spill
  loot once < 80 % remain; < 2 % left = gone. HP `damage_prop` remains only for props WITHOUT a private copy.
- Atlas is 2048x16384 (`MAX_ATLAS_PIXELS` 32M); terrain/cave quality decisions still use `GEN_ATLAS_BUDGET`
  (16.7M), the rest goes to prop copies (122/122 on surface:42). Asset atlas offsets are 4-aligned (float exact
  past 2^24); terrain lookup stores the chunk SLOT (+1), shader multiplies by 4096.
- Layer 0 loot (supersedes "1 upgrade crate + second on ~22%"): NO scattered crates. Exactly one service-crate in
  the salvage den (cave content 0, always present) holding one modifier. `crate_in_reach` (2.4 m) shows
  "E  open the crate"; `crate_interact` drops the mod at the robot's feet (normal pickup popup). Once only.
- Layer-0 atmosphere: preset = the user's night lighting {210.91, 24.19, 2.92, 0.601, warmth 1, 0.64, exposure 0.602, night}.
  `galaxy_night()` (night + layer 0 + galaxy): moon = slider x GALAXY_MOON (0.22, not the cave-night 0.018) and
  sky fill = slider x GALAXY_FILL (0.6). Diffuse sky light is the galaxy itself (`textureLod` mip 6.5, x25, 70 %
  mixed with the old neutral fill; texture has mipmaps/TRILINEAR, background sky pinned to level 0).
  BUG FIXED: "World grid" replaced every sky miss with flat slate (`showGrid`) -> the galaxy never showed in the
  user's sessions; the grid now yields to galaxySky. Captures `play-top.png` / `play-v.png` render WITH the grid on.

### Status (2026-11-19, weapons / atmosphere)

- Three weapons, keys 1/2/3 (`src/weapons.c3`): 0 MG (as before), 1 rocket launcher (windup/blast as before, always
  carried, level 1), 2 shotgun (`fire_shell`: 9 pellets, 27 with the spread cell; 0.5 dmg, ~0.33 s range, 0.62 s
  cycle). Pellets (`Bolt.pellet`): one tracer cube, NO light, 2 chips, small bites, shared impact sound
  (`pellet_fx`). MAX_BOLTS 96. MOD_ROCKET slot is RETIRED, not deleted (saved item kinds): `mod_available()`
  excludes it from rolls/shop/cheats/pickups (fallback `unowned_mod`).
- Models: `build-hexapod.js` now builds a hinge clevis on the hull (the old baked twin cannon is gone) and the
  attachments `parts-hexapod/weapon-*.vpt.json` + `maintenance-hexapod.weapons.json` (rig-space hinge, each
  piece's local origin = centre-x/min-y/centre-z of its voxels, muzzles). The game poses them from the BODY
  part's live transform (`body_frame`, `body_point`): world(P) = partPos + q*(P - body.shift)*scale.
- Procedural: swap = fold down (cubic, 0.2 s) -> swap -> swing up (easeOutBack 0.34 s, latch clack + kick,
  roll wobble); firing blocked until 85 %. Pitch spring kick, MG alternating barrel recoil, rocket pod lift +
  shudder during windup, shotgun pump rack (two clinks). Weapon pitches the last +-23 deg toward the look point.
  `muzzle(b)` = `weapon_muzzle(b)`: shots/auto-aim/rocket sound come from the real bore.
- Atmosphere (`src/atmosphere.c3`, layer 0 only): 30 wind-driven ash motes around the robot (grow in/out, respawn
  upwind) + 9 faint glowing spores per side-cave mouth (culled > 30 m). Plain dyn cubes, no lights.
- Layer 0 darker: GALAXY_MOON 0.15, GALAXY_FILL 0.42.
- Measured (habitat check prints it): top-down 1280x720 bare 10.8 ms, + weapon/motes/spores 11.8 ms, + repeated
  shotgun bursts 12.3 ms. The aim autopilot reporting 0 kills on surface:42 is pre-existing (no lock in range),
  identical with the legacy muzzles.
- Weapon sounds: real recordings (Downloads copied to sounds/source: shotgun.mp3, printer-servo.mp3): shotgun_1..3, weapon_whir_1..3 (fold), weapon_latch_1..3 (latch + pump rack, pitched up). `take()` = no immediate repeat.
- Mounts (F3, `weapon_toggle_mount`): `maintenance-hexapod.weapons.json` `mounts[]` = under (clevis, folds DOWN,
  fold +1) and top (deck pylon at TOP_HINGE [0,46,10], folds UP/BACK, fold -1); TOP is the default. Mount clevis/
  pylon are attachments now (hull only has a deck plate). Weapons stay authored around the under hinge and are
  translated to the active mount's hinge (`weapon_posed`). F3 = fold away, switch mount, swing up.
- Rockets: `projectile-rocket.vpt.json` voxel round (slim, nose, fins, exhaust glow rule) oriented along velocity
  with roll + 2 flame cubes + its light. ROCKET_SPEED 25 (was 22). Pellets: PELLET_SPEED 80, life ~0.18 s,
  3-cube hot streaks on `pellet_asset` (glow 2.2 keeps colours), ONE light per shell cloud, fire_cool 0.85 s.
- SHADER BUG FIXED: dyn tint decode was `uint(tint-.5)`; above 2^23 floats have no .5 so colours with blue >= 0x80
  rounded up (pale gold -> cyan, old pellets/tracer heads looked blue). Now `uint(tint)-1u`.
- `refresh_asset_voxels` only marks dirty; `draw_scene` uploads each changed asset once per frame.
- Habitat bench now flies pellets like the game. At spawn (heavy view) bare 18.7 ms, +extras 19.0, +shells 20.6.

### Status (2026-11-19, hit feedback / knockback)

- Hit feedback (game.c3 `note_enemy_hit`/`note_enemy_kill`, `enemy_feedback_hud`): struck creatures flash hot white
  (`engine::rig_hit_flash[rig]`, decays 9/s, sent as a NEGATIVE record 7.w on rig parts -> shader blends to white,
  material 4 glow 0.3); health bar above the creature for 3 s after a hit (`hp_max`, drained "lost" chunk);
  damage numbers merged per creature within ~0.35 s (a shell = one number, decimals for pellets), "N  KILL" in
  red on death; X hit marker at the crosshair (V) or hit point (top-down), bigger/red on kills; quiet tick =
  printer latch pitched to ~2.3 (non-spatial, 70 ms gate), kill = latch at 1.45. All mirrored on rig swap-removal.
- Knockback: rocket blast pushes creatures 30*(0.35+0.65k) (was 9k, nests 0); pellet knock x1.6; robot recoil
  rocket 4.5 (was 2.2), shotgun 2.4 (was 1.6). MG shot gain 1.05 (was 0.5).
- No editor selection/hover boxes while playing (`playing` in main.c3 draw).
- Check: `hit_feedback_check` (habitat surface) -> `tests/output/hit-flash-{off,on}.png`, `hit-feedback-hud.png`.
- Known: `--game-test-mods gen:42` reports 1 shot; identical with the old knockback values (not caused by it).

### Status (2026-11-19, L0 wildlife / V camera / surface craters / L-1 tunnels)

- L0 creature motion: `build-surface.js` `animation(legs,speed,stride,o)` takes per-species liveliness (turn rate,
  accel, erratic darts, fast gait + idle leg tapping, head scan/tilt, lean/crouch, twitch, bob). Scavenger is
  skitter-like (turn 720, erratic .85), stalker a heavier predator (turn 420, erratic .4). Regenerated through the
  guard (no hand edits existed). surface_ai idle: faster speed_mul, shorter decisions, fewer rest/groom picks,
  arrived scavengers keep scuttling short darts around their interest ("sniffing").
- Reactions (`surface_disturb`): instant (no random sight gate) on a hit, robot within 3.5 m (stalker 5.5 m),
  firing within 12 m, or a shot landing within 3 m (stalker 4 m, `hit_surface`). Scavenger: startle hop + chitter,
  bold (temperament > .45) or hit -> rush at once (chase speed_mul 1.05+), shy -> bolt then return; pack within
  10 m roused (one level). Stalker: rear back + roar, brace a charge immediately (leap cooldown cleared).
  L-1 creatures untouched. Check: `surface_reaction_check` (habitat surface) prints idle move share/speed.
- Surface craters: layer-0 ground (flats were no_pick 0.125 m blocks, matched neither floor slabs nor rock;
  hills hit the cave "bedrock" test) now uses `crater_surface`: jagged sphere carve + 2-voxel lining below
  each column's original top (the fine ground is a thin shell over nothing). `shot_pick` on layer 0 also
  sees the fine ground (pick_floor), so bullets hit the VISIBLE surface, not the hidden 1 m terrain.
  `surface_crater_check`: 144/147 random shots carve; `tests/output/surface-crater{,-day}.png`.
- V camera: spring arm never shorter than 2 m (TP_MIN_ARM); pull-in smooth. Tracer `camCutExit`: each primary
  ray skips object voxels until it leaves a cylinder (r ~0.95 m, dithered edge) around lens -> robot body,
  stopping 0.25 m short of the robot; the controlled rig's parts (camSkipLo/Hi) are never cut. Creatures near
  that line also get `rig_cutaway` (screen-door, record 8.w of rig parts). Root cause of "unplayable": the boss
  body filled the view and robots shoved into walls put the lens inside the fine rock (black screen).
  `--game-test-boss-v gen:42:detailed` bench + `tests/output/boss-v-{60,150}.png`. Cut cost ~3 ms there.
- L-1 fine rock overhangs the 1 m collision by 0.1-0.6 m (more at the foot), so bodies clipped squeezes:
  tunnel half-width base 1.5-2.0 (was 1.35-1.85), min 1.3 (squeezes >= 2.6 m, was 2.1). New generations only.
- Known: `--game-test` shot counter undercounts since the weapon rework (impacts still happen).

### Status (2026-11-19, skill tree)

- `src/skills.c3` replaces the flat modifiers (`mods[]` is gone; MOD_* kinds only survive as legacy item numbers:
  every non-key pickup is a perk). Per run (R / death resets, carried through the rift via SkillState).
  11 skills / 4 branches: Mobility servo 3 -> dash 1 (Servo 2; SHIFT, 2.2 s cd, i-frames); Firepower overclock 3
  -> multi-gun 2 (2/3 guns) -> pierce 2 / ricochet 1; Hull regen 3 -> armor 3 -> nanites 2; Systems scanner 1
  (draw_vision) -> targeting AI 1 (auto aim + optic laser; the F2 auto-aim cheat still exists: `aim_assist()`).
- XP per kill (`xp_for_kill`; boss 80), level n -> n+1 needs 25+15(n-1); each level = 1 point. Kill text shows
  "+N XP". Crates/drops/boss: `grant_random_perk` = 1 free level in a random node unlockable now (hull repair
  when full). Shop console = skill station: +1 point once, one respec (station flags reset per layer).
- T opens the tree (pauses like the old shop menu; mouse released in V). Icons: `tools/generate-icons.py`
  (PIL, 4x supersampled white glyphs, tinted per branch) -> assets/icons/*.png, sheet in tests/output.
- Robot visuals: build-hexapod.js (guarded) now writes mount yokes `mount-{under,top}-{1,2,3}` (weapons.json
  mounts[].multi: guns = x offsets in m) and `upgrades[]` (armor-1..3, scanner-mast/dish (spins), optic (+laser
  anchor), coolant-cell (drawn 1-3x), thrusters (+flame anchors)). weapons.c3: `gun_count()`, `weapon_posed(f,p,g)`,
  `weapon_muzzle(b,g)`; every gun fires (bolts/shells) from its own muzzle. w_prev slots: 0..35 guns, 36..41 yokes,
  48.. upgrades.
- Checks: `skills_check` (habitat surface): levels, prerequisites, perks only from unlockable nodes, respec, multi-gun
  muzzles; captures skills-robot-{front,back,side,under}.png, skills-menu.png / skills-hud.png (offscreen render
  target: `hud_capture`, screen readback is unreliable headless).
- Shaders are compiled into the binary (`$embed` in renderer.c3, paths relative to src/), loaded with
  load_shader_from_memory: editing a .fs needs a rebuild now. main() switches to the binary's folder when
  assets/ is not in the cwd but next to the binary (models, sounds, sky, icons are still files).
- Single-file release: `c3c build && python3 tools/make-release.py` -> dist/vpt-engine (~74 MB) = binary + appended
  DEFLATE pack of assets/ (no previews/, sounds/source, *.js/*.py/*.vox/*.md). `src/vfs.c3`: trailer "VPTPACK1" at
  the end of /proc/self/exe -> raylib LoadFileData/LoadFileText callbacks serve any "assets/..." path from the pack,
  else disk. Asset existence checks must use `vfs_exists()` (rl::file_exists bypasses the callbacks). Folder
  listings (editor asset browser) still need a real assets/ folder. Linux only (/proc/self/exe).

### Status (2026-11-19, game/editor split + DEPTHS app)

- Two build targets (project.json: shared `src/**`, per-target `sources`): `c3c build vpt-engine` = editor + all
  test modes (editor/**), `c3c build vpt-game` = the game only (app/**, x86cpu baseline for other machines).
  Both define per-target hooks: `after_generated()` (play_generated), `ESC_TARGET` (death hint). `possess_player`
  in game.c3 replaces the editor's select+toggle_play. Editor-only code must never be referenced from src/.
- DEPTHS app: main menu over a live diorama (surface seed 1101; heading picked for an open view + galaxy band
  via the sky PNG and the tracer's equirect mapping; bot faces the camera, is the controlled rig with no input,
  follows the mouse inside its 30 deg aim so it never steps; idle look-around after 5 s; warm key + cool rim
  game lights; motes off in the menu). Start = optional digit seed, always generated + detailed layer 0.
  Settings (~/.config/vpt-game.json, re-applied every frame since generation resets lighting): quality
  LOW/MED/HIGH (0.5/0.75/1), bounces 1-3, pixelated lighting (default OFF), fullscreen (borderless), FPS,
  volume. Esc = pause (resume/settings/main menu/quit); after death Esc = main menu. Menu music
  `menu_music.ogg` (SND_MENU_MUSIC, from the user's "ominous music"), fades out on launch.
- F2 cheats (shared): only "go to layer 0 / -1" (`cheat_layer`, applied in apply_layer_transition, carries
  skills/hull/keys) and +1/+5 skill points.
- UI font bundled: assets/fonts/ui.otf (CodeNewRoman Nerd Font Propo, OFL) so the release looks the same anywhere.
- `./build/vpt-game --run-test` drives the real loop: menu -> run (seed 77) -> F2 layer -1 -> menu.
  `--shot PATH [--panel start|settings]` writes PATH.scene.png + PATH.ui.png (composite them; tests/output/game-menu*.png).
- Release: `c3c build vpt-game && python3 tools/make-release.py` -> dist/depths (single file, ~79 MB).

### Status (2026-11-20, three player mechs)

- The robot no longer swaps weapons (1/2/3 removed in game AND editor play). Three mechs, one weapon each, chosen in the
  DEPTHS main menu (MECH cards; the diorama robot is swapped in place via `engine::rig_set_def`, saved as settings.robot):
  0 HX-6 "Rattler" = maintenance-hexapod (MG, top mount, F3 still works, its skill gear), speed x1.05 in game;
  1 BR-4 "Mortar" = br4-mortar (4 chunky legs, 6-tube launcher on a turret; launch: knock 8.5, nose rears up,
  `heavy_t` bogs speed to 20 % for 0.75 s), anim speed 2.25; 2 CQ-1 "Maul" = cq1-maul (8 short claw legs, raked
  riot shield with red eye slits, double barrel through the port, barrels alternate), anim speed 4.5.
- Engine: `ROBOT_RIGS[]` / `player_robot` (surfacegen.c3) decide what surface/cave generation spawns. game: `ROBOT_*`
  tables + `robot_of()` in weapons.c3, `is_player_rig` = any of the three. `weapons_load` reads `<rig>.weapons.json`
  for the player's def (weapons by name, 1-2 mounts, up to 6 muzzles, no upgrades = no skill gear drawn).
- Models: `build-mechs.js` (own guard manifest, writes parts-mortar/, parts-maul/, both rigs/anims/materials/weapons/vox
  + catalog entries). Never run build-hexapod.js for them. MAX_RIG_DEFS 16 (storage stages defs on the heap now).
- Checks: `--game-test-mechs` (spawn, weapon, muzzles, Mortar recoil, speed ranking; mech-{0,1,2}-fire.png).
  `vpt-game --robot K` (shots/tests), `--shot-orbit DEG [DIST HEIGHT]` turntable of the menu mech, `--run-test`
  asserts the chosen mech survives the layer jump. The run test's "pixelated lighting off" assert reads the real
  ~/.config/vpt-game.json; run it with a clean HOME.

### Status (2026-11-20, bestiary + save slots)

- `src/bestiary.c3`: 9 species (`SPECIES[]`, ids stored by index in saves: only APPEND), `species_of(r)` (kind + scale>1.3
  brood crawler + "spire" nests). Hooks: `kill_rig` -> `bestiary_kill` (per species and per mech, first kill = popup
  "NEW BESTIARY ENTRY" + immediate save), `robot_hit(..., species)` -> `last_hit_species`, `die` -> deaths/killed_you,
  `play_generated(layer 0)` -> runs, `bestiary_tick` (play time, deepest layer, 20 s autosave), `game_stop` flushes.
- Profiles = 3 slots, `~/.local/share/depths/slot-N.json` (tmp file + rename). Written ONLY when `save_slot >= 0`; the game
  app selects settings.slot at startup. Editor, all test modes, `--shot` and `--run-test` never write (except `--slot N`).
- App: main menu BESTIARY button (n/9 found) + slot summary line; START panel has the SAVE SLOT picker; bestiary panel
  (`app/bestiary_ui.c3`): list, turning raster portrait of the static proxy (black silhouette until killed), threat/HP,
  kills per mech, killed-you, first-kill date, lore, profile totals, slot tabs, ERASE SLOT (click twice).
  Portrait renders offscreen BEFORE begin_drawing (`bestiary_prepare`). Shots: `--panel bestiary --slot N --bestiary-entry K`.
- Check: `--game-test-bestiary` (HOME redirected to tests/output/save-home).
