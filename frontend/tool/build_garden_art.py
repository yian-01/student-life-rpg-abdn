"""Regenerate the project-owned ginkgo, bamboo and floral mark only.

The user chose to retain reference cherry/bush/maple. Those existing bundle
entries are preserved verbatim; this tool does not recreate or replace them.
"""
from pathlib import Path
from PIL import Image, ImageDraw
from io import BytesIO
import base64
import json
import math
import random

ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'garden'
ROOT.mkdir(parents=True, exist_ok=True)

def png(im):
    out = BytesIO(); im.save(out, format='PNG', optimize=True)
    return base64.b64encode(out.getvalue()).decode()

PALETTES = {
    'cherry':['#a6607b','#c77c98','#da9ab0','#e6b0c0','#f0c8d2','#f9dfe3'],
    'maple':['#93492c','#ae6131','#ca803c','#dc9b50','#eabc79','#f6d9a4'],
    'bush':['#334b32','#47613c','#627f45','#819949','#a0b365','#c4d38b'],
    'ginkgo':['#777339','#989344','#b2ad55','#cbc66d','#dfd78d','#eee5b4'],
    'bamboo':['#29473f','#3d6050','#5b7d5c','#7c9b6e','#9fb78b','#c3ceb0'],
}

def plant(name, seed):
    rng=random.Random(seed);w,h=224,232
    images={n:Image.new('RGBA',(w,h)) for n in ['ground','wood','shade','leaves','light']}
    draw={n:ImageDraw.Draw(im) for n,im in images.items()};bones=[];clusters=[]
    ground=draw['ground']; wood=draw['wood']; palette=PALETTES[name]
    def branch(x,y,length,angle,width,depth,parent=-1):
        end=(x+math.cos(angle)*length,y+math.sin(angle)*length)
        mid=((x+end[0])/2+rng.uniform(-3,3),(y+end[1])/2)
        color='#6d5148' if name=='cherry' else '#69503b'
        wood.line([(round(x),round(y)),tuple(map(round,mid)),tuple(map(round,end))],fill=color,width=max(1,round(width)))
        if width>3:wood.line([(round(x-1),round(y)),(round(mid[0]-1),round(mid[1])),(round(end[0]-1),round(end[1]))],fill='#a47d5a',width=max(1,round(width*.25)))
        index=len(bones)//7;bones.extend([x,y,*end,parent,width,depth])
        if depth==0:
            clusters.append((*end,rng.uniform(14,25)));return
        spread=.4 if name=='cherry' else .5
        branch(*end,length*rng.uniform(.64,.78),angle-spread+rng.uniform(-.2,.1),width*.66,depth-1,index)
        branch(*end,length*rng.uniform(.6,.76),angle+spread+rng.uniform(-.1,.2),width*.64,depth-1,index)
        if depth==1:clusters.append((*end,rng.uniform(15,23)))
    if name=='bamboo':
        for i in range(5):
            x=72+i*19;tip=22+rng.randrange(25);tilt=rng.randint(-16,16)
            wood.line([(x,211),(x+tilt,tip)],fill=palette[2],width=4)
            wood.line([(x-1,211),(x+tilt-1,tip)],fill=palette[4],width=1)
            bones.extend([x,211,x+tilt,tip,-1,3,i])
            for y in range(tip+15,197,25):
                bx=x+tilt*(211-y)/(211-tip);wood.line([(bx-2,y),(bx+2,y)],fill=palette[4],width=1)
                for side in [-1,1]:
                    ex=bx+side*rng.randint(19,37);ey=y-rng.randint(9,18)
                    wood.line([(bx,y),(ex,ey)],fill=palette[1],width=1);bones.extend([bx,y,ex,ey,-1,1,i])
                    for j in range(8):
                        t=rng.random();lx=bx+(ex-bx)*t;ly=y+(ey-y)*t;length=rng.randint(9,17)
                        target='light' if side<0 and j%3==0 else 'leaves'
                        draw[target].polygon([(lx,ly),(lx+side*length,ly-rng.randint(5,10)),(lx+side*length*.55,ly+2)],fill=rng.choice(palette[1:]))
    else:
        if name=='bush':
            for i in range(6):branch(112,207,rng.uniform(27,38),-math.pi/2+rng.uniform(-1.1,1.1),5,2)
        else:
            branch(112,211,53,-math.pi/2-.1,10,4)
            # An independently generated lower bough makes the silhouette asymmetric.
            branch(109,160,35,-.55,4,2)
        for cx,cy,r in sorted(clusters,key=lambda c:c[1]):
            for j in range(260):
                a=rng.random()*math.tau;radius=r*math.sqrt(rng.random())
                x=round(cx+math.cos(a)*radius);y=round(cy+math.sin(a)*radius*.72)
                if not 3<x<w-4 or not 3<y<211:continue
                tone=max(0,min(5,round(2.6-(y-cy)/r*2.2-(x-cx)/r*.65+rng.uniform(-1.5,1.5))))
                layer='shade' if tone<2 else 'light' if tone>3 else 'leaves'
                draw[layer].rectangle((x,y,x+rng.randint(1,3),y+rng.randint(1,2)),fill=palette[tone])
    for i in range(280):
        x=int(rng.gauss(112,28));y=rng.randint(210,219)
        if 29<x<195:ground.rectangle((x,y,x+rng.randrange(1,4),y+1),fill=rng.choice(palette[:5]))
    flat=Image.new('RGBA',(w,h))
    for image in images.values():flat.alpha_composite(image)
    hit=[]
    for y in range(h):
        start=None
        for x in range(w+1):
            opaque=x<w and flat.getpixel((x,y))[3]>0
            if opaque and start is None:start=x
            if not opaque and start is not None:hit.append([y,start,x-1]);start=None
    layers=[]
    for i,(key,image) in enumerate(images.items()):
        layers.append({'name':key,'factor':0 if key=='ground' else .65 if key=='wood' else .8+i*.12,'lag':i*.018,'detach':key not in ['ground','wood'],'src':png(image)})
    return {'width':w,'height':h,'centre':112,'bendTop':8,'bendBase':211,'groundTop':210,'bones':bones,'hit':hit,'sheets':layers}

existing=ROOT/'plants.json'
if not existing.exists():
    raise SystemExit('Retained reference layers must already be present in assets/garden/plants.json')
assets=json.loads(existing.read_text(encoding='utf-8'))
for name,seed in [('ginkgo',11813),('bamboo',2317)]:
    assets[name]=plant(name,seed)
(ROOT/'plants.json').write_text(json.dumps(assets,separators=(',',':')),encoding='utf-8')
# Original floral mark; intentionally uses the same newly selected cherry palette.
logo=Image.new('RGBA',(32,32));d=ImageDraw.Draw(logo)
d.line([(4,29),(14,18),(26,7)],fill='#77564f',width=2)
d.line([(14,18),(8,11)],fill='#8e6660',width=1)
for cx,cy,r in [(21,12,4),(9,11,3)]:
    for i in range(5):
        a=-math.pi/2+i*math.tau/5;x=round(cx+math.cos(a)*r);y=round(cy+math.sin(a)*r)
        d.rectangle((x-2,y-2,x+2,y+2),fill='#da9ab0');d.rectangle((x-1,y-2,x+2,y),fill='#f0c8d2')
    d.rectangle((cx-1,cy-1,cx+1,cy+1),fill='#b08b65')
d.polygon([(13,23),(20,20),(17,25)],fill='#8aab88');logo.save(ROOT/'blossom.png')
print('Updated project-owned assets, preserving three reference plants:',(ROOT/'plants.json').stat().st_size)
