#!/usr/bin/env python3
"""Skill-tree / HUD icons: white glyphs on transparent, drawn at 4x and downsampled (anti-aliased).

The game tints them per branch, so every glyph is pure white with alpha; depth comes from a darker inner
stroke (alpha 0.55) instead of colour. Deterministic, no downloaded art.

    python3 dev/tools/generate-icons.py  -> assets/icons/<name>.png (128 px)
"""
import math
import os
from PIL import Image, ImageDraw

S = 512            # authoring canvas
OUT = 128          # written size
W = (255, 255, 255, 255)
DIM = (255, 255, 255, 140)
HERE = os.path.dirname(os.path.abspath(__file__))
DEST = os.path.join(HERE, '..', '..', 'assets', 'icons')


def canvas():
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def line(d, pts, w, fill=W):
    d.line(pts, fill=fill, width=w, joint='curve')
    r = w / 2
    for x, y in (pts[0], pts[-1]):
        d.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def arrow_head(d, tip, ang, size, fill=W):
    a1, a2 = ang + math.radians(150), ang - math.radians(150)
    d.polygon([tip, (tip[0] + math.cos(a1) * size, tip[1] + math.sin(a1) * size),
               (tip[0] + math.cos(a2) * size, tip[1] + math.sin(a2) * size)], fill=fill)


def arc_pts(cx, cy, r, a0, a1, n=48):
    return [(cx + math.cos(math.radians(a0 + (a1 - a0) * i / n)) * r, cy + math.sin(math.radians(a0 + (a1 - a0) * i / n)) * r) for i in range(n + 1)]


def save(img, name):
    img.resize((OUT, OUT), Image.LANCZOS).save(os.path.join(DEST, name + '.png'))


# ------------------------------------------------------------------ glyphs
def servo():   # an insect leg in stride + speed chevrons
    img, d = canvas()
    line(d, [(150, 150), (250, 110), (330, 300), (300, 420)], 34)
    d.ellipse((120, 120, 180, 180), fill=W); d.ellipse((222, 82, 278, 138), fill=W); d.ellipse((304, 274, 356, 326), fill=W)
    line(d, [(270, 420), (340, 420)], 26)
    for k, x in enumerate((360, 410)):
        line(d, [(x, 150), (x + 50, 200), (x, 250)], 22, W if k else DIM)
    return img


def dash():   # two bold chevrons with speed streaks
    img, d = canvas()
    for k, x in enumerate((190, 310)):
        d.polygon([(x - 70, 110), (x + 20, 110), (x + 150, 256), (x + 20, 402), (x - 70, 402), (x + 60, 256)], fill=W if k else DIM)
    for y, x0, l in ((170, 30, 110), (256, 10, 150), (342, 30, 110)):
        line(d, [(x0, y), (x0 + l, y)], 22, DIM)
    return img


def overclock():   # gauge with needle pinned in the red + a bolt
    img, d = canvas()
    line(d, arc_pts(256, 300, 170, 160, 380), 30)
    for a in range(170, 371, 25):
        r0, r1 = (120, 145) if a < 330 else (105, 145)
        line(d, [(256 + math.cos(math.radians(a)) * r0, 300 + math.sin(math.radians(a)) * r0), (256 + math.cos(math.radians(a)) * r1, 300 + math.sin(math.radians(a)) * r1)], 14, W if a >= 330 else DIM)
    ang = math.radians(340)
    line(d, [(256, 300), (256 + math.cos(ang) * 140, 300 + math.sin(ang) * 140)], 24)
    d.ellipse((226, 270, 286, 330), fill=W)
    d.polygon([(250, 360), (210, 450), (250, 440), (230, 500), (300, 400), (262, 410), (290, 360)], fill=W)
    return img


def multigun():   # three separate barrels from one receiver, muzzle flashes
    img, d = canvas()
    d.rounded_rectangle((70, 140, 230, 372), 26, fill=W)
    d.rounded_rectangle((110, 372, 180, 460), 18, fill=W)
    for y in (172, 256, 340):
        d.rounded_rectangle((220, y - 24, 410, y + 24), 14, fill=W)
        d.rectangle((394, y - 32, 424, y + 32), fill=W)
        d.polygon([(440, y), (500, y - 26), (482, y), (500, y + 26)], fill=DIM)
    for y in (214, 298):
        d.rectangle((100, y - 6, 200, y + 6), fill=(0, 0, 0, 0))
    return img


def pierce():   # arrow through two rings
    img, d = canvas()
    for cx in (210, 330):
        line(d, arc_pts(cx, 256, 70, 0, 360, 64), 22, W if cx == 330 else DIM)
    line(d, [(60, 256), (440, 256)], 30)
    arrow_head(d, (480, 256), 0, 90)
    line(d, [(60, 256), (20, 210)], 18); line(d, [(60, 256), (20, 302)], 18)
    return img


def ricochet():   # wall + bouncing path
    img, d = canvas()
    d.rectangle((400, 70, 450, 440), fill=DIM)
    for y in range(90, 440, 60):
        line(d, [(400, y), (450, y + 30)], 8, (0, 0, 0, 0))
    line(d, [(70, 150), (390, 260)], 28)
    line(d, [(390, 260), (150, 420)], 28)
    arrow_head(d, (120, 440), math.atan2(440 - 260, 120 - 390), 90)
    for k in range(3):
        a = math.radians(-60 + k * 60)
        line(d, [(392 - math.cos(a) * 20, 260 + math.sin(a) * 50), (392 - math.cos(a) * 60, 260 + math.sin(a) * 100)], 10, DIM)
    return img


def regen():   # cross inside a circular refresh arrow
    img, d = canvas()
    line(d, arc_pts(256, 256, 180, -60, 220), 30)
    a = math.radians(220)
    arrow_head(d, (256 + math.cos(a) * 180, 256 + math.sin(a) * 180), a + math.pi / 2, 80)
    d.rounded_rectangle((216, 150, 296, 362), 16, fill=W)
    d.rounded_rectangle((150, 216, 362, 296), 16, fill=W)
    return img


def armor():   # shield with plate seams and rivets
    img, d = canvas()
    pts = [(256, 60), (430, 120), (420, 290)] + arc_pts(256, 290, 164, 0, 180)[1:] + [(92, 290), (82, 120)]
    d.polygon([(256, 60), (430, 120), (420, 300), (256, 460), (92, 300), (82, 120)], fill=W)
    d.polygon([(256, 110), (380, 152), (372, 290), (256, 404), (140, 290), (132, 152)], fill=(0, 0, 0, 0))
    d.polygon([(256, 130), (360, 165), (354, 285), (256, 380), (158, 285), (152, 165)], fill=DIM)
    line(d, [(256, 135), (256, 375)], 16, W)
    line(d, [(160, 240), (352, 240)], 16, W)
    for x, y in ((205, 190), (307, 190), (205, 300), (307, 300)):
        d.ellipse((x - 14, y - 14, x + 14, y + 14), fill=W)
    return img


def nanites():   # hexagon swarm around a plus
    img, d = canvas()
    def hexagon(cx, cy, r, fill):
        d.polygon([(cx + math.cos(math.radians(60 * i + 30)) * r, cy + math.sin(math.radians(60 * i + 30)) * r) for i in range(6)], fill=fill)
    hexagon(256, 256, 110, W)
    d.rectangle((236, 196, 276, 316), fill=(0, 0, 0, 0)); d.rectangle((196, 236, 316, 276), fill=(0, 0, 0, 0))
    for i in range(6):
        a = math.radians(60 * i)
        hexagon(256 + math.cos(a) * 185, 256 + math.sin(a) * 185, 44 if i % 2 else 34, W if i % 2 else DIM)
    return img


def scanner():   # dish on a mast with signal arcs
    img, d = canvas()
    d.chord((110, 120, 330, 340), 120, 300, fill=W)
    d.chord((150, 160, 290, 300), 120, 300, fill=(0, 0, 0, 0))
    line(d, [(220, 230), (300, 150)], 18)
    d.ellipse((288, 138, 324, 174), fill=W)
    line(d, [(200, 280), (200, 440)], 26); line(d, [(140, 450), (260, 450)], 26)
    for k, r in enumerate((80, 140, 200)):
        line(d, arc_pts(300, 150, r, -70, 10, 24), 18, W if k == 0 else DIM)
    return img


def aimbot():   # reticle + eye
    img, d = canvas()
    line(d, arc_pts(256, 256, 170, 0, 360, 72), 22)
    for a in (0, 90, 180, 270):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        line(d, [(256 + c * 120, 256 + s * 120), (256 + c * 225, 256 + s * 225)], 24)
    d.ellipse((150, 196, 362, 316), fill=W)
    d.ellipse((176, 212, 336, 300), fill=(0, 0, 0, 0))
    d.ellipse((216, 216, 296, 296), fill=W)
    d.ellipse((242, 230, 262, 250), fill=(0, 0, 0, 0))
    return img


def point():   # skill point: faceted gem
    img, d = canvas()
    d.polygon([(256, 60), (420, 200), (256, 460), (92, 200)], fill=W)
    d.polygon([(256, 60), (420, 200), (256, 200)], fill=DIM)
    d.polygon([(92, 200), (256, 200), (256, 460)], fill=(255, 255, 255, 200))
    line(d, [(92, 200), (420, 200)], 10, (0, 0, 0, 0))
    return img


def lock():
    img, d = canvas()
    line(d, arc_pts(256, 220, 90, 180, 360, 32), 34)
    line(d, [(166, 220), (166, 250)], 34); line(d, [(346, 220), (346, 250)], 34)
    d.rounded_rectangle((130, 240, 382, 440), 30, fill=W)
    d.ellipse((232, 300, 280, 348), fill=(0, 0, 0, 0)); d.rectangle((248, 330, 264, 390), fill=(0, 0, 0, 0))
    return img


def crate():   # service crate with a star burst (free perk)
    img, d = canvas()
    d.rounded_rectangle((110, 220, 400, 440), 20, fill=W)
    d.rectangle((140, 250, 370, 410), fill=DIM)
    line(d, [(140, 250), (370, 410)], 18, W); line(d, [(370, 250), (140, 410)], 18, W)
    d.rectangle((100, 190, 410, 230), fill=W)
    for k in range(8):
        a = math.radians(-90 + (k - 3.5) * 22)
        line(d, [(256 + math.cos(a) * 60, 150 + math.sin(a) * 60 + 30), (256 + math.cos(a) * 110, 150 + math.sin(a) * 110 + 30)], 14, W if k % 2 else DIM)
    return img


ICONS = {'servo': servo, 'dash': dash, 'overclock': overclock, 'multigun': multigun, 'pierce': pierce, 'ricochet': ricochet,
         'regen': regen, 'armor': armor, 'nanites': nanites, 'scanner': scanner, 'aimbot': aimbot,
         'point': point, 'lock': lock, 'crate': crate}

if __name__ == '__main__':
    os.makedirs(DEST, exist_ok=True)
    for name, fn in ICONS.items():
        save(fn(), name)
    # contact sheet for review (scratch, not loaded by the game)
    sheet = Image.new('RGBA', (OUT * len(ICONS), OUT * 2), (40, 40, 40, 255))
    for i, name in enumerate(ICONS):
        ic = Image.open(os.path.join(DEST, name + '.png'))
        sheet.alpha_composite(ic, (i * OUT, 0))
        tint = Image.new('RGBA', ic.size, (254, 128, 25, 255)); tint.putalpha(ic.getchannel('A'))
        sheet.alpha_composite(tint, (i * OUT, OUT))
    sheet.save(os.environ.get('ICON_SHEET', '/dev/null') if os.environ.get('ICON_SHEET') else os.path.join(DEST, '..', '..', 'dev', 'output', 'icons-sheet.png'))
    print(f'{len(ICONS)} icons -> {os.path.normpath(DEST)}')
