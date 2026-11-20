# Game sounds (Depths)

Files here are named after the game event (`.wav`, `.ogg`, `.mp3` or `.flac`, any sample rate; converted to
48 kHz mono and placed in 3D by the engine). A missing file is **silent** (synthesized stand-ins exist but are
off: `SYNTH_PLACEHOLDERS` in `src/audio.c3`). Restart the application after changing files.

Everything in this folder is generated from `source/` by `python3 tools/prepare-sounds.py` (requires ffmpeg):
it splices, trims, normalizes, fades cut edges and crossfades loops. Edit the splice points there, not the WAVs.
Use `--only flutter_death flutter_click_1 flutter_click_2 flutter_click_3 flutter_flap_loop` to rebuild just the cave-wing sounds without touching other outputs.

| File | Plays when | Source (`source/`) |
|---|---|---|
| `gun_shot_1` … `6` | every machine-gun shot, at the muzzle (random take, never the same twice) | `robot-machine-gun-burst.mp3` (single shots) |
| `missile_launch` | rocket windup + launch: the whoosh is a forced windup, the rocket leaves at the bang (0.43 s into the clip = `ROCKET_WINDUP`); played at 0.8× speed, faster with overclock | `missile-launch.mp3` (0.06–1.0 s) |
| `missile_explosion` | every rocket impact / air burst | `missile-explosion.mp3` |
| `robot_servo_1` … `8` | robot leg joints moving (1–4 small, 5–8 big moves; max 2 at once) | `robot-servo-strokes.mp3` (loud strokes ≥ 30 s) |
| `robot_foot_1` … `8` | each robot foot landing, pitched down | `robot-foot-clinks.mp3` (single casing drops) |
| `enemy_death_splatter` | any creature killed (plus blood spray) | `enemy-death-splatter.mp3` |
| `crawler_walk_loop` | loop on the 2 nearest moving crawlers, by speed | `crawler-walking.mp3` |
| `crawler_attack` | crawler attack | `crawler-attack.mp3` |
| `crawler_roar` | crawler death; the big (boss) crawler's attack | `crawler-roar.mp3` |
| `skitter_crawl_loop_1` … `3` | loop on the 4 nearest moving skitters, by speed | `skitter-crawling.mp3` (three takes) |
| `skitter_hatch_squish` | a skitter hatches from a nest | `skitter-hatch-squish.mp3` |
| `nest_burst_squelch` | nest destroyed | `nest-burst-squelch.mp3` |
| `door_clank` | room gate starts to close / open | `door-metal-clank.mp3` |
| `item_pickup` | item collected (flat, with an on-screen popup) | `item-pickup-chime.mp3` |
| `robot_hit_1` … `6` | the robot takes a hit (random strike; with sparks, red flash, damage number) | `robot-hit-metal.mp3` (single strikes) |
| `flutter_death` | cave-wing killed | `flutter-death.mp3` |
| `flutter_click_1` … `3` | varied idle calls, every 3–9 s per cave-wing | `flutter-clicking.mp3` (three short takes) |
| `flutter_flap_loop` | nearest cave-wings, only during flight; stops on landing | `flutter-flapping.mp3` (0.27–1.9 s, crossfaded) |
| `game_over` | the robot is destroyed (flat, 4× event gain, not placed in 3D) | `game-over-stings.mp3` (first sting, 1.95–5.8 s) |
| `music.ogg` | background music, looped flat and quiet (no reverb) | `background-music.mp3` |
| `menu_music.ogg` | game app main menu music, looped flat (no reverb) | `ominous-music.mp3` |
| `surface_wind_loop` | quiet flat outdoor wind on layer 0; fades/muffles inside side caves, no reverb; absent on −1 | `surface-wind.mp3` (0.7–41.3 s, 2 s crossfade) |
| `portal_idle_loop` | positional hum at an awake rift, ramps with opening; fades out beyond 36 m | `portal-idle.mp3` (2–24 s, 0.8 s crossfade) |
| `teleport` | crossing a rift, flat; cue tail resumes after layer generation instead of restarting | `teleport.mp3` |
| `gravel_step_1` … `6` | natural-ground robot footfalls beneath metal clinks; nearby surface-stalker landings, stronger during charges | `gravel.mp3` (six individual contacts) |
| `shotgun_1` … `3` | shotgun shells (weapon 3), never the same take twice in a row | `shotgun.mp3` = freesound_community "shotgun targetside" (77025), three separate blasts with their own tails |
| `weapon_whir_1` … `3` | weapon fold down / swing up | `printer-servo.mp3` = freesound_community printer/scanner/copier motor servo (30547), short motor whirs |
| `weapon_latch_1` … `3` | weapon latching into place; pitched up for the shotgun pump rack | `printer-servo.mp3`, sharp mechanical clunks |

Event slots without a file (silent for now): `impact_rock`, `impact_flesh`, `footstep`,
`robot_hurt` (replaced by `robot_hit_*`), `ricochet`, `skitter_attack`, `ambience`, `robot_death` (the game over sting covers it).

Keep sounds dry (no baked reverb): the engine adds the room's reverb, distance, direction and occlusion.
The room probe sees real roofs even when they are visually cut away. A legacy walled-in spot open to the
sky falls back to an estimated ceiling, so older scenes still have a useful room sound.

Rebuild just these new effects with `python3 tools/prepare-sounds.py --only surface_wind_loop portal_idle_loop teleport gravel_step_1 gravel_step_2 gravel_step_3 gravel_step_4 gravel_step_5 gravel_step_6` (weapons: `--only shotgun_1 shotgun_2 shotgun_3 weapon_whir_1 weapon_whir_2 weapon_whir_3 weapon_latch_1 weapon_latch_2 weapon_latch_3`).
`--game-test-sounds surface:42` validates file loading, shelter attenuation, loop ownership, gravel contacts,
portal activation/crossing/arrival and layer cleanup with the output muted.

## Original recordings

User-provided downloads (license information was not included), renamed after their use:

| `source/` | Original file |
|---|---|
| `robot-machine-gun-burst.mp3` | `freesound_community-machine-gun-burst-43670.mp3` |
| `missile-launch.mp3` | `universfield-cartoon-explosion-impact-352744.mp3` |
| `missile-explosion.mp3` | `universfield-cartoon-explosion-567193.mp3` |
| `robot-servo-strokes.mp3` | `freesound_community-small-servo-arduino-35614.mp3` |
| `robot-foot-clinks.mp3` | `freesound_community-bullet-casings-33966.mp3` |
| `enemy-death-splatter.mp3` | `universfield-blood-splatter-122253.mp3` |
| `crawler-walking.mp3` | `dragon-studio-giant-spider-walking-504034.mp3` |
| `crawler-attack.mp3` | `yodguard-spider-attack-1-482542.mp3` |
| `crawler-roar.mp3` | `yodguard-giant-insect-monster-580962.mp3` |
| `skitter-crawling.mp3` | `u_xu8o84gxds-small-bug-crawl-sequence-sound-effect_1-449531.mp3` |
| `skitter-hatch-squish.mp3` | `floraphonic-slime-squish-12-219047.mp3` |
| `nest-burst-squelch.mp3` | `universfield-wet-squelch-276679.mp3` |
| `door-metal-clank.mp3` | `freesound_community-metalclank3-89222.mp3` |
| `item-pickup-chime.mp3` | `freesound_community-scale-d6-106129.mp3` |
| `robot-hit-metal.mp3` | `freesound_community-hitting-metal-61071.mp3` |
| `game-over-stings.mp3` | `freesound_community-game-over-sounds-1-14860.mp3` |
| `background-music.mp3` | `echoes_of_lumen-horror-ambient-dark-atmosphere-586983.mp3` |
| `ominous-music.mp3` | `echoes_of_lumen-ominous-music-595730.mp3` |
| `flutter-death.mp3` | `yodguard-small-insect-death-7-580955.mp3` |
| `flutter-clicking.mp3` | `freesound_community-insectoid-monster-clicking-98623.mp3` |
| `flutter-flapping.mp3` | `freesound_community-birds-flapmp3-14504.mp3` |
| `surface-wind.mp3` | `soundreality-wind-blowing-457954.mp3` |
| `portal-idle.mp3` | `freesound_community-portal_idle-34022.mp3` |
| `teleport.mp3` | `freesound_community-teleport-90137.mp3` |
| `gravel.mp3` | `freesound_community-gravel-93504.mp3` |

`yodguard-giant-insect-footsteps-4-482550.mp3` was offered too but is unused (skipped on purpose).
