from pathlib import Path
from PIL import Image, ImageDraw
import json, hashlib, math
import numpy as np
ROOT=Path(__file__).parent
m=json.loads((ROOT/'manifest.json').read_text())
def gemstone(im,state):
    a=np.asarray(im).astype(float);r,g,b,alpha=[a[:,:,i] for i in range(4)]
    pink=(r>170)&(b>120)&(r-g>40)&(b-g>25)&(alpha>160)
    gold=(r>165)&(g>85)&(g<248)&(b<145)&(r-b>65)&(alpha>160)
    bounds={'idle':(175,235,380,435),'running':(175,240,375,435),'review':(185,240,385,445),'waiting':(180,245,375,440),'waving':(145,220,355,425),'failed':(145,220,410,490),'sleeping':(265,330,480,555)}
    x0,x1,y0,y1=bounds.get(state,(45,410,180,605))
    yy,xx=np.nonzero(pink[y0:y1,x0:x1]);xx=xx+x0;yy=yy+y0
    candidates=[]
    # Weighted centres of overlapping 16px windows seed circular-ring fitting.
    for gy in range(y0,y1,8):
        for gx in range(x0,x1,8):
            q=(abs(xx-gx)<11)&(abs(yy-gy)<11)
            if q.sum()<5:continue
            candidates.append((float(xx[q].mean()),float(yy[q].mean())))
    angles=np.arange(32)*math.tau/32;best=None
    for cx,cy in candidates:
        for radius in range(5,19):
            xs=np.rint(cx+np.cos(angles)*radius).astype(int);ys=np.rint(cy+np.sin(angles)*radius).astype(int)
            coverage=float(gold[ys,xs].mean())
            xa,xb=int(cx-radius*.6),int(cx+radius*.6+1);ya,yb=int(cy-radius*.6),int(cy+radius*.6+1)
            mass=float(pink[ya:yb,xa:xb].mean())
            score=coverage**3*mass
            if best is None or score>best[0]:best=(score,cx,cy,radius,coverage)
    assert best and best[0]>.01,(state,best)
    return [round(best[1],2),round(best[2],2)]
missing=[]
for s in m['states']:
    s['anchors']=[]
    for i,file in enumerate(s['characters']):
        p=ROOT/file
        if not p.exists():missing.append(file);s['anchors'].append(None);continue
        im=Image.open(p).convert('RGBA')
        s['anchors'].append(gemstone(im,s['id']))
    s['ready']=all((ROOT/f).exists() for f in s['characters'])
m['status']='complete character coverage; visual QA required' if not missing else 'in progress; not final'
m['missingCharacters']=missing
(ROOT/'manifest.json').write_text(json.dumps(m,indent=2))
(ROOT/'preview-data.js').write_text('window.JEANNE_V36='+json.dumps(m,ensure_ascii=False)+';\n')
# Attachment review: magenta cross must stay inside the Rosario gemstone.
for s in m['states']:
    board=Image.new('RGB',(896,336*((len(s['files'])+3)//4)),'#181827');d=ImageDraw.Draw(board)
    for i,file in enumerate(s['characters']):
        p=ROOT/file
        if not p.exists():continue
        im=Image.open(p).convert('RGBA').resize((224,320),Image.Resampling.LANCZOS)
        tile=Image.new('RGBA',(224,320),'#181827');tile.alpha_composite(im)
        x=i%4*224;y=i//4*336;board.paste(tile.convert('RGB'),(x,y))
        if s['anchors'][i]:
            ax,ay=s['anchors'][i];ax=x+ax/2;ay=y+ay/2
            d.line((ax-4,ay,ax+4,ay),fill='#00ffd5',width=1);d.line((ax,ay-4,ax,ay+4),fill='#00ffd5',width=1)
        d.text((x+8,y+322),str(i),fill='#aaaaaa')
    board.save(ROOT/f"{s['id']}-anchor-review.png")
print(json.dumps({'status':m['status'],'readyStates':[s['id'] for s in m['states'] if s['ready']],'missingCharacters':len(missing)}))
