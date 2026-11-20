// Goxel 0.15.1: run from BLACK_START with goxel --script=build-scenery.js
// Only writes this expansion. Original models and hand-authored scenes are untouched.
import * as std from 'std';
let cells=new Map(), entries=[];
const C={rock:[79,78,75],rock2:[88,85,79],rock3:[69,71,73],dust:[107,100,89],
 sand:[126,112,92],sand2:[136,121,100],sand3:[116,105,90],crack:[48,49,48],
 wood:[105,99,88],woodLight:[139,130,111],woodDark:[66,65,61],
 panel:[93,103,107],deck:[73,82,87],trim:[35,44,49],recess:[50,60,66],
 pale:[163,165,157],amber:[181,139,61],glass:[150,196,214],lamp:[255,206,140,1]};
function start(){cells=new Map();}
// No independent per-voxel random colour/no rust speckle: broad material regions only.
function put(x,y,z,c){x=Math.round(x);y=Math.round(y);z=Math.round(z);let key=`${x},${y},${z}`;if(!c){cells.delete(key);return;}cells.set(key,[x,y,z,...c.slice(0,3),c[3]||0]);}
function box(x0,y0,z0,x1,y1,z1,c){for(let x=x0;x<=x1;x++)for(let y=y0;y<=y1;y++)for(let z=z0;z<=z1;z++)put(x,y,z,c);}
function ell(cx,cy,cz,rx,ry,rz,c){for(let x=Math.ceil(cx-rx);x<=cx+rx;x++)for(let y=Math.ceil(cy-ry);y<=cy+ry;y++)for(let z=Math.ceil(cz-rz);z<=cz+rz;z++)if(((x-cx)/rx)**2+((y-cy)/ry)**2+((z-cz)/rz)**2<=1)put(x,y,z,c);}
function limb(a,b,r0,r1,c){let n=Math.ceil(Math.hypot(...a.map((v,i)=>v-b[i]))*1.6);for(let i=0;i<=n;i++){let t=i/n,p=a.map((v,k)=>v+(b[k]-v)*t),r=r0+(r1-r0)*t;ell(...p,r,r,r,c);put(...p,c);}}
function save(name,size,description){
 const rows=Array.from(cells.values()).sort((a,b)=>a[2]-b[2]||a[1]-b[1]||a[0]-b[0]);
 let lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity];
 for(let v of rows)for(let i=0;i<3;i++){lo[i]=Math.min(lo[i],v[i]);hi[i]=Math.max(hi[i],v[i]);}
 let dimensions=hi.map((v,i)=>v-lo[i]+1);
 if(Math.max(...dimensions)>128||dimensions.reduce((a,b)=>a*b,1)>2097152)throw Error(`Asset exceeds engine limits: ${name}`);
 let volume=new Volume();for(let v of rows)volume.setAt(v.slice(0,3),[...v.slice(3,6),255]);volume.save(`vox/${name}.vox`);
 let f=std.open(`${name}.vpt.json`,'w');f.puts(JSON.stringify({version:1,voxel_size:size,up:'z',voxels:rows}));f.close();
 entries.push({name,voxel_size:size,dimensions,voxels:rows.length,description});console.log(`Created ${name}: ${rows.length} voxels`);
}
// Faceted convex chunks, intersecting tilted planes rather than smooth spheres.
// Geology uses a handful of broad tilted strata, not random voxel stippling.
function rock(cx,cy,cz,rx,ry,rz,seed=0,sandy=false){
 let yaw=seed*.47,co=Math.cos(yaw),si=Math.sin(yaw);
 for(let x=Math.ceil(cx-rx);x<=cx+rx;x++)for(let y=Math.ceil(cy-ry);y<=cy+ry;y++)for(let z=Math.max(0,Math.ceil(cz-rz));z<=cz+rz;z++){
  let dx=(x-cx)/rx,dy=(y-cy)/ry,nx=dx*co+dy*si,ny=-dx*si+dy*co,nz=(z-cz)/rz;
  if(nx*nx+ny*ny+nz*nz>1.08||Math.abs(nx)>.91||Math.abs(ny)>.9||nz>.85+.17*nx-.11*ny||nz<-.9)continue;
  if(nx+.6*ny+.7*nz>1.26||-nx+.4*ny+.65*nz>1.24)continue;
  if(Math.abs(nx)*.78+Math.abs(ny)*.6+Math.abs(nz)*.4>1.16||Math.abs(nx+.45*ny+.25*nz)>1.12||Math.abs(ny-.35*nx-.15*nz)>1)continue;
  let band=((Math.floor((z+.13*x+.08*y+seed*3)/9)%5)+5)%5;
  let c=sandy?(band===0?C.sand3:band===3?C.sand2:C.sand):(band===0?C.rock3:band===3?C.rock2:C.rock);
  if(nz>.67)c=sandy?C.sand2:C.dust;
  put(x,y,z,c);
 }
}
start();rock(0,0,9,27,21,19,1);save('rock-boulder-low',.1,'Low broad 5m basalt boulder; bevelled planes and subtle strata.');
start();rock(-10,0,19,19,23,26,2);rock(15,3,15,16,18,23,4);
// One coherent fracture separates the two halves.
for(let z=0;z<=48;z++)for(let y=-25;y<=25;y++)for(let w=-1;w<=1;w++)put(Math.round(z*.11)+w,y,z,null);
save('rock-boulder-split',.1,'Split basalt boulder with a deep inclined cleft; two uneven halves.');
start();rock(0,0,25,19,17,35,5,true);rock(14,1,7,13,14,13,1,true);save('rock-boulder-upright',.1,'Upright wind-worn pale boulder; angled cap, buttress and broad sediment bands.');
start();rock(-20,2,20,30,25,28,1,true);rock(12,0,29,36,22,38,3,true);rock(35,4,13,20,20,19,4,true);
save('rock-layered-outcrop',.2,'~20m layered escarpment, staggered slabs and slanted exposed strata.');
start();rock(-17,0,44,16,17,51,2);rock(14,4,30,17,18,37,4);rock(1,-10,13,20,15,19,1);
save('rock-spire-cluster',.25,'~23m tall eroded basalt needles; three unequal spires and a shared rocky foot.');
start();rock(-31,0,25,16,18,30,2,true);rock(31,1,22,17,19,29,1,true);rock(0,0,50,47,17,16,0,true);
for(let x=-24;x<=24;x++)for(let z=0;z<=45;z++)if((x/24)**2+((z-15)/31)**2<1)box(x,-22,z,x,22,z,null);
save('rock-natural-arch',.25,'~22m natural stone arch with an open passage, asymmetric piers and a massive sloped lintel.');
start();
for(let i=0;i<15;i++){let x=((i*29)%65)-32,y=((i*43)%53)-26,r=3+(i%4)*2;rock(x,y,r*.3,r+2,r,r*.8,i);}
save('rock-scree-patch',.1,'Loose field of fifteen angular stones, varying size and orientation; no artificial slab underneath.');
// Leafless, tapered silhouettes: sun-bleached wood, exposed fractures, no rust.
function roots(){for(let a=0;a<6.2;a+=1.25)limb([0,0,7],[Math.cos(a)*12,Math.sin(a)*12,1],3,1,C.woodDark);}
start();roots();
limb([0,0,2],[-5,1,35],5,3.8,C.wood);limb([-5,1,35],[3,3,65],3.8,2.5,C.wood);limb([3,3,65],[-3,4,88],2.5,.7,C.woodLight);
for(let [a,b,c] of [ [[-4,1,32],[-24,-2,49],[-31,0,70]], [[0,2,53],[23,7,67],[33,6,82]], [[2,3,65],[12,-17,76],[9,-25,89]] ]){limb(a,b,2.4,1.3,C.wood);limb(b,c,1.3,.5,C.woodLight);}
limb([-24,-2,49],[-34,-11,53],1.2,.5,C.woodLight);limb([23,7,67],[33,17,70],1.1,.5,C.woodLight);
save('dead-tree-crooked',.075,'~7m crooked leafless tree; exposed roots, leaning trunk and snapped asymmetric limbs.');
start();roots();limb([0,0,3],[2,0,38],6,4,C.woodDark);
for(let s of [-1,1]){limb([2,0,33],[s*15,s*3,61],4,2.4,C.wood);limb([s*15,s*3,61],[s*25,s*7,85-s*6],2.4,.8,C.woodLight);limb([s*15,s*3,59],[s*30,-9,68],1.8,.6,C.wood);}
limb([1,0,25],[4,-20,46],2.6,1.2,C.wood);limb([4,-20,46],[11,-29,58],1.2,.6,C.woodLight);
save('dead-tree-forked',.075,'Tall forked dead tree; heavier charred base and two bleached, broken crowns.');
start();limb([-38,0,7],[36,4,6],5,3.2,C.wood);ell(-38,0,7,1,4,4,C.woodLight);ell(-39,0,7,1,2,2,C.woodDark);
for(let [x,y,z] of [[-20,-15,24],[0,18,16],[18,-10,20]])limb([x,2,7],[x+4,y,z],2,.7,C.woodLight);
save('dead-tree-fallen',.075,'Fallen trunk with pale broken end grain and three snapped branches; ~6m long.');
start();roots();limb([0,0,3],[2,1,27],8,6,C.woodDark);ell(2,1,27,6,6,2,C.woodLight);ell(2,1,28,3.5,3.5,4,null);
limb([-4,1,19],[-8,2,39],2,.6,C.wood);limb([6,2,20],[8,4,34],2,.8,C.woodLight);
save('dead-stump-hollow',.05,'Hollow broken stump with a dark heart, exposed pale rim, splinters and roots.');
for(let variant=0;variant<2;variant++){
 start();for(let i=0;i<9;i++){let a=i*2.4,spread=variant?14:24,h=variant?34:22,p=[Math.cos(a)*spread,Math.sin(a)*spread,9+(i*7)%h];
  limb([0,0,1],p,1.8,.65,C.woodDark);limb(p,[p[0]*1.3,p[1]*1.3,p[2]+5],.8,.4,C.woodLight);
  limb(p,[p[0]+Math.cos(a+1)*8,p[1]+Math.sin(a+1)*8,p[2]+3],.7,.4,C.wood);
 }
 save(variant?'dead-scrub-upright':'dead-scrub-spreading',.05,variant?'Narrow upright dead thorn scrub, irregular twigs; no leaves.':'Low spreading wind-flattened dead scrub, radial twisted twigs; no leaves.');
}
start();
for(let i=0;i<9;i++){let a=i*2.4,len=15+(i%3)*4;for(let step=0;step<=40;step++){
 let t=step/40,r=t*len,z=3+Math.sin(t*Math.PI)*13,width=3.5*(1-t);
 for(let w=-width;w<=width;w+=.5)put(Math.cos(a)*r-Math.sin(a)*w,Math.sin(a)*r+Math.cos(a)*w,z,Math.abs(w)<.7?C.woodLight:C.wood);
 }}limb([0,0,2],[1,0,31],2,.5,C.woodLight);
save('dead-agave',.05,'Desiccated alien rosette: nine broad drooping blades and a brittle central spear; bone-grey, no green.');
// Clean corridor kit. Four broad deck panels instead of 64 tread plates.
// A single seam, base trim, large insets, no random rust/speckle or tiny vents.
function floor(){
 box(-40,-40,0,39,39,3,C.trim);box(-39,-39,4,38,38,5,C.deck);
 box(-1,-39,5,0,38,5,C.recess);box(-39,-1,5,38,0,5,C.recess);
 for(let x of [-36,35]){box(x,-36,5,x,35,5,C.recess);for(let y=-30;y<=30;y+=20)box(x,y,5,x,y+6,5,C.amber);}
}
function wall(window=false){
 box(-40,-3,0,39,2,63,C.recess);
 for(let y of [-4,3]){box(-37,y,8,36,y,51,C.panel);box(-1,y,8,0,y,51,C.recess);box(-40,y,0,39,y,5,C.trim);box(-40,y,59,39,y,63,C.trim);box(-26,y,55,25,y,55,C.pale);}
 if(window){box(-32,-4,24,31,3,47,C.trim);box(-30,-5,26,29,4,45,null);box(-30,-1,26,29,0,45,C.glass);box(-1,-2,26,0,1,45,C.trim);}
 else {box(25,-5,16,28,-5,21,C.trim);box(26,-6,19,27,-6,20,C.amber);}
}
function side(axis,positive,window=false){
 let old=cells;cells=new Map();wall(window);let rows=Array.from(cells.values());cells=old;
 for(let v of rows){let [x,y,z,r,g,b,e]=v;if(axis==='x')put(positive?36+y:-37-y,x,z+6,[r,g,b,e]);else put(x,positive?36+y:-37-y,z+6,[r,g,b,e]);}
}
start();floor();save('corridor-clean-floor',.05,'4m square quiet deck: four broad plates, recessed cross seam, sparse amber edge markers. Walking surface Y=0.3m.');
start();wall();save('corridor-clean-wall',.05,'4m x 3.2m double-sided wall; large flat panels, restrained base trim, one seam, no voxel speckle.');
start();wall(true);save('corridor-clean-window',.05,'4m clean wall with a broad transparent observation pane and one mullion; matches the existing glass material.');
start();
box(-40,-3,0,-29,2,63,C.trim);box(28,-3,0,39,2,63,C.trim);box(-40,-3,54,39,2,63,C.trim);
for(let x of [-38,30])box(x,-4,6,x+7,-4,51,C.panel);box(-26,-4,56,25,-4,59,C.panel);box(-16,-5,57,15,-5,57,C.lamp);
box(31,-5,22,35,-4,31,C.recess);box(32,-6,27,34,-6,28,C.amber);
save('corridor-clean-doorway',.05,'Open 2.8m-wide, 2.7m-high passage frame; broad surfaces, warm header light, access panel.');
start();floor();side('x',false);side('x',true,true);save('corridor-clean-straight',.05,'Open-top 4m straight module: smooth floor, two 3.2m walls, one observation window. Overall height 3.5m.');
start();floor();side('x',false);side('y',true);save('corridor-clean-corner',.05,'Open-top 4m corner module, openings on +X and -Y in the Z-up source; broad unbroken panels.');
start();floor();side('y',true,true);save('corridor-clean-junction',.05,'Open-top 4m T-junction: one glazed back wall, three matching full-width connections.');
start();box(-40,-40,0,39,39,3,C.recess);box(-36,-36,0,35,35,0,C.panel);
for(let x of [-26,25]){box(x-2,-29,0,x+2,28,0,C.trim);box(x,-26,0,x,25,0,C.lamp);}
box(-1,-36,0,0,35,0,C.recess);
save('corridor-clean-ceiling',.05,'4m removable ceiling tile; two recessed warm linear lights on underside, broad clean panels. Place at Y=3.5m over complete modules.');
// Upsert only this kit; preserve the existing industrial and megastructure entries.
let f=std.open('catalog.json','r'),all=f?JSON.parse(f.readAsString()):[];if(f)f.close();
const names=new Set(entries.map(e=>e.name));all=all.filter(e=>!names.has(e.name)).concat(entries);
f=std.open('catalog.json','w');f.puts(JSON.stringify(all,null,2)+'\n');f.close();
f=std.open('scenery-catalog.json','w');f.puts(JSON.stringify(entries,null,2)+'\n');f.close();
