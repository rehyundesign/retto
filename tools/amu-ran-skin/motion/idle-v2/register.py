"""Register complete independent characters, without any regional compositing."""
from pathlib import Path
from PIL import Image, ImageDraw
import argparse,hashlib,json,statistics
import numpy as np

root=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('ids',nargs='*');args=parser.parse_args()
base=json.loads((root/'reference/original-body-landmarks.json').read_text())

def components(mask):
    remaining=set(map(tuple,np.argwhere(mask)));found=[]
    while remaining:
        point=remaining.pop();todo=[point];part=[point]
        while todo:
            y,x=todo.pop()
            for p in [(y-1,x),(y+1,x),(y,x-1),(y,x+1)]:
                if p in remaining:remaining.remove(p);todo.append(p);part.append(p)
        if len(part)>12:
            y,x=np.asarray(part).mean(axis=0);found.append((len(part),float(x),float(y)))
    return sorted(found,reverse=True)

def measure(im,name):
    a=np.asarray(im).astype(float);r,g,b,alpha=[a[:,:,i] for i in range(4)]
    blue=(b-r>12)&(g-r>5)&(alpha>128)
    blue[:120]=False;blue[430:]=False
    blobs=components(blue);pairs=[]
    for i,p in enumerate(blobs):
        for q in blobs[i+1:]:
            if 40<abs(p[1]-q[1])<130 and abs(p[2]-q[2])<18:
                pairs.append((p[0]+q[0],(p[1]+q[1])/2,(p[2]+q[2])/2))
    if pairs:
        _,cx,eye=max(pairs)
    else:
        # Full blink: nose stays articulated with the actual whole head.
        pink=(r-g>25)&(b-g>-15)&(g>90)&(alpha>128)
        pink[:310]=False;pink[430:]=False;pink[:,:110]=False;pink[:,245:]=False
        blobs=components(pink)
        assert blobs, (name,'no facial landmark detected')
        _,cx,ny=blobs[0];eye=ny-29
    spans=[];centers=[]
    for y in range(round(eye+8),round(eye+23)):
        xs=np.flatnonzero(alpha[y]>96)
        xs=xs[(xs>cx-160)&(xs<cx+160)]
        if len(xs):spans.append(int(xs[-1]-xs[0]+1));centers.append(float((xs[-1]+xs[0])/2))
    width=statistics.median(spans);center=statistics.median(centers)
    # Grounded foreleg and rear support soles, excluding the tail.
    lo,hi=round(center-width*.36),round(center+width*.36)
    ys,xs=np.nonzero(alpha[round(eye+100):,lo:hi]>96)
    assert len(ys),(name,'no support paw')
    foot=round(eye+100)+int(ys.max())
    # Viewer-right forepaw stays grounded throughout the tie-adjusting sequence.
    lo,hi=max(0,round(center+5)),min(448,round(center+width*.44))
    fy,fx=np.nonzero(alpha[max(0,foot-10):foot+1,lo:hi]>96)
    support=float(np.mean(fx)+lo) if len(fx) else center+40
    return {'cheek_width':width,'head_center_x':center,'eye_line':eye,'foot_baseline':foot,'support_toe_x':support}

records_path=root/'registration.json'
records=json.loads(records_path.read_text()) if records_path.exists() else []
for name in args.ids or [f'F{i:02}' for i in range(16)]:
    if name=='F00' and (root/'reference/costume-master.png').exists():
        out=Image.open(root/'reference/costume-master.png').convert('RGBA')
        post=measure(out,name);out.save(root/'character/F00.png')
        records=[r for r in records if r['id']!='F00']
        records.append({'id':'F00','source':'reference/costume-master.png',
            'source_sha256':hashlib.sha256((root/'reference/costume-master.png').read_bytes()).hexdigest(),
            'after':post,'static_master_proportion_fix':'master-registration.json',
            'regional_grafts':'static <=3% body correction with face restored, not an animated cell patch',
            'full_generated_body_preserved':True,'head_or_body_warp':False})
        continue
    path=root/'raw'/f'{name}.png'
    if not path.exists():continue
    src=Image.open(path).convert('RGBA');contained=src.copy();contained.thumbnail((448,640),Image.Resampling.LANCZOS)
    ox,oy=(448-contained.width)//2,(640-contained.height)//2
    work=Image.new('RGBA',(448,640));work.alpha_composite(contained,(ox,oy))
    m=measure(work,name);scale=base['cheek_width']/m['cheek_width']
    master_row=next((r for r in records if r['id']=='F00'),None)
    x=base['head_center_x']-scale*m['head_center_x']
    if name!='F00' and master_row:
        # Preserve the planted support anchor while allowing a genuine head glance.
        x=master_row['after']['support_toe_x']-scale*m['support_toe_x']
    y=base['foot_baseline']-scale*m['foot_baseline']
    raw_scale=scale*contained.width/src.width;dx=ox*scale+x;dy=oy*scale+y
    out=src.transform((448,640),Image.Transform.AFFINE,
        (1/raw_scale,0,-dx/raw_scale,0,1/raw_scale,-dy/raw_scale),Image.Resampling.BICUBIC)
    # Clear alpha-zero RGB only; retain every visible generated pixel as a whole.
    a=np.array(out);a[a[:,:,3]==0,:3]=0;out=Image.fromarray(a)
    post=measure(out,name)
    if abs(post['foot_baseline']-base['foot_baseline'])>1:
        adjust=base['foot_baseline']-post['foot_baseline'];dy+=adjust;y+=adjust
        out=src.transform((448,640),Image.Transform.AFFINE,(1/raw_scale,0,-dx/raw_scale,0,1/raw_scale,-dy/raw_scale),Image.Resampling.BICUBIC)
        a=np.array(out);a[a[:,:,3]==0,:3]=0;out=Image.fromarray(a);post=measure(out,name)
    assert abs(post['foot_baseline']-base['foot_baseline'])<=1,(name,post)
    assert abs(post['cheek_width']-base['cheek_width'])<=3,(name,post)
    bounds=out.getchannel('A').point(lambda a:255 if a>32 else 0).getbbox()
    assert bounds and bounds[0]>0 and bounds[2]<448 and bounds[1]>0 and bounds[3]<640,(name,'clipping',bounds)
    out.save(root/'character'/f'{name}.png')
    records=[r for r in records if r['id']!=name]
    records.append({'id':name,'source':f'raw/{name}.png','source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'whole_source_uniform_scale':raw_scale,'whole_source_translation':[dx,dy],
        'contained_registration_scale':scale,'before':m,'after':post,'opaque_bounds':bounds,
        'regional_grafts':False,'head_or_body_warp':False,'full_generated_body_preserved':True})
records_path.write_text(json.dumps(sorted(records,key=lambda r:r['id']),indent=2)+'\n')
print('Whole-character registration complete; zero facial/clothing/paw patches or temporal blends.')
