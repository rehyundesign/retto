"""Restore frozen head pixels over independently redrawn compact torso artwork."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageChops, ImageFilter
import json
import hashlib
import statistics

root = Path(__file__).resolve().parent
records = json.loads((root / 'size-repair-input-v1/registration-before-compact.json').read_text())['records']
previous = {r['id']: r for r in records}
settings = {'A04': (164, 44), 'A11': (177, 40), 'A12': (169, 31)}
neck_curves = {
    'A04': [(42,350),(58,376),(88,385),(126,392),(174,413),(205,395),(248,389),(280,368),(299,342)],
    'A11': [(0,365),(15,395),(53,405),(105,407),(159,425),(197,408),(237,399),(275,386),(297,350)],
    'A12': [(29,348),(50,373),(87,383),(120,395),(170,425),(218,405),(257,392),(279,369),(296,343)]
}
audit = []
for name, (eye_line, shift) in settings.items():
    frozen_path = root / 'size-repair-input-v1' / f'{name}.png'
    frozen = Image.open(frozen_path).convert('RGBA')
    assert hashlib.sha256(frozen_path.read_bytes()).hexdigest() == previous[name]['output_sha256']
    edited_path = root / 'anchors' / f'{name}-compact-body-edit-v1.png'
    edited = Image.open(edited_path).convert('RGBA')
    edited.thumbnail((448, 640), Image.Resampling.LANCZOS)
    body = Image.new('RGBA', (448, 640))
    body.alpha_composite(edited, ((448 - edited.width) // 2, (640 - edited.height) // 2))
    pixels = body.load()
    widths = []
    for y in range((eye_line + 8) * 2, (eye_line + 23) * 2):
        xs = [x for x in range(40, 330) if (lambda z: z[3] > 64 and z[0] >= z[1] >= z[2] + 2
               and z[0] - z[1] < 65 and z[1] - z[2] < 70)(pixels[x, y])]
        if len(xs) > 35:
            widths.append(xs[-1] - xs[0] + 1)
    scale = 228 / statistics.median(widths)
    bounds = body.getchannel('A').crop((90, 500, 285, 640)).point(lambda a: 255 if a > 96 else 0).getbbox()
    old_foot = 500 + bounds[3] - 1
    tx, ty = 174 - 174 * scale, 628 - old_foot * scale
    body = body.transform((448, 640), Image.Transform.AFFINE,
        (1 / scale, 0, -tx / scale, 0, 1 / scale, -ty / scale), Image.Resampling.BICUBIC)
    if name == 'A11':
        # Remove the redrawn head's right-hand fringe before restoring the
        # approved turned head; the tail begins below this head-only polygon.
        ImageDraw.Draw(body).polygon([(259,382),(294,383),(298,438),(267,442),(256,420)],
                                    fill=(0,0,0,0))
    # Head is translated as an intact RGBA patch, with no scaling or deformation.
    shifted = Image.new('RGBA', (448, 640))
    shifted.paste(frozen, (0, shift))
    curve = neck_curves[name]
    source_mask = Image.new('L', (448, 640))
    draw = ImageDraw.Draw(source_mask)
    draw.polygon([(curve[0][0], 0), (curve[-1][0], 0)] + list(reversed(curve)), fill=255)
    source_mask = source_mask.filter(ImageFilter.GaussianBlur(2))
    mask = Image.new('L', (448, 640))
    mask.paste(source_mask, (0, shift))
    result = Image.composite(shifted, body, mask)
    difference = ImageChops.difference(shifted, result)
    protected = mask.point(lambda a: 255 if a == 255 else 0)
    changed = sum(any(pixel) and keep == 255 for pixel, keep in
                  zip(difference.get_flattened_data(), protected.get_flattened_data()))
    assert changed == 0
    destination = root / 'anchors' / f'{name}-compact-body-locked-v1.png'
    result.save(destination)
    audit.append({'id': name, 'frozen_input': str(frozen_path.relative_to(root)),
        'frozen_input_sha256': hashlib.sha256(frozen_path.read_bytes()).hexdigest(),
        'independent_body_edit': str(edited_path.relative_to(root)),
        'head_translation_2x': [0, shift], 'changed_protected_head_pixels': 0,
        'blend': '2px feather following the head/neck contour; jacket, raised paw and tail excluded',
        'output': str(destination.relative_to(root)), 'body_scale': scale})
(root / 'compact-body-head-lock-audit-v1.json').write_text(json.dumps(audit, indent=2) + '\n')
print('Three independently redrawn compact bodies assembled; protected translated head RGBA pixels unchanged.')
