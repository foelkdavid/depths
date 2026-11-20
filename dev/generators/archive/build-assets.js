// Run from this directory: goxel --script=build-assets.js
// Goxel's JavaScript API authors and exports the VOX volumes directly.
import * as std from 'std';
const C = {
  steel:[65,76,79], edge:[105,119,119], dark:[26,34,39], black:[15,20,24],
  yellow:[193,133,36], gold:[234,172,49], rust:[112,61,39], bolt:[150,155,144],
  blue:[38,161,233], ice:[123,227,255], red:[240,64,36], green:[91,212,146],
  white:[235,230,193], alien:[51,45,68], violet:[112,77,144], crystal:[128,111,185],
  mint:[89,213,187], bone:[177,158,145],
  // Glass is a plain colour; VPT's materials.json turns it into refractive glass.
  glass:[150,196,214], lamp:[255,206,140],
  // Former lamp colours stay distinct (the user can make them glow in the Materials dialog); nothing glows by default.
  head:[240,236,210]
};
let cells, catalog=[];
function start(){cells=new Map();}
function put(x,y,z,c){
  x=Math.round(x);y=Math.round(y);z=Math.round(z);
  if(!c){cells.delete(`${x},${y},${z}`);return;}
  // Deterministic, restrained surface wear. Emissive surfaces stay clean.
  let h=((Math.imul(x,73856093)^Math.imul(y,19349663)^Math.imul(z,83492791))>>>0);
  let v=c.slice();
  if(!c[3]&&c!==C.glass) {let d=(h%11)-5;for(let i=0;i<3;i++)v[i]=Math.max(0,Math.min(255,v[i]+d));if(h%97===0)v=C.rust.slice();}
  cells.set(`${x},${y},${z}`,[x,y,z,v[0],v[1],v[2],c[3]||0]);
}
function box(x0,y0,z0,x1,y1,z1,c){for(let x=x0;x<=x1;x++)for(let y=y0;y<=y1;y++)for(let z=z0;z<=z1;z++)put(x,y,z,c);}
function ell(cx,cy,cz,rx,ry,rz,c){for(let x=Math.ceil(cx-rx);x<=cx+rx;x++)for(let y=Math.ceil(cy-ry);y<=cy+ry;y++)for(let z=Math.ceil(cz-rz);z<=cz+rz;z++)if(((x-cx)/rx)**2+((y-cy)/ry)**2+((z-cz)/rz)**2<=1)put(x,y,z,c);}
function beam(a,b,r,c){let n=Math.ceil(Math.hypot(...a.map((v,i)=>v-b[i]))*1.5);for(let i=0;i<=n;i++){let p=a.map((v,k)=>v+(b[k]-v)*i/n);ell(...p,r,r,r,c);}}
function pipe(a,b,ro,ri,c){
  let axis=a.findIndex((v,i)=>v!==b[i]);if(axis<0)return;
  let u=(axis+1)%3,v=(axis+2)%3;
  for(let t=Math.min(a[axis],b[axis]);t<=Math.max(a[axis],b[axis]);t++)
    for(let j=-ro;j<=ro;j++)for(let k=-ro;k<=ro;k++)if(j*j+k*k<=ro*ro){
      let p=a.slice();p[axis]=t;p[u]+=j;p[v]+=k;put(...p,ri>0&&j*j+k*k<ri*ri?null:c);
    }
}
function bolts(x0,y,z,x1,step=8){for(let x=x0;x<=x1;x+=step)box(x,y,z,x+1,y+1,z+1,C.bolt);}
function stripes(x0,y,z,x1,height){for(let x=x0;x<=x1;x++)for(let h=0;h<height;h++)put(x,y,z+h,((x+h)%12<6)?C.yellow:C.black);}
function save(name,size,description,listed=true){
  let rows=Array.from(cells.values()).sort((a,b)=>a[2]-b[2]||a[1]-b[1]||a[0]-b[0]);
  let volume=new Volume();for(let v of rows)volume.setAt(v.slice(0,3),[v[3],v[4],v[5],255]);
  volume.save(`vox/${name}.vox`);
  let f=std.open(`${name}.vpt.json`,'w');f.puts(JSON.stringify({version:1,voxel_size:size,up:'z',voxels:rows}));f.close();
  let lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity];
  for(let v of rows)for(let i=0;i<3;i++){lo[i]=Math.min(lo[i],v[i]);hi[i]=Math.max(hi[i],v[i]);}
  if(listed)catalog.push({name,voxel_size:size,dimensions:hi.map((v,i)=>v-lo[i]+1),voxels:rows.length,description});
  console.log(`Created ${name}: ${rows.length} voxels`);
  return {lo,hi,size};
}
// Engine-space position (metres) of a source point, as the VPT importer places a Z-up asset with these
// bounds: x centred, source z -> up (grounded), source -y -> +z (centred).
function engine(p,b){let s=b.size;return [(p[0]-b.lo[0]+.5)*s-(b.hi[0]-b.lo[0]+1)*s/2,(p[2]-b.lo[2]+.5)*s,(b.hi[1]-p[1]+.5)*s-(b.hi[1]-b.lo[1]+1)*s/2].map(v=>Math.round(v*10000)/10000);}
// Player robot (maintenance-hexapod + parts-hexapod/ + rig/anim): see build-hexapod.js (node).
// Crystal-organic hostile silhouettes.
start();
ell(0,0,11,9,15,7,C.alien);ell(0,-12,9,8,7,5,C.violet);
for(let s of [-1,1])for(let j=0;j<3;j++){let y=-10+j*10;beam([s*6,y,10],[s*17,y-5,8],1.8,C.violet);beam([s*17,y-5,8],[s*21,y-10,0],1,C.bone);}
for(let j=0;j<5;j++){let y=-8+j*5;beam([0,y,14],[j%2?4:-3,y+2,24+(j%3)*3],2.1,C.crystal);}
for(let s of [-1,1]){box(s*4-1,-18,10,s*4+1,-17,11,C.mint);beam([s*4,-15,7],[s*6,-23,4],1,C.bone);}
save('alien-crawler',0.025,'Low six-legged crystal crawler, pale mandibles and mint sensory eyes.');
start();
ell(0,0,9,10,13,6,C.alien);ell(0,2,13,7,9,5,C.violet);
for(let s of [-1,1])for(let j=0;j<2;j++){let y=-7+j*15;beam([s*7,y,9],[s*15,y+4,5],1.8,C.violet);beam([s*15,y+4,5],[s*11,y+9,1],1,C.bone);}
for(let x=-4;x<=4;x+=4)beam([x,2,15],[x,5,23-Math.abs(x)],1.5,C.mint);
for(let s of [-1,1]){beam([s*5,-9,9],[s*7,-18,4],1.5,C.alien);beam([s*7,-18,4],[s*3,-21,1],1,C.mint);}
ell(0,-10,9,4,4,3,C.blue);
save('alien-leecher',0.025,'Compact four-hook parasite with twin siphons and charged dorsal crystals.');
// Horizontal 5.5m fuel tank; circular ends, saddles, service hatch and ladder.
start();
for(let x of [-34,34]){box(x-5,-21,0,x+5,21,3,C.dark);box(x-3,-16,4,x+3,16,13,C.steel);}
pipe([-43,0,29],[43,0,29],21,0,C.steel);
ell(-43,0,29,9,21,21,C.steel);ell(43,0,29,9,21,21,C.steel);
for(let x of [-36,36])pipe([x-1,0,29],[x+1,0,29],22,0,C.edge);
// repaint bands to keep one closed tank, with visible fasteners
for(let x of [-36,36])for(let a=0;a<Math.PI*2;a+=Math.PI/6)ell(x,Math.cos(a)*22,29+Math.sin(a)*22,1.3,1.3,1.3,C.bolt);
box(-18,-22,22,18,-21,35,C.dark);stripes(-17,-23,23,17,4);box(-10,-23,29,8,-23,32,C.yellow);
pipe([0,0,49],[0,0,54],6,0,C.dark);pipe([0,0,54],[0,0,56],8,0,C.edge);
pipe([47,-6,15],[56,-6,15],4,0,C.rust);pipe([56,-6,8],[56,-6,15],4,2,C.rust);
for(let x of [27,37])beam([x,-23,4],[x,-23,47],0.7,C.edge);
for(let z=6;z<48;z+=5)beam([27,-24,z],[37,-24,z],0.7,C.edge);
save('diesel-tank',0.05,'5.5m horizontal diesel reservoir, banded shell, saddles, fill hatch, ladder and drain.');
function flangeY(y){pipe([0,y-1,12],[0,y+1,12],10,5,C.edge);for(let a=0;a<Math.PI*2;a+=Math.PI/4)ell(Math.cos(a)*8,y-2,12+Math.sin(a)*8,1,1,1,C.bolt);}
start();pipe([0,-39,12],[0,40,12],7,5,C.rust);flangeY(-38);flangeY(39);
for(let y of [-22,22]){box(-10,y-2,0,10,y+2,2,C.dark);box(-3,y-1,3,3,y+1,6,C.steel);}
save('pipe-straight',0.05,'4m straight open-bore rusty pipe with bolt flanges and supports.');
start();pipe([0,-39,12],[0,0,12],7,5,C.rust);pipe([0,0,12],[39,0,12],7,5,C.rust);flangeY(-38);pipe([37,0,12],[39,0,12],10,5,C.edge);
// Recut connected internal bores after union.
beam([0,-40,12],[0,0,12],5,null);beam([0,0,12],[40,0,12],5,null);
save('pipe-elbow',0.05,'90-degree open-bore pipe corner; mates to the straight run.');
start();pipe([0,-39,12],[0,40,12],7,0,C.rust);pipe([0,0,12],[39,0,12],7,0,C.rust);flangeY(-38);flangeY(39);pipe([37,0,12],[39,0,12],10,0,C.edge);
beam([0,-41,12],[0,42,12],5,null);beam([0,0,12],[41,0,12],5,null);
save('pipe-tee',0.05,'Three-way pipe junction with continuous hollow bore.');
// 4m modules. Front-facing wall at -Y; base at Z=0.
start();box(-40,-4,0,39,3,63,C.steel);
for(let x=-40;x<40;x+=20){box(x,-6,0,x+2,-5,63,C.dark);box(x+4,-5,10,x+17,-5,52,C.edge);}
box(-40,-7,0,39,-5,5,C.dark);box(-40,-7,58,39,-5,63,C.dark);
for(let x=-36;x<40;x+=10){box(x,-7,3,x+1,-7,4,C.bolt);box(x,-7,60,x+1,-7,61,C.bolt);}
box(-30,-6,44,-14,-6,47,C.yellow);box(17,-6,12,30,-6,28,C.dark);for(let z=14;z<28;z+=3)box(19,-7,z,28,-7,z,C.black);
save('wall-panel',0.05,'4m x 3.2m ribbed steel wall, kickplate, vents and painted ID patch.');
start();
for(let x of [-40,32]){box(x,-6,0,x+7,5,63,C.dark);box(x+2,-7,4,x+5,-7,56,C.edge);}
box(-40,-6,57,39,5,63,C.steel);box(-31,-2,0,31,2,56,C.steel);
for(let s of [-1,1]){let x=s===-1?-29:2;box(x,-3,3,x+26,-3,53,C.edge);box(x+3,-4,8,x+23,-4,45,C.steel);}
box(-1,-4,0,1,-3,56,C.black);stripes(-29,-5,5,29,5);
// Viewing windows cut through the leaves: dark frame, 2-voxel glass pane in the middle.
for(let x0 of [-22,9]){box(x0,-5,34,x0+13,5,48,C.dark);box(x0+2,-6,36,x0+11,6,46,null);box(x0+2,-1,36,x0+11,0,46,C.glass);}
box(33,-9,23,39,-7,35,C.black);box(35,-10,30,37,-10,33,C.red);box(35,-10,25,37,-10,27,C.bolt);
save('bulkhead-door',0.05,'Closed split blast door, warning stripes, glass viewing windows and red access reader; 4m module.');
// Wall module with a long viewing band: same panel, window cut through with glass and mullions.
start();box(-40,-4,0,39,3,63,C.steel);
for(let x=-40;x<40;x+=20){box(x,-6,0,x+2,-5,63,C.dark);box(x+4,-5,10,x+17,-5,52,C.edge);}
box(-40,-7,0,39,-5,5,C.dark);box(-40,-7,58,39,-5,63,C.dark);
for(let x=-36;x<40;x+=10){box(x,-7,3,x+1,-7,4,C.bolt);box(x,-7,60,x+1,-7,61,C.bolt);}
box(-36,-7,22,35,4,50,C.dark);box(-34,-8,24,33,5,48,null);box(-34,-1,24,33,0,48,C.glass);
for(let x of [-17,0,16])box(x,-3,24,x+1,2,48,C.dark);
box(-36,-8,20,35,-8,21,C.yellow);
save('wall-window',0.05,'4m x 3.2m wall module with a glazed viewing band and mullions.');
// Open doorway module: wall with a 2.4m x 2.4m passage, dark frame and hazard edges.
start();box(-40,-4,0,39,3,63,C.steel);
for(let x of [-40,20]){box(x,-6,0,x+2,-5,63,C.dark);box(x+4,-5,10,x+17,-5,52,C.edge);}
box(-40,-7,0,39,-5,5,C.dark);box(-40,-7,58,39,-5,63,C.dark);
box(-16,-7,0,15,4,51,C.dark);box(-12,-8,0,11,5,47,null);
for(let z=0;z<48;z++)for(let x of [-14,-13,12,13])put(x,-8,z,(Math.floor(z/4)%2)?C.yellow:C.black);
for(let x=-12;x<12;x++)put(x,-8,49,(Math.floor(x/4)%2)?C.yellow:C.black);
box(-8,-6,1,7,3,1,C.dark);box(18,-8,34,22,-7,40,C.black);box(19,-9,38,21,-9,39,C.green);
save('doorway',0.05,'Open doorway module: 4m wall with a 2.4m passage, framed and hazard-marked.');
// Corner post: covers the joint where two wall modules meet at a room corner.
start();box(-7,-7,0,6,6,65,C.dark);box(-8,-8,0,7,7,3,C.steel);box(-8,-8,62,7,7,65,C.steel);
box(-8,-8,30,7,7,33,C.yellow);for(let z=8;z<60;z+=12){box(-8,-8,z,-7,-7,z+1,C.bolt);box(6,6,z,7,7,z+1,C.bolt);}
save('corner-post',0.05,'Corner post for room corners: 0.8m square steel column with a yellow band.');
// Standing work floodlight: warm bulb in a reflector cavity behind a glass lens, wire cage.
start();
for(let a of [0,2.1,4.2]){let dx=Math.round(Math.cos(a)*10),dy=Math.round(Math.sin(a)*10);beam([0,0,4],[dx,dy,0],1,C.dark);}
pipe([0,0,2],[0,0,40],2,0,C.dark);box(-3,-3,8,2,2,10,C.yellow);
box(-8,-5,40,7,5,53,C.steel);box(-6,-5,42,5,-1,51,null);box(-3,0,44,2,1,49,C.lamp);
box(-6,-6,42,5,-6,51,C.glass);
for(let x=-6;x<=5;x+=3)box(x,-8,41,x,-7,52,C.dark);box(-7,-8,41,6,-7,41,C.dark);box(-7,-8,52,6,-7,52,C.dark);
box(-8,-5,54,7,5,55,C.yellow);box(-2,3,54,1,6,57,C.dark);
save('work-lamp',0.05,'2.8m standing work floodlight: warm bulb behind a glass lens, wire cage, tripod.');
// Wall-mount emergency beacon: red core under a glass dome on a steel bracket.
start();box(-4,-4,0,3,3,2,C.dark);box(-2,-2,3,1,1,4,C.steel);
ell(0,0,8,4.5,4.5,4.5,C.glass);ell(0,0,8,2.2,2.2,2.6,C.red);box(-4,-4,0,3,3,4,C.dark);
save('beacon',0.05,'Emergency beacon: red emitter under a glass dome on a short bracket.');
start();box(-40,-40,0,39,39,3,C.dark);
for(let x=-39;x<40;x+=10)for(let y=-39;y<40;y+=10){box(x,y,4,x+8,y+8,4,C.steel);for(let a=1;a<8;a+=3)box(x+a,y+2,5,x+a,y+6,5,C.edge);}
for(let x of [-39,36]){box(x,-40,4,x+2,39,5,C.yellow);for(let y=-35;y<40;y+=10)box(x,y,6,x+2,y+2,6,C.dark);}
save('corridor-floor',0.05,'4m square deck tile, raised tread plates and yellow edge markings.');
start();
box(-18,-11,0,18,11,3,C.dark);box(-16,-9,4,16,9,24,C.steel);box(-18,-12,25,18,10,28,C.dark);
box(-16,6,29,16,10,47,C.steel);box(-14,4,32,14,5,45,C.black);box(-12,3,34,4,3,43,C.blue);
for(let z=35;z<=41;z+=3)box(-10,2,z,1,2,z,C.ice);
for(let x of [8,12]){box(x,3,40,x+1,3,41,C.green);box(x,3,35,x+1,3,36,C.red);}
for(let x=-13;x<=5;x+=4)for(let y=-8;y<=0;y+=4)box(x,y,29,x+2,y+2,29,C.bolt);
box(10,-7,29,14,-3,30,C.yellow);ell(12,-5,32,1.5,1.5,2,C.red);
for(let x of [-12,12]){box(x-2,-10,9,x+2,-10,20,C.dark);for(let z=10;z<20;z+=3)box(x-1,-11,z,x+1,-11,z,C.black);}
save('control-console',0.05,'Freestanding terminal with blue display, keyboard, status lights and emergency stop.');
start();
box(-30,-17,0,29,17,4,C.dark);box(-26,-14,5,25,14,30,C.steel);
box(-28,-15,8,-18,15,27,C.yellow);box(18,-15,8,27,15,27,C.yellow);
for(let x=-14;x<=12;x+=4)box(x,-16,9,x+1,-15,25,C.black);
box(-14,-15,28,13,14,32,C.dark);for(let x=-12;x<14;x+=5)box(x,-13,33,x+2,12,34,C.edge);
pipe([18,7,30],[18,7,48],3,1,C.rust);pipe([18,7,46],[27,7,46],3,1,C.rust);
box(-24,-17,17,-20,-17,23,C.blue);box(20,-17,21,23,-17,23,C.red);
stripes(-25,-18,5,25,3);for(let x of [-24,23])for(let y of [-12,12])box(x,y,31,x+1,y+1,32,C.bolt);
save('diesel-generator',0.05,'3m skid generator, cooling grille, yellow end guards, exhaust and service lights.');
start();box(-14,-12,0,14,12,25,C.steel);
for(let x of [-14,11])for(let y of [-12,9])box(x,y,0,x+3,y+3,27,C.dark);
box(-15,-13,22,15,13,26,C.yellow);box(-11,-14,7,11,-13,18,C.dark);box(-5,-15,10,5,-15,14,C.yellow);
for(let x of [-8,7])box(x,-14,23,x+1,-14,25,C.bolt);
box(-8,-5,27,8,5,27,C.edge);box(-5,-2,28,5,2,28,C.black);
save('service-crate',0.05,'Reinforced maintenance supply crate, yellow lid, recessed handle and latches.');
// Facility-scale kit: 25cm structural voxels, NOT scaled-up player-sized props.
// Hollow shells, human-scale access doors, ladders, catwalks and service lights
// give these machines their size cues. Max dimension remains <=128 voxels.
function ladder(x,y,z0,z1){
  for(let dx of [-2,2])beam([x+dx,y,z0],[x+dx,y,z1],0.6,C.edge);
  for(let z=z0;z<=z1;z+=2)box(x-2,y-1,z,x+2,y-1,z,C.bolt);
}
function ring(z,r,inner,c){pipe([0,0,z],[0,0,z+1],r,inner,c);}
function guardRing(z,r){
  ring(z+4,r,r-1,C.yellow);
  for(let a=0;a<Math.PI*2;a+=Math.PI/12)beam([Math.round(Math.cos(a)*r),Math.round(Math.sin(a)*r),z],[Math.round(Math.cos(a)*r),Math.round(Math.sin(a)*r),z+4],0.55,C.edge);
}
function serviceDoor(x,y,z){
  box(x-2,y,z,x+2,y,z+8,C.dark);box(x-1,y-1,z+1,x+1,y-1,z+7,C.steel);
  put(x+1,y-2,z+4,C.bolt);box(x-1,y-2,z+6,x+1,y-2,z+6,C.yellow);
  box(x-2,y-2,z+9,x+2,y-2,z+9,C.white);
}
start();
ring(0,32,0,C.dark);ring(2,30,0,C.steel);
pipe([0,0,4],[0,0,98],24,21,C.steel);
ell(0,0,98,24,24,9,C.steel);ell(0,0,98,21,21,6,null);
for(let z of [12,35,72,96])ring(z,26,22,C.edge);
for(let a=0;a<Math.PI*2;a+=Math.PI/4){let x=Math.round(Math.cos(a)*25),y=Math.round(Math.sin(a)*25);beam([x,y,6],[x,y,96],1.3,C.dark);}
ring(52,32,23,C.dark);guardRing(53,32);
for(let x of [-32,32]){pipe([x,0,6],[x,0,89],3,1,C.rust);pipe([x,0,86],[x>0?22:-22,0,86],3,1,C.rust);}
ladder(0,-27,3,102);serviceDoor(10,-23,5);
box(-12,-25,65,12,-25,70,C.dark);stripes(-11,-26,66,11,3);
for(let x of [-10,10])box(x,-24,76,x+1,-24,90,C.blue);
pipe([0,0,106],[0,0,116],5,3,C.dark);ring(106,9,4,C.edge);
box(-2,-2,117,2,2,118,C.red);
save('mega-reactor-tower',0.25,'29.75m reactor tower: hollow pressure vessel, service balcony, external cooling risers, ladder and tiny access door.');
start();
box(-60,-25,0,59,24,3,C.dark);
for(let x of [-48,-16,16,48])box(x-4,-18,4,x+4,18,12,C.steel);
pipe([-57,0,27],[56,0,27],20,17,C.steel);
for(let x of [-57,56])pipe([x,0,27],[x+1,0,27],20,0,C.dark);
for(let x=-48;x<=48;x+=16){pipe([x,0,27],[x+1,0,27],22,17,C.edge);for(let a=0;a<Math.PI*2;a+=Math.PI/6)ell(x-1,Math.round(Math.cos(a)*21),27+Math.round(Math.sin(a)*21),1,1,1,C.bolt);}
box(-54,-24,7,53,-21,11,C.dark);stripes(-52,-25,8,52,3);
for(let x of [-42,-10,22]){serviceDoor(x,-21,15);box(x-4,-21,31,x+4,-21,34,C.dark);box(x-3,-22,32,x+3,-22,33,C.blue);}
box(30,4,39,47,18,66,C.dark);box(32,6,40,45,16,67,C.steel);
for(let z=45;z<66;z+=4)box(31,3,z,46,3,z,C.black);
box(28,2,67,49,20,69,C.edge);box(32,6,68,45,16,70,null);
for(let x of [-52,52])ladder(x,-23,4,40);
box(-54,-5,48,53,5,49,C.dark);
for(let y of [-6,6]){beam([-54,y,53],[53,y,53],0.6,C.yellow);for(let x=-54;x<=53;x+=8)beam([x,y,49],[x,y,53],0.5,C.edge);}
save('mega-turbine',0.25,'30m turbine assembly with ribbed barrel, inspection doors, rooftop service walk and exhaust stack.');
start();
for(let x of [-60,42]){box(x,-8,0,x+17,8,93,C.dark);box(x+2,-10,4,x+15,-9,78,C.steel);box(x+5,-11,16,x+12,-11,74,C.edge);}
box(-60,-8,80,59,8,98,C.dark);box(-57,-10,84,56,-9,95,C.steel);
// Fully open 20m-wide, 20m-tall aperture; shutter is stacked overhead.
for(let z=80;z<=88;z+=2)box(-41,-4,z,41,4,z,C.edge);
for(let x of [-40,39]){box(x,-8,0,x+1,4,79,C.edge);for(let z=4;z<78;z+=8)box(x,-9,z,x+1,-9,z+3,C.yellow);}
for(let x of [-49,49]){pipe([x,-13,20],[x,-13,76],3,0,C.dark);pipe([x,-13,32],[x,-13,75],1,0,C.bolt);}
serviceDoor(-52,-11,2);box(48,-12,4,52,-11,11,C.dark);box(49,-13,8,51,-13,9,C.red);
box(-56,-13,82,55,-11,83,C.dark);
beam([-56,-13,87],[55,-13,87],0.6,C.yellow);for(let x=-56;x<=55;x+=8)beam([x,-13,83],[x,-13,87],0.5,C.edge);
for(let x=-35;x<=35;x+=10)box(x,-11,91,x+5,-11,93,C.blue);
for(let x of [-56,55])box(x,-5,99,x+1,-4,100,C.red);
save('mega-blast-gate',0.25,'30m wide, 25.25m tall OPEN industrial gate; 20m clear aperture, hydraulic rams, upper walkway and human-scale service door.');
start();
ring(0,39,0,C.dark);ring(2,38,33,C.steel);
for(let z=12;z<=112;z++){
  let r=Math.round(22+14*((z-70)/58)**2);
  for(let x=-r;x<=r;x++)for(let y=-r;y<=r;y++)if(x*x+y*y<=r*r&&x*x+y*y>=(r-2)*(r-2))put(x,y,z,C.steel);
}
for(let a=0;a<Math.PI*2;a+=Math.PI/10){let x=Math.round(Math.cos(a)*34),y=Math.round(Math.sin(a)*34);beam([x,y,3],[x,y,14],1.3,C.dark);
  let prev=null;for(let z=12;z<=112;z+=4){let r=Math.round(22+14*((z-70)/58)**2)+1,p=[Math.round(Math.cos(a)*r),Math.round(Math.sin(a)*r),z];if(prev)beam(prev,p,0.65,C.edge);prev=p;}}
// Open rim, dark throat, and large intake gaps between supporting piers.
ring(111,31,27,C.edge);ring(113,32,27,C.dark);guardRing(114,32);
ladder(0,-38,3,111);box(-3,-39,110,3,-29,112,C.dark);
for(let z of [20,50,80]){let r=Math.round(22+14*((z-70)/58)**2);box(-3,-38,z,3,-r,z+1,C.dark);}
for(let x of [-20,20])box(x,-24,116,x+1,-23,117,C.red);
save('mega-cooling-tower',0.25,'30m hyperboloid cooling tower with open throat, intake piers, external ribs, ladder and rim railing.');
start();
for(let x of [-54,51])for(let y of [-17,14]){box(x-2,y-2,0,x+3,y+3,3,C.dark);box(x,y,4,x+1,y+1,52,C.steel);}
box(-60,-20,49,59,19,51,C.dark);
for(let y of [-10,9]){pipe([-60,y,58],[59,y,58],5,3,C.rust);for(let x=-50;x<=50;x+=25)pipe([x,y,58],[x+1,y,58],6,3,C.edge);}
for(let y of [-20,19]){beam([-59,y,52],[58,y,52],0.8,C.edge);beam([-59,y,67],[58,y,67],0.8,C.edge);
 for(let x=-59;x<58;x+=13){beam([x,y,52],[Math.min(x+13,58),y,67],0.8,C.steel);beam([x,y,67],[Math.min(x+13,58),y,52],0.8,C.steel);}}
for(let x of [-54,51])beam([x,-17,10],[x,15,46],1,C.dark);
ladder(54,-21,3,50);box(49,-23,49,58,-19,50,C.yellow);
save('mega-pipe-bridge',0.25,'30m pipe bridge, 12m clear ground clearance, twin 2.5m process pipes, cross-braced trusses and service ladder.');
start();
ring(0,39,0,C.dark);ring(2,37,0,C.steel);
pipe([0,0,4],[0,0,105],32,29,C.steel);
for(let z of [8,30,55,80,102])ring(z,33,29,C.edge);
ell(0,0,105,32,32,12,C.steel);ell(0,0,105,29,29,9,null);
ring(90,38,31,C.dark);guardRing(91,38);
ladder(0,-34,3,114);box(-4,-38,90,4,-31,91,C.edge);
serviceDoor(10,-31,5);box(-16,-33,49,16,-33,62,C.dark);stripes(-15,-34,50,15,4);
// Enormous painted tank ID "01", not a giant screen.
box(-11,-34,56,-5,-34,60,C.yellow);box(-9,-35,57,-7,-35,59,C.dark);box(4,-34,56,5,-34,60,C.yellow);
pipe([25,-25,5],[25,-25,85],3,1,C.rust);
pipe([0,0,117],[0,0,122],5,2,C.dark);box(-1,-1,123,1,1,124,C.red);
save('mega-storage-silo',0.25,'31.25m storage silo with domed roof, circumferential stiffeners, service balcony, ladder, fill riser and painted tank ID.');
start();
box(-48,-48,0,47,47,2,C.dark);
for(let x=-47;x<47;x+=12)for(let y=-47;y<47;y+=12){box(x,y,3,x+10,y+10,3,C.steel);put(x+1,y+1,3,C.bolt);put(x+9,y+9,3,C.bolt);}
for(let x of [-47,46])for(let y=-46;y<47;y++)put(x,y,3,(Math.floor(y/4)%2)?C.yellow:C.black);
for(let y of [-47,46])for(let x=-46;x<47;x++)put(x,y,3,(Math.floor(x/4)%2)?C.yellow:C.black);
save('mega-foundation',0.25,'24m square heavy foundation deck; broad steel plates, expansion joints, anchor bolts and hazard-marked edges. Top surface is 1m high.');
// Preserve the separately generated planet/corridor expansion when rebuilding kit 01.
let extra=std.open('scenery-catalog.json','r');
if(extra){let rows=JSON.parse(extra.readAsString());extra.close();for(let e of rows)if(!catalog.some(a=>a.name===e.name))catalog.push(e);}
let f=std.open('catalog.json','w');f.puts(JSON.stringify(catalog,null,2)+'\n');f.close();
