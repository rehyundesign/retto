"""Register independent idle drawings and protect approved identity/support regions.

Only a single uniform source registration is allowed. Actual eye, cloth-fold and
tail drawings come from each independent source; no synthesized pose deformation.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import argparse, hashlib, json
import numpy as np

root=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('ids',nargs='*');args=parser.parse_args()
master=Image.open(root/'reference/school-master.png').convert('RGBA')
target=np.asarray(master.convert('RGB'),dtype=np.float32)
ys,xs=np.mgrid[278:329:7,106:244:7]
y2,x2=np.mgrid[380:416:7,135:223:7]
ys=np.concatenate([ys.ravel(),y2.ravel()]);xs=np.concatenate([xs.ravel(),x2.ravel()])
pixels=target[ys,xs]
records=[]
audit=root/'registration.json'
if audit.exists():records=json.loads(audit.read_text())
ids=args.ids or [f'F{i:02}' for i in range(16)]
for name in ids:
    path=root/'raw'/f'{name}.png'
    if name=='F00':path=root/'raw/F00-approved.png'
    if not path.exists():continue
    source=Image.open(path).convert('RGBA')
    if name=='F00':
        result=master.copy();scale=1.;tx=ty=0;error=0
    else:
        raw=np.asarray(source.convert('RGB'),dtype=np.float32)
        # Search only rigid placement and one shared XY scale against forehead
        # and muzzle, excluding eyelids/pupils so a blink cannot bias the fit.
        best=(float('inf'),None)
        start=448/source.width
        stages=[(np.arange(start*.70,start*1.31,start*.0125),np.arange(-65,66,5),range(-100,151,5)),
                (None,None,None)]
        for stage,(scales,dxs,dys) in enumerate(stages):
            if stage:
                s0,x0,y0=best[1]
                scales=np.arange(s0-start*.014,s0+start*.014,start*.0015)
                dxs=np.arange(x0-5,x0+6);dys=range(y0-5,y0+6)
            for s in scales:
                for dy in dys:
                    iy=np.rint((ys-dy)/s).astype(int)
                    ix=np.rint((xs[None,:]-dxs[:,None])/s).astype(int)
                    if iy.min()<0 or iy.max()>=raw.shape[0] or ix.min()<0 or ix.max()>=raw.shape[1]:continue
                    values=raw[iy[None,:],ix]
                    errors=((values-pixels)**2).mean(axis=(1,2));i=errors.argmin()
                    if errors[i]<best[0]:best=(float(errors[i]),(float(s),int(dxs[i]),int(dy)))
        error,(scale,tx,ty)=best
        aligned=source.transform((448,640),Image.Transform.AFFINE,
            (1/scale,0,-tx/scale,0,1/scale,-ty/scale),Image.Resampling.BICUBIC)
        (root/'aligned').mkdir(exist_ok=True);aligned.save(root/'aligned'/f'{name}.png')
        # Spatial identity restoration, never temporal blending between drawings.
        eyes=Image.new('L',master.size);d=ImageDraw.Draw(eyes)
        d.ellipse((110,330,164,378),fill=255);d.ellipse((188,330,242,378),fill=255)
        eyes=eyes.filter(ImageFilter.GaussianBlur(2))
        cloth=Image.new('L',master.size);d=ImageDraw.Draw(cloth)
        d.polygon([(112,442),(231,442),(244,484),(235,549),(112,549),(100,485)],fill=255)
        cloth=cloth.filter(ImageFilter.GaussianBlur(4))
        tail=Image.new('L',master.size);d=ImageDraw.Draw(tail)
        d.polygon([(284,432),(438,437),(438,630),(287,630),(277,569),(276,500)],fill=255)
        tail=tail.filter(ImageFilter.GaussianBlur(2))
        mask=ImageChops.lighter(ImageChops.lighter(eyes,cloth),tail)
        ImageDraw.Draw(mask).rectangle((0,590,278,639),fill=0)
        result=Image.composite(aligned,master,mask)
        # Protect all four support feet and the whole muzzle/skull/ear/clip.
        assert not any(any(p) for p in ImageChops.difference(result,master).crop((45,590,278,640)).get_flattened_data())
        mask.save(root/'registration-active-regions.png')
    result.save(root/'character'/f'{name}.png')
    records=[r for r in records if r['id']!=name]
    records.append({'id':name,'source':str(path.relative_to(root)),
        'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'uniform_scale':scale,'translation':[tx,ty],'identity_template_mse':error,
        'final_sha256':hashlib.sha256(result.tobytes()).hexdigest(),
        'planted_paws_preserved':True,'face_body_warp':False})
audit.write_text(json.dumps(sorted(records,key=lambda r:r['id']),indent=2)+'\n')
print(f'Registered {len(ids)} requested independent drawings with protected head/support regions.')
