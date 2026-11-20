#!/usr/bin/env python3
"""Compose planet scenery, a quiet corridor bay, and per-asset capture scenes.
Asset files and existing scenes are preserved. Engine paths are repository-relative.
"""
import json, math, random
from pathlib import Path
ROOT=Path(__file__).resolve().parent
BASE='assets/library/BLACK_START/'
LIGHT=dict(azimuth=215,elevation=34,sun_power=2.5,sky_power=.65,warmth=.25,
           sun_radius=1.2,exposure=1,quality=1,bounces=3,night=0)
def scene():return dict(version=1,size=128,library=BASE.rstrip('/'),lighting=LIGHT.copy(),chunks=[],instances=[])
def add(s,name,x,z,y=0,r=0,scale=1):
    s['instances'].append(dict(asset=BASE+name+'.vpt.json',x=x,y=y,z=z,rotation=r,scale=scale,wind=0))
def ground(s,half):
    chunks={}
    for x in range(-half,half):
        for z in range(-half,half):
            # Macro-scale dust drift tint, NOT per-voxel random noise.
            d=round(2*math.sin(x*.065+z*.035))
            for y in [-2,-1]:
                r,g,b=(58+d,55+d,50+d) if y==-1 else (44,42,39)
                value=r|(g<<8)|(b<<16)|(255<<24)
                gx,gy,gz=x+64,y+16,z+64
                key=(gx//16,gy//16,gz//16)
                data=chunks.setdefault(key,[0]*4096)
                data[((gy%16)*16+gz%16)*16+gx%16]=value
    s['chunks']=[dict(x=k[0],y=k[1],z=k[2],voxels=v) for k,v in sorted(chunks.items())]
def save(s,name):
    path=ROOT/name;path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(s,separators=(',',':'))+'\n')
    print(f'{name}: {len(s["instances"])} instances, {len(s["chunks"])} chunks')
s=scene();ground(s,48)
for n,x,z,r in [('rock-natural-arch',-13,-19,.15),('rock-spire-cluster',22,-25,-.3),
              ('rock-layered-outcrop',-29,4,.4),('rock-boulder-low',8,4,0),
              ('rock-boulder-split',-12,13,.7),('rock-boulder-upright',27,10,-.4),
              ('rock-scree-patch',2,15,.2),('dead-tree-crooked',-5,4,.3),
              ('dead-tree-forked',15,-1,-.6),('dead-tree-fallen',-21,22,1.3),
              ('dead-stump-hollow',-7,19,.2),('dead-scrub-spreading',4,24,.4),
              ('dead-scrub-upright',17,20,-.2),('dead-agave',10,13,.7)]:add(s,n,x,z,r=r)
rng=random.Random(921)
small=['dead-scrub-spreading','dead-scrub-upright','dead-agave','rock-scree-patch']
for i in range(26):
    x,z=rng.uniform(-36,36),rng.uniform(-6,34)
    add(s,small[i%len(small)],x,z,r=rng.random()*math.tau,scale=rng.uniform(.7,1.2))
add(s,'maintenance-hexapod',0,8,r=2.9)
# A distant facility silhouette gives the wasteland a destination.
add(s,'mega-cooling-tower',-31,-34)
save(s,'planet.vptscene.json')
s=scene();s['lighting'].update(azimuth=225,elevation=46,sky_power=.8)
# Open-sided maintenance bay lets the new flat panels and large deck plates read clearly.
for x in [-4,0,4]:
    for z in [-2,2]:add(s,'corridor-clean-floor',x,z)
for x in [-4,0,4]:add(s,'corridor-clean-window' if x==-4 else 'corridor-clean-doorway',x,-4.2,y=.3)
for z in [-2,2]:add(s,'corridor-clean-wall',-6.2,z,y=.3,r=math.pi/2)
for x in [0,4]:
    for z in [-6,-10]:add(s,'corridor-clean-straight',x,z)
add(s,'corridor-clean-corner',0,-14)
add(s,'corridor-clean-junction',4,-14)
add(s,'corridor-clean-ceiling',0,-10,y=3.5)
add(s,'maintenance-hexapod',.6,1,y=.3,r=2.6)
add(s,'control-console',-4.7,-2,y=.3,r=math.pi/2)
add(s,'service-crate',-4,2.3,y=.3)
add(s,'work-lamp',3,-2,y=.3)
save(s,'clean-corridors.vptscene.json')
for a in json.loads((ROOT/'scenery-catalog.json').read_text()):
    s=scene();n=a['name'];dims=[d*a['voxel_size'] for d in a['dimensions']]
    if n.startswith('corridor-clean-'):
        add(s,n,0,0,y=3.5 if n.endswith('ceiling') else 0)
        if n.endswith('ceiling'):add(s,'corridor-clean-floor',0,0)
        if n.endswith(('wall','window','doorway')):
            add(s,'corridor-clean-floor',0,1.8)
            # Lift standalone wall off the floor; preserve source geometry.
            s['instances'][0]['y']=.3
        add(s,'maintenance-hexapod',.6,1 if n.endswith(('wall','window','doorway')) else 0,y=.3)
    else:
        half=math.ceil(max(dims[0],dims[1])/2+3)
        ground(s,half)
        add(s,n,0,0)
        add(s,'maintenance-hexapod',dims[0]/2+1,1)
    save(s,Path('expansion-scenes')/(n+'.vptscene.json'))
