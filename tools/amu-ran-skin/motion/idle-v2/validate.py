"""Original-size and whole-source checks; visual movement remains a separate gate."""
from pathlib import Path
from PIL import Image
import json,hashlib

root=Path(__file__).resolve().parent
read=lambda p:json.loads((root/p).read_text())
base=read('reference/original-body-landmarks.json')
rows=read('registration.json');assert len(rows)==16
master=next(r for r in rows if r['id']=='F00')['after']
checks=[]
for row in rows:
    m=row['after'];name=row['id']
    im=Image.open(root/'character'/f'{name}.png').convert('RGBA')
    assert im.size==(448,640)
    assert abs(m['cheek_width']-base['cheek_width'])<=3,(name,'original face width',m)
    assert abs(m['foot_baseline']-base['foot_baseline'])<=1,(name,'ground contact',m)
    assert abs(m['support_toe_x']-master['support_toe_x'])<=1.5,(name,'sliding support paw',m)
    height_error=m['eye_line']-base['eye_line']
    assert abs(height_error)<=6,(name,'body grew or shortened instead of actual paw movement',height_error)
    if name!='F00':
        assert row['regional_grafts'] is False
        assert row['head_or_body_warp'] is False
    bounds=im.getchannel('A').point(lambda a:255 if a>32 else 0).getbbox()
    assert bounds[0]>0 and bounds[1]>0 and bounds[2]<448 and bounds[3]<640,(name,'clipped')
    checks.append({'id':name,'original_cheek_width_error_2x':m['cheek_width']-base['cheek_width'],
        'original_eye_height_error_2x':round(height_error,3),'foot_baseline_error_2x':m['foot_baseline']-base['foot_baseline'],
        'support_toe_slide_2x':round(m['support_toe_x']-master['support_toe_x'],3),
        'full_motion_cell_without_grafts':name!='F00','opaque_bounds':bounds})
assert len({r['source_sha256'] for r in rows})==16
assert len({hashlib.sha256(Image.open(root/'character'/f'F{i:02}.png').convert('RGBA').tobytes()).hexdigest() for i in range(16)})==16
report={'scope':'idle v2 original Retto size and whole-character integrity',
    'original_measurement':base,'checks':checks,'distinct_source_drawings':16,'distinct_decoded_characters':16,
    'static_master_uniform_correction':read('master-registration.json')['whole_body_uniform_correction'],
    'motion_grafts_or_face_body_warps':0,'loop_visual_continuity':'pending visual review',
    'four_limbs_and_costume_fit':'pending each-cell and triplet visual review','native_test':'not applicable to GIF-only art',
    'installed':False}
(root/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: original Retto face/body stature and fixed support checked for all16; no motion-cell grafts/warps; visual gates separate.')
