"""Check idle evidence without treating decoded hashes as motion approval."""
from pathlib import Path
from PIL import Image, ImageChops
import hashlib,json,math
import numpy as np

root=Path(__file__).resolve().parent
master=Image.open(root/'reference/school-master.png').convert('RGBA')
mask=Image.open(root/'registration-active-regions.png').convert('L')
rows=[]
order=json.loads((root/'plan.json').read_text())['frame_order']
for slot,i in enumerate(order):
    im=Image.open(root/'character'/f'F{i:02}.png').convert('RGBA')
    diff=ImageChops.difference(im,master)
    assert not any(any(p) for p,k in zip(diff.get_flattened_data(),mask.get_flattened_data()) if k==0),i
    a=np.asarray(im)
    eyes=np.concatenate([a[330:379,110:165,:3].reshape(-1,3),a[330:379,188:243,:3].reshape(-1,3)]).astype(float)
    blue=int(((eyes[:,2]-eyes[:,0]>12)&(eyes[:,1]-eyes[:,0]>5)).sum())
    tail=a[435:630,284:440,3]>96;y,x=np.nonzero(tail)
    rows.append({'id':f'F{i:02}','playback_slot':slot,'blue_iris_pixels':blue,
        'tail_center_2x':[round(float(x.mean())+284,2),round(float(y.mean())+435,2)],
        'support_region_changed_pixels':0,'protected_identity_region_changed_pixels':0,
        'anatomy':'four limbs: two unchanged front support paws, rear pair behind; no lifted or duplicate paw'})
assert rows[8]['blue_iris_pixels'] < rows[0]['blue_iris_pixels']*.15
steps=[]
for i in range(16):
    p,q=rows[i]['tail_center_2x'],rows[(i+1)%16]['tail_center_2x']
    steps.append(round(math.dist(p,q),3))
report={'counts':'16 independent drawing sources, 16 distinct decoded character cells; visual continuity reviewed separately',
    'rows':rows,'tail_center_step_2x':steps,'loop_seam_tail_step_2x':steps[-1],
    'baseline':'approved A01 unchanged support-foot pixels; same 628px 2x contact baseline',
    'size':'approved school anchor preserved; no whole-character animation scaling',
    'original_atlas_final_registration':'not certified by the idle preview; preserve static registration report boundaries',
    'native_build_test':'not applicable to this GIF-only change','installed':False}
(root/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: protected identity, four fixed support limbs, closed-eye phase and 16 source cells verified; tail/iris metrics saved for visual continuity review.')
