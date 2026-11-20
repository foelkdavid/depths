#!/usr/bin/env node
// Maintenance hexapod ("MH-6"): industrial six-legged service robot, built as rigid parts for the
// procedural rig runtime. Run from anywhere: node dev/generators/build-hexapod.js   (--force: back up edited outputs, then overwrite)
//
// Writes parts-hexapod/*.vpt.json, maintenance-hexapod.{vpt,rig,anim}.json (static proxy = rest pose),
// vox/maintenance-hexapod.vox and refreshes the catalog entry. Authoring space is engine voxel space:
// x right, y up, z forward (front = +z), one unit = VOXEL metres. Shapes are tested at voxel centres.
//
// Each leg is three servos: a coxa (yaw about the body's up axis), then femur and tibia hinged on one
// axis perpendicular to the leg plane. The chassis has no separate head: the whole body aims.
'use strict';
// Outputs live in the asset folder; this script lives in dev/generators/.
process.chdir(require('path').join(__dirname, '../../assets/library/BLACK_START'));
const fs = require('fs');
// Refuses to overwrite files edited since the last run (editor Materials, hand-tuned JSON); --force backs them up.
require('./generated-guard.js').start('build-hexapod', { skip: ['catalog.json'], dirs: ['parts-hexapod'] });
const VOXEL = 0.02;
const DIR = 'parts-hexapod';

// ---------------------------------------------------------------- palette
const C = {
  yellow: [236, 166, 22], amber: [228, 128, 18], orange: [214, 92, 20],
  gun: [54, 60, 66], dark: [32, 36, 40], black: [17, 19, 21], rubber: [26, 26, 28],
  steel: [128, 136, 140], chrome: [184, 190, 192], cable: [40, 40, 44],
  // the only two glowing colours (rules in materials.json): flashlight emitter and the blinking mast tip
  head: [240, 236, 210, 1], beacon: [60, 230, 50, 1],
  glass: [150, 196, 214],
};
const PLAIN = new Set([C.glass]);

// ---------------------------------------------------------------- vector helpers
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const len = a => Math.hypot(a[0], a[1], a[2]);
const norm = a => mul(a, 1 / len(a));

// ---------------------------------------------------------------- shapes
// A frame maps local (u,y,w) to world: origin + u*dir + y*up + w*side. Body frame = identity.
const IDENT = { o: [0, 0, 0], u: [1, 0, 0], v: [0, 1, 0], w: [0, 0, 1] };
let frame = IDENT;
let shapes = [];
function toLocal(p, f) { const d = sub(p, f.o); return [dot(d, f.u), dot(d, f.v), dot(d, f.w)]; }
function toWorld(p, f) { return add(f.o, add(mul(f.u, p[0]), add(mul(f.v, p[1]), mul(f.w, p[2])))); }
// Generic shape: local-space predicate + local AABB.
function shape(lo, hi, test, color) { shapes.push({ f: frame, lo, hi, test, color }); }
function box(lo, hi, c) { shape(lo, hi, p => p[0] >= lo[0] && p[0] <= hi[0] && p[1] >= lo[1] && p[1] <= hi[1] && p[2] >= lo[2] && p[2] <= hi[2], c); }
function sphere(o, r, c) { shape(sub(o, [r, r, r]), add(o, [r, r, r]), p => len(sub(p, o)) <= r, c); }
// Flat-ended cylinder a->b with radius r0 at a and r1 at b.
function cyl(a, b, r0, c, r1 = r0) {
  const ab = sub(b, a), l2 = dot(ab, ab), r = Math.max(r0, r1);
  const lo = [0, 1, 2].map(i => Math.min(a[i], b[i]) - r), hi = [0, 1, 2].map(i => Math.max(a[i], b[i]) + r);
  shape(lo, hi, p => {
    const ap = sub(p, a), t = dot(ap, ab) / l2; if (t < 0 || t > 1) return false;
    return len(sub(ap, mul(ab, t))) <= r0 + (r1 - r0) * t;
  }, c);
}
// Oriented slab between a and b: thickness th in the u/y plane, width w in local w (centred on wc).
function strut(a, b, th0, wd, c, th1 = th0, wc = 0) {
  a = [a[0], a[1], 0]; b = [b[0], b[1], 0];
  const d = sub(b, a), l = len(d), t = mul(d, 1 / l), n = [-t[1], t[0], 0];
  const r = Math.max(th0, th1) / 2 + 1;
  shape([Math.min(a[0], b[0]) - r, Math.min(a[1], b[1]) - r, wc - wd / 2], [Math.max(a[0], b[0]) + r, Math.max(a[1], b[1]) + r, wc + wd / 2], p => {
    const q = sub(p, a), s = dot(q, t); if (s < 0 || s > l) return false;
    const th = th0 + (th1 - th0) * s / l; return Math.abs(dot(q, n)) <= th / 2 && Math.abs(p[2] - wc) <= wd / 2;
  }, c);
}

// ---------------------------------------------------------------- raster
function hash(x, y, z) { return (Math.imul(x, 73856093) ^ Math.imul(y, 19349663) ^ Math.imul(z, 83492791)) >>> 0; }
function raster(list) {
  const cells = new Map();
  for (const s of list) {
    let lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
    for (let k = 0; k < 8; k++) {
      const p = toWorld([k & 1 ? s.hi[0] : s.lo[0], k & 2 ? s.hi[1] : s.lo[1], k & 4 ? s.hi[2] : s.lo[2]], s.f);
      for (let i = 0; i < 3; i++) { lo[i] = Math.min(lo[i], p[i]); hi[i] = Math.max(hi[i], p[i]); }
    }
    for (let x = Math.floor(lo[0]) - 1; x <= Math.ceil(hi[0]); x++)
      for (let y = Math.floor(lo[1]) - 1; y <= Math.ceil(hi[1]); y++)
        for (let z = Math.floor(lo[2]) - 1; z <= Math.ceil(hi[2]); z++) {
          if (!s.test(toLocal([x + 0.5, y + 0.5, z + 0.5], s.f))) continue;
          const key = `${x},${y},${z}`;
          if (!s.color) { cells.delete(key); continue; }
          let v = s.color.slice(0, 3);
          if (!s.color[3] && !PLAIN.has(s.color)) {
            // Restrained, quantized wear (keeps the .vox palette small): +-2/4 brightness, rare scuffs.
            const h = hash(x, y, z), d = ((h % 5) - 2) * 2, scuff = h % 61 === 0 ? -14 : 0;
            v = v.map(c => Math.max(0, Math.min(255, c + d + scuff)));
          }
          cells.set(key, [x, y, z, v[0], v[1], v[2], s.color[3] ? 1 : 0]);
        }
  }
  return cells;
}

// ---------------------------------------------------------------- design
// MH-6 Mk2: a clean, tall-standing chassis on long legs. Long femurs/tibias give the body room to pitch
// (about 40 deg up) on planted feet, so the nose flashlight can be aimed high up walls.
const HIP_Y = 31;
// Weapon hinge (body voxel space): every weapon is authored around it and folds about the X axis through it.
const HINGE = [0, 26.4, 20];
// Alternative top mount: the same weapon models ride on a pylon above the deck (translated from HINGE).
const TOP_HINGE = [0, 46, 10];
C.exhaust = [255, 150, 60, 1];
// upgrade glows (rules below): targeting lens, coolant, thruster throat, scanner LED
C.laser = [255, 46, 36, 1]; C.coolant = [70, 255, 196, 1]; C.thrust = [120, 200, 255, 1];
// Coxa axis positions and leg headings. Legs 0-2 left (-x) front to back, 3-5 right; front/rear splay 38 deg.
const LEGS = [];
for (const s of [-1, 1]) for (let j = 0; j < 3; j++) {
  const z = [15, 0, -15][j], a = [38, 0, -38][j] * Math.PI / 180;
  LEGS.push({ s, j, o: [s * (j === 1 ? 13.5 : 12.5), HIP_Y, z], dir: [s * Math.cos(a), 0, Math.sin(a)] });
}
// Leg-plane (u radial, y up) joint positions: femur 0.42 m, tibia 0.78 m.
const FEMUR = [10, HIP_Y], KNEE = [27, 44], FOOT = [36, 0], FOOT_R = 3.2;
function legFrame(l) { const w = norm([-l.dir[2], 0, l.dir[0]]); return { o: [l.o[0], 0, l.o[2]], u: l.dir, v: [0, 1, 0], w }; }
const at = (l, uy) => toWorld([uy[0], uy[1], 0], legFrame(l));

// Body hull: long chamfered nose, short tail chamfer, bevelled top edges.
function hull(p, grow = 0) {
  const ax = Math.abs(p[0]), y = p[1], z = p[2];
  let half = 13 + grow;
  if (z > 16) half -= (z - 16) * 0.8; if (z < -18) half -= (-z - 18) * 1.4;
  if (y > 36) half -= (y - 36) * 1.6;
  return ax <= half && z <= 25 + grow && z >= -24 - grow && y >= 26 && y <= 38.5 + grow;
}
function buildBody() {
  frame = IDENT;
  // dark belly pan
  shape([-12, 23, -21], [12, 27, 22], p => Math.abs(p[0]) + Math.abs(p[2]) * 0.3 <= 16 && p[1] >= 23.5 && p[1] <= 27, C.gun);
  // armoured shell: safety yellow over a dark lower band
  shape([-14, 26, -25], [14, 39, 26], p => hull(p), C.yellow);
  shape([-14, 26, -25], [14, 29, 26], p => hull(p, 0.4) && p[1] <= 28.6, C.dark);
  // hip bays (coxa servos sit in them)
  for (const l of LEGS) cyl([l.o[0], 26, l.o[2]], [l.o[0], 35, l.o[2]], 5.4, null);
  for (const l of LEGS) cyl([l.o[0], 35, l.o[2]], [l.o[0], 36.2, l.o[2]], 5, C.gun);
  // top deck: one dark spine with two panel seams
  box([-2.2, 38, -18], [2.2, 39.4, 14], C.dark);
  for (const z of [-6, 6]) box([-10, 38.6, z], [10, 39.2, z + 0.8], C.dark);
  // nose: dark sensor face with ONE round flashlight (emitter disc behind a glass lens, gunmetal bezel)
  shape([-11, 28, 21], [11, 37, 27], p => hull(p, 0.6) && p[2] >= 22.5 && p[1] >= 29 && p[1] <= 36.5, C.black);
  cyl([0, 32.6, 23.5], [0, 32.6, 26.2], 4.6, C.gun);
  cyl([0, 32.6, 24.5], [0, 32.6, 26.6], 3.4, C.head);
  cyl([0, 32.6, 26.3], [0, 32.6, 27.2], 3.4, C.glass);
  // weapon mounts are attachments (under-nose clevis / deck pylon, F3 switches): only a flush deck plate here
  cyl([0, 38.6, TOP_HINGE[2]], [0, 39.5, TOP_HINGE[2]], 5.2, C.dark);
  // tail: radiator grille
  for (let x = -8; x <= 8; x += 2.2) box([x, 29.5, -25], [x + 1, 35.5, -22.5], C.gun);
  // antenna socket (rear left of the spine)
  cyl([-7, 38, -18], [-7, 40, -18], 1.6, C.dark);
}
// Rear antenna mast: two green voxels on top that blink (glow only, they light nothing).
function buildAntenna() {
  frame = IDENT;
  cyl([-7, 40, -18], [-7, 42, -18], 1.0, C.steel);
  cyl([-7, 42, -18], [-7, 52, -18], 0.5, C.black);
  box([-7.5, 52, -18.5], [-6.5, 54, -17.5], C.beacon);
}
// Coxa: vertical yaw servo drum + yellow arm to the femur's pitch servo.
function buildCoxa(l) {
  frame = legFrame(l);
  cyl([0, 26, 0], [0, 35, 0], 4.4, C.gun); cyl([0, 33, 0], [0, 34.6, 0], 4.7, C.orange);
  strut([2, HIP_Y], [FEMUR[0] + 1, HIP_Y], 7.5, 7.2, C.yellow);
  cyl([FEMUR[0], FEMUR[1], -4.2], [FEMUR[0], FEMUR[1], 4.2], 4.6, C.gun);
  for (const w of [-1, 1]) cyl([FEMUR[0], FEMUR[1], w * 4.2], [FEMUR[0], FEMUR[1], w * 5.2], 3.0, C.orange);
}
// Femur: one chunky yellow beam, a single actuator underneath, big knee servo.
function buildFemur(l) {
  frame = legFrame(l);
  const a = FEMUR, b = KNEE, d = norm([b[0] - a[0], b[1] - a[1], 0]), n = [-d[1], d[0]];
  const p = t => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
  const off = (q, s) => [q[0] + n[0] * s, q[1] + n[1] * s];
  strut(p(0.05), p(0.95), 8, 6.4, C.yellow, 7);
  strut(off(p(0.12), 3.9), off(p(0.88), 3.4), 1, 6.8, C.amber);          // top edge highlight
  const h0 = off(p(0.2), -5.2), h1 = off(p(0.85), -4.6), mid = [h0[0] + (h1[0] - h0[0]) * 0.55, h0[1] + (h1[1] - h0[1]) * 0.55];
  cyl([h0[0], h0[1], 0], [mid[0], mid[1], 0], 1.8, C.gun); cyl([mid[0], mid[1], 0], [h1[0], h1[1], 0], 0.9, C.chrome);
  cyl([KNEE[0], KNEE[1], -4.4], [KNEE[0], KNEE[1], 4.4], 4.4, C.gun);
  for (const w of [-1, 1]) cyl([KNEE[0], KNEE[1], w * 4.4], [KNEE[0], KNEE[1], w * 5.4], 2.8, C.orange);
}
// Tibia: long dark shin with a yellow armour plate, rubber foot.
function buildTibia(l) {
  frame = legFrame(l);
  const a = KNEE, f = [FOOT[0], FOOT[1] + FOOT_R], d = norm([f[0] - a[0], f[1] - a[1], 0]), n = [-d[1], d[0]];
  const p = t => [a[0] + (f[0] - a[0]) * t, a[1] + (f[1] - a[1]) * t];
  const off = (q, s) => [q[0] + n[0] * s, q[1] + n[1] * s];
  strut(p(0.04), p(0.9), 7, 5.6, C.gun, 3.8);
  strut(off(p(0.08), 2.8), off(p(0.5), 1.9), 2.2, 6.6, C.yellow, 1.4);    // shin armour
  strut(off(p(0.08), 3.8), off(p(0.16), 3.5), 1, 6.8, C.orange);           // knee guard lip
  cyl([...p(0.9), 0], [...p(0.95), 0], 2.6, C.dark);
  sphere([f[0], f[1], 0], FOOT_R, C.rubber);
}
// ---------------------------------------------------------------- export
function bounds(cells) {
  const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
  for (const v of cells.values()) for (let i = 0; i < 3; i++) { lo[i] = Math.min(lo[i], v[i]); hi[i] = Math.max(hi[i], v[i]); }
  return { lo, hi };
}
// Engine model-space metres of an authoring point for an asset with these bounds (importer centres
// x/z on the voxel bounds and grounds y at the lowest voxel).
function engine(p, b) {
  return [0, 1, 2].map(i => {
    const v = (p[i] - b.lo[i]) * VOXEL - (i === 1 ? 0 : (b.hi[i] - b.lo[i] + 1) * VOXEL / 2);
    return Math.round(v * 10000) / 10000;
  });
}
function writeAsset(file, cells) {
  const rows = Array.from(cells.values()).sort((a, b) => a[1] - b[1] || a[2] - b[2] || a[0] - b[0]);
  for (const r of rows) if (!r[6]) r.length = 6;
  fs.writeFileSync(file, JSON.stringify({ version: 1, voxel_size: VOXEL, up: 'y', voxels: rows }));
  return rows.length;
}
function writeVox(file, cells, b) {
  const pal = new Map(), xyzi = [];
  for (const v of cells.values()) {
    const key = `${v[3]},${v[4]},${v[5]}`; if (!pal.has(key)) pal.set(key, pal.size + 1);
    // VOX is z-up; source -y is the front, as in the other library models.
    xyzi.push([v[0] - b.lo[0], b.hi[2] - v[2], v[1] - b.lo[1], pal.get(key)]);
  }
  if (pal.size > 255) throw new Error(`vox palette overflow: ${pal.size}`);
  const size = [b.hi[0] - b.lo[0] + 1, b.hi[2] - b.lo[2] + 1, b.hi[1] - b.lo[1] + 1];
  const chunk = (id, data) => { const h = Buffer.alloc(12); h.write(id, 0); h.writeInt32LE(data.length, 4); h.writeInt32LE(0, 8); return Buffer.concat([h, data]); };
  const sz = Buffer.alloc(12); size.forEach((v, i) => sz.writeInt32LE(v, i * 4));
  const xy = Buffer.alloc(4 + xyzi.length * 4); xy.writeInt32LE(xyzi.length, 0); xyzi.forEach((v, i) => v.forEach((c, k) => xy.writeUInt8(c, 4 + i * 4 + k)));
  const rgba = Buffer.alloc(1024); for (const [key, i] of pal) { const c = key.split(',').map(Number); rgba.writeUInt8(c[0], (i - 1) * 4); rgba.writeUInt8(c[1], (i - 1) * 4 + 1); rgba.writeUInt8(c[2], (i - 1) * 4 + 2); rgba.writeUInt8(255, (i - 1) * 4 + 3); }
  const children = Buffer.concat([chunk('SIZE', sz), chunk('XYZI', xy), chunk('RGBA', rgba)]);
  const main = Buffer.alloc(12); main.write('MAIN', 0); main.writeInt32LE(0, 4); main.writeInt32LE(children.length, 8);
  const head = Buffer.alloc(8); head.write('VOX ', 0); head.writeInt32LE(150, 4);
  fs.writeFileSync(file, Buffer.concat([head, main, children]));
}

// Part list: name, parent, pivot (authoring units), builder.
// ---------------------------------------------------------------- weapons (separate attachments, not rig parts)
// Authored in body voxel space around HINGE. The game folds them about the hinge and recoils/pumps the
// moving pieces; muzzles are the exact bore exits, so shots leave the real barrels.
function knuckle() { cyl([-6, HINGE[1], HINGE[2]], [6, HINGE[1], HINGE[2]], 2.5, C.dark); }
function buildMg() {   // twin pulse cannon receiver (the barrels are their own recoiling pieces)
  frame = IDENT; knuckle();
  box([-6.2, 24, 18], [6.2, 30.2, 25], C.gun); box([-6.2, 29.4, 19], [6.2, 30.2, 24], C.dark);
  box([-6.3, 25.4, 21], [6.3, 26.4, 23.5], C.orange);
  for (const x of [-4.6, 4.6]) cyl([x, 28.2, 24], [x, 28.2, 26], 2.6, C.black);   // barrel collars
}
function buildMgBarrel(x) {
  frame = IDENT;
  cyl([x, 28.2, 22], [x, 28.2, 33], 1.9, C.gun); cyl([x, 28.2, 26], [x, 28.2, 29], 2.3, C.dark);   // barrel + heat sleeve
  cyl([x, 28.2, 31.6], [x, 28.2, 33.2], 2.2, C.orange); cyl([x, 28.2, 29.5], [x, 28.2, 33.4], 0.9, null);   // muzzle ring, bore
}
function buildRocket() {   // two-tube rocket pod: low and long so it never shades the nose light
  frame = IDENT; knuckle();
  shape([-6.8, 20.6, 15], [6.8, 29, 34], p => Math.abs(p[0]) <= 6.6 - Math.max(0, p[1] - 27.5) * 0.8 && p[1] >= 20.8 && p[1] <= 28.8 && p[2] >= 15.5 && p[2] <= 33.5, C.yellow);
  box([-6.9, 20.6, 15], [6.9, 22.2, 33.6], C.dark);
  for (const z of [26, 28]) box([-6.9, 22.3, z], [6.9, 28.6, z + 0.9], C.black);   // hazard band
  box([-6.9, 25.8, 30.4], [6.9, 26.6, 31.8], C.orange);
  for (const x of [-3.3, 3.3]) {
    cyl([x, 25, 31.5], [x, 25, 34.6], 2.9, C.gun); cyl([x, 25, 16], [x, 25, 34.8], 2.0, null);   // tube lip, bore
    cyl([x, 25, 14.6], [x, 25, 16.2], 2.6, C.black);   // exhaust cap
  }
}
function buildShotgun() {   // heavy single barrel over a pump magazine
  frame = IDENT; knuckle();
  box([-4.6, 23.6, 17.5], [4.6, 30, 25.5], C.gun); box([-4.7, 28.8, 18], [4.7, 30, 25], C.dark);
  box([-4.8, 25, 21.5], [4.8, 26, 24], C.orange);
  cyl([0, 27.6, 24], [0, 27.6, 38.4], 2.2, C.gun); cyl([0, 27.6, 35.6], [0, 27.6, 38.6], 2.6, C.dark);   // barrel, muzzle brake
  for (const z of [36.2, 37.6]) box([-2.8, 26.8, z], [2.8, 28.4, z + 0.5], null);   // brake ports
  cyl([0, 27.6, 30], [0, 27.6, 38.8], 1.1, null);   // bore
  for (let z = 26; z <= 34; z += 2) box([-1.2, 29.6, z], [1.2, 30.4, z + 0.8], C.dark);   // heat-shield ribs
  cyl([0, 24.2, 25.5], [0, 24.2, 35.5], 1.4, C.steel);   // magazine tube
}
// Multi-gun (skill): 1, 2 or 3 guns side by side on one hinge axis. GUNS[n-1] = gun centre x (voxels).
const GUNS = [[0], [-8, 8], [-15, 0, 15]];
function buildMountUnder(xs = [0]) {   // clevis under the flashlight: cheeks per gun + one hinge pin (wide yoke for several)
  frame = IDENT; const w = Math.max(...xs.map(Math.abs)) + 7.8;
  for (const x of xs) for (const s of [-1, 1]) box([x + (s > 0 ? 6.4 : -7.8), 23.5, 16.5], [x + (s > 0 ? 7.8 : -6.4), 29, 23], C.gun);
  if (xs.length > 1) { box([-w, 28.2, 16.5], [w, 29.6, 22], C.gun); box([-w + 1, 29.6, 17.5], [w - 1, 30.4, 21], C.dark); box([-w, 28.4, 19], [w, 29.2, 19.6], C.orange); }
  cyl([-w - 0.1, HINGE[1], HINGE[2]], [w + 0.1, HINGE[1], HINGE[2]], 1.1, C.steel);
}
function buildMountTop(xs = [0]) {   // deck turret: ring, pylon and clevis(es) carrying the hinge high above the hull
  frame = IDENT; const [, hy, hz] = TOP_HINGE; const w = Math.max(...xs.map(Math.abs)) + 7.8;
  cyl([0, 39.4, hz], [0, 40.6, hz], 5.6, C.gun); cyl([0, 40.6, hz], [0, 41.2, hz], 4.6, C.orange);
  box([-2.6, 40.6, hz - 2.6], [2.6, hy - 2.5, hz + 2.6], C.dark);
  for (const x of xs) for (const s of [-1, 1]) box([x + (s > 0 ? 6.4 : -7.8), hy - 4.5, hz - 3], [x + (s > 0 ? 7.8 : -6.4), hy + 2.6, hz + 3], C.gun);
  box([-w, hy - 5, hz - 3], [w, hy - 3.6, hz + 3], C.gun);
  if (xs.length > 1) {   // braced yoke: diagonal struts down to the ring, hazard stripe along the beam
    for (const s of [-1, 1]) for (let t = 0; t <= 1; t += 0.05) { const x = s * (2.6 + (w - 6) * t), y = 41 + (hy - 6 - 41) * t; box([x - 0.9, y - 0.9, hz - 1.6], [x + 0.9, y + 0.9, hz + 1.6], C.dark); }
    box([-w, hy - 5.2, hz + 3], [w, hy - 4.4, hz + 3.6], C.orange);
  }
  cyl([-w - 0.1, hy, hz], [w + 0.1, hy, hz], 1.1, C.steel);
}
// ---------------------------------------------------------------- upgrade attachments (skills)
// Rigid on the body. Armor levels are cumulative pieces; the scanner dish spins about its own vertical axis.
function rivets(x, ys, zs, c = C.steel) { for (const y of ys) for (const z of zs) box([x - 0.5, y - 0.5, z - 0.5], [x + 0.5, y + 0.5, z + 0.5], c); }
function buildArmor1() {   // bolted side panels between the hips, hazard edge
  frame = IDENT;
  for (const s of [-1, 1]) for (const [z0, z1] of [[3.5, 11.5], [-11.5, -3.5]]) {
    const x0 = s * 13.6, x1 = s * 15.2;
    box([Math.min(x0, x1), 27.4, z0], [Math.max(x0, x1), 36.6, z1], C.steel);
    box([Math.min(x0, x1) - 0.2, 27.2, z0], [Math.max(x0, x1) + 0.2, 28.4, z1], C.orange); box([Math.min(x0, x1) - 0.2, 35.6, z0], [Math.max(x0, x1) + 0.2, 36.8, z1], C.dark);
    for (let z = z0 + 1.5; z < z1 - 1; z += 3) box([Math.min(x0, x1) - 0.3, 31, z], [Math.max(x0, x1) + 0.3, 32.2, z + 1.4], C.orange);
    rivets(s * 15.4, [30, 35], [z0 + 1.2, z1 - 1.2]);
  }
}
function buildArmor2() {   // glacis over the nose + front shoulder pauldrons
  frame = IDENT;
  shape([-11, 36, 12], [11, 41.5, 24], p => p[1] >= 37.2 + (p[2] - 12) * 0.12 && p[1] <= 39.4 + (p[2] - 12) * 0.12 - Math.max(0, p[2] - 21) * 0.9 && Math.abs(p[0]) <= 10.5 - Math.max(0, p[2] - 16) * 0.8 && p[2] >= 12 && p[2] <= 24, C.gun);
  for (const x of [-6, 0, 6]) box([x - 0.4, 38.4, 13], [x + 0.4, 40.6, 20], C.dark);   // ribs
  for (const s of [-1, 1]) {
    shape([s * 9, 36, 13], [s * 16.5, 41, 21], p => { const dx = Math.abs(p[0]) - 9, dz = p[2] - 17; return p[0] * s > 0 && dx >= 0 && dx <= 7.5 && Math.abs(dz) <= 3.8 && p[1] >= 36.4 && p[1] <= 40.2 - dx * 0.35; }, C.gun);
    box([s > 0 ? 9 : -16.6, 36.2, 20.6], [s > 0 ? 16.6 : -9, 37, 21.2], C.orange);
  }
}
function buildArmor3() {   // heavy: rear quarter plates, spine ridge, lower skirts
  frame = IDENT;
  for (const s of [-1, 1]) {
    box([s > 0 ? 12.4 : -14.4, 28, -23], [s > 0 ? 14.4 : -12.4, 36.8, -17.5], C.gun);
    box([s > 0 ? 13.2 : -15.4, 24.4, -11], [s > 0 ? 15.4 : -13.2, 27.6, 11], C.dark);
    rivets(s * 15.6, [26], [-9, -4, 4, 9]);
  }
  box([-3, 39.2, -16], [3, 40.8, 2], C.gun); for (let z = -15; z <= 1; z += 4) box([-3.2, 40.8, z], [3.2, 42, z + 1.6], C.dark);
  box([-3.1, 39.2, -16.6], [3.1, 40, -16], C.orange);
}
function buildScannerMast() {   // rear right: mast, base collar, status LED
  frame = IDENT;
  cyl([9, 38.6, -14], [9, 40, -14], 3.2, C.gun); cyl([9, 40, -14], [9, 53, -14], 1.2, C.steel); cyl([9, 51.6, -14], [9, 53.4, -14], 2, C.dark);
  box([10.3, 45, -14.5], [11.1, 45.8, -13.5], C.beacon);
}
function buildScannerDish() {   // parabolic dish (r 9) + feed horn on a tripod, counterweight: centred on its spin axis
  frame = IDENT; const o = [9, 54, -14];
  shape([-1, 52, -26], [19, 72, -2], p => { const d = sub(p, o), r = Math.hypot(d[0], d[1] - 8.5), z = d[2]; return z >= -2 + r * r * 0.03 && z <= -0.6 + r * r * 0.03 && r <= 9; }, C.chrome);
  shape([-1, 52, -26], [19, 72, -2], p => { const d = sub(p, o), r = Math.hypot(d[0], d[1] - 8.5), z = d[2]; return z >= -2.6 + r * r * 0.03 && z < -2 + r * r * 0.03 && r <= 9 && r >= 7.6; }, C.orange);   // rim
  box([8, 53.4, -15], [10, 55.6, -13], C.dark);   // yoke on the mast top
  for (const [x, y] of [[6, 62.5], [12, 62.5], [9, 58]]) cyl([x, y, -14 + (Math.hypot(x - 9, y - 62.5) ** 2) * 0.03 - 1.3], [9, 62.5, -6.5], 0.5, C.steel);
  cyl([9, 62.5, -7.4], [9, 62.5, -5.6], 1.3, C.dark); box([8.4, 61.9, -5.8], [9.6, 63.1, -5], C.beacon);
  cyl([9, 56, -15], [9, 56, -21], 0.7, C.steel); box([7.6, 54.6, -22.4], [10.4, 57.4, -20.6], C.dark);   // counterweight: keeps the bounds centre (spin axis) on the mast
}
function buildOptic() {   // targeting optic on the right shoulder: armoured box, red lens, cooling fins
  frame = IDENT;
  box([7, 38.6, 13], [12.4, 40, 19], C.dark);
  box([7.4, 40, 13.6], [12, 44.6, 21], C.gun); box([7.2, 44.6, 14], [12.2, 45.4, 20.6], C.dark);
  cyl([9.7, 42.3, 20.4], [9.7, 42.3, 22.2], 2.0, C.black); cyl([9.7, 42.3, 21.6], [9.7, 42.3, 22.6], 1.3, C.laser);
  for (let z = 14.4; z <= 18.4; z += 1.6) box([12, 40.6, z], [12.8, 44, z + 0.7], C.steel);
}
function buildCoolantCell() {   // one canister on the rear left deck: glass shell, glowing core, caps (drawn 1-3x)
  frame = IDENT;
  cyl([-9.5, 38.8, -6], [-9.5, 40, -6], 2.6, C.dark); cyl([-9.5, 40, -6], [-9.5, 46, -6], 2.2, C.glass); cyl([-9.5, 40, -6], [-9.5, 46, -6], 1.4, C.coolant);
  cyl([-9.5, 46, -6], [-9.5, 47.2, -6], 2.6, C.dark); box([-10, 47.2, -6.5], [-9, 48, -5.5], C.steel);
}
function buildThrusters() {   // dash: twin nozzles under the tail grille
  frame = IDENT;
  for (const x of [-6.5, 6.5]) {
    box([x - 3, 26.2, -24], [x + 3, 30, -20], C.dark);
    cyl([x, 28, -24], [x, 28, -27.4], 2.6, C.gun, 3.1); cyl([x, 28, -24.6], [x, 28, -27.6], 1.8, null); cyl([x, 28, -24.4], [x, 28, -24.9], 1.8, C.thrust);
  }
}
const UPGRADES = [['armor-1', buildArmor1], ['armor-2', buildArmor2], ['armor-3', buildArmor3], ['scanner-mast', buildScannerMast], ['scanner-dish', buildScannerDish],
  ['optic', buildOptic], ['coolant-cell', buildCoolantCell], ['thrusters', buildThrusters]];
// Effect anchors (rig space): the laser leaves the optic lens, dash flames leave the nozzles.
const ANCHORS = { optic: [[9.7, 42.3, 22.8]], thrusters: [[-6.5, 28, -27.8], [6.5, 28, -27.8]] };
// Rocket projectile: slim body along +z, ogive nose, four fins, glowing exhaust (materials rule).
function buildRocketRound() {
  frame = IDENT;
  cyl([0, 0, -7], [0, 0, 6], 1.6, C.steel); cyl([0, 0, 1], [0, 0, 3], 1.75, C.orange);
  shape([-2, -2, 6], [2, 2, 10], p => Math.hypot(p[0], p[1]) <= 1.6 * Math.sqrt(Math.max(0, 1 - (p[2] - 6) / 4)), C.dark);
  for (const [x, y] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) box([x ? Math.min(0, 3.2 * x) : -0.4, y ? Math.min(0, 3.2 * y) : -0.4, -7], [x ? Math.max(0, 3.2 * x) : 0.4, y ? Math.max(0, 3.2 * y) : 0.4, -4], C.gun);
  cyl([0, 0, -8.6], [0, 0, -7], 1.2, C.exhaust);
}
function buildShotgunPump() {
  frame = IDENT;
  cyl([0, 24.2, 27.5], [0, 24.2, 32.5], 2.3, C.black);
  for (const z of [28.2, 29.8, 31.4]) cyl([0, 24.2, z], [0, 24.2, z + 0.7], 2.6, C.orange);
}
const WEAPONS = [
  { name: 'mg', parts: [['weapon-mg', 'base', buildMg], ['weapon-mg-barrel0', 'barrel', () => buildMgBarrel(-4.6)], ['weapon-mg-barrel1', 'barrel', () => buildMgBarrel(4.6)]],
    muzzles: [[-4.6, 28.2, 33.4], [4.6, 28.2, 33.4]] },
  { name: 'rocket', parts: [['weapon-rocket', 'base', buildRocket]], muzzles: [[-3.3, 25, 34.8], [3.3, 25, 34.8]] },
  { name: 'shotgun', parts: [['weapon-shotgun', 'base', buildShotgun], ['weapon-shotgun-pump', 'pump', buildShotgunPump]], muzzles: [[0, 27.6, 38.8]] },
];

const MOUNTS = [
  { name: 'under', hinge: HINGE, fold: 1, parts: [['mount-under', 'mount', () => buildMountUnder()]], build: buildMountUnder },
  { name: 'top', hinge: TOP_HINGE, fold: -1, parts: [['mount-top', 'mount', () => buildMountTop()]], build: buildMountTop },
];

const PARTS = [
  ['body', '', [0, HIP_Y, 0], buildBody],
  ['antenna', 'body', [-7, 40, -18], buildAntenna],
];
LEGS.forEach((l, i) => {
  PARTS.push([`leg${i}.coxa`, 'body', [l.o[0], HIP_Y, l.o[2]], () => buildCoxa(l)]);
  PARTS.push([`leg${i}.femur`, `leg${i}.coxa`, at(l, FEMUR), () => buildFemur(l)]);
  PARTS.push([`leg${i}.tibia`, `leg${i}.femur`, at(l, KNEE), () => buildTibia(l)]);
});

fs.mkdirSync(DIR, { recursive: true });
for (const f of fs.readdirSync(DIR)) if (f.endsWith('.vpt.json')) fs.unlinkSync(`${DIR}/${f}`);
const built = PARTS.map(([name, parent, joint, build]) => { shapes = []; build(); return { name, parent, joint, cells: raster(shapes) }; });
const all = new Map(); for (const p of built) for (const [k, v] of p.cells) all.set(k, v);
const model = bounds(all);
const rigParts = built.map(p => {
  const b = bounds(p.cells), q = [p.cells.values().next().value[0], 0, 0];
  const shift = engine(q, model).map((v, i) => Math.round((v - engine(q, b)[i]) * 10000) / 10000);
  const n = writeAsset(`${DIR}/${p.name}.vpt.json`, p.cells);
  console.log(`  ${p.name}: ${n} voxels`);
  return { name: p.name, asset: `${DIR}/${p.name}.vpt.json`, parent: p.parent, shift, joint: engine(p.joint, model) };
});
// Weapon attachments: each piece's local origin (centre x/z, min y of its voxels) in rig space, plus hinge/muzzles.
const half = (lo, hi) => lo + (hi - lo + 1) / 2;
const weaponFile = { version: 1, hinge: engine(HINGE.map((v, i) => i === 1 ? v : v), model), weapons: WEAPONS.map(w => ({
  name: w.name,
  parts: w.parts.map(([file, role, build]) => {
    shapes = []; build(); const cells = raster(shapes), b = bounds(cells);
    const n = writeAsset(`${DIR}/${file}.vpt.json`, cells); console.log(`  ${file}: ${n} voxels`);
    return { asset: `${DIR}/${file}.vpt.json`, role, at: engine([half(b.lo[0], b.hi[0]), b.lo[1], half(b.lo[2], b.hi[2])], model) };
  }),
  muzzles: w.muzzles.map(m => engine(m, model)),
})), mounts: MOUNTS.map(m => ({ name: m.name, fold: m.fold, hinge: engine(m.hinge, model),
  parts: m.parts.map(([file, role, build]) => {
    shapes = []; build(); const cells = raster(shapes), b = bounds(cells);
    const n = writeAsset(`${DIR}/${file}.vpt.json`, cells); console.log(`  ${file}: ${n} voxels`);
    return { asset: `${DIR}/${file}.vpt.json`, role, at: engine([half(b.lo[0], b.hi[0]), b.lo[1], half(b.lo[2], b.hi[2])], model) };
  }),
  // multi-gun mounts: guns = gun centre offsets in metres (x), part = the widened yoke for that count
  multi: GUNS.map((xs, i) => {
    shapes = []; m.build(xs); const cells = raster(shapes), b = bounds(cells), file = `mount-${m.name}-${i + 1}`;
    const n = writeAsset(`${DIR}/${file}.vpt.json`, cells); console.log(`  ${file}: ${n} voxels`);
    return { guns: xs.map(x => x * VOXEL), asset: `${DIR}/${file}.vpt.json`, at: engine([half(b.lo[0], b.hi[0]), b.lo[1], half(b.lo[2], b.hi[2])], model) };
  }) })),
  upgrades: UPGRADES.map(([file, build]) => {
    shapes = []; build(); const cells = raster(shapes), b = bounds(cells);
    const n = writeAsset(`${DIR}/${file}.vpt.json`, cells); console.log(`  ${file}: ${n} voxels`);
    return { name: file, asset: `${DIR}/${file}.vpt.json`, at: engine([half(b.lo[0], b.hi[0]), b.lo[1], half(b.lo[2], b.hi[2])], model),
      anchors: (ANCHORS[file] || []).map(q => engine(q, model)) };
  }) };
{ shapes = []; buildRocketRound(); const cells = raster(shapes); console.log(`  projectile-rocket: ${writeAsset(`${DIR}/projectile-rocket.vpt.json`, cells)} voxels`); }
fs.writeFileSync('maintenance-hexapod.weapons.json', JSON.stringify(weaponFile, null, 1) + '\n');
const total = writeAsset('maintenance-hexapod.vpt.json', all);
fs.mkdirSync('vox', { recursive: true }); writeVox('vox/maintenance-hexapod.vox', all, model);
fs.writeFileSync('maintenance-hexapod.rig.json', JSON.stringify({ version: 1, name: 'maintenance-hexapod', parts: rigParts }, null, 1) + '\n');
// Tripod gait: L0,R1,L2 step together, then R0,L1,R2.
const tripod = [0, 1, 0, 1, 0, 1];
const anim = {
  version: 1,
  locomotion: { speed: 3.2, turn_rate: 420, accel: 14, body_height: 0, ground_follow: true, accel_pitch: 0.03, turn_roll: -0.025 },   // snappy: quick to full speed
  legs: LEGS.map((l, i) => ({ chain: [`leg${i}.coxa`, `leg${i}.femur`, `leg${i}.tibia`], foot: engine(at(l, FOOT), model), group: tripod[i] })),
  gait: { stride: 0.7, lift: 0.14, step_time: 0.2 },   // long legs: big, fast steps
  // Whole-body look: the chassis yaws/pitches/rolls on planted feet; the long legs absorb up to ~40 deg
  // nose-up, so the flashlight (fixed in the nose) can light the tops of walls.
  look: { part: 'body', yaw_limit: 30, pitch_min: -24, pitch_max: 40, stiffness: 10, scan_min: 1.4, scan_max: 3.4, scan_range: 75, lean: 0.05, crouch: 0.16, roll: 6 },
  springs: [{ part: 'antenna', stiffness: 14, damping: 0.9, gain: 30 }],
  bob: { part: 'body', amount: 0.014 },
};
fs.writeFileSync('maintenance-hexapod.anim.json', JSON.stringify(anim, null, 1) + '\n');
// Colour rules (parts folder + static proxy). Two light sources only:
//   flashlight: one spot along the nose (pitch 0, so it hits what the body aims at), warm white;
//   mast tip: glows in the dark and blinks, casts no light (range < 0.4 m).
const rules = { materials: [
  { color: C.glass.slice(0, 3), glass: 1, tint: 0.25 },
  { color: C.head.slice(0, 3), glow: 6, light: [255, 226, 186], cone: 34, pitch: 0, yaw: 0, range: 20 },   // warm white
  { color: C.beacon.slice(0, 3), glow: 1.5, range: 0.3, blink: 1.1 },
  { color: C.exhaust.slice(0, 3), glow: 5, range: 0.3 },   // rocket exhaust: glow only, the game adds one light per rocket
  { color: C.laser.slice(0, 3), glow: 4, range: 0.3 },     // targeting optic lens
  { color: C.coolant.slice(0, 3), glow: 1.6, range: 0.3 }, // regen coolant core
  { color: C.thrust.slice(0, 3), glow: 2.5, range: 0.3 },  // dash thruster throat
] };
const ruleText = '{"version":1,"materials":[\n' + rules.materials.map(r => '  ' + JSON.stringify(r)).join(',\n') + '\n]}\n';
fs.writeFileSync(`${DIR}/materials.json`, ruleText); fs.writeFileSync('maintenance-hexapod.materials.json', ruleText);  // static proxy
const catalog = JSON.parse(fs.readFileSync('catalog.json', 'utf8'));
const list = Array.isArray(catalog) ? catalog : catalog.assets;
const entry = list && list.find(e => e.name === 'maintenance-hexapod');
if (entry) {
  entry.voxel_size = VOXEL; entry.dimensions = [0, 2, 1].map(i => model.hi[i] - model.lo[i] + 1); entry.voxels = total;
  entry.description = 'MH-6 Mk2 industrial hexapod: 18 servo joints on long legs, safety-yellow armour, one nose flashlight (spot), folding weapon hardpoint (twin cannon / rocket pod / shotgun attachments), blinking green mast tip. Rig: maintenance-hexapod.rig.json.';
  fs.writeFileSync('catalog.json', JSON.stringify(catalog, null, 2) + '\n');
}
const W = model.hi.map((v, i) => ((v - model.lo[i] + 1) * VOXEL).toFixed(2));
console.log(`maintenance-hexapod: ${total} voxels, ${W[0]} x ${W[1]} x ${W[2]} m, ${rigParts.length} parts`);
