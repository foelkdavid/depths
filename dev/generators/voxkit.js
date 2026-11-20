// Shared voxel authoring toolkit for the organic generators (build-crawlers.js, build-wastes.js).
// Authoring space = engine voxel space (x right, y up, z forward); shapes are tested at voxel centres.
// Usage: const K = require('./voxkit.js'); K.begin(); ...shapes...; const cells = K.raster(K.take());
'use strict';
const fs = require('fs');
// ---------------------------------------------------------------- math
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const len = a => Math.hypot(a[0], a[1], a[2]);
const lerp = (a, b, t) => a + (b - a) * t;
const lerp3 = (a, b, t) => [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
const mix = (a, b, t) => [0, 1, 2].map(i => Math.round(lerp(a[i], b[i], Math.max(0, Math.min(1, t)))));
function hash(x, y, z) { return (Math.imul(x, 73856093) ^ Math.imul(y, 19349663) ^ Math.imul(z, 83492791)) >>> 0; }
function rnd(x, y, z) { return (hash(x | 0, y | 0, z | 0) % 10007) / 10007; }
// Smooth value noise in [0,1].
function noise(p, s) {
  const q = p.map(v => v / s), i = q.map(Math.floor), f = q.map((v, k) => { const t = v - i[k]; return t * t * (3 - 2 * t); });
  let r = 0;
  for (let k = 0; k < 8; k++) {
    const w = (k & 1 ? f[0] : 1 - f[0]) * (k & 2 ? f[1] : 1 - f[1]) * (k & 4 ? f[2] : 1 - f[2]);
    r += w * rnd(i[0] + (k & 1), i[1] + (k >> 1 & 1), i[2] + (k >> 2 & 1));
  }
  return r;
}
// Quadratic/cubic Bezier sampled into a polyline.
function curve(pts, n = 14) {
  const out = [];
  for (let i = 0; i <= n; i++) {
    let p = pts.slice(), t = i / n;
    while (p.length > 1) { const q = []; for (let k = 0; k + 1 < p.length; k++) q.push(lerp3(p[k], p[k + 1], t)); p = q; }
    out.push(p[0]);
  }
  return out;
}

// ---------------------------------------------------------------- shapes: fn(p) -> colour | null (carve) | undefined (outside)
let shapes = [];
function begin() { shapes = []; }
function take() { const s = shapes; shapes = []; return s; }
function shape(lo, hi, fn) { shapes.push({ lo, hi, fn }); }
const paint = (c, p, info) => typeof c === 'function' ? c(p, info) : c;
// Lumpy ellipsoid: radius modulated by noise (amp) for an organic, asymmetric surface.
function blob(o, r, c, amp = 0, scale = 4) {
  const m = Math.max(...r) * (1 + amp);
  shape(sub(o, [m, m, m]), add(o, [m, m, m]), p => {
    const q = [(p[0] - o[0]) / r[0], (p[1] - o[1]) / r[1], (p[2] - o[2]) / r[2]], d = Math.sqrt(dot(q, q));
    if (d > 1 + amp * (noise(p, scale) * 2 - 1)) return undefined;
    return paint(c, p, { q, d });
  });
}
// Tapered tube along a polyline: radius r0 at the start to r1 at the end; info.t is 0..1 along it.
function tube(points, r0, r1, c) {
  // Below ~0.75 voxel a tube breaks into disconnected voxels: clamp so thin limbs stay solid.
  r0 = Math.max(r0, 0.75); r1 = Math.max(r1, 0.75);
  const seg = [], total = points.slice(1).reduce((s, p, i) => s + len(sub(p, points[i])), 0);
  let acc = 0;
  for (let i = 0; i + 1 < points.length; i++) { const l = len(sub(points[i + 1], points[i])); seg.push({ a: points[i], b: points[i + 1], t0: acc / total, t1: (acc + l) / total }); acc += l; }
  const r = Math.max(r0, r1) + 0.5;
  const lo = [0, 1, 2].map(k => Math.min(...points.map(p => p[k])) - r), hi = [0, 1, 2].map(k => Math.max(...points.map(p => p[k])) + r);
  shape(lo, hi, p => {
    let best = undefined, bt = 0, bd = Infinity;
    for (const s of seg) {
      const ab = sub(s.b, s.a), l2 = dot(ab, ab); let u = l2 ? dot(sub(p, s.a), ab) / l2 : 0; u = Math.max(0, Math.min(1, u));
      const d = len(sub(p, add(s.a, mul(ab, u)))), t = lerp(s.t0, s.t1, u), rad = lerp(r0, r1, t);
      if (d <= rad && d - rad < bd) { bd = d - rad; bt = t; best = true; }
    }
    return best ? paint(c, p, { t: bt }) : undefined;
  });
}
function spike(a, b, r, c) { tube([a, b], r, 0.25, c); }

function raster(list) {
  const cells = new Map();
  for (const s of list)
    for (let x = Math.floor(s.lo[0]) - 1; x <= Math.ceil(s.hi[0]); x++)
      for (let y = Math.floor(s.lo[1]) - 1; y <= Math.ceil(s.hi[1]); y++)
        for (let z = Math.floor(s.lo[2]) - 1; z <= Math.ceil(s.hi[2]); z++) {
          const p = [x + 0.5, y + 0.5, z + 0.5], c = s.fn(p);
          if (c === undefined) continue;
          const key = `${x},${y},${z}`;
          if (c === null) { cells.delete(key); continue; }
          let v = c.slice(0, 3);
          if (!c[3]) {
            // Organic mottling: smooth blotches plus fine speckle, quantized for the .vox palette.
            const m = Math.round((noise(p, 3.5) - 0.5) * 5) * 4 + ((hash(x, y, z) % 3) - 1) * 3;
            v = v.map(k => Math.max(0, Math.min(255, k + m)));
          }
          cells.set(key, [x, y, z, v[0], v[1], v[2], c[3] ? 1 : 0]);
        }
  return cells;
}

// ---------------------------------------------------------------- export (same conventions as build-hexapod.js)
function bounds(cells) {
  const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
  for (const v of cells.values()) for (let i = 0; i < 3; i++) { lo[i] = Math.min(lo[i], v[i]); hi[i] = Math.max(hi[i], v[i]); }
  return { lo, hi };
}
function engine(p, b, s) {
  return [0, 1, 2].map(i => Math.round(((p[i] - b.lo[i]) * s - (i === 1 ? 0 : (b.hi[i] - b.lo[i] + 1) * s / 2)) * 10000) / 10000);
}
function writeAsset(file, cells, s) {
  const rows = Array.from(cells.values()).sort((a, b) => a[1] - b[1] || a[2] - b[2] || a[0] - b[0]);
  for (const r of rows) if (!r[6]) r.length = 6;
  fs.writeFileSync(file, JSON.stringify({ version: 1, voxel_size: s, up: 'y', voxels: rows }));
  return rows.length;
}
function writeVox(file, cells, b) {
  const pal = new Map(), xyzi = [];
  for (const v of cells.values()) {
    let c = v.slice(3, 6);
    // VOX palettes hold 255 colours: fold mottling into 8-level steps if needed.
    let key = c.join(','); if (!pal.has(key) && pal.size >= 255) { c = c.map(k => Math.min(255, Math.round(k / 24) * 24)); key = c.join(','); }
    if (!pal.has(key)) { if (pal.size >= 255) key = pal.keys().next().value; else pal.set(key, pal.size + 1); }
    xyzi.push([v[0] - b.lo[0], b.hi[2] - v[2], v[1] - b.lo[1], pal.get(key)]);
  }
  const size = [b.hi[0] - b.lo[0] + 1, b.hi[2] - b.lo[2] + 1, b.hi[1] - b.lo[1] + 1];
  const chunk = (id, data) => { const h = Buffer.alloc(12); h.write(id, 0); h.writeInt32LE(data.length, 4); return Buffer.concat([h, data]); };
  const sz = Buffer.alloc(12); size.forEach((v, i) => sz.writeInt32LE(v, i * 4));
  const xy = Buffer.alloc(4 + xyzi.length * 4); xy.writeInt32LE(xyzi.length, 0); xyzi.forEach((v, i) => v.forEach((c, k) => xy.writeUInt8(c, 4 + i * 4 + k)));
  const rgba = Buffer.alloc(1024); for (const [key, i] of pal) key.split(',').map(Number).concat(255).forEach((c, k) => rgba.writeUInt8(c, (i - 1) * 4 + k));
  const children = Buffer.concat([chunk('SIZE', sz), chunk('XYZI', xy), chunk('RGBA', rgba)]);
  const main = Buffer.alloc(12); main.write('MAIN', 0); main.writeInt32LE(children.length, 8);
  const head = Buffer.alloc(8); head.write('VOX ', 0); head.writeInt32LE(150, 4);
  fs.writeFileSync(file, Buffer.concat([head, main, children]));
}
module.exports = { add, sub, mul, dot, len, lerp, lerp3, mix, hash, rnd, noise, curve, shape, paint, blob, tube, spike, raster, bounds, engine, writeAsset, writeVox, begin, take };
