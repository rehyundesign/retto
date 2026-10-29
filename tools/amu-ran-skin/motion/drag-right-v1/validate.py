"""Structural GIF QA and honest original-landmark diagnostics; not art certification."""
from pathlib import Path
from PIL import Image
import json,hashlib,numpy as np
r=Path(__file__).resolve().parent
rows=json.loads((r/'registration.json').read_text());assert len(rows)==16
assert len({x['source_sha256'] for x in rows})==16
assert all(not x['regional_patches'] and not x['warp'] for x in rows)
report={'scope':'one rightward movement review GIF','source_count':16,'reused_or_reversed_filler':0,'motion_regional_grafts':0,'original_pose_authority':'actual assets/spritesheet.webp row1 eight original poses; independent half-step drawings','strict_original_landmark_certification':False,'checks':[]}
decoded=[]
for q in rows:
 p=r/'character'/(q['id']+'.png');im=Image.open(p).convert('RGBA');assert im.size==(448,640)
 assert hashlib.sha256((r/q['source']).read_bytes()).hexdigest()==q['source_sha256']
 decoded.append(hashlib.sha256(im.tobytes()).hexdigest())
 alpha=im.getchannel('A');box=alpha.point(lambda x:255 if x>32 else 0).getbbox()
 assert box[0]>0 and box[1]>0 and box[2]<448 and box[3]<640,(q['id'],'visible clipped art',box)
 ar=np.array(alpha);edge=max(ar[0].max(),ar[-1].max(),ar[:,0].max(),ar[:,-1].max())
 assert edge<=1,(q['id'],'nontrivial alpha touches edge',int(edge))
 assert abs(q['paw_y_residual_2x'])<=1,(q['id'],'original ground/air paw level')
 report['checks'].append({'id':q['id'],'original_profile':q['original_profile'],'face_span_error_2x':q['after']['cheek_span']-q['target']['cheek_span'],'eye_y_residual_2x':round(q['eye_y_residual_2x'],3),'lowest_paw_residual_2x':q['paw_y_residual_2x'],'visible_bounds':box,'max_edge_alpha':int(edge)})
assert len(set(decoded))==16
for theme in ['light','dark']:
 for name,seconds in [('drag-right',8),('character-only',1.6)]:
  im=Image.open(r/f'{name}-{theme}.gif');total=0
  for i in range(im.n_frames):im.seek(i);total+=im.info['duration']
  assert total==round(seconds*1000)
report['decoded_character_count']=len(set(decoded));report['passed']='source locks, unique decoded drawings, whole-cell integrity, visible bounds, ground/air lowest-paw levels, both GIF durations'
report['visual_review']='pending final light/dark boards and browser render; source counts do not prove naturalness'
report['installed']=False
(r/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: structural review checks; original face/eye residuals retained as diagnostics, no strict original-landmark certificate claimed.')
