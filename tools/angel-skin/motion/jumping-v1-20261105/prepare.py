"""Prepare independent whole-character click-jump poses, without anatomical edits."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image, ImageDraw, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent
SCENE = (544, 544)
SIZE = (576, 544)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def foot_proxy(im):
    gray = im.convert('L')
    rows = []
    for y in range(435, 520):
        if sum(gray.getpixel((x, y)) < 240 for x in range(170, 355)) >= 8:
            rows.append(y)
    if not rows:
        raise ValueError('Supported forepaw proxy missing; inspect the complete pose')
    floor = max(rows)
    pixels = [(x, y) for y in range(floor-7, floor+1) for x in range(170, 355)
              if gray.getpixel((x, y)) < 240]
    left, right = min(x for x, y in pixels), max(x for x, y in pixels)
    return {'x': (left+right)/2, 'y': floor, 'width': right-left+1}


def significant_components(mask):
    width, height = mask.size
    bits = bytearray(mask.point(lambda v: 1 if v else 0).tobytes())
    keep = Image.new('L', mask.size)
    d = ImageDraw.Draw(keep)
    for seed in range(len(bits)):
        if not bits[seed]:
            continue
        bits[seed] = 0; todo = [seed]; component = []
        while todo:
            pos = todo.pop(); component.append(pos)
            x, y = pos % width, pos // width
            for nxt in (pos-1 if x else -1, pos+1 if x+1 < width else -1,
                        pos-width if y else -1, pos+width if y+1 < height else -1):
                if nxt >= 0 and bits[nxt]:
                    bits[nxt] = 0; todo.append(nxt)
        if len(component) >= 80:
            for pos in component:
                d.point((pos % width, pos // width), fill=255)
    return keep


def cutout(im):
    # Hysteresis matte: solid fur/feather forms support their faint edge detail,
    # while low-contrast white-background noise cannot become floating sprites.
    delta = ImageChops.difference(im, Image.new('RGB', im.size, 'white')).convert('L')
    # Tato's near-white crown is valid fur. A >10 threshold opens its contour
    # and lets exterior flood fill erase the forehead. Keep weak connected fur
    # detail while rejecting isolated noise; no body-region mask or repaint.
    strong = significant_components(delta.point(lambda v: 255 if v > 2 else 0))
    outside = strong.copy()
    ImageDraw.floodfill(outside, (0, 0), 128, thresh=0)
    solid = ImageChops.lighter(strong, outside.point(lambda v: 255 if v == 0 else 0))
    support = solid.filter(ImageFilter.MaxFilter(7))
    edge = ImageChops.multiply(delta.point(lambda v: min(255, v*32)), support)
    alpha = ImageChops.lighter(solid.filter(ImageFilter.MinFilter(3)), edge)
    alpha = ImageChops.darker(alpha, alpha.filter(ImageFilter.GaussianBlur(.35)))
    result = im.convert('RGBA'); result.putalpha(alpha)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--partial', action='store_true')
    args = parser.parse_args()
    paths = [ROOT/'raw'/f'{i:02}.png' for i in range(16)]
    if not args.partial and any(not p.exists() for p in paths):
        raise ValueError('Need all16 independent source drawings before final preparation')
    reference = Image.open(ROOT/'references/approved-idle-white.png').convert('RGB')
    reference = reference.resize(SCENE, Image.Resampling.LANCZOS)
    canonical = foot_proxy(reference)
    # Calibrate camera ONCE from neutral00. Per-pose foot alignment would
    # erase the authored jump and displace the grounded companions.
    if not paths[0].exists():
        raise ValueError('Need neutral00 for fixed-camera calibration')
    neutral = Image.open(paths[0]).convert('RGB').resize(SCENE, Image.Resampling.LANCZOS)
    origin = foot_proxy(neutral)
    dx = round(canonical['x']-origin['x'])
    dy = canonical['y']-origin['y']
    if abs(dx) > 28 or abs(dy) > 30:
        raise ValueError('Neutral camera drift exceeds existing preparation limit')
    records = []
    for i, path in enumerate(paths):
        if not path.exists():
            continue
        raw = Image.open(path).convert('RGB')
        if raw.width != raw.height:
            raise ValueError(f'{path}: square camera changed; redraw rather than stretching')
        frame = raw.resize(SCENE, Image.Resampling.LANCZOS)
        registered = Image.new('RGB', SCENE, 'white')
        registered.paste(frame, (dx, dy))
        padded = Image.new('RGB', SIZE, 'white'); padded.paste(registered, (16, 0))
        cell = cutout(padded)
        dest = ROOT/'character'/f'{i:02}.png'; cell.save(dest)
        records.append({'id':f'{i:02}', 'path':f'character/{i:02}.png', 'sha256':sha(dest),
                        'raw_sha256':sha(path), 'raw_size':list(raw.size),
                        'method':'independent whole-character drawing; fixed resolution conversion; same neutral-camera calibration for all poses, preserving drawn jump height',
                        'neutral_camera_support_proxy':origin, 'support_proxy_reference':canonical,
                        'registration_translation_scene_px':[dx,dy], 'per_pose_regrounding':False,
                        'fixed_preview_padding_px':[16,0,16,0],
                        'original_anatomical_landmarks':'unverified; foot proxies are not anatomical certification'})
    (ROOT/'sources.json').write_text(json.dumps(records,indent=2)+'\n')
    board = Image.new('RGB',(576*4,568*4),'#242937')
    small = Image.new('RGB',(288*4,292*4),'#fffaf2')
    for record in records:
        i = int(record['id']); cell = Image.open(ROOT/record['path'])
        x,y=i%4*576,i//4*568; board.paste(cell,(x,y+24),cell)
        ImageDraw.Draw(board).text((x+5,y+4),record['id'],fill='white')
        thumb=cell.resize((288,272),Image.Resampling.LANCZOS)
        x,y=i%4*288,i//4*292;small.paste(thumb,(x,y+20),thumb)
        ImageDraw.Draw(small).text((x+5,y+3),record['id'],fill='#302b21')
    board.save(ROOT/'review/character-dark-board.png')
    small.save(ROOT/'review/character-small-board.png')
    print(json.dumps({'prepared':len(records),'reference_proxy':canonical,
                      'rigid_translations':[r['registration_translation_scene_px'] for r in records]}))


if __name__ == '__main__':
    main()
