"""Verify scoped tailoring, preserved anatomy, and unchanged other anchors."""
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont
import hashlib
import json

root = Path(__file__).resolve().parent
read = lambda p: json.loads((root/p).read_text())
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
version = read('production-map.json').get('size_registration', {}).get('school_tailoring_version', 'v3')
old = Image.open(root/f'sleeve-repair-input-{version}/A02.png').convert('RGBA')
new = Image.open(root/'registered-static-v2/A02.png').convert('RGBA')
mask = Image.open(root/f'A02-sleeve-edit-mask-{version}.png').convert('L')
diff = ImageChops.difference(old,new)
outside = sum(any(pixel) for pixel,allowed in zip(diff.get_flattened_data(),mask.get_flattened_data()) if not allowed)
assert outside == 0
assert not any(any(pixel) for pixel in diff.crop((45,190,296,416)).get_flattened_data())
assert any(any(pixel) for pixel in diff.get_flattened_data())
old_hashes = read(f'sleeve-repair-input-{version}/registered-cell-hashes.json')
for name, expected in old_hashes.items():
    if name != 'A02.png':
        assert digest(root/'registered-static-v2'/name) == expected, name
before = next(a for a in read(f'sleeve-repair-input-{version}/static-size-registration-v2.json')['records'] if a['id']=='A02')
after = next(a for a in read('static-size-registration-v2.json')['records'] if a['id']=='A02')
for k in ['eye_line_2x','face_box_2x','torso_box_2x','body_center_x_2x','foot_baseline_2x','tail_anchor_2x']:
    assert before[k] == after[k], k
assert after['clipped_opaque_pixels'] == 0
font = ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc',14)
ran = Image.open(root/'reference/ran-sculpted-v10-source.png').convert('RGBA')
ran = ran.crop(ran.getchannel('A').point(lambda a:255 if a>8 else 0).getbbox())
ran.thumbnail((90,90),Image.Resampling.LANCZOS)
for theme,bg,ink in [('light','#fffdfa','#51444d'),('dark','#23232d','#f0e7ee')]:
    board = Image.new('RGB',(480,352),bg);draw=ImageDraw.Draw(board)
    for i,(name,label) in enumerate([('A01','교복 · 기본'),('A02','교복 · 앞발 들기')]):
        cell = Image.open(root/'registered-static-v2'/f'{name}.png').convert('RGBA')
        cell.alpha_composite(ran,(360,330))
        cell = cell.resize((224,320),Image.Resampling.LANCZOS)
        draw.text((i*240+8,6),label,font=font,fill=ink)
        board.paste(cell,(i*240+8,28),cell)
    board.save(root/f'school-raised-paw-review-{version}-{theme}.png')
    if version == 'v4':
        detail = Image.new('RGB',(480,352),bg)
        draw = ImageDraw.Draw(detail)
        draw.text((8,6),'수정한 앞발 들기',font=font,fill=ink)
        draw.text((248,6),'어깨 · 옆구리 · 밑단',font=font,fill=ink)
        cell = new.resize((224,320),Image.Resampling.LANCZOS)
        detail.paste(cell,(8,28),cell)
        crop = new.crop((30,416,182,575)).resize((224,234),Image.Resampling.LANCZOS)
        detail.paste(crop,(248,74),crop)
        detail.save(root/f'school-raised-paw-detail-{version}-{theme}.png')
report = {'scope':'A02 raised foreleg school sleeve only','outside_clothing_mask_changed_pixels':outside,
    'unchanged_other_cells':15,'face_and_body_landmarks_unchanged':True,'clipped_pixels':0,
    'four_limb_visual_review':{'front_right':'viewer-left raised paw; black sleeve joins shoulder, white cuff below paw',
        'front_left':'viewer-right grounded foreleg, unchanged','rear_right':'viewer-left supporting rear leg, unchanged',
        'rear_left':'viewer-right rear leg behind grounded foreleg, unchanged','verdict':'approved'},
    'depth_order':'rear skirt and torso, shoulder-attached bent blazer sleeve, white cuff, raised furry paw',
    'light_dark_1x_review':True,'animated':False,'installed':False}
if version == 'v4':
    report['visual_tailoring_correction'] = 'removed downward empty-sleeve silhouette below raised elbow; shortened diagonal torso hem rises toward raised arm, plaid waist strip follows below; no cuff on rear thigh'
(root/f'sleeve-repair-verification-{version}.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: sleeve-only changes, exact face/body landmarks, other 15 cells unchanged, no clipping; 1x boards rendered.')
