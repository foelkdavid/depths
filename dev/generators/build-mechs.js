#!/usr/bin/env node
// Player mechs besides the MH-6 "Rattler" (build-hexapod.js): BR-4 "Mortar" (artillery quadruped, rocket
// launcher) and CQ-1 "Maul" (low eight-legged rusher behind a shield, double-barrel shotgun).
// Run from anywhere: node dev/generators/build-mechs.js   (--force: back up edited outputs, then overwrite)
//
// Per mech: parts-<id>/*.vpt.json, <name>.{vpt,rig,anim,materials,weapons}.json, vox/<name>.vox, catalog entry.
// Same conventions as build-hexapod.js: engine voxel space (x right, y up, z forward), one unit = VOXEL m,
// legs are coxa (yaw) + femur/tibia hinged in the vertical leg plane. The weapon is ONE attachment per mech,
// authored around its hinge (weapons.json: one weapon, one fixed mount, no upgrades).
'use strict';
// Outputs live in the asset folder; this script lives in dev/generators/.
process.chdir(require('path').join(__dirname, '../../assets/library/BLACK_START'));
const fs = require('fs');
require('./generated-guard.js').start('build-mechs', { skip: ['catalog.json'], dirs: ['parts-mortar', 'parts-maul'] });
const VOXEL = 0.02;

// ---------------------------------------------------------------- palette (shared with the MH-6)
const C = {
  yellow: [236, 166, 22], amber: [228, 128, 18], orange: [214, 92, 20], rust: [168, 70, 22],
  gun: [54, 60, 66], dark: [32, 36, 40], black: [17, 19, 21], rubber: [26, 26, 28],
  steel: [128, 136, 140], chrome: [184, 190, 192], cable: [40, 40, 44],
  head: [240, 236, 210, 1], glass: [150, 196, 214], exhaust: [255, 150, 60, 1],
  eye: [255, 40, 20, 1], beacon: [255, 170, 30, 1],
};
const PLAIN = new Set([C.glass]);

// ---------------------------------------------------------------- vector + shape helpers
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const len = a => Math.hypot(a[0], a[1], a[2]);
const norm = a => mul(a, 1 / len(a));
const IDENT = { o: [0, 0, 0], u: [1, 0, 0], v: [0, 1, 0], w: [0, 0, 1] };
let frame = IDENT, shapes = [];
function toLocal(p, f) { const d = sub(p, f.o); return [dot(d, f.u), dot(d, f.v), dot(d, f.w)]; }
function toWorld(p, f) { return add(f.o, add(mul(f.u, p[0]), add(mul(f.v, p[1]), mul(f.w, p[2])))); }
function shape(lo, hi, test, color) { shapes.push({ f: frame, lo, hi, test, color }); }
function box(lo, hi, c) { shape(lo, hi, p => p[0] >= lo[0] && p[0] <= hi[0] && p[1] >= lo[1] && p[1] <= hi[1] && p[2] >= lo[2] && p[2] <= hi[2], c); }
function sphere(o, r, c) { shape(sub(o, [r, r, r]), add(o, [r, r, r]), p => len(sub(p, o)) <= r, c); }
function cyl(a, b, r0, c, r1 = r0) {
  const ab = sub(b, a), l2 = dot(ab, ab), r = Math.max(r0, r1);
  const lo = [0, 1, 2].map(i => Math.min(a[i], b[i]) - r), hi = [0, 1, 2].map(i => Math.max(a[i], b[i]) + r);
  shape(lo, hi, p => {
    const ap = sub(p, a), t = dot(ap, ab) / l2; if (t < 0 || t > 1) return false;
    return len(sub(ap, mul(ab, t))) <= r0 + (r1 - r0) * t;
  }, c);
}
// Slab between a and b in the u/y plane of the current frame: thickness th0->th1, width wd along w.
function strut(a, b, th0, wd, c, th1 = th0, wc = 0) {
  a = [a[0], a[1], 0]; b = [b[0], b[1], 0];
  const d = sub(b, a), l = len(d), t = mul(d, 1 / l), n = [-t[1], t[0], 0];
  const r = Math.max(th0, th1) / 2 + 1;
  shape([Math.min(a[0], b[0]) - r, Math.min(a[1], b[1]) - r, wc - wd / 2], [Math.max(a[0], b[0]) + r, Math.max(a[1], b[1]) + r, wc + wd / 2], p => {
    const q = sub(p, a), s = dot(q, t); if (s < 0 || s > l) return false;
    const th = th0 + (th1 - th0) * s / l; return Math.abs(dot(q, n)) <= th / 2 && Math.abs(p[2] - wc) <= wd / 2;
  }, c);
}
// Diagonal hazard stripes (yellow/black) for a test region: k = stripe period in voxels.
const hazard = (p, k = 6, key = q => q[0] + q[1] + q[2] * 0.3) => (Math.floor(key(p) / k) & 1) ? C.black : C.yellow;
function striped(lo, hi, test, k = 6, key) {   // a shape whose colour alternates in diagonal bands
  for (const c of [C.yellow, C.black]) shape(lo, hi, p => test(p) && hazard(p, k, key) === c, c);
}

// ---------------------------------------------------------------- raster + export
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
            const h = hash(x, y, z), d = ((h % 5) - 2) * 2, scuff = h % 61 === 0 ? -14 : 0;
            v = v.map(c => Math.max(0, Math.min(255, c + d + scuff)));
          }
          cells.set(key, [x, y, z, v[0], v[1], v[2], s.color[3] ? 1 : 0]);
        }
  }
  return cells;
}
function bounds(cells) {
  const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
  for (const v of cells.values()) for (let i = 0; i < 3; i++) { lo[i] = Math.min(lo[i], v[i]); hi[i] = Math.max(hi[i], v[i]); }
  return { lo, hi };
}
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

// ---------------------------------------------------------------- legs
// A leg: coxa axis o (body space, y = hip height), heading dir. FEMUR/KNEE/FOOT are (radial, height) in the
// leg plane. legFrame: local (u radial, y up, w across the leg).
function legFrame(l) { const w = norm([-l.dir[2], 0, l.dir[0]]); return { o: [l.o[0], 0, l.o[2]], u: l.dir, v: [0, 1, 0], w }; }
const at = (l, uy) => toWorld([uy[0], uy[1], 0], legFrame(l));
function makeLegs(spec) {   // spec.place = [[side, z, x, headingDeg], ...]
  return spec.place.map(([s, z, x, deg], j) => {
    const a = deg * Math.PI / 180;
    return { s, j, o: [s * x, spec.hip, z], dir: [s * Math.cos(a), 0, Math.sin(a)] };
  });
}

// ---------------------------------------------------------------- export one mech
function buildMech(m) {
  fs.mkdirSync(m.dir, { recursive: true });
  for (const f of fs.readdirSync(m.dir)) if (f.endsWith('.vpt.json')) fs.unlinkSync(`${m.dir}/${f}`);
  const legs = makeLegs(m.legs);
  const PARTS = [['body', '', [0, m.legs.hip, 0], m.body]];
  legs.forEach((l, i) => {
    PARTS.push([`leg${i}.coxa`, 'body', [l.o[0], m.legs.hip, l.o[2]], () => m.coxa(l)]);
    PARTS.push([`leg${i}.femur`, `leg${i}.coxa`, at(l, m.legs.femur), () => m.femur(l)]);
    PARTS.push([`leg${i}.tibia`, `leg${i}.femur`, at(l, m.legs.knee), () => m.tibia(l)]);
  });
  const built = PARTS.map(([name, parent, joint, build]) => { shapes = []; frame = IDENT; build(); return { name, parent, joint, cells: raster(shapes) }; });
  const all = new Map(); for (const p of built) for (const [k, v] of p.cells) all.set(k, v);
  const model = bounds(all);
  const rigParts = built.map(p => {
    const b = bounds(p.cells), q = [p.cells.values().next().value[0], 0, 0];
    const shift = engine(q, model).map((v, i) => Math.round((v - engine(q, b)[i]) * 10000) / 10000);
    const n = writeAsset(`${m.dir}/${p.name}.vpt.json`, p.cells);
    console.log(`  ${m.name} ${p.name}: ${n} voxels`);
    return { name: p.name, asset: `${m.dir}/${p.name}.vpt.json`, parent: p.parent, shift, joint: engine(p.joint, model) };
  });
  // weapon attachment pieces (rig space origin = centre x/z, min y of the piece's voxels)
  const half = (lo, hi) => lo + (hi - lo + 1) / 2;
  const piece = (file, role, build) => {
    shapes = []; frame = IDENT; build(); const cells = raster(shapes), b = bounds(cells);
    const n = writeAsset(`${m.dir}/${file}.vpt.json`, cells); console.log(`  ${m.name} ${file}: ${n} voxels`);
    return { asset: `${m.dir}/${file}.vpt.json`, role, at: engine([half(b.lo[0], b.hi[0]), b.lo[1], half(b.lo[2], b.hi[2])], model) };
  };
  const hinge = engine(m.weapon.hinge, model);
  const weaponFile = { version: 1, hinge,
    weapons: [{ name: m.weapon.name, parts: m.weapon.parts.map(([f, r, b]) => piece(f, r, b)), muzzles: m.weapon.muzzles.map(q => engine(q, model)) }],
    mounts: [{ name: 'fixed', fold: m.weapon.fold, hinge, parts: [piece(m.weapon.mount[0], 'mount', m.weapon.mount[1])], multi: [] }] };
  fs.writeFileSync(`${m.name}.weapons.json`, JSON.stringify(weaponFile, null, 1) + '\n');
  const total = writeAsset(`${m.name}.vpt.json`, all);
  fs.mkdirSync('vox', { recursive: true }); writeVox(`vox/${m.name}.vox`, all, model);
  fs.writeFileSync(`${m.name}.rig.json`, JSON.stringify({ version: 1, name: m.name, parts: rigParts }, null, 1) + '\n');
  const anim = Object.assign({ version: 1 }, m.anim, {
    legs: legs.map((l, i) => ({ chain: [`leg${i}.coxa`, `leg${i}.femur`, `leg${i}.tibia`], foot: engine(at(l, m.legs.foot), model), group: m.legs.group(l, i) })),
  });
  fs.writeFileSync(`${m.name}.anim.json`, JSON.stringify(anim, null, 1) + '\n');
  const ruleText = '{"version":1,"materials":[\n' + m.rules.map(r => '  ' + JSON.stringify(r)).join(',\n') + '\n]}\n';
  fs.writeFileSync(`${m.dir}/materials.json`, ruleText); fs.writeFileSync(`${m.name}.materials.json`, ruleText);
  const catalog = JSON.parse(fs.readFileSync('catalog.json', 'utf8'));
  const list = Array.isArray(catalog) ? catalog : catalog.assets;
  let entry = list.find(e => e.name === m.name); if (!entry) { entry = { name: m.name }; list.push(entry); }
  entry.voxel_size = VOXEL; entry.dimensions = [0, 2, 1].map(i => model.hi[i] - model.lo[i] + 1); entry.voxels = total; entry.description = m.description;
  fs.writeFileSync('catalog.json', JSON.stringify(catalog, null, 2) + '\n');
  const W = model.hi.map((v, i) => ((v - model.lo[i] + 1) * VOXEL).toFixed(2));
  console.log(`${m.name}: ${total} voxels, ${W[0]} x ${W[1]} x ${W[2]} m, ${rigParts.length} parts`);
}

// ================================================================ BR-4 "MORTAR"
// Wide, fat artillery quadruped: a low armoured tub on four huge splayed legs with elephant pads, a turret
// ring on the deck carrying a quad-tube rocket launcher box. Slow, planted, heavy.
const MO = { hip: 30, femur: [13, 32], knee: [27, 43], foot: [38, 0] };
const MO_HINGE = [0, 62, -4];
function moHull(p, g = 0) {   // tub: wide, slab sides tucked in at the bottom, sloped glacis and rear
  const ax = Math.abs(p[0]), y = p[1], z = p[2];
  let half = 25 + g - Math.max(0, 28 - y) * 0.6;
  if (y > 40) half -= (y - 40) * 1.5;
  let front = 27 + g - Math.max(0, y - 34) * 1.1, back = -26 - g + Math.max(0, y - 38) * 0.8;
  return ax <= half && z <= front && z >= back && y >= 22 - g && y <= 45 + g;
}
function mortarBody() {
  // belly + skid plate
  shape([-22, 18, -24], [22, 23, 25], p => Math.abs(p[0]) <= 21 - Math.max(0, 21 - p[1]) && p[1] >= 18.5 && p[2] >= -23 && p[2] <= 24, C.gun);
  shape([-27, 21, -27], [27, 46, 28], p => moHull(p), C.yellow);
  shape([-27, 21, -27], [27, 26, 28], p => moHull(p, 0.4) && p[1] <= 25.2, C.dark);   // dark lower band
  // glacis hazard chevrons
  striped([-27, 33, 18], [27, 46, 28.5], p => moHull(p, 0.5) && !moHull(p, -0.6) && p[2] > 20 && p[1] >= 35 && p[1] <= 43 && Math.abs(p[0]) <= 18, 7);
  // hip sockets: heavy armoured collars at the four corners
  for (const s of [-1, 1]) for (const z of [-17, 17]) {
    cyl([s * 21, 22, z], [s * 21, 40, z], 8.5, null);
    cyl([s * 21, 38, z], [s * 21, 41, z], 9, C.gun); cyl([s * 21, 41, z], [s * 21, 42, z], 7.5, C.orange);
  }
  // side armour skirts with rivets + an orange stencil bar
  for (const s of [-1, 1]) {
    box([s > 0 ? 25 : -27.5, 27, -8], [s > 0 ? 27.5 : -25, 38, 8], C.amber);
    box([s > 0 ? 27.4 : -28, 31, -6], [s > 0 ? 28 : -27.4, 33, 6], C.black);
    for (const z of [-6, 0, 6]) for (const y of [28.5, 36.5]) box([s > 0 ? 27.4 : -28.1, y - 0.5, z - 0.5], [s > 0 ? 28.1 : -27.4, y + 0.5, z + 0.5], C.steel);
  }
  // deck: turret race (the launcher mount sits on it), vents, grab rails
  cyl([0, 44, MO_HINGE[2]], [0, 46.5, MO_HINGE[2]], 14, C.dark);
  for (let x = -20; x <= -12; x += 2.4) box([x, 44, -22], [x + 1.2, 45.6, -12], C.gun);
  for (let x = 12; x <= 20; x += 2.4) box([x, 44, -22], [x + 1.2, 45.6, -12], C.gun);
  for (const s of [-1, 1]) { cyl([s * 19, 46, 6], [s * 19, 46, 16], 0.8, C.steel); for (const z of [6, 16]) cyl([s * 19, 44, z], [s * 19, 46, z], 0.8, C.steel); }
  // front: dark sensor bar with one big flood lamp, two small amber running lights
  shape([-18, 26, 22], [18, 34, 29], p => moHull(p, 0.6) && !moHull(p, -1.2) && p[2] > 22 && p[1] >= 27 && p[1] <= 33.5 && Math.abs(p[0]) <= 17, C.black);
  cyl([0, 30, 25.5], [0, 30, 28.6], 4.4, C.gun); cyl([0, 30, 26.5], [0, 30, 29], 3.3, C.head); cyl([0, 30, 28.6], [0, 30, 29.4], 3.3, C.glass);
  for (const s of [-1, 1]) box([s * 12 - 1.5, 29, 26.5], [s * 12 + 1.5, 31, 28.6], C.beacon);
  // tow hook + rear exhaust stacks
  box([-3, 23, -28], [3, 27, -25], C.dark); cyl([0, 25, -28.5], [0, 25, -27], 1.4, C.steel);
  for (const s of [-1, 1]) { cyl([s * 15, 34, -26], [s * 15, 50, -26], 2.2, C.gun); cyl([s * 15, 48, -26], [s * 15, 50.5, -26], 2.6, C.black); cyl([s * 15, 46, -26], [s * 15, 51, -26], 1.2, null); }
}
function mortarCoxa(l) {   // big yaw drum + a short, very wide yoke
  frame = legFrame(l);
  cyl([0, 24, 0], [0, 38, 0], 7.4, C.gun); cyl([0, 34, 0], [0, 36.4, 0], 7.8, C.orange);
  strut([4, MO.hip + 1], [MO.femur[0] + 1, MO.femur[1]], 11, 13, C.yellow);
  cyl([MO.femur[0], MO.femur[1], -7.5], [MO.femur[0], MO.femur[1], 7.5], 6.4, C.gun);
  for (const w of [-1, 1]) cyl([MO.femur[0], MO.femur[1], w * 7.5], [MO.femur[0], MO.femur[1], w * 8.8], 4.2, C.orange);
}
function mortarFemur(l) {   // massive box beam with twin hydraulic rams underneath
  frame = legFrame(l);
  const a = MO.femur, b = MO.knee, d = norm([b[0] - a[0], b[1] - a[1], 0]), n = [-d[1], d[0]];
  const p = t => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
  const off = (q, s) => [q[0] + n[0] * s, q[1] + n[1] * s];
  strut(p(0.05), p(0.95), 13, 11, C.yellow, 11);
  strut(off(p(0.15), 6.2), off(p(0.85), 5.4), 1.4, 11.6, C.amber);
  strut(off(p(0.3), 0), off(p(0.7), 0), 4, 11.8, C.black);   // stencil band
  for (const w of [-3.4, 3.4]) {
    const h0 = off(p(0.15), -8), h1 = off(p(0.9), -7), mid = [h0[0] + (h1[0] - h0[0]) * 0.55, h0[1] + (h1[1] - h0[1]) * 0.55];
    cyl([h0[0], h0[1], w], [mid[0], mid[1], w], 2.4, C.gun); cyl([mid[0], mid[1], w], [h1[0], h1[1], w], 1.3, C.chrome);
  }
  cyl([MO.knee[0], MO.knee[1], -7], [MO.knee[0], MO.knee[1], 7], 6.8, C.gun);
  for (const w of [-1, 1]) cyl([MO.knee[0], MO.knee[1], w * 7], [MO.knee[0], MO.knee[1], w * 8.4], 4.4, C.orange);
}
function mortarTibia(l) {   // thick column straight down to an elephant pad with toe plates
  frame = legFrame(l);
  const a = MO.knee, f = [MO.foot[0], MO.foot[1] + 5], d = norm([f[0] - a[0], f[1] - a[1], 0]), n = [-d[1], d[0]];
  const p = t => [a[0] + (f[0] - a[0]) * t, a[1] + (f[1] - a[1]) * t];
  const off = (q, s) => [q[0] + n[0] * s, q[1] + n[1] * s];
  strut(p(0.06), p(0.95), 11, 10, C.gun, 8);
  strut(off(p(0.06), 4.6), off(p(0.62), 3.4), 3, 11.4, C.yellow, 2.4);   // shin armour
  strut(off(p(0.06), 6), off(p(0.18), 5.6), 1.4, 11.8, C.orange);
  cyl([...p(0.78), 0], [...p(0.88), 0], 5.6, C.dark);   // ankle collar
  // pad: wide rubber disc + steel rim + three toe plates (in the leg frame; it tilts with the shin a little)
  const fx = MO.foot[0];
  cyl([fx, 0, 0], [fx, 3.4, 0], 8, C.rubber); cyl([fx, 3.4, 0], [fx, 5.4, 0], 7.2, C.steel);
  for (const k of [-1, 0, 1]) { const ang = k * 0.7, dx = Math.cos(ang), dz = Math.sin(ang); box([fx + dx * 6 - 2, 0, dz * 6 - 2], [fx + dx * 6 + 2, 2.6, dz * 6 + 2], C.dark); }
}
// Launcher: authored around MO_HINGE. A long armoured box with four tubes (2 x 2), hazard flanks, sight block.
const MO_TUBES = [-10.6, 0, 10.6].flatMap(x => [57.5, 68.5].map(y => [x, y]));   // 3 x 2 tubes
function mortarLauncher() {
  const [, hy, hz] = MO_HINGE, W = 17.5;
  cyl([-20, hy, hz], [20, hy, hz], 3.4, C.dark);   // trunnion
  const inBox = p => Math.abs(p[0]) <= W && p[1] >= 51.5 && p[1] <= 74.5 && p[2] >= -24 && p[2] <= 27 - Math.max(0, p[1] - 71) * 0.7;
  shape([-W - 1, 51, -25], [W + 1, 75, 28], p => inBox(p), C.yellow);
  striped([-W - 1, 51, -17], [W + 1, 75, 12], p => Math.abs(p[0]) > W - 1 && Math.abs(p[0]) <= W + 0.9 && p[1] >= 54 && p[1] <= 72 && p[2] >= -17 && p[2] <= 12, 5, q => q[1] + q[2]);
  box([-W - 0.3, 51.2, -24.2], [W + 0.3, 53.6, 27.2], C.dark);   // dark lower rim
  box([-W - 0.3, 72.2, -24.2], [W + 0.3, 74.8, -9], C.gun);      // top cover plate
  for (let x = -W + 3; x <= W - 3; x += 4) box([x - 0.6, 74.4, -8], [x + 0.6, 75.4, 20], C.dark);   // top ribs
  for (const z of [-21, 18]) box([-W - 0.5, 51.5, z], [W + 0.5, 74.5, z + 1.8], C.orange);   // end bands
  // front face: dark frame + six tubes with orange-lipped muzzles
  box([-W + 0.4, 52, 25.5], [W - 0.4, 74.6, 27.4], C.dark);
  for (const [x, y] of MO_TUBES) {
    cyl([x, y, 24], [x, y, 29.4], 4.6, C.gun); cyl([x, y, 28.2], [x, y, 29.6], 4.8, C.orange);
    cyl([x, y, -23], [x, y, 29.8], 3.5, null); cyl([x, y, 14], [x, y, 15], 3.5, C.black);   // bore (dark at the back)
  }
  for (const [x, y] of MO_TUBES) cyl([x, y, -25.6], [x, y, -23.4], 4, C.black);   // rear exhaust caps
  // sight block + ranging lens on the left top
  box([-W + 2, 74.5, 6], [-W + 9, 79, 18], C.gun); cyl([-W + 5.5, 76.8, 18], [-W + 5.5, 76.8, 19.6], 1.7, C.glass);
  box([-W + 2, 79, 6], [-W + 9, 79.8, 18], C.orange);
}
function mortarMount() {   // turret ring + two tall armoured cheeks carrying the trunnion
  const [, hy, hz] = MO_HINGE, X0 = 18.4, X1 = 22.8;
  cyl([0, 46, hz], [0, 48.5, hz], 14, C.gun); cyl([0, 48.5, hz], [0, 49.4, hz], 12.5, C.orange);
  box([-X1, 46, hz - 9], [X1, 49, hz + 9], C.dark);   // cross beam the cheeks stand on
  for (const s of [-1, 1]) {
    shape([s > 0 ? X0 - 1 : -X1 - 1, 46, hz - 10], [s > 0 ? X1 + 1 : -X0 + 1, hy + 6, hz + 10], p => Math.abs(p[0]) >= X0 && Math.abs(p[0]) <= X1 && p[1] >= 47 && p[1] <= hy + 5 - Math.abs(p[2] - hz) * 0.3 && Math.abs(p[2] - hz) <= 9 - Math.max(0, p[1] - 49) * 0.25, C.dark);
    cyl([s * X1, hy, hz], [s * (X1 + 1.2), hy, hz], 3.8, C.orange);
  }
}

// ================================================================ CQ-1 "MAUL"
// A low armoured wedge scuttling on eight short legs, all hidden behind a raked riot shield with ram teeth.
// The double barrel pokes out through a port in the shield. Fast and mean.
const MA = { hip: 22, femur: [7, 24], knee: [17, 31], foot: [27, 0] };
const MA_HINGE = [0, 27, 15];
const MA_SHIELD_Z = 21;   // shield face plane at y = 22 (raked back above, forward below)
const shieldZ = y => MA_SHIELD_Z - (y - 22) * 0.32;
function maHull(p, g = 0) {   // wedge: high at the shield, sloping down to a low tail
  const ax = Math.abs(p[0]), y = p[1], z = p[2];
  const top = 33 + g - Math.max(0, -z - 2) * 0.32, half = 14 + g - Math.max(0, y - 29) * 1.2 - Math.max(0, -z - 14) * 0.6;
  return ax <= half && y >= 15 - g && y <= top && z >= -22 - g && z <= 20 + g;
}
// Outline in the face plane (x, y): arrowhead top, tusk corners. inset > 0 shrinks it (for the rim band).
function shieldOutline(x, y, inset = 0) {
  const ax = Math.abs(x);
  return y >= 5 + Math.max(0, ax - 12) * 0.9 + inset && y <= 46 - ax * 0.38 - inset && ax <= 21 - inset;
}
function shieldIn(p, th = 3) {   // raked plate
  const dz = p[2] - shieldZ(p[1]);
  return dz >= 0 && dz <= th && shieldOutline(p[0], p[1]);
}
function maulBody() {
  shape([-14, 13, -22], [14, 17, 19], p => Math.abs(p[0]) <= 12 && p[1] >= 13.5 && p[1] <= 16 && p[2] >= -20 && p[2] <= 18, C.gun);   // belly
  shape([-15, 14, -23], [15, 34, 21], p => maHull(p), C.yellow);
  shape([-15, 14, -23], [15, 19, 21], p => maHull(p, 0.4) && p[1] <= 18.4, C.dark);
  // spine fin + side vents
  shape([-2, 30, -20], [2, 37, 14], p => Math.abs(p[0]) <= 1.4 && p[1] <= 33 + 3 - Math.abs(p[2] + 3) * 0.18 - Math.max(0, -p[2] - 2) * 0.32 && p[1] >= 30, C.dark);
  for (const s of [-1, 1]) for (let z = -16; z <= -4; z += 3) box([s > 0 ? 12.8 : -14.6, 21, z], [s > 0 ? 14.6 : -12.8, 26, z + 1.4], C.black);
  // hip sockets (8 legs: four per side)
  for (const s of [-1, 1]) for (const z of MA_Z) cyl([s * 12, 17, z], [s * 12, 27, z], 4.4, null);
  // tail: hazard stripes and one amber beacon
  striped([-13, 15, -23.5], [13, 30, -20], p => Math.abs(p[0]) <= 12 && p[1] >= 16 && p[1] <= 28 && p[2] >= -23 && p[2] <= -21, 5);
  box([-1.5, 33, -15], [1.5, 35, -12], C.beacon);
  // the shield: safety-yellow plate with black chevrons pointing up at the port, a dark visor band across the
  // top with two angled glowing slits (an angry brow), orange rim, dark back face
  frame = IDENT;
  const SH = [[-22, 3, 8], [22, 46, 28]], face = p => p[2] - shieldZ(p[1]);
  const edge = p => !shieldOutline(p[0], p[1], 1.3);
  shape(...SH, p => shieldIn(p, 3.2), C.yellow);
  shape(...SH, p => shieldIn(p, 3.2) && p[1] < 33 && (Math.floor((p[1] - Math.abs(p[0]) * 0.75) / 4) & 1) === 0, C.black);   // chevrons
  shape(...SH, p => shieldIn(p, 3.2) && p[1] >= 33 && p[1] <= 40.5 - Math.abs(p[0]) * 0.12, C.dark);   // visor band
  shape(...SH, p => shieldIn(p, 3.2) && edge(p), C.orange);   // rim
  shape(...SH, p => shieldIn(p, 3.2) && face(p) <= 0.9, C.dark);   // back face
  // centre crest + eye slits (glow): inner ends low, outer ends high
  shape(...SH, p => Math.abs(p[0]) <= 1.4 && p[1] >= 36 && p[1] <= 43 && face(p) > 2 && face(p) <= 4.4, C.orange);
  for (const s of [-1, 1]) shape(...SH, p => { const ax = p[0] * s, y0 = 34.4 + (ax - 9) * 0.32; return ax >= 9 && ax <= 16.5 && p[1] >= y0 && p[1] <= y0 + 2 && face(p) > 1.2 && face(p) <= 3.6; }, C.eye);
  shape([-8, 20, 10], [8, 34, 30], p => Math.abs(p[0]) <= 6.6 && p[1] >= 21.5 && p[1] <= 32.5 && p[2] >= 10, null);   // barrel port
  shape([-9, 19, 10], [9, 35, 30], p => Math.abs(p[0]) <= 8 && p[1] >= 20 && p[1] <= 34 && !(Math.abs(p[0]) <= 6.6 && p[1] >= 21.5 && p[1] <= 32.5) && shieldIn(p, 4.6) && p[2] - shieldZ(p[1]) > 3.2, C.black);   // port collar
  // ram teeth along the bottom edge, spikes at the tusk corners and the top point
  for (let x = -14; x <= 14; x += 4) { const y = 6 + Math.max(0, Math.abs(x) - 12) * 0.9, z = shieldZ(y) + 3; cyl([x, y + 1.5, z - 1], [x, y - 3, z + 5], 1.6, C.steel, 0.3); }
  for (const s of [-1, 1]) cyl([s * 19, 33, shieldZ(33) + 3], [s * 24, 37, shieldZ(33) + 9], 1.8, C.chrome, 0.2);
  cyl([0, 44.5, shieldZ(44.5) + 3], [0, 50, shieldZ(44.5) + 7], 1.6, C.chrome, 0.2);
  // braces from the shield back into the hull
  for (const s of [-1, 1]) strutBrace([s * 10, 30, 18], [s * 8, 27, 10]);
  // flashlight: a small bezel low left of the port
  cyl([-12, 15.5, shieldZ(15.5) + 2], [-12, 15.5, shieldZ(15.5) + 4.6], 2.6, C.gun); cyl([-12, 15.5, shieldZ(15.5) + 3.2], [-12, 15.5, shieldZ(15.5) + 4.9], 1.9, C.head);
}
function strutBrace(a, b) { cyl(a, b, 1.3, C.dark); }
// Leg sockets: front pair swept forward behind the shield, rear pair swept back.
const MA_Z = [11, 3, -6, -15];
const MA_LEGS = { hip: MA.hip, femur: MA.femur, knee: MA.knee, foot: MA.foot,
  place: [-1, 1].flatMap(s => MA_Z.map((z, j) => [s, z, 12, [38, 12, -14, -42][j]])),
  group: (l, i) => (l.j + (l.s > 0 ? 1 : 0)) % 2 };
function maulCoxa(l) {
  frame = legFrame(l);
  cyl([0, 17, 0], [0, 26, 0], 4, C.gun); cyl([0, 24, 0], [0, 25.4, 0], 4.3, C.orange);
  strut([2, MA.hip], [MA.femur[0] + 1, MA.femur[1]], 6.5, 6, C.yellow);
  cyl([MA.femur[0], MA.femur[1], -3.6], [MA.femur[0], MA.femur[1], 3.6], 3.8, C.gun);
}
function maulFemur(l) {   // short, swept, with a hooked spur on top
  frame = legFrame(l);
  const a = MA.femur, b = MA.knee, d = norm([b[0] - a[0], b[1] - a[1], 0]), n = [-d[1], d[0]];
  const p = t => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
  const off = (q, s) => [q[0] + n[0] * s, q[1] + n[1] * s];
  strut(p(0.05), p(0.95), 6.4, 5.4, C.yellow, 5);
  strut(off(p(0.2), 3.2), off(p(0.8), 2.8), 1, 5.8, C.orange);
  const sp = off(p(0.75), 3), tip = off(p(1.25), 7);
  cyl([sp[0], sp[1], 0], [tip[0], tip[1], 0], 1.4, C.dark, 0.3);   // spur
  cyl([MA.knee[0], MA.knee[1], -3.4], [MA.knee[0], MA.knee[1], 3.4], 3.6, C.gun);
  for (const w of [-1, 1]) cyl([MA.knee[0], MA.knee[1], w * 3.4], [MA.knee[0], MA.knee[1], w * 4.2], 2.2, C.orange);
}
function maulTibia(l) {   // blade shin ending in a steel claw point
  frame = legFrame(l);
  const a = MA.knee, f = [MA.foot[0], MA.foot[1] + 1.5], d = norm([f[0] - a[0], f[1] - a[1], 0]), n = [-d[1], d[0]];
  const p = t => [a[0] + (f[0] - a[0]) * t, a[1] + (f[1] - a[1]) * t];
  const off = (q, s) => [q[0] + n[0] * s, q[1] + n[1] * s];
  strut(p(0.04), p(0.8), 5.4, 4.6, C.gun, 3.4);
  strut(off(p(0.06), 2.4), off(p(0.55), 1.4), 1.6, 5.2, C.yellow, 1);
  cyl([...p(0.78), 0], [MA.foot[0], MA.foot[1] + 0.6, 0], 1.9, C.steel, 0.7);   // claw
}
// Double barrel: receiver behind the shield, two barrels side by side through the port (each recoils).
const MA_BARRELS = [-2.9, 2.9];
function maulReceiver() {
  const [, hy, hz] = MA_HINGE;
  cyl([-6.4, hy, hz], [6.4, hy, hz], 2.4, C.dark);
  box([-6, 23, 6], [6, 31, 17], C.gun); box([-6.2, 30, 7], [6.2, 31.2, 16], C.dark); box([-6.3, 24.5, 9], [6.3, 25.5, 14], C.orange);
  box([-6.2, 26.4, 16.5], [6.2, 29.6, 19.5], C.black);   // breech block
}
function maulBarrel(x) {
  const y = 28;
  cyl([x, y, 18], [x, y, 43], 2.5, C.gun); cyl([x, y, 34], [x, y, 37], 2.8, C.dark);
  cyl([x, y, 41.4], [x, y, 43.4], 2.9, C.orange); cyl([x, y, 30], [x, y, 43.6], 1.4, null);
  box([x - 0.6, y + 2.2, 20], [x + 0.6, y + 3.2, 40], C.black);   // vent rib
}
function maulMount() {   // pivot cradle bolted to the hull top, behind the shield
  const [, hy, hz] = MA_HINGE;
  box([-8, 30, 8], [8, 32.5, 15], C.dark);
  for (const s of [-1, 1]) box([s > 0 ? 6.6 : -8.4, 24, hz - 3], [s > 0 ? 8.4 : -6.6, 32.5, hz + 3], C.dark);
  cyl([-8.6, hy, hz], [8.6, hy, hz], 1, C.steel);
}

// ================================================================ build both
buildMech({
  name: 'br4-mortar', dir: 'parts-mortar', body: mortarBody, coxa: mortarCoxa, femur: mortarFemur, tibia: mortarTibia,
  legs: { hip: MO.hip, femur: MO.femur, knee: MO.knee, foot: MO.foot,
    place: [[-1, 17, 21, 42], [-1, -17, 21, -42], [1, 17, 21, 42], [1, -17, 21, -42]],
    group: (l, i) => [0, 1, 1, 0][i] },   // trot: diagonal pairs
  anim: {
    locomotion: { speed: 2.25, turn_rate: 170, accel: 5, body_height: 0, ground_follow: true, accel_pitch: 0.05, turn_roll: -0.035 },
    gait: { stride: 0.62, lift: 0.12, step_time: 0.36 },
    look: { part: 'body', yaw_limit: 22, pitch_min: -14, pitch_max: 20, stiffness: 4.5, scan_min: 2, scan_max: 4.5, scan_range: 75, lean: 0.03, crouch: 0.2, roll: 3 },
    bob: { part: 'body', amount: 0.022 },
  },
  weapon: { name: 'rocket', hinge: MO_HINGE, fold: -1, parts: [['weapon-launcher', 'base', mortarLauncher]],
    muzzles: MO_TUBES.map(([x, y]) => [x, y, 29]), mount: ['mount-turret', mortarMount] },
  rules: [
    { color: C.glass.slice(0, 3), glass: 1, tint: 0.25 },
    { color: C.head.slice(0, 3), glow: 6, light: [255, 222, 176], cone: 40, pitch: 0, yaw: 0, range: 22 },
    { color: C.beacon.slice(0, 3), glow: 1.8, range: 0.3, blink: 0.8 },
  ],
  description: 'BR-4 "Mortar": wide armoured artillery quadruped, huge splayed legs with elephant pads, turret-mounted quad rocket launcher, one flood lamp. Slow and heavy. Rig: br4-mortar.rig.json.',
});
buildMech({
  name: 'cq1-maul', dir: 'parts-maul', body: maulBody, coxa: maulCoxa, femur: maulFemur, tibia: maulTibia, legs: MA_LEGS,
  anim: {
    locomotion: { speed: 4.5, turn_rate: 620, accel: 22, body_height: 0, ground_follow: true, accel_pitch: 0.04, turn_roll: -0.03 },
    gait: { stride: 0.46, lift: 0.1, step_time: 0.12 },
    look: { part: 'body', yaw_limit: 26, pitch_min: -18, pitch_max: 26, stiffness: 14, scan_min: 1, scan_max: 2.6, scan_range: 60, lean: 0.07, crouch: 0.12, roll: 7 },
    bob: { part: 'body', amount: 0.01 },
  },
  weapon: { name: 'shotgun', hinge: MA_HINGE, fold: 1, parts: [['weapon-receiver', 'base', maulReceiver], ['weapon-barrel0', 'barrel', () => maulBarrel(MA_BARRELS[0])], ['weapon-barrel1', 'barrel', () => maulBarrel(MA_BARRELS[1])]],
    muzzles: MA_BARRELS.map(x => [x, 28, 43.6]), mount: ['mount-cradle', maulMount] },
  rules: [
    { color: C.head.slice(0, 3), glow: 6, light: [255, 226, 186], cone: 36, pitch: 0, yaw: 0, range: 18 },
    { color: C.eye.slice(0, 3), glow: 2.2, range: 0.3 },
    { color: C.beacon.slice(0, 3), glow: 1.8, range: 0.3, blink: 2.2 },
  ],
  description: 'CQ-1 "Maul": low wedge on eight short claw legs behind a raked riot shield with ram teeth and red eye slits; a double-barrel shotgun pokes through the shield port. Fastest mech. Rig: cq1-maul.rig.json.',
});
