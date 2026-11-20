#!/usr/bin/env python3
"""Small dark industrial scene: a powered-down equipment bay on a desolate moon.
Writes industrial.vptscene.json next to this file. Paths are relative to the engine root.
Terrain is hand-written regolith (sparse chunks), not the editor's green ground brush.
"""
import json, math, random
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BASE = 'assets/library/BLACK_START/'
SIZE = 64                      # world is x,z in [-32,32)
Y_MIN = -16
random.seed(7)

def rgba(r, g, b, a=255):
    return r | (g << 8) | (b << 16) | (a << 24)

# ---------------------------------------------------------------- terrain (regolith)
chunks = {}
def set_voxel(x, y, z, value):
    gx, gy, gz = x + SIZE // 2, y - Y_MIN, z + SIZE // 2
    if not (0 <= gx < SIZE and 0 <= gz < SIZE and 0 <= gy < 64):
        return
    key = (gx // 16, gy // 16, gz // 16)
    data = chunks.setdefault(key, [0] * 4096)
    data[((gy % 16) * 16 + gz % 16) * 16 + gx % 16] = value

def regolith(x, z, depth):
    h = (x * 73856093 ^ z * 19349663 ^ depth * 83492791) & 0xffff
    n = (h % 7) - 3
    stain = math.sin(x * 0.21 + z * 0.13) + math.sin(x * 0.07 - z * 0.19)
    r, g, b = 50 + n, 48 + n, 46 + n
    if stain > 1.3:                       # rusty dust drifts
        r, g, b = r + 6, g + 2, b - 1
    if depth > 0:                         # darker below the surface
        r, g, b = r - 10, g - 10, b - 10
    return rgba(max(0, r), max(0, g), max(0, b))

heaps = [(-14, 9, 3.5, 1.6), (15, 6, 2.5, 1.2), (-22, -3, 4.0, 2.2), (21, -6, 3.0, 1.4),
         (-6, 14, 2.2, 0.9), (9, 18, 3.5, 1.5), (26, 20, 5.0, 2.6), (-27, 22, 4.5, 2.0)]
crater = (-12, 22, 5.0)
for x in range(-SIZE // 2, SIZE // 2):
    for z in range(-SIZE // 2, SIZE // 2):
        top = 0.0
        for hx, hz, r, hgt in heaps:
            d = math.hypot(x + 0.5 - hx, z + 0.5 - hz)
            if d < r:
                top = max(top, hgt * (1 - (d / r) ** 2))
        d = math.hypot(x + 0.5 - crater[0], z + 0.5 - crater[1])
        if d < crater[2]:
            top -= 1.2 * (1 - (d / crater[2]) ** 2)
        elif d < crater[2] + 1.5:
            top += 0.6
        top = int(round(top))
        for y in range(top - 3, top):
            set_voxel(x, y, z, regolith(x, z, top - 1 - y))
# scattered rocks
for _ in range(70):
    x, z = random.randint(-31, 30), random.randint(-31, 30)
    if -10 <= x <= 10 and -8 <= z <= 8:
        continue
    c = rgba(40 + random.randint(-6, 6), 39 + random.randint(-6, 6), 38 + random.randint(-6, 6))
    for dx in range(random.randint(1, 2)):
        for dz in range(random.randint(1, 2)):
            set_voxel(x + dx, 0, z + dz, c)

# ---------------------------------------------------------------- instances
instances = []
def add(name, x, z, y=0.0, rot=0.0, scale=1.0):
    instances.append(dict(asset=BASE + name + '.vpt.json', x=x, y=y, z=z,
                          rotation=rot, scale=scale, wind=0))

DECK = 0.35                            # corridor-floor tile height
HALF_PI = math.pi / 2
# Floor: 4 x 3 deck tiles, room spans x [-8,8], z [-6,6].
for x in (-6, -2, 2, 6):
    for z in (-4, 0, 4):
        add('corridor-floor', x, z)
# Back wall faces the room (+Z). Door glass and windows look out to the yard.
add('wall-window', -6, -6.33)
add('wall-panel', -2, -6.28)
add('bulkhead-door', 2, -6.4)
add('wall-window', 6, -6.33)
# Left wall faces +X; right wall is broken: one panel left standing.
add('wall-window', -8.33, -4, rot=HALF_PI)
add('wall-panel', -8.28, 0, rot=HALF_PI)
add('wall-panel', -8.28, 4, rot=HALF_PI)
add('wall-panel', 8.28, -4, rot=-HALF_PI)

# Fuel and power: tank along the left wall, generator with a leecher feeding on it.
add('diesel-tank', -6.5, 2.9, y=DECK, rot=HALF_PI)
add('diesel-generator', -3.6, -3.0, y=DECK, rot=0.0)
add('alien-leecher', -3.0, -2.55, y=DECK + 1.72, rot=0.9)
# Pipe run along the back wall under the windows.
add('pipe-straight', -5.6, -5.45, y=DECK, rot=HALF_PI)
add('pipe-straight', -1.5, -5.45, y=DECK, rot=HALF_PI)
# Controls on the right, crates near the open side.
add('control-console', 6.6, -2.6, y=DECK, rot=-HALF_PI)
add('control-console', 6.6, -0.3, y=DECK, rot=-HALF_PI - 0.12)
add('service-crate', 5.9, 3.6, y=DECK, rot=0.15)
add('service-crate', 5.9, 3.6, y=DECK + 1.45, rot=-0.2)
add('service-crate', 3.9, 4.9, y=DECK, rot=0.55)
# The robot faces the sealed door; a crawler lurks behind the crates.
add('maintenance-hexapod', 1.2, 0.6, y=DECK, rot=math.pi - 0.25)
add('alien-crawler', 3.1, 2.3, y=DECK, rot=-2.1)
# Light: two work lamps inside, one outside shining through the door glass.
add('work-lamp', -0.6, -3.6, y=DECK, rot=0.35)
add('work-lamp', -2.6, 4.6, y=DECK, rot=math.pi - 0.7)
add('work-lamp', 2.3, -8.4, y=0.0, rot=0.0)
# Emergency beacons on the wall tops.
add('beacon', -2.0, -6.28, y=3.2)
add('beacon', 8.28, -4.0, y=3.2)
add('beacon', -8.28, 4.0, y=3.2)
# The yard: megastructures looming outside.
add('mega-cooling-tower', -18.0, -20.5)
add('mega-storage-silo', 12.0, -21.5)

LIGHT = dict(azimuth=210, elevation=22, sun_power=6, sky_power=0.6, warmth=0.0,
             sun_radius=1.2, exposure=1.1, quality=1, bounces=3, night=1)
scene = dict(version=1, size=SIZE, library=BASE.rstrip('/'), lighting=LIGHT,
             chunks=[dict(x=k[0], y=k[1], z=k[2], voxels=v) for k, v in sorted(chunks.items())],
             instances=instances)
out = ROOT / 'industrial.vptscene.json'
out.write_text(json.dumps(scene, separators=(',', ':')) + '\n')
print(f'Wrote {out.name}: {len(chunks)} terrain chunks, {len(instances)} instances')
