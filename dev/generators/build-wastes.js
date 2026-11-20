#!/usr/bin/env node
// Desolate-planet outdoor set: dead flora, fungi, alien crystal growths, fossils, rocks and fine ground
// cover. Run from anywhere: node dev/generators/build-wastes.js   (--force: back up edited outputs, then overwrite)
//
// Writes wastes/*.vpt.json (+ wastes/materials.json, vox/wastes-*.vox, catalog entries). Everything is
// static (place it like any asset; thin plants look best with Wind on). Ground cover tiles are thin
// slabs meant to be scattered densely over the dark regolith terrain: the terrain gives the broad tone,
// the tiles give the detail where the robot's lamps actually reach.
//
// Glow here is bioluminescence that never casts light (range 0.3): in a pitch-black scene the robot
// stays the only light source; the plants just glimmer where nothing else is visible.
'use strict';
// Outputs live in the asset folder; this script lives in dev/generators/.
process.chdir(require('path').join(__dirname, '../../assets/library/BLACK_START'));
const fs = require('fs');
require('./generated-guard.js').start('build-wastes', { skip: ['catalog.json'], dirs: ['wastes'] });
const K = require('./voxkit.js');
const { add, sub, mul, len, lerp, lerp3, mix, rnd, noise, curve, shape, blob, tube, spike, raster, bounds, writeAsset, writeVox } = K;

const DIR = 'wastes';
const C = {
  // regolith (matches the scene terrain tones), ash, rust, salt
  rego: [50, 46, 42], regoDark: [34, 31, 29], regoLight: [78, 72, 64], ash: [104, 100, 94], ashPale: [142, 138, 130],
  rust: [112, 62, 40], rustDark: [74, 42, 30], ochre: [138, 108, 64], salt: [176, 172, 160], scorch: [20, 18, 17],
  // dead vegetation
  bark: [46, 36, 30], barkPale: [96, 84, 72], twig: [70, 58, 48], straw: [140, 122, 88], strawDark: [96, 82, 58],
  olive: [74, 78, 56], oliveDark: [48, 52, 38], leather: [92, 70, 56],
  // fungi / fossils / crystal
  cap: [150, 128, 104], capDark: [96, 76, 62], gill: [64, 50, 44], bone: [190, 178, 156], boneDark: [132, 120, 102],
  crystal: [96, 80, 150], crystalPale: [150, 134, 196],
  // muted teal gills / violet crystal tips: plain colours. Nothing in the wastes glows by default;
  // glow is added by the user in the editor's Materials dialog (wastes/materials.json).
  teal: [70, 150, 138], violet: [132, 92, 196],
};
const RULES = [];

// Seeded RNG per asset, so variants are stable between runs.
function rng(seed) { let a = seed >>> 0; return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
const norm = v => mul(v, 1 / (len(v) || 1));
function jitterDir(d, amount, R) { return norm(add(d, [(R() - 0.5) * 2 * amount, (R() - 0.5) * 2 * amount * 0.6, (R() - 0.5) * 2 * amount])); }

const catalogEntries = [];
function asset(name, voxel, description, build) {
  K.begin(); build(); const cells = raster(K.take());
  if (!cells.size) throw new Error(`${name}: empty`);
  const b = bounds(cells), dims = [0, 2, 1].map(i => b.hi[i] - b.lo[i] + 1);
  if (dims.some(d => d > 128)) throw new Error(`${name}: ${dims} exceeds the 128-voxel axis limit`);
  const n = writeAsset(`${DIR}/${name}.vpt.json`, cells, voxel);
  writeVox(`vox/wastes-${name}.vox`, cells, b);
  catalogEntries.push({ name: `wastes/${name}`, voxel_size: voxel, dimensions: dims, voxels: n, description });
  const m = [b.hi[0] - b.lo[0] + 1, b.hi[1] - b.lo[1] + 1, b.hi[2] - b.lo[2] + 1].map(v => (v * voxel).toFixed(2));
  console.log(`  ${name}: ${n} voxels, ${m[0]} x ${m[1]} x ${m[2]} m`);
}

// Recursive branching (bushes, trees, coral, roots): tapered bent tubes, children fan out, thorns at nodes.
function branch(R, p, d, length, r, depth, o) {
  const bend = add(mul(d, length * 0.5), [(R() - 0.5) * length * o.wiggle, (R() - 0.5) * length * o.wiggle * 0.5, (R() - 0.5) * length * o.wiggle]);
  const end = add(p, add(mul(d, length), [0, -o.droop * length * (1 - d[1]), 0]));
  const pts = curve([p, add(p, bend), end], Math.max(3, Math.round(length / 1.5)));
  tube(pts, r, Math.max(0.75, r * o.taper), (q, { t }) => o.color(q, t, depth));
  if (o.thorns && depth < o.depth) for (let i = 0; i < o.thorns; i++) {
    const q = pts[Math.min(pts.length - 1, 1 + Math.floor(R() * (pts.length - 1)))], td = jitterDir([R() - 0.5, R() * 0.6, R() - 0.5], 1, R);
    spike(q, add(q, mul(td, r * 2.2 + 1)), Math.max(0.75, r * 0.5), o.thornColor || C.twig);
  }
  if (depth <= 0) { if (o.tip) o.tip(end, d, R); return; }
  const kids = o.kids[0] + Math.floor(R() * (o.kids[1] - o.kids[0] + 1));
  for (let i = 0; i < kids; i++) {
    const nd = jitterDir(add(d, [0, o.rise, 0]), o.spread, R);
    branch(R, lerp3(p, end, 0.55 + R() * 0.45), nd, length * (o.shrink + R() * 0.15), r * 0.66, depth - 1, o);
  }
}
const ground = (r, h, c, amp = 0.25) => blob([0, 0, 0], [r, h, r], c, amp, Math.max(2, r * 0.6));

// ================================================================ dead flora
function thornbush(seed, size) {
  return () => {
    const R = rng(seed);
    ground(size * 0.45, size * 0.12, (p) => mix(C.regoDark, C.rego, noise(p, 2)), 0.35);
    for (let i = 0; i < 4 + Math.floor(R() * 3); i++) {
      const a = R() * 6.283, d = norm([Math.cos(a) * 0.55, 1, Math.sin(a) * 0.55]);
      branch(R, [(R() - 0.5) * 3, 0, (R() - 0.5) * 3], d, size * (0.35 + R() * 0.2), 2.2, 3, {
        wiggle: 0.5, droop: 0.15, taper: 0.55, kids: [2, 3], spread: 0.75, rise: -0.1, shrink: 0.62, depth: 3, thorns: 3,
        color: (q, t, dep) => dep < 1 ? mix(C.twig, C.barkPale, noise(q, 1.5)) : mix(C.bark, C.twig, t),
      });
    }
  };
}
function bristleShrub(seed, size, tint) {
  return () => {
    const R = rng(seed);
    blob([0, size * 0.25, 0], [size * 0.55, size * 0.38, size * 0.5], (p) => mix(C.strawDark, tint, noise(p, 1.6) * 0.8), 0.3, 3);
    // radiating needles poke out of the dome
    for (let i = 0; i < 70; i++) {
      const a = R() * 6.283, e = R() * 1.3, d = [Math.cos(a) * Math.cos(e), Math.sin(e) + 0.15, Math.sin(a) * Math.cos(e)];
      const base = [d[0] * size * 0.4, size * 0.25 + d[1] * size * 0.25, d[2] * size * 0.36];
      spike(base, add(base, mul(norm(d), size * (0.25 + R() * 0.25))), 0.8, R() < 0.3 ? C.ashPale : tint);
    }
  };
}
function tendrilWeed(seed) {
  return () => {
    const R = rng(seed);
    ground(6, 1.5, C.regoDark);
    for (let i = 0; i < 9; i++) {
      const base = [(R() - 0.5) * 8, 0, (R() - 0.5) * 8], h = 34 + R() * 28, lean = [(R() - 0.5) * 14, 0, (R() - 0.5) * 14];
      const top = add(base, add([0, h, 0], lean)), head = add(top, [lean[0] * 0.3, -6 - R() * 6, lean[2] * 0.3]);
      tube(curve([base, add(base, [lean[0] * 0.2, h * 0.6, lean[2] * 0.2]), top, head], 16), 0.9, 0.75, (q, { t }) => mix(C.strawDark, C.straw, t));
      // drooping seed head: a string of husks
      for (let k = 0; k < 4; k++) blob(lerp3(top, head, 0.3 + k * 0.22), [1.2, 1.8, 1.2], k % 2 ? C.straw : C.ochre);
    }
  };
}
function sporeStalks(seed) {
  return () => {
    const R = rng(seed);
    ground(7, 2, (p) => mix(C.oliveDark, C.regoDark, noise(p, 2)));
    for (let i = 0; i < 7; i++) {
      const base = [(R() - 0.5) * 9, 0, (R() - 0.5) * 9], h = 20 + R() * 30, top = add(base, [(R() - 0.5) * 6, h, (R() - 0.5) * 6]);
      tube(curve([base, lerp3(base, top, 0.5).map((v, k) => v + (k === 1 ? 0 : (R() - 0.5) * 4)), top], 12), 1.2, 0.8, C.olive);
      const pr = 2.4 + R() * 2;
      blob(top, [pr, pr * 1.3, pr], (p) => Math.abs(noise(p, 1.4) - 0.5) < 0.06 ? C.ochre : mix(C.leather, C.olive, noise(p, 1.1)), 0.15, 1.5);
    }
  };
}
function bulbFungus(seed, n) {
  return () => {
    const R = rng(seed);
    ground(9, 2, (p) => mix(C.regoDark, C.capDark, noise(p, 2.5) * 0.6));
    for (let i = 0; i < n; i++) {
      const base = [(R() - 0.5) * 12, 0, (R() - 0.5) * 12], h = 6 + R() * 16, cr = 3 + R() * 5, top = add(base, [(R() - 0.5) * 3, h, (R() - 0.5) * 3]);
      tube(curve([base, top], 6), cr * 0.35, cr * 0.28, (q) => mix(C.cap, C.ashPale, noise(q, 1.5) * 0.5));
      blob(add(top, [0, cr * 0.25, 0]), [cr, cr * 0.55, cr], (p) => mix(C.capDark, C.cap, noise(p, 1.8) + (p[1] - top[1]) / cr), 0.12, 2);
      // underside gills glimmer faintly
      blob(add(top, [0, -cr * 0.05, 0]), [cr * 0.85, cr * 0.2, cr * 0.85], (p) => noise(p, 0.9) > 0.62 ? C.teal : C.gill);
    }
  };
}
function crystalShrub(seed) {
  return () => {
    const R = rng(seed);
    blob([0, 2, 0], [9, 4, 8], (p) => mix(C.regoDark, C.crystal, noise(p, 2) * 0.4), 0.3, 3);
    for (let i = 0; i < 16; i++) {
      const a = R() * 6.283, e = 0.35 + R() * 1.1, d = [Math.cos(a) * Math.cos(e), Math.sin(e), Math.sin(a) * Math.cos(e)];
      const base = [d[0] * 4, 2, d[2] * 4], l = 10 + R() * 22;
      tube([base, add(base, mul(d, l))], 1.4 + R() * 1.6, 0.75, (q, { t }) => t > 0.85 ? C.violet : mix(C.crystal, C.crystalPale, t + (noise(q, 1) - 0.5) * 0.4));
    }
  };
}
function coralFan(seed) {
  return () => {
    const R = rng(seed);
    ground(7, 2, C.rustDark);
    // flattened fan: branches spread mostly in the x/y plane
    branch(R, [0, 0, 0], [0, 1, 0], 22, 2.6, 4, {
      wiggle: 0.35, droop: 0, taper: 0.6, kids: [2, 2], spread: 0.6, rise: 0.25, shrink: 0.7, depth: 4, thorns: 0,
      color: (q, t, dep) => mix(C.rustDark, C.rust, (4 - dep) / 4 + (noise(q, 1.4) - 0.5) * 0.4),
      tip: (e) => blob(e, [1.2, 1.2, 1.2], C.ochre),
    });
    // flatten: carve everything far from the fan plane
    shape([-60, -5, -60], [60, 80, -2.5], () => null); shape([-60, -5, 2.5], [60, 80, 60], (p) => p[1] > 3 ? null : undefined);
  };
}
function rootTangle(seed) {
  return () => {
    const R = rng(seed);
    blob([0, 0, 0], [16, 3, 14], (p) => mix(C.regoDark, C.rego, noise(p, 3)), 0.3, 5);
    for (let i = 0; i < 8; i++) {
      const a = R() * 6.283, b = a + 1.2 + R() * 2.2, ra = 6 + R() * 12, rb = 6 + R() * 12, h = 5 + R() * 12;
      const s = [Math.cos(a) * ra, 0, Math.sin(a) * ra], e = [Math.cos(b) * rb, 0, Math.sin(b) * rb];
      tube(curve([s, add(lerp3(s, e, 0.3), [0, h, 0]), add(lerp3(s, e, 0.7), [0, h * 0.8, 0]), e], 16), 2.4 + R() * 1.5, 1.2, (q, { t }) => mix(C.bark, C.barkPale, Math.abs(t - 0.5) < 0.3 ? 0.6 : 0.1));
    }
  };
}
function podSucculent(seed) {
  return () => {
    const R = rng(seed);
    ground(8, 2, C.regoDark);
    for (let i = 0; i < 11; i++) {
      const a = i / 11 * 6.283 + R() * 0.3, e = 0.5 + R() * 0.7, l = 8 + R() * 8;
      const d = [Math.cos(a) * Math.cos(e), Math.sin(e), Math.sin(a) * Math.cos(e)];
      tube(curve([[0, 2, 0], add([0, 2, 0], mul(d, l * 0.6)), add(add([0, 2, 0], mul(d, l)), [0, -2, 0])], 10), 3, 0.8, (q, { t }) => mix(C.oliveDark, C.olive, t + (noise(q, 1.2) - 0.5) * 0.5));
    }
    for (let i = 0; i < 4; i++) blob([(R() - 0.5) * 4, 5 + R() * 3, (R() - 0.5) * 4], [2.2, 2.8, 2.2], (p) => noise(p, 1) > 0.7 ? C.teal : C.leather);
  };
}
function tumbleweed(seed) {
  return () => {
    const R = rng(seed), c = [0, 11, 0];
    for (let i = 0; i < 46; i++) {
      const a = R() * 6.283, b = Math.acos(2 * R() - 1), d = [Math.sin(b) * Math.cos(a), Math.cos(b), Math.sin(b) * Math.sin(a)];
      const s = add(c, mul(d, 4 + R() * 6)), e = add(c, mul(jitterDir(d, 1.2, R), 10));
      tube(curve([s, lerp3(s, e, 0.5).map(v => v + (R() - 0.5) * 4), e], 6), 0.8, 0.75, R() < 0.5 ? C.straw : C.strawDark);
    }
  };
}
function huskTree(seed) {
  return () => {
    const R = rng(seed);
    blob([0, 0, 0], [14, 4, 13], (p) => mix(C.regoDark, C.bark, noise(p, 2) * 0.5), 0.35, 4);
    // twisted trunk, few heavy limbs, snapped tips
    const top = [6, 70, -4];
    tube(curve([[0, 0, 0], [-6, 22, 5], [8, 44, -2], top], 24), 6.5, 2.8, (q, { t }) => Math.abs(noise(q, 2.4) - 0.5) < 0.05 ? C.barkPale : mix(C.bark, C.twig, noise(q, 1.6) * 0.6 + t * 0.2));
    for (let i = 0; i < 5; i++) {
      const p = curve([[0, 0, 0], [-6, 22, 5], [8, 44, -2], top], 24)[12 + i * 2 + Math.floor(R() * 2)];
      const a = R() * 6.283;
      branch(R, p, norm([Math.cos(a), 0.5 + R() * 0.5, Math.sin(a)]), 18 + R() * 10, 2.6, 2, {
        wiggle: 0.45, droop: 0.2, taper: 0.5, kids: [1, 2], spread: 0.7, rise: 0, shrink: 0.6, depth: 2, thorns: 0,
        color: (q) => mix(C.bark, C.barkPale, noise(q, 1.3) * 0.7),
      });
    }
  };
}

// ================================================================ fossils
function boneRibs() {
  return () => {
    const spine = curve([[-50, 4, 0], [-20, 9, 2], [15, 10, -1], [50, 3, 1]], 30);
    blob([0, 0, 0], [50, 3, 24], (p) => mix(C.regoDark, C.rego, noise(p, 4)), 0.18, 6);   // sunken bed
    for (let i = 0; i < spine.length; i++) blob(spine[i], [2.6, 2.2, 2.2], (p) => mix(C.boneDark, C.bone, noise(p, 1.2)), 0.12, 1.2);   // vertebrae
    for (let i = 3; i < 26; i += 2) {
      const s = spine[i], h = 26 - Math.abs(i - 14) * 1.2;
      for (const side of [-1, 1]) {
        const broken = (i * 7 + side * 3) % 5 === 0;
        const pts = curve([s, add(s, [0, h * 0.6, side * h * 0.55]), add(s, [2, h * 0.5, side * h * 1.0]), add(s, [3, 0, side * h * 0.9])], 18);
        tube(broken ? pts.slice(0, 11) : pts, 2.1, 1.1, (q) => noise(q, 1.6) > 0.78 ? C.boneDark : mix(C.bone, C.ashPale, noise(q, 2.2) * 0.4));
      }
    }
  };
}
function skullFossil() {
  return () => {
    blob([0, 0, 0], [30, 4, 26], (p) => mix(C.regoDark, C.rego, noise(p, 4)), 0.3, 5);
    const bone = (p) => noise(p, 1.5) > 0.8 ? C.boneDark : mix(C.bone, C.ashPale, noise(p, 2.5) * 0.4);
    blob([0, 8, -4], [16, 14, 18], bone, 0.06, 4);                          // cranium (half buried: y<0 is cut by the ground)
    blob([0, 4, 14], [10, 8, 14], bone, 0.08, 3);                           // snout
    for (const s of [-1, 1]) { blob([s * 8, 12, 6], [5, 5, 5], null); blob([s * 8, 12, 6], [4.4, 4.4, 4.4], C.scorch); }   // eye sockets
    for (let i = 0; i < 7; i++) for (const s of [-1, 1]) spike([s * (7 - i * 0.6), 0, 22 - i * 3], [s * (7.5 - i * 0.6), -4, 23 - i * 3], 1.3, C.bone);   // teeth
    for (const s of [-1, 1]) tube(curve([[s * 12, 16, -12], [s * 26, 24, -18], [s * 30, 14, -30]], 14), 4, 1, bone);  // horns
    shape([-80, -20, -80], [80, -0.01, 80], () => null);                  // nothing below ground
  };
}

// ================================================================ rocks
function pittedBoulder(seed, size) {
  return () => {
    const R = rng(seed);
    blob([0, size * 0.35, 0], [size, size * 0.7, size * 0.85], (p) => noise(p, 1.3) > 0.86 ? C.rustDark : mix(C.regoDark, C.regoLight, noise(p, size * 0.4) * 0.8), 0.22, size * 0.5);
    for (let i = 0; i < 14; i++) { const a = R() * 6.283, e = R() * 1.2; blob([Math.cos(a) * Math.cos(e) * size * 0.95, size * 0.35 + Math.sin(e) * size * 0.65, Math.sin(a) * Math.cos(e) * size * 0.8], [1.5 + R() * 2.5, 1.5 + R() * 2.5, 1.5 + R() * 2.5], null); }  // pits
    shape([-80, -20, -80], [80, -0.01, 80], () => null);
  };
}
function shaleShards(seed) {
  return () => {
    const R = rng(seed);
    blob([0, 0, 0], [20, 2, 16], C.regoDark, 0.3, 4);
    for (let i = 0; i < 12; i++) {
      const base = [(R() - 0.5) * 30, 0, (R() - 0.5) * 24], d = norm([R() - 0.5, 1.2 + R(), R() - 0.5]), l = 8 + R() * 22, w = 3 + R() * 4;
      // thin slanted slabs: an oriented box test
      const u = norm([d[2], 0, -d[0]]);
      shape([base[0] - l, -1, base[2] - l], [base[0] + l, l + 2, base[2] + l], (p) => {
        const q = sub(p, base), along = q[0] * d[0] + q[1] * d[1] + q[2] * d[2], side = q[0] * u[0] + q[2] * u[2];
        const perp = len(sub(q, add(mul(d, along), mul(u, side))));
        return along >= 0 && along <= l * (1 - Math.abs(side) / (w * 1.6)) && Math.abs(side) <= w && perp <= 1.1 ? mix(C.regoDark, C.ash, along / l * 0.6 + noise(p, 1) * 0.3) : undefined;
      });
    }
  };
}
function hoodoo() {
  return () => {
    // eroded pillar: stacked bands of soft and hard rock, a caprock on top
    for (let y = 0; y < 90; y += 1) {
      const r = 11 + Math.sin(y * 0.21) * 2.5 + Math.sin(y * 0.07 + 1) * 3 - y * 0.04;
      shape([-r - 3, y, -r - 3], [r + 3, y + 1, r + 3], (p) => {
        const d = Math.hypot(p[0], p[2] * 1.1) + (noise(p, 3) - 0.5) * 4;
        return d <= r ? ((Math.floor(p[1] / 7) % 2) ? mix(C.rustDark, C.regoLight, noise(p, 2) * 0.6) : mix(C.regoDark, C.rego, noise(p, 2))) : undefined;
      });
    }
    blob([2, 96, 0], [20, 7, 17], (p) => mix(C.regoDark, C.ash, noise(p, 2)), 0.25, 5);
    blob([0, 0, 0], [22, 4, 20], (p) => mix(C.regoDark, C.rust, noise(p, 3) * 0.4), 0.3, 5);   // scree skirt
  };
}

// ================================================================ ground cover (0.05 m voxels, thin)
const edgeFade = (p, half) => Math.max(0, 1 - Math.max(Math.abs(p[0]), Math.abs(p[2])) / half);
function crustPlates(seed) {
  return () => {
    const R = rng(seed), half = 40, cells = [];
    for (let i = 0; i < 26; i++) cells.push([(R() - 0.5) * 2 * half, (R() - 0.5) * 2 * half, 1 + R() * 2.2, R()]);
    shape([-half, 0, -half], [half, 5, half], (p) => {
      let a = 1e9, b = 1e9, id = 0;
      for (let k = 0; k < cells.length; k++) { const d = Math.hypot(p[0] - cells[k][0], p[2] - cells[k][1]); if (d < a) { b = a; a = d; id = k; } else if (d < b) b = d; }
      const crack = b - a, f = edgeFade(p, half), h = cells[id][2] * Math.min(1, f * 3);
      if (crack < 1.3 || p[1] > h || f <= 0.02) return undefined;
      return p[1] > h - 1 ? mix(C.regoDark, C.regoLight, cells[id][3] * 0.7 + noise(p, 3) * 0.3) : C.regoDark;
    });
  };
}
function gravel(seed) {
  return () => {
    const R = rng(seed);
    for (let i = 0; i < 260; i++) {
      const r = Math.sqrt(R()) * 30, a = R() * 6.283, s = 0.7 + R() * R() * 3.2;
      const c = [Math.cos(a) * r, s * 0.4, Math.sin(a) * r], col = R() < 0.08 ? C.rustDark : R() < 0.4 ? C.regoLight : C.rego;
      blob(c, [s, s * 0.75, s * (0.8 + R() * 0.4)], col, 0.2, 1.2);
    }
  };
}
function ashRipples(seed) {
  return () => {
    const R = rng(seed), half = 40, k = 0.32 + R() * 0.1, ang = R() * 3.14, ca = Math.cos(ang), sa = Math.sin(ang);
    shape([-half, 0, -half], [half, 6, half], (p) => {
      const u = p[0] * ca + p[2] * sa, f = edgeFade(p, half);
      const h = (1.4 + 1.6 * (0.5 + 0.5 * Math.sin(u * k + noise(p, 9) * 6))) * Math.min(1, f * 2.5);
      return p[1] <= h && f > 0.02 ? mix(C.rego, C.ash, p[1] / 5 + noise(p, 4) * 0.25) : undefined;
    });
  };
}
function fissure(seed) {
  return () => {
    const R = rng(seed), pts = [];
    for (let i = 0; i <= 12; i++) pts.push([-60 + i * 10, 0, (R() - 0.5) * 10]);
    const line = curve(pts, 60);
    shape([-62, 0, -18], [62, 6, 18], (p) => {
      let d = 1e9, t = 0; for (let i = 0; i < line.length; i++) { const e = Math.hypot(p[0] - line[i][0], p[2] - line[i][2]); if (e < d) { d = e; t = i / line.length; } }
      const width = 2.2 * Math.sin(Math.PI * t) + 0.4, lip = 5 * Math.sin(Math.PI * t);
      if (d < width) return p[1] < 1 ? C.scorch : undefined;                       // the dark crack itself
      const h = Math.max(0, lip * (1 - (d - width) / 9)) + (noise(p, 2) - 0.5) * 1.5;  // broken raised lips
      return d < width + 9 && p[1] <= h ? mix(C.regoDark, C.regoLight, p[1] / 5 + noise(p, 1.5) * 0.3) : undefined;
    });
  };
}
function crater(seed) {
  return () => {
    const R = rng(seed), rad = 34;
    shape([-50, 0, -50], [50, 9, 50], (p) => {
      const d = Math.hypot(p[0], p[2]) + (noise(p, 6) - 0.5) * 5, rim = Math.exp(-((d - rad) ** 2) / 40) * 7;
      if (d < rad - 6) return p[1] < 1 ? mix(C.scorch, C.regoDark, d / rad) : undefined;   // scorched floor
      return p[1] <= rim && rim > 0.4 ? mix(C.regoDark, C.regoLight, p[1] / 7 + noise(p, 2) * 0.3) : undefined;
    });
    for (let i = 0; i < 40; i++) { const a = R() * 6.283, r = rad + 4 + R() * 16, s = 0.8 + R() * 2.5; blob([Math.cos(a) * r, s * 0.5, Math.sin(a) * r], [s, s * 0.7, s], R() < 0.15 ? C.rustDark : C.regoLight, 0.2, 1); }  // ejecta
  };
}
function saltCrust(seed) {
  return () => {
    const R = rng(seed), half = 36;
    shape([-half, 0, -half], [half, 3, half], (p) => {
      const hx = p[0] / 7, hz = p[2] / 6.06;   // hexagon-ish polygon seams
      const seam = Math.min(Math.abs(Math.sin(hx * 3.1416)), Math.abs(Math.sin((hx * 0.5 + hz) * 3.1416)), Math.abs(Math.sin((hx * 0.5 - hz) * 3.1416)));
      const f = edgeFade(p, half) - (noise(p, 8) - 0.5) * 0.6;
      if (f < 0.05) return undefined;
      return p[1] < 1 + (seam < 0.18 ? 1.2 : 0) ? (seam < 0.18 ? C.ash : mix(C.regoLight, C.ash, noise(p, 3) * 0.7)) : undefined;
    });
    void R;
  };
}

// ================================================================ output
fs.mkdirSync(DIR, { recursive: true });
for (const f of fs.readdirSync(DIR)) if (f.endsWith('.vpt.json')) fs.unlinkSync(`${DIR}/${f}`);
console.log('wastes:');
asset('thornbush-a', 0.025, 'Dead thorn bush, gnarled charcoal branches.', thornbush(11, 40));
asset('thornbush-b', 0.025, 'Tall dead thorn bush.', thornbush(23, 54));
asset('thornbush-c', 0.025, 'Low wide dead thorn bush.', thornbush(37, 32));
asset('bristle-shrub-a', 0.025, 'Dome of dry pale needles.', bristleShrub(5, 24, C.straw));
asset('bristle-shrub-b', 0.025, 'Ash-grey bristle shrub.', bristleShrub(9, 30, C.ash));
asset('tendril-weed', 0.025, 'Wispy tall stalks with drooping seed husks (use Wind).', tendrilWeed(3));
asset('spore-stalks', 0.025, 'Thin olive stalks with leathery veined spore pods (use Wind).', sporeStalks(7));
asset('bulb-fungus-a', 0.025, 'Cluster of pale fungus caps with teal gills.', bulbFungus(13, 7));
asset('bulb-fungus-b', 0.025, 'Big lone fungus caps.', bulbFungus(29, 3));
asset('crystal-shrub', 0.025, 'Alien violet crystal growth.', crystalShrub(17));
asset('coral-fan', 0.025, 'Dead rust-red branching fan.', coralFan(19));
asset('root-tangle', 0.04, 'Exposed arching roots.', rootTangle(31));
asset('pod-succulent', 0.025, 'Leathery olive rosette with teal pods.', podSucculent(41));
asset('tumbleweed', 0.025, 'Ball of dry twigs.', tumbleweed(43));
asset('husk-tree', 0.05, 'Dead twisted husk tree, ~3.5 m.', huskTree(47));
asset('bone-ribs', 0.06, 'Giant fossil ribcage and spine, ~7 m.', boneRibs());
asset('skull-fossil', 0.05, 'Half-buried horned fossil skull, ~3 m.', skullFossil());
asset('pitted-boulder-a', 0.05, 'Pitted dark boulder with rust streaks.', pittedBoulder(53, 16));
asset('pitted-boulder-b', 0.05, 'Large pitted boulder.', pittedBoulder(59, 26));
asset('shale-shards', 0.05, 'Slanted shale slabs jutting from the ground.', shaleShards(61));
asset('hoodoo', 0.05, 'Banded eroded rock pillar with caprock, ~5 m.', hoodoo());
asset('ground-crust-a', 0.05, 'Ground cover: cracked crust plates, 4 m.', crustPlates(71));
asset('ground-crust-b', 0.05, 'Ground cover: cracked crust plates, 4 m (variant).', crustPlates(73));
asset('ground-gravel', 0.05, 'Ground cover: pebble scatter, 3 m.', gravel(79));
asset('ground-ash-ripples', 0.05, 'Ground cover: wind-rippled ash, 4 m.', ashRipples(83));
asset('ground-fissure', 0.05, 'Ground cover: dark fissure with raised broken lips, 6 m.', fissure(89));
asset('ground-crater', 0.05, 'Ground cover: small impact crater with ejecta, 5 m.', crater(97));
asset('ground-salt', 0.05, 'Ground cover: pale polygonal salt crust, 3.6 m.', saltCrust(101));
fs.writeFileSync(`${DIR}/materials.json`, '{"version":1,"materials":[\n' + RULES.map(r => '  ' + JSON.stringify(r)).join(',\n') + '\n]}\n');
const catalog = JSON.parse(fs.readFileSync('catalog.json', 'utf8')).filter(e => !e.name.startsWith('wastes/'));
fs.writeFileSync('catalog.json', JSON.stringify(catalog.concat(catalogEntries), null, 2) + '\n');
