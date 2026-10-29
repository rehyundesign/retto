"""Whole-cell uniform registration against each actual original gait pose."""
from pathlib import Path
from PIL import Image
import json,hashlib
import numpy as np
from measure import measure
r=Path(__file__).resolve().parent
original=[measure(r/'reference'/f'base-{i:02}.png') for i in range(8)]
records=[]
for i in range(16):
 p=r/'raw'/f'F{i:02}.png'
 if not p.exists():continue
 a,b=original[i//2],original[(i//2+1)%8];u=.5 if i%2 else 0
 target={k:a[k]*(1-u)+b[k]*u for k in ['eye_x','eye_y','cheek_span']}
 target['lowest_paw_y']=a['bounds'][3]*(1-u)+b['bounds'][3]*u
 m=measure(p);scale=target['cheek_span']/m['cheek_span']
 dx=target['eye_x']-m['eye_x']*scale;dy=target['lowest_paw_y']-m['bounds'][3]*scale
 src=Image.open(p).convert('RGBA');s=m['source_scale']*scale
 out=src.transform((448,640),Image.Transform.AFFINE,(1/s,0,-dx/s,0,1/s,-dy/s),Image.Resampling.BICUBIC)
 ar=np.array(out);ar[ar[:,:,3]==0,:3]=0;out=Image.fromarray(ar)
 op=r/'character'/p.name;out.save(op);post=measure(op)
 # Refine the same uniform transform after raster sampling changes the cheek scanline.
 for _ in range(4):
  if abs(post['cheek_span']-target['cheek_span'])<=1:break
  scale*=target['cheek_span']/post['cheek_span']
  dx=target['eye_x']-m['eye_x']*scale;dy=target['lowest_paw_y']-m['bounds'][3]*scale
  s=m['source_scale']*scale
  out=src.transform((448,640),Image.Transform.AFFINE,(1/s,0,-dx/s,0,1/s,-dy/s),Image.Resampling.BICUBIC)
  ar=np.array(out);ar[ar[:,:,3]==0,:3]=0;out=Image.fromarray(ar);out.save(op);post=measure(op)
 records.append({'id':p.stem,'source':str(p.relative_to(r)),'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'original_profile':[i//2,(i//2+1)%8] if i%2 else [i//2],'target':target,'before':m,'after':post,'uniform_scale':s,'translation':[dx,dy],'regional_patches':False,'warp':False,'eye_y_residual_2x':post['eye_y']-target['eye_y'],'paw_y_residual_2x':post['bounds'][3]-target['lowest_paw_y']})
(r/'registration.json').write_text(json.dumps(records,indent=2)+'\n')
print('id, cheek width, original width, eye-y residual, foot residual')
for q in records: print(q['id'],q['after']['cheek_span'],q['target']['cheek_span'],round(q['eye_y_residual_2x'],1),q['paw_y_residual_2x'])
