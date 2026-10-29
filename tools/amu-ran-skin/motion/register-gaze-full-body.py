"""Register independent complete seated gaze drawings against base Retto.

The only image operation is one uniform whole-source affine transform. No head
cutout, body master, neck bridge, static face patch, or regional deformation.
"""
from pathlib import Path
import hashlib
import json
import sys
from PIL import Image, ImageDraw
import numpy as np

ROOT = Path(__file__).resolve().parent


def contained(path):
    image = Image.open(path).convert('RGBA')
    image.thumbnail((448, 640), Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', (448, 640))
    canvas.alpha_composite(image, ((448-image.width)//2, (640-image.height)//2))
    return canvas


def feet(image):
    a = np.asarray(image)
    yy, xx = np.indices(a.shape[:2])
    r, g, b = [a[:, :, i].astype(float) for i in range(3)]
    # Measure the bare cream toes, excluding the brown tail to viewer-right.
    bottom = int(np.nonzero((a[:, :, 3] > 80) & (xx < 280))[0].max())
    mask = ((a[:, :, 3] > 128) & (yy > bottom-18) & (g > 145)
            & (r > 175) & (b > 120) & (r-g < 60) & (xx < 280))
    y, x = np.nonzero(mask)
    assert len(x) > 300, 'No readable grounded forepaws'
    return {'left': int(x.min()), 'right': int(x.max()),
            'center': float((x.min()+x.max())/2), 'baseline': bottom}


def fur_top(image):
    a = np.asarray(image)
    r, g, b = [a[:, :, i].astype(float) for i in range(3)]
    yy, xx = np.indices(a.shape[:2])
    mask = ((a[:, :, 3] > 100) & (r-g > -3) & (r-g < 65)
            & (g-b > 4) & (g > 90) & (yy < 500) & (xx < 350))
    return int(np.nonzero(mask)[0].min())


def register(costume):
    directory = ROOT / f'gaze-{costume}-v2'
    records = []
    for direction in range(16):
        source = directory / 'raw' / f'G{direction:02}.png'
        if not source.exists():
            continue
        original = ROOT.parent / 'gaze/reference' / f'base-{direction:02}.png'
        base, image = contained(original), contained(source)
        target, observed = feet(base), feet(image)
        scale = (target['baseline']-fur_top(base))/(observed['baseline']-fur_top(image))
        dx = target['center'] - observed['center']*scale
        dy = target['baseline'] - observed['baseline']*scale
        output = image.transform((448, 640), Image.Transform.AFFINE,
                                 (1/scale, 0, -dx/scale, 0, 1/scale, -dy/scale),
                                 Image.Resampling.BICUBIC)
        pixels = np.array(output)
        pixels[pixels[:, :, 3] == 0, :3] = 0
        output = Image.fromarray(pixels)
        output.save(directory / 'character' / f'G{direction:02}.png')
        measured = feet(output)
        records.append({'id': f'G{direction:02}', 'direction': direction,
                        'profile': f'original-seated-gaze-{direction}',
                        'original': str(original), 'source': str(source),
                        'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                        'base_feet': target, 'source_feet': observed,
                        'base_fur_top': fur_top(base), 'source_fur_top': fur_top(image),
                        'registration_basis': 'whole seated stature and foot center/baseline; headgear excluded',
                        'output_feet': measured, 'whole_character_scale': scale,
                        'whole_character_translation': [dx, dy],
                        'natural_outline_preserved': True, 'regional_face_trims': False,
                        'head_body_compositing': False, 'entire_cell_one_source': True,
                        'lower_body_pixel_lock': False,
                        'four_limbs': {'front_left': 'grounded in sleeve/cuff',
                                       'front_right': 'grounded in sleeve/cuff',
                                       'rear_left': 'behind front-left foreleg and rear hip skirt',
                                       'rear_right': 'grounded beside front-right foreleg; hip partly behind skirt'},
                        'visual_review': 'pending'})
    (directory / 'registration.json').write_text(json.dumps(records, indent=2)+'\n')
    for theme, background in [('light', '#fffdfa'), ('dark', '#23232d')]:
        board = Image.new('RGB', (960, 1408), background)
        draw = ImageDraw.Draw(board)
        for record in records:
            direction = record['direction']
            image = Image.open(directory / 'character' / f'G{direction:02}.png').convert('RGBA')
            image = image.resize((224, 320), Image.Resampling.LANCZOS)
            x, y = direction % 4 * 240, direction // 4 * 352
            board.paste(image, (x+8, y+25), image)
            draw.text((x+8, y+6), f'G{direction:02}', fill='gray')
        board.save(directory / f'directions-{theme}-1x.png')
    print(costume, len(records), 'complete-source cells registered')


if __name__ == '__main__':
    for costume in (sys.argv[1:] or ['school', 'heart']):
        register(costume)
