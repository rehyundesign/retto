"""Whole-source curled-pose registration; closed-face template, no head/body patches."""
from pathlib import Path
from PIL import Image
import json,hashlib,importlib.util
import numpy as np
root=Path(__file__).resolve().parent;r=root/'sleeping-v1'
sp=importlib.util.spec_from_file_location('fr',root/'face-registration.py');fr=importlib.util.module_from_spec(sp);sp.loader.exec_module(fr)
sp=importlib.util.spec_from_file_location('lm',root/'drag-left-v1/measure.py');lm=importlib.util.module_from_spec(sp);sp.loader.exec_module(lm)
def contained(p):
 src=Image.open(p).convert('RGBA');im=src.copy();im.thumbnail((448,640),Image.Resampling.LANCZOS);ox,oy=(448-im.width)//2,(640-im.height)//2;c=Image.new('RGBA',(448,640));c.alpha_composite(im,(ox,oy));return src,im,c,ox,oy
def measure(im):
 a=np.array(im).astype(float);rr,g,b,al=[a[:,:,i] for i in range(4)];bounds=im.getchannel('A').point(lambda x:255 if x>96 else 0).getbbox();mask=(rr-g>45)&(b-g>-22)&(g>70)&(al>128);mask[:bounds[3]-100]=0;mask[bounds[3]-35:]=0;mask[:,:220]=0;mask[:,350:]=0;bb=lm.blobs(mask)
 if not bb:raise ValueError('sleep nose landmark missing')
 n,x,y=bb[0];return {'nose_x':x,'nose_y':y,'foot_baseline':bounds[3]-1,'bounds':bounds}
reference=Image.open(r/'raw/F00.png').convert('RGBA');base=measure(reference);roi=(240,539,338,615);rows=[]
for p in sorted((r/'raw').glob('F*.png')):
 src,im,cell,ox,oy=contained(p);m=measure(cell);fit=fr.match(cell,reference,roi=roi,guess_eye=(m['nose_x'],m['nose_y']),reference_anchor=(base['nose_x'],base['nose_y']));s=fit['scale_to_reference'];dx=fit['translation_to_reference'][0];dy=629-m['foot_baseline']*s;raw_s=s*im.width/src.width;tx,ty=dx+ox*s,dy+oy*s
 out=src.transform((448,640),Image.Transform.AFFINE,(1/raw_s,0,-tx/raw_s,0,1/raw_s,-ty/raw_s),Image.Resampling.BICUBIC);a=np.array(out);a[a[:,:,3]==0,:3]=0;out=Image.fromarray(a);out.save(r/'character'/p.name);post=measure(out)
 rows.append({'id':p.stem,'source':str(p.relative_to(r)),'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'uniform_scale':raw_s,'translation':[tx,ty],'before':m,'after':post,'inner_face_match':fit,'regional_patches':False,'warp':False,'target':{'foot_baseline':629,'view_group':'original curled sleep, not frontal seated'},'lowest_paw_residual_2x':post['foot_baseline']-629})
(r/'registration.json').write_text(json.dumps(rows,indent=2)+'\n')
for q in rows:print(q['id'],'face_loss',round(q['inner_face_match']['ncc_loss'],3),'nose',round(q['after']['nose_x'],1),round(q['after']['nose_y'],1),'foot',q['after']['foot_baseline'])
