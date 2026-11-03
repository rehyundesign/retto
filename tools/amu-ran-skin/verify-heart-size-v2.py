"""Check the four repaired bodies against frozen inputs and approved faces."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageChops

root = Path(__file__).resolve().parent
read = lambda path: json.loads((root / path).read_text())
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
report = read('static-size-registration-v2.json')
rows = {r['id']: r for r in report['records']}
previous = read('heart-size-input-v2/all-v1-source-hashes.json')
corrected = {'A06', 'A07', 'A14', 'A15'}
clothing_repairs = set(read('production-map.json').get('size_registration', {}).get('scoped_clothing_repairs', {}))
changed = set()
for filename, expected in previous.items():
    assert digest(root / 'registered-static-v1' / filename) == expected
    output = root / 'registered-static-v2' / filename
    assert Image.open(output).size == (448, 640)
    if digest(output) != expected:
        changed.add(Path(filename).stem)
assert changed == corrected | clothing_repairs, changed
for master in read('approved-master-v12-lock.json')['sources'].values():
    assert digest(root / master['path']) == master['sha256']
for row in report['records']:
    assert row['clipped_opaque_pixels'] == 0
assert len(report['cross_costume_body_gate']) == 4
for row in report['cross_costume_body_gate']:
    assert abs(row['eye_error_2x']) <= 1 and row['paw_error_2x'] == 0

# Match the approved face after the same single uniform cell transform.
specs = {'A06': (80, (105,242,246,337)), 'A07': (55, (105,276,246,372)),
         'A14': (70, (106,254,246,349)), 'A15': (131, (105,153,246,242))}
for name, (shift, box) in specs.items():
    expected = Image.new('RGBA', (448,640))
    expected.paste(Image.open(root / 'heart-size-input-v2' / f'{name}.png').convert('RGBA'), (0,shift))
    affine = rows[name]['source_to_cell_affine']
    scale, tx, ty = (affine[k] for k in ('uniform_scale','translate_x','translate_y'))
    expected = expected.transform((448,640), Image.Transform.AFFINE,
        (1/scale,0,-tx/scale,0,1/scale,-ty/scale), Image.Resampling.BICUBIC)
    roi = (round(box[0]*scale+tx)+3, round((box[1]+shift)*scale+ty)+3,
           round(box[2]*scale+tx)-3, round((box[3]+shift)*scale+ty)-3)
    actual = Image.open(root / rows[name]['output']).convert('RGBA')
    diff = ImageChops.difference(expected.crop(roi), actual.crop(roi))
    assert not any(any(pixel) for pixel in diff.get_flattened_data()), name

# Regression: the previous face-width-only registration must fail body height.
old = {r['id']: r for r in read('heart-size-input-v2/static-size-registration-v1.json')['records']}
landmarks = read('heart-size-input-v2/static-size-landmarks.json')['anchors']
old_eye = lambda name: landmarks[name]['eye_line']*2*old[name]['uniform_scale_from_previous_display']+old[name]['translation_2x'][1]
assert abs(old_eye('A06')-old_eye('A01')) > 1
print(f'PASS: 4 body gates, 4 exact face templates, {16-len(changed)} unchanged cells, declared clothing repairs, masters, clipping and previous-size regression.')
