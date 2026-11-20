#!/usr/bin/env node
// Layer 0 wildlife + dormant rift monument. Independent outputs: never regenerates existing creatures.
'use strict';
// Outputs live in the asset folder; this script lives in dev/generators/.
process.chdir(require('path').join(__dirname, '../../assets/library/BLACK_START'));
const fs=require('fs');
require('./generated-guard.js').start('build-surface',{skip:['catalog.json'],dirs:['parts-scavenger','parts-stalker']});
const K=require('./voxkit.js');
const {blob,tube,curve,spike,add,lerp3,mix,noise,bounds,engine,writeAsset,writeVox}=K;
const C={shell:[130,105,67],ridge:[190,164,112],dark:[57,54,44],rust:[123,62,39],bone:[193,183,147],flesh:[87,77,55],eye:[144,201,167,1]};
const rules={version:1,materials:[{color:C.eye.slice(0,3),glow:0.45,range:0.3}]};
const catalog=JSON.parse(fs.readFileSync('catalog.json','utf8'));
function entry(name,model,s,voxels,description){let e=catalog.find(e=>e.name===name);if(!e){e={name};catalog.push(e);}Object.assign(e,{voxel_size:s,dimensions:[0,2,1].map(i=>model.hi[i]-model.lo[i]+1),voxels,description});}
function build(name,dir,s,parts,anim,description){
 fs.mkdirSync(dir,{recursive:true});const all=new Map();
 const built=parts.map(([name,parent,joint,draw])=>{K.begin();draw();const cells=K.raster(K.take());for(const [k,v]of cells)all.set(k,v);return{name,parent,joint,cells};});
 const model=bounds(all);
 const rig=built.map(p=>{const b=bounds(p.cells),q=[0,0,0];writeAsset(`${dir}/${p.name}.vpt.json`,p.cells,s);return{name:p.name,parent:p.parent,asset:`${dir}/${p.name}.vpt.json`,joint:engine(p.joint,model,s),shift:engine(q,model,s).map((v,i)=>Math.round((v-engine(q,b,s)[i])*10000)/10000)};});
 const voxels=writeAsset(`${name}.vpt.json`,all,s);writeVox(`vox/${name}.vox`,all,model);
 anim.legs=anim.legs.map(l=>({...l,foot:engine(l.foot,model,s)}));
 fs.writeFileSync(`${name}.rig.json`,JSON.stringify({version:1,name,parts:rig},null,1)+'\n');
 fs.writeFileSync(`${name}.anim.json`,JSON.stringify(anim,null,1)+'\n');
 for(const path of [`${name}.materials.json`,`${dir}/materials.json`])fs.writeFileSync(path,JSON.stringify(rules,null,1)+'\n');
 entry(name,model,s,voxels,description);console.log(`${name}: ${voxels} voxels, ${rig.length} parts`);
}
function shell(p){const n=noise(p,4);return mix(C.shell,C.ridge,n*0.7);}
function legParts(legs,parts){legs.forEach((l,i)=>{
 parts.push([`leg${i}.femur`,'body',l.hip,()=>tube(curve([l.hip,add(lerp3(l.hip,l.knee,.5),[l.side*2,2,0]),l.knee]),1.6,1.2,C.rust)]);
 parts.push([`leg${i}.tibia`,`leg${i}.femur`,l.knee,()=>{tube(curve([l.knee,add(lerp3(l.knee,l.foot,.5),[l.side*2,0,0]),l.foot]),1.2,.75,C.bone);spike(l.knee,add(l.knee,[l.side*3,3,-1]),1,C.dark);}]);
 });}
// Lively like the cave fauna: quick turns, darting bursts with abrupt stops, idle leg tapping, head scans with tilt,
// body lean/crouch into turns and stops. `o` overrides per species.
function animation(legs,speed,stride,o){return{version:1,locomotion:{speed,turn_rate:o.turn,ground_follow:true,accel:o.accel,erratic:o.erratic,accel_pitch:o.pitch,turn_roll:o.roll},legs:legs.map((l,i)=>({chain:[`leg${i}.femur`,`leg${i}.tibia`],foot:l.foot,group:l.group})),gait:{stride,lift:o.lift,step_time:o.step,fidget:o.fidget},look:{part:'head',yaw_limit:o.yaw,pitch_min:-18,pitch_max:22,stiffness:o.stiff,scan_min:o.scan[0],scan_max:o.scan[1],scan_range:o.scan[2],lean:o.lean,crouch:o.crouch,roll:o.tilt},twitches:[{part:'head',amount:o.twitch[0],rate:o.twitch[1]}],bob:{part:'body',amount:o.bob}};}
fs.mkdirSync('vox',{recursive:true});
{
 const legs=[];for(const side of[-1,1])for(let i=0;i<3;i++)legs.push({side,hip:[side*6,9,8-i*8],knee:[side*14,13,13-i*12],foot:[side*22,0,18-i*18],group:(i+(side>0?1:0))%2});
 const parts=[['body','',[0,10,0],()=>{blob([0,10,-2],[8,6,14],C.dark);for(let z=-12;z<10;z+=5)blob([0,14,z],[9,5,3.5],shell,.04,3);for(const side of[-1,1])tube([[side*7,13,-12],[side*8,14,0],[side*6,12,11]],1,1,C.rust);}],['head','body',[0,10,10],()=>{blob([0,9,14],[6,4,5],C.shell);for(const side of[-1,1]){blob([side*4,11,17],[1.3,1.4,1],C.eye);tube(curve([[side*3,12,16],[side*9,17,20],[side*10,15,25]]),.9,.75,C.bone);tube([[side*3,8,16],[side*4,5,20],[side,6,21]],1,.75,C.dark);}}]];
 legParts(legs,parts);build('ash-scavenger','parts-scavenger',.02,parts,animation(legs,2.6,.2,{turn:720,accel:24,erratic:.85,pitch:.03,roll:.05,lift:.08,step:.075,fidget:4.5,yaw:45,stiff:38,scan:[.08,.45,150],lean:.02,crouch:.05,tilt:14,twitch:[16,6],bob:.01}),'Ash scavenger: small sand-coloured plated beetle, six hooked legs and probing feelers. Forages in groups; flees first, fights when disturbed. Layer 0.');
}
{
 const legs=[];for(const side of[-1,1])for(let i=0;i<2;i++)legs.push({side,hip:[side*8,27,13-i*25],knee:[side*24,37,22-i*44],foot:[side*34,0,33-i*66],group:(i+(side>0?1:0))%2});
 const parts=[['body','',[0,29,0],()=>{blob([0,29,-2],[10,8,23],C.dark,.08,4);for(let z=-20;z<18;z+=6){blob([0,34,z],[11,5,4],shell);for(const side of[-1,1])spike([side*6,36,z],[side*10,45+(z+20)*.15,z-4],2,C.bone);}blob([0,28,-22],[7,5,7],C.rust);}],['head','body',[0,30,19],()=>{blob([0,29,23],[8,5,9],C.rust);blob([0,33,23],[7,3,7],C.shell);for(const side of[-1,1]){blob([side*5,31,29],[1.6,1.4,1.3],C.eye);tube(curve([[side*5,28,28],[side*10,23,34],[side*4,21,38]]),2,1,C.bone);spike([side*4,34,23],[side*12,43,34],1.6,C.bone);}}]];
 legParts(legs,parts);const anim=animation(legs,2.9,.38,{turn:420,accel:13,erratic:.4,pitch:.035,roll:.05,lift:.1,step:.11,fidget:1.8,yaw:40,stiff:30,scan:[.15,.8,120],lean:.05,crouch:.12,tilt:9,twitch:[11,3.5],bob:.025});
 build('dune-stalker','parts-stalker',.025,parts,anim,'Dune stalker: tall four-legged salt-bone hunter, rust armour, dorsal sail-spines and hooked jaws. Watches from ridges, braces, then charges. A larger elder guards the surface rift. Layer 0.');
}
K.begin();
// Fractured basalt arch, inert until the boss dies; all radiance belongs to runtime portal effects.
for(const side of[-1,1]){
 blob([side*27,8,0],[10,9,10],[54,57,55],.16,4);
 tube(curve([[side*28,4,0],[side*33,30,-1],[side*21,58,0],[side*5,67,1]]),5,3,[64,70,67]);
 for(let i=0;i<5;i++)blob([side*(30-i),17+i*8,0],[6,4,7],i%2?[91,102,94]:[46,51,51],.13,3);
 spike([side*29,15,0],[side*38,36,-1],4,[94,104,94]);
}
blob([0,1,0],[34,2,15],[65,69,61]);
const stone=K.raster(K.take()),b=bounds(stone),total=writeAsset('rift-monument.vpt.json',stone,.05);writeVox('vox/rift-monument.vox',stone,b);
entry('rift-monument',b,.05,total,'Broken basalt rift monument. Dormant stone arch; gameplay adds counter-rotating luminous rings, a vortex, rising motes and one light after the layer boss falls.');
fs.writeFileSync('rift-monument.materials.json',JSON.stringify({version:1,materials:[]})+'\n');
fs.writeFileSync('catalog.json',JSON.stringify(catalog,null,2)+'\n');
