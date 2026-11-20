#!/usr/bin/env node
// Kamikaze creature for the Depths: a squat six-legged crawler carrying a huge round sac on its back that
// pulses red. It shuffles slowly at the robot and detonates (game.c3: BLOATER). Run from anywhere (node dev/generators/<script>):
//   node build-bloater.js   (--force: back up edited outputs, then overwrite)
//
//   alien-bloater  ~1.0 m tall, 6 stubby legs, swollen sac (red glowing veins + core), small fanged head
//
// Writes parts-bloater/*.vpt.json, alien-bloater.{vpt,rig,anim,materials}.json, vox/alien-bloater.vox and a
// catalog entry. Same conventions as build-crawlers.js (kept separate so that script's guarded outputs are
// never touched by this one).
'use strict';
// Outputs live in the asset folder; this script lives in dev/generators/.
process.chdir(require('path').join(__dirname, '../../assets/library/BLACK_START'));
const fs = require('fs');
require('./generated-guard.js').start('build-bloater', { skip: ['catalog.json'], dirs: ['parts-bloater'] });
const K = require('./voxkit.js');
const { add, sub, lerp3, mix, rnd, noise, curve, blob, tube, spike, raster, bounds, engine, writeAsset, writeVox } = K;

const C = {
  chitin: [30, 24, 40], chitin2: [52, 38, 66], sheen: [92, 70, 120], seam: [16, 12, 22],
  flesh: [116, 70, 84], membrane: [92, 30, 46], bone: [198, 182, 160], boneDark: [146, 124, 108], orb: [10, 11, 14],
  sacSkin: [104, 40, 44], sacDark: [64, 22, 30], sacShine: [168, 92, 96],
  // emissive (matched by the materials rules below; 4th element = exact colour, no mottling)
  vein: [255, 52, 34, 1], core: [255, 96, 48, 1], eye: [255, 140, 40, 1],
};
const RULES = [
  { color: C.vein.slice(0, 3), glow: 1.3, flicker: 0.5, range: 0.3 },                         // veins: glow, cast nothing
  { color: C.core.slice(0, 3), glow: 1.6, light: [255, 60, 30], flicker: 0.6, range: 2.6 },    // one red light per bloater
  { color: C.eye.slice(0, 3), glow: 1.2, range: 0.3 },
];

function build(name, voxel, parts, anim, description) {
  const dir = 'parts-bloater';
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
  fs.writeFileSync(`${name}.anim.json`, JSON.stringify(anim, null, 1) + '\n');
  const rules = '{"version":1,"materials":[\n' + RULES.map(r => '  ' + JSON.stringify(r)).join(',\n') + '\n]}\n';
  fs.writeFileSync(`${dir}/materials.json`, rules); fs.writeFileSync(`${name}.materials.json`, rules);
  const catalog = JSON.parse(fs.readFileSync('catalog.json', 'utf8'));
  let entry = catalog.find(e => e.name === name); if (!entry) { entry = { name }; catalog.splice(1, 0, entry); }
  Object.assign(entry, { voxel_size: voxel, dimensions: [0, 2, 1].map(i => model.hi[i] - model.lo[i] + 1), voxels: total, description });
  fs.writeFileSync('catalog.json', JSON.stringify(catalog, null, 2) + '\n');
  const W = model.hi.map((v, i) => ((v - model.lo[i] + 1) * voxel).toFixed(2));
  console.log(`${name}: ${total} voxels, ${W[0]} x ${W[1]} x ${W[2]} m, ${rig.length} parts`);
}
function legPlan(hip, foot, kneeY, kf) {
  const h = sub(foot, hip); h[1] = 0;
  return { hip, foot, knee: [hip[0] + h[0] * kf, kneeY, hip[2] + h[2] * kf] };
}
function carapace(o, ry) {
  return p => {
    const up = (p[1] - o[1]) / ry;
    if (up < -0.45) return mix(C.flesh, C.membrane, noise(p, 2.5));
    if (((p[2] + 1000) % 4) / 4 < 0.16 && up > -0.2) return C.seam;
    return mix(C.chitin, up > 0.55 ? C.sheen : C.chitin2, Math.max(0, up) * 0.9);
  };
}

// ================================================================ alien-bloater (voxel 0.02)
{
  const S = 0.02, HIPY = 12;
  const legs = [];
  const Z = [7, 0, -7], SPREAD = [9, 0, -9], REACH = [24, 26, 24];
  for (const s of [-1, 1]) Z.forEach((z, i) => {
    const hip = [s * 8, HIPY, z], foot = [s * REACH[i], 0, z + SPREAD[i]];
    legs.push({ s, i, ...legPlan(hip, foot, 20, 0.5) });
  });
  const SAC = [0, 33, -3], SR = [17, 16, 18];
  function body() {
    blob([0, 13, 1], [10, 6.5, 12], carapace([0, 13, 1], 6.5), 0.1, 3);
    blob([0, 19, -3], [8, 3, 9], C.membrane, 0.25, 2);                     // fleshy saddle the sac sits in
    for (const l of legs) blob(l.hip, [2.4, 2.4, 2.4], C.membrane, 0.2, 2);
  }
  function head() {
    blob([0, 12, 14], [6, 4.5, 5], carapace([0, 12, 14], 4.5), 0.1, 2);
    for (const [x, y, z, r] of [[2.2, 14, 18, 1.3], [-2.2, 14, 18, 1.3], [3.8, 13, 16.6, 0.9], [-3.8, 13, 16.6, 0.9]]) {
      blob([x, y, z], [r + 0.4, r + 0.4, r + 0.4], C.orb); blob([x, y + 0.1, z + r * 0.7], [r * 0.5, r * 0.5, r * 0.4], C.eye);
    }
    for (const s of [-1, 1]) tube(curve([[s * 2, 9.5, 17], [s * 3, 7.5, 19.5], [s * 1, 6, 20]], 6), 1, 0.3, (p, { t }) => mix(C.boneDark, C.bone, t));
  }
  // The sac: a thin-skinned bladder with glowing red veins and a hot core seen through translucent patches.
  function sac() {
    blob(add(SAC, [0, -SR[1] * 0.8, 0]), [8, 4, 9], C.membrane, 0.2, 2);    // neck
    blob(SAC, SR, p => {
      const n = noise(p, 2.4), v = Math.abs(noise(p, 7) - 0.5), v2 = Math.abs(noise(add(p, [40, 0, 0]), 4) - 0.5), up = (p[1] - SAC[1]) / SR[1];
      if (v < 0.022 || v2 < 0.016) return C.vein;
      if (v < 0.045 || v2 < 0.03) return C.sacDark;
      if (n > 0.8 && up > 0) return C.sacShine;
      return mix(C.sacDark, C.sacSkin, 0.5 + up * 0.4 + (n - 0.5) * 0.6);
    }, 0.05, 3);
    blob(SAC, [SR[0] * 0.55, SR[1] * 0.55, SR[2] * 0.55], C.core);           // hot core (hidden inside, lights the room)
    // blister nodules
    for (let i = 0; i < 9; i++) {
      const a = rnd(i, 4, 1) * 6.283, e = 0.1 + rnd(i, 2, 7) * 1.1, q = [SAC[0] + Math.cos(a) * SR[0] * Math.cos(e), SAC[1] + Math.sin(e) * SR[1], SAC[2] + Math.sin(a) * SR[2] * Math.cos(e)];
      blob(q, [2, 1.8, 2], i % 3 === 0 ? C.vein : C.sacShine);
    }
    // windows into the core: punch through the skin in a few places
    for (const [x, y, z] of [[9, 44, 4], [-10, 41, -8], [3, 48, -12]]) blob([x, y, z], [2.2, 2.2, 2.2], C.core);
  }
  function femur(l) { return () => tube(curve([l.hip, add(lerp3(l.hip, l.knee, 0.5), [l.s * 1.5, 2, 0]), l.knee], 8), 2.2, 1.7, (p, { t }) => mix(C.chitin, C.chitin2, t)); }
  function tibia(l) {
    return () => {
      blob(l.knee, [1.8, 1.8, 1.8], C.membrane, 0.15, 1.5);
      tube(curve([l.knee, add(lerp3(l.knee, l.foot, 0.4), [l.s * 2, 1, 0]), l.foot], 10), 1.7, 0.6, (p, { t }) => t > 0.7 ? mix(C.boneDark, C.bone, (t - 0.7) * 3) : mix(C.chitin2, C.chitin, t));
      spike(l.knee, add(l.knee, [l.s * 1.5, 3, 0]), 0.6, C.boneDark);
    };
  }
  const parts = [['body', '', [0, 13, 0], body], ['head', 'body', [0, 12, 10], head], ['sac', 'body', [0, 19, -3], sac]];
  legs.forEach((l, i) => { parts.push([`leg${i}.femur`, 'body', l.hip, femur(l)], [`leg${i}.tibia`, `leg${i}.femur`, l.knee, tibia(l)]); });
  build('alien-bloater', S, parts, {
    version: 1,
    locomotion: { speed: 1.1, turn_rate: 220, body_height: 0, ground_follow: true, accel: 5, erratic: 0.15, accel_pitch: 0.02, turn_roll: 0.03 },
    legs: legs.map((l, i) => ({ chain: [`leg${i}.femur`, `leg${i}.tibia`], foot: l.foot, group: (l.i + (l.s > 0 ? 1 : 0)) % 2 })),
    gait: { stride: 0.2, lift: 0.07, step_time: 0.16, fidget: 1 },
    look: { part: 'body', yaw_limit: 14, pitch_min: -8, pitch_max: 8, stiffness: 14, scan_min: 0.2, scan_max: 0.9, scan_range: 60, lean: 0.03, crouch: 0.03, roll: 5 },
    pulses: [{ part: 'sac', amount: 0.09, rate: 1.4, sway: 3, vary: 0.25 }],
    twitches: [{ part: 'head', amount: 10, rate: 3 }],
    bob: { part: 'body', amount: 0.012 },
  }, 'Kamikaze bloater, ~1 m: six stubby legs carrying a huge pulsing sac with glowing red veins. Shuffles at you and detonates. Rig: alien-bloater.rig.json.');
}
