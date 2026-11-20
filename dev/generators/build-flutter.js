#!/usr/bin/env node
// Small cave-wing, independently guarded: never rewrites hand-edited crawler/skitter outputs.
'use strict';
// Outputs live in the asset folder; this script lives in dev/generators/.
process.chdir(require('path').join(__dirname, '../../assets/library/BLACK_START'));
const fs = require('fs');
require('./generated-guard.js').start('build-flutter', {skip:['catalog.json'], dirs:['parts-flutter']});
const K = require('./voxkit.js');
const {blob,tube,curve,add,sub,lerp3,bounds,engine,writeAsset,writeVox} = K;
const S=0.0125, dir='parts-flutter', name='alien-flutter';
const C={shell:[48,64,58],ridge:[109,133,94],flesh:[99,67,87],bone:[170,157,112],wing:[92,119,111],vein:[47,69,64],eye:[154,238,156,1]};
const parts=[];const legs=[];
function part(n,parent,joint,draw){K.begin();draw();parts.push({name:n,parent,joint,cells:K.raster(K.take())});}
part('body','',[0,12,0],()=>{
 blob([0,12,1],[6,5,11],C.shell,0.08,3);
 blob([0,11,-12],[7,6,11],C.flesh,0.08,3);
 for(let z=-20;z<0;z+=4)blob([0,14,z],[6,3,1.1],C.ridge);
});
part('head','body',[0,12,10],()=>{
 blob([0,13,13],[5,4,5],C.shell);
 for(const s of [-1,1]){
  blob([s*3.7,14,15],[2,2.5,2],C.eye);
  tube(curve([[s*2,16,15],[s*7,23,18],[s*6,24,24]]),0.8,0.75,C.bone);
  tube([[s*2,11,17],[s*3,8,20],[s,9,21]],1,0.75,C.bone);
 }
});
for(const s of [-1,1]){
 for(let i=0;i<3;i++){
  const hip=[s*4,12,6-i*6],knee=[s*(13+i),15,9-i*9],foot=[s*(19+i),0,13-i*13];
  const n=legs.length;
  legs.push({hip,knee,foot,group:(i+(s>0?1:0))%2});
  part(`leg${n}.femur`,'body',hip,()=>tube([hip,knee],1.3,1,C.shell));
  part(`leg${n}.tibia`,`leg${n}.femur`,knee,()=>tube(curve([knee,add(lerp3(knee,foot,0.5),[s*2,0,0]),foot]),1,0.75,C.bone));
 }
 for(let w=0;w<2;w++){
  const joint=[s*4,16,4-w*9];
  part(`wing${s>0?'R':'L'}${w}`,'body',joint,()=>{
   // Thin opaque, veined chitin sails: no extra ray-traced lights or expensive glass surfaces.
   blob([s*19,16,0-w*11],[15,0.8,9-w*2],C.wing);
   for(let v=0;v<4;v++)tube([joint,[s*(29-v*2),16,8-w*12-v*4]],0.8,0.75,C.vein);
  });
 }
}
fs.mkdirSync(dir,{recursive:true});
const all=new Map();for(const p of parts)for(const [k,v] of p.cells)all.set(k,v);
const model=bounds(all);
const rig=parts.map(p=>{
 const b=bounds(p.cells),q=[0,0,0];
 const shift=engine(q,model,S).map((v,i)=>Math.round((v-engine(q,b,S)[i])*10000)/10000);
 writeAsset(`${dir}/${p.name}.vpt.json`,p.cells,S);
 return {name:p.name,parent:p.parent,asset:`${dir}/${p.name}.vpt.json`,joint:engine(p.joint,model,S),shift};
});
const voxels=writeAsset(`${name}.vpt.json`,all,S);fs.mkdirSync('vox',{recursive:true});writeVox(`vox/${name}.vox`,all,model);
fs.writeFileSync(`${name}.rig.json`,JSON.stringify({version:1,name,parts:rig},null,1)+'\n');
const anim={version:1,
 locomotion:{speed:1.6,turn_rate:420,ground_follow:true,accel:16,erratic:0.5},
 legs:legs.map((l,i)=>({chain:[`leg${i}.femur`,`leg${i}.tibia`],foot:engine(l.foot,model,S),group:l.group})),
 gait:{stride:0.15,lift:0.045,step_time:0.09,fidget:1.5},
 look:{part:'head',yaw_limit:35,pitch_min:-20,pitch_max:25,stiffness:30,scan_min:0.2,scan_max:0.8,scan_range:100},
 twitches:[{part:'head',amount:12,rate:4}],
 wings:parts.filter(p=>p.name.startsWith('wing')).map(p=>({part:p.name,side:p.name.includes('R')?1:-1,rate:17,amount:48,fold:68}))};
fs.writeFileSync(`${name}.anim.json`,JSON.stringify(anim,null,1)+'\n');
const rules=JSON.stringify({version:1,materials:[{color:C.eye.slice(0,3),glow:0.7,range:0.3}]},null,1)+'\n';
fs.writeFileSync(`${dir}/materials.json`,rules);fs.writeFileSync(`${name}.materials.json`,rules);
const catalog=JSON.parse(fs.readFileSync('catalog.json','utf8'));
let entry=catalog.find(e=>e.name===name);if(!entry){entry={name};catalog.push(entry);}
Object.assign(entry,{voxel_size:S,dimensions:[0,2,1].map(i=>model.hi[i]-model.lo[i]+1),voxels,description:'Cave-wing: 0.85 m wingspan, six hooked legs, four veined wings, feelers and pale glow-only eyes. Perches, chirps, flits and defends itself.'});
fs.writeFileSync('catalog.json',JSON.stringify(catalog,null,2)+'\n');
console.log(`${name}: ${voxels} voxels, ${rig.length} parts, ${((model.hi[0]-model.lo[0]+1)*S).toFixed(2)} m wingspan`);
