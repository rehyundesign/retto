"""Assemble independently generated character anchors for internal visual review.

Canvas conversion preserves aspect ratio. It is not original Retto registration
approval, and this script never generates animation frames from static anchors.
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
manifest = json.loads((ROOT / 'manifest.json').read_text())
results = json.loads((ROOT / 'generated-results.json').read_text())
by_id = {item['id']: item for item in results}
(ROOT / 'cells').mkdir(exist_ok=True)
reports = []
for anchor in manifest['anchors']:
    result = by_id.get(anchor['id'], {})
    source = Path(result.get('path') or '')
    if not source.is_file():
        anchor['status'] = 'generation-failed'
        continue
    image = Image.open(source).convert('RGBA')
    image.save(ROOT / 'raw' / (anchor['id'] + '.png'))
    factor = min(448 / image.width, 640 / image.height)
    size = (round(image.width * factor), round(image.height * factor))
    reduced = image.resize(size, Image.Resampling.LANCZOS)
    cell = Image.new('RGBA', (448, 640))
    cell.alpha_composite(reduced, ((448 - size[0]) // 2, (640 - size[1]) // 2))
    alpha = cell.getchannel('A')
    cell.paste((0, 0, 0, 0), mask=alpha.point(lambda value: 255 if value == 0 else 0))
    cell.save(ROOT / 'cells' / (anchor['id'] + '.png'))
    anchor.update(status='review-pending', src='cells/' + anchor['id'] + '.png')
    reports.append({'id': anchor['id'], 'source_size': image.size,
                    'canvas_scale': factor, 'cell_size': cell.size,
                    'alpha_bounds': alpha.getbbox(),
                    'original_face_registration': 'not checked',
                    'original_torso_registration': 'not checked',
                    'four_limbs': 'not checked'})
for theme, colour, text_colour in [('white', '#ffffff', '#654356'),
                                    ('dark', '#25232c', '#f4dfe8')]:
    board = Image.new('RGB', (4 * 250, 4 * 355), colour)
    draw = ImageDraw.Draw(board)
    for index, anchor in enumerate(manifest['anchors']):
        path = ROOT / 'cells' / (anchor['id'] + '.png')
        if not path.is_file():
            continue
        cell = Image.open(path).convert('RGBA').resize((224, 320), Image.Resampling.LANCZOS)
        x, y = (index % 4) * 250 + 13, (index // 4) * 355
        board.paste(cell, (x, y), cell)
        draw.text((x, y + 325), anchor['id'], fill=text_colour)
    board.save(ROOT / ('review-' + theme + '.jpg'), quality=95)
manifest['static_anchors_generated'] = len(reports)
manifest['motion_sequences_completed'] = 0
manifest['stage'] = 'static-review-pending'
(ROOT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
(ROOT / 'canvas-report.json').write_text(json.dumps(reports, indent=2))
print(json.dumps({'static_anchors_generated': len(reports),
                  'motion_sequences_completed': 0,
                  'registration_approved': False}))
