"""Place isolated approved drawings with uniform scale; preserve every input file.

This repairs the user's requested cross-anchor display sizes. It does not redraw
faces, deform a torso, certify final anatomical registration, or create animation.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import hashlib
import json
import statistics

ROOT = Path(__file__).resolve().parent
SIZE = (448, 640)
manifest = json.loads((ROOT / 'production-map.json').read_text())
VERSION = manifest.get('size_registration', {}).get('version', 'v1')
config_path = manifest.get('size_registration', {}).get('landmarks', 'static-size-landmarks.json')
config = json.loads((ROOT / config_path).read_text())
out = ROOT / f'registered-static-{VERSION}'
out.mkdir(exist_ok=True)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contained(source):
    image = source.copy()
    image.thumbnail(SIZE, Image.Resampling.LANCZOS)
    offset = ((SIZE[0] - image.width) // 2, (SIZE[1] - image.height) // 2)
    cell = Image.new('RGBA', SIZE)
    cell.alpha_composite(image, offset)
    return cell, offset, min(SIZE[0] / source.width, SIZE[1] / source.height)


def cheek_width(image, x_range, y_range):
    """Median warm-fur span; the source ROI excludes hats, paws and tail."""
    pixels = image.load()
    widths = []
    for y in range(max(0, round(y_range[0])), min(image.height, round(y_range[1]))):
        xs = []
        for x in range(max(0, round(x_range[0])), min(image.width, round(x_range[1]))):
            r, g, b, a = pixels[x, y]
            if a > 64 and r >= g >= b + 2 and r - g < 65 and g - b < 70:
                xs.append(x)
        if len(xs) > 35:
            widths.append(xs[-1] - xs[0] + 1)
    if not widths:
        raise ValueError('No fur pixels in measured head region')
    return statistics.median(widths)


def foot_y(image, x_range, minimum_y=440):
    alpha = image.getchannel('A')
    x0, x1 = [max(0, min(image.width, round(x))) for x in x_range]
    bounds = alpha.crop((x0, minimum_y, x1, image.height)).point(
        lambda a: 255 if a > 96 else 0).getbbox()
    if not bounds:
        raise ValueError('No grounded/tucked paw in foot region')
    return minimum_y + bounds[3] - 1


def affine(source, raw_scale, dx, dy, padding=0):
    # One uniform affine scale in both axes; no separate head/body deformation.
    return source.transform((SIZE[0] + padding * 2, SIZE[1] + padding * 2),
        Image.Transform.AFFINE,
        (1 / raw_scale, 0, -(dx + padding) / raw_scale,
         0, 1 / raw_scale, -(dy + padding) / raw_scale),
        Image.Resampling.BICUBIC)


records = []
for anchor in manifest['static_anchors']:
    name = anchor['id']
    spec = config['anchors'][name]
    path = ROOT / anchor['source']
    before_hash = digest(path)
    source = Image.open(path).convert('RGBA')
    work, offset, base_scale = contained(source)
    group = spec['group']
    if 'head_box' in spec:
        box = spec['head_box']
        measured = (box[3] - box[1]) * 2
        target = config['targets']['sleep_head_height' if group == 'sleep' else 'profile_head_height'] * 2
        measure_kind = 'view-specific anatomical head height'
        band = None
    else:
        band = [y * 2 for y in spec.get('cheek_y', [spec['eye_line'] + 8, spec['eye_line'] + 23])]
        measured = cheek_width(work, [x * 2 for x in spec['head_x']], band)
        target = config['targets']['front_cheek_width'] * 2
        measure_kind = 'warm-fur cheek span excluding costume/raised paw/tail'
    scale = target / measured
    old_foot = foot_y(work, [x * 2 for x in spec['foot_x']])
    new_foot = config['targets']['jump_baseline' if group == 'airborne' else 'ground_baseline'] * 2
    old_hip = spec['hip_x'] * 2
    new_hip = spec.get('target_hip_x', config['targets']['front_hip_center_x']) * 2
    tx, ty = new_hip - scale * old_hip, new_foot - scale * old_foot
    raw_scale = base_scale * scale
    dx, dy = offset[0] * scale + tx, offset[1] * scale + ty
    cell = affine(source, raw_scale, dx, dy)
    # Measure the final paw contact again after resampling, then correct rounding.
    foot_range = [x * 2 * scale + tx for x in spec['foot_x']]
    actual_foot = foot_y(cell, foot_range, minimum_y=max(0, round(new_foot - 100)))
    ty += new_foot - actual_foot
    dy = offset[1] * scale + ty
    cell = affine(source, raw_scale, dx, dy)
    padded = affine(source, raw_scale, dx, dy, padding=128)
    if spec.get('registered_clothing_only'):
        # Identity resampling can alter translucent fur RGB through premultiplication.
        # A localized repair already in cell coordinates needs no resampling.
        assert source.size == SIZE and raw_scale == 1 and dx == 0 and dy == 0
        cell = source.copy()
    alpha = padded.getchannel('A')
    draw = ImageDraw.Draw(alpha)
    draw.rectangle((128, 128, 128 + SIZE[0] - 1, 128 + SIZE[1] - 1), fill=0)
    outside = sum(a > 32 for a in alpha.get_flattened_data())
    if outside:
        raise ValueError(f'{name}: {outside} character pixels would be clipped; repair owning layer')
    actual_foot = foot_y(cell, foot_range, minimum_y=max(0, round(new_foot - 100)))
    assert actual_foot == new_foot
    destination = out / f'{name}.png'
    cell.save(destination)
    assert digest(path) == before_hash
    mapped = lambda point: [round(point[0] * 2 * scale + tx, 3), round(point[1] * 2 * scale + ty, 3)]
    mapped_box = lambda box: mapped(box[:2]) + mapped(box[2:])
    if band:
        final_measure = cheek_width(cell,
            [x * 2 * scale + tx for x in spec['head_x']], [y * scale + ty for y in band])
    else:
        final_measure = measured * scale
    assert abs(final_measure - target) <= 2, (name, final_measure, target)
    records.append({'id': name, 'group': group, 'source': anchor['source'],
        'source_sha256': before_hash, 'output': str(destination.relative_to(ROOT)),
        'output_sha256': digest(destination), 'uniform_scale_from_previous_display': round(scale, 6),
        'translation_2x': [round(tx, 3), round(ty, 3)],
        'source_to_cell_affine': {'uniform_scale':raw_scale, 'translate_x':dx, 'translate_y':dy},
        'measurement': measure_kind, 'before_2x': measured, 'target_2x': target,
        'after_2x': final_measure, 'measurement_error_2x': round(final_measure - target, 3),
        'foot_baseline_2x': actual_foot, 'body_center_x_2x': new_hip,
        'eye_line_2x': round(spec['eye_line']*2*scale+ty, 6) if 'eye_line' in spec else None,
        'face_box_2x': mapped_box(spec['face_box']), 'torso_box_2x': mapped_box(spec['torso_box']),
        'tail_anchor_2x': mapped(spec['tail_anchor']), 'clipped_opaque_pixels': outside,
        'four_limb_review': 'source anatomy unchanged under a single uniform transform; see static-review-notes.md',
        'face_shape_deformed': False,
        'strict_anatomical_registration': 'not certified by a display-size normalization'})

body_gate = manifest.get('size_registration', {}).get('body_gate')
body_gate_results = []
if body_gate:
    by_id = {r['id']:r for r in records}
    reference = by_id[body_gate['reference_id']]
    for name,expected in body_gate['anchors'].items():
        row = by_id[name]
        eye_error = row['eye_line_2x']-reference['eye_line_2x']-expected['eye_offset_2x']
        paw_error = row['foot_baseline_2x']-reference['foot_baseline_2x']-expected['paw_offset_2x']
        assert abs(eye_error) <= body_gate['max_eye_error_2x'], (name,'body stature/eye height',eye_error)
        assert abs(paw_error) <= body_gate['max_paw_error_2x'], (name,'ground/jump paw height',paw_error)
        assert row['body_center_x_2x'] == reference['body_center_x_2x']
        body_gate_results.append({'id':name,'eye_error_2x':round(eye_error,6),'paw_error_2x':paw_error})

font = ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc', 13)
for theme, background, ink in [('light', '#fffdfa', '#51444d'), ('dark', '#23232d', '#f0e7ee')]:
    board = Image.new('RGB', (960, 1408), background)
    draw = ImageDraw.Draw(board)
    for i, record in enumerate(records):
        x, y = i % 4 * 240, i // 4 * 352
        label = manifest['static_anchors'][i]['sequence']
        draw.text((x + 8, y + 6), f"{record['id']} / {label}", font=font, fill=ink)
        cell = Image.open(ROOT / record['output']).convert('RGBA').resize((224, 320), Image.Resampling.LANCZOS)
        board.paste(cell, (x + 8, y + 28), cell)
    board.save(ROOT / f'static-size-review-{VERSION}-{theme}.png')

lock = json.loads((ROOT / 'approved-master-v12-lock.json').read_text())
assert all(digest(ROOT / s['path']) == s['sha256'] for s in lock['sources'].values())
report = {'scope': 'user-requested uniform cross-anchor size and placement repair',
    'cell': list(SIZE), 'display': [224, 320], 'separate_companion': True,
    'approved_source_hashes_unchanged': True, 'anisotropic_transforms': False,
    'original_reference': config['canonical_original_profiles'],
    'artwork_redrawn': any('pre_size_repair_source' in a or 'pre_heart_size_repair_source' in a for a in manifest['static_anchors']),
    'redrawn_body_only': [a['id'] for a in manifest['static_anchors'] if 'pre_size_repair_source' in a or 'pre_heart_size_repair_source' in a],
    'head_restoration_audit': 'compact-body-head-lock-audit-v1.json',
    'heart_head_and_costume_restoration_audit': 'heart-body-lock-audit-v2.json' if VERSION=='v2' else None,
    'cross_costume_body_gate':body_gate_results,
    'animated': False, 'installed': False,
    'records': records}
(ROOT / f'static-size-registration-{VERSION}.json').write_text(json.dumps(report, indent=2) + '\n')
print(f'Registered {len(records)} isolated sources: uniform transforms, exact paw baselines, zero clipping, unchanged source hashes.')
