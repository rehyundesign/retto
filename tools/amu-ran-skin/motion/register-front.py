"""Uniform whole-source registration using protected inner-face template matching.
The face remains independently drawn in every source; no face/body graft is performed.
"""
from pathlib import Path
from PIL import Image
import sys,json,hashlib,importlib.util
import numpy as np
root=Path(__file__).resolve().parent
mods={}
for key,file in [('mf','measure-front.py'),('fr','face-registration.py')]:
 spec=importlib.util.spec_from_file_location(key,root/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);mods[key]=m
mf,fr=mods['mf'],mods['fr'];state=sys.argv[1];r=root/state;name=state.rsplit('-v',1)[0]
entry=next(x for x in json.loads((root.parent/'full-motion-plan.json').read_text())['remaining_states'] if x['id']==name)
base=json.loads((root/'idle-v2/reference/original-body-landmarks.json').read_text());heart=entry['costume']=='heart'
refpath=root.parent/'registered-static-v2/A06.png' if heart else root/'idle-v2/reference/costume-master.png'
reference=Image.open(refpath).convert('RGBA');unit=228/224 if heart else 1.0;rows=[]
for i in range(16):
 p=r/'raw'/f'F{i:02}.png'
 if not p.exists():continue
 src=Image.open(p).convert('RGBA');im=src.copy();im.thumbnail((448,640),Image.Resampling.LANCZOS);ox=(448-im.width)//2;oy=(640-im.height)//2;cell=Image.new('RGBA',(448,640));cell.alpha_composite(im,(ox,oy))
 m=mf.measure(cell,p.stem);fit=fr.match(cell,reference,guess_eye=(m['eye_center_x'],m['eye_line']));predicted_fur_width=(224 if heart else 228)/fit['scale_to_reference']
 occluded_cheek=(name=='waving' and p.stem=='F07')  # actual raised paw occludes the cheek scan; whole-source registration only
 scale=fit['scale_to_reference']*unit if occluded_cheek else 228/m['cheek_width']
 cx=(171.5-fit['translation_to_reference'][0])/fit['scale_to_reference'] if occluded_cheek else m['head_center_x']
 # Ground from real central paws, with headgear/tail excluded by body-relative x range.
 al=np.asarray(cell)[:,:,3];lo=max(0,round(cx-90/fit['scale_to_reference']));hi=min(448,round(cx+90/fit['scale_to_reference']))
 ys,xs=np.nonzero(al[round(m['eye_line']+100):,lo:hi]>96);foot_source=round(m['eye_line']+100)+int(ys.max())
 foot=entry.get('lowest_paw_targets_2x',[629]*16)[i]
 dx=171.5-cx*scale;dy=foot-foot_source*scale
 s=scale*im.width/src.width;tx=dx+ox*scale;ty=dy+oy*scale
 out=src.transform((448,640),Image.Transform.AFFINE,(1/s,0,-tx/s,0,1/s,-ty/s),Image.Resampling.BICUBIC);ar=np.array(out);ar[ar[:,:,3]==0,:3]=0;out=Image.fromarray(ar);out.save(r/'character'/p.name);post=mf.measure(out,p.stem)
 rows.append({'id':p.stem,'source':str(p.relative_to(r)),'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'uniform_scale':s,'translation':[tx,ty],'before':m,'after':post,'inner_face_match':fit,'occluded_cheek_template_scale':bool(occluded_cheek),'reference':str(refpath),'face_template_only_for_measurement':True,'target':{'reference_face_unit_scale':unit,'body_center_x':171.5,'lowest_paw_y':foot},'regional_patches':False,'warp':False,'original_eye_y_residual_2x':post['eye_line']-base['eye_line'],'lowest_paw_residual_2x':post['foot_baseline']-foot})
(r/'registration.json').write_text(json.dumps(rows,indent=2)+'\n')
for q in rows:print(q['id'],'face_loss',round(q['inner_face_match']['ncc_loss'],3),'eye_delta',round(q['original_eye_y_residual_2x'],1),'foot_delta',q['lowest_paw_residual_2x'])
