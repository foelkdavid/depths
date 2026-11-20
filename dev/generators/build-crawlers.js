#!/usr/bin/env node
// Hostile crystal-organic crawlers, built as rigid parts for the procedural rig runtime.
// Run from anywhere: node dev/generators/build-crawlers.js   (--force: back up edited outputs, then overwrite)
//
//   alien-crawler  ~2.6 m leg span, 10 spider-high legs, crystal spine, scorpion tail, hook mandibles
//   alien-skitter  ~0.6 m leg span, 8 needle legs, swollen vein-lit abdomen, red eyes, fangs
//
// For each: parts-<name>/*.vpt.json, <name>.{vpt,rig,anim,materials}.json, vox/<name>.vox, catalog entry.
// Authoring space = engine voxel space (x right, y up, z forward), one unit = the creature's voxel size.
// Knees sit in the vertical plane through hip and foot so the 2-bone solver reproduces the rest pose.
'use strict';
// Outputs live in the asset folder; this script lives in dev/generators/.
process.chdir(require('path').join(__dirname, '../../assets/library/BLACK_START'));
const fs = require('fs');
// Refuses to overwrite files edited since the last run (editor Materials, hand-tuned JSON); --force backs them up.
require('./generated-guard.js').start('build-crawlers', { skip: ['catalog.json'], dirs: ['parts-crawler', 'parts-skitter', 'parts-nest', 'parts-nest-spire'] });

// ---------------------------------------------------------------- palette (organic, never machined)
const C = {
  chitin: [30, 24, 40], chitin2: [52, 38, 66], sheen: [92, 70, 120], seam: [16, 12, 22],
  flesh: [116, 70, 84], membrane: [92, 30, 46], vein: [84, 26, 44],
  bone: [198, 182, 160], boneDark: [146, 124, 108], crystal: [124, 104, 182], crystalPale: [176, 160, 220],
  // emissive: colours matched by the per-creature materials.json written below
  eye: [89, 213, 187, 1], orb: [10, 11, 14],
  goo: [52, 20, 40], gooTop: [104, 40, 72], gooShine: [150, 78, 112], mucus: [128, 140, 52], yolk: [200, 120, 255, 1], pustule: [190, 96, 255, 1],
  membrane: [176, 104, 196], slime: [120, 84, 112], sacSkin: [118, 52, 96], sacShine: [176, 104, 150], glow: [176, 112, 255, 1], red: [240, 64, 36, 1],
};
const NEST_RULES = [
  { color: [176, 104, 196], glass: 1, tint: 0.8 },                    // sac membrane windows
  { color: [120, 84, 112], glass: 1, tint: 0.6 },                     // wet slime coat
  { color: [200, 120, 255], glow: 1.1, flicker: 0.35, range: 0.3 },   // embryo yolk: glows, casts nothing
  { color: [190, 96, 255], glow: 0.9, light: [150, 60, 255], flicker: 0.3, range: 3.0 },  // one light per nest
  { color: [240, 64, 36], glow: 0.8, range: 0.3 },                    // embryo eyes
];
const RULES = {
  'alien-nest': NEST_RULES, 'alien-nest-spire': NEST_RULES,
  'alien-crawler': [
    { color: C.eye.slice(0, 3), glow: 0.7, light: [80, 255, 200], flicker: 0.12 },
    { color: C.glow.slice(0, 3), glow: 0.6, light: [150, 70, 255], flicker: 0.25 },
  ],
  // Too small to light the room: the tracer skips lights within 0.4 m of their source, which would carve a
  // dark disc under the body. range < 0.4 keeps the glow on the voxels without casting any light.
  'alien-skitter': [
    { color: C.red.slice(0, 3), glow: 1.4, range: 0.3 },
    { color: C.glow.slice(0, 3), glow: 0.9, flicker: 0.4, range: 0.3 },
  ],
};

// Toolkit (math, noise, shapes, raster, export): voxkit.js
const K = require('./voxkit.js');
const { add, sub, mul, dot, len, lerp, lerp3, mix, hash, rnd, noise, curve, shape, paint, blob, tube, spike, raster, bounds, engine, writeAsset, writeVox } = K;

function build(name, voxel, parts, anim, description) {
  const dir = `parts-${name.replace('alien-', '')}`;  // alien-nest -> parts-nest
  fs.mkdirSync(dir, { recursive: true });
  for (const f of fs.readdirSync(dir)) if (f.endsWith('.vpt.json')) fs.unlinkSync(`${dir}/${f}`);
  const built = parts.map(([pname, parent, joint, fn]) => { K.begin(); fn(); return { pname, parent, joint, cells: raster(K.take()) }; });
  const all = new Map(); for (const p of built) for (const [k, v] of p.cells) all.set(k, v);
  const model = bounds(all);
  const rig = built.map(p => {
    const b = bounds(p.cells), q = [0, 0, 0];
    const shift = engine(q, model, voxel).map((v, i) => Math.round((v - engine(q, b, voxel)[i]) * 10000) / 10000);
    writeAsset(`${dir}/${p.pname}.vpt.json`, p.cells, voxel);
    return { name: p.pname, asset: `${dir}/${p.pname}.vpt.json`, parent: p.parent, shift, joint: engine(p.joint, model, voxel) };
  });
  const total = writeAsset(`${name}.vpt.json`, all, voxel);
  fs.mkdirSync('vox', { recursive: true }); writeVox(`vox/${name}.vox`, all, model);
  fs.writeFileSync(`${name}.rig.json`, JSON.stringify({ version: 1, name, parts: rig }, null, 1) + '\n');
  anim.legs = anim.legs.map(l => ({ ...l, foot: engine(l.foot, model, voxel) }));
  if (anim.anchors) anim.anchors = anim.anchors.map(a => ({ ...a, foot: engine(a.foot, model, voxel) }));
  fs.writeFileSync(`${name}.anim.json`, JSON.stringify(anim, null, 1) + '\n');
  const rules = '{"version":1,"materials":[\n' + RULES[name].map(r => '  ' + JSON.stringify(r)).join(',\n') + '\n]}\n';
  fs.writeFileSync(`${dir}/materials.json`, rules); fs.writeFileSync(`${name}.materials.json`, rules);
  const catalog = JSON.parse(fs.readFileSync('catalog.json', 'utf8'));
  let entry = catalog.find(e => e.name === name); if (!entry) { entry = { name }; catalog.splice(1, 0, entry); }
  Object.assign(entry, { voxel_size: voxel, dimensions: [0, 2, 1].map(i => model.hi[i] - model.lo[i] + 1), voxels: total, description });
  fs.writeFileSync('catalog.json', JSON.stringify(catalog, null, 2) + '\n');
  const W = model.hi.map((v, i) => ((v - model.lo[i] + 1) * voxel).toFixed(2));
  console.log(`${name}: ${total} voxels, ${W[0]} x ${W[1]} x ${W[2]} m, ${rig.length} parts`);
}

// Carapace colouring: dark plates with segment seams, a violet sheen on top, pale flesh underneath.
function carapace(o, ry, segment = 5) {
  return (p, info) => {
    const up = (p[1] - o[1]) / ry;
    if (up < -0.45) return mix(C.flesh, C.membrane, noise(p, 2.5));
    const band = ((p[2] + 1000) % segment) / segment;
    if (band < 0.16 && up > -0.2) return C.seam;
    if (noise(p, 1.7) > 0.82) return C.vein;
    return mix(C.chitin, up > 0.55 ? C.sheen : C.chitin2, Math.max(0, up) * 0.9 + band * 0.25);
  };
}
// A leg: knee placed in the vertical hip-foot plane at fraction kf of the horizontal reach.
function legPlan(hip, foot, kneeY, kf) {
  const h = sub(foot, hip); h[1] = 0;
  return { hip, foot, knee: [hip[0] + h[0] * kf, kneeY, hip[2] + h[2] * kf] };
}
const femurColor = (p, { t }) => t > 0.93 ? C.membrane : (noise(p, 1.4) > 0.86 ? C.sheen : mix(C.chitin, C.chitin2, t * 0.7));
const tibiaColor = (p, { t }) => t < 0.06 ? C.membrane : t > 0.62 ? mix(C.boneDark, C.bone, (t - 0.62) * 2.5) : mix(C.chitin2, C.chitin, t);

// ================================================================ alien-crawler (voxel 0.025)
{
  const S = 0.025, HIPY = 24;
  const legs = [];
  const Z = [16, 10, 4, -2, -8], SPREAD = [24, 10, 0, -10, -24], REACH = [40, 45, 46, 45, 41];
  for (const s of [-1, 1]) Z.forEach((z, i) => {
    const hip = [s * 8, HIPY, z], foot = [s * REACH[i], 0, z + SPREAD[i]];
    legs.push({ s, i, ...legPlan(hip, foot, 50 - Math.abs(i - 2) * 2, 0.6) });
  });
  const crystal = (base, tip, r) => tube(curve([base, lerp3(base, tip, 0.5).map((v, k) => v + (k === 1 ? 1 : 0)), tip], 6), r, 0.3, (p, { t }) => t > 0.72 ? C.glow : mix(C.crystal, C.crystalPale, t + (noise(p, 1.2) - 0.5) * 0.5));
  function body() {
    blob([0, 25, 6], [10, 7, 15], carapace([0, 25, 6], 7), 0.12, 4);
    blob([0, 24.5, -6], [7, 6, 8], carapace([0, 24.5, -6], 6, 4), 0.08);
    blob([0, 28, -17], [13, 11, 14], carapace([0, 28, -17], 11, 6), 0.14, 5);
    // glowing spiracle sacs along the abdomen flanks
    for (const s of [-1, 1]) for (const z of [-11, -17, -23]) blob([s * 11.5, 26 + (z + 17) * -0.2, z], [1.4, 1.6, 1.6], C.glow);
    // crystal growths erupting along the spine, leaning back
    const spine = [[0, 31.5, 15, 7, 2], [2, 32, 8, 9, 2.2], [-2, 32, 2, 8, 2], [0, 36, -10, 13, 2.8], [3, 38, -16, 11, 2.4], [-3, 37.5, -19, 12, 2.4], [1, 37, -24, 9, 2], [-5, 34, -26, 7, 1.6], [6, 33, -9, 8, 1.8]];
    for (const [x, y, z, l, r] of spine) crystal([x, y - 2, z], [x * 1.6 + (rnd(x, y, z) - 0.5) * 4, y + l, z - l * 0.45], r);
    // hip sockets: raw membrane
    for (const l of legs) blob(l.hip, [3, 3, 3], C.membrane, 0.2, 2);
  }
  function head() {
    blob([0, 23, 25], [7.5, 5.5, 8], carapace([0, 23, 25], 5.5, 3), 0.1, 3);
    blob([0, 21, 29], [5, 3.5, 4], C.flesh, 0.2, 2);
    // eye cluster: two big, six small, asymmetric
    const eyes = [[2.6, 26, 31, 1.7], [-2.6, 26, 31, 1.7], [4.8, 25.2, 29.6, 1.1], [-4.9, 25, 29.4, 1.1], [1.3, 27.8, 29.8, 0.9], [-1.1, 27.9, 29.9, 0.9], [3.7, 27.6, 27.8, 0.8], [-3.5, 27.3, 27.6, 0.8]];
    for (const [x, y, z, r] of eyes) { blob([x, y, z], [r + 0.4, r + 0.4, r + 0.4], C.orb); blob([x, y + 0.2, z + r * 0.85], [r * 0.3 + 0.35, r * 0.3 + 0.35, r * 0.3 + 0.35], C.eye); }
    for (const s of [-1, 1]) tube(curve([[s * 3, 27, 23], [s * 5, 32, 19], [s * 6, 33, 12]], 8), 1.6, 0.3, (p, { t }) => mix(C.chitin2, C.bone, t));
  }
  function mandible(s) {
    return () => {
      tube(curve([[s * 3.5, 20.5, 30], [s * 8.5, 19.5, 35], [s * 6, 18, 41], [s * 1.2, 17.5, 43]], 12), 2, 0.4, (p, { t }) => mix(C.boneDark, C.bone, t * 1.4));
      for (const t of [0.45, 0.62, 0.78]) { const q = curve([[s * 3.5, 20.5, 30], [s * 8.5, 19.5, 35], [s * 6, 18, 41], [s * 1.2, 17.5, 43]], 20)[Math.round(t * 20)]; spike(q, [q[0] - s * 2.2, q[1] - 0.3, q[2] + 0.4], 0.7, C.bone); }
    };
  }
  function feeler(s) { return () => tube(curve([[s * 5, 25, 30], [s * 11, 32, 38], [s * 14, 33, 47], [s * 16, 30, 54]], 16), 0.9, 0.35, (p, { t }) => t > 0.8 ? C.bone : C.chitin2); }
  const tail1Pts = curve([[0, 29, -28], [0, 31, -36], [0, 36, -42]], 10);
  const tail2Pts = curve([[0, 36, -42], [0, 45, -48], [0, 52, -43], [0, 53, -35]], 14);
  function tail1() { tube(tail1Pts, 6.5, 4.2, (p, { t }) => (t * 4) % 1 < 0.14 ? C.seam : mix(C.chitin2, C.chitin, t)); crystal([0, 37, -38], [2, 42, -41], 1.6); }
  function tail2() {
    tube(tail2Pts, 4.2, 1.8, (p, { t }) => (t * 6) % 1 < 0.14 ? C.seam : mix(C.chitin, C.chitin2, t));
    blob([0, 52, -39], [2.8, 2.6, 3.2], C.glow, 0.1, 1.5);                              // venom sac
    tube(curve([[0, 53, -36], [0, 53.5, -31], [0, 50.5, -27]], 8), 1.6, 0.25, (p, { t }) => mix(C.boneDark, C.bone, t));
  }
  function femur(l) { return () => { const k = add(lerp3(l.hip, l.knee, 0.5), [l.s * 2, 3, 0]); const pts = curve([l.hip, k, l.knee], 12); tube(pts, 2.6, 1.9, femurColor); for (const t of [0.35, 0.6, 0.82]) { const q = pts[Math.round(t * 12)]; spike(q, add(q, [l.s * 1.2, 3, -0.8]), 0.6, C.boneDark); } }; }
  function tibia(l) {
    return () => {
      const k = add(lerp3(l.knee, l.foot, 0.4), [l.s * 5, 2, 0]); const pts = curve([l.knee, k, l.foot], 16);
      blob(l.knee, [1.9, 1.9, 1.9], C.membrane, 0.15, 1.5); tube(pts, 2.1, 0.45, tibiaColor);
      for (const t of [0.2, 0.3, 0.42]) { const q = pts[Math.round(t * 16)]; spike(q, add(q, [l.s * 2.5, 1.2, (rnd(t * 100, 1, 2) - 0.5) * 2]), 0.4, C.chitin2); }
    };
  }
  const parts = [['body', '', [0, 25, 0], body], ['head', 'body', [0, 23, 20], head],
    ['mandible.l', 'head', [-3.5, 20.5, 30], mandible(-1)], ['mandible.r', 'head', [3.5, 20.5, 30], mandible(1)],
    ['feeler.l', 'head', [-5, 25, 30], feeler(-1)], ['feeler.r', 'head', [5, 25, 30], feeler(1)],
    ['tail1', 'body', [0, 29, -28], tail1], ['tail2', 'tail1', [0, 36, -42], tail2]];
  legs.forEach((l, i) => { parts.push([`leg${i}.femur`, 'body', l.hip, femur(l)], [`leg${i}.tibia`, `leg${i}.femur`, l.knee, tibia(l)]); });
  build('alien-crawler', S, parts, {
    version: 1,
    locomotion: { speed: 3.4, turn_rate: 540, body_height: 0, ground_follow: true, accel: 14, erratic: 0.9, accel_pitch: 0.03, turn_roll: 0.05 },
    legs: legs.map((l, i) => ({ chain: [`leg${i}.femur`, `leg${i}.tibia`], foot: l.foot, group: (l.i + (l.s > 0 ? 1 : 0)) % 2 })),
    gait: { stride: 0.42, lift: 0.16, step_time: 0.12, fidget: 4 },
    look: { part: 'body', yaw_limit: 20, pitch_min: -12, pitch_max: 12, stiffness: 32, scan_min: 0.08, scan_max: 0.55, scan_range: 140, lean: 0.06, crouch: 0.25, roll: 9 },
    springs: [{ part: 'tail1', stiffness: 45, damping: 3, gain: 2.5 }, { part: 'tail2', stiffness: 30, damping: 2, gain: 3.5 }],
    twitches: [{ part: 'head', amount: 22, rate: 5 }, { part: 'mandible.l', amount: 28, rate: 9 }, { part: 'mandible.r', amount: 28, rate: 10 },
      { part: 'feeler.l', amount: 40, rate: 7 }, { part: 'feeler.r', amount: 40, rate: 8 }],
    bob: { part: 'body', amount: 0.035 },
  }, 'Hostile crystal crawler, 2.6 m leg span: ten spider-high legs, crystal spine, scorpion tail with venom sac, hook mandibles, eight mint eyes. Rig: alien-crawler.rig.json (hectic, erratic).');
}

// ================================================================ alien-skitter (voxel 0.01)
{
  const S = 0.01, HIPY = 10;
  const legs = [];
  const Z = [5, 2.5, 0, -2.5], SPREAD = [15, 5, -5, -15], REACH = [24, 26, 26, 23];
  for (const s of [-1, 1]) Z.forEach((z, i) => {
    const hip = [s * 3.8, HIPY, z], foot = [s * REACH[i], 0, z + SPREAD[i]];
    legs.push({ s, i, ...legPlan(hip, foot, 22 - Math.abs(i - 1.5) * 1.5, 0.45) });
  });
  function body() {
    blob([0, 10, 3], [5, 3.6, 5.5], carapace([0, 10, 3], 3.6, 2.5), 0.08, 2);
    // swollen abdomen with glowing veins
    blob([0, 13, -7.5], [7.2, 6.6, 8.6], (p, info) => {
      const up = (p[1] - 13) / 6.6, n = noise(p, 2.2);
      if (up > -0.3 && Math.abs(n - 0.5) < 0.045) return C.glow;
      if (up < -0.5) return C.flesh;
      return mix(C.chitin, up > 0.4 ? C.sheen : C.chitin2, Math.max(0, up) + (noise(p, 1.3) - 0.5) * 0.4);
    }, 0.06, 3);
    blob([0, 15.5, -14.5], [1.6, 1.6, 1.4], C.membrane);            // spinneret
    const eyes = [[1.4, 12.6, 7.4, 1.0], [-1.4, 12.6, 7.4, 1.0], [2.9, 12, 6.6, 0.7], [-2.9, 12, 6.6, 0.7], [0.8, 13.4, 5.8, 0.6], [-0.8, 13.4, 5.8, 0.6]];
    for (const [x, y, z, r] of eyes) { blob([x, y, z], [r + 0.5, r + 0.5, r + 0.5], C.orb); blob([x, y, z + r * 0.6], [r * 0.6 + 0.3, r * 0.6 + 0.3, r * 0.5 + 0.3], C.red); }
    for (const l of legs) blob(l.hip, [1.2, 1.2, 1.2], C.vein);
    for (const [x, z] of [[2, 1], [-2.5, 0], [1, -3]]) spike([x, 13, z], [x * 1.5, 15.5, z - 2], 0.6, C.boneDark);
  }
  function fang(s) { return () => tube(curve([[s * 1.6, 8.6, 7.6], [s * 2.6, 7.4, 9.6], [s * 1.4, 5.6, 10.6], [s * 0.4, 5.2, 9.4]], 10), 1.2, 0.3, (p, { t }) => t < 0.35 ? C.chitin2 : mix(C.boneDark, C.bone, t)); }
  function femur(l) { return () => { const k = add(lerp3(l.hip, l.knee, 0.5), [l.s * 1.2, 1.5, 0]); tube(curve([l.hip, k, l.knee], 10), 1.15, 0.8, femurColor); }; }
  function tibia(l) {
    return () => {
      const k = add(lerp3(l.knee, l.foot, 0.35), [l.s * 3, 1.5, 0]);
      blob(l.knee, [0.9, 0.9, 0.9], C.chitin2); tube(curve([l.knee, k, l.foot], 14), 0.85, 0.3, tibiaColor);
    };
  }
  const parts = [['body', '', [0, 10, 0], body], ['fang.l', 'body', [-1.6, 8.6, 7.6], fang(-1)], ['fang.r', 'body', [1.6, 8.6, 7.6], fang(1)]];
  legs.forEach((l, i) => { parts.push([`leg${i}.femur`, 'body', l.hip, femur(l)], [`leg${i}.tibia`, `leg${i}.femur`, l.knee, tibia(l)]); });
  build('alien-skitter', S, parts, {
    version: 1,
    locomotion: { speed: 2.6, turn_rate: 900, body_height: 0, ground_follow: true, accel: 26, erratic: 1, accel_pitch: 0.012, turn_roll: 0.02 },
    legs: legs.map((l, i) => ({ chain: [`leg${i}.femur`, `leg${i}.tibia`], foot: l.foot, group: (l.i + (l.s > 0 ? 1 : 0)) % 2 })),
    gait: { stride: 0.16, lift: 0.05, step_time: 0.05, fidget: 7 },
    look: { part: 'body', yaw_limit: 26, pitch_min: -14, pitch_max: 14, stiffness: 42, scan_min: 0.05, scan_max: 0.35, scan_range: 160, lean: 0.012, crouch: 0.04, roll: 12 },
    twitches: [{ part: 'fang.l', amount: 35, rate: 12 }, { part: 'fang.r', amount: 35, rate: 13 }],
    flee: { radius: 4.5, boost: 1.5 },   // bolts from the robot / crawlers within 4.5 m
    bob: { part: 'body', amount: 0.008 },
  }, 'Tiny skittering parasite, 0.6 m leg span: eight needle legs, swollen abdomen with glowing violet veins, red eye cluster, twitching fangs. Rig: alien-skitter.rig.json (hectic, erratic).');
}

// ================================================================ nests (voxel 0.02)
// Breathing glass egg sacs with curled skitter embryos, on a wet goo mound under a thin slime coat.
// Anchor strands stick to walls / corners / ceiling / neighbouring nests within reach, else droop to the
// floor; sac sizes vary per placed nest (seeded), so a field of nests never repeats.
{
  const S = 0.02;
  const gooColor = (o, ry) => (p) => {
    const up = (p[1] - o[1]) / ry, n = noise(p, 3.2);
    if (Math.abs(noise(p, 2.1) - 0.5) < 0.035) return C.vein;
    if (n > 0.8) return C.mucus;
    if (noise(p, 1.3) > 0.83) return C.gooShine;
    return mix(C.goo, C.gooTop, Math.max(0, up) * 0.9 + (n - 0.5) * 0.3);
  };
  // wet mound: slime glass coat first, opaque body inside (later shapes win), pustules + bubbles on top
  function mound(o, r, amp) {
    blob([o[0], 0.6, o[2]], [r[0] * 1.45, 1.7, r[2] * 1.45], gooColor([0, 0, 0], 2), 0.3, 5);     // puddle
    blob(o, [r[0] + 1, r[1] + 1, r[2] + 1], p => p[1] > o[1] - r[1] * 0.2 && noise(p, 2.8) > 0.35 ? C.slime : undefined, amp, 5);
    blob(o, r, gooColor(o, r[1]), amp, 5);
    for (let i = 0; i < 14; i++) {
      const a = rnd(i, 3, 7) * 6.283, e = 0.15 + rnd(i, 5, 1) * 0.75, q = [o[0] + Math.cos(a) * r[0] * Math.cos(e) * 0.92, o[1] + Math.sin(e) * r[1] * 0.92, o[2] + Math.sin(a) * r[2] * Math.cos(e) * 0.92];
      if (i % 3 === 0) blob(q, [1.4, 1.2, 1.4], C.pustule); else blob(q, [1.3 + rnd(i, 1, 1), 1.1, 1.3 + rnd(i, 2, 2)], C.slime);
    }
  }
  // Egg sac: veined glass membrane, hollow, a curled embryo with folded legs, glowing yolk, two red eyes.
  function sac(c, r) {
    return () => {
      blob(sub(c, [0, r[1] * 0.85, 0]), [r[0] * 0.55, r[1] * 0.35, r[2] * 0.55], gooColor(c, r[1]), 0.2, 2);   // goo neck
      blob(c, r, p => { const n = noise(p, 2.6); return Math.abs(noise(p, 2.2) - 0.5) < 0.025 ? C.vein : n > 0.56 ? C.membrane : noise(p, 1.2) > 0.75 ? C.sacShine : C.sacSkin; }, 0.06, 3);   // flesh with translucent windows
      blob(c, [r[0] - 1.6, r[1] - 1.6, r[2] - 1.6], null);
      const e = add(c, [0, -r[1] * 0.15, 0]), er = [r[0] * 0.42, r[1] * 0.36, r[2] * 0.5];
      blob(add(e, [0, -er[1] * 0.2, -er[2] * 0.3]), [er[0] * 0.75, er[1] * 0.7, er[2] * 0.6], C.yolk);
      blob(e, er, carapace(e, er[1], 2.5), 0.1, 1.5);
      for (const sd of [-1, 1]) for (let k = 0; k < 3; k++) {
        const h = add(e, [sd * er[0] * 0.6, -er[1] * 0.3, (k - 1) * er[2] * 0.5]);
        tube(curve([h, add(h, [sd * er[0] * 0.7, -er[1] * 0.2, 0]), add(h, [sd * er[0] * 0.2, -er[1] * 0.6, er[2] * 0.3])], 5), 0.75, 0.75, C.chitin2);
      }
      for (const sd of [-1, 1]) blob(add(e, [sd * er[0] * 0.3, er[1] * 0.25, er[2] * 0.85]), [0.8, 0.8, 0.8], C.red);
    };
  }
  // Strand: arched goo tendril (2-bone anchor) ending in a sticky glob, with hanging drips.
  function strandPlan(hipR, hipY, a, tipR, kneeY, lift = 0) {
    const d = [Math.cos(a), 0, Math.sin(a)];
    const hip = [d[0] * hipR, hipY, d[2] * hipR], foot = [d[0] * tipR, lift, d[2] * tipR];
    // Slack: the knee curls sideways on the floor (the side the runtime sag solver picks, cross(dir, down)),
    // so the strand is ~30% longer than the hip-tip distance: it reaches farther and curves when relaxed.
    const side = [-d[2], 0, d[0]], m = hipR + (tipR - hipR) * 0.5, curl = (tipR - hipR) * 0.5;
    return { hip, foot, knee: [d[0] * m + side[0] * curl, kneeY, d[2] * m + side[2] * curl] };
  }
  const strandColor = (p, { t }) => noise(p, 1.4) > 0.8 ? C.gooShine : Math.abs(noise(p, 1.9) - 0.5) < 0.05 ? C.vein : mix(C.goo, C.gooTop, 0.3 + t * 0.4);
  function strandA(st) { return () => { const k = add(lerp3(st.hip, st.knee, 0.5), [0, 2, 0]); tube(curve([st.hip, st.knee], 6), 3.2, 2.1, strandColor); blob(st.hip, [4, 3.2, 4], gooColor(st.hip, 3), 0.25, 2); }; }
  function strandB(st) {
    return () => {
      const pts = curve([st.knee, st.foot], 12);
      blob(st.knee, [2.6, 2.4, 2.6], gooColor(st.knee, 2.4), 0.2, 1.5); tube(pts, 2.1, 1.5, strandColor); blob(st.foot, [3.6, 2.2, 3.6], gooColor(st.foot, 2.2), 0.3, 1.5);
      for (const t of [0.2, 0.45]) { const q = pts[Math.round(t * 12)]; tube([q, add(q, [0, -2.5 - rnd(t * 9, 1, 1) * 2, 0])], 0.8, 0.8, C.slime); blob(add(q, [0, -4.2, 0]), [1, 1.2, 1], C.slime); }
    };
  }
  function nest(name, voxelMound, sacs, strands, description) {
    const parts = [['body', '', [0, 8, 0], () => mound(...voxelMound)]];
    sacs.forEach(([c, r], i) => parts.push([`sac${i}`, 'body', sub(c, [0, r[1] * 0.85, 0]), sac(c, r)]));
    strands.forEach((st, i) => parts.push([`strand${i}.root`, 'body', st.hip, strandA(st)], [`strand${i}.tip`, `strand${i}.root`, st.knee, strandB(st)]));
    build(name, S, parts, {
      version: 1,
      // Immobile: no legs, negligible speed (Patrol does nothing visible); ground follow keeps it seated.
      locomotion: { speed: 0.001, turn_rate: 1, body_height: 0, ground_follow: true },
      legs: [],
      anchors: strands.map((st, i) => ({ chain: [`strand${i}.root`, `strand${i}.tip`], foot: st.foot, dir: st.dir, reach: 0 })),
      pulses: sacs.map((sc, i) => ({ part: `sac${i}`, amount: 0.07 + (i % 3) * 0.015, rate: 0.32 + (i % 4) * 0.09, sway: 4 + (i % 2) * 2, vary: 0.85 })),
    }, description);
  }
  const DEG = Math.PI / 180;
  // Cluster: wide mound, six sacs, seven strands (no strand straight ahead: the opening where skitters spill out).
  // Probe directions angle upward so a nearby wall is climbed (the strand sags from up the wall); in the open they miss and rest on the floor.
  const clusterStrands = [[180, [-1, 0.45, 0]], [0, [1, 0.45, 0]], [-90, [0, 0.45, -1]], [-135, [-0.6, 0.55, -0.6]], [-45, [0.6, 0.55, -0.6]], [135, [-0.7, 0.3, 0.7]], [45, [0.7, 0.3, 0.7]]]
    .map(([a, dir]) => ({ ...strandPlan(18, 6, a * DEG, 46, 3.2), dir }));
  nest('alien-nest', [[0, 6, 0], [22, 10, 20], 0.2], [
    [[0, 20, -2], [9.5, 11.5, 9.5]], [[-12, 15, 6], [7, 8, 7]], [[11, 14, 8], [6.5, 7.5, 6.5]],
    [[8, 16, -12], [7, 8.5, 7]], [[-9, 14, -12], [6, 7, 6]], [[2, 13, 15], [5.5, 6, 5.5]]], clusterStrands,
    'Gooey skitter nest: breathing glass egg sacs with curled embryos on a wet mound. Strands stick to nearby walls, corners, ceilings and neighbouring nests. Rig: alien-nest.rig.json.');
  // Spire: narrow mound with a tall stack of sacs; an up-strand finds ceilings. Good in corners.
  const spireStrands = [[180, [-1, 0.5, 0]], [0, [1, 0.5, 0]], [-90, [0, 0.5, -1]], [-135, [-0.6, 0.9, -0.6]], [-45, [0.6, 0.9, -0.6]]]
    .map(([a, dir]) => ({ ...strandPlan(12, 6, a * DEG, 40, 3.2), dir }));
  spireStrands.push({ hip: [0, 48, -2], knee: [6, 40, 3], foot: [13, 26, 8], dir: [0, 1, 0] });   // droops down the spire unless a ceiling is in reach
  nest('alien-nest-spire', [[0, 5, 0], [14, 8, 13], 0.2], [
    [[3, 14, 4], [7, 7.5, 7]], [[-4, 22, -2], [7.5, 8, 7.5]], [[4, 31, -3], [7, 7.5, 7]],
    [[-3, 39, 2], [6.5, 7, 6.5]], [[1, 47, 0], [6, 7, 6]], [[-8, 12, 8], [4.5, 5, 4.5]], [[9, 11, -8], [4, 4.5, 4]]], spireStrands,
    'Tall skitter nest spire: a stack of breathing egg sacs; strands reach walls, corners and the ceiling. Rig: alien-nest-spire.rig.json.');
}
