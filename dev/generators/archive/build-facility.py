#!/usr/bin/env python3
"""Assemble the huge facility and true-scale comparisons; run from any cwd.
Paths in engine scene files are relative to the VPT Engine repository root.
"""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parent
BASE='assets/library/BLACK_START/'
LIGHT=dict(azimuth=225,elevation=36,sun_power=2,sky_power=.5,warmth=.3,
           sun_radius=1,exposure=1,quality=1,bounces=3,night=0)
def scene():
    return dict(version=1,size=128,library=BASE.rstrip('/'),lighting=LIGHT.copy(),chunks=[],instances=[])
def add(s,name,x,z,y=1,r=0):
    s['instances'].append(dict(asset=BASE+name+'.vpt.json',x=x,y=y,z=z,rotation=r,scale=1,wind=0))
def save(s,path):
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(s,indent=2)+'\n')
s=scene()
for x in [-36,-12,12,36]:
    for z in [-48,-24,0,24,48]:add(s,'mega-foundation',x,z,y=0)
for n,x,z in [('mega-reactor-tower',-25,-23),('mega-cooling-tower',29,-24),
              ('mega-cooling-tower',29,-48),('mega-storage-silo',-32,18),
              ('mega-storage-silo',-32,43),('mega-turbine',24,19),
              ('mega-pipe-bridge',0,-6),('mega-blast-gate',0,42)]:add(s,n,x,z)
add(s,'maintenance-hexapod',0,31)
for n,x,z in [('control-console',-3,33),('service-crate',5,32),('diesel-generator',-9,25),
              ('diesel-tank',-13,-13),('alien-leecher',-13,-10),('alien-crawler',6,0),
              ('control-console',-19,-12),('control-console',27,27)]:add(s,n,x,z)
save(s,ROOT/'facility.vptscene.json')
# Every comparison contains the ORIGINAL robot at scale 1, not a proxy/label.
catalog=json.loads((ROOT/'catalog.json').read_text())
for a in catalog:
    n=a['name']
    if not n.startswith('mega-'):continue
    s=scene()
    if n!='mega-foundation':
        for x in ([-12,12] if a['dimensions'][0]*a['voxel_size']>24 else [0]):
            add(s,'mega-foundation',x,2,y=0)
    add(s,n,0,0,y=0 if n=='mega-foundation' else 1)
    depth=a['dimensions'][1]*a['voxel_size']
    add(s,'maintenance-hexapod',0,depth/2+2 if n!='mega-foundation' else 0)
    # A small terminal beside the robot adds a familiar human-scale detail.
    add(s,'control-console',-2,depth/2+2 if n!='mega-foundation' else 2)
    save(s,ROOT/'scale-scenes'/f'{n}.vptscene.json')
print('Created facility.vptscene.json and 7 true-scale comparison scenes.')
