"""Constrain same-pose eye/ear/costume repairs to their allowed regions.

No new head/neck/body pose is constructed here. Existing complete-character
poses stay unchanged; new articulated wing drawings come from image_gen.
"""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent
V1 = ROOT.parent / 'idle-v1-20261105'
CROP = (0, 320, 1024, 1408)
SIZE = (544, 544)


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def iris_regions(im):
    # Blue-grey iris pixels distinguish eyes from the warm fur; then retain
    # generous eye-opening/lid margins for this explicitly requested repair.
    pixels = []
    for y in range(600, 855):
        for x in range(265, 705):
            r, g, b = im.getpixel((x, y))[:3]
            if g > r + 5 and b > r + 9 and b - r < 100 and b > 45:
                pixels.append((x, y))
    xs = sorted({x for x, _ in pixels})
    if len(xs) < 12:
        raise ValueError('Iris detection needs direct review')
    split = max(range(len(xs) - 1), key=lambda i: xs[i + 1] - xs[i])
    if xs[split + 1] - xs[split] < 12:
        raise ValueError('Cannot separate two irises')
    mid = (xs[split] + xs[split + 1]) / 2
    groups = [[p for p in pixels if p[0] < mid], [p for p in pixels if p[0] >= mid]]
    boxes = []
    for group in groups:
        boxes.append((min(x for x, y in group) - 16, min(y for x, y in group) - 15,
                      max(x for x, y in group) + 17, max(y for x, y in group) + 16))
    return boxes


def permitted_mask(target):
    mask = Image.new('L', target.size)
    d = ImageDraw.Draw(mask)
    # Cover the old feather fans as well as the new up/downstroke envelopes.
    d.rectangle((0, 420, 370, 1320), fill=255)
    d.rectangle((605, 420, 1023, 1320), fill=255)
    foreground = ImageChops.difference(target, Image.new('RGB', target.size, 'white')).convert('L')
    foreground = foreground.point(lambda v: 255 if v > 4 else 0)
    protected = Image.new('L', target.size)
    q = ImageDraw.Draw(protected)
    q.polygon([(265, 440), (470, 520), (680, 435), (705, 690),
               (665, 840), (690, 975), (710, 1230), (650, 1335),
               (280, 1335), (245, 1150), (265, 945), (245, 805), (235, 650)], fill=255)
    protected = ImageChops.multiply(protected, foreground)
    # Keep only the connected Tato silhouette, excluding detached old feathers.
    tato_shape = Image.new('L', target.size)
    td = ImageDraw.Draw(tato_shape)
    td.rectangle((20, 1000, 265, 1335), fill=255)
    td.ellipse((33, 970, 245, 1135), fill=255)
    td.polygon([(42, 1010), (46, 978), (67, 964), (96, 993)], fill=255)
    td.polygon([(96, 993), (108, 940), (130, 940), (153, 988)], fill=255)
    tato = ImageChops.multiply(tato_shape, foreground)
    if tato.getpixel((140, 1050)) == 255:
        ImageDraw.floodfill(tato, (140, 1050), 128, thresh=0)
        tato = tato.point(lambda v: 255 if v == 128 else 0)
    protected = ImageChops.lighter(protected, tato)
    coloured = Image.new('L', target.size)
    px = coloured.load()
    src = target.load()
    for y in range(850, 1336):
        for x in range(625, 1024):
            r, g, b = src[x, y]
            pink = x >= 690 and r > g + 14 and r > b + 3
            tail = y >= 960 and r < 220 and r > g + 8 and g > b + 5
            if pink or tail:
                px[x, y] = 255
    coloured = coloured.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    protected = ImageChops.lighter(protected, coloured)
    # Retain the rabbit's white winglets below the large wing envelope.
    details = Image.new('L', target.size)
    dd = ImageDraw.Draw(details)
    dd.rectangle((720, 1090, 780, 1170), fill=255)
    dd.rectangle((915, 1080, 975, 1175), fill=255)
    protected = ImageChops.lighter(protected, ImageChops.multiply(details, foreground))
    mask = ImageChops.subtract(mask, protected)
    # Same-pose ear contour repair: no head position/orientation change.
    ear = Image.new('L', target.size)
    ImageDraw.Draw(ear).polygon([(480, 550), (515, 470), (640, 425),
                                (705, 450), (690, 585), (650, 680),
                                (580, 700), (510, 640)], fill=255)
    mask = ImageChops.lighter(mask, ear)
    boxes = iris_regions(target)
    eyes = Image.new('L', target.size)
    e = ImageDraw.Draw(eyes)
    for box in boxes:
        e.ellipse(box, fill=255)
    mask = ImageChops.lighter(mask, eyes).filter(ImageFilter.GaussianBlur(1.0))
    pet_faces = Image.new('L', target.size)
    pf = ImageDraw.Draw(pet_faces)
    pf.ellipse((60, 1000, 225, 1105), fill=255)
    pf.ellipse((770, 980, 925, 1100), fill=255)
    mask = ImageChops.subtract(mask, pet_faces)
    return mask, boxes


def white_cutout(im):
    rgba = im.convert('RGBA')
    # Remove only connected flat inspection matte; do not recolour fur or eyes.
    for point in [(0, 0), (rgba.width - 1, 0), (0, rgba.height - 1), (rgba.width - 1, rgba.height - 1)]:
        if all(v > 248 for v in rgba.getpixel(point)[:3]):
            ImageDraw.floodfill(rgba, point, (0, 0, 0, 0), thresh=5)
    alpha = rgba.getchannel('A')
    width, height = rgba.size
    bits = bytearray(alpha.point(lambda v: 1 if v > 20 else 0).tobytes())
    debris = Image.new('L', rgba.size)
    dd = ImageDraw.Draw(debris)
    for seed in range(len(bits)):
        if bits[seed] != 1:
            continue
        bits[seed] = 0
        pending = [seed]
        component = []
        while pending:
            pos = pending.pop(); component.append(pos)
            x, y = pos % width, pos // width
            for next_pos in (pos-1 if x else -1, pos+1 if x+1 < width else -1,
                             pos-width if y else -1, pos+width if y+1 < height else -1):
                if next_pos >= 0 and bits[next_pos] == 1:
                    bits[next_pos] = 0; pending.append(next_pos)
        if len(component) < 96:
            for pos in component:
                dd.point((pos % width, pos // width), fill=255)
    alpha = ImageChops.subtract(alpha, debris.filter(ImageFilter.MaxFilter(3)))
    # Feather only the surviving outer matte edge; never blur facial/body art.
    alpha = ImageChops.darker(alpha, alpha.filter(ImageFilter.GaussianBlur(.4)))
    rgba.putalpha(alpha)
    return rgba


def main():
    missing = [f'{i:02}' for i in range(16)
               if not (ROOT / 'targets' / f'{i:02}.png').exists()
               or not (ROOT / 'generated' / f'{i:02}.png').exists()]
    if missing:
        raise ValueError('Repair drafts are incomplete: ' + ','.join(missing)
                         + '. Use render.py to reproduce the committed final cells.')
    prior = {r['id']: r for r in json.loads((V1 / 'sources.json').read_text())}
    records = []
    review = ROOT / 'review'
    for i in range(16):
        ident = f'{i:02}'
        donor_path = ROOT / 'generated' / f'{ident}.png'
        if not donor_path.exists():
            continue
        target = Image.open(ROOT / 'targets' / f'{ident}.png').convert('RGB')
        donor = Image.open(donor_path).convert('RGB')
        if target.size != donor.size or target.size != (1024, 1536):
            raise ValueError(f'{ident}: camera changed')
        mask, boxes = permitted_mask(target)
        repaired = Image.composite(donor, target, mask)
        diff = ImageChops.difference(target, repaired)
        delta = ImageChops.lighter(ImageChops.lighter(diff.getchannel('R'), diff.getchannel('G')), diff.getchannel('B'))
        outside = ImageChops.multiply(delta,
                                     ImageChops.invert(mask.point(lambda v: 255 if v else 0)))
        assert outside.getbbox() is None
        # Keep the original support registration, before any star/light effects.
        dy = prior[ident]['character_only_translation_raw'][1]
        registered = Image.new('RGB', target.size, 'white')
        registered.paste(repaired, (0, dy))
        crop = registered.crop(CROP).resize((512, 544), Image.Resampling.LANCZOS)
        # Fixed padding reserves wing-tip room without shrinking any character.
        cell = Image.new('RGB', SIZE, 'white')
        cell.paste(crop, (16, 0))
        cell = white_cutout(cell)
        dst = ROOT / 'character' / f'{ident}.png'
        cell.save(dst)
        mask.resize((512, 768)).save(review / f'mask-{ident}.png')
        records.append({'id': ident, 'path': f'character/{ident}.png', 'sha256': sha(dst),
                        'target_sha256': sha(ROOT / 'targets' / f'{ident}.png'),
                        'generated_sha256': sha(donor_path), 'eye_regions_raw': boxes,
                        'character_only_translation_raw': [0, dy],
                        'fixed_preview_padding_px': [16, 0, 16, 0],
                        'changed_outside_permitted_regions': 0})
    (ROOT / 'sources.json').write_text(json.dumps(records, indent=2) + '\n')
    if records:
        board = Image.new('RGB', (544 * 4, 568 * 4), '#262333')
        for record in records:
            i = int(record['id']); cell = Image.open(ROOT / record['path'])
            x, y = i % 4 * 544, i // 4 * 568
            board.paste(cell, (x, y + 24), cell)
            ImageDraw.Draw(board).text((x + 7, y + 5), record['id'], fill='white')
        board.save(review / 'character-dark-board.png')
    print(f'Prepared {len(records)} same-pose repairs; outside-mask changes:0')


if __name__ == '__main__':
    main()
