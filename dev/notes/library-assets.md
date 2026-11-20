# BLACK START — asset library

45 static voxel assets (16 small props/characters, 7 facility-scale pieces,
14 planet scenery variations, and 8 clean corridor pieces),
authored and exported with Goxel's JavaScript API.
Industrial charcoal steel, worn yellow safety paint, rust, cool blue power cells,
and violet/mint crystalline organisms. No engine source or neighbouring assets changed.

## Browse

- [Contact sheet](previews/contact-sheet.png): all 45 models, software isometric views.
- [Planet scenery](previews/planet-scenery-contact-sheet.png) · [Planet render](previews/planet-showcase.png).
- [Clean corridors](previews/clean-corridors-contact-sheet.png) · [Corridor render](previews/clean-corridors-showcase.png).
- `previews/expansion/*.png`: 22 individual clean engine renders of the newest assets.
- [Megastructures](previews/megastructures-contact-sheet.png): the seven huge additions.
- [Facility screenshot](previews/facility-showcase.png): the complete industrial yard.
- `previews/scale-comparisons/*.png`: actual engine screenshots with the original robot at scale 1.
- [Engine screenshot](previews/engine-showcase.png): actual path-traced showcase.
- `*.vpt.json`: engine-ready assets, correct physical scale and emissive flags.
- `vox/*.vox`: editable Goxel/MagicaVoxel volumes. Open with `goxel vox/maintenance-hexapod.vox`.
- `catalog.json`: dimensions, occupied voxel counts and descriptions.
- `showcase.vptscene.json`: original small-prop demonstration (not the complete library).
- `planet.vptscene.json` / `clean-corridors.vptscene.json`: latest assembled environments.

### Desolate-planet set (`wastes/`, `node build-wastes.js`)

28 static assets on the same organic toolkit (`voxkit.js`): thorn bushes (3), bristle shrubs (2), tendril
weed, spore stalks, bulb fungi (2), crystal shrub, coral fan, root tangle, pod succulent, tumbleweed, husk
tree; fossils (giant ribcage, horned skull); rocks (pitted boulders, shale shards, hoodoo); and 5 cm ground
cover tiles (cracked crust x2, gravel, ash ripples, fissure, impact crater, salt crust) to scatter over dark
regolith terrain. Glow in this set never casts light (bioluminescent glimmer only). Thin plants: use Wind.
Scenes: `assets/scenes/build-wasteland.py` → `wasteland-lineup` (daylight) and `wasteland-night` (pitch black).

Generated robot/creature files (`build-hexapod.js`, `build-crawlers.js`, run with node) are protected:
if you changed any of their outputs (e.g. glow rules in the editor), the scripts stop and list the files
instead of overwriting them. `--force` backs your versions up to `.generator-backups/` first.

| Asset | Details |
|---|---|
| maintenance-hexapod | MH-6 industrial hexapod (0.02 m voxels, 1.84 m wide): 18 servo joints, safety-yellow armour, caged blue cell, spinning lidar, twin headlamps, status LEDs, whip antenna. Built by `node build-hexapod.js`, not Goxel |
| alien-crawler | Rig, 2.5 m: ten spider-high legs, crystal spine, scorpion tail + venom sac, hook mandibles, eight eyes. Hectic. `node build-crawlers.js` |
| alien-nest | Rig, 2 m: breathing egg sacs (fleshy membrane, glass windows, curled glowing embryos) on a wet goo mound; 7 strands stick to walls/corners/neighbouring nests. Varies per placement. `node build-crawlers.js` |
| alien-nest-spire | Rig, 1.1 m tall: stacked egg sacs; strands incl. one probing for the ceiling. Good in corners |
| alien-skitter | Rig, 0.5 m: eight needle legs, vein-lit abdomen, red eye cluster, twitching fangs. Hectic. `node build-crawlers.js` |
| alien-leecher | Four hooked legs, twin siphons, charged dorsal crystals |
| diesel-tank | ~5.65 m reservoir, circular ends, bands, saddle supports, ladder, fill hatch, drain |
| pipe-straight | 4 m straight run, hollow bore, flanges, supports |
| pipe-elbow | Hollow 90-degree corner |
| pipe-tee | Hollow three-way junction |
| wall-panel | 4 m × 3.2 m steel module, ribs, vent, kickplate |
| bulkhead-door | Closed split door, blue windows, warning stripes, access reader |
| corridor-floor | 4 m square deck with raised tread and safety edges |
| control-console | Screen, keyboard, status lights, emergency stop |
| diesel-generator | 3 m skid, cooling grille, end guards, exhaust, indicators |
| service-crate | Reinforced supply crate, yellow lid, latches and handle |

## Scale and placement

Characters: **0.025 m/voxel**. Small environment: **0.05 m/voxel**.
Megastructures: **0.25 m/voxel**; hollow structural shells keep occupancy modest.
These are purpose-built large models, not scaled-up small props.
All models satisfy the engine's 128-voxel axis and 2M dense-voxel limits.
Sources are Z-up; the character front is -Y. The engine converts this to Y-up,
front +Z, centres the occupied horizontal bounds, and grounds the model at Y=0.
Asymmetric fittings therefore have bounds-centred, not connector-centred pivots.
The deck is 0.3 m tall including tread: place objects on it at Y=0.3.

VOX stores colours but not this engine's metre scale or per-voxel emissive flags.
Use the root JSON assets in VPT, not the VOX copies, for matching scale and lighting.
Lights are static emissive voxels; blinking LEDs, animation, door opening, collision
and gameplay behaviours are not implemented in these assets. These are static
voxel models, not rigged characters.

From the engine repository root:

```sh
./build/vpt-engine --assets assets/library/BLACK_START
./build/vpt-engine --scene assets/library/BLACK_START/showcase.vptscene.json
```

## Facility-scale additions

The robot is 0.925 m tall including its antenna. All dimensions below are at
placement scale **1**, including in `facility.vptscene.json` and the comparison scenes.

| Asset | Physical size / scale cues |
|---|---|
| mega-reactor-tower | 29.75 m tall; pressure chamber, cooling risers, balcony, ladder, small access door |
| mega-turbine | 30 m long; massive ribbed barrel, roof walk, inspection doors, exhaust stack |
| mega-blast-gate | 30 m wide × 25.25 m tall; open ~20 m aperture, hydraulic rams, service doorway, upper walkway |
| mega-cooling-tower | 30 m tall; hyperboloid shell, open throat, intake piers, rim rail and ladder |
| mega-pipe-bridge | 30 m span × 17 m tall; two overhead mains, lattice trusses, four supports, access ladder |
| mega-storage-silo | 31.25 m tall; banded vessel, domed roof, upper catwalk, fill riser and service door |
| mega-foundation | 24 m square × 1 m tall; heavy deck plates, expansion joints, anchors and hazard edges |

The **128 m facility scene** assembles 20 foundation tiles, paired silos and cooling
towers, reactor, turbine, bridge, and huge entrance gate. Small terminals, a diesel
set, and the unchanged player establish scale. Structural models sit at Y=1 on
the foundation; do not enlarge the robot to match them.

```sh
# Run from the engine repository root:
./build/vpt-engine --scene assets/library/BLACK_START/facility.vptscene.json
./build/vpt-engine --scene assets/library/BLACK_START/scale-scenes/mega-blast-gate.vptscene.json
```

The comparison scenes put the original robot and a small terminal beside each new
asset. PNG screenshots are also copied to
`/mnt/Cloud/Transfer/BLACK_START/asset_previews/`.

## Desolate planet and quiet corridors

The expansion adds **14 scenery variations** without random per-voxel colour noise:

- Rocks: `rock-boulder-low`, `rock-boulder-split`, `rock-boulder-upright`,
  `rock-layered-outcrop`, `rock-spire-cluster`, `rock-natural-arch`, `rock-scree-patch`.
  Rounded volumes intersect tilted fracture planes; subdued broad strata and broken
  silhouettes provide detail. Formations reach roughly 24 m tall, alongside smaller
  boulders and a scatter of fifteen stones. Voxel sizes: 0.1 / 0.2 / 0.25 m.
- Dead plants: `dead-tree-crooked`, `dead-tree-forked`, `dead-tree-fallen`,
  `dead-stump-hollow`, `dead-scrub-spreading`, `dead-scrub-upright`, `dead-agave`.
  Tapered branches, pale broken wood, hollow stump, thorn scrub and dried drooping
  blades; no living foliage. Voxel sizes: 0.05 / 0.075 m.

The **8 `corridor-clean-*` pieces** are `floor`, `wall`, `window`, `doorway`,
`straight`, `corner`, `junction`, and `ceiling`. They deliberately replace the dense
visual language of the original kit with four broad deck panels, large flat wall
insets, a single wall seam, wide observation windows and sparse amber markings.
**No stochastic rust, voxel speckling, or repeated tiny tread/vent details.** The
original weathered models are preserved rather than silently overwritten.

All corridor pieces use **0.05 m voxels**. Floor/prefab footprints are exactly
**4 × 4 m**; the floor surface is at **Y=0.3 m**. Standalone walls are 3.2 m tall
and should be placed at Y=0.3 on the floor. Open-top straight/corner/junction
prefabs include their floor and walls and are **3.5 m tall overall**. Do not stack
another floor under them. Place the optional ceiling at Y=3.5; its lights face down.
Standalone walls and portal frames use bounds-centred thickness pivots; prefab
outer edges remain on the 4 m footprint. The window colour uses the existing glass rule.

`planet.vptscene.json` includes every new scenery model, deterministic scatter,
a flat regolith surface and a distant cooling tower. `clean-corridors.vptscene.json`
shows an open-sided service bay connected to a corridor loop. Both include the
original robot for scale. `expansion-scenes/` contains one capture scene per new asset.

```sh
# From the engine repository root:
./build/vpt-engine --scene assets/library/BLACK_START/planet.vptscene.json
./build/vpt-engine --scene assets/library/BLACK_START/clean-corridors.vptscene.json
```

Screenshots and contact sheets are also copied to
`/mnt/Cloud/Transfer/BLACK_START/asset_previews/`.

## Rebuild and validate

From this directory (Goxel 0.15.1; Python with Pillow for previews):

```sh
mkdir -p vox
goxel --script=build-assets.js
python3 build-facility.py
goxel --script=build-scenery.js
python3 build-planet.py
python3 preview-assets.py
```

The generator overwrites both the JSON and VOX models: preserve manual edits before
running it again. Goxel runs the modelling script and writes each native VOX export;
the same voxel coordinates are written as JSON with scale/emission metadata.
The preview script checks JSON structure, bounds, uniqueness, engine allocation
budgets, and matching voxel counts in Goxel's VOX files.

Verified: all 45 JSON/VOX pairs pass validation. Captured all 22 new assets in the
engine, including their assembled planet and corridor scenes. Inspected the contact
sheets, assembled scenes, boulder and scrub captures. Shaders validate, `c3c build`,
`--check` (ALL VPT ENGINE CHECKS PASSED), and `--bench-small --size 512` pass.
Planet captures include sparse regolith chunks; corridor/facility scenes are instance-only.

## Industrial scene, glass and lights (2026-11-18)

`industrial.vptscene.json` (built by `build-industrial.py`) is a small dark equipment bay on
regolith at night: deck floor, glazed walls, the sealed bulkhead door, tank, generator with a
feeding leecher, consoles, crates, the robot and a lurking crawler, work lamps, red beacons, and
the cooling tower and silo looming outside. Renders: `renders/*.png` (full resolution in
`/mnt/Cloud/Transfer/BLACK_START/industrial_scene/`).

```sh
./build/vpt-engine --scene assets/library/BLACK_START/industrial.vptscene.json
# clean render: no UI, custom camera
./build/vpt-engine --scene assets/library/BLACK_START/industrial.vptscene.json --capture --clean \
  --frames 90 --orbit 0.55 --tilt 0.5 --focus 0 1 -1 --zoom 13 --out overview.png
```

`kit.json` in this folder makes the engine's Room (8) / Wall (9) tools build with this kit
(4 m modules: corridor-floor, wall-panel, wall-window, bulkhead-door, doorway, corner-post).

New/changed assets (in `build-assets.js`):

| Asset | Notes |
|---|---|
| bulkhead-door | windows are now cut through the leaves with a glass pane (was emissive blue) |
| wall-window | wall module with a glazed viewing band and mullions |
| work-lamp | standing floodlight, warm bulb behind a glass lens, wire cage |
| beacon | red emergency light under a glass dome |
| doorway | open 2.4 m passage in a 4 m wall module, hazard-striped frame (room tool default door) |
| corner-post | 0.8 m column covering room corners |

Glass is the plain colour `C.glass` = `150,196,214`; `put()` skips wear noise for it so the
colour stays exact. **`materials.json` in this folder** turns it into glass (tint 0.35) and sets
glow strengths / cast-light colours for the kit's emissive colours (lamp `255,206,140`, white
`235,230,193`, blue `38,161,233`, ice `123,227,255`, red `240,64,36`, green `91,212,146`,
mint `89,213,187`). Edit it in the engine (asset → Materials) or by hand; see
`docs/MATERIALS.md` in the engine repo.
