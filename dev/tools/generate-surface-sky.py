#!/usr/bin/env python3
"""Author the layer-0 equirectangular galaxy sky (numpy + Pillow; deterministic, no external imagery).
Fields are evaluated on unit directions, not cube faces, so there are no face seams. The runtime samples
one texture, not expensive per-pixel fractal noise; stars do not shimmer/reseed as the camera moves.
"""
from pathlib import Path
import numpy as np
from PIL import Image

W, H = 4096, 2048
rng = np.random.default_rng(730821)
lon = (np.arange(W, dtype=np.float32) + .5) / W * (2*np.pi) - np.pi
lat = np.pi/2 - (np.arange(H, dtype=np.float32) + .5) / H * np.pi
x = np.cos(lat)[:, None] * np.cos(lon)[None, :]
y = np.broadcast_to(np.sin(lat)[:, None], (H, W))
z = np.cos(lat)[:, None] * np.sin(lon)[None, :]

def field(scale, seed):
    local = np.random.default_rng(seed)
    value = np.zeros((H, W), dtype=np.float32)
    for _ in range(6):
        axis = local.normal(size=3); axis /= np.linalg.norm(axis)
        value += np.sin((x*axis[0] + y*axis[1] + z*axis[2])*scale + local.uniform(0, 2*np.pi)).astype(np.float32)
    return value / 6

large = field(8, 11)
medium = field(29, 12)
fine = field(85, 13)
detail = field(210, 14)
latitude = x*.31 + y*.68 + z*-.664
warp = latitude + large*.13 + medium*.035
band = np.exp(-warp*warp*26)
core = np.exp(-warp*warp*240)
dust = np.exp(-((warp + medium*.08 + fine*.022 + .014)**2)*1800) * np.clip(.5 + large*1.5 + medium*1.2 + fine*.5, 0, 1)
cloud = np.clip(.5 + large*.9 + medium*.7 + fine*.5 + detail*.25, 0, 1.4)
# Deep indigo, silver-violet stellar clouds, petrol-blue wisps and a dark marbled dust lane.
base = np.stack([.025 + .028*(1-y), .030 + .023*(1-y), .065 + .044*(1-y)], axis=2)
image = base.astype(np.float32)
image += (band*cloud)[..., None] * np.array([.23, .13, .34], np.float32)
image += (core*cloud*cloud)[..., None] * np.array([.29, .29, .28], np.float32)
blue = band*np.clip(-large+medium*.5, 0, 1)
image += blue[..., None] * np.array([.025, .13, .19], np.float32)
image *= 1-dust[..., None]*.76
# Warm, thin-atmosphere horizon, instead of an opaque blue dome.
horizon = np.exp(-((y-.005)/.075)**2)
image += horizon[..., None] * np.array([.16, .085, .055], np.float32)

# Sparse bright field plus tiny stars concentrated toward the galactic plane. Gaussian PSFs, no hard pixels.
for i in range(10500):
    d = rng.normal(size=3); d /= np.linalg.norm(d)
    if i >= 6500:
        n = np.array([.31, .68, -.664]); n /= np.linalg.norm(n)
        d -= n*np.dot(d, n); d += n*rng.normal(0, .11); d /= np.linalg.norm(d)
    u = (np.arctan2(d[2], d[0])/(2*np.pi)+.5)*W
    v = np.arccos(d[1])/np.pi*H
    radius = rng.uniform(.32, .7)
    intensity = rng.uniform(.12, .55)
    if i % 139 == 0:
        radius = rng.uniform(1.0, 1.55); intensity = rng.uniform(.7, 1.25)
    sx = min(12, radius/max(.12, np.sqrt(1-d[1]*d[1])))
    sy = radius
    rx, ry = int(np.ceil(sx*3)), int(np.ceil(sy*3))
    px = np.arange(int(u)-rx, int(u)+rx+1)
    py = np.arange(max(0, int(v)-ry), min(H, int(v)+ry+1))
    if not len(py):
        continue
    glow = np.exp(-.5*(((px[None, :]+.5-u)/sx)**2+((py[:, None]+.5-v)/sy)**2))*intensity
    tint = np.array([.8, .9, 1.0]) if i%3 else np.array([1.0, .82, .61])
    image[py[:, None], (px%W)[None, :]] += glow[..., None]*tint

# A quiet, distant ringed moon, lit from one side. It occludes stars rather than being a transparent decal.
center = np.array([.58, .44, .685]); center /= np.linalg.norm(center)
right = np.cross(center, [0, 1, 0]); right /= np.linalg.norm(right)
up = np.cross(right, center)
size = .048
mx = (x*right[0]+y*right[1]+z*right[2])/size
my = (x*up[0]+y*up[1]+z*up[2])/size
front = x*center[0]+y*center[1]+z*center[2] > .9
rr = mx*mx + my*my
moon = (rr < 1) & front
normal_z = np.sqrt(np.clip(1-rr, 0, 1))
light = np.clip(-mx*.7+my*.45+normal_z*.25, 0, 1)
craters = np.clip(.8 + fine*.5 + medium*.2, .4, 1.1)
shade = (.025 + light*.43)*craters
moon_rgb = shade[..., None]*np.array([.75, .82, 1.0], np.float32)
angle = .38
rx = mx*np.cos(angle)+my*np.sin(angle)
ry = -mx*np.sin(angle)+my*np.cos(angle)
ring_r = np.sqrt(rx*rx + (ry/.23)**2)
ring = (ring_r>1.4)&(ring_r<2.25)&front&(~moon)
ring_bands = (.045+.06*(.5+.5*np.sin(ring_r*100))) * (.6+.4*np.clip(-mx, 0, 1))
image[ring] = (ring_bands[..., None]*np.array([.8, .72, .63]))[ring]
image[moon] = moon_rgb[moon]

out = Path(__file__).resolve().parents[2]/'assets/skies/ash-waste-galaxy.png'
out.parent.mkdir(parents=True, exist_ok=True)
Image.fromarray((np.clip(image, 0, 1)*255+.5).astype(np.uint8)).save(out, optimize=True)
print(f'{out}: {W}x{H}, {out.stat().st_size/1048576:.1f} MiB')
