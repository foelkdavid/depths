#!/usr/bin/env python3
"""Validate the kit and draw reproducible, unlit isometric reference sheets.
These are software previews, not screenshots of the engine's path tracer.
"""
import json, math, struct
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'previews'
OUT.mkdir(exist_ok=True)
FONT = '/usr/share/fonts/noto/NotoSans-Regular.ttf'
def font(n):
    try: return ImageFont.truetype(FONT, n)
    except OSError: return ImageFont.load_default()
def project(p):
    x,y,z = p
    return ((x+y)*0.8660254, (x-y)*0.5-z)
def render(name):
    data=json.loads((ROOT/f'{name}.vpt.json').read_text())
    rows=data['voxels']; cells={tuple(v[:3]):v[3:] for v in rows}
    assert len(cells)==len(rows), name
    dims=[max(p[i] for p in cells)-min(p[i] for p in cells)+1 for i in range(3)]
    assert max(dims)<=128 and math.prod(dims)<=2097152, (name,dims)
    assert all(len(v)==7 and all(0<=c<=255 for c in v[3:6]) and v[6] in (0,1) for v in rows)
    # Ensure native Goxel output contains exactly the same voxel count.
    vox=(ROOT/'vox'/f'{name}.vox').read_bytes()
    assert vox[:4]==b'VOX '
    offset=20; count=None
    while offset+12<=len(vox):
        kind, size, children=struct.unpack_from('<4sII',vox,offset)
        if kind==b'XYZI': count=struct.unpack_from('<I',vox,offset+12)[0]
        offset+=12+size
    assert count==len(rows),(name,count,len(rows))
    faces=[]
    for (x,y,z),c in cells.items():
        for normal,points,shade in [
            ((1,0,0),[(x+1,y,z),(x+1,y+1,z),(x+1,y+1,z+1),(x+1,y,z+1)],.72),
            ((0,-1,0),[(x,y,z),(x+1,y,z),(x+1,y,z+1),(x,y,z+1)],.88),
            ((0,0,1),[(x,y,z+1),(x+1,y,z+1),(x+1,y+1,z+1),(x,y+1,z+1)],1.12),
        ]:
            if (x+normal[0],y+normal[1],z+normal[2]) in cells: continue
            rgb=tuple(min(255,int(v*(1 if c[3] else shade))) for v in c[:3])
            faces.append((sum(p[0]-p[1]+p[2] for p in points)/4,[project(p) for p in points],rgb))
    pts=[p for _,poly,_ in faces for p in poly]
    lo=[min(p[i] for p in pts) for i in range(2)]; hi=[max(p[i] for p in pts) for i in range(2)]
    scale=min(430/(hi[0]-lo[0]),320/(hi[1]-lo[1]))
    canvas=Image.new('RGB',(1024,880),(19,26,33)); draw=ImageDraw.Draw(canvas)
    ox=(512-(hi[0]-lo[0])*scale)/2; oy=(360-(hi[1]-lo[1])*scale)/2+15
    for _,poly,rgb in sorted(faces,key=lambda f:f[0]):
        draw.polygon([(round((p[0]-lo[0])*scale*2+ox*2),round((p[1]-lo[1])*scale*2+oy*2)) for p in poly],fill=rgb)
    draw.text((40,755),name.upper().replace('-',' '),font=font(28),fill=(233,181,70))
    draw.text((40,800),f'{data["voxel_size"]*100:g} cm / voxel  |  {dims[0]} x {dims[1]} x {dims[2]}  |  {len(rows):,} voxels',font=font(20),fill=(147,164,175))
    canvas=canvas.resize((512,440),Image.Resampling.LANCZOS)
    canvas.save(OUT/f'{name}.png')
    return canvas
catalog=json.loads((ROOT/'catalog.json').read_text())
sheet=Image.new('RGB',(2048,440*math.ceil(len(catalog)/4)+95),(13,19,26)); d=ImageDraw.Draw(sheet)
d.text((28,20),'BLACK START / COMPLETE ASSET LIBRARY',font=font(34),fill=(233,181,70))
d.text((30,65),'Goxel-authored voxel models / isometric reference views',font=font(16),fill=(147,164,175))
categories={
    'megastructures':('MEGASTRUCTURES',('mega-',)),
    'planet-scenery':('DESOLATE PLANET / ROCKS + DEAD PLANTS',('rock-','dead-')),
    'clean-corridors':('QUIET CORRIDOR KIT',('corridor-clean-',)),
}
category_sheets={}
for key,(title,prefixes) in categories.items():
    count=sum(e['name'].startswith(prefixes) for e in catalog)
    image=Image.new('RGB',(1536,440*math.ceil(count/3)+95),(13,19,26))
    ImageDraw.Draw(image).text((28,20),'BLACK START / '+title,font=font(30),fill=(233,181,70))
    ImageDraw.Draw(image).text((30,65),'Goxel-authored / individual views auto-fit; see catalog.json for physical dimensions',font=font(17),fill=(147,164,175))
    category_sheets[key]=[image,0]
for i,entry in enumerate(catalog):
    image=render(entry['name'])
    sheet.paste(image,((i%4)*512,(i//4)*440+95))
    for key,(_,prefixes) in categories.items():
        if entry['name'].startswith(prefixes):
            target,m=category_sheets[key]
            target.paste(image,((m%3)*512,(m//3)*440+95));category_sheets[key][1]+=1
for key,(image,_) in category_sheets.items():
    image.save(OUT/(key+'-contact-sheet.png'))
sheet.save(OUT/'contact-sheet.png')
print(f'Validated {len(catalog)} JSON + Goxel VOX pairs. Wrote previews/contact-sheet.png')
