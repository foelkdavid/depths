#!/usr/bin/env python3
"""Rebuild the game sounds in assets/sounds/ from the original recordings in dev/sounds-source/
(requires ffmpeg). Output names are the event names the game registers (see dev/notes/sounds.md)."""
import argparse
import array
from pathlib import Path
import subprocess
import sys
import wave

repo = Path(__file__).resolve().parents[2]
root = repo / 'assets' / 'sounds'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', nargs='?', type=Path, default=repo / 'dev' / 'sounds-source')
parser.add_argument('--only', nargs='+', help='Rebuild only these event names (leave other sounds untouched)')
args = parser.parse_args()
out = root
for old in out.glob('*.wav'):
    if not args.only or old.stem in args.only:
        old.unlink()   # names change over time: never leave a stale sound behind


def decode(source, start, end, filt):
    cmd = ['ffmpeg', '-v', 'error', '-i', str(args.source / source), '-ss', str(start)]
    if end is not None:
        cmd += ['-t', str(end - start)]
    cmd += ['-af', filt, '-ar', '48000', '-ac', '1', '-f', 'f32le', '-']
    samples = array.array('f', subprocess.check_output(cmd))
    if sys.byteorder != 'little':
        samples.byteswap()
    return samples


def write(name, samples, peak):
    gain = peak / max(abs(x) for x in samples)
    pcm = array.array('h', (int(x * gain * 32767) for x in samples))
    if sys.byteorder != 'little':
        pcm.byteswap()
    with wave.open(str(out / (name + '.wav')), 'wb') as w:
        w.setparams((1, 2, 48000, 0, 'NONE', 'not compressed'))
        w.writeframes(pcm.tobytes())


def export(source, name, start=0, end=None, short=False, peak=None, fade=None):
    """One-shot: trims outside silence (keeps inner pauses), fades the cut edges."""
    if args.only and name not in args.only:
        return
    samples = decode(source, start, end, 'highpass=f=100,lowpass=f=11000' if short else 'highpass=f=30')
    threshold = max(abs(x) for x in samples) * (0.015 if short else 0.002)
    first = next(i for i, x in enumerate(samples) if abs(x) > threshold)
    last = len(samples) - next(i for i, x in enumerate(reversed(samples)) if abs(x) > threshold)
    samples = samples[max(0, first - 240):min(len(samples), last + 480)]
    fade_in, fade_out = 144, int(fade * 48000) if fade else 480 if short else 960
    n = len(samples)
    samples = array.array('f', (x * min(1, i / fade_in, (n - 1 - i) / fade_out) for i, x in enumerate(samples)))
    write(name, samples, peak or (0.65 if short else 0.85))
    print(f'{name}: {n / 48000:.3f}s ({source}, {start}..{end})')


def export_loop(source, name, start, end, xfade=0.25):
    """Seamless loop: the last `xfade` seconds are blended into the start (equal-power)."""
    if args.only and name not in args.only:
        return
    samples = decode(source, start, end, 'highpass=f=60')
    x = int(xfade * 48000)
    body = samples[:len(samples) - x]
    for i in range(x):
        t = i / x
        body[i] = body[i] * t ** 0.5 + samples[len(samples) - x + i] * (1 - t) ** 0.5
    write(name, body, 0.8)
    print(f'{name}: {len(body) / 48000:.3f}s loop ({source}, {start}..{end})')


# ---- robot
# Machine gun: single shots cut between the burst's transients (the last one keeps its natural tail).
for i, (start, end) in enumerate([(0.035, 0.13), (0.125, 0.225), (0.32, 0.42),
                                  (0.42, 0.525), (0.92, 1.03), (1.32, 1.44)]):
    export('robot-machine-gun-burst.mp3', f'gun_shot_{i + 1}', start, end, True, 0.85)
# Rocket windup + launch: the whoosh is the forced windup, the bang at ~0.50 s in the file is the moment the
# rocket leaves (ROCKET_WINDUP in src/game.c3 = bang time in this clip), then a bit of its decay.
export('missile-launch.mp3', 'missile_launch', 0.06, 1.0, fade=0.2)
export('missile-explosion.mp3', 'missile_explosion')
# Servos: loud isolated strokes from >= 30 s. 1..4 short corrections, 5..8 longer moves.
for i, (start, end) in enumerate([(35.69, 36.03), (38.81, 39.15), (43.32, 43.70), (53.11, 53.50),
                                  (30.40, 31.00), (38.08, 38.71), (47.35, 47.84), (50.48, 51.21)]):
    export('robot-servo-strokes.mp3', f'robot_servo_{i + 1}', start, end, True)
# Foot landings: single clean casing drops (first clink + short bounce).
for i, (start, end) in enumerate([(4.28, 4.53), (5.51, 5.67), (7.07, 7.28), (7.975, 8.22),
                                  (8.94, 9.09), (10.18, 10.39), (14.695, 14.94), (25.345, 25.58)]):
    export('robot-foot-clinks.mp3', f'robot_foot_{i + 1}', start, end, True)

# ---- creatures
export('enemy-death-splatter.mp3', 'enemy_death_splatter')
export('crawler-attack.mp3', 'crawler_attack')
export('crawler-roar.mp3', 'crawler_roar')
export_loop('crawler-walking.mp3', 'crawler_walk_loop', 0.0, 4.25)
# The bug-crawl file is three takes separated by silence: one loop each.
for i, (start, end) in enumerate([(0.0, 2.45), (3.4, 5.85), (7.0, 9.85)]):
    export_loop('skitter-crawling.mp3', f'skitter_crawl_loop_{i + 1}', start, end, 0.2)
export('nest-burst-squelch.mp3', 'nest_burst_squelch')

# ---- cave-wing: the user's insect recordings (short varied idle calls and an airborne-only wing loop)
export('flutter-death.mp3', 'flutter_death')
for i, (start, end) in enumerate([(0.28, 1.5), (1.5, 2.9), (2.9, 4.5)]):
    export('flutter-clicking.mp3', f'flutter_click_{i + 1}', start, end, short=True)
export_loop('flutter-flapping.mp3', 'flutter_flap_loop', 0.27, 1.9, 0.12)

# ---- new surface/rift recordings: preserve natural gusts and drone variation, crossfade loop boundaries.
export_loop('surface-wind.mp3', 'surface_wind_loop', 0.7, 41.3, 2.0)
export_loop('portal-idle.mp3', 'portal_idle_loop', 2.0, 24.0, 0.8)
export('teleport.mp3', 'teleport', fade=0.08)
# Individual gravel contacts, not a walking loop (the robot's actual gait triggers these).
for i, (start, end) in enumerate([(1.44, 1.96), (2.14, 2.67), (3.19, 3.74),
                                  (4.41, 4.98), (5.81, 6.37), (8.08, 8.64)]):
    export('gravel.mp3', f'gravel_step_{i + 1}', start, end, short=True, peak=0.7, fade=0.05)

# ---- shotgun: three separate blasts of one recording, each with its own natural tail (no reuse of one take)
for i, start in enumerate([0.803, 6.189, 9.219]):
    export('shotgun.mp3', f'shotgun_{i + 1}', start - 0.012, start + 1.25, peak=0.9, fade=0.35)
# ---- weapon swap mechanics from a laser printer's motor/servo: short motor whirs (fold motion)
#      and its sharp mechanical clunks (latch / pump rack)
for i, (start, end) in enumerate([(19.25, 19.78), (39.05, 39.62), (43.95, 44.5)]):
    export('printer-servo.mp3', f'weapon_whir_{i + 1}', start, end, short=True, peak=0.7, fade=0.09)
for i, start in enumerate([24.225, 29.205, 34.235]):
    export('printer-servo.mp3', f'weapon_latch_{i + 1}', start - 0.01, start + 0.3, short=True, peak=0.8, fade=0.08)

# ---- world
export('door-metal-clank.mp3', 'door_clank')
export('item-pickup-chime.mp3', 'item_pickup')
export('skitter-hatch-squish.mp3', 'skitter_hatch_squish')

# ---- robot taking a hit: single strikes from the metal-hitting take (each cut before the next strike)
for i, start in enumerate([2.64, 5.93, 7.54, 9.465, 11.455, 14.865]):
    export('robot-hit-metal.mp3', f'robot_hit_{i + 1}', start - 0.01, start + 0.5, fade=0.12)

# ---- game over: the first sting of the pack (hit at ~2.05 s, tail fades out by ~5.8 s)
export('game-over-stings.mp3', 'game_over', 1.95, 5.8, fade=0.4)

# ---- music: compressed stereo OGG (looped, flat and quiet)
if not args.only or 'music' in args.only:
    subprocess.check_call(['ffmpeg', '-v', 'error', '-y', '-i', str(args.source / 'background-music.mp3'),
                           '-ar', '48000', '-c:a', 'libvorbis', '-q:a', '5', str(out / 'music.ogg')])
    print('music: background-music.mp3')
# ---- main menu music (game app): the user's "ominous music" download, compressed stereo OGG, looped
if not args.only or 'menu-music' in args.only:
    subprocess.check_call(['ffmpeg', '-v', 'error', '-y', '-i', str(args.source / 'ominous-music.mp3'),
                           '-ar', '48000', '-c:a', 'libvorbis', '-q:a', '5', str(out / 'menu_music.ogg')])
    print('menu-music: ominous-music.mp3')
